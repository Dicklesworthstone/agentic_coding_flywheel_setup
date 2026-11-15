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

helper_create_selection_runtime() {
    ONBOARD_SELECTION_TEST_HOME="$BATS_TEST_TMPDIR/selection-home"
    ONBOARD_SELECTION_TEST_ACFS="$ONBOARD_SELECTION_TEST_HOME/.acfs"
    mkdir -p "$ONBOARD_SELECTION_TEST_ACFS/onboard" \
        "$ONBOARD_SELECTION_TEST_ACFS/scripts/lib" \
        "$ONBOARD_SELECTION_TEST_ACFS/scripts/generated"
    cp "$PROJECT_ROOT/packages/onboard/onboard.sh" "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh"
    cp "$PROJECT_ROOT/scripts/lib/state.sh" "$PROJECT_ROOT/scripts/lib/logging.sh" \
        "$PROJECT_ROOT/scripts/lib/gum_ui.sh" "$ONBOARD_SELECTION_TEST_ACFS/scripts/lib/"
    cp "$PROJECT_ROOT/scripts/generated/manifest_index.sh" "$ONBOARD_SELECTION_TEST_ACFS/scripts/generated/manifest_index.sh"
    cp "$PROJECT_ROOT/scripts/services-setup.sh" "$ONBOARD_SELECTION_TEST_ACFS/scripts/services-setup.sh"
    helper_create_mock_lessons "$ONBOARD_SELECTION_TEST_ACFS/onboard/lessons"
}

helper_write_selection_checkpoint() {
    jq -n --arg target_home "$ONBOARD_SELECTION_TEST_HOME" --arg target_user "$(id -un)" \
        --argjson modules "$1" \
        '{target_home:$target_home,target_user:$target_user,
          module_selection:{schema_version:1,selected_modules:$modules}}' \
        > "$ONBOARD_SELECTION_TEST_ACFS/state.json"
}

helper_run_selection_onboard() {
    run env -u ACFS_STATE_FILE -u CODEX_HOME -u ANTHROPIC_API_KEY -u OPENAI_API_KEY \
        -u GEMINI_API_KEY -u GOOGLE_API_KEY -u VERCEL_TOKEN -u SUPABASE_ACCESS_TOKEN -u CLOUDFLARE_API_TOKEN \
        ACFS_HOME="$ONBOARD_SELECTION_TEST_ACFS" TARGET_HOME="$ONBOARD_SELECTION_TEST_HOME" \
        TARGET_USER="$(id -un)" ACFS_SYSTEM_STATE_FILE="$ONBOARD_SELECTION_TEST_HOME/no-system-state.json" \
        ACFS_PROGRESS_FILE="$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ACFS_LOCAL_PROGRESS=off \
        "$@"
}

@test "onboard: selected auth screen omits excluded probes and credential rows" {
    helper_create_selection_runtime
    helper_write_selection_checkpoint '["agents.codex","acfs.onboard"]'
    cp "$ONBOARD_SELECTION_TEST_ACFS/state.json" "$ONBOARD_SELECTION_TEST_HOME/state.before"
    mkdir -p "$ONBOARD_SELECTION_TEST_HOME/.codex"
    printf '%s\n' '{"tokens":{"access_token":"selection-fixture-secret"}}' > "$ONBOARD_SELECTION_TEST_HOME/.codex/auth.json"

    helper_run_selection_onboard bash -c '
        source "$1"
        has_gum() { return 1; }
        clear() { :; }
        get_auth_status_code() { printf "PROBE:%s\n" "$1" >&2; printf "1\n"; }
        show_auth_flow </dev/null
    ' _ "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh"
    assert_success
    assert_output --partial 'PROBE:codex'
    assert_output --partial '[1] Codex CLI'
    assert_output --partial 'codex: state=file_configured'
    local service
    for service in tailscale claude antigravity github vercel supabase cloudflare; do
        refute_output --partial "PROBE:$service"
        refute_output --partial "$service: state="
    done
    refute_output --partial 'selection-fixture-secret'
    [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
    [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/local_progress.json" ]]
    cmp -s "$ONBOARD_SELECTION_TEST_HOME/state.before" "$ONBOARD_SELECTION_TEST_ACFS/state.json"
}

@test "onboard: scoped credential JSON contains only selected optional services" {
    helper_create_selection_runtime
    helper_write_selection_checkpoint '["agents.codex","cloud.wrangler","acfs.onboard"]'

    helper_run_selection_onboard bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" credential-status
    assert_success
    printf '%s' "$output" | jq -e '
        .kind == "acfs.credential_status" and .status == "pass" and .read_only == true and
        ([.services[].service] | sort) == ["codex","wrangler"] and
        all(.services[]; .requirement == "optional" and .authentication == "unverified") and
        .safety.files_mutated == false and .safety.provider_validation_performed == false' >/dev/null
    [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
}

@test "onboard: scoped credential capture rejects duplicate unknown or missing service rows" {
    helper_create_selection_runtime
    helper_write_selection_checkpoint '["agents.codex","acfs.onboard"]'
    helper_run_selection_onboard bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" credential-status
    assert_success
    printf '%s\n' "$output" > "$ONBOARD_SELECTION_TEST_HOME/report.before.json"
    cat > "$ONBOARD_SELECTION_TEST_ACFS/scripts/services-setup.sh" <<'EOF'
services_setup_credential_status_json() {
    cat "$ONBOARD_CREDENTIAL_FIXTURE"
}
EOF
    local filter
    for filter in '.services += [.services[0]]' '.services[0].service = "unknown-provider"' '.services = []'; do
        jq "$filter" "$ONBOARD_SELECTION_TEST_HOME/report.before.json" > "$ONBOARD_SELECTION_TEST_HOME/report.json"
        helper_run_selection_onboard env ONBOARD_CREDENTIAL_FIXTURE="$ONBOARD_SELECTION_TEST_HOME/report.json" \
            bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" credential-status
        assert_failure
        [[ "$status" == 2 ]]
        printf '%s' "$output" | jq -e '.status == "error" and .error == "credential_capture_unavailable"' >/dev/null
        [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
    done
}

@test "onboard: no selected auth services produces an empty passive report" {
    helper_create_selection_runtime
    helper_write_selection_checkpoint '["acfs.onboard"]'

    helper_run_selection_onboard bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" credential-status
    assert_success
    printf '%s' "$output" | jq -e '.status == "pass" and .services == [] and .summary.required_unmet == 0' >/dev/null
    helper_run_selection_onboard bash -c '
        source "$1"
        has_gum() { return 1; }
        clear() { :; }
        get_auth_status_code() { printf "UNEXPECTED_PROVIDER_PROBE:%s\n" "$1" >&2; return 1; }
        show_auth_flow </dev/null
    ' _ "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh"
    assert_success
    refute_output --partial UNEXPECTED_PROVIDER_PROBE
    assert_output --partial 'No installed services currently need authentication.'
}

@test "onboard: direct excluded auth checks and instructions cannot bypass scope" {
    helper_create_selection_runtime
    helper_write_selection_checkpoint '["agents.codex","acfs.onboard"]'

    helper_run_selection_onboard bash -c '
        source "$1"
        onboard_runtime_binary_path() { printf "UNEXPECTED_BINARY_LOOKUP:%s\n" "$1" >&2; printf /usr/bin/true; }
        status=0
        check_auth_status vercel || status=$?
        [[ "$status" == 3 ]] || exit 1
        if show_auth_service vercel; then exit 1; fi
        printf "EXCLUDED_AUTH_REFUSED\n"
    ' _ "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh"
    assert_success
    assert_output --partial EXCLUDED_AUTH_REFUSED
    refute_output --partial UNEXPECTED_BINARY_LOOKUP
    refute_output --partial 'vercel login'
}

@test "onboard: direct auth helpers reload switched and replaced checkpoints" {
    helper_create_selection_runtime
    helper_write_selection_checkpoint '["agents.codex","acfs.onboard"]'
    jq '.module_selection.selected_modules = ["cloud.vercel","acfs.onboard"]' \
        "$ONBOARD_SELECTION_TEST_ACFS/state.json" > "$ONBOARD_SELECTION_TEST_HOME/next.json"

    helper_run_selection_onboard bash -c '
        source "$1"
        check_auth_status vercel && status=0 || status=$?
        [[ "$status" == 3 ]] || exit 1
        ACFS_STATE_FILE="$2"
        check_auth_status codex && status=0 || status=$?
        [[ "$status" == 3 ]] || exit 1
        printf "{invalid checkpoint\n" > "$ACFS_STATE_FILE"
        check_auth_status codex && status=0 || status=$?
        [[ "$status" == 4 ]] || exit 1
        if show_auth_service codex; then exit 1; fi
        printf "STALE_SCOPE_NOT_REUSED\n"
    ' _ "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" "$ONBOARD_SELECTION_TEST_HOME/next.json"
    assert_success
    assert_output --partial STALE_SCOPE_NOT_REUSED
    refute_output --partial 'codex login'
    [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
}

@test "onboard: selected missing agent stays visible and is not silently excluded" {
    helper_create_selection_runtime
    helper_write_selection_checkpoint '["agents.codex","acfs.onboard"]'

    helper_run_selection_onboard bash -c '
        source "$1"
        has_gum() { return 1; }
        clear() { :; }
        lookup_log="$2"
        onboard_runtime_binary_path() { printf "LOOKUP:%s\n" "$1" >> "$lookup_log"; return 1; }
        show_auth_flow </dev/null
        cat "$lookup_log"
    ' _ "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" "$ONBOARD_SELECTION_TEST_HOME/lookups.log"
    assert_success
    assert_output --partial 'LOOKUP:codex'
    assert_output --partial 'Codex CLI'
    refute_output --partial 'LOOKUP:claude'
    refute_output --partial 'LOOKUP:vercel'
}

@test "onboard: invalid scoped checkpoints refuse progress and auth before mutation" {
    helper_create_selection_runtime
    local invalid
    for invalid in malformed unknown foreign-home foreign-user empty duplicates unsupported; do
        helper_write_selection_checkpoint '["agents.codex","acfs.onboard"]'
        case "$invalid" in
            malformed) printf '{"module_selection":' > "$ONBOARD_SELECTION_TEST_ACFS/state.json" ;;
            *)
                local filter
                case "$invalid" in
                    unknown) filter='.module_selection.selected_modules = ["agents.unknown"]' ;;
                    foreign-home) filter='.target_home = "/home/another-installation"' ;;
                    foreign-user) filter='.target_user = "another-user"' ;;
                    empty) filter='.module_selection.selected_modules = []' ;;
                    duplicates) filter='.module_selection.selected_modules = ["agents.codex","agents.codex"]' ;;
                    unsupported) filter='.module_selection.schema_version = 2' ;;
                esac
                jq "$filter" "$ONBOARD_SELECTION_TEST_ACFS/state.json" > "$ONBOARD_SELECTION_TEST_HOME/$invalid.json"
                cp "$ONBOARD_SELECTION_TEST_HOME/$invalid.json" "$ONBOARD_SELECTION_TEST_ACFS/state.json"
                ;;
        esac
        cp "$ONBOARD_SELECTION_TEST_ACFS/state.json" "$ONBOARD_SELECTION_TEST_HOME/$invalid.before"
        helper_run_selection_onboard bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" status
        assert_failure
        [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
        [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/local_progress.json" ]]
        cmp -s "$ONBOARD_SELECTION_TEST_HOME/$invalid.before" "$ONBOARD_SELECTION_TEST_ACFS/state.json"
        helper_run_selection_onboard bash -c '
            source "$1"
            get_auth_status_code() { printf "UNEXPECTED_PROVIDER_PROBE\n"; }
            show_auth_flow </dev/null
        ' _ "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh"
        assert_failure
        refute_output --partial UNEXPECTED_PROVIDER_PROBE
    done
}

@test "onboard: explicit missing and foreign checkpoints never become legacy sessions" {
    helper_create_selection_runtime
    helper_write_selection_checkpoint '["agents.codex","acfs.onboard"]'
    jq '.target_home = "/home/other"' "$ONBOARD_SELECTION_TEST_ACFS/state.json" > "$ONBOARD_SELECTION_TEST_HOME/foreign.json"
    local checkpoint
    for checkpoint in "$ONBOARD_SELECTION_TEST_HOME/missing.json" "$ONBOARD_SELECTION_TEST_HOME/foreign.json" relative-state.json; do
        helper_run_selection_onboard env ACFS_STATE_FILE="$checkpoint" \
            bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" reset
        assert_failure
        [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
    done
}

@test "onboard: valid custom checkpoint is read without replacing the installation state" {
    helper_create_selection_runtime
    helper_write_selection_checkpoint '["agents.codex","acfs.onboard"]'
    cp "$ONBOARD_SELECTION_TEST_ACFS/state.json" "$ONBOARD_SELECTION_TEST_HOME/custom.json"
    helper_write_selection_checkpoint '["agents.claude","acfs.onboard"]'
    cp "$ONBOARD_SELECTION_TEST_ACFS/state.json" "$ONBOARD_SELECTION_TEST_HOME/state.before"

    helper_run_selection_onboard env ACFS_STATE_FILE="$ONBOARD_SELECTION_TEST_HOME/custom.json" \
        bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" credential-status
    assert_success
    printf '%s' "$output" | jq -e '[.services[].service] == ["codex"]' >/dev/null
    cmp -s "$ONBOARD_SELECTION_TEST_HOME/state.before" "$ONBOARD_SELECTION_TEST_ACFS/state.json"
    [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
}

@test "onboard: scoped catalogue is read as data and never executed" {
    helper_create_selection_runtime
    helper_write_selection_checkpoint '["agents.codex","acfs.onboard"]'
    printf '\nprintf UNEXPECTED_CATALOG_EXECUTION > "%s"\n' "$ONBOARD_SELECTION_TEST_HOME/catalog-executed" \
        >> "$ONBOARD_SELECTION_TEST_ACFS/scripts/generated/manifest_index.sh"

    helper_run_selection_onboard bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" status
    assert_success
    [[ ! -e "$ONBOARD_SELECTION_TEST_HOME/catalog-executed" ]]
    [[ -f "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
}

@test "onboard: missing or malformed scoped catalogues cannot hide selected failures" {
    helper_create_selection_runtime
    helper_write_selection_checkpoint '["agents.codex","acfs.onboard"]'
    mv "$ONBOARD_SELECTION_TEST_ACFS/scripts/generated/manifest_index.sh" "$ONBOARD_SELECTION_TEST_HOME/catalog.saved"
    helper_run_selection_onboard bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" status
    assert_failure
    [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]

    printf '%s\n' 'ACFS_MODULES_IN_ORDER=(' '  "agents.codex"' '  "agents.codex"' ')' \
        > "$ONBOARD_SELECTION_TEST_ACFS/scripts/generated/manifest_index.sh"
    helper_run_selection_onboard bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" status
    assert_failure
    [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
}

@test "onboard: state symlinks are rejected without progress or target changes" {
    helper_create_selection_runtime
    helper_write_selection_checkpoint '["agents.codex","acfs.onboard"]'
    mv "$ONBOARD_SELECTION_TEST_ACFS/state.json" "$ONBOARD_SELECTION_TEST_HOME/state-target.json"
    cp "$ONBOARD_SELECTION_TEST_HOME/state-target.json" "$ONBOARD_SELECTION_TEST_HOME/state.before"
    ln -s "$ONBOARD_SELECTION_TEST_HOME/state-target.json" "$ONBOARD_SELECTION_TEST_ACFS/state.json"

    helper_run_selection_onboard bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" status
    assert_failure
    cmp -s "$ONBOARD_SELECTION_TEST_HOME/state.before" "$ONBOARD_SELECTION_TEST_HOME/state-target.json"
    [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
}

@test "onboard: legacy installs retain all auth services with no new install checkpoint" {
    helper_create_selection_runtime
    local state_kind
    for state_kind in absent legacy; do
        if [[ "$state_kind" == legacy ]]; then
            printf '%s\n' '{"version":"0.1.0","completed_phases":[1,2]}' > "$ONBOARD_SELECTION_TEST_ACFS/state.json"
        fi
        helper_run_selection_onboard bash -c '
            source "$1"
            has_gum() { return 1; }
            clear() { :; }
            get_auth_status_code() { printf "PROBE:%s\n" "$1" >&2; printf "2\n"; }
            show_auth_flow </dev/null
        ' _ "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh"
        assert_success
        local service
        for service in tailscale claude codex antigravity github vercel supabase cloudflare; do
            assert_output --partial "PROBE:$service"
        done
        [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
        if [[ "$state_kind" == absent ]]; then [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/state.json" ]]; fi
    done
}

@test "onboard: relocated legacy defaults retain their home but scoped and custom checkpoints bind the owner" {
    helper_create_selection_runtime
    local relocated_home="$BATS_TEST_TMPDIR/legacy-user"
    mkdir -p "$relocated_home/.codex" "$relocated_home/.local/bin"
    printf '#!/bin/bash\nexit 0\n' > "$relocated_home/.local/bin/codex"
    chmod +x "$relocated_home/.local/bin/codex"
    printf '%s\n' '{"tokens":{"access_token":"legacy-relocation-fixture"}}' > "$relocated_home/.codex/auth.json"
    jq -n --arg home "$relocated_home" --arg user "$(id -un)" \
        '{version:"0.1.0",target_home:$home,target_user:$user}' > "$ONBOARD_SELECTION_TEST_ACFS/state.json"
    cp "$ONBOARD_SELECTION_TEST_ACFS/state.json" "$ONBOARD_SELECTION_TEST_HOME/relocated.json"

    helper_run_selection_onboard bash -c '
        source "$1"
        check_auth_status codex || exit 1
        [[ "$_ONBOARD_SELECTION_TARGET_HOME" == "$2" ]]
    ' _ "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" "$relocated_home"
    assert_success
    helper_run_selection_onboard bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" credential-status
    assert_success
    printf '%s' "$output" | jq -e '(.services | length) == 6 and
        any(.services[]; .service == "codex" and .state == "file_configured")' >/dev/null
    cmp -s "$ONBOARD_SELECTION_TEST_ACFS/state.json" "$ONBOARD_SELECTION_TEST_HOME/relocated.json"

    helper_run_selection_onboard env ACFS_STATE_FILE="$ONBOARD_SELECTION_TEST_HOME/relocated.json" \
        bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" status
    assert_failure
    jq '.module_selection = {schema_version:1,selected_modules:["agents.codex","acfs.onboard"]}' \
        "$ONBOARD_SELECTION_TEST_HOME/relocated.json" > "$ONBOARD_SELECTION_TEST_ACFS/state.json"
    helper_run_selection_onboard bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" status
    assert_failure
    [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
    [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/local_progress.json" ]]
}

@test "onboard: invalid selection still permits help but preserves the credential CLI flag contract" {
    helper_create_selection_runtime
    printf '{"module_selection":' > "$ONBOARD_SELECTION_TEST_ACFS/state.json"

    helper_run_selection_onboard bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" --help
    assert_success
    assert_output --partial 'ACFS Onboarding Tutorial'
    helper_run_selection_onboard bash "$ONBOARD_SELECTION_TEST_ACFS/onboard/onboard.sh" credential-status --require codex
    assert_failure
    [[ "$status" == 2 ]]
    assert_output --partial 'does not accept setup or requirement flags'
    [[ ! -e "$ONBOARD_SELECTION_TEST_ACFS/onboard_progress.json" ]]
}
