#!/usr/bin/env bash
# ============================================================
# Unit tests for offline artifact pack builder CLI
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OFFLINE_PACK_SH="$REPO_ROOT/scripts/lib/offline_artifact_pack.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_OFFLINE_PACK_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-offline-pack-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

mkdir -p "$ARTIFACT_DIR"

write_fake_curl() {
    mkdir -p "$ARTIFACT_DIR/bin"
    cat > "$ARTIFACT_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output=""
url=""

while (($#)); do
    case "$1" in
        -o)
            output="$2"
            shift 2
            ;;
        --connect-timeout|--max-time|--proto|--proto-redir)
            shift 2
            ;;
        -*)
            shift
            ;;
        *)
            url="$1"
            shift
            ;;
    esac
done

[[ -n "$output" && -n "$url" ]] || exit 64

case "$url" in
    https://fixture.test/*/*)
        path="${url#https://fixture.test/}"
        name="${path%%/*}"
        file_name="${path#*/}"
        source_path="${ACFS_OFFLINE_PACK_TEST_ARTIFACTS_DIR:?}/$name/$file_name"
        [[ -f "$source_path" ]] || exit 22
        /bin/cp "$source_path" "$output"
        ;;
    *)
        exit 22
        ;;
esac
EOF
    chmod +x "$ARTIFACT_DIR/bin/curl"
}

write_fake_curl

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    [[ -n "${2:-}" ]] && echo "  Reason: $2"
}

write_fixture_source() {
    local name="$1"
    local mode="${2:-valid}"
    local module_id="${3:-stack.rch}"
    local runner="${4:-bash}"
    local source_root="$ARTIFACT_DIR/$name/source"
    local artifact_file="$ARTIFACT_DIR/$name/rch-install.sh"
    local artifact_sha=""
    local artifact_url=""

    mkdir -p "$source_root/scripts/lib" "$source_root/scripts/generated" "$source_root/acfs/zsh"
    printf '9.9.9-test\n' > "$source_root/VERSION"
    printf '# fixture lib\n' > "$source_root/scripts/lib/fixture.sh"
    printf '# fixture generated\n' > "$source_root/scripts/generated/manifest_index.sh"
    printf '# fixture acfs config\n' > "$source_root/acfs/zsh/acfs.zshrc"
    printf '#!/usr/bin/env bash\nprintf "rch fixture installer\\n"\n' > "$artifact_file"
    artifact_sha="$(sha256sum "$artifact_file" | awk '{print $1}')"
    artifact_url="https://fixture.test/$name/rch-install.sh"

    case "$mode" in
        file-url)
            artifact_url="file://$artifact_file"
            ;;
        mismatch)
            artifact_sha="0000000000000000000000000000000000000000000000000000000000000000"
            ;;
        missing)
            artifact_url="https://fixture.test/$name/missing-install.sh"
            ;;
    esac

    cat > "$source_root/acfs.manifest.yaml" <<YAML
version: 2
name: fixture
id: acfs
modules:
  - id: base.system
    description: Base packages
    category: base
    phase: 1
    run_as: root
    optional: false
    enabled_by_default: true
    install: []
    verify: []

  - id: $module_id
    description: Remote compilation helper
    category: stack
    phase: 9
    run_as: target_user
    optional: false
    enabled_by_default: true
    verified_installer:
      tool: rch
      runner: $runner
      args: ["--easy-mode"]
    install: []
    verify: []
YAML

    cat > "$source_root/checksums.yaml" <<YAML
installers:
  rch:
    url: "$artifact_url"
    sha256: "$artifact_sha"
YAML

    printf '%s\n' "$source_root"
}

run_pack() {
    local name="$1"
    shift
    local output=""
    local status=0

    set +e
    output="$(ACFS_OFFLINE_PACK_CURL_BIN="$ARTIFACT_DIR/bin/curl" ACFS_OFFLINE_PACK_TEST_ARTIFACTS_DIR="$ARTIFACT_DIR" PATH="$ARTIFACT_DIR/bin:$PATH" bash "$OFFLINE_PACK_SH" "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

test_dry_run_json_uses_manifest_and_checksums() {
    local source_root output status
    source_root="$(write_fixture_source dry-run valid)"

    output="$(run_pack dry-run build --dry-run --json --source-root "$source_root" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/dry-run.exit")"

    [[ "$status" -eq 0 ]] || return 1
    jq -e '
      .schema == "acfs.offline-artifact-pack-build.v1" and
      .status == "pass" and
      .mode == "dry-run" and
      .pack.schema == "acfs.offline-artifact-pack.v1" and
      .pack.downloadTimeoutSeconds == 60 and
      .pack.modules[0].moduleId == "stack.rch" and
      .pack.modules[0].verifiedInstallerKey == "rch" and
      (.pack.modules[0].sourceUrl | startswith("https://"))
    ' <<<"$output" >/dev/null || return 1

    pass "dry_run_json_uses_manifest_and_checksums"
}

test_non_https_source_is_refused() {
    local source_root output status
    source_root="$(write_fixture_source non-https file-url)"

    output="$(run_pack non-https build --dry-run --json --source-root "$source_root" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/non-https.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_non_https_source"))
    ' <<<"$output" >/dev/null || return 1

    pass "non_https_source_is_refused"
}

test_build_writes_manifest_and_verified_artifact() {
    local source_root output_dir output status manifest artifact_path expected_sha
    source_root="$(write_fixture_source build valid)"
    output_dir="$ARTIFACT_DIR/build/output"

    output="$(run_pack build build --json --source-root "$source_root" --output "$output_dir" --module stack.rch --expires-days 7)"
    status="$(cat "$ARTIFACT_DIR/build.exit")"
    manifest="$output_dir/acfs-offline-pack/manifest.json"
    artifact_path="$output_dir/acfs-offline-pack/artifacts/stack.rch/rch-install.sh"
    expected_sha="$(sha256sum "$artifact_path" | awk '{print $1}')"

    [[ "$status" -eq 0 ]] || return 1
    [[ -f "$manifest" ]] || return 1
    [[ -f "$artifact_path" ]] || return 1
    [[ -d "$output_dir/acfs-offline-pack/scripts/lib" ]] || return 1
    [[ -d "$output_dir/acfs-offline-pack/scripts/generated" ]] || return 1
    [[ -d "$output_dir/acfs-offline-pack/acfs" ]] || return 1
    jq -e --arg expectedSha "$expected_sha" '
      .schema == "acfs.offline-artifact-pack.v1" and
      .packMode == "complete" and
      .policy.verifiedInstallerPolicy == "must_match_checksums_yaml" and
      .modules[0].id == "stack.rch" and
      .modules[0].verifiedInstallerKey == "rch" and
      .artifacts[0].sha256 == $expectedSha and
      .artifacts[0].path == "artifacts/stack.rch/rch-install.sh" and
      .failures == []
    ' "$manifest" >/dev/null || return 1
    jq -e '.status == "pass" and .output.packMode == "complete"' <<<"$output" >/dev/null || return 1

    pass "build_writes_manifest_and_verified_artifact"
}

test_build_ignores_path_poisoned_pack_tools() {
    local source_root output_dir output status tool marker
    local poison_markers=()
    local poison_tools=(jq sha256sum shasum awk wc tr date uname cp mkdir find git)
    source_root="$(write_fixture_source trusted-tools valid)"
    output_dir="$ARTIFACT_DIR/trusted-tools/output"

    for tool in "${poison_tools[@]}"; do
        marker="$ARTIFACT_DIR/trusted-tools-$tool-used"
        poison_markers+=("$marker")
        cat > "$ARTIFACT_DIR/bin/$tool" <<EOF
#!/usr/bin/env bash
printf 'poisoned $tool\\n' > "$marker"
exit 99
EOF
        chmod +x "$ARTIFACT_DIR/bin/$tool"
    done

    output="$(run_pack trusted-tools build --json --source-root "$source_root" --output "$output_dir" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/trusted-tools.exit")"

    [[ "$status" -eq 0 ]] || return 1
    for marker in "${poison_markers[@]}"; do
        [[ ! -e "$marker" ]] || return 1
    done
    jq -e '.status == "pass" and .pack.artifacts[0].verifiedInstallerKey == "rch"' <<<"$output" >/dev/null || return 1

    pass "build_ignores_path_poisoned_pack_tools"
}

test_checksum_mismatch_fails_closed() {
    local source_root output_dir output status
    source_root="$(write_fixture_source mismatch mismatch)"
    output_dir="$ARTIFACT_DIR/mismatch/output"

    output="$(run_pack mismatch build --json --source-root "$source_root" --output "$output_dir" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/mismatch.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_hash_mismatch"))
    ' <<<"$output" >/dev/null || return 1
    [[ ! -f "$output_dir/acfs-offline-pack/manifest.json" ]] || return 1

    pass "checksum_mismatch_fails_closed"
}

test_unknown_module_is_refused() {
    local source_root output status
    source_root="$(write_fixture_source unknown valid)"

    output="$(run_pack unknown build --dry-run --json --source-root "$source_root" --module stack.nope)"
    status="$(cat "$ARTIFACT_DIR/unknown.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_unknown_module"))
    ' <<<"$output" >/dev/null || return 1

    pass "unknown_module_is_refused"
}

test_non_verified_module_is_refused() {
    local source_root output status
    source_root="$(write_fixture_source unbundled valid)"

    output="$(run_pack unbundled build --dry-run --json --source-root "$source_root" --module base.system)"
    status="$(cat "$ARTIFACT_DIR/unbundled.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_unbundled_required_module"))
    ' <<<"$output" >/dev/null || return 1

    pass "non_verified_module_is_refused"
}

test_invalid_module_id_cannot_escape_pack_root() {
    local source_root output_dir escaped_path output status
    local malicious_id="../../../escaped"
    source_root="$(write_fixture_source invalid-module valid "$malicious_id")"
    output_dir="$ARTIFACT_DIR/invalid-module/output"
    escaped_path="$ARTIFACT_DIR/invalid-module/escaped"

    output="$(run_pack invalid-module build --json --source-root "$source_root" --output "$output_dir" --module "$malicious_id")"
    status="$(cat "$ARTIFACT_DIR/invalid-module.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_malformed_manifest: invalid module id"))
    ' <<<"$output" >/dev/null || return 1
    [[ ! -e "$output_dir" ]] || return 1
    [[ ! -e "$escaped_path" ]] || return 1

    pass "invalid_module_id_cannot_escape_pack_root"
}

test_duplicate_module_id_is_refused() {
    local source_root output status
    source_root="$(write_fixture_source duplicate-module valid)"
    cat >> "$source_root/acfs.manifest.yaml" <<'YAML'

  - id: stack.rch
    description: Duplicate module
    install: []
    verify: []
YAML

    output="$(run_pack duplicate-module build --dry-run --json --source-root "$source_root" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/duplicate-module.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_malformed_manifest: duplicate module id stack.rch"))
    ' <<<"$output" >/dev/null || return 1

    pass "duplicate_module_id_is_refused"
}

test_invalid_verified_installer_runner_is_refused() {
    local source_root output status
    source_root="$(write_fixture_source invalid-runner valid stack.rch python)"

    output="$(run_pack invalid-runner build --dry-run --json --source-root "$source_root" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/invalid-runner.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_malformed_manifest: invalid verified_installer runner for stack.rch"))
    ' <<<"$output" >/dev/null || return 1

    pass "invalid_verified_installer_runner_is_refused"
}

test_best_effort_records_download_failure() {
    local source_root output_dir output status manifest
    source_root="$(write_fixture_source best-effort missing)"
    output_dir="$ARTIFACT_DIR/best-effort/output"

    output="$(run_pack best-effort build --json --best-effort --source-root "$source_root" --output "$output_dir" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/best-effort.exit")"
    manifest="$output_dir/acfs-offline-pack/manifest.json"

    [[ "$status" -eq 0 ]] || return 1
    [[ -f "$manifest" ]] || return 1
    jq -e '
      .status == "warn" and
      .output.packMode == "diagnostic" and
      .pack.failures[0].code == "pack_download_failed"
    ' <<<"$output" >/dev/null || return 1
    jq -e '
      .packMode == "diagnostic" and
      .failures[0].code == "pack_download_failed" and
      .artifacts == []
    ' "$manifest" >/dev/null || return 1

    pass "best_effort_records_download_failure"
}

test_timeout_option_is_validated_and_recorded() {
    local source_root output status
    source_root="$(write_fixture_source timeout valid)"

    output="$(run_pack timeout-plan build --dry-run --json --source-root "$source_root" --module stack.rch --timeout 1)"
    status="$(cat "$ARTIFACT_DIR/timeout-plan.exit")"
    [[ "$status" -eq 0 ]] || return 1
    jq -e '.pack.downloadTimeoutSeconds == 1' <<<"$output" >/dev/null || return 1

    output="$(run_pack timeout-invalid build --dry-run --json --source-root "$source_root" --module stack.rch --timeout 0)"
    status="$(cat "$ARTIFACT_DIR/timeout-invalid.exit")"
    [[ "$status" -eq 2 ]] || return 1
    [[ "$output" == *"--timeout must be a positive integer"* ]] || return 1

    pass "timeout_option_is_validated_and_recorded"
}

run_all_tests() {
    local test_name=""
    local tests=(
        test_dry_run_json_uses_manifest_and_checksums
        test_non_https_source_is_refused
        test_build_writes_manifest_and_verified_artifact
        test_build_ignores_path_poisoned_pack_tools
        test_checksum_mismatch_fails_closed
        test_unknown_module_is_refused
        test_non_verified_module_is_refused
        test_invalid_module_id_cannot_escape_pack_root
        test_duplicate_module_id_is_refused
        test_invalid_verified_installer_runner_is_refused
        test_best_effort_records_download_failure
        test_timeout_option_is_validated_and_recorded
    )

    for test_name in "${tests[@]}"; do
        if ! "$test_name"; then
            fail "$test_name" "Offline artifact pack builder contract failed"
        fi
    done

    echo ""
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

run_all_tests "$@"
