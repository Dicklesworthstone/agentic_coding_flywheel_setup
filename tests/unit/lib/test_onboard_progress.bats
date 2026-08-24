#!/usr/bin/env bats
# ============================================================
# Unit tests for onboard progress tracking and lesson numbering (bd-s2nz2)
# ============================================================

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
}

@test "onboard: root startup uses the fixed interpreter and an OS-owned PATH" {
    run bash -c '
        first_line="$(sed -n "1p" packages/onboard/onboard.sh)"
        [[ "$first_line" == "#!/bin/bash" ]]
        grep -Fq '\''readonly _ONBOARD_PRIVILEGED_PATH="/usr/sbin:/usr/bin:/sbin:/bin"'\'' packages/onboard/onboard.sh
        grep -Fq '\''export PATH="$_ONBOARD_PRIVILEGED_PATH"'\'' packages/onboard/onboard.sh
    '

    assert_success
}

teardown() {
    common_teardown
}

helper_create_mock_lessons() {
    local target_dir="$1"
    mkdir -p "$target_dir"
    cat > "$target_dir/00_welcome.md" <<'EOF'
# Welcome to ACFS
Welcome lesson content.
EOF
    cat > "$target_dir/01_linux_basics.md" <<'EOF'
# Linux Basics
Linux basics content.
EOF
    cat > "$target_dir/23_srps.md" <<'EOF'
# SRPS
SRPS content.
EOF
    cat > "$target_dir/33_fsfs.md" <<'EOF'
# FSFS
FSFS content.
EOF
}

@test "onboard: discovers non-contiguous lesson numbers accurately" {
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    helper_create_mock_lessons "$lessons_dir"

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        printf "COUNT:%d\n" "$NUM_LESSONS"
        printf "NUMS:%s\n" "${LESSON_NUMBERS[*]}"
        printf "IDX_33:%s\n" "$(get_lesson_index_by_number 33)"
        printf "NUM_IDX3:%s\n" "$(get_lesson_number 3)"
    '
    assert_success
    assert_output --partial "COUNT:4"
    assert_output --partial "NUMS:0 1 23 33"
    assert_output --partial "IDX_33:3"
    assert_output --partial "NUM_IDX3:33"
}

@test "onboard: duplicate lesson numbers emit warning and do not collide silently" {
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    helper_create_mock_lessons "$lessons_dir"
    cat > "$lessons_dir/01_duplicate_linux.md" <<'EOF'
# Duplicate Linux
Duplicate content.
EOF

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        printf "COUNT:%d\n" "$NUM_LESSONS"
        printf "NUMS:%s\n" "${LESSON_NUMBERS[*]}"
    '
    assert_success
    assert_output --partial "Warning: duplicate lesson number 1"
    assert_output --partial "COUNT:5"
}

@test "onboard: saves progress keyed by lesson number and advances current correctly" {
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    helper_create_mock_lessons "$lessons_dir"

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        init_progress
        before="$(cat "$ACFS_PROGRESS_FILE")"
        if mark_completed 999 || set_current 999; then
            echo "INVALID_LESSON_ACCEPTED"
            exit 1
        fi
        [[ "$(cat "$ACFS_PROGRESS_FILE")" == "$before" ]] || {
            echo "INVALID_LESSON_MUTATED_PROGRESS"
            exit 1
        }
        mark_completed 0
        printf "AFTER_0_CURRENT:%s\n" "$(get_current)"
        mark_completed 1
        printf "AFTER_1_CURRENT:%s\n" "$(get_current)"
        mark_completed 2
        printf "AFTER_2_CURRENT:%s\n" "$(get_current)"
        mark_completed 3
        printf "AFTER_3_CURRENT:%s\n" "$(get_current)"
    '
    assert_success
    refute_output --partial "INVALID_LESSON_ACCEPTED"
    refute_output --partial "INVALID_LESSON_MUTATED_PROGRESS"
    assert_output --partial "AFTER_0_CURRENT:1"
    assert_output --partial "AFTER_1_CURRENT:23"
    assert_output --partial "AFTER_2_CURRENT:33"
    assert_output --partial "AFTER_3_CURRENT:33"

    [[ -f "$progress_file" ]]
    run env ACFS_PROGRESS_FILE="$progress_file" bash -c '
        if command -v jq &>/dev/null; then
            jq -e "(.version == 2) and (.completed == [0, 1, 23, 33])" "$ACFS_PROGRESS_FILE"
        else
            grep -q "33" "$ACFS_PROGRESS_FILE"
        fi
    '
    assert_success
}

@test "onboard: handles index vs lesson number collisions accurately without cross-talk" {
    local lessons_dir="$BATS_TEST_TMPDIR/collision_lessons"
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    mkdir -p "$lessons_dir"
    cat > "$lessons_dir/00_a.md" <<'EOF'
# A
EOF
    cat > "$lessons_dir/02_b.md" <<'EOF'
# B
EOF
    cat > "$lessons_dir/10_c.md" <<'EOF'
# C
EOF

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        init_progress
        # Mark index 2 (lesson 10) complete
        mark_completed 2

        # Verify index 2 (lesson 10) is completed
        if is_completed 2; then echo "IDX2_COMPLETED"; fi

        # Verify index 1 (lesson 2) is NOT completed
        if ! is_completed 1; then echo "IDX1_NOT_COMPLETED"; fi

        # Set current to index 2 (lesson 10)
        set_current 2
        printf "CURRENT_NUM:%s\n" "$(get_current)"
        printf "CURRENT_IDX:%s\n" "$(get_current_index)"
    '
    assert_success
    assert_output --partial "IDX2_COMPLETED"
    assert_output --partial "IDX1_NOT_COMPLETED"
    assert_output --partial "CURRENT_NUM:10"
    assert_output --partial "CURRENT_IDX:2"
}

@test "onboard: adding intermediate lesson file does not corrupt existing completion state" {
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    helper_create_mock_lessons "$lessons_dir"

    # Complete index 3 (lesson 33)
    env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        init_progress
        mark_completed 3
    '

    # Verify index 3 (lesson 33) is completed
    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        init_progress
        if is_completed 3; then echo "33_IS_COMPLETED"; fi
    '
    assert_success
    assert_output --partial "33_IS_COMPLETED"

    # Now add an intermediate lesson: 24_new_tool.md
    cat > "$lessons_dir/24_new_tool.md" <<'EOF'
# New Tool
Intermediate tool content.
EOF

    # In new ordering:
    # 0 -> 00, 1 -> 01, 2 -> 23, 3 -> 24 (new), 4 -> 33
    # Verify index 4 (lesson 33) is STILL completed and index 3 (lesson 24) is NOT completed
    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        init_progress
        if is_completed 4; then echo "33_STILL_COMPLETED"; fi
        if ! is_completed 3; then echo "24_NOT_COMPLETED"; fi
    '
    assert_success
    assert_output --partial "33_STILL_COMPLETED"
    assert_output --partial "24_NOT_COMPLETED"
}

@test "onboard: removed current lesson number falls back without index reinterpretation" {
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    mkdir -p "$lessons_dir"
    printf '# Zero\n' > "$lessons_dir/00_zero.md"
    printf '# Ten\n' > "$lessons_dir/10_ten.md"
    printf '# Twenty\n' > "$lessons_dir/20_twenty.md"
    printf '%s\n' '{"version":2,"completed":[0],"current":2,"started_at":"2026-01-01T00:00:00Z","last_accessed":"2026-01-01T00:00:00Z"}' > "$progress_file"

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        init_progress
        printf "CURRENT_IDX:%s\n" "$(get_current_index)"
        printf "CURRENT_NUM:%s\n" "$(get_lesson_number "$(get_current_index)")"
    '
    assert_success
    assert_output --partial "CURRENT_IDX:1"
    assert_output --partial "CURRENT_NUM:10"
    refute_output --partial "CURRENT_NUM:20"
}

@test "onboard: no-jq progress does not reinterpret a canonical lesson number as an index" {
    local lessons_dir="$BATS_TEST_TMPDIR/long_lessons"
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    local lesson_number
    mkdir -p "$lessons_dir"

    # Index 24 is lesson 33, while index 33 is lesson 42. This reproduces the
    # live-catalog collision that a second canonicalization used to corrupt.
    for lesson_number in {0..23} {33..42}; do
        printf '# Lesson %s\n' "$lesson_number" > \
            "$lessons_dir/$(printf '%02d' "$lesson_number")_lesson.md"
    done

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        command() {
            if [[ "$1" == "-v" && "${2:-}" == "jq" ]]; then
                return 1
            fi
            builtin command "$@"
        }

        init_progress
        mark_completed 24
        printf "COMPLETED:%s\n" "$(get_completed)"
    '
    assert_success
    assert_output --partial "COMPLETED:33"
    refute_output --partial "COMPLETED:42"
}

@test "onboard: migrates legacy index-based progress files to version 2 lesson numbers" {
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    helper_create_mock_lessons "$lessons_dir"

    # Write legacy unversioned progress file where index 3 represents lesson 33
    cat > "$progress_file" <<'EOF'
{
  "completed": [0, 3],
  "current": 3,
  "started_at": "2026-01-01T00:00:00Z",
  "last_accessed": "2026-01-01T00:00:00Z"
}
EOF

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        init_progress
        if is_completed 0; then echo "0_COMPLETED"; fi
        if is_completed 3; then echo "33_COMPLETED"; fi
    '
    assert_success
    assert_output --partial "0_COMPLETED"
    assert_output --partial "33_COMPLETED"

    # Verify file was migrated to version 2
    run env ACFS_PROGRESS_FILE="$progress_file" bash -c '
        if command -v jq &>/dev/null; then
            jq -e ".version == 2 and (.completed | index(33) != null)" "$ACFS_PROGRESS_FILE"
        else
            grep -q "\"version\":2" "$ACFS_PROGRESS_FILE"
        fi
    '
    assert_success
}

@test "onboard: dotlock verifies pid ownership on acquire and release" {
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    helper_create_mock_lessons "$lessons_dir"

    run env _ONBOARD_DISABLE_FLOCK="true" ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        handle=""
        onboard_acquire_progress_lock handle
        echo "ACQUIRED_HANDLE:$handle"

        # Attempt to release with a mismatched PID handle (should NOT remove lock dir)
        onboard_release_progress_lock "dir:999999"
        if [[ -d "${PROGRESS_LOCK_FILE}.d" ]]; then
            echo "DIR_STILL_EXISTS_AFTER_MISMATCH"
        fi

        # A missing ownership record is not evidence that this handle owns the
        # directory. Preserve the lock until ownership can be proven.
        mv "${PROGRESS_LOCK_FILE}.d/pid" "${PROGRESS_LOCK_FILE}.d/pid.saved"
        onboard_release_progress_lock "$handle"
        if [[ -d "${PROGRESS_LOCK_FILE}.d" ]]; then
            echo "DIR_STILL_EXISTS_WITHOUT_PID"
        fi
        mv "${PROGRESS_LOCK_FILE}.d/pid.saved" "${PROGRESS_LOCK_FILE}.d/pid"

        # Release with correct handle
        onboard_release_progress_lock "$handle"
        if [[ ! -d "${PROGRESS_LOCK_FILE}.d" ]]; then
            echo "DIR_REMOVED_AFTER_MATCH"
        fi
    '
    assert_success
    assert_output --partial "DIR_STILL_EXISTS_AFTER_MISMATCH"
    assert_output --partial "DIR_STILL_EXISTS_WITHOUT_PID"
    assert_output --partial "DIR_REMOVED_AFTER_MATCH"
}

@test "onboard: exit cleanup releases the owned fallback progress lock" {
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    helper_create_mock_lessons "$lessons_dir"

    run env _ONBOARD_DISABLE_FLOCK="true" ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        trap _onboard_release_active_progress_lock EXIT
        handle=""
        onboard_acquire_progress_lock handle
        [[ "$handle" == dir:* ]]
        [[ -d "${PROGRESS_LOCK_FILE}.d" ]]
    '

    assert_success
    [[ ! -e "${progress_file}.lock.d" ]]
}

@test "onboard: sourcing preserves the caller's signal traps" {
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    helper_create_mock_lessons "$lessons_dir"

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        trap "printf caller-int\\n" INT
        trap "printf caller-term\\n" TERM
        trap "printf caller-hup\\n" HUP
        before_int="$(trap -p INT)"
        before_term="$(trap -p TERM)"
        before_hup="$(trap -p HUP)"
        before_path="$PATH"
        source packages/onboard/onboard.sh
        [[ "$(trap -p INT)" == "$before_int" ]]
        [[ "$(trap -p TERM)" == "$before_term" ]]
        [[ "$(trap -p HUP)" == "$before_hup" ]]
        [[ "$PATH" == "$before_path" ]]
    '

    assert_success
}

@test "onboard: repeated resets preserve distinct progress backups" {
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    helper_create_mock_lessons "$lessons_dir"

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        init_progress
        mark_completed 0
        reset_progress >/dev/null
        mark_completed 1
        reset_progress >/dev/null
        backup_count=0
        for backup in "${ACFS_PROGRESS_FILE}".backup.*; do
            [[ -e "$backup" || -L "$backup" ]] || continue
            ((backup_count += 1))
        done
        printf "BACKUPS:%s\n" "$backup_count"
    '

    assert_success
    assert_output --partial "BACKUPS:2"
}

@test "onboard: failed reset restores the active progress file" {
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    helper_create_mock_lessons "$lessons_dir"

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        init_progress
        mark_completed 0
        before="$(cat "$ACFS_PROGRESS_FILE")"
        mktemp() { return 1; }
        if reset_progress >/dev/null 2>&1; then
            echo "RESET_UNEXPECTEDLY_SUCCEEDED"
            exit 1
        fi
        unset -f mktemp
        [[ -f "$ACFS_PROGRESS_FILE" ]]
        [[ "$(cat "$ACFS_PROGRESS_FILE")" == "$before" ]]
        printf "RESTORED:%s\n" "$(get_completed)"
    '

    assert_success
    assert_output --partial "RESTORED:0"
    refute_output --partial "RESET_UNEXPECTEDLY_SUCCEEDED"
}

@test "onboard: refuses unsupported progress path types" {
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    helper_create_mock_lessons "$lessons_dir"
    mkdir -p "$progress_file"

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        if init_progress >/dev/null 2>&1; then
            echo "DIRECTORY_PROGRESS_UNEXPECTEDLY_ACCEPTED"
            exit 1
        fi
        entry_count=0
        for entry in "$ACFS_PROGRESS_FILE"/*; do
            [[ -e "$entry" || -L "$entry" ]] || continue
            ((entry_count += 1))
        done
        printf "DIRECTORY_ENTRIES:%s\n" "$entry_count"
    '

    assert_success
    assert_output --partial "DIRECTORY_ENTRIES:0"
    refute_output --partial "DIRECTORY_PROGRESS_UNEXPECTEDLY_ACCEPTED"
}

@test "onboard: progress locks refuse symlinks without truncating their targets" {
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    local sentinel="$BATS_TEST_TMPDIR/sentinel"
    helper_create_mock_lessons "$lessons_dir"
    printf '%s\n' 'must survive' > "$sentinel"
    ln -s "$sentinel" "${progress_file}.lock"

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        handle=""
        if onboard_acquire_progress_lock handle; then
            echo "LOCK_UNEXPECTEDLY_ACQUIRED"
            exit 1
        fi
        printf "SENTINEL:%s\n" "$(cat "$1")"
    ' _ "$sentinel"
    assert_success
    assert_output --partial "SENTINEL:must survive"
    refute_output --partial "LOCK_UNEXPECTEDLY_ACQUIRED"
}

@test "onboard: rejects semantically malformed progress values" {
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    helper_create_mock_lessons "$lessons_dir"
    printf '%s\n' '{"version":2,"completed":[0,"1"],"current":-1}' > "$progress_file"

    run env ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        if progress_file_is_valid; then
            echo "MALFORMED_PROGRESS_ACCEPTED"
            exit 1
        fi
    '
    assert_success
    refute_output --partial "MALFORMED_PROGRESS_ACCEPTED"
}

@test "onboard: no-jq migration preserves multi-digit v2-compatible versions" {
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    helper_create_mock_lessons "$lessons_dir"
    printf '%s\n' '{"version":10,"completed":[33],"current":33}' > "$progress_file"

    run env _ONBOARD_DISABLE_FLOCK="true" ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        command() {
            if [[ "$1" == "-v" && "${2:-}" == "jq" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        init_progress
        printf "PROGRESS:%s\n" "$(tr -d "[:space:]" < "$ACFS_PROGRESS_FILE")"
    '
    assert_success
    assert_output --partial '"version":10'
    assert_output --partial '"completed":[33]'
    assert_output --partial '"current":33'
}

@test "onboard: no-jq writes replace malformed carried timestamps" {
    local progress_file="$BATS_TEST_TMPDIR/progress.json"
    local lessons_dir="$BATS_TEST_TMPDIR/lessons"
    helper_create_mock_lessons "$lessons_dir"
    printf '%s\n' '{"version":2,"completed":[],"current":0,"started_at":"broken\\","last_accessed":"2026-01-01T00:00:00Z"}' > "$progress_file"

    run env _ONBOARD_DISABLE_FLOCK="true" ACFS_LESSONS_DIR="$lessons_dir" ACFS_PROGRESS_FILE="$progress_file" bash -c '
        source packages/onboard/onboard.sh
        command() {
            if [[ "$1" == "-v" && "${2:-}" == "jq" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        init_progress
        mark_completed 0
        printf "PROGRESS:%s\n" "$(tr -d "[:space:]" < "$ACFS_PROGRESS_FILE")"
    '
    assert_success
    refute_output --partial '"started_at":"broken\\"'
    [[ "$output" =~ \"started_at\":\"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\" ]]
}
