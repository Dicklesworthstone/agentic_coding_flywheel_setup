#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
# ============================================================
# Test script for security.sh
# Run: bash scripts/lib/test_security.sh
#
# Tests non-network functions locally. Network functions tested
# with local file:// URLs where possible.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source required files
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/security.sh"

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

# Create temp directory for test fixtures
setup_fixtures() {
    TEST_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/acfs_test_security.XXXXXX")
    trap 'rm -rf "$TEST_TMP_DIR"' EXIT

    # Create a simple test script
    echo '#!/bin/bash
echo "Hello from test script"' > "$TEST_TMP_DIR/test_script.sh"

    # Create a test checksums.yaml
    cat > "$TEST_TMP_DIR/checksums.yaml" << 'EOF'
# Test checksums file
installers:
  test_tool:
    url: "https://example.com/install.sh"
    sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  another_tool:
    url: "https://example.com/another.sh"
    sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
EOF
}

STRICT_HASH_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
STRICT_HASH_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
STRICT_HASH_C="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
STRICT_HASH_D="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

write_strict_policy_fixture() {
    local destination="$1"
    local alpha_hash="$2"
    local beta_hash="$3"
    local beta_url="${4:-https://example.com/beta.sh}"

    cat > "$destination" << EOF
# checksums.yaml - Auto-generated 2026-08-24T12:00:00Z
# Run: ./scripts/lib/security.sh --update-checksums

installers:
  alpha:
    url: "https://example.com/alpha.sh"
    sha256: "$alpha_hash"

  beta:
    url: "$beta_url"
    sha256: "$beta_hash"
EOF
}

write_strict_mismatch_report_fixture() {
    local destination="$1"
    local policy_digest="$2"
    local beta_actual="$3"

    cat > "$destination" << EOF
{"schema":"acfs.installer-checksum-verification.v1","schemaVersion":1,"timestamp":"2026-08-24T16:00:00Z","checksumsYamlSha256":"$policy_digest","total":2,"matches":[{"name":"alpha","url":"https://example.com/alpha.sh","checksum":"$STRICT_HASH_A"}],"mismatches":[{"name":"beta","url":"https://example.com/beta.sh","expected":"$STRICT_HASH_B","actual":"$beta_actual"}],"errors":[],"skipped":[]}
EOF
}

write_strict_error_report_fixture() {
    local destination="$1"
    local policy_digest="$2"

    cat > "$destination" << EOF
{"schema":"acfs.installer-checksum-verification.v1","schemaVersion":1,"timestamp":"2026-08-24T16:00:00Z","checksumsYamlSha256":"$policy_digest","total":2,"matches":[{"name":"alpha","url":"https://example.com/alpha.sh","checksum":"$STRICT_HASH_A"}],"mismatches":[],"errors":[{"name":"beta","url":"https://example.com/beta.sh","error":"upstream unavailable"}],"skipped":[]}
EOF
}

# ============================================================
# Test Cases: HTTPS Enforcement
# ============================================================

test_is_https_valid() {
    local name="is_https returns true for HTTPS URLs"

    if is_https "https://example.com/install.sh"; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_is_https_invalid() {
    local name="is_https returns false for HTTP URLs"

    if ! is_https "http://example.com/install.sh"; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_is_https_ftp() {
    local name="is_https returns false for FTP URLs"

    if ! is_https "ftp://example.com/file"; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_enforce_https_valid() {
    local name="enforce_https passes for HTTPS URLs"

    if enforce_https "https://example.com/install.sh" "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_enforce_https_invalid() {
    local name="enforce_https fails for HTTP URLs"

    if ! enforce_https "http://example.com/install.sh" "test" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

# ============================================================
# Test Cases: SHA256 Calculation
# ============================================================

test_calculate_sha256_empty() {
    local name="calculate_sha256 handles empty input"

    # SHA256 of empty string
    local expected="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    local actual

    actual=$(printf '' | calculate_sha256)

    if [[ "$actual" == "$expected" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected: $expected, Got: $actual"
    fi
}

test_calculate_sha256_known_value() {
    local name="calculate_sha256 produces correct hash for known input"

    # SHA256 of "abc"
    local expected="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    local actual

    actual=$(printf 'abc' | calculate_sha256)

    if [[ "$actual" == "$expected" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected: $expected, Got: $actual"
    fi
}

test_calculate_sha256_with_newline() {
    local name="calculate_sha256 handles content with newlines"

    # SHA256 of "hello\n" (with trailing newline)
    local expected="5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
    local actual

    actual=$(printf 'hello\n' | calculate_sha256)

    if [[ "$actual" == "$expected" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected: $expected, Got: $actual"
    fi
}

# ============================================================
# Test Cases: Checksums File Loading
# ============================================================

test_load_checksums_file_not_found() {
    local name="load_checksums fails gracefully for missing file"

    if ! load_checksums "/nonexistent/file.yaml" 2>/dev/null; then
        test_pass "$name"
    else
        test_fail "$name" "Should fail for missing file"
    fi
}

test_load_checksums_parses_correctly() {
    local name="load_checksums parses YAML correctly"
    setup_fixtures

    # Clear existing checksums
    LOADED_CHECKSUMS=()

    load_checksums "$TEST_TMP_DIR/checksums.yaml" 2>/dev/null

    local test_checksum="${LOADED_CHECKSUMS[test_tool]:-}"
    local expected="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    if [[ "$test_checksum" == "$expected" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected: $expected, Got: $test_checksum"
    fi
}

test_load_checksums_multiple_tools() {
    local name="load_checksums loads multiple tools"
    setup_fixtures

    # Clear existing checksums
    LOADED_CHECKSUMS=()

    load_checksums "$TEST_TMP_DIR/checksums.yaml" 2>/dev/null

    local count=0
    for key in "${!LOADED_CHECKSUMS[@]}"; do
        ((++count))
    done

    if [[ $count -eq 2 ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected 2 tools, Got: $count"
    fi
}

test_get_checksum_existing() {
    local name="get_checksum returns correct value for existing tool"
    setup_fixtures

    LOADED_CHECKSUMS=()
    load_checksums "$TEST_TMP_DIR/checksums.yaml" 2>/dev/null

    local result
    result=$(get_checksum "test_tool")
    local expected="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    if [[ "$result" == "$expected" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected: $expected, Got: $result"
    fi
}

test_get_checksum_missing() {
    local name="get_checksum returns empty for missing tool"
    setup_fixtures

    LOADED_CHECKSUMS=()
    load_checksums "$TEST_TMP_DIR/checksums.yaml" 2>/dev/null

    local result
    result=$(get_checksum "nonexistent_tool")

    if [[ -z "$result" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected empty, Got: $result"
    fi
}

# ============================================================
# Test Cases: Strict Checksum Evidence Boundary
# ============================================================

test_strict_checksums_parser_accepts_canonical_closed_world() {
    local name="strict checksum parser accepts the canonical closed-world policy"
    local -a saved_required=("${ACFS_SECURITY_REQUIRED_INSTALLERS[@]}")
    local -A parsed_urls=()
    local -A parsed_checksums=()
    local policy="$TEST_TMP_DIR/strict-current.yaml"
    local passed=false

    ACFS_SECURITY_REQUIRED_INSTALLERS=(alpha beta)
    write_strict_policy_fixture "$policy" "$STRICT_HASH_A" "$STRICT_HASH_B"
    if acfs_load_checksums_strict "$policy" parsed_urls parsed_checksums 2>/dev/null \
        && [[ "${#parsed_urls[@]}" -eq 2 ]] \
        && [[ "${parsed_urls[alpha]:-}" == "https://example.com/alpha.sh" ]] \
        && [[ "${parsed_checksums[beta]:-}" == "$STRICT_HASH_B" ]]; then
        passed=true
    fi
    ACFS_SECURITY_REQUIRED_INSTALLERS=("${saved_required[@]}")

    if [[ "$passed" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Canonical policy was not parsed and bound exactly"
    fi
}

test_strict_checksums_parser_rejects_noncanonical_mutations_transactionally() {
    local name="strict checksum parser rejects sort/case mutations without clobbering trusted state"
    local -a saved_required=("${ACFS_SECURITY_REQUIRED_INSTALLERS[@]}")
    local -A parsed_urls=([trusted]="https://trusted.example/install.sh")
    local -A parsed_checksums=([trusted]="$STRICT_HASH_D")
    local policy="$TEST_TMP_DIR/strict-mutated.yaml"
    local passed=false

    ACFS_SECURITY_REQUIRED_INSTALLERS=(alpha beta)
    cat > "$policy" << EOF
# checksums.yaml - Auto-generated 2026-08-24T12:00:00Z
# Run: ./scripts/lib/security.sh --update-checksums

installers:
  beta:
    url: "https://example.com/beta.sh"
    sha256: "$STRICT_HASH_B"

  alpha:
    url: "https://example.com/alpha.sh"
    sha256: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
EOF
    if ! acfs_load_checksums_strict "$policy" parsed_urls parsed_checksums 2>/dev/null \
        && [[ "${#parsed_urls[@]}" -eq 1 ]] \
        && [[ "${parsed_urls[trusted]:-}" == "https://trusted.example/install.sh" ]] \
        && [[ "${parsed_checksums[trusted]:-}" == "$STRICT_HASH_D" ]]; then
        passed=true
    fi
    ACFS_SECURITY_REQUIRED_INSTALLERS=("${saved_required[@]}")

    if [[ "$passed" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "A malformed policy was accepted or partially committed"
    fi
}

test_strict_checksums_parser_rejects_incomplete_set_and_extra_syntax() {
    local name="strict checksum parser rejects incomplete policy and non-canonical syntax"
    local -a saved_required=("${ACFS_SECURITY_REQUIRED_INSTALLERS[@]}")
    local -A parsed_urls=()
    local -A parsed_checksums=()
    local policy="$TEST_TMP_DIR/strict-incomplete.yaml"
    local passed=false

    ACFS_SECURITY_REQUIRED_INSTALLERS=(alpha beta)
    cat > "$policy" << EOF
# checksums.yaml - Auto-generated 2026-08-24T12:00:00Z
# Run: ./scripts/lib/security.sh --update-checksums

installers:
  alpha:
    url: "https://example.com/alpha.sh"
    sha256: "$STRICT_HASH_A"
unexpected: true
EOF
    if ! acfs_load_checksums_strict "$policy" parsed_urls parsed_checksums 2>/dev/null; then
        passed=true
    fi
    ACFS_SECURITY_REQUIRED_INSTALLERS=("${saved_required[@]}")

    if [[ "$passed" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Incomplete or augmented policy was accepted"
    fi
}

test_strict_checksums_parser_rejects_byte_boundary_smuggling() {
    local name="strict checksum parser rejects erased NULs and missing final newline"
    local -a saved_required=("${ACFS_SECURITY_REQUIRED_INSTALLERS[@]}")
    local -A parsed_urls=()
    local -A parsed_checksums=()
    local policy="$TEST_TMP_DIR/strict-nul.yaml"
    local unterminated_policy="$TEST_TMP_DIR/strict-unterminated.yaml"
    local policy_without_final_newline=""
    local passed=false

    ACFS_SECURITY_REQUIRED_INSTALLERS=(alpha beta)
    write_strict_policy_fixture "$policy" "$STRICT_HASH_A" "$STRICT_HASH_B"
    printf '\0' >> "$policy"
    write_strict_policy_fixture "$unterminated_policy" "$STRICT_HASH_A" "$STRICT_HASH_B"
    policy_without_final_newline="$(acfs_security_cat_file "$unterminated_policy")"
    printf '%s' "$policy_without_final_newline" > "$unterminated_policy"
    if ! acfs_load_checksums_strict "$policy" parsed_urls parsed_checksums 2>/dev/null \
        && ! acfs_load_checksums_strict "$unterminated_policy" parsed_urls parsed_checksums 2>/dev/null; then
        passed=true
    fi
    ACFS_SECURITY_REQUIRED_INSTALLERS=("${saved_required[@]}")

    if [[ "$passed" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "A byte-mutated policy was normalized and accepted"
    fi
}

test_versioned_checksum_report_binds_urls_hashes_and_exit_status() {
    local name="versioned checksum report binds URLs/hashes and returns nonzero on mismatch"
    local -A urls=(
        [alpha]="https://example.com/alpha.sh"
        [beta]="https://example.com/beta.sh"
    )
    local -A checksums=(
        [alpha]="$STRICT_HASH_A"
        [beta]="$STRICT_HASH_B"
    )
    local report=""
    local status=0
    local passed=false

    fetch_checksum() {
        case "$1" in
            https://example.com/alpha.sh) printf '%s\n' "$STRICT_HASH_A" ;;
            https://example.com/beta.sh) printf '%s\n' "$STRICT_HASH_C" ;;
            *) return 1 ;;
        esac
    }
    if report="$(verify_all_installers_json "$STRICT_HASH_D" urls checksums 2>/dev/null)"; then
        status=0
    else
        status=$?
    fi

    if [[ "$status" -eq 1 && "$report" != *$'\n'* ]] \
        && printf '%s\n' "$report" | jq -e --arg digest "$STRICT_HASH_D" \
            '.schema == "acfs.installer-checksum-verification.v1"
             and .schemaVersion == 1
             and .checksumsYamlSha256 == $digest
             and .total == 2
             and (.matches == [{"name":"alpha","url":"https://example.com/alpha.sh","checksum":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}])
             and (.mismatches == [{"name":"beta","url":"https://example.com/beta.sh","expected":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","actual":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}])
             and (.errors | length) == 0
             and (.skipped | length) == 0' >/dev/null; then
        passed=true
    fi

    if [[ "$passed" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Report lost a policy binding or returned a false-green status"
    fi
}

test_checksum_candidate_validation_is_exact_and_network_free() {
    local name="checksum candidate proof emits exact reviewed bytes without network access"
    local -a saved_required=("${ACFS_SECURITY_REQUIRED_INSTALLERS[@]}")
    local current="$TEST_TMP_DIR/candidate-current.yaml"
    local candidate="$TEST_TMP_DIR/candidate-good.yaml"
    local report="$TEST_TMP_DIR/candidate-report.json"
    local network_marker="$TEST_TMP_DIR/candidate-network-called"
    local current_digest=""
    local validated=""
    local expected=""
    local passed=false

    ACFS_SECURITY_REQUIRED_INSTALLERS=(alpha beta)
    write_strict_policy_fixture "$current" "$STRICT_HASH_A" "$STRICT_HASH_B"
    write_strict_policy_fixture "$candidate" "$STRICT_HASH_A" "$STRICT_HASH_C"
    current_digest="$(calculate_file_sha256 "$current")"
    write_strict_mismatch_report_fixture "$report" "$current_digest" "$STRICT_HASH_C"
    fetch_checksum() {
        printf 'network path was invoked\n' > "$network_marker"
        return 99
    }

    if validated="$(acfs_validate_checksum_candidate "$current" "$candidate" "$report" 2>/dev/null)"; then
        expected="$(acfs_security_cat_file "$candidate")"
        if [[ "$validated" == "$expected" && ! -e "$network_marker" ]]; then
            passed=true
        fi
    fi
    ACFS_SECURITY_REQUIRED_INSTALLERS=("${saved_required[@]}")

    if [[ "$passed" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Candidate proof changed bytes, failed valid evidence, or invoked the network"
    fi
}

test_checksum_candidate_validation_rejects_cross_wired_hashes() {
    local name="checksum candidate proof rejects matched and mismatched hash cross-wiring"
    local -a saved_required=("${ACFS_SECURITY_REQUIRED_INSTALLERS[@]}")
    local current="$TEST_TMP_DIR/crosswire-current.yaml"
    local changed_match="$TEST_TMP_DIR/crosswire-match.yaml"
    local wrong_actual="$TEST_TMP_DIR/crosswire-actual.yaml"
    local report="$TEST_TMP_DIR/crosswire-report.json"
    local current_digest=""
    local passed=false

    ACFS_SECURITY_REQUIRED_INSTALLERS=(alpha beta)
    write_strict_policy_fixture "$current" "$STRICT_HASH_A" "$STRICT_HASH_B"
    write_strict_policy_fixture "$changed_match" "$STRICT_HASH_D" "$STRICT_HASH_C"
    write_strict_policy_fixture "$wrong_actual" "$STRICT_HASH_A" "$STRICT_HASH_D"
    current_digest="$(calculate_file_sha256 "$current")"
    write_strict_mismatch_report_fixture "$report" "$current_digest" "$STRICT_HASH_C"

    if ! acfs_validate_checksum_candidate "$current" "$changed_match" "$report" >/dev/null 2>&1 \
        && ! acfs_validate_checksum_candidate "$current" "$wrong_actual" "$report" >/dev/null 2>&1; then
        passed=true
    fi
    ACFS_SECURITY_REQUIRED_INSTALLERS=("${saved_required[@]}")

    if [[ "$passed" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "A candidate changed a matched tool or substituted an unobserved digest"
    fi
}

test_checksum_candidate_validation_rejects_url_drift_and_incomplete_evidence() {
    local name="checksum candidate proof rejects URL drift and error-bearing evidence"
    local -a saved_required=("${ACFS_SECURITY_REQUIRED_INSTALLERS[@]}")
    local current="$TEST_TMP_DIR/boundary-current.yaml"
    local url_drift="$TEST_TMP_DIR/boundary-url.yaml"
    local candidate="$TEST_TMP_DIR/boundary-candidate.yaml"
    local mismatch_report="$TEST_TMP_DIR/boundary-mismatch.json"
    local error_report="$TEST_TMP_DIR/boundary-error.json"
    local current_digest=""
    local passed=false

    ACFS_SECURITY_REQUIRED_INSTALLERS=(alpha beta)
    write_strict_policy_fixture "$current" "$STRICT_HASH_A" "$STRICT_HASH_B"
    write_strict_policy_fixture "$url_drift" "$STRICT_HASH_A" "$STRICT_HASH_C" "https://mirror.example/beta.sh"
    write_strict_policy_fixture "$candidate" "$STRICT_HASH_A" "$STRICT_HASH_C"
    current_digest="$(calculate_file_sha256 "$current")"
    write_strict_mismatch_report_fixture "$mismatch_report" "$current_digest" "$STRICT_HASH_C"
    write_strict_error_report_fixture "$error_report" "$current_digest"

    if ! acfs_validate_checksum_candidate "$current" "$url_drift" "$mismatch_report" >/dev/null 2>&1 \
        && ! acfs_validate_checksum_candidate "$current" "$candidate" "$error_report" >/dev/null 2>&1; then
        passed=true
    fi
    ACFS_SECURITY_REQUIRED_INSTALLERS=("${saved_required[@]}")

    if [[ "$passed" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "URL drift or incomplete verification evidence authorized a candidate"
    fi
}

test_checksum_report_rejects_duplicate_keys_and_policy_digest_drift() {
    local name="checksum report rejects duplicate JSON keys and stale policy digests"
    local -a saved_required=("${ACFS_SECURITY_REQUIRED_INSTALLERS[@]}")
    local current="$TEST_TMP_DIR/report-current.yaml"
    local candidate="$TEST_TMP_DIR/report-candidate.yaml"
    local duplicate_report="$TEST_TMP_DIR/report-duplicate.json"
    local stale_report="$TEST_TMP_DIR/report-stale.json"
    local current_digest=""
    local passed=false

    ACFS_SECURITY_REQUIRED_INSTALLERS=(alpha beta)
    write_strict_policy_fixture "$current" "$STRICT_HASH_A" "$STRICT_HASH_B"
    write_strict_policy_fixture "$candidate" "$STRICT_HASH_A" "$STRICT_HASH_C"
    current_digest="$(calculate_file_sha256 "$current")"
    write_strict_mismatch_report_fixture "$stale_report" "$STRICT_HASH_D" "$STRICT_HASH_C"
    cat > "$duplicate_report" << EOF
{"schema":"acfs.installer-checksum-verification.v1","schemaVersion":1,"timestamp":"2026-08-24T16:00:00Z","checksumsYamlSha256":"$current_digest","total":2,"matches":[],"matches":[{"name":"alpha","url":"https://example.com/alpha.sh","checksum":"$STRICT_HASH_A"}],"mismatches":[{"name":"beta","url":"https://example.com/beta.sh","expected":"$STRICT_HASH_B","actual":"$STRICT_HASH_C"}],"errors":[],"skipped":[]}
EOF

    if ! acfs_validate_checksum_candidate "$current" "$candidate" "$duplicate_report" >/dev/null 2>&1 \
        && ! acfs_validate_checksum_candidate "$current" "$candidate" "$stale_report" >/dev/null 2>&1; then
        passed=true
    fi
    ACFS_SECURITY_REQUIRED_INSTALLERS=("${saved_required[@]}")

    if [[ "$passed" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Duplicate-key or stale-digest evidence was accepted"
    fi
}

# ============================================================
# Test Cases: Mismatch Recording
# ============================================================

test_record_checksum_mismatch() {
    local name="record_checksum_mismatch adds entry"

    CHECKSUM_MISMATCHES=()
    record_checksum_mismatch "test_tool" "https://example.com" "expected123" "actual456"

    if [[ ${#CHECKSUM_MISMATCHES[@]} -eq 1 ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected 1 entry, Got: ${#CHECKSUM_MISMATCHES[@]}"
    fi
}

test_clear_checksum_mismatches() {
    local name="clear_checksum_mismatches clears all entries"

    CHECKSUM_MISMATCHES=()
    record_checksum_mismatch "tool1" "url1" "exp1" "act1"
    record_checksum_mismatch "tool2" "url2" "exp2" "act2"
    clear_checksum_mismatches

    if [[ ${#CHECKSUM_MISMATCHES[@]} -eq 0 ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected 0 entries after clear, Got: ${#CHECKSUM_MISMATCHES[@]}"
    fi
}

test_count_checksum_mismatches() {
    local name="count_checksum_mismatches returns correct count"

    CHECKSUM_MISMATCHES=()
    record_checksum_mismatch "tool1" "url1" "exp1" "act1"
    record_checksum_mismatch "tool2" "url2" "exp2" "act2"
    record_checksum_mismatch "tool3" "url3" "exp3" "act3"

    local count
    count=$(count_checksum_mismatches)

    if [[ "$count" -eq 3 ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected 3, Got: $count"
    fi
}

test_has_checksum_mismatches_true() {
    local name="has_checksum_mismatches returns true when entries exist"

    CHECKSUM_MISMATCHES=()
    record_checksum_mismatch "tool1" "url1" "exp1" "act1"

    if has_checksum_mismatches; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_has_checksum_mismatches_false() {
    local name="has_checksum_mismatches returns false when empty"

    CHECKSUM_MISMATCHES=()

    if ! has_checksum_mismatches; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

# ============================================================
# Test Cases: Retryable Exit Codes
# ============================================================

test_retryable_exit_code_dns() {
    local name="DNS error (6) is retryable"

    if acfs_is_retryable_curl_exit_code 6; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_retryable_exit_code_connect() {
    local name="Connect error (7) is retryable"

    if acfs_is_retryable_curl_exit_code 7; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_retryable_exit_code_timeout() {
    local name="Timeout (28) is retryable"

    if acfs_is_retryable_curl_exit_code 28; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_non_retryable_exit_code() {
    local name="HTTP error (22) is not retryable"

    if ! acfs_is_retryable_curl_exit_code 22; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

test_non_retryable_exit_code_success() {
    local name="Success (0) is not retryable"

    if ! acfs_is_retryable_curl_exit_code 0; then
        test_pass "$name"
    else
        test_fail "$name"
    fi
}

# ============================================================
# Test Cases: KNOWN_INSTALLERS Array
# ============================================================

test_known_installers_has_entries() {
    local name="KNOWN_INSTALLERS array has expected entries"

    local count=0
    for key in "${!KNOWN_INSTALLERS[@]}"; do
        ((++count))
    done

    if [[ $count -gt 5 ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Expected >5 entries, Got: $count"
    fi
}

test_known_installers_all_https() {
    local name="All KNOWN_INSTALLERS URLs are HTTPS"

    local all_https=true
    for key in "${!KNOWN_INSTALLERS[@]}"; do
        local url="${KNOWN_INSTALLERS[$key]}"
        if ! is_https "$url"; then
            all_https=false
            break
        fi
    done

    if [[ "$all_https" == "true" ]]; then
        test_pass "$name"
    else
        test_fail "$name" "Found non-HTTPS URL"
    fi
}

# ============================================================
# Run Tests
# ============================================================

echo ""
echo "ACFS Security Tests"
echo "==================="
echo ""

# HTTPS tests
test_is_https_valid
test_is_https_invalid
test_is_https_ftp
test_enforce_https_valid
test_enforce_https_invalid

# SHA256 tests
test_calculate_sha256_empty
test_calculate_sha256_known_value
test_calculate_sha256_with_newline

# Checksums file tests
test_load_checksums_file_not_found
test_load_checksums_parses_correctly
test_load_checksums_multiple_tools
test_get_checksum_existing
test_get_checksum_missing

# Mismatch recording tests
test_record_checksum_mismatch
test_clear_checksum_mismatches
test_count_checksum_mismatches
test_has_checksum_mismatches_true
test_has_checksum_mismatches_false

# Retryable exit code tests
test_retryable_exit_code_dns
test_retryable_exit_code_connect
test_retryable_exit_code_timeout
test_non_retryable_exit_code
test_non_retryable_exit_code_success

# KNOWN_INSTALLERS tests
test_known_installers_has_entries
test_known_installers_all_https

# Strict policy/report/candidate boundary tests.  Use one fixture directory so
# all mutation cases operate on explicitly named, isolated evidence files.
setup_fixtures
test_strict_checksums_parser_accepts_canonical_closed_world
test_strict_checksums_parser_rejects_noncanonical_mutations_transactionally
test_strict_checksums_parser_rejects_incomplete_set_and_extra_syntax
test_strict_checksums_parser_rejects_byte_boundary_smuggling
test_versioned_checksum_report_binds_urls_hashes_and_exit_status
test_checksum_candidate_validation_is_exact_and_network_free
test_checksum_candidate_validation_rejects_cross_wired_hashes
test_checksum_candidate_validation_rejects_url_drift_and_incomplete_evidence
test_checksum_report_rejects_duplicate_keys_and_policy_digest_drift

echo ""
echo "==================="
echo "Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
echo ""

[[ $TESTS_FAILED -eq 0 ]]
