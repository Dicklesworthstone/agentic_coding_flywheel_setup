#!/usr/bin/env bash
# ============================================================
# Unit tests for verified installer entrypoint cache consumption in verify_checksum
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="${ACFS_INSTALLER_CACHE_CONSUMER_TEST_DIR:-${TMPDIR:-/tmp}/acfs-installer-cache-consumer-$(date +%Y%m%d-%H%M%S)-$$}"
TESTS_PASSED=0
TESTS_FAILED=0
CACHE_TEST_NETWORK_CALLS=0

TOOL="fixture_tool"
URL="https://example.com/acfs/fixture-install.sh"
CONTENT='printf "cached installer fixture\n"'

mkdir -p "$TEST_ROOT"
export CHECKSUMS_FILE="$TEST_ROOT/current-checksums.yaml"
TEST_TIMEOUT_BIN="$TEST_ROOT/timeout"
printf '#!/usr/bin/env bash\nshift\nexec "$@"\n' > "$TEST_TIMEOUT_BIN"
chmod +x "$TEST_TIMEOUT_BIN"

sha_text() {
    printf '%s' "$1" | sha256sum | awk '{print $1}'
}

write_checksums() {
    local output_file="$1"
    local artifact_sha="$2"

    cat > "$output_file" <<EOF
installers:
  $TOOL:
    url: "$URL"
    sha256: "$artifact_sha"
EOF
}

ARTIFACT_SHA="$(sha_text "$CONTENT")"
write_checksums "$CHECKSUMS_FILE" "$ARTIFACT_SHA"

# shellcheck source=scripts/lib/security.sh
source "$REPO_ROOT/scripts/lib/security.sh"

acfs_security_required_binary_path() {
    local name="${1:-}"
    local path=""

    if [[ "$name" == "timeout" ]]; then
        printf '%s\n' "$TEST_TIMEOUT_BIN"
        return 0
    fi
    path="$(acfs_security_system_binary_path "$name" 2>/dev/null || true)"
    [[ -n "$path" ]] || return 127
    printf '%s\n' "$path"
}

acfs_security_date() {
    case "$*" in
        "-u -d 2099-01-01T00:00:00Z +%s") printf '4070908800\n' ;;
        "-u -d 2000-01-01T00:00:00Z +%s") printf '946684800\n' ;;
        "-u +%s") printf '2000000000\n' ;;
        *) /usr/bin/date "$@" ;;
    esac
}

# The consumer contract is Ubuntu-specific. Keep fixture metadata deterministic
# when this static/unit harness is invoked from a non-Ubuntu development host.
acfs_offline_pack_current_ubuntu_version() {
    printf '25.10\n'
}

# Session policy forbids test cleanup from deleting diagnostic evidence.
_acfs_remove_temp_files() {
    :
}

CURRENT_ARCH="$(acfs_offline_pack_current_arch)"
MANIFEST_SHA="$(calculate_file_sha256 "$REPO_ROOT/acfs.manifest.yaml")"
CHECKSUMS_SHA="$(calculate_file_sha256 "$CHECKSUMS_FILE")"
FUTURE_EXPIRES="2099-01-01T00:00:00Z"
PAST_EXPIRES="2000-01-01T00:00:00Z"

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    [[ -n "${2:-}" ]] && echo "  Reason: $2"
}

other_arch() {
    if [[ "$CURRENT_ARCH" == "x86_64" ]]; then
        printf 'aarch64\n'
    else
        printf 'x86_64\n'
    fi
}

write_pack() {
    local name="$1"
    local expires_at="$2"
    local arch="$3"
    local include_artifact="${4:-yes}"
    local artifact_rel="${5:-artifacts/fixture.module/${TOOL}-install.sh}"
    local fixture_mode="${6:-valid}"
    local output_dir="$TEST_ROOT/$name"
    local pack_root="$output_dir/acfs-installer-cache"
    local artifact_path="$pack_root/$artifact_rel"
    local artifact_size=""
    local artifact_content="$CONTENT"
    local artifacts_json="[]"

    mkdir -p "$pack_root/artifacts"
    write_checksums "$pack_root/checksums.yaml" "$ARTIFACT_SHA"
    /bin/cp "$REPO_ROOT/acfs.manifest.yaml" "$pack_root/acfs.manifest.yaml"

    if [[ "$include_artifact" == "yes" ]]; then
        mkdir -p "${artifact_path%/*}"
        if [[ "$fixture_mode" == "tampered-artifact" ]]; then
            artifact_content='tampered content'
            artifact_size="$(printf '%s' "$CONTENT" | wc -c | tr -d '[:space:]')"
        fi
        printf '%s' "$artifact_content" > "$artifact_path"
        if [[ -z "$artifact_size" ]]; then
            artifact_size="$(acfs_security_file_size "$artifact_path")"
        fi
    elif [[ "$include_artifact" == "manifest-only" ]]; then
        artifact_size="$(printf '%s' "$CONTENT" | wc -c | tr -d '[:space:]')"
    fi

    if [[ "$include_artifact" == "yes" || "$include_artifact" == "manifest-only" ]]; then
        artifacts_json="$(
            jq -n \
                --arg id "fixture.module:$TOOL" \
                --arg moduleId "fixture.module" \
                --arg tool "$TOOL" \
                --arg path "$artifact_rel" \
                --arg sourceUrl "$URL" \
                --arg sha "$ARTIFACT_SHA" \
                --arg arch "$arch" \
                --argjson sizeBytes "$artifact_size" \
                '[{
                    id: $id,
                    moduleId: $moduleId,
                    kind: "verified_installer_entrypoint",
                    verifiedInstallerKey: $tool,
                    path: $path,
                    sourceUrl: $sourceUrl,
                    sha256: $sha,
                    sizeBytes: $sizeBytes,
                    architecture: $arch
                }]'
        )"
    fi

    jq -n \
        --arg generatedAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg expiresAt "$expires_at" \
        --arg manifestSha "$MANIFEST_SHA" \
        --arg checksumsSha "$CHECKSUMS_SHA" \
        --arg arch "$arch" \
        --arg fixtureMode "$fixture_mode" \
        --argjson artifacts "$artifacts_json" \
        '{
            schema: "acfs.verified-installer-entrypoint-cache.v1",
            schemaVersion: 1,
            generatedBy: "acfs installer-cache build",
            generatedAt: $generatedAt,
            expiresAt: $expiresAt,
            staleAfterDays: 30,
            packMode: "entrypoint-cache",
            packScope: "verified_installer_entrypoints",
            acfs: {
                version: "test",
                sourceRef: "main",
                sourceCommit: "test",
                sourceTreeState: "clean",
                manifestSha256: $manifestSha,
                checksumsYamlSha256: $checksumsSha
            },
            targets: [{os: "ubuntu", version: "25.10", architecture: $arch}],
            modules: [{
                id: "fixture.module",
                coverage: "entrypoint_cached",
                verifiedInstallerKey: "fixture_tool",
                verifiedInstallerRunner: "bash",
                verifiedInstallerArgsRaw: ""
            }],
            artifacts: $artifacts,
            failures: [],
            policy: {
                entrypointFetchMode: "cache_required",
                executionNetworkMode: "required",
                transitiveClosure: "not_bundled",
                bootstrap: "not_bundled",
                verifiedInstallerPolicy: "must_match_checksums_yaml",
                partialPackPolicy: "refuse_unless_best_effort_diagnostic"
            }
        }
        | if $fixtureMode == "missing-policy" then
            del(.policy.executionNetworkMode)
          elif $fixtureMode == "duplicate-artifact" then
            .artifacts += [.artifacts[0]]
          elif $fixtureMode == "missing-artifact-arch" then
            del(.artifacts[0].architecture)
          elif $fixtureMode == "failure-bearing" then
            .failures = [{code: "pack_download_failed"}]
          else
            .
          end' > "$pack_root/manifest.json"

    printf '%s\n' "$pack_root"
}

verify_with_pack() {
    local pack_root="$1"
    local output_file="$2"
    local error_file="$3"

    export ACFS_VERIFIED_INSTALLER_CACHE="$pack_root"
    CACHE_TEST_NETWORK_CALLS=0

    acfs_download_to_file() {
        CACHE_TEST_NETWORK_CALLS=$((CACHE_TEST_NETWORK_CALLS + 1))
        echo "network download should not be used for cached installer entrypoints" >&2
        return 79
    }

    verify_checksum "$URL" "$ARTIFACT_SHA" "$TOOL" > "$output_file" 2> "$error_file"
}

test_valid_pack_uses_local_artifact() {
    local pack_root=""
    local output_file="$TEST_ROOT/valid.out"
    local error_file="$TEST_ROOT/valid.err"
    local output=""

    pack_root="$(write_pack "valid" "$FUTURE_EXPIRES" "$CURRENT_ARCH" yes)"
    if ! verify_with_pack "$pack_root" "$output_file" "$error_file"; then
        fail "valid_pack_uses_local_artifact" "verify_checksum failed unexpectedly"
        return
    fi

    output="$(< "$output_file")"
    [[ "$output" == "$CONTENT" ]] || {
        fail "valid_pack_uses_local_artifact" "verified bytes did not match fixture"
        return
    }
    grep -Fq "installer_cache_hit tool=$TOOL" "$error_file" || {
        fail "valid_pack_uses_local_artifact" "installer cache hit log missing"
        return
    }
    [[ "$CACHE_TEST_NETWORK_CALLS" -eq 0 ]] || {
        fail "valid_pack_uses_local_artifact" "valid cache attempted a live network fetch"
        return
    }
    pass "valid_pack_uses_local_artifact"
}

expect_refusal_code() {
    local test_name="$1"
    local pack_root="$2"
    local code="$3"
    local output_file="$TEST_ROOT/$test_name.out"
    local error_file="$TEST_ROOT/$test_name.err"

    CACHE_TEST_NETWORK_CALLS=0
    if verify_with_pack "$pack_root" "$output_file" "$error_file"; then
        fail "$test_name" "verify_checksum unexpectedly succeeded"
        return
    fi

    [[ "$CACHE_TEST_NETWORK_CALLS" -eq 0 ]] || {
        fail "$test_name" "cache refusal attempted a live network fallback"
        return
    }
    [[ ! -s "$output_file" ]] || {
        fail "$test_name" "cache refusal emitted unverified bytes"
        return
    }

    grep -Fq "code=$code" "$error_file" || {
        fail "$test_name" "expected $code in error log"
        return
    }
    pass "$test_name"
}

test_missing_required_policy_field_is_refused() {
    local pack_root=""

    pack_root="$(write_pack "missing-policy" "$FUTURE_EXPIRES" "$CURRENT_ARCH" yes "artifacts/fixture.module/${TOOL}-install.sh" missing-policy)"
    expect_refusal_code "missing_required_policy_field_is_refused" "$pack_root" "pack_malformed_manifest"
}

test_duplicate_artifact_identity_is_refused() {
    local pack_root=""

    pack_root="$(write_pack "duplicate-artifact" "$FUTURE_EXPIRES" "$CURRENT_ARCH" yes "artifacts/fixture.module/${TOOL}-install.sh" duplicate-artifact)"
    expect_refusal_code "duplicate_artifact_identity_is_refused" "$pack_root" "pack_malformed_manifest"
}

test_architectureless_artifact_is_refused() {
    local pack_root=""

    pack_root="$(write_pack "missing-artifact-arch" "$FUTURE_EXPIRES" "$CURRENT_ARCH" yes "artifacts/fixture.module/${TOOL}-install.sh" missing-artifact-arch)"
    expect_refusal_code "architectureless_artifact_is_refused" "$pack_root" "pack_malformed_manifest"
}

test_failure_bearing_cache_is_refused() {
    local pack_root=""

    pack_root="$(write_pack "failure-bearing" "$FUTURE_EXPIRES" "$CURRENT_ARCH" yes "artifacts/fixture.module/${TOOL}-install.sh" failure-bearing)"
    expect_refusal_code "failure_bearing_cache_is_refused" "$pack_root" "pack_malformed_manifest"
}

test_stale_pack_is_refused() {
    local pack_root=""

    pack_root="$(write_pack "stale" "$PAST_EXPIRES" "$CURRENT_ARCH" yes)"
    expect_refusal_code "stale_pack_is_refused" "$pack_root" "pack_expired"
}

test_tampered_artifact_is_refused() {
    local pack_root=""

    pack_root="$(write_pack "tampered" "$FUTURE_EXPIRES" "$CURRENT_ARCH" yes "artifacts/fixture.module/${TOOL}-install.sh" tampered-artifact)"
    expect_refusal_code "tampered_artifact_is_refused" "$pack_root" "pack_hash_mismatch"
}

test_missing_artifact_is_refused() {
    local pack_root=""

    pack_root="$(write_pack "missing" "$FUTURE_EXPIRES" "$CURRENT_ARCH" manifest-only)"
    expect_refusal_code "missing_artifact_is_refused" "$pack_root" "pack_unbundled_required_module"
}

test_symlink_parent_escape_is_refused() {
    local pack_root=""
    local outside_dir="$TEST_ROOT/outside-artifacts"
    local artifact_rel="artifacts/escape-parent/${TOOL}-install.sh"

    pack_root="$(write_pack "symlink-parent-escape" "$FUTURE_EXPIRES" "$CURRENT_ARCH" manifest-only "$artifact_rel")"
    mkdir -p "$outside_dir"
    printf '%s' "$CONTENT" > "$outside_dir/${TOOL}-install.sh"
    ln -s "$outside_dir" "$pack_root/artifacts/escape-parent"

    expect_refusal_code "symlink_parent_escape_is_refused" "$pack_root" "pack_path_escape"
}

test_unsupported_arch_is_refused() {
    local pack_root=""

    pack_root="$(write_pack "wrong-arch" "$FUTURE_EXPIRES" "$(other_arch)" yes)"
    expect_refusal_code "unsupported_arch_is_refused" "$pack_root" "pack_arch_unsupported"
}

test_missing_pack_fails_closed() {
    local output_file="$TEST_ROOT/missing-pack.out"
    local error_file="$TEST_ROOT/missing-pack.err"

    export ACFS_VERIFIED_INSTALLER_CACHE="$TEST_ROOT/no-such-cache"
    CACHE_TEST_NETWORK_CALLS=0
    acfs_download_to_file() {
        CACHE_TEST_NETWORK_CALLS=$((CACHE_TEST_NETWORK_CALLS + 1))
        echo "network download should not run for a missing requested cache" >&2
        return 79
    }

    if verify_checksum "$URL" "$ARTIFACT_SHA" "$TOOL" > "$output_file" 2> "$error_file"; then
        fail "missing_pack_fails_closed" "verify_checksum unexpectedly succeeded"
        return
    fi

    grep -Fq "code=pack_missing_manifest" "$error_file" || {
        fail "missing_pack_fails_closed" "expected pack_missing_manifest in error log"
        return
    }
    [[ "$CACHE_TEST_NETWORK_CALLS" -eq 0 && ! -s "$output_file" ]] || {
        fail "missing_pack_fails_closed" "missing cache fell back live or emitted bytes"
        return
    }
    pass "missing_pack_fails_closed"
}

test_live_path_still_works_without_pack() {
    local output_file="$TEST_ROOT/live.out"
    local error_file="$TEST_ROOT/live.err"
    local output=""

    unset ACFS_VERIFIED_INSTALLER_CACHE
    CACHE_TEST_NETWORK_CALLS=0
    acfs_download_to_file() {
        CACHE_TEST_NETWORK_CALLS=$((CACHE_TEST_NETWORK_CALLS + 1))
        printf '%s' "$CONTENT" > "$2"
    }

    if ! verify_checksum "$URL" "$ARTIFACT_SHA" "$TOOL" > "$output_file" 2> "$error_file"; then
        fail "live_path_still_works_without_pack" "verify_checksum live path failed"
        return
    fi

    output="$(< "$output_file")"
    [[ "$output" == "$CONTENT" ]] || {
        fail "live_path_still_works_without_pack" "live verified bytes did not match fixture"
        return
    }
    grep -Fq "Verified: $TOOL" "$error_file" || {
        fail "live_path_still_works_without_pack" "live verification log missing"
        return
    }
    [[ "$CACHE_TEST_NETWORK_CALLS" -eq 1 ]] || {
        fail "live_path_still_works_without_pack" "live path did not perform exactly one fetch"
        return
    }
    pass "live_path_still_works_without_pack"
}

test_verified_emission_uses_private_snapshot() {
    local pack_root=""
    local artifact_path=""
    local emitted_path_file="$TEST_ROOT/private-snapshot-path.txt"
    local output_file="$TEST_ROOT/private-snapshot.out"
    local error_file="$TEST_ROOT/private-snapshot.err"
    local emitted_path=""

    pack_root="$(write_pack "private-snapshot" "$FUTURE_EXPIRES" "$CURRENT_ARCH" yes)"
    artifact_path="$pack_root/artifacts/fixture.module/${TOOL}-install.sh"

    # Mutation-sensitive seam: the old consumer emitted artifact_path directly;
    # the hardened consumer must emit a distinct private snapshot pathname.
    acfs_security_cat_file() {
        local file="$1"
        printf '%s\n' "$file" > "$emitted_path_file"
        /bin/cat "$file"
    }

    if ! verify_with_pack "$pack_root" "$output_file" "$error_file"; then
        fail "verified_emission_uses_private_snapshot" "verified private snapshot was not emitted"
        return
    fi
    emitted_path="$(< "$emitted_path_file")"
    [[ -n "$emitted_path" && "$emitted_path" != "$artifact_path" ]] || {
        fail "verified_emission_uses_private_snapshot" "consumer emitted the shared cache pathname"
        return
    }
    [[ "$CACHE_TEST_NETWORK_CALLS" -eq 0 ]] || {
        fail "verified_emission_uses_private_snapshot" "private snapshot path attempted a live fetch"
        return
    }
    [[ "$(< "$output_file")" == "$CONTENT" ]] || {
        fail "verified_emission_uses_private_snapshot" "verified snapshot bytes were not emitted"
        return
    }
    pass "verified_emission_uses_private_snapshot"
}

run_all_tests() {
    test_valid_pack_uses_local_artifact
    test_missing_required_policy_field_is_refused
    test_duplicate_artifact_identity_is_refused
    test_architectureless_artifact_is_refused
    test_failure_bearing_cache_is_refused
    test_stale_pack_is_refused
    test_tampered_artifact_is_refused
    test_missing_artifact_is_refused
    test_symlink_parent_escape_is_refused
    test_unsupported_arch_is_refused
    test_missing_pack_fails_closed
    test_live_path_still_works_without_pack
    test_verified_emission_uses_private_snapshot

    echo ""
    echo "Installer entrypoint cache consumer tests: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $TEST_ROOT"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

run_all_tests
