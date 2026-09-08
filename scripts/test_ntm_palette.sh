#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $*" >&2; }
pass() { echo "✅ PASS: $1"; }
fail() { echo "❌ FAIL: $1"; exit 1; }

# ============================================
# Test 1: Palette file exists after install
# ============================================
test_palette_exists() {
    log "Test 1: Palette file exists after install"

    local palette="$HOME/.config/ntm/command_palette.md"

    if [[ -f "$palette" ]]; then
        pass "Test 1: Palette file exists"
    else
        fail "Test 1: Palette file not found at $palette"
    fi
}

# ============================================
# Test 2: Palette has substantial content
# ============================================
test_palette_content() {
    log "Test 2: Palette has substantial content"

    local palette="$HOME/.config/ntm/command_palette.md"
    local lines=$(wc -l < "$palette")

    log "  Palette has $lines lines"

    if [[ $lines -gt 50 ]]; then
        pass "Test 2: Palette has $lines lines (>50)"
    else
        fail "Test 2: Palette too small ($lines lines)"
    fi
}

# Count the prompt entries in a palette file. Entries are `### id | Title`
# headings under `## Category` headings; that is the format `ntm palette`
# parses, and the only non-interactive view of the palette we have (the TUI
# has no --list/--send flags, so never probe it with one: an unknown flag
# exits non-zero and a `|| echo 0` fallback would hide that, see #393).
palette_entry_count() {
    local palette="$1"
    local count
    count=$(grep -cE '^### [A-Za-z0-9_-]+ \| ' "$palette") || count=0
    echo "$count"
}

# `ntm palette --help` must exit 0. The help path is the only thing the
# subcommand does without a TTY, and a non-zero exit here means the
# subcommand itself is missing or broken.
assert_ntm_palette_subcommand() {
    local help_output
    if ! help_output=$(ntm palette --help 2>&1); then
        fail "$1: 'ntm palette --help' failed: $help_output"
    fi
    if ! grep -q 'ntm palette \[session\]' <<< "$help_output"; then
        fail "$1: 'ntm palette --help' does not describe the palette subcommand"
    fi
}

# ============================================
# Test 3: NTM palette command shows entries
# ============================================
test_ntm_palette_command() {
    log "Test 3: ntm palette subcommand works and the palette has entries"

    if ! command -v ntm >/dev/null 2>&1; then
        log "  Skipping: ntm not installed"
        pass "Test 3: Skipped (ntm not available)"
        return
    fi

    assert_ntm_palette_subcommand "Test 3"

    local palette="$HOME/.config/ntm/command_palette.md"
    local count
    count=$(palette_entry_count "$palette")

    log "  palette file has $count prompt entries"

    if [[ $count -gt 5 ]]; then
        pass "Test 3: Palette has $count entries (>5)"
    else
        fail "Test 3: Too few palette entries ($count)"
    fi
}

# ============================================
# Test 4: File owned by current user
# ============================================
test_ownership() {
    log "Test 4: File owned by current user"

    local palette="$HOME/.config/ntm/command_palette.md"
    local owner=$(stat -c '%U' "$palette" 2>/dev/null || stat -f '%Su' "$palette")

    if [[ "$owner" == "$(whoami)" ]]; then
        pass "Test 4: Owned by $owner (correct)"
    else
        fail "Test 4: Owned by $owner, expected $(whoami)"
    fi
}

# ============================================
# Test 5: Works without ~/.acfs
# ============================================
test_works_without_acfs() {
    log "Test 5: Works without ~/.acfs"

    if ! command -v ntm >/dev/null 2>&1; then
        log "  Skipping: ntm not installed"
        pass "Test 5: Skipped"
        return
    fi

    # Temporarily rename .acfs if it exists
    local acfs_dir="$HOME/.acfs"
    local acfs_backup="$HOME/.acfs.backup.$$"

    if [[ -d "$acfs_dir" ]]; then
        mv "$acfs_dir" "$acfs_backup"
    fi

    # Test ntm palette still works: the subcommand must resolve and the
    # palette file it reads must still be populated. Capture the outcome
    # rather than exiting so ~/.acfs is always restored.
    local help_rc=0
    ntm palette --help >/dev/null 2>&1 || help_rc=$?
    local count
    count=$(palette_entry_count "$HOME/.config/ntm/command_palette.md")

    # Restore .acfs
    if [[ -d "$acfs_backup" ]]; then
        mv "$acfs_backup" "$acfs_dir"
    fi

    if [[ $help_rc -ne 0 ]]; then
        fail "Test 5: 'ntm palette --help' exited $help_rc without ~/.acfs"
    fi

    if [[ $count -gt 5 ]]; then
        pass "Test 5: Palette works without ~/.acfs ($count entries)"
    else
        fail "Test 5: Palette broken without ~/.acfs ($count entries)"
    fi
}

main() {
    echo "========================================"
    echo "NTM Palette E2E Tests"
    echo "========================================"

    test_palette_exists
    test_palette_content
    test_ntm_palette_command
    test_ownership
    test_works_without_acfs

    echo ""
    echo "========================================"
    echo "All E2E tests passed!"
    echo "========================================"
}

main "$@"
