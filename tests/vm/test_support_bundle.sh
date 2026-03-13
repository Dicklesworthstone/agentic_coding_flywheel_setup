#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Support Bundle Tests
# Tests: collection functions, redaction, CLI flags, manifest
# Usage: bash tests/vm/test_support_bundle.sh
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPPORT_SH="$REPO_ROOT/scripts/lib/support.sh"

# Source test harness
source "$REPO_ROOT/tests/vm/lib/test_harness.sh"

# ============================================================
# Test setup: create a mock ACFS environment
# ============================================================
MOCK_HOME=""
MOCK_ACFS=""

setup_mock_env() {
    MOCK_HOME=$(mktemp -d)
    MOCK_ACFS="$MOCK_HOME/.acfs"
    mkdir -p "$MOCK_ACFS/logs"

    # Create mock state.json
    cat > "$MOCK_ACFS/state.json" <<'JSON'
{
  "completed_phases": ["base_packages", "shell_setup"],
  "phase_durations": {"base_packages": 45, "shell_setup": 12},
  "current_phase": null,
  "failed_phase": null
}
JSON

    # Create mock VERSION
    echo "0.42.0-test" > "$MOCK_ACFS/VERSION"

    # Create a mock install log with secrets
    cat > "$MOCK_ACFS/logs/install-20260126_220000.log" <<'LOG'
[2026-01-26T22:00:00] Starting ACFS install
API_KEY=sk-proj-abc123def456ghi789jkl012mno345pqr
VAULT_TOKEN=hvs.CAESIJRemUxuRxxxxxxxxxxxxxxxYYY
ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn
PASSWORD=supersecretpassword123
Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U
AKIAIOSFODNN7EXAMPLE
hostname=myserver.example.com
git_sha=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0
LOG

    # Create mock install summary JSON
    cat > "$MOCK_ACFS/logs/install_summary_20260126_220000.json" <<'JSON'
{
  "status": "success",
  "secret_key": "my_very_secret_value_here_1234",
  "hostname": "test-server"
}
JSON

    # Create mock .zshrc
    echo "# mock zshrc" > "$MOCK_HOME/.zshrc"

    # Create a fast mock doctor.sh so support.sh doesn't timeout on real doctor
    mkdir -p "$MOCK_ACFS/scripts/lib"
    cat > "$MOCK_ACFS/scripts/lib/doctor.sh" <<'DOCTOR'
#!/usr/bin/env bash
echo '{"status": "mock", "checks": []}'
DOCTOR
    chmod +x "$MOCK_ACFS/scripts/lib/doctor.sh"
}

cleanup_mock_env() {
    if [[ -n "$MOCK_HOME" ]] && [[ -d "$MOCK_HOME" ]]; then
        rm -rf "$MOCK_HOME"
    fi
}

# ============================================================
# Tests
# ============================================================

test_help_flag() {
    local output
    output=$(bash "$SUPPORT_SH" --help 2>&1) || true
    harness_assert_contains "$output" "support-bundle" "Help output mentions support-bundle"
    harness_assert_contains "$output" "no-redact" "Help output mentions --no-redact flag"
    harness_assert_contains "$output" "verbose" "Help output mentions --verbose flag"
}

test_bundle_creates_archive() {
    setup_mock_env
    local output_dir="$MOCK_HOME/test-output"
    mkdir -p "$output_dir"

    local archive_path
    archive_path=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" --output "$output_dir" 2>/dev/null) || true

    if [[ -n "$archive_path" ]] && [[ -f "$archive_path" ]]; then
        harness_pass "Bundle creates .tar.gz archive"
    else
        harness_fail "Bundle creates .tar.gz archive" "Archive not found at: $archive_path"
    fi

    # Verify it's a valid gzip
    if [[ -f "$archive_path" ]] && file "$archive_path" | grep -q 'gzip'; then
        harness_pass "Archive is valid gzip"
    else
        harness_fail "Archive is valid gzip"
    fi

    cleanup_mock_env
}

test_bundle_contains_expected_files() {
    setup_mock_env
    local output_dir="$MOCK_HOME/test-output"
    mkdir -p "$output_dir"

    local archive_path
    archive_path=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" --output "$output_dir" 2>/dev/null) || true

    if [[ -z "$archive_path" ]] || [[ ! -f "$archive_path" ]]; then
        harness_fail "Bundle archive exists for content check"
        cleanup_mock_env
        return
    fi

    # List archive contents
    local contents
    contents=$(tar tzf "$archive_path" 2>/dev/null) || contents=""

    # Check expected files
    if echo "$contents" | grep -q 'state.json'; then
        harness_pass "Bundle contains state.json"
    else
        harness_fail "Bundle contains state.json"
    fi

    if echo "$contents" | grep -q 'VERSION'; then
        harness_pass "Bundle contains VERSION"
    else
        harness_fail "Bundle contains VERSION"
    fi

    if echo "$contents" | grep -q 'manifest.json'; then
        harness_pass "Bundle contains manifest.json"
    else
        harness_fail "Bundle contains manifest.json"
    fi

    if echo "$contents" | grep -q 'versions.json'; then
        harness_pass "Bundle contains versions.json"
    else
        harness_fail "Bundle contains versions.json"
    fi

    if echo "$contents" | grep -q 'environment.json'; then
        harness_pass "Bundle contains environment.json"
    else
        harness_fail "Bundle contains environment.json"
    fi

    cleanup_mock_env
}

test_manifest_json_valid() {
    setup_mock_env
    local output_dir="$MOCK_HOME/test-output"
    mkdir -p "$output_dir"

    local archive_path
    archive_path=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" --output "$output_dir" 2>/dev/null) || true

    if [[ -z "$archive_path" ]] || [[ ! -f "$archive_path" ]]; then
        harness_fail "Bundle archive exists for manifest check"
        cleanup_mock_env
        return
    fi

    # Extract manifest.json
    local extract_dir
    extract_dir=$(mktemp -d)
    tar xzf "$archive_path" -C "$extract_dir" 2>/dev/null

    local manifest
    manifest=$(find "$extract_dir" -name 'manifest.json' -type f 2>/dev/null | head -1)

    if [[ -n "$manifest" ]] && jq . "$manifest" >/dev/null 2>&1; then
        harness_pass "manifest.json is valid JSON"
    else
        harness_fail "manifest.json is valid JSON"
        rm -rf "$extract_dir"
        cleanup_mock_env
        return
    fi

    # Check redaction fields
    local redaction_enabled
    redaction_enabled=$(jq -r '.redaction.enabled' "$manifest" 2>/dev/null)
    harness_assert_eq "true" "$redaction_enabled" "Manifest shows redaction enabled"

    local pattern_count
    pattern_count=$(jq '.redaction.patterns | length' "$manifest" 2>/dev/null)
    if [[ "$pattern_count" -ge 5 ]]; then
        harness_pass "Manifest lists redaction patterns ($pattern_count)"
    else
        harness_fail "Manifest lists redaction patterns" "Expected >=5, got $pattern_count"
    fi

    local schema_version
    schema_version=$(jq -r '.schema_version' "$manifest" 2>/dev/null)
    harness_assert_eq "1" "$schema_version" "Manifest schema_version is 1"

    rm -rf "$extract_dir"
    cleanup_mock_env
}

test_manifest_lists_each_summary_once() {
    setup_mock_env
    local output_dir="$MOCK_HOME/test-output"
    mkdir -p "$output_dir"

    local archive_path
    archive_path=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" --output "$output_dir" 2>/dev/null) || true

    if [[ -z "$archive_path" ]] || [[ ! -f "$archive_path" ]]; then
        harness_fail "Bundle archive exists for manifest dedup check"
        cleanup_mock_env
        return
    fi

    local extract_dir
    extract_dir=$(mktemp -d)
    tar xzf "$archive_path" -C "$extract_dir" 2>/dev/null

    local manifest
    manifest=$(find "$extract_dir" -name 'manifest.json' -type f 2>/dev/null | head -1)
    if [[ -z "$manifest" ]]; then
        harness_fail "manifest.json exists for manifest dedup check"
        rm -rf "$extract_dir"
        cleanup_mock_env
        return
    fi

    local summary_count
    summary_count=$(jq '[.files[] | select(. == "logs/install_summary_20260126_220000.json")] | length' "$manifest" 2>/dev/null || echo 0)
    harness_assert_eq "1" "$summary_count" "Manifest lists each install summary once"

    rm -rf "$extract_dir"
    cleanup_mock_env
}

test_bundle_names_stay_unique_when_timestamps_collide() {
    setup_mock_env
    local output_dir="$MOCK_HOME/test-output"
    local stub_dir="$MOCK_HOME/test-bin"
    mkdir -p "$output_dir" "$stub_dir"

    cat > "$stub_dir/date" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    +%Y%m%d_%H%M%S)
        printf '20260312_181600\n'
        ;;
    -Iseconds)
        printf '2026-03-12T18:16:00+00:00\n'
        ;;
    +%s)
        printf '1741803360\n'
        ;;
    *)
        command -p date "$@"
        ;;
esac
EOF
    chmod +x "$stub_dir/date"

    local first_path=""
    local second_path=""
    first_path=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" PATH="$stub_dir:$PATH" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" --output "$output_dir" 2>/dev/null) || true
    second_path=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" PATH="$stub_dir:$PATH" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" --output "$output_dir" 2>/dev/null) || true

    if [[ -n "$first_path" ]] && [[ -n "$second_path" ]] \
        && [[ "$first_path" != "$second_path" ]] \
        && [[ -f "$first_path" ]] && [[ -f "$second_path" ]]; then
        harness_pass "Support bundles stay unique when timestamps collide"
    else
        harness_fail "Support bundles stay unique when timestamps collide" "first=$first_path second=$second_path"
    fi

    cleanup_mock_env
}

test_manifest_matches_bundle_inventory() {
    setup_mock_env
    local output_dir="$MOCK_HOME/test-output"
    mkdir -p "$output_dir"

    local archive_path
    archive_path=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" --output "$output_dir" 2>/dev/null) || true

    if [[ -z "$archive_path" ]] || [[ ! -f "$archive_path" ]]; then
        harness_fail "Bundle archive exists for manifest inventory check"
        cleanup_mock_env
        return
    fi

    local extract_dir
    extract_dir=$(mktemp -d)
    tar xzf "$archive_path" -C "$extract_dir" 2>/dev/null

    local bundle_root
    bundle_root=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
    if [[ -z "$bundle_root" ]]; then
        harness_fail "Bundle root exists for manifest inventory check"
        rm -rf "$extract_dir"
        cleanup_mock_env
        return
    fi

    local manifest
    manifest="$bundle_root/manifest.json"
    if [[ ! -f "$manifest" ]]; then
        harness_fail "manifest.json exists for manifest inventory check"
        rm -rf "$extract_dir"
        cleanup_mock_env
        return
    fi

    local listed_files actual_files listed_count actual_count
    listed_files=$(jq -r '.files[]' "$manifest" 2>/dev/null | sort)
    actual_files=$(cd "$bundle_root" && find . -type f | sed 's#^\./##' | sort)
    listed_count=$(jq -r '.file_count' "$manifest" 2>/dev/null)
    actual_count=$(printf '%s\n' "$actual_files" | sed '/^$/d' | wc -l | tr -d ' ')

    if [[ "$listed_files" == "$actual_files" ]] \
        && [[ "$listed_count" == "$actual_count" ]] \
        && printf '%s\n' "$listed_files" | grep -qx 'manifest.json'; then
        harness_pass "Manifest inventory matches extracted bundle contents"
    else
        harness_fail "Manifest inventory matches extracted bundle contents" \
            "listed_count=$listed_count actual_count=$actual_count listed=[$listed_files] actual=[$actual_files]"
    fi

    rm -rf "$extract_dir"
    cleanup_mock_env
}

test_redaction_catches_secrets() {
    setup_mock_env
    local output_dir="$MOCK_HOME/test-output"
    mkdir -p "$output_dir"

    local archive_path
    archive_path=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" --output "$output_dir" 2>/dev/null) || true

    if [[ -z "$archive_path" ]] || [[ ! -f "$archive_path" ]]; then
        harness_fail "Bundle archive exists for redaction check"
        cleanup_mock_env
        return
    fi

    # Extract bundle
    local extract_dir
    extract_dir=$(mktemp -d)
    tar xzf "$archive_path" -C "$extract_dir" 2>/dev/null

    # Check that secrets were redacted in the install log
    local log_file
    log_file=$(find "$extract_dir" -name 'install-*.log' -type f 2>/dev/null | head -1)

    if [[ -z "$log_file" ]]; then
        harness_fail "Install log found in bundle for redaction check"
        rm -rf "$extract_dir"
        cleanup_mock_env
        return
    fi

    local log_content
    log_content=$(cat "$log_file")

    # Secrets MUST be redacted
    if echo "$log_content" | grep -q 'sk-proj-abc123'; then
        harness_fail "API key redacted" "Found raw sk-proj key in bundle"
    else
        harness_pass "API key redacted"
    fi

    if echo "$log_content" | grep -q 'hvs.CAESIJRem'; then
        harness_fail "Vault token redacted" "Found raw Vault token in bundle"
    else
        harness_pass "Vault token redacted"
    fi

    if echo "$log_content" | grep -q 'ghp_ABCDEFGHIJKL'; then
        harness_fail "GitHub token redacted" "Found raw GitHub token in bundle"
    else
        harness_pass "GitHub token redacted"
    fi

    if echo "$log_content" | grep -q 'AKIAIOSFODNN7'; then
        harness_fail "AWS key redacted" "Found raw AWS key in bundle"
    else
        harness_pass "AWS key redacted"
    fi

    if echo "$log_content" | grep -q 'eyJhbGciOiJIUzI1NiI'; then
        harness_fail "JWT redacted" "Found raw JWT in bundle"
    else
        harness_pass "JWT redacted"
    fi

    # Redaction markers MUST be present
    if echo "$log_content" | grep -q '<REDACTED:'; then
        harness_pass "Redaction markers present in output"
    else
        harness_fail "Redaction markers present in output"
    fi

    # Safe values MUST NOT be redacted
    if echo "$log_content" | grep -q 'hostname=myserver.example.com'; then
        harness_pass "Hostname NOT redacted (safe value)"
    else
        harness_fail "Hostname NOT redacted (safe value)"
    fi

    if echo "$log_content" | grep -q 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0'; then
        harness_pass "Git SHA NOT redacted (safe value)"
    else
        harness_fail "Git SHA NOT redacted (safe value)"
    fi

    # Check install summary JSON too
    local summary_file
    summary_file=$(find "$extract_dir" -name 'install_summary_*.json' -type f 2>/dev/null | head -1)

    if [[ -n "$summary_file" ]]; then
        local summary_content
        summary_content=$(cat "$summary_file")

        if echo "$summary_content" | grep -q 'my_very_secret_value'; then
            harness_fail "Generic secret_key redacted in summary JSON" "Found raw secret_key"
        else
            harness_pass "Generic secret_key redacted in summary JSON"
        fi

        if echo "$summary_content" | grep -q 'test-server'; then
            harness_pass "Hostname preserved in summary JSON"
        else
            harness_fail "Hostname preserved in summary JSON"
        fi
    fi

    rm -rf "$extract_dir"
    cleanup_mock_env
}

test_no_redact_flag() {
    setup_mock_env
    local output_dir="$MOCK_HOME/test-output"
    mkdir -p "$output_dir"

    local archive_path
    archive_path=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" --no-redact --output "$output_dir" 2>/dev/null) || true

    if [[ -z "$archive_path" ]] || [[ ! -f "$archive_path" ]]; then
        harness_fail "Bundle archive exists for --no-redact check"
        cleanup_mock_env
        return
    fi

    # Extract and check that secrets are preserved (NOT redacted)
    local extract_dir
    extract_dir=$(mktemp -d)
    tar xzf "$archive_path" -C "$extract_dir" 2>/dev/null

    local log_file
    log_file=$(find "$extract_dir" -name 'install-*.log' -type f 2>/dev/null | head -1)

    if [[ -n "$log_file" ]]; then
        local log_content
        log_content=$(cat "$log_file")

        # With --no-redact, secrets should be present
        if echo "$log_content" | grep -q 'ghp_ABCDEFGHIJKL'; then
            harness_pass "--no-redact preserves GitHub token"
        else
            harness_fail "--no-redact preserves GitHub token" "Token was redacted despite --no-redact"
        fi
    fi

    # Check manifest shows redaction disabled
    local manifest
    manifest=$(find "$extract_dir" -name 'manifest.json' -type f 2>/dev/null | head -1)

    if [[ -n "$manifest" ]]; then
        local redaction_enabled
        redaction_enabled=$(jq -r '.redaction.enabled' "$manifest" 2>/dev/null)
        harness_assert_eq "false" "$redaction_enabled" "Manifest shows redaction disabled with --no-redact"
    fi

    rm -rf "$extract_dir"
    cleanup_mock_env
}

test_verbose_flag() {
    setup_mock_env
    local output_dir="$MOCK_HOME/test-output"
    mkdir -p "$output_dir"

    local stderr_output
    stderr_output=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" --verbose --output "$output_dir" 2>&1 >/dev/null) || true

    if echo "$stderr_output" | grep -qi 'collected\|scanned\|redact'; then
        harness_pass "--verbose produces additional detail output"
    else
        harness_fail "--verbose produces additional detail output"
    fi

    cleanup_mock_env
}

test_tar_failure_returns_bundle_dir() {
    setup_mock_env
    local output_dir="$MOCK_HOME/test-output"
    local stub_dir="$MOCK_HOME/test-bin"
    mkdir -p "$output_dir" "$stub_dir"

    cat > "$stub_dir/tar" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$stub_dir/tar"

    local output_path=""
    output_path=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" PATH="$stub_dir:$PATH" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" --output "$output_dir" 2>/dev/null) || true

    if [[ "$output_path" == "$output_dir"/* ]] && [[ "$output_path" != *.tar.gz ]] && [[ -d "$output_path" ]]; then
        harness_pass "Tar failure returns the bundle directory path"
    else
        harness_fail "Tar failure returns the bundle directory path" "Got: $output_path"
    fi

    cleanup_mock_env
}

test_unknown_flag_errors() {
    local exit_code=0
    bash "$SUPPORT_SH" --bogus-flag >/dev/null 2>&1 || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        harness_pass "Unknown flag produces error exit code"
    else
        harness_fail "Unknown flag produces error exit code" "Got exit 0"
    fi
}

# ============================================================
# Main
# ============================================================
main() {
    harness_init "ACFS Support Bundle Tests"

    # Pre-flight check
    if ! command -v jq &>/dev/null; then
        harness_warn "jq not available — some tests will be limited"
    fi

    harness_section "CLI Flag Tests"
    test_help_flag || true
    test_unknown_flag_errors || true
    test_verbose_flag || true

    harness_section "Bundle Collection Tests"
    test_bundle_creates_archive || true
    test_bundle_contains_expected_files || true
    test_bundle_names_stay_unique_when_timestamps_collide || true
    test_tar_failure_returns_bundle_dir || true

    harness_section "Manifest JSON Tests"
    test_manifest_json_valid || true
    test_manifest_lists_each_summary_once || true
    test_manifest_matches_bundle_inventory || true

    harness_section "Redaction Tests"
    test_redaction_catches_secrets || true
    test_no_redact_flag || true

    harness_summary
}

main "$@"
