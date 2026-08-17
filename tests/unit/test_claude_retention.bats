#!/usr/bin/env bats
#
# Claude Code session retention at install (issue #330).
#
# Claude Code deletes session transcripts older than cleanupPeriodDays
# (default 30) with no warning; ACFS must set an explicit high value at
# install so cass can index history before it is pruned. These tests
# exercise the exact jq merge filter shipped in install.sh: the key is
# added when absent and NEVER overrides a user-set value.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    INSTALL_SH="$PROJECT_ROOT/install.sh"

    command -v jq >/dev/null 2>&1 || skip "jq not available"

    # Load the shipped constants (single-line assignments) from install.sh so
    # the tests exercise exactly what the installer runs.
    eval "$(grep '^ACFS_CLAUDE_RETENTION_DAYS=' "$INSTALL_SH")"
    eval "$(grep '^ACFS_CLAUDE_RETENTION_JQ_FILTER=' "$INSTALL_SH")"
    [[ -n "$ACFS_CLAUDE_RETENTION_DAYS" ]]
    [[ -n "$ACFS_CLAUDE_RETENTION_JQ_FILTER" ]]
}

@test "retention merge adds cleanupPeriodDays when absent" {
    run jq -c "$ACFS_CLAUDE_RETENTION_JQ_FILTER" <<< '{}'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "{\"cleanupPeriodDays\":$ACFS_CLAUDE_RETENTION_DAYS}" ]]
}

@test "retention merge preserves existing settings keys" {
    run jq -c "$ACFS_CLAUDE_RETENTION_JQ_FILTER" \
        <<< '{"skipDangerousModePermissionPrompt":true}'
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"skipDangerousModePermissionPrompt":true'* ]]
    [[ "$output" == *"\"cleanupPeriodDays\":$ACFS_CLAUDE_RETENTION_DAYS"* ]]
}

@test "retention merge respects a user-set cleanupPeriodDays" {
    run jq -c "$ACFS_CLAUDE_RETENTION_JQ_FILTER" <<< '{"cleanupPeriodDays":30}'
    [[ "$status" -eq 0 ]]
    [[ "$output" == '{"cleanupPeriodDays":30}' ]]
}

@test "retention merge respects a user-set zero value" {
    run jq -c "$ACFS_CLAUDE_RETENTION_JQ_FILTER" <<< '{"cleanupPeriodDays":0}'
    [[ "$status" -eq 0 ]]
    [[ "$output" == '{"cleanupPeriodDays":0}' ]]
}

@test "retention merge is idempotent" {
    local once=""
    once="$(jq -c "$ACFS_CLAUDE_RETENTION_JQ_FILTER" <<< '{}')"
    run jq -c "$ACFS_CLAUDE_RETENTION_JQ_FILTER" <<< "$once"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$once" ]]
}

@test "retention value keeps the cleanup mechanism available (finite integer)" {
    # A high explicit value, not a removal of the mechanism.
    [[ "$ACFS_CLAUDE_RETENTION_DAYS" =~ ^[0-9]+$ ]]
    [[ "$ACFS_CLAUDE_RETENTION_DAYS" -ge 3650 ]]
}

@test "installer applies retention outside the vibe-mode guard" {
    # The retention block must run for every mode; transcript loss is not
    # vibe-specific. Marker comment lives directly on the block.
    run grep -F 'Applies to EVERY mode' "$INSTALL_SH"
    [[ "$status" -eq 0 ]]
}

@test "installer create-if-absent path writes cleanupPeriodDays" {
    run grep -F '"cleanupPeriodDays": $ACFS_CLAUDE_RETENTION_DAYS' "$INSTALL_SH"
    [[ "$status" -eq 0 ]]
}
