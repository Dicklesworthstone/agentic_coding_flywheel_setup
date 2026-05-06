#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PALETTE_SOURCE="$REPO_ROOT/acfs/onboard/docs/ntm/command_palette.md"

pass() { echo "✅ PASS: $1"; }
fail() { echo "❌ FAIL: $1"; exit 1; }
log() { echo "[TEST] $*" >&2; }

# ============================================
# Test 1: Source palette exists
# ============================================
test_source_exists() {
    log "Test 1: Source palette exists"

    local source="$PALETTE_SOURCE"

    if [[ -f "$source" ]]; then
        pass "Test 1: Source palette exists"
    else
        fail "Test 1: Source palette not found at $source"
    fi
}

# ============================================
# Test 2: Source palette has content
# ============================================
test_source_has_content() {
    log "Test 2: Source palette has substantial content"

    local source="$PALETTE_SOURCE"
    local lines=$(wc -l < "$source")

    if [[ $lines -gt 50 ]]; then
        pass "Test 2: Palette has $lines lines"
    else
        fail "Test 2: Palette too small ($lines lines < 50)"
    fi
}

# ============================================
# Test 3: Palette format is valid
# ============================================
test_palette_format() {
    log "Test 3: Palette format is valid"

    local source="$PALETTE_SOURCE"

    # Should have category headers
    if ! grep -q "^## " "$source"; then
        fail "Test 3: No category headers (## ) found"
    fi

    # Should have command entries (### key | label format)
    if ! grep -q "^### " "$source"; then
        fail "Test 3: No command entries (### ) found"
    fi

    pass "Test 3: Palette format valid"
}

# ============================================
# Test 4: Install script has palette logic
# ============================================
test_install_has_palette_logic() {
    log "Test 4: Install script has palette logic"

    if grep -q "command_palette.md" "$REPO_ROOT/install.sh"; then
        pass "Test 4: Install script references palette"
    else
        fail "Test 4: Install script missing palette wiring"
    fi
}

main() {
    echo "========================================"
    echo "NTM Palette Install Unit Tests"
    echo "========================================"

    test_source_exists
    test_source_has_content
    test_palette_format
    test_install_has_palette_logic

    echo ""
    echo "All unit tests passed!"
}

main "$@"
