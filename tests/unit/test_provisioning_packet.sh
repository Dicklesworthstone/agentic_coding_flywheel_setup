#!/usr/bin/env bash
# ============================================================
# Unit tests for provider provisioning packet CLI validator
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROVISIONING_PACKET_SH="$REPO_ROOT/scripts/lib/provisioning_packet.sh"
FACTORY_INSTALL_SH="$REPO_ROOT/tests/vm/test_factory_install_ubuntu.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_PROVISIONING_PACKET_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-provisioning-packet-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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
    local name="$1"
    local path="$ARTIFACT_DIR/$name"
    cat > "$path"
    printf '%s\n' "$path"
}

valid_packet_fixture() {
    write_fixture valid-packet.json <<'JSON'
{
  "schema": "acfs.provider-provisioning-packet.v1",
  "schemaVersion": 1,
  "stage": "ready_for_manual_provider_checkout",
  "privacy": {
    "supportBundleSafe": true,
    "rawProviderCredentialsIncluded": false,
    "rawTargetHostIncluded": false,
    "rawPrivateKeyIncluded": false,
    "rawPrivateKeyPathIncluded": false,
    "rawCloudInitIncludedInSupportBundle": false,
    "exactInstallCommandIncluded": true,
    "targetUsernameMayAppear": true,
    "publicSshKeyMaterialMayAppear": true,
    "redactedFieldPaths": ["targetHost.address", "cloudInit.rawUserData"],
    "forbiddenFieldNames": ["provider_api_key", "sshPrivateKey", "token", "password", "ip", "hostname"]
  },
  "provenance": {
    "generatedBy": "acfs-web-wizard",
    "generatedAt": "2026-05-08T20:00:00.000Z",
    "sourceRef": "main",
    "wizardStep": "run-installer",
    "readinessSource": "validateVPSReadiness",
    "capacitySource": "calculateRequiredSpecs/evaluatePlan",
    "pricingLastUpdated": "2026-01"
  },
  "provider": {
    "id": "contabo",
    "name": "Contabo",
    "productUrl": "https://contabo.com/en-us/vps/",
    "automationLevel": "manual",
    "manualCheckoutRequired": true,
    "manualStepsRemaining": [
      "Log in to the provider console and choose the ACFS-recommended VPS product.",
      "Select the desired region and Ubuntu image from the provider UI.",
      "Use the provider password flow, keep root as the initial login user, and save the temporary VPS root password.",
      "Complete checkout and payment manually."
    ]
  },
  "region": {
    "id": "us",
    "label": "US",
    "readinessStatus": "supported",
    "providerSpecificCode": "us"
  },
  "size": {
    "planName": "Cloud VPS 50",
    "ramGB": 64,
    "vCPU": 16,
    "storageGB": 400,
    "priceUSD": 56,
    "sourcePlan": {"name": "Cloud VPS 50", "ramGB": 64, "vCPU": 16, "storageGB": 400, "priceUSD": 56}
  },
  "osImage": {
    "distribution": "ubuntu",
    "version": "25.10",
    "minimumVersion": "22.04",
    "preferredVersions": ["25.10", "24.04"],
    "readinessStatus": "supported"
  },
  "access": {
    "username": "ubuntu",
    "rootLoginExpected": true,
    "sshPublicKeyLabel": "acfs_ed25519.pub",
    "sshPrivateKeyIncluded": false,
    "sshPrivateKeyPathIncluded": false
  },
  "cloudInit": {
    "mode": "none",
    "userDataIncluded": false,
    "notes": ["Run the exact installer command manually from the VPS root SSH session."]
  },
  "install": {
    "mode": "vibe",
    "sourceRef": "main",
    "command": "curl -fsSL \"https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh\" | bash -s -- --yes --mode vibe",
    "commandRunLocation": "vps-root-shell"
  },
  "compatibility": {
    "workloadId": "standard",
    "targetAgents": 10,
    "requiredSpecs": {"ramGB": 64, "vCPU": 16, "storageGB": 250},
    "selectedPlanStatus": "pass",
    "selectedPlanSafeAgents": 19,
    "selectedPlanRecommendedAgents": 13,
    "readinessStatus": "supported",
    "readinessChecks": [
      {"id": "provider", "label": "Provider", "status": "supported", "message": "Contabo is in the ACFS guidance table."},
      {"id": "os", "label": "Ubuntu image", "status": "supported", "message": "Ubuntu 25.10 is a preferred ACFS image."}
    ]
  },
  "verificationCommands": [
    {"id": "ssh-root", "label": "Root SSH reaches the new VPS", "command": "ssh root@<target-host>", "runLocation": "local", "expectedStatus": "pass", "supportBundleSafe": false},
    {"id": "installer", "label": "ACFS installer exits successfully", "command": "curl -fsSL \"https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh\" | bash -s -- --yes --mode vibe", "runLocation": "vps", "expectedStatus": "pass", "supportBundleSafe": true},
    {"id": "doctor", "label": "ACFS doctor passes or reports only documented warnings", "command": "acfs doctor", "runLocation": "vps", "expectedStatus": "pass", "supportBundleSafe": true}
  ],
  "expectedArtifacts": [
    {"id": "installer-log", "pathPattern": "~/.acfs/logs/install-*.log", "producedBy": "installer", "supportBundleSafe": true, "redactionRequired": true}
  ]
}
JSON
}

unknown_provider_packet_fixture() {
    local source_path="$1"
    local target_path="$ARTIFACT_DIR/unknown-provider-packet.json"
    jq '
      .stage = "draft" |
      .provider.id = "linode" |
      .provider.name = "Linode" |
      .provider.productUrl = "" |
      .region.id = "newark" |
      .region.label = "Newark" |
      .region.readinessStatus = "unknown" |
      .compatibility.selectedPlanStatus = "unknown" |
      .compatibility.readinessStatus = "unknown" |
      .compatibility.readinessChecks = [
        {"id": "provider", "label": "Provider", "status": "unknown", "message": "Provider is not in the ACFS table."}
      ]
    ' "$source_path" > "$target_path"
    printf '%s\n' "$target_path"
}

unsupported_os_packet_fixture() {
    local source_path="$1"
    local target_path="$ARTIFACT_DIR/unsupported-os-packet.json"
    jq '
      .stage = "blocked" |
      .osImage.version = "20.04" |
      .osImage.readinessStatus = "unsupported" |
      .compatibility.readinessStatus = "unsupported" |
      .compatibility.readinessChecks += [
        {"id": "os", "label": "Ubuntu image", "status": "unsupported", "message": "Ubuntu 20.04 is below the ACFS minimum."}
      ]
    ' "$source_path" > "$target_path"
    printf '%s\n' "$target_path"
}

secret_packet_fixture() {
    local source_path="$1"
    local target_path="$ARTIFACT_DIR/secret-packet.json"
    jq '.access.sshPrivateKey = "-----BEGIN OPENSSH PRIVATE KEY----- fixture"' "$source_path" > "$target_path"
    printf '%s\n' "$target_path"
}

distinct_factory_packet_fixture() {
    local source_path="$1"
    local target_path="$ARTIFACT_DIR/distinct-factory-packet.json"
    jq '
      .osImage.version = "24.04" |
      .access.username = "acfsbot" |
      .install.mode = "safe" |
      .install.sourceRef = "v9.9.9-test" |
      .provenance.sourceRef = "v9.9.9-test" |
      .install.moduleSelection = {
        onlyModules: ["base.system"],
        onlyPhases: [],
        skipModules: ["tools.vault"],
        noDeps: true
      } |
      .install.command = "curl -fsSL \"https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/v9.9.9-test/install.sh\" | TARGET_USER=\"acfsbot\" bash -s -- --yes --mode safe --ref \"v9.9.9-test\" --only \"base.system\" --skip \"tools.vault\" --no-deps"
    ' "$source_path" > "$target_path"
    printf '%s\n' "$target_path"
}

run_packet() {
    local name="$1"
    shift
    local output status

    set +e
    output="$(bash "$PROVISIONING_PACKET_SH" "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

test_valid_packet_json_output_is_stable() {
    local packet output status
    packet="$(valid_packet_fixture)"

    output="$(run_packet valid-json --json --file "$packet")"
    status="$(cat "$ARTIFACT_DIR/valid-json.exit")"

    [[ "$status" -eq 0 ]] || return 1
    jq -e '
      .schema == "acfs.provider-provisioning-packet-check.v1" and
      .status == "pass" and
      .packet.provider.name == "Contabo" and
      .packet.compatibility.targetAgents == 10 and
      .validation.errors == [] and
      any(.validation.manualSteps[]; contains("temporary VPS root password")) and
      (.validation.manualSteps[] | select(contains("Complete checkout"))) and
      (.validation.verificationCommands[] | select(.id == "installer"))
    ' <<<"$output" >/dev/null || return 1
    [[ "$output" != *"203.0.113.42"* ]] || return 1

    pass "valid_packet_json_output_is_stable"
}

test_valid_packet_markdown_renders_steps() {
    local packet output status
    packet="$(valid_packet_fixture)"

    output="$(run_packet valid-markdown --markdown --file "$packet")"
    status="$(cat "$ARTIFACT_DIR/valid-markdown.exit")"

    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"Status: pass"* ]] || return 1
    [[ "$output" == *"Provider: Contabo (manual)"* ]] || return 1
    [[ "$output" == *"Manual provider steps:"* ]] || return 1
    [[ "$output" == *"temporary VPS root password"* ]] || return 1
    [[ "$output" == *"[installer] ACFS installer exits successfully"* ]] || return 1

    pass "valid_packet_markdown_renders_steps"
}

test_unknown_provider_warns_without_provider_api() {
    local packet unknown_packet output status
    packet="$(valid_packet_fixture)"
    unknown_packet="$(unknown_provider_packet_fixture "$packet")"

    output="$(run_packet unknown-provider --json --file "$unknown_packet")"
    status="$(cat "$ARTIFACT_DIR/unknown-provider.exit")"

    [[ "$status" -eq 0 ]] || return 1
    jq -e '
      .status == "warn" and
      .packet.provider.id == "linode" and
      any(.validation.warnings[]; contains("Provider readiness is unknown"))
    ' <<<"$output" >/dev/null || return 1

    pass "unknown_provider_warns_without_provider_api"
}

test_unsupported_os_fails_validation() {
    local packet unsupported_packet output status
    packet="$(valid_packet_fixture)"
    unsupported_packet="$(unsupported_os_packet_fixture "$packet")"

    output="$(run_packet unsupported-os --json --file "$unsupported_packet")"
    status="$(cat "$ARTIFACT_DIR/unsupported-os.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("Ubuntu image readiness is unsupported"))
    ' <<<"$output" >/dev/null || return 1

    pass "unsupported_os_fails_validation"
}

test_secret_values_are_refused() {
    local packet secret_packet output status
    packet="$(valid_packet_fixture)"
    secret_packet="$(secret_packet_fixture "$packet")"

    output="$(run_packet secret-refusal --json --file "$secret_packet")"
    status="$(cat "$ARTIFACT_DIR/secret-refusal.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("Secret-looking value refused"))
    ' <<<"$output" >/dev/null || return 1

    pass "secret_values_are_refused"
}

test_packet_rejects_root_username_and_command_drift() {
    local packet invalid_packet output status
    packet="$(valid_packet_fixture)"
    invalid_packet="$ARTIFACT_DIR/root-command-drift-packet.json"
    jq '
      .access.username = "root" |
      .install.mode = "safe" |
      .install.moduleSelection = {onlyModules: ["base.system"], noDeps: true} |
      .install.command = "npm install"
    ' "$packet" > "$invalid_packet"

    output="$(run_packet root-command-drift --json --file "$invalid_packet")"
    status="$(cat "$ARTIFACT_DIR/root-command-drift.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("valid Linux username")) and
      any(.validation.errors[]; contains("wrong-package-manager")) and
      any(.validation.errors[]; contains("declared install.mode")) and
      any(.validation.errors[]; contains("declared module selector")) and
      any(.validation.errors[]; contains("--no-deps"))
    ' <<<"$output" >/dev/null || return 1

    pass "packet_rejects_root_username_and_command_drift"
}

test_malformed_packet_fails_with_json_error() {
    local packet output status
    packet="$(write_fixture malformed-packet.json <<'JSON'
{"schema":
JSON
)"

    output="$(run_packet malformed --json --file "$packet")"
    status="$(cat "$ARTIFACT_DIR/malformed.exit")"

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      any(.validation.errors[]; contains("Malformed JSON packet"))
    ' <<<"$output" >/dev/null || return 1

    pass "malformed_packet_fails_with_json_error"
}

test_factory_sentinel_rejects_invalid_packet_with_provider_setup_category() {
    local packet out_dir status
    packet="$(write_fixture invalid-os-sentinel-packet.json <<'JSON'
{
  "schema": "acfs.provider-provisioning-packet.v1",
  "schemaVersion": 1,
  "stage": "ready_for_manual_provider_checkout",
  "os": {"id": "debian", "initialReleaseId": "12", "expectedFinalReleaseId": "12"}
}
JSON
)"
    out_dir="$ARTIFACT_DIR/factory-sentinel-invalid-os"
    mkdir -p "$out_dir"

    status=0
    "$FACTORY_INSTALL_SH" \
        --ssh-target root@127.0.0.1 \
        --provisioning-packet "$packet" \
        --artifacts-dir "$out_dir" >/dev/null 2>&1 || status=$?

    [[ "$status" -eq 2 ]] || return 1
    [[ -f "$out_dir/factory-sentinel-manifest.json" ]] || return 1
    [[ -f "$out_dir/factory-sentinel-summary.md" ]] || return 1

    jq -e '
      .status == "failed" and
      .failureCategory == "provider_setup" and
      .exitCode == 2
    ' "$out_dir/factory-sentinel-manifest.json" >/dev/null || return 1

    pass "factory_sentinel_rejects_invalid_packet_with_provider_setup_category"
}

test_factory_sentinel_rejects_unreachable_ssh_with_ssh_category() {
    local packet out_dir status
    packet="$(valid_packet_fixture)"
    out_dir="$ARTIFACT_DIR/factory-sentinel-ssh-unreachable"
    mkdir -p "$out_dir"

    status=0
    "$FACTORY_INSTALL_SH" \
        --ssh-target root@127.0.0.1 \
        --ssh-port 59999 \
        --provisioning-packet "$packet" \
        --artifacts-dir "$out_dir" >/dev/null 2>&1 || status=$?

    [[ "$status" -eq 1 ]] || return 1
    [[ -f "$out_dir/factory-sentinel-manifest.json" ]] || return 1
    [[ -f "$out_dir/factory-sentinel-summary.md" ]] || return 1

    jq -e '
      .status == "failed" and
      .failureCategory == "ssh" and
      .exitCode == 1 and
      .target.host == "root@<REDACTED:host>"
    ' "$out_dir/factory-sentinel-manifest.json" >/dev/null || return 1

    pass "factory_sentinel_rejects_unreachable_ssh_with_ssh_category"
}

test_factory_maps_canonical_packet_before_building_url() {
    local packet distinct_packet out_dir status
    packet="$(valid_packet_fixture)"
    distinct_packet="$(distinct_factory_packet_fixture "$packet")"
    out_dir="$ARTIFACT_DIR/factory-canonical-mapping"
    mkdir -p "$out_dir"

    status=0
    "$FACTORY_INSTALL_SH" \
        --ssh-target root@localhost \
        --ssh-port 59997 \
        --provisioning-packet "$distinct_packet" \
        --artifacts-dir "$out_dir" >/dev/null 2>&1 || status=$?

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .failureCategory == "ssh" and
      .target.host == "root@<REDACTED:host>" and
      .target.ref == "v9.9.9-test" and
      .target.mode == "safe" and
      .target.username == "acfsbot" and
      .target.expectedInitialUbuntu == "24.04" and
      .provisioningPacketProjection.status == "captured" and
      .provisioningPacketProjection.packet.osImage.version == "24.04" and
      .provisioningPacketProjection.packet.access.username == "acfsbot" and
      .provisioningPacketProjection.packet.install.sourceRef == "v9.9.9-test" and
      .provisioningPacketProjection.packet.install.moduleSelection.onlyModules == ["base.system"]
    ' "$out_dir/factory-sentinel-manifest.json" >/dev/null || return 1
    ! grep -q 'localhost' "$out_dir/factory-sentinel-manifest.json" || return 1
    ! grep -q 'localhost' "$out_dir/factory-sentinel-summary.md" || return 1

    pass "factory_maps_canonical_packet_before_building_url"
}

test_factory_rejects_explicit_packet_conflicts_before_ssh() {
    local packet distinct_packet out_dir status
    packet="$(valid_packet_fixture)"
    distinct_packet="$(distinct_factory_packet_fixture "$packet")"
    out_dir="$ARTIFACT_DIR/factory-explicit-conflict"
    mkdir -p "$out_dir"

    status=0
    "$FACTORY_INSTALL_SH" \
        --ssh-target root@localhost \
        --mode vibe \
        --provisioning-packet "$distinct_packet" \
        --artifacts-dir "$out_dir" >/dev/null 2>&1 || status=$?

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .failureCategory == "provider_setup" and
      .errorMessage == "explicit factory arguments conflict with provisioning packet intent"
    ' "$out_dir/factory-sentinel-manifest.json" >/dev/null || return 1

    pass "factory_rejects_explicit_packet_conflicts_before_ssh"
}

test_factory_sentinel_manifest_redacts_host_ip_and_sensitive_tokens() {
    local packet out_dir status
    packet="$(valid_packet_fixture)"
    out_dir="$ARTIFACT_DIR/factory-sentinel-redaction"
    mkdir -p "$out_dir"

    status=0
    "$FACTORY_INSTALL_SH" \
        --ssh-target root@192.0.2.123 \
        --ssh-port 59998 \
        --provisioning-packet "$packet" \
        --artifacts-dir "$out_dir" >/dev/null 2>&1 || status=$?

    # Verify that raw host IP is not exposed in the manifest JSON or summary markdown
    if grep -q "192.0.2.123" "$out_dir/factory-sentinel-manifest.json"; then
        return 1
    fi
    if grep -q "192.0.2.123" "$out_dir/factory-sentinel-summary.md"; then
        return 1
    fi

    pass "factory_sentinel_manifest_redacts_host_ip_and_sensitive_tokens"
}

run_all_tests() {
    local test_name=""
    local tests=(
        test_valid_packet_json_output_is_stable
        test_valid_packet_markdown_renders_steps
        test_unknown_provider_warns_without_provider_api
        test_unsupported_os_fails_validation
        test_secret_values_are_refused
        test_packet_rejects_root_username_and_command_drift
        test_malformed_packet_fails_with_json_error
        test_factory_sentinel_rejects_invalid_packet_with_provider_setup_category
        test_factory_sentinel_rejects_unreachable_ssh_with_ssh_category
        test_factory_sentinel_manifest_redacts_host_ip_and_sensitive_tokens
        test_factory_maps_canonical_packet_before_building_url
        test_factory_rejects_explicit_packet_conflicts_before_ssh
    )

    for test_name in "${tests[@]}"; do
        if ! "$test_name"; then
            fail "$test_name" "See artifacts in $ARTIFACT_DIR"
        fi
    done

    echo ""
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo "Artifacts: $ARTIFACT_DIR"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

run_all_tests "$@"
