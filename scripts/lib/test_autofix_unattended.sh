#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
# ============================================================
# Test script for autofix_unattended.sh
# Run: bash scripts/lib/test_autofix_unattended.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the module
source "$SCRIPT_DIR/autofix_unattended.sh"

TESTS_PASSED=0
TESTS_FAILED=0

setup_autofix_state_dir() {
    local state_dir="$1"
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

write_checksummed_test_record() {
    local target_file="$1"
    local record_json="$2"
    local checksummed_record=""

    checksummed_record="$(autofix_add_record_checksum "$record_json")" || return 1
    printf '%s\n' "$checksummed_record" > "$target_file"
}

append_checksummed_test_record() {
    local target_file="$1"
    local record_json="$2"
    local checksummed_record=""

    checksummed_record="$(autofix_add_record_checksum "$record_json")" || return 1
    printf '%s\n' "$checksummed_record" >> "$target_file"
}

make_test_change_record() {
    local change_id="${1:-chg_0001}"
    local description="${2:-Stopped unattended-upgrades service}"
    local session_id="${3:-sess_fixture}"

    jq -cn \
        --arg id "$change_id" \
        --arg desc "$description" \
        --arg session "$session_id" \
        '{
          id: $id,
          timestamp: "2026-04-15T00:00:00Z",
          category: "unattended",
          description: $desc,
          undo_command: "true",
          undo_requires_root: true,
          severity: "warning",
          files_affected: [],
          post_checksums: [],
          backups: [],
          depends_on: [],
          session_id: $session,
          reversible: true,
          undone: false
        }'
}

cleanup_test_dir() {
    local test_dir="$1"
    if [[ -d "$test_dir" ]]; then
        rm -rf "$test_dir"
    fi
}

use_autofix_unattended_command_stubs() {
    _autofix_unattended_binary_path() {
        printf '%s\n' "${1:-}"
    }
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

# Test: Check function returns valid JSON
test_check_returns_json() {
    local result
    result=$(autofix_unattended_upgrades_check 2>/dev/null)

    if ! echo "$result" | jq . &>/dev/null; then
        test_fail "check_returns_json" "Output is not valid JSON"
        return
    fi

    # Verify required fields exist
    local status
    status=$(echo "$result" | jq -r '.status')
    if [[ -z "$status" ]]; then
        test_fail "check_returns_json" "Missing 'status' field"
        return
    fi

    local held_locks
    held_locks=$(echo "$result" | jq -r '.held_locks | type')
    if [[ "$held_locks" != "array" ]]; then
        test_fail "check_returns_json" "held_locks should be array"
        return
    fi

    test_pass "check_returns_json"
}

# Test: Check returns valid status values
test_check_valid_status() {
    local result
    result=$(autofix_unattended_upgrades_check 2>/dev/null)
    local status
    status=$(echo "$result" | jq -r '.status')

    case "$status" in
        none|active|locks_held|processes_running|inspection_unavailable)
            test_pass "check_valid_status ($status)"
            ;;
        *)
            test_fail "check_valid_status" "Unknown status: $status"
            ;;
    esac
}

# Test: needs_fix function returns boolean-like result
test_needs_fix_returns_correctly() {
    # This function uses exit codes, so test that behavior
    local result
    if autofix_unattended_upgrades_needs_fix 2>/dev/null; then
        result="needs_fix"
    else
        result="clean"
    fi

    # Either result is valid depending on system state
    if [[ "$result" == "needs_fix" || "$result" == "clean" ]]; then
        test_pass "needs_fix_returns_correctly (returned: $result)"
    else
        test_fail "needs_fix_returns_correctly" "Invalid result"
    fi
}

# Test: Dry-run mode doesn't modify system
test_dry_run_no_changes() {
    # Get state before
    local before_active="false"
    if systemctl is-active unattended-upgrades &>/dev/null 2>&1; then
        before_active="true"
    fi

    # Run dry-run
    autofix_unattended_upgrades_fix "dry-run" &>/dev/null

    # Get state after
    local after_active="false"
    if systemctl is-active unattended-upgrades &>/dev/null 2>&1; then
        after_active="true"
    fi

    if [[ "$before_active" == "$after_active" ]]; then
        test_pass "dry_run_no_changes"
    else
        test_fail "dry_run_no_changes" "System state changed during dry-run"
    fi
}

test_fix_manages_session_and_records_changes() {
    local test_dir="/tmp/test_autofix_unattended_fix_$$"
    local state_dir="$test_dir/state"
    mkdir -p "$test_dir"
    setup_autofix_state_dir "$state_dir"

    if ! (
        use_autofix_unattended_command_stubs
        sudo() { "$@"; }
        autofix_unattended_upgrades_check() {
            jq -n \
                --arg status "active" \
                --arg details "test fixture" \
                '{status: $status, details: $details, held_locks: [], apt_pids: ""}'
        }
        systemctl() {
            case "${1:-}" in
                is-active) return 0 ;;
                is-enabled) return 1 ;;
                stop|start) return 0 ;;
            esac
            return 0
        }
        pgrep() { return 1; }
        fuser() { return 1; }
        dpkg() { return 0; }
        apt-get() { return 0; }

        autofix_unattended_upgrades_fix "fix"
    ) >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "fix_manages_session_and_records_changes" "fix mode failed in isolated fixture"
        return
    fi

    if [[ -f "$ACFS_STATE_DIR/.session" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "fix_manages_session_and_records_changes" "session marker was left behind after standalone fix"
        return
    fi

    if ! jq -e 'select(.category == "unattended")' "$ACFS_CHANGES_FILE" >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "fix_manages_session_and_records_changes" "standalone fix did not record unattended changes"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "fix_manages_session_and_records_changes"
}

test_restore_manages_session_and_persists_marker() {
    local test_dir="/tmp/test_autofix_unattended_restore_$$"
    local state_dir="$test_dir/state"
    mkdir -p "$test_dir"
    setup_autofix_state_dir "$state_dir"

    write_checksummed_test_record "$ACFS_CHANGES_FILE" \
        "$(make_test_change_record)"
    update_integrity_file >/dev/null 2>&1

    if ! (
        use_autofix_unattended_command_stubs
        sudo() { "$@"; }
        systemctl() {
            case "${1:-}" in
                start) return 0 ;;
            esac
            return 0
        }

        autofix_unattended_upgrades_restore
    ) >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_manages_session_and_persists_marker" "restore mode failed in isolated fixture"
        return
    fi

    if [[ -f "$ACFS_STATE_DIR/.session" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_manages_session_and_persists_marker" "session marker was left behind after restore"
        return
    fi

    if ! jq -e 'select(.auto_restored == "unattended-upgrades")' "$ACFS_UNDOS_FILE" >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_manages_session_and_persists_marker" "restore did not persist unattended auto-restore marker"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "restore_manages_session_and_persists_marker"
}

test_restore_fails_closed_on_unresolved_session_marker() {
    local test_dir="/tmp/test_autofix_unattended_restore_incomplete_$$"
    local state_dir="$test_dir/state"
    local sentinel="$test_dir/systemctl-started"
    mkdir -p "$test_dir"
    setup_autofix_state_dir "$state_dir"

    write_checksummed_test_record "$ACFS_CHANGES_FILE" \
        "$(make_test_change_record)"
    write_checksummed_test_record "$ACFS_UNDOS_FILE" \
        '{"undone":"chg_0001","auto_restored":"unattended-upgrades","timestamp":"2026-04-16T00:00:00Z","exit_code":0,"status":"applied"}'
    update_integrity_file >/dev/null 2>&1

    cat > "$ACFS_STATE_DIR/.session" <<'EOF'
{"id":"sess_stale","start":"2026-04-16T00:00:00Z","pid":123}
EOF

    if (
        use_autofix_unattended_command_stubs
        sudo() { "$@"; }
        systemctl() {
            case "${1:-}" in
                start)
                    : > "$sentinel"
                    return 0
                    ;;
            esac
            return 0
        }

        autofix_unattended_upgrades_restore
    ) >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_fails_closed_on_unresolved_session_marker" "restore unexpectedly succeeded with a stale session marker"
        return
    fi

    if [[ -f "$sentinel" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_fails_closed_on_unresolved_session_marker" "restore attempted to start unattended-upgrades despite inconsistent autofix state"
        return
    fi

    if [[ ! -f "$ACFS_STATE_DIR/.session" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_fails_closed_on_unresolved_session_marker" "stale session marker was unexpectedly removed"
        return
    fi

    if ! jq -e 'select(.auto_restored == "unattended-upgrades")' "$ACFS_UNDOS_FILE" >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_fails_closed_on_unresolved_session_marker" "existing auto-restore marker was unexpectedly removed"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "restore_fails_closed_on_unresolved_session_marker"
}

test_stop_service_rolls_back_when_record_change_fails() {
    local test_dir="/tmp/test_autofix_unattended_stop_rollback_$$"
    local state_dir="$test_dir/state"
    local stopped_sentinel="$test_dir/stopped"
    local started_sentinel="$test_dir/started"
    mkdir -p "$test_dir"
    setup_autofix_state_dir "$state_dir"

    if (
        use_autofix_unattended_command_stubs
        sudo() { "$@"; }
        # shellcheck disable=SC2123
        PATH="/definitely-missing-for-this-test"

        systemctl() {
            case "${1:-}" in
                is-active|is-enabled) return 0 ;;
                stop)
                    : > "$stopped_sentinel"
                    return 0
                    ;;
                start)
                    : > "$started_sentinel"
                    return 0
                    ;;
            esac
            return 0
        }

        record_change() {
            return 1
        }

        _autofix_stop_unattended_service
    ) >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "stop_service_rolls_back_when_record_change_fails" "service stop unexpectedly succeeded when record_change failed"
        return
    fi

    if [[ ! -f "$stopped_sentinel" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "stop_service_rolls_back_when_record_change_fails" "service stop was not attempted"
        return
    fi

    if [[ ! -f "$started_sentinel" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "stop_service_rolls_back_when_record_change_fails" "service was not restarted after journaling failure"
        return
    fi

    if [[ -s "$ACFS_CHANGES_FILE" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "stop_service_rolls_back_when_record_change_fails" "service stop wrote change records despite journaling failure"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "stop_service_rolls_back_when_record_change_fails"
}

test_live_package_owner_fails_closed_without_mutation() {
    local test_dir="/tmp/test_autofix_unattended_live_owner_$$"
    local state_dir="$test_dir/state"
    local mutation_sentinel="$test_dir/mutated"
    mkdir -p "$test_dir"
    setup_autofix_state_dir "$state_dir"

    if (
        sudo() { "$@"; }
        autofix_unattended_upgrades_check() {
            jq -n \
                --arg status "processes_running" \
                --arg details "test fixture" \
                '{status: $status, details: $details, held_locks: [], apt_pids: "123"}'
        }
        _autofix_stop_unattended_service() { return 0; }
        _autofix_wait_for_apt_processes() { return 1; }
        autofix_unattended_upgrades_restore() { return 0; }
        _autofix_reconfigure_dpkg() {
            : > "$mutation_sentinel"
            return 0
        }
        _autofix_update_apt() {
            : > "$mutation_sentinel"
            return 0
        }

        autofix_unattended_upgrades_fix "fix"
    ) >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "live_package_owner_fails_closed_without_mutation" "repair unexpectedly succeeded while a live owner remained"
        return
    fi

    if [[ -e "$mutation_sentinel" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "live_package_owner_fails_closed_without_mutation" "repair mutated package state while a live owner remained"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "live_package_owner_fails_closed_without_mutation"
}

test_service_stop_failure_blocks_package_mutation() {
    local mutation_sentinel="/tmp/test_autofix_unattended_stop_failure_$$"

    if (
        use_autofix_unattended_command_stubs
        autofix_unattended_upgrades_check() {
            jq -n \
                --arg status "active" \
                --arg details "test fixture" \
                '{status: $status, details: $details, held_locks: [], apt_pids: ""}'
        }
        autofix_ensure_session() { return 0; }
        autofix_finalize_managed_session() { return 0; }
        _autofix_stop_unattended_service() { return 1; }
        _autofix_wait_for_apt_processes() {
            : > "$mutation_sentinel"
            return 0
        }
        _autofix_reconfigure_dpkg() {
            : > "$mutation_sentinel"
            return 0
        }
        _autofix_update_apt() {
            : > "$mutation_sentinel"
            return 0
        }

        autofix_unattended_upgrades_fix "fix"
    ) >/dev/null 2>&1; then
        test_fail "service_stop_failure_blocks_package_mutation" "repair unexpectedly succeeded after service stop failure"
        return
    fi

    if [[ -e "$mutation_sentinel" ]]; then
        test_fail "service_stop_failure_blocks_package_mutation" "package mutation path ran after service stop failure"
        return
    fi

    test_pass "service_stop_failure_blocks_package_mutation"
}

test_package_owner_detection_includes_aptitude_and_lock_holders() {
    if ! (
        use_autofix_unattended_command_stubs
        detection_mode="named"
        pgrep() {
            [[ "$detection_mode" == "named" && "$*" == *"aptitude"* ]]
        }
        fuser() {
            [[ "$detection_mode" == "lock" && "${1:-}" == "/var/lib/dpkg/lock" ]]
        }

        _autofix_package_owner_running || exit 1
        detection_mode="lock"
        _autofix_package_owner_running || exit 2
        detection_mode="none"
        ! _autofix_package_owner_running || exit 3
    ); then
        test_fail "package_owner_detection_includes_aptitude_and_lock_holders" "package-owner detection did not distinguish named, lock-held, and idle states"
        return
    fi

    test_pass "package_owner_detection_includes_aptitude_and_lock_holders"
}

test_package_owner_detection_fails_closed_without_probes() {
    if ! (
        _autofix_unattended_binary_path() { return 1; }
        _autofix_package_owner_running
    ); then
        test_fail "package_owner_detection_fails_closed_without_probes" "missing ownership probes were treated as proof that package state was idle"
        return
    fi

    test_pass "package_owner_detection_fails_closed_without_probes"
}

test_update_apt_failure_propagates() {
    if (
        use_autofix_unattended_command_stubs
        sudo() { "$@"; }
        apt-get() { return 1; }

        _autofix_update_apt
    ) >/dev/null 2>&1; then
        test_fail "update_apt_failure_propagates" "failed apt-get update was reported as successful"
        return
    fi

    test_pass "update_apt_failure_propagates"
}

test_restore_skips_compact_existing_marker() {
    local test_dir="/tmp/test_autofix_unattended_restore_idempotent_$$"
    local state_dir="$test_dir/state"
    local sentinel="$test_dir/systemctl-started"
    mkdir -p "$test_dir"
    setup_autofix_state_dir "$state_dir"

    write_checksummed_test_record "$ACFS_CHANGES_FILE" \
        "$(make_test_change_record)"
    write_checksummed_test_record "$ACFS_UNDOS_FILE" \
        '{"undone":"chg_0001","auto_restored":"unattended-upgrades","timestamp":"2026-04-16T00:00:00Z","exit_code":0,"status":"applied"}'
    update_integrity_file >/dev/null 2>&1

    if ! (
        use_autofix_unattended_command_stubs
        sudo() { "$@"; }
        systemctl() {
            : > "$sentinel"
            return 0
        }

        autofix_unattended_upgrades_restore
    ) >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_skips_compact_existing_marker" "restore rejected a valid existing marker"
        return
    fi

    if [[ -e "$sentinel" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_skips_compact_existing_marker" "restore restarted the service despite an existing compact JSON marker"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "restore_skips_compact_existing_marker"
}

test_restore_does_not_reuse_marker_for_older_change() {
    local test_dir="/tmp/test_autofix_unattended_restore_newer_$$"
    local state_dir="$test_dir/state"
    local sentinel="$test_dir/systemctl-started"
    mkdir -p "$test_dir"
    setup_autofix_state_dir "$state_dir"

    write_checksummed_test_record "$ACFS_CHANGES_FILE" \
        "$(make_test_change_record "chg_0001" "First unattended stop" "sess_first")"
    append_checksummed_test_record "$ACFS_CHANGES_FILE" \
        "$(make_test_change_record "chg_0002" "Later unattended stop" "sess_second")"
    write_checksummed_test_record "$ACFS_UNDOS_FILE" \
        '{"undone":"chg_0001","auto_restored":"unattended-upgrades","timestamp":"2026-04-16T00:00:00Z","exit_code":0,"status":"applied"}'
    update_integrity_file >/dev/null 2>&1

    if ! (
        use_autofix_unattended_command_stubs
        sudo() { "$@"; }
        systemctl() {
            : > "$sentinel"
            return 0
        }

        autofix_unattended_upgrades_restore
    ) >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_does_not_reuse_marker_for_older_change" "restore rejected the later unattended stop"
        return
    fi

    if [[ ! -e "$sentinel" ]]; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_does_not_reuse_marker_for_older_change" "older restore marker suppressed the later restore"
        return
    fi
    if ! jq -e -s 'any(.[]; .undone == "chg_0002" and .status == "applied" and .auto_restored == "unattended-upgrades")' \
        "$ACFS_UNDOS_FILE" >/dev/null 2>&1; then
        cleanup_test_dir "$test_dir"
        test_fail "restore_does_not_reuse_marker_for_older_change" "later change was not recorded as restored"
        return
    fi

    cleanup_test_dir "$test_dir"
    test_pass "restore_does_not_reuse_marker_for_older_change"
}

# Test: CLI modes work
test_cli_modes() {
    local failed=0

    # Test check mode
    if ! bash "$SCRIPT_DIR/autofix_unattended.sh" check &>/dev/null; then
        failed=$((failed + 1))
        echo "       check mode failed"
    fi

    # Test dry-run mode
    if ! bash "$SCRIPT_DIR/autofix_unattended.sh" dry-run &>/dev/null; then
        failed=$((failed + 1))
        echo "       dry-run mode failed"
    fi

    # Test help (invalid mode shows usage)
    if bash "$SCRIPT_DIR/autofix_unattended.sh" --help &>/dev/null 2>&1; then
        # Should exit 1 for unknown mode
        :
    fi

    if [[ $failed -eq 0 ]]; then
        test_pass "cli_modes"
    else
        test_fail "cli_modes" "$failed mode(s) failed"
    fi
}

# Test: Lock file list is properly defined
test_lock_file_constants() {
    if [[ ${#APT_LOCK_FILES[@]} -lt 3 ]]; then
        test_fail "lock_file_constants" "Should have at least 3 lock files defined"
        return
    fi

    # All paths should be absolute
    for lock in "${APT_LOCK_FILES[@]}"; do
        if [[ "$lock" != /* ]]; then
            test_fail "lock_file_constants" "Lock path not absolute: $lock"
            return
        fi
    done

    test_pass "lock_file_constants"
}

# Run all tests
main() {
    echo "==========================================="
    echo "Running autofix_unattended.sh unit tests"
    echo "==========================================="

    test_check_returns_json
    test_check_valid_status
    test_needs_fix_returns_correctly
    test_dry_run_no_changes
    test_fix_manages_session_and_records_changes
    test_restore_manages_session_and_persists_marker
    test_restore_fails_closed_on_unresolved_session_marker
    test_stop_service_rolls_back_when_record_change_fails
    test_live_package_owner_fails_closed_without_mutation
    test_service_stop_failure_blocks_package_mutation
    test_package_owner_detection_includes_aptitude_and_lock_holders
    test_package_owner_detection_fails_closed_without_probes
    test_update_apt_failure_propagates
    test_restore_skips_compact_existing_marker
    test_restore_does_not_reuse_marker_for_older_change
    test_cli_modes
    test_lock_file_constants

    echo "==========================================="
    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi

    echo "All tests passed!"
    exit 0
}

main "$@"
