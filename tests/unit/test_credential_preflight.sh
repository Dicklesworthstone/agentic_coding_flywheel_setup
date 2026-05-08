#!/usr/bin/env bash
# ============================================================
# Unit tests for ACFS credential/environment preflight
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CREDENTIAL_PREFLIGHT_SH="$REPO_ROOT/scripts/lib/credential_preflight.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_CREDENTIAL_PREFLIGHT_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-credential-preflight-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

mkdir -p "$ARTIFACT_DIR"

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    [[ -n "${2:-}" ]] && echo "  Reason: $2"
}

write_fixture() {
    local path="$1"
    local body="$2"

    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$body" > "$path"
}

assert_category_present() {
    local json_file="$1"
    local category="$2"

    jq -e --arg category "$category" '.findings[] | select(.category == $category)' "$json_file" >/dev/null
}

assert_no_raw_secret() {
    local json_file="$1"
    local secret="$2"

    ! grep -Fq "$secret" "$json_file"
}

assert_file_no_raw_secret() {
    local file_path="$1"
    local secret="$2"

    ! grep -Fq "$secret" "$file_path"
}

test_detects_common_fake_secret_shapes_without_printing_values() {
    local fixture="$ARTIFACT_DIR/common/.zshrc"
    local output="$ARTIFACT_DIR/common.json"

    write_fixture "$fixture" 'OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz1234567890
GITHUB_TOKEN=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.examplepayload.signaturevalue
DATABASE_URL=postgres://acfs:supersecret@db.example.test/app
'

    if bash "$CREDENTIAL_PREFLIGHT_SH" --json --file "$fixture" > "$output"; then
        return 1
    fi

    assert_category_present "$output" "api_key" || return 1
    assert_category_present "$output" "github_token" || return 1
    assert_category_present "$output" "aws_key" || return 1
    assert_category_present "$output" "bearer_token" || return 1
    assert_category_present "$output" "credential_url" || return 1
    assert_no_raw_secret "$output" "sk-abcdefghijklmnopqrstuvwxyz1234567890" || return 1
    assert_no_raw_secret "$output" "supersecret" || return 1
    jq -e '.safety.raw_secret_values_printed == false and .safety.user_files_mutated == false' "$output" >/dev/null || return 1

    pass "detects_common_fake_secret_shapes_without_printing_values"
}

test_secret_matrix_detects_categories_without_value_leaks() {
    local fixture="$ARTIFACT_DIR/matrix/.env"
    local json_output="$ARTIFACT_DIR/matrix.json"
    local human_output="$ARTIFACT_DIR/matrix.human"
    local secret=""

    write_fixture "$fixture" 'OPENAI_API_KEY=sk-fakeacfscredentialmatrix000001
GITHUB_TOKEN=ghp_FAKEACFSCREDENTIALMATRIX0000000001
GITHUB_FINE=github_pat_FAKEACFSMATRIX_123456789012345678901234
VAULT_TOKEN=hvs.FAKEACFSCREDENTIALMATRIX001
SLACK_BOT_TOKEN=xoxb-fake-acfs-credential-matrix
Authorization: Bearer fakeacfscredentialmatrixbearer001
SESSION_JWT=eyJfakeacfsmatrix.eyJfakeacfsmatrix.fakeacfsmatrixsig
DATABASE_URL=postgres://acfs:fake-matrix-password@app.example.invalid/db
DB_PASSWORD=fake-matrix-password-002
'

    if bash "$CREDENTIAL_PREFLIGHT_SH" --json --file "$fixture" > "$json_output"; then
        return 1
    fi
    if bash "$CREDENTIAL_PREFLIGHT_SH" --file "$fixture" > "$human_output"; then
        return 1
    fi

    for category in api_key github_token github_pat vault_token slack_token bearer_token jwt credential_url generic_secret; do
        assert_category_present "$json_output" "$category" || return 1
        grep -Fq "$category" "$human_output" || return 1
    done

    for secret in \
        "sk-fakeacfscredentialmatrix000001" \
        "ghp_FAKEACFSCREDENTIALMATRIX0000000001" \
        "github_pat_FAKEACFSMATRIX_123456789012345678901234" \
        "hvs.FAKEACFSCREDENTIALMATRIX001" \
        "xoxb-fake-acfs-credential-matrix" \
        "fakeacfscredentialmatrixbearer001" \
        "eyJfakeacfsmatrix.eyJfakeacfsmatrix.fakeacfsmatrixsig" \
        "fake-matrix-password"
    do
        assert_file_no_raw_secret "$json_output" "$secret" || return 1
        assert_file_no_raw_secret "$human_output" "$secret" || return 1
    done

    jq -e '
      .status == "warn" and
      .summary.findings >= 9 and
      .safety.raw_secret_values_printed == false and
      .safety.raw_snippets_printed == false and
      .safety.user_files_mutated == false
    ' "$json_output" >/dev/null || return 1

    pass "secret_matrix_detects_categories_without_value_leaks"
}

test_detects_private_key_marker() {
    local fixture="$ARTIFACT_DIR/private-key/id_rsa.log"
    local output="$ARTIFACT_DIR/private-key.json"

    write_fixture "$fixture" 'before
-----BEGIN OPENSSH PRIVATE KEY-----
not-real-key-material
-----END OPENSSH PRIVATE KEY-----
after
'

    if bash "$CREDENTIAL_PREFLIGHT_SH" --json --file "$fixture" > "$output"; then
        return 1
    fi

    assert_category_present "$output" "private_key" || return 1
    assert_no_raw_secret "$output" "not-real-key-material" || return 1

    pass "detects_private_key_marker"
}

test_benign_examples_pass() {
    local fixture="$ARTIFACT_DIR/benign/.env"
    local output="$ARTIFACT_DIR/benign.json"
    local human_output="$ARTIFACT_DIR/benign.human"

    write_fixture "$fixture" 'GITHUB_TOKEN=your-token-here
OPENAI_API_KEY=<REDACTED:api_key>
git_sha=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
version=1.2.3
PASSWORD=abc
'

    bash "$CREDENTIAL_PREFLIGHT_SH" --json --file "$fixture" > "$output" || return 1
    jq -e '.status == "pass" and .summary.findings == 0 and .summary.files_scanned == 1' "$output" >/dev/null || return 1
    bash "$CREDENTIAL_PREFLIGHT_SH" --file "$fixture" > "$human_output" || return 1
    grep -Fq "PASS: credential preflight" "$human_output" || return 1

    pass "benign_examples_pass"
}

test_binary_and_unreadable_files_are_skipped() {
    local binary_file="$ARTIFACT_DIR/skipped/binary.bin"
    local unreadable_file="$ARTIFACT_DIR/skipped/unreadable.env"
    local output="$ARTIFACT_DIR/skipped.json"

    mkdir -p "$(dirname "$binary_file")"
    printf 'abc\0def\n' > "$binary_file"
    printf 'GITHUB_TOKEN=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn\n' > "$unreadable_file"
    chmod 000 "$unreadable_file"

    bash "$CREDENTIAL_PREFLIGHT_SH" --json --file "$binary_file" --file "$unreadable_file" > "$output" || return 1
    jq -e '
      .status == "pass" and
      .summary.findings == 0 and
      (.skipped_files[] | select(.reason == "binary")) and
      (.skipped_files[] | select(.reason == "unreadable"))
    ' "$output" >/dev/null || return 1
    assert_no_raw_secret "$output" "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" || return 1

    pass "binary_and_unreadable_files_are_skipped"
}

test_excluded_paths_are_opted_out() {
    local fixture="$ARTIFACT_DIR/excluded/.env"
    local output="$ARTIFACT_DIR/excluded.json"

    write_fixture "$fixture" 'GITHUB_TOKEN=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn'

    bash "$CREDENTIAL_PREFLIGHT_SH" --json --file "$fixture" --exclude "$fixture" > "$output" || return 1
    jq -e '
      .status == "pass" and
      .summary.findings == 0 and
      (.skipped_files[] | select(.reason == "excluded_by_option"))
    ' "$output" >/dev/null || return 1
    assert_no_raw_secret "$output" "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" || return 1

    pass "excluded_paths_are_opted_out"
}

test_default_scan_covers_shell_history_and_acfs_state() {
    local home_dir="$ARTIFACT_DIR/default-home"
    local acfs_home="$home_dir/.acfs"
    local output="$ARTIFACT_DIR/default.json"

    mkdir -p "$acfs_home"
    write_fixture "$home_dir/.zsh_history" 'export SLACK_BOT_TOKEN=xoxb-123456789012-abcdefghijkl'
    write_fixture "$acfs_home/state.json" '{"access_token":"realistic-token-value-12345"}'

    if bash "$CREDENTIAL_PREFLIGHT_SH" --json --home "$home_dir" --acfs-home "$acfs_home" > "$output"; then
        return 1
    fi

    assert_category_present "$output" "slack_token" || return 1
    assert_category_present "$output" "generic_secret" || return 1
    jq -e '
      (.findings[] | select(.source == "shell_history")) and
      (.findings[] | select(.source == "acfs_state"))
    ' "$output" >/dev/null || return 1
    assert_no_raw_secret "$output" "realistic-token-value-12345" || return 1

    pass "default_scan_covers_shell_history_and_acfs_state"
}

run_test() {
    local name="$1"

    if "$name"; then
        return 0
    fi

    fail "$name" "see $ARTIFACT_DIR for fixtures and outputs"
}

main() {
    run_test test_detects_common_fake_secret_shapes_without_printing_values
    run_test test_secret_matrix_detects_categories_without_value_leaks
    run_test test_detects_private_key_marker
    run_test test_benign_examples_pass
    run_test test_binary_and_unreadable_files_are_skipped
    run_test test_excluded_paths_are_opted_out
    run_test test_default_scan_covers_shell_history_and_acfs_state

    echo ""
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
