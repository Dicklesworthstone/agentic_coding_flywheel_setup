#!/usr/bin/env bash
# ============================================================
# Unit tests for verified installer entrypoint cache builder CLI
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

[[ "${1:-}" == "-q" ]] || exit 65

while (($#)); do
    case "$1" in
        -o)
            output="$2"
            shift 2
            ;;
        --connect-timeout|--max-time|--max-filesize|--proto|--proto-redir)
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

test_sha256_file() {
    local file="$1"
    local output=""
    local hash=""

    if [[ -x /usr/bin/sha256sum ]]; then
        output="$(/usr/bin/sha256sum "$file")" || return 1
    elif [[ -x /bin/sha256sum ]]; then
        output="$(/bin/sha256sum "$file")" || return 1
    elif [[ -x /usr/bin/shasum ]]; then
        output="$(/usr/bin/shasum -a 256 "$file")" || return 1
    else
        return 127
    fi
    read -r hash _ <<<"$output"
    [[ "$hash" =~ ^[0-9A-Fa-f]{64}$ ]] || return 1
    printf '%s\n' "${hash,,}"
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

    mkdir -p "$source_root/scripts/lib"
    printf '9.9.9-test\n' > "$source_root/VERSION"
    /bin/cp "$OFFLINE_PACK_SH" "$source_root/scripts/lib/offline_artifact_pack.sh"
    printf '#!/usr/bin/env bash\nprintf "rch fixture installer\\n"\n' > "$artifact_file"
    artifact_sha="$(test_sha256_file "$artifact_file")"
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

write_fixture_source_without_verified_installer() {
    local name="$1"
    local source_root="$ARTIFACT_DIR/$name/source"

    mkdir -p "$source_root/scripts/lib"
    printf '9.9.9-test\n' > "$source_root/VERSION"
    /bin/cp "$OFFLINE_PACK_SH" "$source_root/scripts/lib/offline_artifact_pack.sh"
    cat > "$source_root/acfs.manifest.yaml" <<'YAML'
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
YAML
    cat > "$source_root/checksums.yaml" <<'YAML'
installers:
  rch:
    url: "https://fixture.test/no-verified/rch-install.sh"
    sha256: "0000000000000000000000000000000000000000000000000000000000000000"
YAML

    printf '%s\n' "$source_root"
}

run_pack() {
    local name="$1"
    shift
    local output=""
    local status=0

    set +e
    output="$(ACFS_OFFLINE_PACK_TEST_MODE=true ACFS_OFFLINE_PACK_CURL_BIN="$ARTIFACT_DIR/bin/curl" ACFS_OFFLINE_PACK_TEST_ARTIFACTS_DIR="$ARTIFACT_DIR" PATH="$ARTIFACT_DIR/bin:$PATH" bash "$OFFLINE_PACK_SH" "$@" 2>&1)"
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
      .schema == "acfs.verified-installer-entrypoint-cache-build.v1" and
      .status == "pass" and
      .mode == "dry-run" and
      .pack.schema == "acfs.verified-installer-entrypoint-cache.v1" and
      .pack.packScope == "verified_installer_entrypoints" and
      .pack.executionNetworkMode == "required" and
      .pack.transitiveClosure == "not_bundled" and
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

test_single_backslash_is_refused_by_url_and_path_guards() {
    if ! (
        source "$OFFLINE_PACK_SH"
        source "$REPO_ROOT/scripts/lib/security.sh"

        ! offline_pack_installer_url_is_safe 'https://fixture.test/path\installer.sh'
        ! acfs_offline_pack_path_is_safe 'artifacts\stack.rch\installer.sh'
        ! offline_pack_installer_url_is_safe $'https://fixture.test/path/\033installer.sh'
        ! acfs_offline_pack_path_is_safe $'artifacts/stack.rch/\033installer.sh'
        offline_pack_installer_url_is_safe 'https://fixture.test/path/installer.sh'
        acfs_offline_pack_path_is_safe 'artifacts/stack.rch/installer.sh'
    ); then
        return 1
    fi

    pass "single_backslash_is_refused_by_url_and_path_guards"
}

test_build_writes_manifest_and_verified_artifact() {
    local source_root output_dir output status manifest artifact_path expected_sha
    local builder_env_sha source_index_sha
    source_root="$(write_fixture_source build valid)"
    output_dir="$ARTIFACT_DIR/build/output"

    output="$(run_pack build build --json --source-root "$source_root" --output "$output_dir" --module stack.rch --expires-days 7)"
    status="$(cat "$ARTIFACT_DIR/build.exit")"
    manifest="$output_dir/acfs-installer-cache/manifest.json"
    artifact_path="$output_dir/acfs-installer-cache/artifacts/stack.rch/rch-install.sh"
    expected_sha="$(test_sha256_file "$artifact_path")"
    builder_env_sha="$(test_sha256_file "$output_dir/acfs-installer-cache/provenance/builder-env.json")"
    source_index_sha="$(test_sha256_file "$output_dir/acfs-installer-cache/provenance/source-index.json")"

    [[ "$status" -eq 0 ]] || return 1
    [[ -f "$manifest" ]] || return 1
    [[ -f "$artifact_path" ]] || return 1
    [[ ! -e "$output_dir/acfs-installer-cache/scripts" ]] || return 1
    [[ ! -e "$output_dir/acfs-installer-cache/acfs" ]] || return 1
    jq -e \
      --arg expectedSha "$expected_sha" \
      --arg builderEnvSha "$builder_env_sha" \
      --arg sourceIndexSha "$source_index_sha" '
      .schema == "acfs.verified-installer-entrypoint-cache.v1" and
      .generatedBy == "acfs installer-cache build" and
      .packMode == "entrypoint-cache" and
      .packScope == "verified_installer_entrypoints" and
      (.targets | length) == 1 and
      .targets[0].os == "ubuntu" and
      .targets[0].version == "25.10" and
      (.targets[0].architecture == "x86_64" or .targets[0].architecture == "aarch64") and
      .policy.executionNetworkMode == "required" and
      .policy.transitiveClosure == "not_bundled" and
      .policy.bootstrap == "not_bundled" and
      .policy.verifiedInstallerPolicy == "must_match_checksums_yaml" and
      .policy.partialPackPolicy == "refuse_unless_best_effort_diagnostic" and
      .acfs.sourceRef == "unknown" and
      .acfs.sourceCommit == "unknown" and
      .acfs.sourceTreeState == "unversioned" and
      .acfs.provenanceBuilderEnvSha256 == $builderEnvSha and
      .acfs.provenanceSourceIndexSha256 == $sourceIndexSha and
      .modules[0].id == "stack.rch" and
      .modules[0].coverage == "entrypoint_cached" and
      .modules[0].verifiedInstallerKey == "rch" and
      .modules[0].verifiedInstallerRunner == "bash" and
      .artifacts[0].kind == "verified_installer_entrypoint" and
      .artifacts[0].architecture == .targets[0].architecture and
      .artifacts[0].sha256 == $expectedSha and
      .artifacts[0].path == "artifacts/stack.rch/rch-install.sh" and
      .failures == []
    ' "$manifest" >/dev/null || return 1
    jq -e '.status == "pass" and .output.packMode == "entrypoint-cache" and .output.published == true and .output.stagingRoot == ""' <<<"$output" >/dev/null || return 1

    pass "build_writes_manifest_and_verified_artifact"
}

test_build_refuses_dirty_versioned_source_surfaces() {
    local source_root output_dir output status
    source_root="$(write_fixture_source dirty-source valid)"
    output_dir="$ARTIFACT_DIR/dirty-source/output"

    git -C "$source_root" init -q -b main
    git -C "$source_root" add -- VERSION acfs.manifest.yaml checksums.yaml scripts/lib/offline_artifact_pack.sh
    git -C "$source_root" -c user.name=ACFS -c user.email=acfs@example.invalid commit -q -m fixture
    printf '# uncommitted builder mutation\n' >> "$source_root/scripts/lib/offline_artifact_pack.sh"

    output="$(run_pack dirty-source build --json --source-root "$source_root" --output "$output_dir" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/dirty-source.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_source_dirty"))
    ' <<<"$output" >/dev/null || return 1
    [[ ! -e "$output_dir" ]] || return 1

    pass "build_refuses_dirty_versioned_source_surfaces"
}

test_build_binds_clean_versioned_source_commit() {
    local source_root output_dir output status expected_commit manifest
    source_root="$(write_fixture_source clean-source valid)"
    output_dir="$ARTIFACT_DIR/clean-source/output"
    manifest="$output_dir/acfs-installer-cache/manifest.json"

    git -C "$source_root" init -q -b main
    git -C "$source_root" add -- VERSION acfs.manifest.yaml checksums.yaml scripts/lib/offline_artifact_pack.sh
    git -C "$source_root" -c user.name=ACFS -c user.email=acfs@example.invalid commit -q -m fixture
    expected_commit="$(git -C "$source_root" rev-parse HEAD)"

    output="$(run_pack clean-source build --json --source-root "$source_root" --output "$output_dir" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/clean-source.exit")"

    [[ "$status" -eq 0 ]] || return 1
    jq -e --arg commit "$expected_commit" '
      .acfs.sourceCommit == $commit and
      .acfs.sourceTreeState == "clean"
    ' "$manifest" >/dev/null || return 1
    jq -e '.status == "pass"' <<<"$output" >/dev/null || return 1

    pass "build_binds_clean_versioned_source_commit"
}

test_build_does_not_bind_custom_inputs_to_source_commit() {
    local source_root output_dir output status manifest custom_manifest
    source_root="$(write_fixture_source custom-inputs valid)"
    output_dir="$ARTIFACT_DIR/custom-inputs/output"
    manifest="$output_dir/acfs-installer-cache/manifest.json"
    custom_manifest="$ARTIFACT_DIR/custom-inputs/reviewed.manifest.yaml"

    git -C "$source_root" init -q -b main
    git -C "$source_root" add -- VERSION acfs.manifest.yaml checksums.yaml scripts/lib/offline_artifact_pack.sh
    git -C "$source_root" -c user.name=ACFS -c user.email=acfs@example.invalid commit -q -m fixture
    cp "$source_root/acfs.manifest.yaml" "$custom_manifest"

    output="$(run_pack custom-inputs build --json --source-root "$source_root" --manifest-file "$custom_manifest" --output "$output_dir" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/custom-inputs.exit")"

    [[ "$status" -eq 0 ]] || return 1
    jq -e '
      .acfs.sourceRef == "unknown" and
      .acfs.sourceCommit == "unknown" and
      .acfs.sourceTreeState == "custom-inputs"
    ' "$manifest" >/dev/null || return 1
    jq -e '
      .status == "warn" and
      any(.validation.warnings[]; contains("pack_source_custom_inputs"))
    ' <<<"$output" >/dev/null || return 1

    pass "build_does_not_bind_custom_inputs_to_source_commit"
}

test_build_refuses_symlinked_source_input() {
    local source_root output_dir output status
    source_root="$(write_fixture_source symlink-source valid)"
    output_dir="$ARTIFACT_DIR/symlink-source/output"
    mv "$source_root/VERSION" "$source_root/VERSION.real"
    ln -s VERSION.real "$source_root/VERSION"

    output="$(run_pack symlink-source build --json --source-root "$source_root" --output "$output_dir" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/symlink-source.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_source_unsafe"))
    ' <<<"$output" >/dev/null || return 1
    [[ ! -e "$output_dir" ]] || return 1

    pass "build_refuses_symlinked_source_input"
}

test_build_ignores_path_poisoned_pack_tools() {
    local source_root output_dir output status tool marker
    local poison_markers=()
    local poison_tools=(jq sha256sum shasum awk wc tr date uname cp mkdir mktemp mv find git)
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
    [[ ! -e "$output_dir/acfs-installer-cache" ]] || return 1
    jq -e '.output.published == false and .output.manifestPath == ""' <<<"$output" >/dev/null || return 1

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

test_default_selection_refuses_zero_verified_installers() {
    local source_root output status
    source_root="$(write_fixture_source_without_verified_installer no-verified)"

    output="$(run_pack no-verified build --dry-run --json --source-root "$source_root")"
    status="$(cat "$ARTIFACT_DIR/no-verified.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_unbundled_required_module: no verified_installer modules were selected"))
    ' <<<"$output" >/dev/null || return 1

    pass "default_selection_refuses_zero_verified_installers"
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
    [[ ! -e "$output_dir/acfs-installer-cache" ]] || return 1
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

test_invalid_module_markdown_reports_without_crashing() {
    local source_root output status
    source_root="$(write_fixture_source invalid-markdown valid)"

    output="$(run_pack invalid-markdown build --dry-run --markdown --source-root "$source_root" --module stack.nope)"
    status="$(cat "$ARTIFACT_DIR/invalid-markdown.exit")"

    [[ "$status" -eq 1 ]] || return 1
    [[ "$output" == *"pack_unknown_module: stack.nope"* ]] || return 1
    [[ "$output" == *"stack.nope (no verified installer) no approved URL"* ]] || return 1
    [[ "$output" != *"bad array subscript"* ]] || return 1

    pass "invalid_module_markdown_reports_without_crashing"
}

test_duplicate_checksum_installer_key_is_refused() {
    local source_root output status
    source_root="$(write_fixture_source duplicate-checksum-key valid)"
    cat >> "$source_root/checksums.yaml" <<'YAML'
  rch:
    url: "https://fixture.test/duplicate-checksum-key/rch-install.sh"
    sha256: "0000000000000000000000000000000000000000000000000000000000000000"
YAML

    output="$(run_pack duplicate-checksum-key build --dry-run --json --source-root "$source_root" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/duplicate-checksum-key.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_checksums_mismatch: duplicate installer key rch"))
    ' <<<"$output" >/dev/null || return 1

    pass "duplicate_checksum_installer_key_is_refused"
}

test_duplicate_module_selection_is_refused() {
    local source_root output status
    source_root="$(write_fixture_source duplicate-selection valid)"

    output="$(run_pack duplicate-selection build --dry-run --json --source-root "$source_root" --module stack.rch --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/duplicate-selection.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_duplicate_module: module selected more than once: stack.rch"))
    ' <<<"$output" >/dev/null || return 1

    pass "duplicate_module_selection_is_refused"
}

test_best_effort_does_not_downgrade_structural_errors() {
    local source_root output status
    source_root="$(write_fixture_source best-effort-structural valid)"

    output="$(run_pack best-effort-structural build --dry-run --best-effort --json --source-root "$source_root" --module stack.nope)"
    status="$(cat "$ARTIFACT_DIR/best-effort-structural.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_unknown_module: stack.nope"))
    ' <<<"$output" >/dev/null || return 1

    pass "best_effort_does_not_downgrade_structural_errors"
}

test_clean_source_commit_cannot_claim_a_different_executing_builder() {
    local source_root output_dir output status
    source_root="$(write_fixture_source builder-mismatch valid)"
    output_dir="$ARTIFACT_DIR/builder-mismatch/output"
    printf '#!/usr/bin/env bash\nprintf "different builder bytes\\n"\n' > "$source_root/scripts/lib/offline_artifact_pack.sh"

    git -C "$source_root" init -q -b main
    git -C "$source_root" add -- VERSION acfs.manifest.yaml checksums.yaml scripts/lib/offline_artifact_pack.sh
    git -C "$source_root" -c user.name=ACFS -c user.email=acfs@example.invalid commit -q -m fixture

    output="$(run_pack builder-mismatch build --json --source-root "$source_root" --output "$output_dir" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/builder-mismatch.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      .output.published == false and
      .output.manifestPath == "" and
      any(.validation.errors[]; contains("pack_source_changed: executing builder does not match sourceCommit"))
    ' <<<"$output" >/dev/null || return 1
    [[ ! -e "$output_dir/acfs-installer-cache" ]] || return 1

    pass "clean_source_commit_cannot_claim_a_different_executing_builder"
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
    manifest="$output_dir/acfs-installer-cache/manifest.json"

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

    output="$(run_pack timeout-too-large build --dry-run --json --source-root "$source_root" --module stack.rch --timeout 3601)"
    status="$(cat "$ARTIFACT_DIR/timeout-too-large.exit")"
    [[ "$status" -eq 2 ]] || return 1
    [[ "$output" == *"--timeout must be no greater than 3600"* ]] || return 1

    output="$(run_pack expiry-too-large build --dry-run --json --source-root "$source_root" --module stack.rch --expires-days 3651)"
    status="$(cat "$ARTIFACT_DIR/expiry-too-large.exit")"
    [[ "$status" -eq 2 ]] || return 1
    [[ "$output" == *"--expires-days must be no greater than 3650"* ]] || return 1

    pass "timeout_option_is_validated_and_recorded"
}

test_invalid_ubuntu_target_is_refused_before_publication() {
    local source_root output status
    source_root="$(write_fixture_source invalid-ubuntu valid)"

    output="$(run_pack invalid-ubuntu build --dry-run --json --source-root "$source_root" --module stack.rch --ubuntu-version rolling)"
    status="$(cat "$ARTIFACT_DIR/invalid-ubuntu.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("pack_ubuntu_unsupported"))
    ' <<<"$output" >/dev/null || return 1

    pass "invalid_ubuntu_target_is_refused_before_publication"
}

test_uncreatable_output_emits_structured_refusal() {
    local source_root blocker output status
    source_root="$(write_fixture_source output-unwritable valid)"
    blocker="$ARTIFACT_DIR/output-unwritable/not-a-directory"
    mkdir -p "${blocker%/*}"
    printf 'blocks child creation\n' > "$blocker"

    output="$(run_pack output-unwritable build --json --source-root "$source_root" --output "$blocker/child" --module stack.rch)"
    status="$(cat "$ARTIFACT_DIR/output-unwritable.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      .output.published == false and
      any(.validation.errors[]; contains("pack_output_unwritable"))
    ' <<<"$output" >/dev/null || return 1

    pass "uncreatable_output_emits_structured_refusal"
}

test_supported_no_target_directory_failure_never_uses_weaker_fallback() {
    if ! (
        source "$OFFLINE_PACK_SH"
        calls=0
        offline_pack_mv_supports_no_target_directory() { return 0; }
        offline_pack_mv() {
            calls=$((calls + 1))
            return 1
        }

        ! offline_pack_publish_staging "/nonexistent/acfs-staging" "/nonexistent/acfs-pack"
        [[ "$calls" -eq 1 ]]
    ); then
        return 1
    fi

    pass "supported_no_target_directory_failure_never_uses_weaker_fallback"
}

test_bsd_publish_race_is_detected_after_nested_move() {
    local race_root="$ARTIFACT_DIR/publish-race"
    local staging_root="$race_root/.acfs-installer-cache.build.fixture"
    local pack_root="$race_root/acfs-installer-cache"

    mkdir -p "$staging_root" "$pack_root"
    printf '{"builder":"ours"}\n' > "$staging_root/manifest.json"
    printf '{"builder":"racer"}\n' > "$pack_root/manifest.json"

    if ! (
        source "$OFFLINE_PACK_SH"
        offline_pack_mv_supports_no_target_directory() { return 1; }
        OFFLINE_PACK_STAGING_ROOT="$staging_root"

        ! offline_pack_publish_staging "$staging_root" "$pack_root"
        [[ "$OFFLINE_PACK_STAGING_ROOT" == "$pack_root/${staging_root##*/}" ]]
        [[ -f "$OFFLINE_PACK_STAGING_ROOT/manifest.json" ]]
        [[ "$(<"$pack_root/manifest.json")" == '{"builder":"racer"}' ]]
    ); then
        return 1
    fi

    pass "bsd_publish_race_is_detected_after_nested_move"
}

run_all_tests() {
    local test_name=""
    local tests=(
        test_dry_run_json_uses_manifest_and_checksums
        test_non_https_source_is_refused
        test_single_backslash_is_refused_by_url_and_path_guards
        test_build_writes_manifest_and_verified_artifact
        test_build_refuses_dirty_versioned_source_surfaces
        test_build_binds_clean_versioned_source_commit
        test_build_does_not_bind_custom_inputs_to_source_commit
        test_build_refuses_symlinked_source_input
        test_build_ignores_path_poisoned_pack_tools
        test_checksum_mismatch_fails_closed
        test_unknown_module_is_refused
        test_non_verified_module_is_refused
        test_default_selection_refuses_zero_verified_installers
        test_invalid_module_id_cannot_escape_pack_root
        test_duplicate_module_id_is_refused
        test_invalid_module_markdown_reports_without_crashing
        test_duplicate_checksum_installer_key_is_refused
        test_duplicate_module_selection_is_refused
        test_best_effort_does_not_downgrade_structural_errors
        test_clean_source_commit_cannot_claim_a_different_executing_builder
        test_invalid_verified_installer_runner_is_refused
        test_best_effort_records_download_failure
        test_timeout_option_is_validated_and_recorded
        test_invalid_ubuntu_target_is_refused_before_publication
        test_uncreatable_output_emits_structured_refusal
        test_supported_no_target_directory_failure_never_uses_weaker_fallback
        test_bsd_publish_race_is_detected_after_nested_move
    )

    for test_name in "${tests[@]}"; do
        if ! "$test_name"; then
            fail "$test_name" "Installer entrypoint cache builder contract failed"
        fi
    done

    echo ""
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

run_all_tests "$@"
