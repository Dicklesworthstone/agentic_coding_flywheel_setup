#!/usr/bin/env bash
# ============================================================
# Unit tests for plugin validation, generation, and provenance gates
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST_GEN="$REPO_ROOT/packages/manifest/src/generate.ts"
ARTIFACT_DIR="${ACFS_PLUGIN_GATES_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-plugin-gates-$(date +%Y%m%d-%H%M%S)-$$}"

mkdir -p "$ARTIFACT_DIR"

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    [[ -n "${2:-}" ]] && echo "  Reason: $2"
}

cleanup() {
    # Non-destructive test artifact directory notification
    if [[ -d "$ARTIFACT_DIR" ]]; then
        :
    fi
}
trap cleanup EXIT

# 1. A schema-valid JSON file is still not an activation authority.
test_valid_plugin_activation_is_refused() {
    local valid_json="$ARTIFACT_DIR/valid-plugin.json"
    cat > "$valid_json" <<'JSON'
{
  "schema": "acfs.plugin-package.v1",
  "schemaVersion": 1,
  "packageId": "example.gate_tools",
  "displayName": "Example Gate Tools",
  "version": "1.0.0",
  "description": "Example gate tools for testing plugin validation.",
  "publisher": {
    "name": "Gate Maintainers",
    "contactUrl": "https://example.com/security",
    "sourceUrl": "https://github.com/example/gate-tools"
  },
  "license": "Apache-2.0",
  "docsUrl": "https://example.com/gate-tools",
  "provenance": {
    "generatedAt": "2026-05-08T00:00:00Z",
    "sourceRef": "main",
    "sourceCommit": "1111222233334444555566667777888899990000",
    "acfsManifestVersion": 2
  },
  "targets": [
    {
      "os": "ubuntu",
      "versions": ["25.10"],
      "arch": ["x86_64"],
      "libc": ["glibc"]
    }
  ],
  "capabilities": {
    "allowed": ["verified_installer", "doctor_check", "web_metadata"],
    "reviewRequired": [],
    "disallowed": ["arbitrary_shell", "secret_values"]
  },
  "modules": [
    {
      "id": "plugin.example_gate_tools.cli",
      "description": "Gate test CLI module.",
      "category": "tools",
      "phase": 6,
      "run_as": "target_user",
      "optional": false,
      "enabled_by_default": true,
      "dependencies": ["lang.bun"],
      "install": {
        "kind": "verified_installer",
        "tool": "rch",
        "url": "https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh",
        "runner": "bash",
        "args": [],
        "env": []
      },
      "verify": [{ "kind": "command_exists", "command": "rch" }],
      "docs_url": "https://example.com/gate-tools/cli",
      "web": {
        "display_name": "Gate CLI",
        "short_name": "Gate",
        "tagline": "Gate CLI testing tool",
        "visible": true
      }
    }
  ],
  "offline": {
    "bundlingPolicy": "metadata_only",
    "liveAuthRequired": false,
    "providerInteractionRequired": false
  },
  "extensions": {}
}
JSON

    local output
    if output="$(bun run "$MANIFEST_GEN" --validate --plugin "$valid_json" 2>&1)"; then
        fail "valid_plugin_activation_is_refused" "Command succeeded without archive/review bindings: $output"
        return 0
    fi

    if [[ "$output" != *"Plugin package activation is not implemented"* ]]; then
        fail "valid_plugin_activation_is_refused" "Output missing fail-closed activation reason: $output"
        return 0
    fi
    if [[ "$output" == *"Validation passed"* || "$output" == *"Plugin packages valid"* ]]; then
        fail "valid_plugin_activation_is_refused" "Output falsely claimed validation success: $output"
        return 0
    fi

    pass "valid_plugin_activation_is_refused"
}

# 2. Refusal precedes descriptor parsing, so an invalid descriptor cannot
# distinguish itself or turn the disabled surface into filesystem work.
test_invalid_plugin_activation_is_refused_before_validation() {
    local invalid_json="$ARTIFACT_DIR/invalid-plugin.json"
    cat > "$invalid_json" <<'JSON'
{
  "schema": "acfs.plugin-package.v1",
  "schemaVersion": 1,
  "packageId": "example.invalid_tools",
  "displayName": "Invalid Tools",
  "version": "1.0.0",
  "description": "Invalid tool missing checksums",
  "publisher": {
    "name": "Untrusted",
    "contactUrl": "https://example.com/security",
    "sourceUrl": "https://github.com/example/invalid"
  },
  "license": "Apache-2.0",
  "docsUrl": "https://example.com/invalid",
  "provenance": {
    "generatedAt": "2026-05-08T00:00:00Z",
    "sourceRef": "main",
    "sourceCommit": "1111222233334444555566667777888899990000",
    "acfsManifestVersion": 1
  },
  "targets": [
    {
      "os": "ubuntu",
      "versions": ["25.10"],
      "arch": ["x86_64"],
      "libc": ["glibc"]
    }
  ],
  "capabilities": {
    "allowed": ["verified_installer"],
    "reviewRequired": [],
    "disallowed": ["arbitrary_shell"]
  },
  "modules": [
    {
      "id": "plugin.example_invalid_tools.tool",
      "description": "Missing checksum tool",
      "category": "tools",
      "phase": 6,
      "run_as": "target_user",
      "optional": false,
      "enabled_by_default": true,
      "dependencies": [],
      "install": {
        "kind": "verified_installer",
        "tool": "nonexistent_untrusted_checksum_key",
        "url": "https://example.com/untrusted.sh",
        "runner": "bash",
        "args": [],
        "env": []
      },
      "verify": [{ "kind": "command_exists", "command": "nonexistent" }],
      "docs_url": "https://example.com/docs"
    }
  ],
  "offline": {
    "bundlingPolicy": "metadata_only",
    "liveAuthRequired": false,
    "providerInteractionRequired": false
  },
  "extensions": {}
}
JSON

    local output
    if output="$(bun run "$MANIFEST_GEN" --validate --plugin "$invalid_json" 2>&1)"; then
        fail "invalid_plugin_activation_is_refused_before_validation" "Command succeeded when it should have failed: $output"
        return 0
    fi

    if [[ "$output" != *"Plugin package activation is not implemented"* ]]; then
        fail "invalid_plugin_activation_is_refused_before_validation" "Output missing fail-closed activation reason: $output"
        return 0
    fi

    pass "invalid_plugin_activation_is_refused_before_validation"
}

test_plugin_diff_activation_is_refused() {
    local valid_json="$ARTIFACT_DIR/valid-plugin.json"
    local output
    if output="$(bun run "$MANIFEST_GEN" --diff --plugin "$valid_json" 2>&1)"; then
        fail "plugin_diff_activation_is_refused" "Diff mode accepted unbound plugin input: $output"
        return 0
    fi

    if [[ "$output" != *"Plugin package activation is not implemented"* ]]; then
        fail "plugin_diff_activation_is_refused" "Output missing fail-closed activation reason: $output"
        return 0
    fi

    if [[ "$output" == *"[DIFF]"* || "$output" == *"Generated files would change"* ]]; then
        fail "plugin_diff_activation_is_refused" "Generator inspected or emitted output after refusal: $output"
        return 0
    fi

    pass "plugin_diff_activation_is_refused"
}

test_missing_plugin_inputs_are_refused_before_path_errors() {
    local output=""
    local input_kind=""
    local -a invocation_args=()

    for input_kind in plugin directory
    do
        if [[ "$input_kind" == "plugin" ]]; then
            invocation_args=(--plugin /definitely/missing/plugin.json)
        else
            invocation_args=(--plugins-dir /definitely/missing/plugins)
        fi
        if output="$(bun run "$MANIFEST_GEN" --validate "${invocation_args[@]}" 2>&1)"; then
            fail "missing_plugin_inputs_are_refused_before_path_errors" "$input_kind unexpectedly succeeded: $output"
            return 0
        fi
        if [[ "$output" != *"Plugin package activation is not implemented"* ]] \
            || [[ "$output" == *"not a readable plugin package directory"* ]]; then
            fail "missing_plugin_inputs_are_refused_before_path_errors" "$input_kind: $output"
            return 0
        fi
    done

    if output="$(ACFS_PLUGIN_PATHS=/definitely/missing/plugin.json bun run "$MANIFEST_GEN" --validate 2>&1)"; then
        fail "missing_plugin_inputs_are_refused_before_path_errors" "ambient path unexpectedly succeeded: $output"
        return 0
    fi
    if [[ "$output" != *"Plugin package activation is not implemented"* ]]; then
        fail "missing_plugin_inputs_are_refused_before_path_errors" "ambient path: $output"
        return 0
    fi
    if output="$(ACFS_PLUGINS_DIR=/definitely/missing/plugins bun run "$MANIFEST_GEN" --validate 2>&1)"; then
        fail "missing_plugin_inputs_are_refused_before_path_errors" "ambient directory unexpectedly succeeded: $output"
        return 0
    fi
    if [[ "$output" != *"Plugin package activation is not implemented"* ]] \
        || [[ "$output" == *"not a readable plugin package directory"* ]]; then
        fail "missing_plugin_inputs_are_refused_before_path_errors" "ambient directory: $output"
        return 0
    fi

    pass "missing_plugin_inputs_are_refused_before_path_errors"
}

test_valid_plugin_activation_is_refused
test_invalid_plugin_activation_is_refused_before_validation
test_plugin_diff_activation_is_refused
test_missing_plugin_inputs_are_refused_before_path_errors

echo ""
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

[[ $TESTS_FAILED -eq 0 ]] || exit 1
