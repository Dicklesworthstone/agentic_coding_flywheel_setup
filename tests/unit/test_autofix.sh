#!/usr/bin/env bash
# ============================================================
# Unit tests for scripts/lib/autofix.sh
#
# Run with: bash tests/unit/test_autofix.sh
# ============================================================

# Note: We use set -u but NOT set -e because:
# 1. ((var++)) returns 1 when var=0 which would exit with set -e
# 2. We want to continue running tests even if some fail
set -uo pipefail

# Get the absolute path to the scripts directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the autofix library
source "$REPO_ROOT/scripts/lib/autofix.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================
# Test Helpers
# ============================================================

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
}

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Running: $test_name..."
    if "$test_name"; then
        test_pass "$test_name"
    else
        test_fail "$test_name"
    fi
}

# Setup test environment
setup_test_env() {
    # Use unique directory for each test to avoid interference
    local test_id="${FUNCNAME[1]:-$$}_$(date +%s%N)"
    export ACFS_STATE_DIR="/tmp/test_autofix_${test_id}"
    export ACFS_CHANGES_FILE="$ACFS_STATE_DIR/changes.jsonl"
    export ACFS_UNDOS_FILE="$ACFS_STATE_DIR/undos.jsonl"
    export ACFS_BACKUPS_DIR="$ACFS_STATE_DIR/backups"
    export ACFS_LOCK_FILE="$ACFS_STATE_DIR/.lock"
    export ACFS_INTEGRITY_FILE="$ACFS_STATE_DIR/.integrity"

    # Reset in-memory state
    ACFS_CHANGE_RECORDS=()
    ACFS_CHANGE_ORDER=()
    ACFS_AUTOFIX_INITIALIZED=false

    # Clean start
    rm -rf "$ACFS_STATE_DIR"
    mkdir -p "$ACFS_STATE_DIR"
    mkdir -p "$ACFS_BACKUPS_DIR"

    # Create empty files
    : > "$ACFS_CHANGES_FILE"
    : > "$ACFS_UNDOS_FILE"
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "/tmp/test_autofix_"* 2>/dev/null || true
    rm -rf "/tmp/test_atomic_"* 2>/dev/null || true
    rm -rf "/tmp/test_backup_"* 2>/dev/null || true
    rm -rf "/tmp/test_fsync_"* 2>/dev/null || true
    rm -rf "/tmp/test_undo_"* 2>/dev/null || true
}

make_test_change_record() {
    local change_id="${1:-chg_001}"
    local description="${2:-test change}"
    local backups_json="${3:-[]}"
    local depends_on_json="${4:-[]}"
    local record=""

    record="$(jq -cn \
        --arg id "$change_id" \
        --arg desc "$description" \
        --argjson backups "$backups_json" \
        --argjson deps "$depends_on_json" \
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
          backups: $backups,
          depends_on: $deps,
          session_id: "test_sess",
          reversible: true,
          undone: false
        }')" || return 1
    autofix_add_record_checksum "$record"
}

# ============================================================
# Test Functions
# ============================================================

# Test: Atomic write
test_atomic_write() {
    local test_file="/tmp/test_atomic_$$"
    local content="test content $(date +%s)"

    write_atomic "$test_file" "$content"

    if [[ ! -f "$test_file" ]]; then
        echo "  File not created"
        rm -f "$test_file"
        return 1
    fi

    local actual_content
    actual_content=$(cat "$test_file")
    if [[ "$actual_content" != "$content" ]]; then
        echo "  Content mismatch: expected '$content', got '$actual_content'"
        rm -f "$test_file"
        return 1
    fi

    rm -f "$test_file"
    return 0
}

# Test: Atomic append
test_atomic_append() {
    local test_file="/tmp/test_atomic_append_$$"

    # First write
    write_atomic "$test_file" "line1"

    # Append
    append_atomic "$test_file" "line2"
    append_atomic "$test_file" "line3"

    local line_count
    line_count=$(wc -l < "$test_file")
    if [[ "$line_count" -ne 3 ]]; then
        echo "  Expected 3 lines, got $line_count"
        rm -f "$test_file"
        return 1
    fi

    local last_line
    last_line=$(tail -1 "$test_file")
    if [[ "$last_line" != "line3" ]]; then
        echo "  Last line mismatch: expected 'line3', got '$last_line'"
        rm -f "$test_file"
        return 1
    fi

    rm -f "$test_file"
    return 0
}

test_write_atomic_preserves_temp_through_fsync_functions() {
    local test_file="/tmp/test_atomic_fsync_write_$$"
    local original_fsync_file original_fsync_directory
    original_fsync_file="$(declare -f fsync_file)"
    original_fsync_directory="$(declare -f fsync_directory)"

    fsync_file() {
        return 0
    }
    fsync_directory() {
        return 0
    }

    if ! write_atomic "$test_file" "fsync function content"; then
        eval "$original_fsync_file"
        eval "$original_fsync_directory"
        echo "  write_atomic failed after shell-function fsync"
        rm -f "$test_file"
        return 1
    fi

    eval "$original_fsync_file"
    eval "$original_fsync_directory"

    if [[ "$(cat "$test_file" 2>/dev/null)" != "fsync function content" ]]; then
        echo "  write_atomic content missing after shell-function fsync"
        rm -f "$test_file"
        return 1
    fi

    rm -f "$test_file"
    return 0
}

test_append_atomic_preserves_temp_through_fsync_functions() {
    local test_file="/tmp/test_atomic_fsync_append_$$"
    local original_fsync_file original_fsync_directory
    original_fsync_file="$(declare -f fsync_file)"
    original_fsync_directory="$(declare -f fsync_directory)"

    printf '%s\n' "first" > "$test_file"

    fsync_file() {
        return 0
    }
    fsync_directory() {
        return 0
    }

    if ! append_atomic "$test_file" "second"; then
        eval "$original_fsync_file"
        eval "$original_fsync_directory"
        echo "  append_atomic failed after shell-function fsync"
        rm -f "$test_file"
        return 1
    fi

    eval "$original_fsync_file"
    eval "$original_fsync_directory"

    if [[ "$(tail -1 "$test_file" 2>/dev/null)" != "second" ]]; then
        echo "  append_atomic content missing after shell-function fsync"
        rm -f "$test_file"
        return 1
    fi

    rm -f "$test_file"
    return 0
}

# Test: Backup creation with checksum
test_backup_creation() {
    setup_test_env

    local test_file="/tmp/test_backup_orig_$$"
    echo "original content" > "$test_file"

    ACFS_SESSION_ID="test_sess"

    local backup_json
    backup_json=$(create_backup "$test_file" "test")

    if [[ -z "$backup_json" ]]; then
        echo "  No backup JSON returned"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    local backup_path
    backup_path=$(echo "$backup_json" | jq -r '.backup')
    if [[ ! -f "$backup_path" ]]; then
        echo "  Backup file not created: $backup_path"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    # Verify checksum
    if ! verify_backup_integrity "$backup_json"; then
        echo "  Integrity check failed"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    cleanup_test_env
    return 0
}

# Test: Backup paths stay unique across multiple backups in one session
test_backup_creation_uses_unique_paths_per_session() {
    setup_test_env

    local test_file="/tmp/test_backup_repeat_$$"
    printf 'first version\n' > "$test_file"

    ACFS_SESSION_ID="test_sess"

    local backup_json_1 backup_json_2 backup_path_1 backup_path_2
    backup_json_1=$(create_backup "$test_file" "test")
    backup_path_1=$(echo "$backup_json_1" | jq -r '.backup')

    printf 'second version\n' > "$test_file"
    backup_json_2=$(create_backup "$test_file" "test")
    backup_path_2=$(echo "$backup_json_2" | jq -r '.backup')

    if [[ "$backup_path_1" == "$backup_path_2" ]]; then
        echo "  Backup paths collided: $backup_path_1"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    if ! grep -qx 'first version' "$backup_path_1"; then
        echo "  First backup content was overwritten"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    if ! grep -qx 'second version' "$backup_path_2"; then
        echo "  Second backup content mismatch"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    cleanup_test_env
    return 0
}

# Test: Symlink backups preserve link type and fail integrity if rewritten as files
test_backup_creation_preserves_symlink_type() {
    setup_test_env

    local test_dir="/tmp/test_backup_symlink_${$}"
    local test_target="$test_dir/target"
    local test_link="$test_dir/link"
    mkdir -p "$test_dir"
    printf 'original target\n' > "$test_target"
    ln -s "$test_target" "$test_link"

    ACFS_SESSION_ID="test_sess"

    local backup_json backup_path backup_type
    backup_json=$(create_backup "$test_link" "test")
    backup_path=$(echo "$backup_json" | jq -r '.backup')
    backup_type=$(echo "$backup_json" | jq -r '.path_type')

    if [[ "$backup_type" != "symlink" ]]; then
        echo "  Backup path type mismatch: expected symlink, got $backup_type"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    if [[ ! -L "$backup_path" ]]; then
        echo "  Backup path is not a symlink: $backup_path"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    if ! verify_backup_integrity "$backup_json"; then
        echo "  Symlink backup integrity check failed"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    rm -f "$backup_path"
    printf 'not a symlink anymore\n' > "$backup_path"
    if verify_backup_integrity "$backup_json" >/dev/null 2>&1; then
        echo "  Symlink backup integrity accepted a rewritten regular file"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    rm -rf "$test_dir"
    cleanup_test_env
    return 0
}

# Test: Broken symlink backups are preserved and verified as symlinks
test_backup_creation_preserves_broken_symlink_type() {
    setup_test_env

    local test_dir="/tmp/test_backup_broken_symlink_${$}"
    local missing_target="$test_dir/missing-target"
    local test_link="$test_dir/link"
    mkdir -p "$test_dir"
    ln -s "$missing_target" "$test_link"

    ACFS_SESSION_ID="test_sess"

    local backup_json backup_path backup_type
    backup_json=$(create_backup "$test_link" "test")
    if [[ -z "$backup_json" ]]; then
        echo "  No backup JSON returned for broken symlink"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    backup_path=$(echo "$backup_json" | jq -r '.backup')
    backup_type=$(echo "$backup_json" | jq -r '.path_type')

    if [[ "$backup_type" != "symlink" ]]; then
        echo "  Broken symlink backup type mismatch: expected symlink, got $backup_type"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    if [[ ! -L "$backup_path" ]]; then
        echo "  Broken symlink backup path is not a symlink: $backup_path"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    if ! verify_backup_integrity "$backup_json"; then
        echo "  Broken symlink backup integrity check failed"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    rm -rf "$test_dir"
    cleanup_test_env
    return 0
}

# Test: Broken symlink backups fsync the backup parent directory, not a missing target
test_backup_creation_fsyncs_broken_symlink_parent_directory() {
    setup_test_env

    local test_dir="/tmp/test_backup_broken_symlink_fsync_${$}"
    local missing_target="$test_dir/missing-target"
    local test_link="$test_dir/link"
    local fsync_log="$ACFS_STATE_DIR/fsync.log"
    local original_fsync_file original_fsync_directory
    mkdir -p "$test_dir"
    ln -s "$missing_target" "$test_link"

    original_fsync_file="$(declare -f fsync_file)"
    original_fsync_directory="$(declare -f fsync_directory)"
    fsync_file() {
        printf 'file:%s\n' "$1" >> "$fsync_log"
        return 0
    }
    fsync_directory() {
        printf 'dir:%s\n' "$1" >> "$fsync_log"
        return 0
    }

    ACFS_SESSION_ID="test_sess"

    local backup_json backup_path backup_parent
    backup_json=$(create_backup "$test_link" "test")
    backup_path=$(echo "$backup_json" | jq -r '.backup')
    backup_parent=$(dirname "$backup_path")

    eval "$original_fsync_file"
    eval "$original_fsync_directory"

    if ! grep -Fx "dir:$backup_parent" "$fsync_log" >/dev/null 2>&1; then
        echo "  Broken symlink backup did not fsync parent dir: $backup_parent"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    if grep -Fx "file:$backup_path" "$fsync_log" >/dev/null 2>&1; then
        echo "  Broken symlink backup incorrectly fsynced the symlink as a file"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    rm -rf "$test_dir"
    cleanup_test_env
    return 0
}

# Test: Regular file backups fsync the backup file and parent directory
test_backup_creation_fsyncs_file_parent_directory() {
    setup_test_env

    local test_file="/tmp/test_backup_file_fsync_${$}"
    local fsync_log="$ACFS_STATE_DIR/fsync.log"
    local original_fsync_file original_fsync_directory
    printf 'content\n' > "$test_file"

    original_fsync_file="$(declare -f fsync_file)"
    original_fsync_directory="$(declare -f fsync_directory)"
    fsync_file() {
        printf 'file:%s\n' "$1" >> "$fsync_log"
        return 0
    }
    fsync_directory() {
        printf 'dir:%s\n' "$1" >> "$fsync_log"
        return 0
    }

    ACFS_SESSION_ID="test_sess"

    local backup_json backup_path backup_parent
    backup_json=$(create_backup "$test_file" "test")
    backup_path=$(echo "$backup_json" | jq -r '.backup')
    backup_parent=$(dirname "$backup_path")

    eval "$original_fsync_file"
    eval "$original_fsync_directory"

    if ! grep -Fx "file:$backup_path" "$fsync_log" >/dev/null 2>&1; then
        echo "  File backup did not fsync backup file: $backup_path"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    if ! grep -Fx "dir:$backup_parent" "$fsync_log" >/dev/null 2>&1; then
        echo "  File backup did not fsync backup parent dir: $backup_parent"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    cleanup_test_env
    return 0
}

# Test: Failed backup sync cleans up incomplete backup and fsyncs its parent directory
test_backup_creation_cleans_up_after_sync_failure() {
    setup_test_env

    local test_file="/tmp/test_backup_sync_fail_${$}"
    local fsync_log="$ACFS_STATE_DIR/fsync.log"
    local original_sync_helper original_fsync_directory
    printf 'content\n' > "$test_file"

    original_sync_helper="$(declare -f autofix_sync_backup_path)"
    original_fsync_directory="$(declare -f fsync_directory)"
    autofix_sync_backup_path() {
        return 1
    }
    fsync_directory() {
        printf 'dir:%s\n' "$1" >> "$fsync_log"
        return 0
    }

    ACFS_SESSION_ID="test_sess"

    local backup_result exit_code=0
    backup_result=$(create_backup "$test_file" "test" 2>/dev/null) || exit_code=$?

    eval "$original_sync_helper"
    eval "$original_fsync_directory"

    if [[ "$exit_code" -eq 0 ]]; then
        echo "  Backup unexpectedly succeeded: $backup_result"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    if find "$ACFS_BACKUPS_DIR" -mindepth 1 -print -quit | grep -q .; then
        echo "  Incomplete backup path was not cleaned up after sync failure"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    if ! grep -Fx "dir:$ACFS_BACKUPS_DIR" "$fsync_log" >/dev/null 2>&1; then
        echo "  Backup parent dir was not fsynced after sync-failure cleanup"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    cleanup_test_env
    return 0
}

# Test: Failed checksum computation cleans up incomplete backup artifacts
test_backup_creation_cleans_up_after_checksum_failure() {
    setup_test_env

    local test_file="/tmp/test_backup_checksum_fail_${$}"
    local original_checksum_helper
    printf 'content\n' > "$test_file"

    original_checksum_helper="$(declare -f calculate_backup_checksum)"
    calculate_backup_checksum() {
        if [[ "$1" == "$ACFS_BACKUPS_DIR/"* ]]; then
            return 1
        fi
        sha256sum "$1" | cut -d' ' -f1
    }

    ACFS_SESSION_ID="test_sess"

    local backup_result exit_code=0
    backup_result=$(create_backup "$test_file" "test" 2>/dev/null) || exit_code=$?

    eval "$original_checksum_helper"

    if [[ "$exit_code" -eq 0 ]]; then
        echo "  Backup unexpectedly succeeded: $backup_result"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    if find "$ACFS_BACKUPS_DIR" -mindepth 1 -print -quit | grep -q .; then
        echo "  Incomplete backup path was not cleaned up after checksum failure"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    cleanup_test_env
    return 0
}

test_directory_checksum_propagates_walker_failure() {
    setup_test_env

    local test_dir="/tmp/test_backup_checksum_walker_$$"
    local fake_python="/tmp/test_backup_checksum_python_$$"
    mkdir -p "$test_dir"
    printf 'content\n' > "$test_dir/file.txt"
    cat > "$fake_python" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
    chmod +x "$fake_python"

    if (
        autofix_system_binary_path() {
            if [[ "${1:-}" == "python3" ]]; then
                printf '%s\n' "$fake_python"
                return 0
            fi
            return 1
        }
        calculate_backup_checksum "$test_dir"
    ) >/dev/null 2>&1; then
        echo "  Directory checksum hid a walker/read failure"
        rm -f "$fake_python"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    rm -f "$fake_python"
    rm -rf "$test_dir"
    cleanup_test_env
    return 0
}

test_directory_checksum_tracks_symlink_targets_and_empty_directories() {
    setup_test_env

    local test_dir="/tmp/test_backup_checksum_shape_$$"
    mkdir -p "$test_dir/empty"
    ln -s "first-target" "$test_dir/link"

    local first_checksum=""
    local second_checksum=""
    local third_checksum=""
    first_checksum="$(calculate_backup_checksum "$test_dir")" || {
        echo "  Failed to checksum directory fixture"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    }

    rm -f "$test_dir/link"
    ln -s "second-target" "$test_dir/link"
    second_checksum="$(calculate_backup_checksum "$test_dir")" || true
    mkdir -p "$test_dir/second-empty"
    third_checksum="$(calculate_backup_checksum "$test_dir")" || true

    if [[ -z "$second_checksum" || -z "$third_checksum" || \
          "$first_checksum" == "$second_checksum" || "$second_checksum" == "$third_checksum" ]]; then
        echo "  Directory checksum did not cover symlink targets and empty-directory structure"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    rm -rf "$test_dir"
    cleanup_test_env
    return 0
}

# Test: Failed backup copy cleans up partial backup artifacts and fsyncs the backup parent
test_backup_creation_cleans_up_after_copy_failure() {
    setup_test_env

    local test_file="/tmp/test_backup_copy_fail_${$}"
    local fsync_log="$ACFS_STATE_DIR/fsync.log"
    local original_autofix_copy_backup_path original_fsync_directory
    printf 'content\n' > "$test_file"

    original_autofix_copy_backup_path="$(declare -f autofix_copy_backup_path)"
    original_fsync_directory="$(declare -f fsync_directory)"
    autofix_copy_backup_path() {
        local backup_path="$3"
        : > "$backup_path"
        return 1
    }
    fsync_directory() {
        printf 'dir:%s\n' "$1" >> "$fsync_log"
        return 0
    }

    ACFS_SESSION_ID="test_sess"

    local backup_result exit_code=0
    backup_result=$(create_backup "$test_file" "test" 2>/dev/null) || exit_code=$?

    eval "$original_autofix_copy_backup_path"
    eval "$original_fsync_directory"

    if [[ "$exit_code" -eq 0 ]]; then
        echo "  Backup unexpectedly succeeded: $backup_result"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    if find "$ACFS_BACKUPS_DIR" -mindepth 1 -print -quit | grep -q .; then
        echo "  Incomplete backup path was not cleaned up after copy failure"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    if ! grep -Fx "dir:$ACFS_BACKUPS_DIR" "$fsync_log" >/dev/null 2>&1; then
        echo "  Backup parent dir was not fsynced after copy-failure cleanup"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    cleanup_test_env
    return 0
}

# Test: State integrity accepts active broken symlink backups
test_state_integrity_accepts_broken_symlink_backup() {
    setup_test_env

    local test_dir="/tmp/test_state_broken_symlink_${$}"
    local missing_target="$test_dir/missing-target"
    local test_link="$test_dir/link"
    mkdir -p "$test_dir"
    ln -s "$missing_target" "$test_link"

    ACFS_SESSION_ID="test_sess"

    local backup_json record
    backup_json=$(create_backup "$test_link" "test")
    record="$(make_test_change_record "chg_001" "broken symlink backup" "[$backup_json]")"
    printf '%s\n' "$record" > "$ACFS_CHANGES_FILE"
    update_integrity_file >/dev/null 2>&1

    if ! verify_state_integrity >/dev/null 2>&1; then
        echo "  Broken symlink backup was rejected by state integrity"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    rm -rf "$test_dir"
    cleanup_test_env
    return 0
}

# Test: State integrity detects path-type drift for symlink backups
test_state_integrity_detects_type_drifted_symlink_backup() {
    setup_test_env

    local test_dir="/tmp/test_state_type_drift_symlink_${$}"
    local missing_target="$test_dir/missing-target"
    local test_link="$test_dir/link"
    mkdir -p "$test_dir"
    ln -s "$missing_target" "$test_link"

    ACFS_SESSION_ID="test_sess"

    local backup_json backup_path record
    backup_json=$(create_backup "$test_link" "test")
    backup_path=$(echo "$backup_json" | jq -r '.backup')

    record="$(make_test_change_record "chg_001" "drifted symlink backup" "[$backup_json]")"
    printf '%s\n' "$record" > "$ACFS_CHANGES_FILE"
    update_integrity_file >/dev/null 2>&1
    rm -f "$backup_path"
    printf 'symlink:%s' "$missing_target" > "$backup_path"

    if verify_state_integrity >/dev/null 2>&1; then
        echo "  Type-drifted symlink backup passed integrity verification"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    rm -rf "$test_dir"
    cleanup_test_env
    return 0
}

# Test: Directory backup corruption is detected by integrity verification
test_state_integrity_detects_corrupt_directory_backup() {
    setup_test_env

    local test_dir="/tmp/test_backup_dir_$$"
    mkdir -p "$test_dir"
    printf 'original\n' > "$test_dir/file.txt"

    ACFS_SESSION_ID="test_sess"

    local backup_json backup_path record
    backup_json=$(create_backup "$test_dir" "test")
    backup_path=$(echo "$backup_json" | jq -r '.backup')

    record="$(make_test_change_record "chg_001" "dir backup" "[$backup_json]")"
    printf '%s\n' "$record" > "$ACFS_CHANGES_FILE"
    update_integrity_file >/dev/null 2>&1
    printf 'corrupted\n' > "$backup_path/file.txt"

    if verify_state_integrity >/dev/null 2>&1; then
        echo "  Corrupt directory backup was accepted"
        rm -rf "$test_dir"
        cleanup_test_env
        return 1
    fi

    rm -rf "$test_dir"
    cleanup_test_env
    return 0
}

# Test: Missing backups for undone changes do not fail integrity verification
test_state_integrity_ignores_missing_backup_for_undone_change() {
    setup_test_env

    local test_file="/tmp/test_backup_undone_$$"
    printf 'original\n' > "$test_file"

    ACFS_SESSION_ID="test_sess"

    local backup_json backup_path record undo_record
    backup_json=$(create_backup "$test_file" "test")
    backup_path=$(echo "$backup_json" | jq -r '.backup')

    record="$(make_test_change_record "chg_001" "undone backup" "[$backup_json]")"
    undo_record='{"undone":"chg_001","timestamp":"2026-04-15T00:00:00Z","exit_code":0,"status":"applied"}'
    undo_record="$(autofix_add_record_checksum "$undo_record")"
    printf '%s\n' "$record" > "$ACFS_CHANGES_FILE"
    printf '%s\n' "$undo_record" > "$ACFS_UNDOS_FILE"
    rm -f "$backup_path"
    update_integrity_file >/dev/null 2>&1

    if ! verify_state_integrity >/dev/null 2>&1; then
        echo "  Missing backup for undone change should not fail integrity"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    cleanup_test_env
    return 0
}

# Test: Integrity verification checks every active backup, not just one
test_state_integrity_checks_all_active_backups() {
    setup_test_env

    local file_a="/tmp/test_backup_multi_a_$$"
    local file_b="/tmp/test_backup_multi_b_$$"
    printf 'alpha\n' > "$file_a"
    printf 'beta\n' > "$file_b"

    ACFS_SESSION_ID="test_sess"

    local backup_json_a backup_json_b backup_path_b record
    backup_json_a=$(create_backup "$file_a" "test")
    backup_json_b=$(create_backup "$file_b" "test")
    backup_path_b=$(echo "$backup_json_b" | jq -r '.backup')

    record="$(make_test_change_record "chg_001" "multi backup" "[$backup_json_a,$backup_json_b]")"
    printf '%s\n' "$record" > "$ACFS_CHANGES_FILE"
    update_integrity_file >/dev/null 2>&1
    printf 'corrupted\n' > "$backup_path_b"

    if verify_state_integrity >/dev/null 2>&1; then
        echo "  Corruption in second active backup was not detected"
        rm -f "$file_a" "$file_b"
        cleanup_test_env
        return 1
    fi

    rm -f "$file_a" "$file_b"
    cleanup_test_env
    return 0
}

# Test: Backup of non-existent file
test_backup_nonexistent_file() {
    setup_test_env
    ACFS_SESSION_ID="test_sess"

    local backup_json
    backup_json=$(create_backup "/tmp/this_file_does_not_exist_$$" "test")

    if [[ -n "$backup_json" ]]; then
        echo "  Expected empty result for non-existent file"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_backup_restore_command_rejects_unsafe_metadata() {
    setup_test_env
    ACFS_SESSION_ID="test_sess"

    local original_file="/tmp/test_restore_metadata_$$"
    local backup_json=""
    local restore_command=""
    printf 'original\n' > "$original_file"
    backup_json="$(create_backup "$original_file" "restore-metadata")"

    restore_command="$(autofix_backup_restore_command "$backup_json" 2>/dev/null || true)"
    if [[ -z "$restore_command" ]]; then
        echo "  Valid backup metadata did not produce a restore command"
        rm -f "$original_file"
        cleanup_test_env
        return 1
    fi

    local unsafe_json=""
    unsafe_json="$(printf '%s' "$backup_json" | jq -c '.original = "/"')"
    if autofix_backup_restore_command "$unsafe_json" >/dev/null 2>&1; then
        echo "  Restore command accepted the filesystem root as its target"
        rm -f "$original_file"
        cleanup_test_env
        return 1
    fi

    unsafe_json="$(printf '%s' "$backup_json" | jq -c '.original = "/tmp/.."')"
    if autofix_backup_restore_command "$unsafe_json" >/dev/null 2>&1; then
        echo "  Restore command accepted a root alias containing a parent segment"
        rm -f "$original_file"
        cleanup_test_env
        return 1
    fi

    unsafe_json="$(printf '%s' "$backup_json" | jq -c --arg dir "$ACFS_BACKUPS_DIR" '.original = ($dir | split("/backups")[0])')"
    if autofix_backup_restore_command "$unsafe_json" >/dev/null 2>&1; then
        echo "  Restore command accepted an ancestor of the backup store as its target"
        rm -f "$original_file"
        cleanup_test_env
        return 1
    fi

    unsafe_json="$(printf '%s' "$backup_json" | jq -c --arg path "$original_file" '.backup = $path')"
    if autofix_backup_restore_command "$unsafe_json" >/dev/null 2>&1; then
        echo "  Restore command accepted a backup outside the owned backup store"
        rm -f "$original_file"
        cleanup_test_env
        return 1
    fi

    if create_backup "$ACFS_STATE_DIR" "recursive-state" >/dev/null 2>&1; then
        echo "  Backup creation accepted an ancestor of its own backup store"
        rm -f "$original_file"
        cleanup_test_env
        return 1
    fi

    local external_file="/tmp/test_external_backup_cleanup_$$"
    printf 'preserve\n' > "$external_file"
    if autofix_cleanup_failed_backup_path "$external_file" >/dev/null 2>&1; then
        echo "  Failed-backup cleanup accepted a path outside the backup store"
        rm -f "$original_file" "$external_file"
        cleanup_test_env
        return 1
    fi
    if [[ "$(cat "$external_file")" != "preserve" ]]; then
        echo "  Failed-backup cleanup modified an external path"
        rm -f "$original_file" "$external_file"
        cleanup_test_env
        return 1
    fi

    rm -f "$original_file" "$external_file"
    cleanup_test_env
    return 0
}

# Test: Record checksum computation
test_record_checksum() {
    local record='{"id":"chg_001","description":"test"}'

    local checksum1 checksum2
    checksum1=$(compute_record_checksum "$record")
    checksum2=$(compute_record_checksum "$record")

    if [[ "$checksum1" != "$checksum2" ]]; then
        echo "  Checksums not deterministic: $checksum1 vs $checksum2"
        return 1
    fi

    if [[ ${#checksum1} -ne 64 ]]; then
        echo "  Invalid checksum length: ${#checksum1} (expected 64)"
        return 1
    fi

    # Different content should have different checksum
    local record2='{"id":"chg_002","description":"test"}'
    local checksum3
    checksum3=$(compute_record_checksum "$record2")

    if [[ "$checksum1" == "$checksum3" ]]; then
        echo "  Different records have same checksum"
        return 1
    fi

    return 0
}

# Test: State integrity verification
test_state_integrity() {
    setup_test_env

    # Create valid records
    local record1 record2
    record1="$(make_test_change_record "chg_001" "test1")"
    record2="$(make_test_change_record "chg_002" "test2")"
    printf '%s\n' "$record1" > "$ACFS_CHANGES_FILE"
    printf '%s\n' "$record2" >> "$ACFS_CHANGES_FILE"
    update_integrity_file >/dev/null 2>&1

    if ! verify_state_integrity 2>/dev/null; then
        echo "  Valid state rejected"
        cleanup_test_env
        return 1
    fi

    # Add invalid JSON
    echo 'not valid json' >> "$ACFS_CHANGES_FILE"

    if verify_state_integrity 2>/dev/null; then
        echo "  Invalid state accepted"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# Test: State repair
test_state_repair() {
    setup_test_env

    # Create file with mix of valid and invalid lines
    local record1 record2
    record1="$(make_test_change_record "chg_001" "test1")"
    record2="$(make_test_change_record "chg_002" "test2")"
    printf '%s\n' "$record1" > "$ACFS_CHANGES_FILE"
    printf '%s\n' 'invalid json line' >> "$ACFS_CHANGES_FILE"
    printf '%s\n' "$record2" >> "$ACFS_CHANGES_FILE"

    # Repair should succeed
    repair_state_files 2>/dev/null

    # Now verification should pass
    if ! verify_state_integrity 2>/dev/null; then
        echo "  State repair did not fix issues"
        cleanup_test_env
        return 1
    fi

    # Should have exactly 2 lines
    local line_count
    line_count=$(wc -l < "$ACFS_CHANGES_FILE")
    if [[ "$line_count" -ne 2 ]]; then
        echo "  Expected 2 lines after repair, got $line_count"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_state_integrity_rejects_missing_record_checksum() {
    setup_test_env

    printf '%s\n' '{"id":"chg_001","description":"untrusted"}' > "$ACFS_CHANGES_FILE"
    update_integrity_file >/dev/null 2>&1
    if verify_state_integrity >/dev/null 2>&1; then
        echo "  Integrity verification accepted a change record without a checksum"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_state_integrity_rejects_checksummed_malformed_change_schema() {
    setup_test_env

    local record=""
    record="$(make_test_change_record "chg_001" "malformed inventory")"
    record="$(printf '%s' "$record" | jq -c 'del(.record_checksum) | .backups = "not-an-array"')"
    record="$(autofix_add_record_checksum "$record")"
    printf '%s\n' "$record" > "$ACFS_CHANGES_FILE"
    update_integrity_file >/dev/null 2>&1

    if verify_state_integrity >/dev/null 2>&1; then
        echo "  Integrity verification accepted checksummed malformed change metadata"
        cleanup_test_env
        return 1
    fi
    if repair_state_files >/dev/null 2>&1; then
        echo "  State repair falsely blessed unrecoverable semantic journal corruption"
        cleanup_test_env
        return 1
    fi
    if ! grep -Fqx "$record" "$ACFS_CHANGES_FILE"; then
        echo "  State repair discarded the malformed record instead of failing closed"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_state_integrity_rejects_checksummed_malformed_undo_schema() {
    setup_test_env

    local change_record=""
    local undo_record=""
    change_record="$(make_test_change_record "chg_001" "malformed undo state")"
    undo_record='{"undone":"chg_001","timestamp":"2026-04-15T00:00:00Z","status":"unknown"}'
    undo_record="$(autofix_add_record_checksum "$undo_record")"
    printf '%s\n' "$change_record" > "$ACFS_CHANGES_FILE"
    printf '%s\n' "$undo_record" > "$ACFS_UNDOS_FILE"
    update_integrity_file >/dev/null 2>&1

    if verify_state_integrity >/dev/null 2>&1; then
        echo "  Integrity verification accepted a checksummed unknown undo status"
        cleanup_test_env
        return 1
    fi
    if autofix_change_undo_status "chg_001" >/dev/null 2>&1; then
        echo "  Undo status reader coerced malformed journal state into an actionable status"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_state_integrity_rejects_duplicate_change_ids() {
    setup_test_env

    local record1=""
    local record2=""
    record1="$(make_test_change_record "chg_001" "first record")"
    record2="$(make_test_change_record "chg_001" "duplicate record")"
    printf '%s\n%s\n' "$record1" "$record2" > "$ACFS_CHANGES_FILE"
    update_integrity_file >/dev/null 2>&1

    if verify_state_integrity >/dev/null 2>&1; then
        echo "  Integrity verification accepted ambiguous duplicate change IDs"
        cleanup_test_env
        return 1
    fi
    if autofix_active_backup_paths >/dev/null 2>&1; then
        echo "  Active-backup inventory accepted ambiguous duplicate change IDs"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_state_repair_reconciles_checkpoint_without_losing_valid_records() {
    setup_test_env

    if ! update_integrity_file >/dev/null 2>&1; then
        echo "  Failed to create baseline integrity checkpoint"
        cleanup_test_env
        return 1
    fi

    local record
    record="$(make_test_change_record "chg_001" "valid after checkpoint")"
    printf '%s\n' "$record" >> "$ACFS_CHANGES_FILE"

    if verify_state_integrity >/dev/null 2>&1; then
        echo "  Journal drift was not detected against the integrity checkpoint"
        cleanup_test_env
        return 1
    fi
    if ! repair_state_files >/dev/null 2>&1 || ! verify_state_integrity >/dev/null 2>&1; then
        echo "  State repair did not reconcile a valid checksummed journal"
        cleanup_test_env
        return 1
    fi
    if ! grep -Fqx "$record" "$ACFS_CHANGES_FILE"; then
        echo "  State repair lost the valid record while reconciling the checkpoint"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_state_repair_replaces_malformed_checkpoint() {
    setup_test_env

    printf '%s\n' '{"backup_file_count":"not-a-number"}' > "$ACFS_INTEGRITY_FILE"
    if verify_state_integrity >/dev/null 2>&1; then
        echo "  Malformed integrity checkpoint was accepted"
        cleanup_test_env
        return 1
    fi
    if ! repair_state_files >/dev/null 2>&1 || ! verify_state_integrity >/dev/null 2>&1; then
        echo "  State repair did not replace a malformed integrity checkpoint"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_state_repair_preserves_all_valid_checksummed_records() {
    setup_test_env

    local record1 record2 line_count
    record1="$(make_test_change_record "chg_001" "test1")"

    record2="$(make_test_change_record "chg_002" "test2")"

    printf '%s\n' "$record1" > "$ACFS_CHANGES_FILE"
    printf '%s\n' 'invalid json line' >> "$ACFS_CHANGES_FILE"
    printf '%s\n' "$record2" >> "$ACFS_CHANGES_FILE"

    if ! repair_state_files 2>/dev/null; then
        echo "  State repair failed for valid checksummed records"
        cleanup_test_env
        return 1
    fi

    line_count=$(wc -l < "$ACFS_CHANGES_FILE")
    if [[ "$line_count" -ne 2 ]]; then
        echo "  Expected 2 checksummed records after repair, got $line_count"
        cleanup_test_env
        return 1
    fi

    if ! grep -F "$record1" "$ACFS_CHANGES_FILE" >/dev/null || ! grep -F "$record2" "$ACFS_CHANGES_FILE" >/dev/null; then
        echo "  State repair lost a valid checksummed record"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# Test: State repair fails if repaired journal cannot replace changes file
test_state_repair_fails_when_changes_rewrite_cannot_replace_file() {
    setup_test_env

    echo 'invalid json line' > "$ACFS_CHANGES_FILE"

    mv() {
        local last="${!#}"
        if [[ "$last" == "$ACFS_CHANGES_FILE" ]]; then
            return 1
        fi
        command mv "$@"
    }

    if repair_state_files >/dev/null 2>&1; then
        echo "  repair_state_files unexpectedly succeeded when changes rewrite could not replace the file"
        unset -f mv
        cleanup_test_env
        return 1
    fi

    unset -f mv

    if ! grep -qx 'invalid json line' "$ACFS_CHANGES_FILE"; then
        echo "  Original corrupt changes journal was not preserved after failed repair"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_autofix_globals_are_initialized_under_set_u() {
    local output=""

    if ! output="$(bash -c '
        set -u
        source "$1"
        printf "records=%s order=%s\n" "${#ACFS_CHANGE_RECORDS[@]}" "${#ACFS_CHANGE_ORDER[@]}"
    ' _ "$REPO_ROOT/scripts/lib/autofix.sh" 2>&1)"; then
        echo "  Sourcing autofix.sh under set -u failed: $output"
        return 1
    fi

    if [[ "$output" != "records=0 order=0" ]]; then
        echo "  Expected empty initialized globals under set -u, got: $output"
        return 1
    fi

    return 0
}


test_autofix_refresh_state_paths_falls_back_to_tmp_when_runtime_home_unresolved() {
    local output=""
    local expected=""

    if ! output="$(bash -c '
        source "$1"
        autofix_resolve_current_user() { return 1; }
        autofix_home_for_user() { return 1; }
        unset ACFS_STATE_DIR ACFS_CHANGES_FILE ACFS_UNDOS_FILE ACFS_BACKUPS_DIR ACFS_LOCK_FILE ACFS_INTEGRITY_FILE TARGET_HOME
        HOME="relative-home"
        TARGET_USER="tester"
        SUDO_USER=""
        autofix_refresh_state_paths
        printf "%s
" "${ACFS_STATE_DIR:-unset}"
    ' _ "$REPO_ROOT/scripts/lib/autofix.sh" 2>&1)"; then
        echo "  Recomputing autofix state paths with unresolved runtime home failed: $output"
        return 1
    fi

    expected="/tmp/acfs-autofix.$(id -u 2>/dev/null || echo unknown)"
    if [[ "$output" != "$expected" ]]; then
        echo "  Expected ACFS_STATE_DIR fallback '$expected', got: $output"
        return 1
    fi

    return 0
}
test_autofix_resolve_current_home_ignores_path_poisoned_identity_shims() {
    local current_user=""
    local current_home=""
    local poisoned_home=""
    local fake_bin=""
    local output=""

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        current_home="/root"
    elif command -v getent &>/dev/null; then
        current_home="$(command getent passwd "$current_user" 2>/dev/null | cut -d: -f6)"
    elif command -v dscl &>/dev/null; then
        current_home="$(dscl . -read "/Users/$current_user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    elif command -v python3 &>/dev/null; then
        current_home="$(python3 -c "import pwd; print(pwd.getpwnam('$current_user').pw_dir)" 2>/dev/null || true)"
    fi
    [[ -z "$current_home" ]] && current_home="$HOME"
    current_home="${current_home%/}"

    poisoned_home="$(mktemp -d)"
    fake_bin="$(mktemp -d)"
    cat > "$fake_bin/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-un" ]]; then
    printf 'poisoned-user
'
    exit 0
fi
exit 2
EOF
    cat > "$fake_bin/whoami" <<'EOF'
#!/usr/bin/env bash
printf 'poisoned-user
'
EOF
    cat > "$fake_bin/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]]; then
    printf 'poisoned-user:x:1000:1000::%s:/bin/bash
' "$poisoned_home"
    exit 0
fi
exit 2
EOF
    chmod +x "$fake_bin/id" "$fake_bin/whoami" "$fake_bin/getent"

    if ! output="$(env HOME="$poisoned_home" PATH="$fake_bin:/usr/bin:/bin" bash -c '
        source "$1"
        autofix_resolve_current_home
    ' _ "$REPO_ROOT/scripts/lib/autofix.sh" 2>&1)"; then
        echo "  autofix_resolve_current_home failed under PATH poisoning: $output"
        rm -rf "$poisoned_home" "$fake_bin"
        return 1
    fi

    if [[ "$output" != "$current_home" ]]; then
        echo "  Expected current home '$current_home', got: $output"
        rm -rf "$poisoned_home" "$fake_bin"
        return 1
    fi

    rm -rf "$poisoned_home" "$fake_bin"
    return 0
}

test_autofix_passwd_python_fallback_passes_username_as_argv() {
    local fake_python="/tmp/test_autofix_passwd_python_$$"
    local marker_file="/tmp/test_autofix_passwd_args_$$"
    cat > "$fake_python" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$marker_file"
printf '/tmp/acfs-python-home\n'
EOF
    chmod +x "$fake_python"

    local result=""
    if ! result="$({
        autofix_system_binary_path() {
            case "${1:-}" in
                python3) printf '%s\n' "$fake_python" ;;
                *) return 1 ;;
            esac
        }
        autofix_getent_passwd_entry "acfs-python-fixture"
    })"; then
        echo "  Python passwd fallback failed"
        rm -f "$fake_python" "$marker_file"
        return 1
    fi

    if [[ "$result" != 'acfs-python-fixture:*:::acfs-python-fixture:/tmp/acfs-python-home:/bin/zsh' ]] || \
       [[ "$(sed -n '3p' "$marker_file")" != 'acfs-python-fixture' ]] || \
       grep -Fq 'acfs-python-fixture' <(sed -n '2p' "$marker_file"); then
        echo "  Python passwd fallback interpolated the username into source instead of passing argv"
        rm -f "$fake_python" "$marker_file"
        return 1
    fi

    if autofix_getent_passwd_entry "bad'user" >/dev/null 2>&1; then
        echo "  Invalid username was accepted by passwd lookup"
        rm -f "$fake_python" "$marker_file"
        return 1
    fi

    rm -f "$fake_python" "$marker_file"
    return 0
}

# Test: Init fails closed if integrity repair fails
test_init_autofix_state_fails_when_repair_fails() {
    setup_test_env

    verify_state_integrity() { return 1; }
    repair_state_files() { return 1; }

    if init_autofix_state >/dev/null 2>&1; then
        echo "  init_autofix_state unexpectedly succeeded despite failed repair"
        unset _ACFS_AUTOFIX_SOURCED
        source "$REPO_ROOT/scripts/lib/autofix.sh"
        cleanup_test_env
        return 1
    fi

    if [[ "$ACFS_AUTOFIX_INITIALIZED" == "true" ]]; then
        echo "  init_autofix_state left ACFS_AUTOFIX_INITIALIZED=true after failed repair"
        unset _ACFS_AUTOFIX_SOURCED
        source "$REPO_ROOT/scripts/lib/autofix.sh"
        cleanup_test_env
        return 1
    fi

    unset _ACFS_AUTOFIX_SOURCED
    source "$REPO_ROOT/scripts/lib/autofix.sh"
    cleanup_test_env
    return 0
}

test_init_autofix_state_rejects_symlinked_state_paths() {
    local test_root="/tmp/test_autofix_state_symlink_$$"
    local state_target="$test_root/target"
    local state_link="$test_root/state"
    mkdir -p "$state_target"
    ln -s "$state_target" "$state_link"

    export ACFS_STATE_DIR="$state_link"
    export ACFS_CHANGES_FILE="$state_link/changes.jsonl"
    export ACFS_UNDOS_FILE="$state_link/undos.jsonl"
    export ACFS_BACKUPS_DIR="$state_link/backups"
    export ACFS_LOCK_FILE="$state_link/.lock"
    export ACFS_INTEGRITY_FILE="$state_link/.integrity"
    ACFS_AUTOFIX_INITIALIZED=false

    if init_autofix_state >/dev/null 2>&1; then
        echo "  init_autofix_state accepted a symlinked state directory"
        rm -f "$state_link"
        rm -rf "$test_root"
        return 1
    fi
    if [[ -e "$state_target/changes.jsonl" || -e "$state_target/undos.jsonl" || -e "$state_target/backups" ]]; then
        echo "  Symlinked state initialization touched files outside the owned layout"
        rm -f "$state_link"
        rm -rf "$test_root"
        return 1
    fi

    rm -f "$state_link"
    rm -rf "$test_root"
    return 0
}

test_init_autofix_state_rejects_symlinked_state_parent() {
    local test_root="/tmp/test_autofix_state_parent_symlink_$$"
    local state_target="$test_root/target"
    local state_parent_link="$test_root/home/.acfs"
    local state_dir="$state_parent_link/autofix"
    mkdir -p "$state_target" "$test_root/home"
    ln -s "$state_target" "$state_parent_link"

    export ACFS_STATE_DIR="$state_dir"
    export ACFS_CHANGES_FILE="$state_dir/changes.jsonl"
    export ACFS_UNDOS_FILE="$state_dir/undos.jsonl"
    export ACFS_BACKUPS_DIR="$state_dir/backups"
    export ACFS_LOCK_FILE="$state_dir/.lock"
    export ACFS_INTEGRITY_FILE="$state_dir/.integrity"
    ACFS_AUTOFIX_INITIALIZED=false

    if init_autofix_state >/dev/null 2>&1; then
        echo "  init_autofix_state accepted a symlinked state parent"
        rm -f "$state_parent_link"
        rm -rf "$test_root"
        return 1
    fi
    if [[ -e "$state_target/autofix" ]]; then
        echo "  Symlinked parent initialization created state outside the trusted layout"
        rm -f "$state_parent_link"
        rm -rf "$test_root"
        return 1
    fi

    rm -f "$state_parent_link"
    rm -rf "$test_root"
    return 0
}

test_init_autofix_state_rejects_symlinked_journal() {
    setup_test_env

    local victim_file="/tmp/test_autofix_journal_victim_$$"
    printf 'preserve me\n' > "$victim_file"
    rm -f "$ACFS_CHANGES_FILE"
    ln -s "$victim_file" "$ACFS_CHANGES_FILE"

    if init_autofix_state >/dev/null 2>&1; then
        echo "  init_autofix_state accepted a symlinked changes journal"
        rm -f "$ACFS_CHANGES_FILE" "$victim_file"
        cleanup_test_env
        return 1
    fi
    if [[ "$(cat "$victim_file")" != "preserve me" ]]; then
        echo "  Symlinked journal initialization modified its external target"
        rm -f "$ACFS_CHANGES_FILE" "$victim_file"
        cleanup_test_env
        return 1
    fi

    rm -f "$ACFS_CHANGES_FILE" "$victim_file"
    cleanup_test_env
    return 0
}

# Test: Session management
test_session_management() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    if [[ -z "$ACFS_SESSION_ID" ]]; then
        echo "  Session ID not set"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if [[ ! -f "$ACFS_STATE_DIR/.session" ]]; then
        echo "  Session marker not created"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session 2>/dev/null || true

    if [[ -f "$ACFS_STATE_DIR/.session" ]]; then
        echo "  Session marker not removed"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_session_lock_preserves_caller_descriptors() {
    setup_test_env

    local caller_fd_file="/tmp/test_autofix_caller_fd_$$"
    exec 201>"$caller_fd_file"
    printf 'before\n' >&201

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session with a caller-owned descriptor open"
        exec 201>&-
        cleanup_test_env
        return 1
    fi
    printf 'during\n' >&201
    end_autofix_session >/dev/null 2>&1 || true
    printf 'after\n' >&201
    exec 201>&-

    if [[ "$(cat "$caller_fd_file")" != $'before\nduring\nafter' ]]; then
        echo "  Auto-fix lock allocation clobbered a caller-owned descriptor"
        rm -f "$caller_fd_file"
        cleanup_test_env
        return 1
    fi

    rm -f "$caller_fd_file"
    cleanup_test_env
    return 0
}

# Test: Session start fails closed if session marker cannot be persisted
test_start_autofix_session_releases_lock_when_session_marker_write_fails() {
    setup_test_env

    write_atomic() { return 1; }

    if start_autofix_session >/dev/null 2>&1; then
        echo "  start_autofix_session unexpectedly succeeded when session marker write failed"
        unset _ACFS_AUTOFIX_SOURCED
        source "$REPO_ROOT/scripts/lib/autofix.sh"
        cleanup_test_env
        return 1
    fi

    unset _ACFS_AUTOFIX_SOURCED
    source "$REPO_ROOT/scripts/lib/autofix.sh"

    if [[ -f "$ACFS_STATE_DIR/.session" ]]; then
        echo "  Failed start left behind a session marker"
        cleanup_test_env
        return 1
    fi

    exec 201>"$ACFS_LOCK_FILE" || {
        echo "  Failed to open autofix lock file after failed session start"
        cleanup_test_env
        return 1
    }
    if ! flock -n 201; then
        echo "  Failed start left the autofix lock held"
        exec 201>&-
        cleanup_test_env
        return 1
    fi
    flock -u 201 2>/dev/null || true
    exec 201>&-

    cleanup_test_env
    return 0
}

# Test: Session start rejects a preexisting unresolved session marker
test_start_autofix_session_clears_stale_session_marker() {
    setup_test_env

    # A marker left by an interrupted run (owning pid gone) must not brick
    # every later --fix and `acfs undo`; it is cleared and a new session
    # starts.
    printf '{"id":"stale","start":"2026-01-01T00:00:00Z","pid":999999}\n' > "$ACFS_STATE_DIR/.session"

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  start_autofix_session refused to start over a stale (dead-pid) session marker"
        cleanup_test_env
        return 1
    fi

    if [[ -z "${ACFS_SESSION_ID:-}" ]]; then
        echo "  Session started but no session ID was set"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if grep -q '"id":"stale"' "$ACFS_STATE_DIR/.session" 2>/dev/null; then
        echo "  Stale session marker was not replaced by the new session's marker"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_start_autofix_session_ignores_reused_pid_in_orphaned_marker() {
    setup_test_env

    # The marker's pid can be reused by an unrelated process. The flock is the
    # ownership authority, so an available lock permits atomic replacement.
    sleep 300 &
    local live_pid=$!

    printf '{"id":"stale","start":"2026-01-01T00:00:00Z","pid":%s}\n' "$live_pid" > "$ACFS_STATE_DIR/.session"

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  start_autofix_session mistook a reused live pid for lock ownership"
        kill "$live_pid" 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if [[ -z "${ACFS_SESSION_ID:-}" ]]; then
        echo "  Session started but no session ID was set"
        kill "$live_pid" 2>/dev/null || true
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if grep -q '"id":"stale"' "$ACFS_STATE_DIR/.session" 2>/dev/null; then
        echo "  Orphaned marker with reused pid was not replaced"
        kill "$live_pid" 2>/dev/null || true
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi
    if ! kill -0 "$live_pid" 2>/dev/null; then
        echo "  Session recovery disturbed the unrelated process whose pid was reused"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    kill "$live_pid" 2>/dev/null || true
    wait "$live_pid" 2>/dev/null || true

    cleanup_test_env
    return 0
}

# Test: Session start clears transient session state when lock is already held
test_start_autofix_session_clears_session_id_when_lock_is_held() {
    setup_test_env

    exec 201>"$ACFS_LOCK_FILE" || {
        echo "  Failed to open autofix lock file for pre-lock test"
        cleanup_test_env
        return 1
    }
    if ! flock -n 201; then
        echo "  Failed to pre-acquire autofix lock for contention test"
        exec 201>&-
        cleanup_test_env
        return 1
    fi

    if start_autofix_session >/dev/null 2>&1; then
        echo "  start_autofix_session unexpectedly succeeded while the autofix lock was held"
        flock -u 201 2>/dev/null || true
        exec 201>&-
        cleanup_test_env
        return 1
    fi

    flock -u 201 2>/dev/null || true
    exec 201>&-

    if [[ -n "${ACFS_SESSION_ID:-}" ]]; then
        echo "  Failed start left a transient session ID behind"
        cleanup_test_env
        return 1
    fi

    if [[ -f "$ACFS_STATE_DIR/.session" ]]; then
        echo "  Failed lock acquisition left behind a session marker"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# Test: Session end preserves marker if integrity finalization fails
test_end_autofix_session_preserves_marker_when_integrity_update_fails() {
    setup_test_env

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    update_integrity_file() { return 1; }

    if end_autofix_session >/dev/null 2>&1; then
        echo "  end_autofix_session unexpectedly succeeded when integrity update failed"
        unset _ACFS_AUTOFIX_SOURCED
        source "$REPO_ROOT/scripts/lib/autofix.sh"
        cleanup_test_env
        return 1
    fi

    unset _ACFS_AUTOFIX_SOURCED
    source "$REPO_ROOT/scripts/lib/autofix.sh"

    if [[ ! -f "$ACFS_STATE_DIR/.session" ]]; then
        echo "  Failed session finalization removed the session marker"
        cleanup_test_env
        return 1
    fi

    exec 201>"$ACFS_LOCK_FILE" || {
        echo "  Failed to open autofix lock file after failed session finalization"
        cleanup_test_env
        return 1
    }
    if ! flock -n 201; then
        echo "  Failed session finalization left the autofix lock held"
        exec 201>&-
        cleanup_test_env
        return 1
    fi
    flock -u 201 2>/dev/null || true
    exec 201>&-

    cleanup_test_env
    return 0
}

# Test: Record change and list
test_record_change() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local change_id
    change_id=$(record_change "test" "Test change" "echo undo" "false" "info" '[]' '[]' '[]' 2>/dev/null)

    if [[ -z "$change_id" ]]; then
        echo "  Failed to record change"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if [[ ! "$change_id" =~ ^chg_ ]]; then
        echo "  Invalid change ID format: $change_id"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    # Verify persisted (note: in-memory state is lost due to subshell from command substitution)
    if [[ ! -s "$ACFS_CHANGES_FILE" ]]; then
        echo "  Changes file is empty"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    # Verify the persisted change has the correct ID
    local persisted_id
    persisted_id=$(jq -r '.id' "$ACFS_CHANGES_FILE" | tail -1)
    if [[ "$persisted_id" != "$change_id" ]]; then
        echo "  Persisted ID mismatch: expected '$change_id', got '$persisted_id'"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session 2>/dev/null || true
    cleanup_test_env
    return 0
}

test_record_change_requires_active_session() {
    setup_test_env

    local output_file="$ACFS_STATE_DIR/record_change_no_session.out"
    local status=0

    if record_change "test" "No session" "echo undo" "false" "info" '[]' '[]' '[]' >"$output_file" 2>/dev/null; then
        status=0
    else
        status=$?
    fi

    if [[ $status -eq 0 ]]; then
        echo "  record_change succeeded without an active session"
        cleanup_test_env
        return 1
    fi

    if [[ -s "$output_file" ]]; then
        echo "  record_change emitted a change id without an active session"
        cleanup_test_env
        return 1
    fi

    if [[ -s "$ACFS_CHANGES_FILE" ]]; then
        echo "  changes.jsonl was modified without an active session"
        cleanup_test_env
        return 1
    fi

    if [[ ${#ACFS_CHANGE_ORDER[@]} -ne 0 ]] || [[ ${#ACFS_CHANGE_RECORDS[@]} -ne 0 ]]; then
        echo "  In-memory change state mutated without an active session"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_record_change_fails_when_append_atomic_fails() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local original_append_atomic output_file status=0
    original_append_atomic="$(declare -f append_atomic)"
    output_file="$ACFS_STATE_DIR/record_change.out"
    append_atomic() { return 1; }

    if record_change "test" "Broken persist" "echo undo" "false" "info" '[]' '[]' '[]' >"$output_file" 2>/dev/null; then
        status=0
    else
        status=$?
    fi

    eval "$original_append_atomic"

    if [[ $status -eq 0 ]]; then
        echo "  record_change succeeded even though append_atomic failed"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if [[ -s "$output_file" ]]; then
        echo "  record_change produced a change id despite persist failure"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if [[ -s "$ACFS_CHANGES_FILE" ]]; then
        echo "  changes.jsonl was modified despite persist failure"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if [[ ${#ACFS_CHANGE_ORDER[@]} -ne 0 ]] || [[ ${#ACFS_CHANGE_RECORDS[@]} -ne 0 ]]; then
        echo "  In-memory change state mutated despite persist failure"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session 2>/dev/null || true
    cleanup_test_env
    return 0
}

test_autofix_files_json_escapes_special_paths() {
    local tricky_path='/tmp/acfs "quoted" path\bin'
    local files_json=""
    local decoded=""

    files_json="$(autofix_files_json "$tricky_path")" || {
        echo "  autofix_files_json should encode valid path arguments"
        return 1
    }

    decoded="$(printf '%s' "$files_json" | jq -r '.[0]' 2>/dev/null)" || {
        echo "  Encoded affected-files JSON was not parseable"
        return 1
    }

    if [[ "$decoded" != "$tricky_path" ]]; then
        echo "  Encoded affected-files JSON did not round-trip special path characters"
        return 1
    fi

    return 0
}

# Test: Single backup objects are normalized into backup arrays
test_record_change_normalizes_single_backup_object() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local test_file="/tmp/test_record_backup_$$"
    printf 'original\n' > "$test_file"

    local backup_json change_id backup_type backup_len stored_backup_path expected_backup_path
    backup_json=$(create_backup "$test_file" "test")
    expected_backup_path=$(echo "$backup_json" | jq -r '.backup')

    change_id=$(record_change "test" "Normalized backup" "rm -f '$test_file'" "false" "info" "$(autofix_files_json "$test_file")" "$backup_json" "[]" 2>/dev/null)
    backup_type=$(jq -r --arg id "$change_id" 'select(.id == $id) | (.backups | type)' "$ACFS_CHANGES_FILE")
    backup_len=$(jq -r --arg id "$change_id" 'select(.id == $id) | (.backups | length)' "$ACFS_CHANGES_FILE")
    stored_backup_path=$(jq -r --arg id "$change_id" 'select(.id == $id) | .backups[0].backup' "$ACFS_CHANGES_FILE")

    if [[ "$backup_type" != "array" ]] || [[ "$backup_len" != "1" ]] || [[ "$stored_backup_path" != "$expected_backup_path" ]]; then
        echo "  Backup normalization failed: type=$backup_type len=$backup_len path=$stored_backup_path"
        rm -f "$test_file"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    end_autofix_session 2>/dev/null || true
    cleanup_test_env
    return 0
}

# Test: Multiple changes preserve order
test_multiple_changes_order() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local id1 id2 id3
    id1=$(record_change "cat1" "First" "echo 1" "false" "info" '[]' '[]' '[]' 2>/dev/null)
    id2=$(record_change "cat2" "Second" "echo 2" "false" "info" '[]' '[]' '[]' 2>/dev/null)
    id3=$(record_change "cat3" "Third" "echo 3" "false" "info" '[]' '[]' '[]' 2>/dev/null)

    # Check we got 3 changes in the file
    local file_count
    file_count=$(wc -l < "$ACFS_CHANGES_FILE")
    if [[ "$file_count" -ne 3 ]]; then
        echo "  Expected 3 changes in file, got $file_count"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    # Check order of IDs (should be sequential)
    if [[ "$id1" != "chg_0001" ]] || [[ "$id2" != "chg_0002" ]] || [[ "$id3" != "chg_0003" ]]; then
        echo "  Change IDs not sequential: $id1, $id2, $id3"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    # Check order in file
    local first_id last_id
    first_id=$(head -1 "$ACFS_CHANGES_FILE" | jq -r '.id')
    last_id=$(tail -1 "$ACFS_CHANGES_FILE" | jq -r '.id')
    if [[ "$first_id" != "chg_0001" ]] || [[ "$last_id" != "chg_0003" ]]; then
        echo "  File order incorrect: first=$first_id, last=$last_id"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session 2>/dev/null || true
    cleanup_test_env
    return 0
}

# Test: Undo command execution
test_undo_change() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    # Create a test file that the undo command will remove
    local test_marker="/tmp/test_undo_marker_$$"
    touch "$test_marker"

    # Record a change that removes the marker
    local change_id
    change_id=$(record_change "test" "Test change" "rm -f '$test_marker'" "false" "info" '[]' '[]' '[]' 2>/dev/null)

    # Undo should remove the marker
    if ! undo_change "$change_id" true true 2>/dev/null; then
        echo "  Undo failed"
        rm -f "$test_marker"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if [[ -f "$test_marker" ]]; then
        echo "  Undo command did not execute (marker still exists)"
        rm -f "$test_marker"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session 2>/dev/null || true
    cleanup_test_env
    return 0
}

test_undo_change_never_executes_checksum_invalid_record_with_force() {
    setup_test_env

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local marker_file="/tmp/test_untrusted_undo_marker_$$"
    local change_id=""
    local tampered_record=""
    change_id="$(record_change "test" "Untrusted undo" "true" false info '[]' '[]' '[]')"
    tampered_record="$(printf '%s' "${ACFS_CHANGE_RECORDS[$change_id]}" | jq -c --arg command "printf compromised > '$marker_file'" '.undo_command = $command')"
    ACFS_CHANGE_RECORDS["$change_id"]="$tampered_record"

    if undo_change "$change_id" true true >/dev/null 2>&1; then
        echo "  Forced undo accepted a checksum-invalid executable record"
        rm -f "$marker_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi
    if [[ -e "$marker_file" ]]; then
        echo "  Forced undo executed an untrusted journal command"
        rm -f "$marker_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_undo_change_rejects_checksummed_malformed_record() {
    setup_test_env

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local marker_file="/tmp/test_malformed_undo_marker_$$"
    local change_id=""
    local malformed_record=""
    change_id="$(record_change "test" "Malformed undo" "true" false info '[]' '[]' '[]')"
    malformed_record="$(printf '%s' "${ACFS_CHANGE_RECORDS[$change_id]}" | jq -c 'del(.record_checksum) | .undo_requires_root = "yes"')"
    malformed_record="$(autofix_add_record_checksum "$malformed_record")"
    malformed_record="$(printf '%s' "$malformed_record" | jq -c --arg command "printf compromised > '$marker_file'" 'del(.record_checksum) | .undo_command = $command')"
    malformed_record="$(autofix_add_record_checksum "$malformed_record")"
    ACFS_CHANGE_RECORDS["$change_id"]="$malformed_record"

    if undo_change "$change_id" true true >/dev/null 2>&1; then
        echo "  Undo accepted malformed executable metadata with a valid checksum"
        rm -f "$marker_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi
    if [[ -e "$marker_file" ]]; then
        echo "  Undo executed a checksummed but malformed record"
        rm -f "$marker_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_undo_change_never_forces_missing_recovery_backup() {
    setup_test_env

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local test_file="/tmp/test_missing_recovery_backup_$$"
    local backup_json=""
    local backup_path=""
    local restore_command=""
    local change_id=""
    printf 'before fix\n' > "$test_file"
    backup_json="$(create_backup "$test_file" "missing-recovery")"
    backup_path="$(printf '%s' "$backup_json" | jq -r '.backup')"
    restore_command="$(autofix_backup_restore_command "$backup_json")"
    printf 'after fix\n' > "$test_file"
    change_id="$(record_change "test" "Missing recovery backup" "$restore_command" false info "$(autofix_files_json "$test_file")" "[$backup_json]" '[]')"

    rm -f "$backup_path"
    if undo_change "$change_id" true true >/dev/null 2>&1; then
        echo "  Forced undo accepted a missing recovery backup"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi
    if [[ "$(cat "$test_file")" != "after fix" ]]; then
        echo "  Failed forced undo damaged the current target without a recovery backup"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_undo_change_fails_when_append_atomic_fails() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local marker_file="$ACFS_STATE_DIR/pending_precheck_marker"
    local output_file="$ACFS_STATE_DIR/change_id.out"
    touch "$marker_file"
    if ! record_change "test" "Undo persist failure" "rm -f '$marker_file'" "false" "info" '[]' '[]' '[]' >"$output_file" 2>/dev/null; then
        echo "  Failed to seed change for undo test"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    local change_id original_append_atomic status=0 undone_flag=""
    change_id="$(cat "$output_file")"
    original_append_atomic="$(declare -f append_atomic)"
    eval "${original_append_atomic/append_atomic/original_append_atomic}"
    append_atomic() {
        if [[ "$1" == "$ACFS_UNDOS_FILE" ]]; then
            return 1
        fi
        original_append_atomic "$@"
    }

    if undo_change "$change_id" true true >/dev/null 2>&1; then
        status=0
    else
        status=$?
    fi

    eval "$original_append_atomic"

    if [[ $status -eq 0 ]]; then
        echo "  undo_change succeeded even though undo journal append failed"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if [[ ! -f "$marker_file" ]]; then
        echo "  Undo command executed even though pending undo journal append failed"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if [[ -s "$ACFS_UNDOS_FILE" ]]; then
        echo "  undos.jsonl was modified despite persist failure"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    undone_flag="$(printf '%s' "${ACFS_CHANGE_RECORDS["$change_id"]}" | jq -r '.undone')"
    if [[ "$undone_flag" != "false" ]]; then
        echo "  In-memory undo state mutated despite persist failure"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session 2>/dev/null || true
    cleanup_test_env
    return 0
}

test_undo_change_leaves_pending_state_when_completion_persist_fails() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local marker_file="$ACFS_STATE_DIR/completion_pending_marker"
    local exec_log="$ACFS_STATE_DIR/completion_pending_exec.log"
    local output_file="$ACFS_STATE_DIR/change_id.out"
    touch "$marker_file"

    if ! record_change "test" "Undo completion persist failure" "printf x >> '$exec_log'; rm -f '$marker_file'" "false" "info" '[]' '[]' '[]' >"$output_file" 2>/dev/null; then
        echo "  Failed to seed change for completion-persist test"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    local change_id original_append_atomic status=0 undo_append_calls=0 undo_status="" exec_contents="" undo_line_count=0
    change_id="$(cat "$output_file")"
    original_append_atomic="$(declare -f append_atomic)"
    eval "${original_append_atomic/append_atomic/original_append_atomic}"
    append_atomic() {
        if [[ "$1" == "$ACFS_UNDOS_FILE" ]]; then
            undo_append_calls=$((undo_append_calls + 1))
            if [[ $undo_append_calls -eq 2 ]]; then
                return 1
            fi
        fi
        original_append_atomic "$@"
    }

    if undo_change "$change_id" true true >/dev/null 2>&1; then
        status=0
    else
        status=$?
    fi

    eval "$original_append_atomic"

    if [[ $status -eq 0 ]]; then
        echo "  undo_change succeeded even though completion persist failed"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if [[ -f "$marker_file" ]]; then
        echo "  Undo command did not execute before completion persist failure"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    exec_contents="$(cat "$exec_log" 2>/dev/null || true)"
    if [[ "$exec_contents" != "x" ]]; then
        echo "  Undo command execution log mismatch after completion persist failure: '$exec_contents'"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    undo_line_count=$(wc -l < "$ACFS_UNDOS_FILE")
    undo_status="$(autofix_change_undo_status "$change_id" 2>/dev/null || true)"
    if [[ "$undo_line_count" -ne 1 ]] || [[ "$undo_status" != "pending" ]] || [[ "$(jq -r '.status' "$ACFS_UNDOS_FILE")" != "pending" ]]; then
        echo "  Pending undo state was not preserved after completion persist failure"
        echo "  lines=$undo_line_count status=$undo_status file=$(cat "$ACFS_UNDOS_FILE" 2>/dev/null || true)"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if is_change_undone "$change_id"; then
        echo "  Pending undo state was incorrectly treated as undone"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if undo_change "$change_id" true true >/dev/null 2>&1; then
        echo "  Retry succeeded despite unresolved pending undo state"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    exec_contents="$(cat "$exec_log" 2>/dev/null || true)"
    if [[ "$exec_contents" != "x" ]]; then
        echo "  Pending undo retry re-executed the undo command"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session 2>/dev/null || true
    cleanup_test_env
    return 0
}

test_undo_change_marks_failed_when_executor_missing_after_pending() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local output_file="$ACFS_STATE_DIR/change_id.out"
    if ! record_change "test" "Undo executor missing" "true" "false" "info" '[]' '[]' '[]' >"$output_file" 2>/dev/null; then
        echo "  Failed to seed change for missing-executor test"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    local change_id original_autofix_system_binary_path status=0 undo_status="" undo_line_count=0
    change_id="$(cat "$output_file")"
    original_autofix_system_binary_path="$(declare -f autofix_system_binary_path)"
    eval "${original_autofix_system_binary_path/autofix_system_binary_path/original_autofix_system_binary_path}"
    autofix_system_binary_path() {
        case "${1:-}" in
            bash|env) return 1 ;;
            *) original_autofix_system_binary_path "$@" ;;
        esac
    }

    if undo_change "$change_id" true true >/dev/null 2>&1; then
        status=0
    else
        status=$?
    fi

    eval "$original_autofix_system_binary_path"
    unset -f original_autofix_system_binary_path

    if [[ $status -eq 0 ]]; then
        echo "  undo_change succeeded even though bash lookup failed"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    undo_line_count=$(wc -l < "$ACFS_UNDOS_FILE")
    undo_status="$(autofix_change_undo_status "$change_id" 2>/dev/null || true)"
    if [[ "$undo_line_count" -ne 2 ]] || [[ "$undo_status" != "failed" ]]; then
        echo "  Missing executor should leave failed undo state, not pending"
        echo "  lines=$undo_line_count status=$undo_status file=$(cat "$ACFS_UNDOS_FILE" 2>/dev/null || true)"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    if ! jq -e '.[0].status == "pending" and .[1].status == "failed" and .[1].exit_code == 127' < <(jq -s . "$ACFS_UNDOS_FILE") >/dev/null; then
        echo "  Undo journal did not record pending then failed executor state"
        cat "$ACFS_UNDOS_FILE"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session 2>/dev/null || true
    cleanup_test_env
    return 0
}

# Test: Manual/non-reversible changes cannot be falsely marked undone
test_undo_change_rejects_manual_non_reversible_change() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local change_id output="" list_output="" reversible=""
    change_id=$(record_change "test" "Manual change" "# Restore from backup manually" "false" "warning" '[]' '[]' '[]' 2>/dev/null)
    reversible=$(jq -r --arg id "$change_id" 'select(.id == $id) | .reversible' "$ACFS_CHANGES_FILE")

    output=$(undo_change "$change_id" true true 2>&1)
    if [[ $? -eq 0 ]]; then
        echo "  Manual change was incorrectly marked undone"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session 2>/dev/null || true
    list_output=$(acfs_undo_command --list 2>&1)

    if [[ "$reversible" != "false" ]] || [[ -s "$ACFS_UNDOS_FILE" ]] || [[ "$output" != *"Manual undo instructions: Restore from backup manually"* ]] || [[ "$list_output" != *"$change_id"* ]] || [[ "$list_output" != *"manual"* ]]; then
        echo "  Manual undo handling failed"
        echo "  reversible=$reversible"
        echo "  undo output=$output"
        echo "  list output=$list_output"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# Test: Undo category filtering handles quoted category values safely
test_acfs_undo_command_category_handles_quotes() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local change_id
    change_id=$(record_change 'quote"cat' "Quoted category" "echo quoted" "false" "info" '[]' '[]' '[]' 2>/dev/null)
    end_autofix_session 2>/dev/null || true

    local output=""
    output=$(acfs_undo_command --dry-run --category 'quote"cat' 2>&1)

    if [[ "$output" != *"$change_id"* ]] || [[ "$output" == *"jq:"* ]]; then
        echo "  Quoted category filter failed: $output"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# Test: --all skips already-undone changes instead of reprocessing them
test_acfs_undo_command_all_skips_undone_changes() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local already_undone_marker="/tmp/test_undo_all_done_$$"
    local active_marker="/tmp/test_undo_all_active_$$"
    touch "$already_undone_marker" "$active_marker"

    local done_id active_id
    done_id=$(record_change "test" "Already undone" "rm -f '$already_undone_marker'" "false" "info" '[]' '[]' '[]' 2>/dev/null)
    active_id=$(record_change "test" "Still active" "rm -f '$active_marker'" "false" "info" '[]' '[]' '[]' 2>/dev/null)
    end_autofix_session 2>/dev/null || true

    local undo_record=""
    undo_record="$(jq -cn --arg id "$done_id" '{undone:$id,timestamp:"2026-04-15T00:00:00Z",exit_code:0,status:"applied"}')"
    undo_record="$(autofix_add_record_checksum "$undo_record")"
    printf '%s\n' "$undo_record" > "$ACFS_UNDOS_FILE"

    local output=""
    output=$(acfs_undo_command --all 2>&1)

    if [[ -f "$active_marker" ]]; then
        echo "  Active change was not undone"
        rm -f "$already_undone_marker" "$active_marker"
        cleanup_test_env
        return 1
    fi

    if [[ ! -f "$already_undone_marker" ]]; then
        echo "  Already-undone change was processed again"
        rm -f "$already_undone_marker" "$active_marker"
        cleanup_test_env
        return 1
    fi

    if [[ "$output" == *"already been undone"* ]] || [[ "$output" != *"All requested changes have been undone"* ]]; then
        echo "  --all output indicates undone change was still queued: $output"
        rm -f "$already_undone_marker" "$active_marker"
        cleanup_test_env
        return 1
    fi

    rm -f "$already_undone_marker" "$active_marker"
    cleanup_test_env
    return 0
}

test_acfs_undo_command_list_marks_pending_changes() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local change_id
    change_id=$(record_change "test" "Pending undo change" "echo pending" "false" "info" '[]' '[]' '[]' 2>/dev/null)
    end_autofix_session 2>/dev/null || true

    local undo_record=""
    undo_record="$(jq -cn --arg id "$change_id" '{undone:$id,timestamp:"2026-04-15T00:00:00Z",status:"pending"}')"
    undo_record="$(autofix_add_record_checksum "$undo_record")"
    printf '%s\n' "$undo_record" > "$ACFS_UNDOS_FILE"

    local output=""
    output=$(acfs_undo_command --list 2>&1)

    if [[ "$output" != *"$change_id"* ]] || [[ "$output" != *"pending"* ]]; then
        echo "  --list did not mark pending change correctly: $output"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# Test: fsync_file function
test_fsync_file() {
    local test_file="/tmp/test_fsync_$$"
    echo "test" > "$test_file"

    # Should not error
    if ! fsync_file "$test_file"; then
        echo "  fsync_file failed"
        rm -f "$test_file"
        return 1
    fi

    rm -f "$test_file"
    return 0
}

test_fsync_file_dd_fallback_uses_valid_gnu_dd_syntax() {
    local test_file="/tmp/test_fsync_dd_fallback_$$"
    local args_file="/tmp/test_fsync_dd_args_$$"
    local original_python3=""
    local original_sync=""
    local original_dd=""
    local dd_args=""

    echo "test" > "$test_file"

    original_python3="$(declare -f python3 2>/dev/null || true)"
    original_sync="$(declare -f sync 2>/dev/null || true)"
    original_dd="$(declare -f dd 2>/dev/null || true)"

    python3() { return 127; }
    sync() { return 1; }
    dd() {
        if [[ "${1:-}" == "--help" ]]; then
            printf '%s\n' "GNU dd supports conv=fsync"
            return 0
        fi
        printf '%s\n' "$*" > "$args_file"
        return 0
    }

    if ! fsync_file "$test_file"; then
        [[ -n "$original_python3" ]] && eval "$original_python3" || unset -f python3
        [[ -n "$original_sync" ]] && eval "$original_sync" || unset -f sync
        [[ -n "$original_dd" ]] && eval "$original_dd" || unset -f dd
        echo "  fsync_file failed instead of using dd fallback"
        rm -f "$test_file" "$args_file"
        return 1
    fi

    [[ -n "$original_python3" ]] && eval "$original_python3" || unset -f python3
    [[ -n "$original_sync" ]] && eval "$original_sync" || unset -f sync
    [[ -n "$original_dd" ]] && eval "$original_dd" || unset -f dd

    dd_args="$(cat "$args_file" 2>/dev/null || true)"
    if [[ "$dd_args" == *"oflag=append,fsync"* ]]; then
        echo "  dd fallback still uses invalid oflag=fsync syntax: $dd_args"
        rm -f "$test_file" "$args_file"
        return 1
    fi
    if [[ "$dd_args" != *"oflag=append"* || "$dd_args" != *"conv=notrunc,fsync"* ]]; then
        echo "  dd fallback did not use expected append + conv=fsync syntax: $dd_args"
        rm -f "$test_file" "$args_file"
        return 1
    fi

    rm -f "$test_file" "$args_file"
    return 0
}

# Test: fsync_directory function
test_fsync_directory() {
    local test_dir="/tmp/test_fsync_dir_$$"
    mkdir -p "$test_dir"

    # Should not error
    if ! fsync_directory "$test_dir"; then
        echo "  fsync_directory failed"
        rm -rf "$test_dir"
        return 1
    fi

    rm -rf "$test_dir"
    return 0
}

# Test: Init autofix state
test_init_autofix_state() {
    setup_test_env

    # Remove the directories we just created to test init
    rm -rf "$ACFS_STATE_DIR"

    if ! init_autofix_state 2>/dev/null; then
        echo "  init_autofix_state failed"
        cleanup_test_env
        return 1
    fi

    if [[ ! -d "$ACFS_STATE_DIR" ]]; then
        echo "  State directory not created"
        cleanup_test_env
        return 1
    fi

    if [[ ! -d "$ACFS_BACKUPS_DIR" ]]; then
        echo "  Backups directory not created"
        cleanup_test_env
        return 1
    fi

    if [[ ! -f "$ACFS_INTEGRITY_FILE" ]]; then
        echo "  Initial integrity checkpoint not created"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# Test: Print undo summary (no errors)
test_print_undo_summary() {
    setup_test_env

    if ! start_autofix_session 2>/dev/null; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    record_change "test" "Test change 1" "echo 1" "false" "info" '[]' '[]' '[]' >/dev/null 2>&1
    record_change "test" "Test change 2" "echo 2" "false" "info" '[]' '[]' '[]' >/dev/null 2>&1

    # Should not error
    if ! print_undo_summary >/dev/null 2>&1; then
        echo "  print_undo_summary failed"
        end_autofix_session 2>/dev/null || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session 2>/dev/null || true
    cleanup_test_env
    return 0
}

# Test: Update integrity file
test_update_integrity_file() {
    setup_test_env

    echo '{"id":"chg_001"}' > "$ACFS_CHANGES_FILE"

    update_integrity_file 2>/dev/null

    if [[ ! -f "$ACFS_INTEGRITY_FILE" ]]; then
        echo "  Integrity file not created"
        cleanup_test_env
        return 1
    fi

    # Verify it's valid JSON
    if ! jq -e . "$ACFS_INTEGRITY_FILE" >/dev/null 2>&1; then
        echo "  Integrity file is not valid JSON"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# Test: Cleanup removes old backup directories as well as files
test_cleanup_old_backups_removes_directory_entries() {
    setup_test_env

    local old_backup_dir="$ACFS_BACKUPS_DIR/old-backup-dir"
    local old_backup_file="$ACFS_BACKUPS_DIR/old-backup-file.backup"
    mkdir -p "$old_backup_dir"
    printf 'nested\n' > "$old_backup_dir/file.txt"
    printf 'flat\n' > "$old_backup_file"

    if touch -d '40 days ago' "$old_backup_file" 2>/dev/null; then
        touch -d '40 days ago' "$old_backup_dir/file.txt" "$old_backup_file" "$old_backup_dir"
    elif command -v python3 &>/dev/null; then
        python3 -c "import os, time; t = time.time() - 40*86400; os.utime('$old_backup_dir/file.txt', (t, t)); os.utime('$old_backup_file', (t, t)); os.utime('$old_backup_dir', (t, t))" 2>/dev/null || true
    else
        touch -t 202001010000 "$old_backup_dir/file.txt" "$old_backup_file" "$old_backup_dir" 2>/dev/null || true
    fi

    if ! cleanup_old_backups 30 >/dev/null 2>&1; then
        echo "  Cleanup failed for old unreferenced backup entries"
        cleanup_test_env
        return 1
    fi

    if [[ -e "$old_backup_dir" ]] || [[ -e "$old_backup_file" ]]; then
        echo "  Old backup entries were not fully removed"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# Test: Cleanup preserves active referenced backups even when old
test_cleanup_old_backups_preserves_active_referenced_backups() {
    setup_test_env

    local test_file="/tmp/test_backup_active_$$"
    printf 'active\n' > "$test_file"

    ACFS_SESSION_ID="test_sess"

    local backup_json backup_path record
    backup_json=$(create_backup "$test_file" "test")
    backup_path=$(echo "$backup_json" | jq -r '.backup')
    record="$(make_test_change_record "chg_001" "active backup" "[$backup_json]")"
    printf '%s\n' "$record" > "$ACFS_CHANGES_FILE"
    if touch -d '40 days ago' "$backup_path" 2>/dev/null; then
        :
    elif command -v python3 &>/dev/null; then
        python3 -c "import os, time; t = time.time() - 40*86400; os.utime('$backup_path', (t, t))" 2>/dev/null || true
    else
        touch -t 202001010000 "$backup_path" 2>/dev/null || true
    fi

    if ! cleanup_old_backups 30 >/dev/null 2>&1; then
        echo "  Cleanup failed while preserving an active referenced backup"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    if [[ ! -e "$backup_path" ]]; then
        echo "  Active referenced backup was removed"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    cleanup_test_env
    return 0
}

test_cleanup_old_backups_fails_closed_on_untrusted_inventory() {
    setup_test_env

    local old_backup="$ACFS_BACKUPS_DIR/old-untrusted.backup"
    local record=""
    printf 'preserve\n' > "$old_backup"
    touch -t 202001010000 "$old_backup" 2>/dev/null || true

    record="$(make_test_change_record "chg_001" "malformed backup inventory")"
    record="$(printf '%s' "$record" | jq -c 'del(.record_checksum) | .backups = "not-an-array"')"
    record="$(autofix_add_record_checksum "$record")"
    printf '%s\n' "$record" > "$ACFS_CHANGES_FILE"

    if cleanup_old_backups 30 >/dev/null 2>&1; then
        echo "  Cleanup accepted an untrustworthy active-backup inventory"
        cleanup_test_env
        return 1
    fi
    if [[ ! -f "$old_backup" ]]; then
        echo "  Cleanup removed a backup despite untrustworthy journal metadata"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_cleanup_old_backups_rejects_invalid_retention() {
    setup_test_env

    local old_backup="$ACFS_BACKUPS_DIR/old-invalid-retention.backup"
    printf 'preserve\n' > "$old_backup"
    touch -t 202001010000 "$old_backup" 2>/dev/null || true

    if cleanup_old_backups 0 >/dev/null 2>&1; then
        echo "  Cleanup accepted a zero-day destructive retention window"
        cleanup_test_env
        return 1
    fi
    if [[ ! -f "$old_backup" ]]; then
        echo "  Invalid retention cleanup modified the backup store"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# ============================================================
# Regression tests for handle_existing_installation session management
# (ACFS #264 — https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues/264)
# ============================================================

_acfs_264_setup_installation() {
    local target_home="$1"
    local installed_version="${2:-0.6.0}"
    mkdir -p "$target_home/.acfs"
    printf '%s\n' "$installed_version" > "$target_home/.acfs/version"
}

test_handle_existing_installation_manages_session_for_upgrade() {
    setup_test_env
    local target_home="/tmp/test_acfs264_upgrade_$$"
    rm -rf "$target_home"
    _acfs_264_setup_installation "$target_home" "0.6.0"

    local output
    output=$(HOME="$target_home" TARGET_HOME="$target_home" \
        ACFS_STATE_DIR="$ACFS_STATE_DIR" \
        ACFS_CHANGES_FILE="$ACFS_CHANGES_FILE" \
        ACFS_UNDOS_FILE="$ACFS_UNDOS_FILE" \
        ACFS_BACKUPS_DIR="$ACFS_BACKUPS_DIR" \
        ACFS_LOCK_FILE="$ACFS_LOCK_FILE" \
        ACFS_INTEGRITY_FILE="$ACFS_INTEGRITY_FILE" \
        bash -c '
            set -u
            unset _ACFS_AUTOFIX_SOURCED _ACFS_AUTOFIX_EXISTING_SOURCED
            source "$1"
            source "$2"
            update_path_entries() { return 0; }
            export -f update_path_entries
            if autofix_session_active; then
                echo "precondition-fail: session already active"
                exit 2
            fi
            if ! handle_existing_installation "0.7.0" "upgrade" >/dev/null 2>&1; then
                echo "upgrade-failed"
                exit 3
            fi
            if autofix_session_active; then
                echo "session-leaked"
                exit 4
            fi
            echo "ok"
        ' _ "$REPO_ROOT/scripts/lib/autofix.sh" "$REPO_ROOT/scripts/lib/autofix_existing.sh" 2>&1)

    local status=$?
    rm -rf "$target_home"
    cleanup_test_env

    if [[ $status -eq 0 && "$output" == *"ok"* ]]; then
        return 0
    fi
    echo "  output: $output"
    echo "  status: $status"
    return 1
}

test_handle_existing_installation_preserves_outer_session() {
    setup_test_env
    local target_home="/tmp/test_acfs264_nested_$$"
    rm -rf "$target_home"
    _acfs_264_setup_installation "$target_home" "0.6.0"

    local output
    output=$(HOME="$target_home" TARGET_HOME="$target_home" \
        ACFS_STATE_DIR="$ACFS_STATE_DIR" \
        ACFS_CHANGES_FILE="$ACFS_CHANGES_FILE" \
        ACFS_UNDOS_FILE="$ACFS_UNDOS_FILE" \
        ACFS_BACKUPS_DIR="$ACFS_BACKUPS_DIR" \
        ACFS_LOCK_FILE="$ACFS_LOCK_FILE" \
        ACFS_INTEGRITY_FILE="$ACFS_INTEGRITY_FILE" \
        bash -c '
            set -u
            unset _ACFS_AUTOFIX_SOURCED _ACFS_AUTOFIX_EXISTING_SOURCED
            source "$1"
            source "$2"
            update_path_entries() { return 0; }
            export -f update_path_entries
            if ! start_autofix_session >/dev/null 2>&1; then
                echo "outer-start-failed"
                exit 2
            fi
            outer_sid="$ACFS_SESSION_ID"
            handle_existing_installation "0.7.0" "upgrade" >/dev/null 2>&1 || true
            if ! autofix_session_active; then
                echo "outer-session-lost"
                exit 3
            fi
            if [[ "$ACFS_SESSION_ID" != "$outer_sid" ]]; then
                echo "session-id-changed"
                exit 4
            fi
            end_autofix_session >/dev/null 2>&1 || true
            echo "ok"
        ' _ "$REPO_ROOT/scripts/lib/autofix.sh" "$REPO_ROOT/scripts/lib/autofix_existing.sh" 2>&1)

    local status=$?
    rm -rf "$target_home"
    cleanup_test_env

    if [[ $status -eq 0 && "$output" == *"ok"* ]]; then
        return 0
    fi
    echo "  output: $output"
    echo "  status: $status"
    return 1
}

# Test: record_change computes post_checksums for affected files
test_record_change_computes_post_checksums() {
    setup_test_env

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local test_file="/tmp/test_post_chk_$$"
    printf 'initial content\n' > "$test_file"

    local backup_json
    backup_json=$(create_backup "$test_file" "test")

    printf 'modified post fix content\n' > "$test_file"

    local change_id
    change_id=$(record_change "test" "Post checksum test" "cat > $test_file <<'EOF'\ninitial content\nEOF" false info "[\"$test_file\"]" "[$backup_json]")

    local recorded_post_sum
    recorded_post_sum=$(jq -r --arg id "$change_id" 'select(.id == $id) | .post_checksums[0].checksum // empty' "$ACFS_CHANGES_FILE")

    local expected_sum
    expected_sum=$(calculate_backup_checksum "$test_file")

    if [[ -z "$recorded_post_sum" || "$recorded_post_sum" != "$expected_sum" ]]; then
        echo "  Post checksum not recorded correctly: got '$recorded_post_sum', expected '$expected_sum'"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_record_change_fails_when_post_checksum_is_unavailable() {
    setup_test_env

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local test_file="/tmp/test_post_checksum_failure_$$"
    printf 'post-fix content\n' > "$test_file"

    if (
        calculate_backup_checksum() { return 1; }
        record_change "test" "Missing post checksum" "printf restored > '$test_file'" false info "[\"$test_file\"]" '[]'
    ) >/dev/null 2>&1; then
        echo "  record_change accepted an affected path without a post-fix checksum"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ -s "$ACFS_CHANGES_FILE" ]]; then
        echo "  Failed post-fix snapshot left a journal record behind"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_undo_change_refuses_incomplete_post_snapshot_without_force() {
    setup_test_env

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local test_file="/tmp/test_post_snapshot_missing_$$"
    printf 'post-fix content\n' > "$test_file"

    local change_id=""
    change_id=$(record_change "test" "Incomplete post snapshot" "printf 'restored content\\n' > '$test_file'" false info "[\"$test_file\"]" '[]')

    local incomplete_record=""
    local incomplete_checksum=""
    incomplete_record=$(printf '%s' "${ACFS_CHANGE_RECORDS[$change_id]}" | jq -c 'del(.post_checksums, .record_checksum)')
    incomplete_checksum=$(compute_record_checksum "$incomplete_record")
    incomplete_record=$(printf '%s' "$incomplete_record" | jq -c --arg sum "$incomplete_checksum" '.record_checksum = $sum')
    ACFS_CHANGE_RECORDS["$change_id"]="$incomplete_record"
    printf '%s\n' "$incomplete_record" > "$ACFS_CHANGES_FILE"

    if undo_change "$change_id" false >/dev/null 2>&1; then
        echo "  undo_change accepted an incomplete anti-clobber snapshot without --force"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ "$(cat "$test_file")" != "post-fix content" ]]; then
        echo "  Incomplete snapshot undo modified the affected file"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

# Test: undo_change refuses to clobber modified target file without --force
test_undo_change_refuses_to_clobber_modified_target_file_without_force() {
    setup_test_env

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local test_file="/tmp/test_post_clobber_$$"
    printf 'initial content\n' > "$test_file"

    local backup_json
    backup_json=$(create_backup "$test_file" "test")

    printf 'fix modified content\n' > "$test_file"

    local change_id
    change_id=$(record_change "test" "Clobber protection test" "printf 'initial content\n' > '$test_file'" false info "[\"$test_file\"]" "[$backup_json]")

    # User subsequently modifies file
    printf 'user subsequent edit\n' > "$test_file"

    # Attempt undo without force - must fail
    if undo_change "$change_id" false >/dev/null 2>&1; then
        echo "  undo_change unexpectedly succeeded without --force when target file had user edits"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    # Target file should not have been overwritten
    local current_content
    current_content=$(cat "$test_file")
    if [[ "$current_content" != "user subsequent edit" ]]; then
        echo "  Target file was modified despite rejected undo"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

# Test: undo_change overrides modified target file with --force
test_undo_change_overrides_modified_target_file_with_force() {
    setup_test_env

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local test_file="/tmp/test_post_force_$$"
    printf 'initial content\n' > "$test_file"

    local backup_json
    backup_json=$(create_backup "$test_file" "test")

    printf 'fix modified content\n' > "$test_file"

    local change_id
    change_id=$(record_change "test" "Force override test" "printf 'initial content\n' > '$test_file'" false info "[\"$test_file\"]" "[$backup_json]")

    # User subsequently modifies file
    printf 'user subsequent edit\n' > "$test_file"

    # Attempt undo with force - must succeed
    if ! undo_change "$change_id" true >/dev/null 2>&1; then
        echo "  undo_change failed with --force"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    local current_content
    current_content=$(cat "$test_file")
    if [[ "$current_content" != "initial content" ]]; then
        echo "  Target file was not restored to initial content after forced undo"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

# Test: undo_change refuses when target file deleted without --force
test_undo_change_refuses_when_missing_target_file_without_force() {
    setup_test_env

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local test_file="/tmp/test_post_deleted_$$"
    printf 'initial content\n' > "$test_file"

    local backup_json
    backup_json=$(create_backup "$test_file" "test")

    printf 'fix modified content\n' > "$test_file"

    local change_id
    change_id=$(record_change "test" "Deleted target protection test" "printf 'initial content\n' > '$test_file'" false info "[\"$test_file\"]" "[$backup_json]")

    # User deleted target file
    rm -f "$test_file"

    # Undo without force should fail
    if undo_change "$change_id" false >/dev/null 2>&1; then
        echo "  undo_change unexpectedly succeeded without --force when target file was deleted"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    # Undo with force should succeed
    if ! undo_change "$change_id" true >/dev/null 2>&1; then
        echo "  undo_change failed with --force on deleted target file"
        rm -f "$test_file"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

# Test: Change ID generation avoids collisions after journal repair
test_record_change_change_id_sequence_does_not_collide_after_journal_repair() {
    setup_test_env

    # Seed changes.jsonl with 5 changes
    local i
    for i in 1 2 3 4 5; do
        local cid="chg_$(printf '%04d' "$i")"
        local rec
        rec=$(jq -cn --arg id "$cid" '{id: $id, description: "seed", undone: false}')
        local csum
        csum=$(compute_record_checksum "$rec")
        rec=$(printf '%s' "$rec" | jq -c --arg sum "$csum" '. + {record_checksum: $sum}')
        printf '%s\n' "$rec" >> "$ACFS_CHANGES_FILE"
    done

    # Remove chg_0003 from changes.jsonl (leaving 4 lines total, with max ID chg_0005)
    local temp_f
    temp_f=$(mktemp)
    grep -v '"id":"chg_0003"' "$ACFS_CHANGES_FILE" > "$temp_f"
    mv "$temp_f" "$ACFS_CHANGES_FILE"

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local new_id
    new_id=$(record_change "test" "Collision test" "echo undo" false info '[]' '[]' '[]')

    if [[ "$new_id" != "chg_0006" ]]; then
        echo "  Expected next change ID chg_0006, got '$new_id' (collision with chg_0005 or line-count bug)"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

# Test: verify_backup_integrity rejects missing or null checksum
test_verify_backup_integrity_rejects_missing_checksum() {
    setup_test_env

    local test_file="/tmp/test_backup_sum_$$"
    printf 'data\n' > "$test_file"

    local bad_backup_json
    bad_backup_json=$(jq -cn --arg f "$test_file" '{backup: $f, original: $f, path_type: "file", checksum: null}')

    if verify_backup_integrity "$bad_backup_json" >/dev/null 2>&1; then
        echo "  verify_backup_integrity unexpectedly passed for null checksum"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    bad_backup_json=$(jq -cn --arg f "$test_file" '{backup: $f, original: $f, path_type: "file", checksum: ""}')
    if verify_backup_integrity "$bad_backup_json" >/dev/null 2>&1; then
        echo "  verify_backup_integrity unexpectedly passed for empty checksum"
        rm -f "$test_file"
        cleanup_test_env
        return 1
    fi

    rm -f "$test_file"
    cleanup_test_env
    return 0
}

# Test: undo_change runs under sanitized environment
test_undo_change_runs_under_sanitized_environment() {
    setup_test_env

    if ! start_autofix_session >/dev/null 2>&1; then
        echo "  Failed to start session"
        cleanup_test_env
        return 1
    fi

    local marker_file="/tmp/test_undo_env_marker_$$"
    local change_id
    change_id=$(record_change "test" "Sanitized env test" "printf '%s:%s:%s' \"\${BASH_ENV:-unset}\" \"\${ENV:-unset}\" \"\${LD_PRELOAD:-unset}\" > \"$marker_file\"" false info '[]' '[]' '[]')

    BASH_ENV="/evil/env" ENV="/evil/env" LD_PRELOAD="/evil/preload.so" undo_change "$change_id" true true >/dev/null 2>&1 || true

    local marker_content=""
    [[ -f "$marker_file" ]] && marker_content=$(cat "$marker_file")
    rm -f "$marker_file"

    if [[ "$marker_content" != "unset:unset:unset" ]]; then
        echo "  undo_change leaked startup or dynamic-loader environment: got '$marker_content'"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

# ============================================================
# Main Test Runner
# ============================================================

main() {
    echo "============================================================"
    echo "Running autofix unit tests..."
    echo "============================================================"
    echo ""

    run_test test_atomic_write
    run_test test_atomic_append
    run_test test_write_atomic_preserves_temp_through_fsync_functions
    run_test test_append_atomic_preserves_temp_through_fsync_functions
    run_test test_fsync_file
    run_test test_fsync_file_dd_fallback_uses_valid_gnu_dd_syntax
    run_test test_fsync_directory
    run_test test_backup_creation
    run_test test_backup_creation_uses_unique_paths_per_session
    run_test test_backup_creation_preserves_symlink_type
    run_test test_backup_creation_preserves_broken_symlink_type
    run_test test_backup_creation_fsyncs_broken_symlink_parent_directory
    run_test test_backup_creation_fsyncs_file_parent_directory
    run_test test_backup_creation_cleans_up_after_sync_failure
    run_test test_backup_creation_cleans_up_after_checksum_failure
    run_test test_directory_checksum_propagates_walker_failure
    run_test test_directory_checksum_tracks_symlink_targets_and_empty_directories
    run_test test_backup_creation_cleans_up_after_copy_failure
    run_test test_backup_nonexistent_file
    run_test test_backup_restore_command_rejects_unsafe_metadata
    run_test test_record_checksum
    run_test test_state_integrity
    run_test test_state_integrity_accepts_broken_symlink_backup
    run_test test_state_integrity_detects_type_drifted_symlink_backup
    run_test test_state_integrity_detects_corrupt_directory_backup
    run_test test_state_integrity_ignores_missing_backup_for_undone_change
    run_test test_state_integrity_checks_all_active_backups
    run_test test_state_integrity_rejects_missing_record_checksum
    run_test test_state_integrity_rejects_checksummed_malformed_change_schema
    run_test test_state_integrity_rejects_checksummed_malformed_undo_schema
    run_test test_state_integrity_rejects_duplicate_change_ids
    run_test test_state_repair
    run_test test_state_repair_preserves_all_valid_checksummed_records
    run_test test_state_repair_reconciles_checkpoint_without_losing_valid_records
    run_test test_state_repair_replaces_malformed_checkpoint
    run_test test_state_repair_fails_when_changes_rewrite_cannot_replace_file
    run_test test_autofix_globals_are_initialized_under_set_u
    run_test test_autofix_refresh_state_paths_falls_back_to_tmp_when_runtime_home_unresolved
    run_test test_autofix_resolve_current_home_ignores_path_poisoned_identity_shims
    run_test test_autofix_passwd_python_fallback_passes_username_as_argv
    run_test test_init_autofix_state
    run_test test_init_autofix_state_fails_when_repair_fails
    run_test test_init_autofix_state_rejects_symlinked_state_paths
    run_test test_init_autofix_state_rejects_symlinked_state_parent
    run_test test_init_autofix_state_rejects_symlinked_journal
    run_test test_session_management
    run_test test_session_lock_preserves_caller_descriptors
    run_test test_start_autofix_session_releases_lock_when_session_marker_write_fails
    run_test test_start_autofix_session_ignores_reused_pid_in_orphaned_marker
    run_test test_start_autofix_session_clears_stale_session_marker
    run_test test_start_autofix_session_clears_session_id_when_lock_is_held
    run_test test_end_autofix_session_preserves_marker_when_integrity_update_fails
    run_test test_record_change
    run_test test_record_change_requires_active_session
    run_test test_record_change_fails_when_append_atomic_fails
    run_test test_autofix_files_json_escapes_special_paths
    run_test test_record_change_normalizes_single_backup_object
    run_test test_record_change_computes_post_checksums
    run_test test_record_change_fails_when_post_checksum_is_unavailable
    run_test test_undo_change_refuses_incomplete_post_snapshot_without_force
    run_test test_record_change_change_id_sequence_does_not_collide_after_journal_repair
    run_test test_verify_backup_integrity_rejects_missing_checksum
    run_test test_multiple_changes_order
    run_test test_undo_change
    run_test test_undo_change_never_executes_checksum_invalid_record_with_force
    run_test test_undo_change_rejects_checksummed_malformed_record
    run_test test_undo_change_never_forces_missing_recovery_backup
    run_test test_undo_change_fails_when_append_atomic_fails
    run_test test_undo_change_leaves_pending_state_when_completion_persist_fails
    run_test test_undo_change_marks_failed_when_executor_missing_after_pending
    run_test test_undo_change_rejects_manual_non_reversible_change
    run_test test_undo_change_refuses_to_clobber_modified_target_file_without_force
    run_test test_undo_change_overrides_modified_target_file_with_force
    run_test test_undo_change_refuses_when_missing_target_file_without_force
    run_test test_undo_change_runs_under_sanitized_environment
    run_test test_acfs_undo_command_category_handles_quotes
    run_test test_acfs_undo_command_all_skips_undone_changes
    run_test test_acfs_undo_command_list_marks_pending_changes
    run_test test_print_undo_summary
    run_test test_update_integrity_file
    run_test test_cleanup_old_backups_removes_directory_entries
    run_test test_cleanup_old_backups_preserves_active_referenced_backups
    run_test test_cleanup_old_backups_fails_closed_on_untrusted_inventory
    run_test test_cleanup_old_backups_rejects_invalid_retention
    run_test test_handle_existing_installation_manages_session_for_upgrade
    run_test test_handle_existing_installation_preserves_outer_session

    echo ""
    echo "============================================================"
    echo "Test Summary"
    echo "============================================================"
    echo "  Total:  $TESTS_RUN"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "============================================================"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
