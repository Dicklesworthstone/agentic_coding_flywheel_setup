#!/usr/bin/env bash
# ============================================================
# Unit tests for ACFS output formatting library (output.sh)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the output library
source "$PROJECT_ROOT/scripts/lib/output.sh"

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Under set -e, ((COUNT++)) from 0 returns 1; the first skip outside an &&/||
# list (no `tru` installed) used to end the suite silently at Test 7.
pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); echo "✅ PASS: $1"; }
fail() { TESTS_FAILED=$((TESTS_FAILED + 1)); echo "❌ FAIL: $1"; }
skip() { TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); echo "⏭️  SKIP: $1"; }

echo "=== ACFS Output Module Unit Tests ==="
echo ""

# Test 1: acfs_resolve_format CLI flags
echo "Test 1: acfs_resolve_format CLI flags"
unset ACFS_OUTPUT_FORMAT TOON_DEFAULT_FORMAT

result=$(acfs_resolve_format "json")
[[ "$result" == "json" ]] && pass "CLI json" || fail "CLI json (got: $result)"

result=$(acfs_resolve_format "toon")
[[ "$result" == "toon" ]] && pass "CLI toon" || fail "CLI toon (got: $result)"

result=$(acfs_resolve_format "TOON")
[[ "$result" == "toon" ]] && pass "CLI TOON (case insensitive)" || fail "CLI TOON (got: $result)"

# Test 2: Environment variables
echo ""
echo "Test 2: Environment variables"
unset ACFS_OUTPUT_FORMAT TOON_DEFAULT_FORMAT

export ACFS_OUTPUT_FORMAT=toon
result=$(acfs_resolve_format "")
[[ "$result" == "toon" ]] && pass "ACFS_OUTPUT_FORMAT=toon" || fail "ACFS_OUTPUT_FORMAT (got: $result)"
unset ACFS_OUTPUT_FORMAT

export TOON_DEFAULT_FORMAT=toon
result=$(acfs_resolve_format "")
[[ "$result" == "toon" ]] && pass "TOON_DEFAULT_FORMAT=toon" || fail "TOON_DEFAULT_FORMAT (got: $result)"
unset TOON_DEFAULT_FORMAT

# Test 3: CLI overrides env
echo ""
echo "Test 3: CLI overrides environment"
export ACFS_OUTPUT_FORMAT=toon
result=$(acfs_resolve_format "json")
[[ "$result" == "json" ]] && pass "CLI overrides env" || fail "CLI override (got: $result)"
unset ACFS_OUTPUT_FORMAT

# Test 4: ACFS_OUTPUT_FORMAT overrides TOON_DEFAULT_FORMAT
echo ""
echo "Test 4: ACFS_OUTPUT_FORMAT overrides TOON_DEFAULT_FORMAT"
export ACFS_OUTPUT_FORMAT=json
export TOON_DEFAULT_FORMAT=toon
result=$(acfs_resolve_format "")
[[ "$result" == "json" ]] && pass "ACFS_OUTPUT_FORMAT takes precedence" || fail "Env precedence (got: $result)"
unset ACFS_OUTPUT_FORMAT TOON_DEFAULT_FORMAT

# Test 5: Default
echo ""
echo "Test 5: Default format"
unset ACFS_OUTPUT_FORMAT TOON_DEFAULT_FORMAT
result=$(acfs_resolve_format "")
[[ "$result" == "json" ]] && pass "Default is json" || fail "Default (got: $result)"

# Test 6: acfs_format_output JSON
echo ""
echo "Test 6: acfs_format_output JSON"
test_json='{"config": {"env": "test"}}'
result=$(acfs_format_output "$test_json" "json" "false")
[[ "$result" == "$test_json" ]] && pass "JSON passthrough" || fail "JSON passthrough"

# Test 7: acfs_format_output TOON
echo ""
echo "Test 7: acfs_format_output TOON"
if command -v tru &>/dev/null; then
    result=$(acfs_format_output "$test_json" "toon" "false")
    if [[ "${result:0:1}" != "{" ]]; then
        pass "TOON encoding"
    else
        fail "TOON looks like JSON"
    fi
else
    skip "tru not available"
fi

# Test 8: Round-trip verification
echo ""
echo "Test 8: Round-trip verification"
if command -v tru &>/dev/null; then
    test_config='{"flywheel":{"agents":["cc","cod"],"session":"main"}}'
    if acfs_verify_roundtrip "$test_config"; then
        pass "Round-trip preserves data"
    else
        fail "Round-trip mismatch"
    fi
else
    skip "tru not available"
fi

# Test 9: Stats output to stderr (TOON mode)
echo ""
echo "Test 9: Stats output (TOON mode)"
if command -v tru &>/dev/null; then
    stderr=$(acfs_format_output "$test_json" "toon" "true" 2>&1 >/dev/null)
    if echo "$stderr" | command grep -q "bytes"; then
        pass "Stats to stderr (TOON)"
    else
        fail "Stats missing (TOON)"
    fi
else
    skip "tru not available"
fi

# Test 10: Stats output to stderr (JSON mode with potential savings)
echo ""
echo "Test 10: Stats output (JSON mode)"
if command -v tru &>/dev/null; then
    stderr=$(acfs_format_output "$test_json" "json" "true" 2>&1 >/dev/null)
    if echo "$stderr" | command grep -q "potential savings"; then
        pass "Stats to stderr (JSON)"
    else
        fail "Stats missing (JSON)"
    fi
else
    skip "tru not available"
fi

# Test 11: tru availability check
echo ""
echo "Test 11: _acfs_tru_available check"
if command -v tru &>/dev/null; then
    if _acfs_tru_available; then
        pass "_acfs_tru_available returns true when tru exists"
    else
        fail "_acfs_tru_available returned false when tru exists"
    fi
else
    if ! _acfs_tru_available; then
        pass "_acfs_tru_available returns false when tru missing"
    else
        fail "_acfs_tru_available returned true when tru missing"
    fi
fi

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped ==="
[[ $TESTS_FAILED -eq 0 ]]
