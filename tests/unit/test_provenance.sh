#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs installed-tool provenance ledger
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROVENANCE_SH="$REPO_ROOT/scripts/lib/provenance.sh"
SUPPORT_SH="$REPO_ROOT/scripts/lib/support.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_PROVENANCE_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-provenance-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

mkdir -p "$ARTIFACT_DIR"

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    [[ -n "${2:-}" ]] && echo "  Reason: $2"
    return 0
}

write_executable() {
    local path="$1"
    local body="$2"

    printf '%s\n' "$body" > "$path"
    chmod 755 "$path"
}

make_fixture() {
    local name="$1"
    local home_dir="$ARTIFACT_DIR/$name-home"
    local bin_dir="$home_dir/bin"
    local spec_file="$ARTIFACT_DIR/$name-tools.txt"
    local checksums_file="$ARTIFACT_DIR/$name-checksums.yaml"

    mkdir -p "$bin_dir"

    write_executable "$bin_dir/present-tool" '#!/usr/bin/env bash
printf "present-tool 1.2.3\n"'
    write_executable "$bin_dir/mismatch-tool" '#!/usr/bin/env bash
printf "mismatch-tool 9.9.9\n"'
    write_executable "$bin_dir/unknown-tool" '#!/usr/bin/env bash
printf "unknown-tool token=ghp_abcdefghijklmnopqrstuvwxyz1234567890\n"'

    local present_sha
    present_sha="$(sha256sum "$bin_dir/present-tool" | awk '{print $1}')"

    cat > "$checksums_file" <<'YAML'
installers:
  present:
    url: "https://example.test/present/install.sh"
    sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  missing:
    url: "https://example.test/missing/install.sh"
    sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
YAML

    cat > "$spec_file" <<EOF
present|present-tool|--version|verified_installer|https://example.test/present|present|$present_sha
missing|missing-tool|--version|verified_installer|https://example.test/missing|missing|
mismatch|mismatch-tool|--version|verified_installer|https://example.test/mismatch||0000000000000000000000000000000000000000000000000000000000000000
unknown|unknown-tool|--version|manual|local test tool||
EOF

    printf '%s|%s|%s|%s\n' "$home_dir" "$bin_dir" "$spec_file" "$checksums_file"
}

run_provenance_fixture() {
    local fixture="$1"
    local home_dir bin_dir spec_file checksums_file

    IFS='|' read -r home_dir bin_dir spec_file checksums_file <<<"$fixture"
    env \
        HOME="$home_dir" \
        PATH="$bin_dir:/usr/bin:/bin" \
        ACFS_PROVENANCE_TOOLS_FILE="$spec_file" \
        ACFS_PROVENANCE_CHECKSUMS_FILE="$checksums_file" \
        bash "$PROVENANCE_SH" --json
}

test_ledger_reports_present_missing_mismatch_and_unknown() {
    local fixture output
    fixture="$(make_fixture ledger)"
    output="$(run_provenance_fixture "$fixture")"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/ledger.json"

    jq -e '
      .schema_version == 1 and
      .summary.total == 4 and
      .summary.present == 3 and
      .summary.missing == 1 and
      .summary.verified == 1 and
      .summary.mismatched == 1 and
      .summary.unknown_provenance == 1 and
      (.tools[] | select(.name == "present").verification_status) == "verified" and
      (.tools[] | select(.name == "missing").verification_status) == "missing" and
      (.tools[] | select(.name == "mismatch").verification_status) == "mismatched" and
      (.tools[] | select(.name == "unknown").verification_status) == "unknown_provenance"
    ' <<<"$output" >/dev/null || return 1

    pass "ledger_reports_present_missing_mismatch_and_unknown"
}

test_ledger_redacts_paths_and_version_secrets() {
    local fixture output home_dir
    fixture="$(make_fixture redaction)"
    IFS='|' read -r home_dir _ _ _ <<<"$fixture"
    output="$(run_provenance_fixture "$fixture")"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/redaction.json"

    if grep -Fq "$home_dir" <<<"$output"; then
        return 1
    fi

    jq -e '
      (.tools[] | select(.name == "present").resolved_path | startswith("$HOME/bin/")) and
      (.tools[] | select(.name == "present").path_redacted == true) and
      (.tools[] | select(.name == "unknown").installed_version | contains("<REDACTED:github_token>"))
    ' <<<"$output" >/dev/null || return 1

    pass "ledger_redacts_paths_and_version_secrets"
}

test_ledger_includes_installer_references() {
    local fixture output
    fixture="$(make_fixture installer_ref)"
    output="$(run_provenance_fixture "$fixture")"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/installer-ref.json"

    jq -e '
      (.tools[] | select(.name == "present").installer_reference.url) == "https://example.test/present/install.sh" and
      (.tools[] | select(.name == "present").installer_reference.sha256) == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and
      (.tools[] | select(.name == "unknown").installer_reference.url) == null
    ' <<<"$output" >/dev/null || return 1

    pass "ledger_includes_installer_references"
}

test_support_capture_records_provenance_json() {
    local fixture home_dir bin_dir spec_file checksums_file bundle_dir output
    fixture="$(make_fixture support_capture)"
    IFS='|' read -r home_dir bin_dir spec_file checksums_file <<<"$fixture"
    bundle_dir="$ARTIFACT_DIR/support-bundle"
    mkdir -p "$bundle_dir"

    output="$(env \
        HOME="$home_dir" \
        PATH="$bin_dir:/usr/bin:/bin" \
        ACFS_PROVENANCE_TOOLS_FILE="$spec_file" \
        ACFS_PROVENANCE_CHECKSUMS_FILE="$checksums_file" \
        SUPPORT_SH="$SUPPORT_SH" \
        REPO_ROOT="$REPO_ROOT" \
        BUNDLE_DIR="$bundle_dir" \
        bash -lc '
            set -euo pipefail
            log_step() { :; }
            log_section() { :; }
            log_detail() { :; }
            log_success() { :; }
            log_warn() { :; }
            log_error() { :; }
            # shellcheck source=../../scripts/lib/support.sh
            source "$SUPPORT_SH"
            _SUPPORT_ACFS_HOME=""
            _SUPPORT_SCRIPT_DIR="$REPO_ROOT/scripts/lib"
            PROVENANCE_TIMEOUT=5
            BUNDLE_FILES=()
            capture_provenance_json "$BUNDLE_DIR"
            jq -r ".files? // empty" /dev/null >/dev/null 2>&1 || true
            printf "%s\n" "${BUNDLE_FILES[*]}"
        ')"

    printf '%s\n' "$output" > "$ARTIFACT_DIR/support-capture.files"
    [[ -f "$bundle_dir/provenance.json" ]] || return 1
    grep -qw "provenance.json" <<<"$output" || return 1
    jq -e '.summary.total == 4 and (.tools[] | select(.name == "mismatch").verification_status) == "mismatched"' "$bundle_dir/provenance.json" >/dev/null || return 1

    pass "support_capture_records_provenance_json"
}

test_ledger_finds_user_tools_under_minimal_dispatch_path() {
    # `acfs provenance` / `acfs support-bundle` run helpers with only the system
    # PATH; per-user tools must still be found in the target home's bin dirs.
    [[ "$EUID" -ne 0 ]] || { pass "ledger_finds_user_tools_under_minimal_dispatch_path (skipped as root)"; return 0; }
    local fixture output home_dir bin_dir spec_file checksums_file
    fixture="$(make_fixture minimal-path)"
    IFS='|' read -r home_dir bin_dir spec_file checksums_file <<<"$fixture"
    output="$(env -i \
        HOME="$home_dir" \
        PATH="/usr/sbin:/usr/bin:/sbin:/bin" \
        ACFS_PROVENANCE_TOOLS_FILE="$spec_file" \
        ACFS_PROVENANCE_CHECKSUMS_FILE="$checksums_file" \
        bash "$PROVENANCE_SH" --json)"

    jq -e '.summary.present == 3 and .summary.missing == 1' <<<"$output" >/dev/null || return 1

    pass "ledger_finds_user_tools_under_minimal_dispatch_path"
}

run_test() {
    local name="$1"

    if "$name"; then
        return 0
    fi
    fail "$name"
}

main() {
    run_test test_ledger_reports_present_missing_mismatch_and_unknown
    run_test test_ledger_redacts_paths_and_version_secrets
    run_test test_ledger_includes_installer_references
    run_test test_support_capture_records_provenance_json
    run_test test_ledger_finds_user_tools_under_minimal_dispatch_path

    echo ""
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo "Artifacts: $ARTIFACT_DIR"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

main "$@"
