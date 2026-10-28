#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Support Bundle Tests
# Tests: collection functions, redaction, CLI flags, manifest
# Usage: bash tests/vm/test_support_bundle.sh
# Focused filesystem regression: bash tests/vm/test_support_bundle.sh --output-safety-only
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPPORT_SH="${ACFS_SUPPORT_TEST_SCRIPT:-$REPO_ROOT/scripts/lib/support.sh}"

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
gho_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn
PASSWORD=supersecretpassword123
Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U
AKIAIOSFODNN7EXAMPLE
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAA
-----END OPENSSH PRIVATE KEY-----
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

    # Create mock performance budget JSON
    cat > "$MOCK_ACFS/logs/performance_budget_20260126_220000.json" <<'JSON'
{
  "schema_version": 1,
  "status": "pass",
  "secret_key": "budget_secret_value_here_1234",
  "budgets": [
    {
      "name": "total_install_duration",
      "actual_seconds": 57,
      "budget_seconds": 3600,
      "status": "pass"
    }
  ],
  "artifacts": [
    {
      "kind": "source_summary",
      "path": "install_summary_20260126_220000.json",
      "redacted": true
    }
  ]
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

    cat > "$MOCK_ACFS/scripts/lib/swarm_status.sh" <<'SWARM'
#!/usr/bin/env bash
echo '{"schema_version": 1, "status": "pass", "probes": {}}'
SWARM
    chmod +x "$MOCK_ACFS/scripts/lib/swarm_status.sh"
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
    if grep -q 'state.json' <<< "$contents"; then
        harness_pass "Bundle contains state.json"
    else
        harness_fail "Bundle contains state.json"
    fi

    if grep -q 'VERSION' <<< "$contents"; then
        harness_pass "Bundle contains VERSION"
    else
        harness_fail "Bundle contains VERSION"
    fi

    if grep -q 'manifest.json' <<< "$contents"; then
        harness_pass "Bundle contains manifest.json"
    else
        harness_fail "Bundle contains manifest.json"
    fi

    if grep -q 'performance_budget_20260126_220000.json' <<< "$contents"; then
        harness_pass "Bundle contains performance budget JSON"
    else
        harness_fail "Bundle contains performance budget JSON"
    fi

    if grep -q 'swarm_status.json' <<< "$contents"; then
        harness_pass "Bundle contains swarm status JSON"
    else
        harness_fail "Bundle contains swarm status JSON"
    fi

    if grep -q 'swarm_timeline.json' <<< "$contents"; then
        harness_pass "Bundle contains swarm timeline JSON"
    else
        harness_fail "Bundle contains swarm timeline JSON"
    fi

    if grep -q 'swarm_inventory.json' <<< "$contents"; then
        harness_pass "Bundle contains swarm inventory JSON"
    else
        harness_fail "Bundle contains swarm inventory JSON"
    fi

    if grep -q 'versions.json' <<< "$contents"; then
        harness_pass "Bundle contains versions.json"
    else
        harness_fail "Bundle contains versions.json"
    fi

    if grep -q 'environment.json' <<< "$contents"; then
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

    if jq -e '.redaction.patterns | index("private_key")' "$manifest" >/dev/null 2>&1; then
        harness_pass "Manifest lists private_key redaction pattern"
    else
        harness_fail "Manifest lists private_key redaction pattern"
    fi

    local schema_version
    schema_version=$(jq -r '.schema_version' "$manifest" 2>/dev/null)
    harness_assert_eq "1" "$schema_version" "Manifest schema_version is 1"

    if jq -e '.diagnostics.swarm_timeline.included == true and (.diagnostics.swarm_timeline.probes | length) >= 5' "$manifest" >/dev/null 2>&1; then
        harness_pass "Manifest includes swarm timeline probe manifest"
    else
        harness_fail "Manifest includes swarm timeline probe manifest"
    fi

    if jq -e '.diagnostics.swarm_inventory.included == false and .diagnostics.swarm_inventory.status == "skipped" and .diagnostics.swarm_inventory.paths_redacted == true and .diagnostics.swarm_inventory.raw_hosts_collected == false' "$manifest" >/dev/null 2>&1; then
        harness_pass "Manifest includes skipped swarm inventory diagnostics"
    else
        harness_fail "Manifest includes skipped swarm inventory diagnostics"
    fi

    if jq -e '
        (.diagnostics | keys | length) >= 8 and
        ([.diagnostics[] | select(
            .proof_schema_version == 1 and
            (.included | type) == "boolean" and
            (.source_status | type) == "string" and
            (.records.raw_count | type) == "number" and
            (.records.sanitized_count | type) == "number" and
            .records.raw_values_collected == false and
            (.redaction.categories | type) == "array" and
            .redaction.raw_values_collected == false
        )] | length) == (.diagnostics | keys | length) and
        (.diagnostics.doctor.redaction.categories | index("secret_values")) and
        (.diagnostics.swarm_inventory.redaction.categories | index("hostnames")) and
        (.diagnostics.environment.redaction.categories | index("home_paths"))
    ' "$manifest" >/dev/null 2>&1; then
        harness_pass "Manifest includes redaction proof metadata for diagnostic sources"
    else
        harness_fail "Manifest includes redaction proof metadata for diagnostic sources"
    fi

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

    local budget_count
    budget_count=$(jq '[.files[] | select(. == "logs/performance_budget_20260126_220000.json")] | length' "$manifest" 2>/dev/null || echo 0)
    harness_assert_eq "1" "$budget_count" "Manifest lists each performance budget once"

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

test_log_collection_skips_symlinked_logs() {
    setup_mock_env
    local output_dir="$MOCK_HOME/test-output"
    mkdir -p "$output_dir"

    cat > "$MOCK_HOME/outside-secret.log" <<'LOG'
SYMLINK_SHOULD_NOT_LEAK=super-secret-diagnostic-value
LOG
    ln -s "$MOCK_HOME/outside-secret.log" "$MOCK_ACFS/logs/install-20260126_230000.log"

    local archive_path
    archive_path=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" --output "$output_dir" 2>/dev/null) || true

    if [[ -z "$archive_path" ]]; then
        harness_fail "Bundle archive exists for symlink log check"
        cleanup_mock_env
        return
    fi

    local bundle_dir="$archive_path"
    if [[ "$bundle_dir" == *.tar.gz ]]; then
        bundle_dir="${bundle_dir%.tar.gz}"
    fi

    if [[ ! -d "$bundle_dir" ]]; then
        harness_fail "Bundle directory exists for symlink log check" "Got: $bundle_dir"
        cleanup_mock_env
        return
    fi

    if [[ ! -e "$bundle_dir/logs/install-20260126_230000.log" ]] \
        && ! grep -R "SYMLINK_SHOULD_NOT_LEAK" "$bundle_dir" >/dev/null 2>&1; then
        harness_pass "Support bundle skips symlinked install logs"
    else
        harness_fail "Support bundle skips symlinked install logs" "Symlink target content was copied"
    fi

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
    if grep -q 'sk-proj-abc123' <<< "$log_content"; then
        harness_fail "API key redacted" "Found raw sk-proj key in bundle"
    else
        harness_pass "API key redacted"
    fi

    if grep -q 'hvs.CAESIJRem' <<< "$log_content"; then
        harness_fail "Vault token redacted" "Found raw Vault token in bundle"
    else
        harness_pass "Vault token redacted"
    fi

    if grep -q 'ghp_ABCDEFGHIJKL' <<< "$log_content"; then
        harness_fail "GitHub token redacted" "Found raw GitHub token in bundle"
    else
        harness_pass "GitHub token redacted"
    fi

    if grep -q 'gho_ABCDEFGHIJKL' <<< "$log_content"; then
        harness_fail "GitHub OAuth token redacted" "Found raw GitHub OAuth token in bundle"
    else
        harness_pass "GitHub OAuth token redacted"
    fi

    if grep -q 'AKIAIOSFODNN7' <<< "$log_content"; then
        harness_fail "AWS key redacted" "Found raw AWS key in bundle"
    else
        harness_pass "AWS key redacted"
    fi

    if grep -q 'eyJhbGciOiJIUzI1NiI' <<< "$log_content"; then
        harness_fail "JWT redacted" "Found raw JWT in bundle"
    else
        harness_pass "JWT redacted"
    fi

    if grep -q 'b3BlbnNzaC1rZXktdjE' <<< "$log_content"; then
        harness_fail "Private key block redacted" "Found raw private key payload in bundle"
    else
        harness_pass "Private key block redacted"
    fi

    if grep -q 'BEGIN OPENSSH PRIVATE KEY' <<< "$log_content"; then
        harness_fail "Private key header redacted" "Found raw private key header in bundle"
    else
        harness_pass "Private key header redacted"
    fi

    # Redaction markers MUST be present
    if grep -q '<REDACTED:' <<< "$log_content"; then
        harness_pass "Redaction markers present in output"
    else
        harness_fail "Redaction markers present in output"
    fi

    # Safe values MUST NOT be redacted
    if grep -q 'hostname=myserver.example.com' <<< "$log_content"; then
        harness_pass "Hostname NOT redacted (safe value)"
    else
        harness_fail "Hostname NOT redacted (safe value)"
    fi

    if grep -q 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0' <<< "$log_content"; then
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

        if grep -q 'my_very_secret_value' <<< "$summary_content"; then
            harness_fail "Generic secret_key redacted in summary JSON" "Found raw secret_key"
        else
            harness_pass "Generic secret_key redacted in summary JSON"
        fi

        if grep -q 'test-server' <<< "$summary_content"; then
            harness_pass "Hostname preserved in summary JSON"
        else
            harness_fail "Hostname preserved in summary JSON"
        fi
    fi

    # Check performance budget JSON too
    local budget_file
    budget_file=$(find "$extract_dir" -name 'performance_budget_*.json' -type f 2>/dev/null | head -1)

    if [[ -n "$budget_file" ]]; then
        local budget_content
        budget_content=$(cat "$budget_file")

        if grep -q 'budget_secret_value' <<< "$budget_content"; then
            harness_fail "Generic secret_key redacted in performance budget JSON" "Found raw secret_key"
        else
            harness_pass "Generic secret_key redacted in performance budget JSON"
        fi

        if grep -q 'total_install_duration' <<< "$budget_content"; then
            harness_pass "Budget metric name preserved in performance budget JSON"
        else
            harness_fail "Budget metric name preserved in performance budget JSON"
        fi
    fi

    rm -rf "$extract_dir"
    cleanup_mock_env
}

test_binary_log_replaced_with_redaction_marker() {
    setup_mock_env
    local output_dir="$MOCK_HOME/test-output"
    mkdir -p "$output_dir"

    printf 'binary-prefix\000BINARY_SECRET_SHOULD_NOT_LEAK\n' > "$MOCK_ACFS/logs/install-20260126_235959.log"

    local archive_path
    archive_path=$(HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" \
        SUPPORT_BUNDLE_DOCTOR_TIMEOUT=1 \
        SUPPORT_BUNDLE_SWARM_STATUS_TIMEOUT=1 \
        SUPPORT_BUNDLE_PROVENANCE_TIMEOUT=1 \
        SUPPORT_BUNDLE_RESOURCE_PROFILE_TIMEOUT=1 \
        SUPPORT_BUNDLE_SWARM_INVENTORY_TIMEOUT=1 \
        SUPPORT_BUNDLE_SWARM_TIMELINE_TIMEOUT=1 \
        bash "$SUPPORT_SH" --output "$output_dir" 2>/dev/null) || true

    if [[ -z "$archive_path" ]] || [[ ! -f "$archive_path" ]]; then
        harness_fail "Bundle archive exists for binary redaction check"
        cleanup_mock_env
        return
    fi

    local extract_dir
    extract_dir=$(mktemp -d)
    tar xzf "$archive_path" -C "$extract_dir" 2>/dev/null

    local binary_log
    binary_log=$(find "$extract_dir" -name 'install-20260126_235959.log' -type f 2>/dev/null | head -1)
    if [[ -n "$binary_log" ]] && grep -Fxq '<REDACTED:binary_file>' "$binary_log"; then
        harness_pass "Binary log is replaced with redaction marker"
    else
        harness_fail "Binary log is replaced with redaction marker"
    fi

    if ! grep -R -a 'BINARY_SECRET_SHOULD_NOT_LEAK' "$extract_dir" >/dev/null 2>&1; then
        harness_pass "Binary log raw content is not retained"
    else
        harness_fail "Binary log raw content is not retained"
    fi

    local manifest
    manifest=$(find "$extract_dir" -name 'manifest.json' -type f 2>/dev/null | head -1)
    if [[ -n "$manifest" ]] && jq -e '.redaction.files_modified >= 1' "$manifest" >/dev/null 2>&1; then
        harness_pass "Manifest records binary redaction modification"
    else
        harness_fail "Manifest records binary redaction modification"
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
        if grep -q 'ghp_ABCDEFGHIJKL' <<< "$log_content"; then
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

    if grep -qiE 'collected|scanned|redact' <<< "$stderr_output"; then
        harness_pass "--verbose produces additional detail output"
    else
        harness_fail "--verbose produces additional detail output"
    fi

    cleanup_mock_env
}

test_sudo_user_defaults_to_target_acfs_home() {
    setup_mock_env

    local root_home="$MOCK_HOME/root-home"
    local target_home="$MOCK_HOME/target-home"
    local target_acfs="$target_home/.acfs"
    mkdir -p "$root_home" "$target_home" "$target_acfs"

    cp -R "$MOCK_ACFS/." "$target_acfs/"
    cat > "$target_acfs/state.json" <<JSON
{
  "target_user": "acfstarget",
  "target_home": "$target_home",
  "completed_phases": ["base_packages", "shell_setup"]
}
JSON
    echo "# root zshrc" > "$root_home/.zshrc"
    echo "# target zshrc" > "$target_home/.zshrc"

    local archive_path=""
    archive_path=$(HOME="$root_home" SUDO_USER="acfstarget" ACFS_SYSTEM_STATE_FILE="$target_acfs/state.json" SUPPORT_BUNDLE_DOCTOR_TIMEOUT=5 \
        bash "$SUPPORT_SH" 2>/dev/null) || true

    if [[ "$archive_path" == "$target_acfs"/support/* ]] && [[ -f "$archive_path" ]]; then
        harness_pass "SUDO_USER support bundle defaults to target ACFS home"
    else
        harness_fail "SUDO_USER support bundle defaults to target ACFS home" "Got: $archive_path"
        cleanup_mock_env
        return
    fi

    local extract_dir
    extract_dir=$(mktemp -d)
    tar xzf "$archive_path" -C "$extract_dir" 2>/dev/null

    local zshrc_path
    zshrc_path=$(find "$extract_dir" -path '*/config/.zshrc' -type f 2>/dev/null | head -1)

    if [[ -n "$zshrc_path" ]] && grep -q '# target zshrc' "$zshrc_path"; then
        harness_pass "SUDO_USER support bundle collects target user .zshrc"
    else
        harness_fail "SUDO_USER support bundle collects target user .zshrc"
    fi

    rm -rf "$extract_dir"
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

# Exercise real collection, redaction, manifest and tar writes in a private
# fixture. Optional telemetry is omitted so no shared services are contacted.
# Plant the output collision after collection starts, not before name selection.
test_bundle_output_safety() {
    setup_mock_env
    local output_dir="$MOCK_HOME/output with spaces"
    local replacement_dir="$MOCK_HOME/replacement"
    local original_dir="$MOCK_HOME/original"
    local mode status output_path archive_target bundle_root entry
    mkdir -p "$replacement_dir" "$original_dir"
    ln -s "$original_dir" "$output_dir"
    for mode in ordinary failed-journal archive-file archive-symlink archive-dangling archive-hardlink archive-directory archive-swap ancestor-swap workspace-move; do
        archive_target="$MOCK_HOME/target-$mode"
        if [[ "$mode" != archive-dangling ]]; then
            printf 'existing target stays intact\n' > "$archive_target"
        fi
        status=0
        HOME="$MOCK_HOME" ACFS_HOME="$MOCK_ACFS" bash -s -- \
            "$SUPPORT_SH" "$output_dir" "$MOCK_HOME" "$MOCK_ACFS" "$mode" \
            "$archive_target" "$replacement_dir" \
            > "$MOCK_HOME/$mode.stdout" 2> "$MOCK_HOME/$mode.stderr" <<'BASH' || status=$?
source "$1"
fixture_output="$2" fixture_home="$3" fixture_acfs="$4" fixture_mode="$5" fixture_target="$6" fixture_replacement="$7"
log_section() { :; }
log_step() { :; }
log_detail() { :; }
log_warn() { printf '%s\n' "$*" >&2; }
log_error() { printf '%s\n' "$*" >&2; }
log_success() { printf '%s\n' "$*" >&2; }
support_initialize_context() {
    OUTPUT_BASE="$fixture_output"
    SUPPORT_TARGET_HOME="$fixture_home"
    SUPPORT_TARGET_USER="fixture-user"
    _SUPPORT_ACFS_HOME="$fixture_acfs"
}
capture_doctor_json() { :; }
capture_agent_readiness_json() { :; }
capture_checkpoint_summary_json() { :; }
capture_local_progress_json() { :; }
capture_swarm_status_json() { :; }
capture_provenance_json() { :; }
capture_resource_profile_json() { :; }
capture_credential_status_json() { :; }
capture_team_profile_json() { :; }
capture_swarm_inventory_json() { :; }
capture_swarm_timeline_json() { :; }
capture_env_summary() { :; }
capture_versions() {
    local archive_file="${1}.tar.gz"
    case "$fixture_mode" in
        archive-file) printf 'existing archive stays intact\n' > "$archive_file" ;;
        archive-symlink|archive-dangling) ln -s "$fixture_target" "$archive_file" ;;
        archive-hardlink) ln "$fixture_target" "$archive_file" ;;
        archive-directory) mkdir "$archive_file" ;;
        archive-swap) fixture_archive="$archive_file" ;;
        ancestor-swap)
            mv "$fixture_output" "${fixture_output}.retained"
            ln -s "$fixture_replacement" "$fixture_output"
            ;;
        workspace-move)
            mv "$OUTPUT_BASE" "${OUTPUT_BASE}.moved"
            mkdir "$OUTPUT_BASE"
            ;;
    esac
}
tar() {
    if [[ "$fixture_mode" == archive-swap ]]; then
        if [[ -f "$fixture_archive" ]]; then
            mv "$fixture_archive" "${fixture_archive}.retained"
        fi
        ln -s "$fixture_target" "$fixture_archive"
    fi
    command tar "$@"
}
# Keep system journal capture out of this filesystem fixture as well.
journalctl() { printf 'uncollected fixture journal bytes\n'; return 1; }
before_cwd="$PWD"
before_umask=$(umask)
main --output "$fixture_output"
result=$?
if [[ "$PWD" == "$before_cwd" && "$(umask)" == "$before_umask" ]]; then
    printf 'preserved\n' > "$fixture_home/$fixture_mode.caller"
else
    printf 'changed\n' > "$fixture_home/$fixture_mode.caller"
fi
exit "$result"
BASH
        output_path=$(cat "$MOCK_HOME/$mode.stdout")
        harness_assert_eq "preserved" "$(cat "$MOCK_HOME/$mode.caller")" "Sourced caller directory and umask preserved: $mode"
        if [[ "$mode" == workspace-move ]]; then
            if [[ "$status" -ne 0 && -z "$output_path" ]] \
                && grep -q 'workspace moved' "$MOCK_HOME/$mode.stderr"; then
                harness_pass "Moved workspace cannot produce a stale success path"
            else
                harness_fail "Moved workspace cannot produce a stale success path" "status=$status output=$output_path"
            fi
            continue
        fi
        if [[ "$status" -ne 0 ]]; then
            harness_fail "Support output scenario completes: $mode" "status=$status; see $MOCK_HOME/$mode.stderr"
            continue
        fi
        case "$mode" in
            archive-*)
                if [[ -d "$output_path" && "$output_path" != *.tar.gz ]]; then
                    harness_pass "Archive collision retains useful diagnostic directory: $mode"
                else
                    harness_fail "Archive collision retains useful diagnostic directory: $mode" "$output_path"
                fi
                if [[ "$mode" == archive-dangling ]]; then
                    if [[ ! -e "$archive_target" ]]; then
                        harness_pass "Dangling archive target is never created"
                    else
                        harness_fail "Dangling archive target is never created"
                    fi
                elif [[ "$(cat "$archive_target")" == 'existing target stays intact' ]]; then
                    harness_pass "Archive target remains unchanged: $mode"
                else
                    harness_fail "Archive target remains unchanged: $mode"
                fi
                if [[ "$mode" == archive-file ]]; then
                    if [[ "$(cat "${output_path}.tar.gz")" == 'existing archive stays intact' ]]; then
                        harness_pass "Pre-existing archive bytes remain unchanged"
                    else
                        harness_fail "Pre-existing archive bytes remain unchanged"
                    fi
                fi
                if [[ "$mode" == archive-directory ]]; then
                    if [[ -d "${output_path}.tar.gz" && -z "$(find "${output_path}.tar.gz" -mindepth 1 -print -quit)" ]]; then
                        harness_pass "Pre-existing archive directory remains unchanged"
                    else
                        harness_fail "Pre-existing archive directory remains unchanged"
                    fi
                fi
                if [[ "$mode" == archive-swap ]]; then
                    if grep -q 'Archive pathname changed' "$MOCK_HOME/$mode.stderr" \
                        && tar -tzf "${output_path}.tar.gz.retained" > "$MOCK_HOME/$mode.contents"; then
                        harness_pass "Archive swap writes only through the retained descriptor and reports diagnostics"
                    else
                        harness_fail "Archive swap writes only through the retained descriptor and reports diagnostics"
                    fi
                fi
                ;;
            ordinary|failed-journal|ancestor-swap)
                if [[ -f "$output_path" ]] && tar -tzf "$output_path" > "$MOCK_HOME/$mode.contents"; then
                    harness_pass "Real archive remains readable: $mode"
                else
                    harness_fail "Real archive remains readable: $mode" "$output_path"
                    continue
                fi
                if [[ "$mode" == ancestor-swap && -z "$(find "$replacement_dir" -mindepth 1 -print -quit)" ]]; then
                    harness_pass "Changing output ancestor cannot redirect collection or archive writes"
                elif [[ "$mode" == ancestor-swap ]]; then
                    harness_fail "Changing output ancestor cannot redirect collection or archive writes"
                fi
                bundle_root="${output_path%.tar.gz}"
                if [[ -f "$bundle_root/state.json" && -f "$bundle_root/config/.zshrc" \
                    && -f "$bundle_root/manifest.json" && -f "$bundle_root/support-report.md" ]]; then
                    harness_pass "Useful state, configuration, manifest and report persist: $mode"
                else
                    harness_fail "Useful state, configuration, manifest and report persist: $mode"
                fi
                entry=$(find "$(dirname "$output_path")" \( \
                    -perm -040 -o -perm -020 -o -perm -010 \
                    -o -perm -004 -o -perm -002 -o -perm -001 \) -print -quit)
                if [[ -z "$entry" ]]; then
                    harness_pass "Workspace, diagnostics and archive remain owner-only: $mode"
                else
                    harness_fail "Workspace, diagnostics and archive remain owner-only: $mode" "$entry"
                fi
                if [[ "$mode" == failed-journal ]]; then
                    if [[ -z "$(find "$bundle_root" -type f -name '*.tmp.*' -print -quit)" ]] \
                        && ! grep -R -F 'uncollected fixture journal bytes' "$bundle_root"; then
                        harness_pass "Failed capture scratch data stays outside the diagnostic archive"
                    else
                        harness_fail "Failed capture scratch data stays outside the diagnostic archive"
                    fi
                fi
                ;;
        esac
    done
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

test_complete_quoted_redaction() {
    if python3 - "$SUPPORT_SH" <<'PY'
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

script = sys.argv[1]
checks = unittest.TestCase()
root = Path(tempfile.mkdtemp(prefix="acfs-support-quoted-"))
secret = 'fixtureSecretFirst "fixtureSecretMiddle" fixtureSecretTail\\end'
public = '{"apiKeyCount":9007199254740993,"tokenCount":5,"url":"https://example.com/docs","empty":{"password":"","apiKey":null}}'
structured = json.dumps({"password": secret, "secretKey": secret, "MYSQL_PWD": secret,
                         "service_api_key": secret, "serviceAccessToken": secret})
structured = structured[:-1] + ',"public":' + public + '}'
cases = {
    "json": structured,
    "json-lines": structured + "\n" + structured,
    "embedded-json": "[diagnostic] " + structured,
    "encoded-json": json.dumps({"diagnostic": structured}),
    "encoded-shell": json.dumps({"diagnostic": 'MYSQL_PWD="' + secret.replace('"', '\\"') + '"'}),
    "shell": 'MYSQL_PWD="' + secret.replace('"', '\\"') + '"',
    "single-quoted-shell": "MYSQL_PWD='" + secret + "'",
    "message-snippet": json.dumps({"body_md": secret}),
    "multiline-json": json.dumps({"apiKey": "fixtureSecretFirst\nfixtureSecretTail"}, indent=2),
    "escaped-key": '{"passw\\u006frd":' + json.dumps(secret) + '}',
    "public": public,
}
for name, body in cases.items():
    target = root / (name + ".log")
    target.write_text(body + "\n")
    result = subprocess.run(["bash", "-c", 'source "$1"; redact_file "$2"', "_", script, str(target)],
                            capture_output=True, text=True, timeout=10, check=False)
    checks.assertEqual(result.returncode, 0, (name, result.stderr))
    safe = target.read_text()
    checks.assertNotIn("fixtureSecret", safe, (name, safe))
    try:
        if name in ("json", "encoded-json", "encoded-shell", "multiline-json", "escaped-key", "public", "message-snippet"):
            json.loads(safe)
        if name == "json-lines":
            for line in safe.splitlines():
                json.loads(line)
    except json.JSONDecodeError as error:
        raise AssertionError((name, "redacted JSON is malformed", safe)) from error
    if "9007199254740993" in body:
        checks.assertIn("9007199254740993", safe, (name, "public integer changed", safe))
    if name == "public":
        checks.assertEqual(safe, body + "\n")
    else:
        checks.assertIn("<REDACTED:", safe, (name, safe))
    print("PASS quoted redaction:", name)

target = root / "failed-redactor.log"
target.write_text(structured + "\n")
result = subprocess.run(["bash", "-c", '''source "$1"
support_system_binary_path() {
    if [[ "$1" == jq ]]; then printf '/bin/false\\n'; else command -v "$1"; fi
}
redact_file "$2"
''', "_", script, str(target)], capture_output=True, text=True, timeout=10, check=False)
checks.assertNotEqual(result.returncode, 0, result.stderr)
checks.assertEqual(target.read_text(), "<REDACTED:redaction_failed>\n")
print("PASS quoted redaction: dependency failure stays closed")
PY
    then
        harness_pass "Complete quoted credentials are redacted without damaging public JSON"
    else
        harness_fail "Complete quoted credentials are redacted without damaging public JSON"
    fi
}

# ============================================================
# Main
# ============================================================
main() {
    harness_init "ACFS Support Bundle Tests"

    if [[ "${1:-}" == --redaction-only ]]; then
        test_complete_quoted_redaction
        harness_summary
        return $?
    fi

    if [[ "${1:-}" == --output-safety-only ]]; then
        harness_section "Output Filesystem Safety Tests"
        test_bundle_output_safety || true
        harness_summary
        return $?
    fi

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
    test_sudo_user_defaults_to_target_acfs_home || true
    test_bundle_names_stay_unique_when_timestamps_collide || true
    test_log_collection_skips_symlinked_logs || true
    test_tar_failure_returns_bundle_dir || true
    test_bundle_output_safety || true

    harness_section "Manifest JSON Tests"
    test_manifest_json_valid || true
    test_manifest_lists_each_summary_once || true
    test_manifest_matches_bundle_inventory || true

    harness_section "Redaction Tests"
    test_complete_quoted_redaction || true
    test_redaction_catches_secrets || true
    test_binary_log_replaced_with_redaction_marker || true
    test_no_redact_flag || true

    harness_summary
}

main "$@"
