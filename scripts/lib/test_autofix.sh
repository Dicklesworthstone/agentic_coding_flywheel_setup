#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2317
# ============================================================
# Test script for autofix.sh
# Run: bash scripts/lib/test_autofix.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the autofix module
source "$SCRIPT_DIR/autofix.sh"

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

make_test_change_record() {
    local change_id="${1:-chg_001}"
    local description="${2:-test change}"
    local record=""

    record="$(jq -cn \
        --arg id "$change_id" \
        --arg desc "$description" \
        '{
          id: $id,
          timestamp: "2026-04-15T00:00:00Z",
          category: "test",
          description: $desc,
          undo_command: "true",
          undo_requires_root: false,
          severity: "info",
          files_affected: [],
          post_checksums: [],
          backups: [],
          depends_on: [],
          session_id: "test_sess",
          reversible: true,
          undone: false
        }')" || return 1
    autofix_add_record_checksum "$record"
}

# Safe cleanup function - removes only specific test files
cleanup_test_files() {
    local test_id="$1"
    rm -f "/tmp/test_autofix_${test_id}_"* 2>/dev/null || true
    rmdir "/tmp/test_autofix_${test_id}" 2>/dev/null || true
}

# Test: Atomic write
test_atomic_write() {
    local test_id="atomic"
    local test_file="/tmp/test_autofix_${test_id}_file"
    local content="test content $(date)"
    
    write_atomic "$test_file" "$content"
    
    if [[ ! -f "$test_file" ]]; then
        test_fail "atomic_write" "File not created"
        return
    fi
    
    local read_content
    read_content=$(cat "$test_file")
    if [[ "$read_content" != "$content" ]]; then
        test_fail "atomic_write" "Content mismatch"
        rm -f "$test_file"
        return
    fi
    
    rm -f "$test_file"
    test_pass "atomic_write"
}

# Test: Atomic append
test_atomic_append() {
    local test_id="append"
    local test_file="/tmp/test_autofix_${test_id}_file"
    
    write_atomic "$test_file" "line1"
    append_atomic "$test_file" "line2"
    
    local line_count
    line_count=$(wc -l < "$test_file")
    if [[ "$line_count" -ne 2 ]]; then
        test_fail "atomic_append" "Expected 2 lines, got $line_count"
        rm -f "$test_file"
        return
    fi
    
    rm -f "$test_file"
    test_pass "atomic_append"
}

# Test: Record checksum determinism
test_record_checksum() {
    local record='{"id":"chg_001","description":"test"}'
    
    local checksum1
    checksum1=$(compute_record_checksum "$record")
    local checksum2
    checksum2=$(compute_record_checksum "$record")
    
    if [[ "$checksum1" != "$checksum2" ]]; then
        test_fail "record_checksum" "Checksums not deterministic"
        return
    fi
    
    if [[ ${#checksum1} -ne 64 ]]; then
        test_fail "record_checksum" "Invalid checksum length: ${#checksum1}"
        return
    fi
    
    # Different content should have different checksum
    local record2='{"id":"chg_002","description":"test"}'
    local checksum3
    checksum3=$(compute_record_checksum "$record2")
    
    if [[ "$checksum1" == "$checksum3" ]]; then
        test_fail "record_checksum" "Different records have same checksum"
        return
    fi
    
    test_pass "record_checksum"
}

# Test: State integrity verification - valid state
test_state_integrity_valid() {
    local test_id="integrity_valid"
    local test_dir="/tmp/test_autofix_${test_id}"
    mkdir -p "$test_dir"
    
    ACFS_STATE_DIR="$test_dir"
    ACFS_CHANGES_FILE="$test_dir/changes.jsonl"
    ACFS_UNDOS_FILE="$test_dir/undos.jsonl"
    ACFS_BACKUPS_DIR="$test_dir/backups"
    ACFS_LOCK_FILE="$test_dir/.lock"
    ACFS_INTEGRITY_FILE="$test_dir/.integrity"
    mkdir -p "$ACFS_BACKUPS_DIR"
    
    # Create valid records
    local record1 record2
    record1="$(make_test_change_record "chg_001" "test1")"
    record2="$(make_test_change_record "chg_002" "test2")"
    printf '%s\n' "$record1" > "$ACFS_CHANGES_FILE"
    printf '%s\n' "$record2" >> "$ACFS_CHANGES_FILE"
    touch "$ACFS_UNDOS_FILE"
    update_integrity_file >/dev/null 2>&1
    
    if ! verify_state_integrity 2>/dev/null; then
        test_fail "state_integrity_valid" "Valid state rejected"
        rm -f "$ACFS_CHANGES_FILE" "$ACFS_UNDOS_FILE" "$ACFS_INTEGRITY_FILE" "$ACFS_LOCK_FILE"
        rmdir "$ACFS_BACKUPS_DIR" 2>/dev/null || true
        rmdir "$test_dir" 2>/dev/null || true
        return
    fi
    
    rm -f "$ACFS_CHANGES_FILE" "$ACFS_UNDOS_FILE" "$ACFS_INTEGRITY_FILE" "$ACFS_LOCK_FILE"
    rmdir "$ACFS_BACKUPS_DIR" 2>/dev/null || true
    rmdir "$test_dir" 2>/dev/null || true
    test_pass "state_integrity_valid"
}

# Test: State integrity verification - invalid state
test_state_integrity_invalid() {
    local test_id="integrity_invalid"
    local test_dir="/tmp/test_autofix_${test_id}"
    mkdir -p "$test_dir"
    
    ACFS_STATE_DIR="$test_dir"
    ACFS_CHANGES_FILE="$test_dir/changes.jsonl"
    ACFS_UNDOS_FILE="$test_dir/undos.jsonl"
    ACFS_BACKUPS_DIR="$test_dir/backups"
    ACFS_LOCK_FILE="$test_dir/.lock"
    ACFS_INTEGRITY_FILE="$test_dir/.integrity"
    mkdir -p "$ACFS_BACKUPS_DIR"
    
    # Create invalid JSON
    echo 'not valid json' > "$ACFS_CHANGES_FILE"
    touch "$ACFS_UNDOS_FILE"
    update_integrity_file >/dev/null 2>&1
    
    if verify_state_integrity 2>/dev/null; then
        test_fail "state_integrity_invalid" "Invalid state accepted"
        rm -f "$ACFS_CHANGES_FILE" "$ACFS_UNDOS_FILE" "$ACFS_INTEGRITY_FILE" "$ACFS_LOCK_FILE"
        rmdir "$ACFS_BACKUPS_DIR" 2>/dev/null || true
        rmdir "$test_dir" 2>/dev/null || true
        return
    fi
    
    rm -f "$ACFS_CHANGES_FILE" "$ACFS_UNDOS_FILE" "$ACFS_INTEGRITY_FILE" "$ACFS_LOCK_FILE"
    rmdir "$ACFS_BACKUPS_DIR" 2>/dev/null || true
    rmdir "$test_dir" 2>/dev/null || true
    test_pass "state_integrity_invalid"
}

# Test: State repair
test_state_repair() {
    local test_id="repair"
    local test_dir="/tmp/test_autofix_${test_id}"
    mkdir -p "$test_dir"
    
    ACFS_STATE_DIR="$test_dir"
    ACFS_CHANGES_FILE="$test_dir/changes.jsonl"
    ACFS_UNDOS_FILE="$test_dir/undos.jsonl"
    ACFS_BACKUPS_DIR="$test_dir/backups"
    ACFS_LOCK_FILE="$test_dir/.lock"
    ACFS_INTEGRITY_FILE="$test_dir/.integrity"
    mkdir -p "$ACFS_BACKUPS_DIR"
    
    # Create mixed valid/invalid records
    local record1 record2
    record1="$(make_test_change_record "chg_001" "valid")"
    record2="$(make_test_change_record "chg_002" "also valid")"
    printf '%s\n' "$record1" > "$ACFS_CHANGES_FILE"
    printf '%s\n' 'invalid json line' >> "$ACFS_CHANGES_FILE"
    printf '%s\n' "$record2" >> "$ACFS_CHANGES_FILE"
    touch "$ACFS_UNDOS_FILE"
    
    repair_state_files 2>/dev/null
    
    # Should have only 2 valid lines now
    local valid_count
    valid_count=$(grep -c '^{' "$ACFS_CHANGES_FILE" || echo 0)
    if [[ "$valid_count" -ne 2 ]]; then
        test_fail "state_repair" "Expected 2 valid lines, got $valid_count"
        rm -f "$ACFS_CHANGES_FILE" "$ACFS_UNDOS_FILE" "$ACFS_INTEGRITY_FILE" "$ACFS_LOCK_FILE"
        rmdir "$ACFS_BACKUPS_DIR" 2>/dev/null || true
        rmdir "$test_dir" 2>/dev/null || true
        return
    fi
    
    rm -f "$ACFS_CHANGES_FILE" "$ACFS_UNDOS_FILE" "$ACFS_INTEGRITY_FILE" "$ACFS_LOCK_FILE"
    rmdir "$ACFS_BACKUPS_DIR" 2>/dev/null || true
    rmdir "$test_dir" 2>/dev/null || true
    test_pass "state_repair"
}

# Run all tests
main() {
    echo "=============================="
    echo "Running autofix.sh unit tests"
    echo "=============================="
    
    test_atomic_write
    test_atomic_append
    test_record_checksum
    test_state_integrity_valid
    test_state_integrity_invalid
    test_state_repair
    
    echo "=============================="
    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    
    echo "All tests passed!"
    exit 0
}

main "$@"
