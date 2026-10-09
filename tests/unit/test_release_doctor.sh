#!/usr/bin/env bash
# Unit tests for scripts/release-doctor.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_DOCTOR="$REPO_ROOT/scripts/release-doctor.sh"
ARTIFACT_DIR="${ACFS_RELEASE_DOCTOR_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-release-doctor-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

TESTS_PASSED=0
TESTS_FAILED=0
LAST_OUTPUT=""
LAST_STATUS=0

TEST_BRANCH="main"
TEST_GIT_STATUS=""
TEST_ORIGIN_MAIN="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
TEST_ORIGIN_MASTER="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
TEST_CHANGED_FILES=""
TEST_SHELLCHECK_STATUS="pass"
TEST_MANIFEST_STATUS="pass"
TEST_CHECKSUM_STATUS="pass"
TEST_WEB_STATUS="pass"
TEST_REPO_ROOT="$REPO_ROOT"

reset_fakes() {
    TEST_BRANCH="main"
    TEST_GIT_STATUS=""
    TEST_ORIGIN_MAIN="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    TEST_ORIGIN_MASTER="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    TEST_CHANGED_FILES=""
    TEST_SHELLCHECK_STATUS="pass"
    TEST_MANIFEST_STATUS="pass"
    TEST_CHECKSUM_STATUS="pass"
    TEST_WEB_STATUS="pass"
    TEST_REPO_ROOT="$REPO_ROOT"
}

# Fixture repos need the files the real version-consistency gate reads
# (VERSION and install.sh's ACFS_VERSION), added after these fixtures.
write_fixture_base() {
    local fixture="$1"
    mkdir -p "$fixture/scripts/lib"
    printf '9.9.9\n' > "$fixture/VERSION"
    printf '#!/usr/bin/env bash\nACFS_VERSION="9.9.9"\n' > "$fixture/install.sh"
}

run_release_doctor() {
    set +e
    LAST_OUTPUT="$(
        env \
            ACFS_RELEASE_DOCTOR_GIT_BRANCH="$TEST_BRANCH" \
            ACFS_RELEASE_DOCTOR_GIT_STATUS="$TEST_GIT_STATUS" \
            ACFS_RELEASE_DOCTOR_ORIGIN_MAIN="$TEST_ORIGIN_MAIN" \
            ACFS_RELEASE_DOCTOR_ORIGIN_MASTER="$TEST_ORIGIN_MASTER" \
            ACFS_RELEASE_DOCTOR_CHANGED_FILES="$TEST_CHANGED_FILES" \
            ACFS_RELEASE_DOCTOR_FAKE_SHELLCHECK_STATUS="$TEST_SHELLCHECK_STATUS" \
            ACFS_RELEASE_DOCTOR_FAKE_MANIFEST_DRIFT_STATUS="$TEST_MANIFEST_STATUS" \
            ACFS_RELEASE_DOCTOR_FAKE_CHECKSUM_CANDIDATE_STATUS="$TEST_CHECKSUM_STATUS" \
            ACFS_RELEASE_DOCTOR_FAKE_WEB_CHECKS_STATUS="$TEST_WEB_STATUS" \
            ACFS_RELEASE_DOCTOR_REPO_ROOT="$TEST_REPO_ROOT" \
            bash "$RELEASE_DOCTOR" --json "$@" 2>&1
    )"
    LAST_STATUS=$?
    set -u
}

run_release_doctor_human() {
    set +e
    LAST_OUTPUT="$(
        env \
            ACFS_RELEASE_DOCTOR_GIT_BRANCH="$TEST_BRANCH" \
            ACFS_RELEASE_DOCTOR_GIT_STATUS="$TEST_GIT_STATUS" \
            ACFS_RELEASE_DOCTOR_ORIGIN_MAIN="$TEST_ORIGIN_MAIN" \
            ACFS_RELEASE_DOCTOR_ORIGIN_MASTER="$TEST_ORIGIN_MASTER" \
            ACFS_RELEASE_DOCTOR_CHANGED_FILES="$TEST_CHANGED_FILES" \
            ACFS_RELEASE_DOCTOR_FAKE_SHELLCHECK_STATUS="$TEST_SHELLCHECK_STATUS" \
            ACFS_RELEASE_DOCTOR_FAKE_MANIFEST_DRIFT_STATUS="$TEST_MANIFEST_STATUS" \
            ACFS_RELEASE_DOCTOR_FAKE_CHECKSUM_CANDIDATE_STATUS="$TEST_CHECKSUM_STATUS" \
            ACFS_RELEASE_DOCTOR_FAKE_WEB_CHECKS_STATUS="$TEST_WEB_STATUS" \
            ACFS_RELEASE_DOCTOR_REPO_ROOT="$TEST_REPO_ROOT" \
            bash "$RELEASE_DOCTOR" "$@" 2>&1
    )"
    LAST_STATUS=$?
    set -u
}

assert_jq() {
    local expression="$1"
    if jq -e "$expression" >/dev/null 2>&1 <<< "$LAST_OUTPUT"; then
        return 0
    fi
    printf 'jq assertion failed: %s\nOutput:\n%s\n' "$expression" "$LAST_OUTPUT"
    return 1
}

run_test() {
    local name="$1"
    shift
    printf '[TEST] %s\n' "$name"
    reset_fakes
    if "$@"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '[PASS] %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '[FAIL] %s\n' "$name"
    fi
}

test_pass_report() {
    run_release_doctor --network=check --web=always
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    assert_jq '
      .ok == true and
      .summary.fail == 0 and
      ([.checks[].status] | all(. == "pass"))
    '
}

test_fail_report() {
    TEST_MANIFEST_STATUS="fail"
    run_release_doctor --network=check --web=always
    [[ "$LAST_STATUS" -eq 1 ]] || return 1
    assert_jq '
      .ok == false and
      .summary.fail == 1 and
      (.checks[] | select(.id == "manifest_drift").status) == "fail"
    '
}

test_warning_report() {
    TEST_ORIGIN_MASTER="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    run_release_doctor --network=check --web=always
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    assert_jq '
      .ok == true and
      .summary.warn == 1 and
      (.checks[] | select(.id == "branch_policy").status) == "warn"
    '
}

test_skipped_network_check() {
    run_release_doctor --web=always
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    assert_jq '
      .ok == true and
      (.checks[] | select(.id == "checksum_candidate").status) == "skip"
    '
}

test_checksum_candidate_ignores_progress_stderr() {
    local fixture="$ARTIFACT_DIR/checksum-progress"
    write_fixture_base "$fixture"
    cat > "$fixture/checksums.yaml" <<'YAML'
# checksums.yaml - Auto-generated original timestamp
# Run: ./scripts/lib/security.sh --update-checksums

installers:
  example:
    url: "https://example.test/install.sh"
    sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

YAML
    cat > "$fixture/scripts/lib/security.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "--update-checksums" ]]; then
    exit 2
fi
printf 'Generating checksums.yaml...\n' >&2
cat <<'YAML'
# checksums.yaml - Auto-generated replacement timestamp
# Run: ./scripts/lib/security.sh --update-checksums

installers:
  example:
    url: "https://example.test/install.sh"
    sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

YAML
BASH

    TEST_REPO_ROOT="$fixture"
    TEST_CHECKSUM_STATUS=""
    run_release_doctor --network=check --web=never
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    assert_jq '
      .ok == true and
      (.checks[] | select(.id == "checksum_candidate").status) == "pass" and
      (.checks[] | select(.id == "checksum_candidate").detail | contains("timestamp header"))
    '
}

test_checksum_candidate_target_diff_fails() {
    local fixture="$ARTIFACT_DIR/checksum-target-diff"
    write_fixture_base "$fixture"
    cat > "$fixture/checksums.yaml" <<'YAML'
# checksums.yaml - Auto-generated original timestamp
# Run: ./scripts/lib/security.sh --update-checksums

installers:
  example:
    url: "https://example.test/install.sh"
    sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

YAML
    cat > "$fixture/scripts/lib/security.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "--update-checksums" ]]; then
    exit 2
fi
cat <<'YAML'
# checksums.yaml - Auto-generated replacement timestamp
# Run: ./scripts/lib/security.sh --update-checksums

installers:
  example:
    url: "https://example.test/install.sh"
    sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

YAML
BASH

    TEST_REPO_ROOT="$fixture"
    TEST_CHECKSUM_STATUS=""
    run_release_doctor --network=check --web=never
    [[ "$LAST_STATUS" -eq 1 ]] || return 1
    assert_jq '
      .ok == false and
      (.checks[] | select(.id == "checksum_candidate").status) == "fail" and
      (.checks[] | select(.id == "checksum_candidate").detail | contains("checksum candidate differs"))
    '
}

test_checksum_candidate_unrelated_diff_fails() {
    local fixture="$ARTIFACT_DIR/checksum-unrelated-diff"
    write_fixture_base "$fixture"
    cat > "$fixture/checksums.yaml" <<'YAML'
# checksums.yaml - Auto-generated original timestamp
# Run: ./scripts/lib/security.sh --update-checksums

installers:
  example:
    url: "https://example.test/install.sh"
    sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  unrelated:
    url: "https://unrelated.test/install.sh"
    sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

YAML
    cat > "$fixture/scripts/lib/security.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "--update-checksums" ]]; then
    exit 2
fi
cat <<'YAML'
# checksums.yaml - Auto-generated replacement timestamp
# Run: ./scripts/lib/security.sh --update-checksums

installers:
  example:
    url: "https://example.test/install.sh"
    sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  unrelated:
    url: "https://unrelated.test/install.sh"
    sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

YAML
BASH

    TEST_REPO_ROOT="$fixture"
    TEST_CHECKSUM_STATUS=""
    run_release_doctor --network=check --web=never
    [[ "$LAST_STATUS" -eq 1 ]] || return 1
    assert_jq '
      .ok == false and
      (.checks[] | select(.id == "checksum_candidate").status) == "fail" and
      (.checks[] | select(.id == "checksum_candidate").detail | contains("checksum candidate differs"))
    '
}

test_missing_installer_records_failed_version_check() {
    # With install.sh absent the doctor used to die under set -e/pipefail
    # (status 2, no report) instead of failing its version-consistency check.
    local fixture="$ARTIFACT_DIR/missing-installer"
    mkdir -p "$fixture"
    printf '9.9.9\n' > "$fixture/VERSION"

    TEST_REPO_ROOT="$fixture"
    run_release_doctor --network=skip --web=never
    [[ "$LAST_STATUS" -eq 1 ]] || return 1
    assert_jq '
      .ok == false and
      (.checks[] | select(.id == "version_consistency").status) == "fail" and
      (.checks[] | select(.id == "version_consistency").detail | contains("could not read ACFS_VERSION"))
    '
}

test_web_check_gating() {
    TEST_WEB_STATUS="fail"
    run_release_doctor --network=check
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    assert_jq '(.checks[] | select(.id == "web_checks").status) == "skip"' || return 1

    TEST_WEB_STATUS="pass"
    TEST_CHANGED_FILES="apps/web/app/page.tsx"
    run_release_doctor --network=check
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    assert_jq '(.checks[] | select(.id == "web_checks").status) == "pass"'
}

test_help_mentions_release_workflow() {
    run_release_doctor --help
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    [[ "$LAST_OUTPUT" == *"--network=skip|check"* ]] || return 1
    [[ "$LAST_OUTPUT" == *"--web=auto|always|never"* ]]
}

test_human_output_reports_governance_checks() {
    run_release_doctor_human --network=skip --web=never
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    [[ "$LAST_OUTPUT" == *"ACFS release doctor"* ]] || return 1
    [[ "$LAST_OUTPUT" == *"[PASS] Branch policy"* ]] || return 1
    [[ "$LAST_OUTPUT" == *"[SKIP] Verified-installer checksum candidate"* ]] || return 1
    [[ "$LAST_OUTPUT" == *"Release readiness: ready"* ]]
}

if ! command -v jq >/dev/null 2>&1; then
    printf '[FAIL] jq is required for release doctor tests\n'
    exit 1
fi

run_test "pass report" test_pass_report
run_test "fail report" test_fail_report
run_test "warning report" test_warning_report
run_test "skipped network check" test_skipped_network_check
run_test "checksum candidate ignores progress stderr" test_checksum_candidate_ignores_progress_stderr
run_test "checksum candidate target diff fails" test_checksum_candidate_target_diff_fails
run_test "checksum candidate unrelated diff fails" test_checksum_candidate_unrelated_diff_fails
run_test "missing installer records a failed version check" test_missing_installer_records_failed_version_check
run_test "web check gating" test_web_check_gating
run_test "help mentions release workflow" test_help_mentions_release_workflow
run_test "human output reports governance checks" test_human_output_reports_governance_checks

printf '\nPassed: %d\nFailed: %d\n' "$TESTS_PASSED" "$TESTS_FAILED"
if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
