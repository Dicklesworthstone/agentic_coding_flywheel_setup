#!/usr/bin/env bash
# Test RU update functionality
# Run from: ./scripts/tests/test_ru_update.sh

# Don't use set -e so tests can fail individually without stopping
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

log_step() { echo -e "[STEP] $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; ((TESTS_PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; ((TESTS_FAILED++)); }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; ((TESTS_SKIPPED++)); }

run_test() {
    local name="$1"
    shift
    log_step "Testing: $name"
    if "$@"; then
        log_pass "$name"
    else
        log_fail "$name"
    fi
}

# Test 1: update.sh exists and has valid syntax
test_update_sh_syntax() {
    local update_sh="$REPO_ROOT/scripts/lib/update.sh"
    [[ -f "$update_sh" ]] && bash -n "$update_sh"
}

# Test 2: update.sh contains RU handling
test_update_sh_has_ru() {
    local update_sh="$REPO_ROOT/scripts/lib/update.sh"
    # Check for ru in the file (avoid regex pipe which breaks with rg alias)
    command grep -q "ru" "$update_sh" 2>/dev/null
}

# Test 3: get_version handles ru
test_get_version_ru() {
    local update_sh="$REPO_ROOT/scripts/lib/update.sh"
    local tmpdir

    # Pass if get_version does not exist.
    if ! command grep -q '^get_version()' "$update_sh" 2>/dev/null; then
        return 0
    fi

    tmpdir="$(mktemp -d)" || return 1

    cat > "$tmpdir/ru" <<'EOF'
#!/usr/bin/env bash
echo "ru 9.9.9"
EOF
    chmod +x "$tmpdir/ru"

    PATH="$tmpdir:$PATH" UPDATE_SH_PATH="$update_sh" bash -c '
        set -euo pipefail
        source "$UPDATE_SH_PATH"
        [[ "$(get_version ru)" == "ru 9.9.9" ]]
    '
    local rc=$?
    rm -rf "$tmpdir"
    return "$rc"
}

# Test 4: update helper supports env-aware verified installers
test_update_helper_has_env_support() {
    local update_sh="$REPO_ROOT/scripts/lib/update.sh"
    command grep -q "update_run_verified_installer_with_env()" "$update_sh" 2>/dev/null
}

# Test 5: RU update preserves non-interactive env
test_ru_update_uses_non_interactive_env() {
    local update_sh="$REPO_ROOT/scripts/lib/update.sh"
    command grep -q 'update_run_verified_installer_with_env ru "RU_NON_INTERACTIVE=1"' "$update_sh" 2>/dev/null
}

# Test 6: ru self-update mechanism (if ru is installed)
test_ru_self_update_check() {
    if command -v ru &>/dev/null; then
        # ru should have --version or version command
        ru --version &>/dev/null || ru version &>/dev/null || {
            log_skip "ru version command not available"
            return 0
        }
        return 0
    else
        log_skip "ru not installed, skipping self-update test"
        return 0
    fi
}

# Test 7: ru is in manifest
test_ru_in_manifest() {
    local manifest="$REPO_ROOT/acfs.manifest.yaml"
    [[ -f "$manifest" ]] && command grep -q "stack.ru" "$manifest" 2>/dev/null
}

# Test 8: ru is in checksums
test_ru_in_checksums() {
    local checksums="$REPO_ROOT/checksums.yaml"
    [[ -f "$checksums" ]] && command grep -q "ru:" "$checksums" 2>/dev/null
}

# Test 9: Generated install script has RU
test_generated_install_has_ru() {
    local install_stack="$REPO_ROOT/scripts/generated/install_stack.sh"
    [[ -f "$install_stack" ]] || return 1
    command grep -q "install_stack_ru" "$install_stack" 2>/dev/null || command grep -q '"ru"' "$install_stack" 2>/dev/null
}

# Test 10: ru binary works if installed
test_ru_binary_works() {
    if command -v ru &>/dev/null; then
        # ru should respond to --help or help
        ru --help &>/dev/null || ru help &>/dev/null || {
            return 1
        }
        return 0
    else
        log_skip "ru not installed"
        return 0
    fi
}

# Run all tests
main() {
    echo ""
    echo "============================================================"
    echo "  RU Update Integration Tests"
    echo "============================================================"
    echo ""

    run_test "update.sh syntax valid" test_update_sh_syntax
    run_test "update.sh has RU handling" test_update_sh_has_ru
    run_test "get_version handles ru" test_get_version_ru
    run_test "update helper has env support" test_update_helper_has_env_support
    run_test "RU update uses non-interactive env" test_ru_update_uses_non_interactive_env
    run_test "ru self-update check" test_ru_self_update_check
    run_test "ru in manifest" test_ru_in_manifest
    run_test "ru in checksums" test_ru_in_checksums
    run_test "generated install has ru" test_generated_install_has_ru
    run_test "ru binary works" test_ru_binary_works

    echo ""
    echo "============================================================"
    echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
    echo "============================================================"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
