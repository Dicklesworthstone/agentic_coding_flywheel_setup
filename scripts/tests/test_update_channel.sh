#!/usr/bin/env bash
# ============================================================
# Test: Update Channel Fix (bd-gsjqf)
# Validates that all update paths use update_run_verified_installer
# instead of bare "claude update" (which has no --channel flag and
# silently downgrades from latest to stable channel).
# ============================================================
# Bead: bd-gsjqf.4
# 8 tests per specification:
#   1. Static Analysis — No bare "claude update" in function body
#   2. Static Analysis — update_run_verified_installer is called
#   3. Dry-run behavior
#   4. Function instrumentation (mock)
#   5. Security fallback
#   6. uca alias definition
#   7. Completeness sweep
#   8. Channel version (live, optional)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
SKIP=0
LOG_FILE="/tmp/test_update_channel_$(date +%Y%m%d_%H%M%S).log"

# --- Helpers ---
log()     { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*" | tee -a "$LOG_FILE"; }
pass()    { PASS=$((PASS + 1)); log "  PASS: $1"; }
fail()    { FAIL=$((FAIL + 1)); log "  FAIL: $1"; }
skip()    { SKIP=$((SKIP + 1)); log "  SKIP: $1"; }
section() { log ""; log "=== $1 ==="; }

UPDATE_SH="$REPO_ROOT/scripts/lib/update.sh"
ZSHRC="$REPO_ROOT/acfs/zsh/acfs.zshrc"

log "Test: Update Channel Fix (bd-gsjqf)"
log "Log file: $LOG_FILE"
log "Repo root: $REPO_ROOT"

# Ensure required files exist
if [[ ! -f "$UPDATE_SH" ]]; then
    log "FATAL: $UPDATE_SH not found"
    exit 2
fi

# Extract function body once for Tests 1-2
func_body=$(sed -n '/^run_cmd_claude_update()/,/^}/p' "$UPDATE_SH")
if [[ -z "$func_body" ]]; then
    log "FATAL: Could not extract run_cmd_claude_update() from $UPDATE_SH"
    exit 2
fi

# ============================================================
section "Test 1: Static Analysis — No bare 'claude update' in function body"
# ============================================================
# Extract lines that are NOT comments, NOT variable assignments (cmd_display=),
# and NOT log strings, then check for bare "claude update" invocations.
bare_claude_update=$(
    echo "$func_body" \
    | grep -v '^\s*#' \
    | grep -v 'cmd_display=' \
    | grep -v 'log_to_file' \
    | grep -v 'log_item' \
    | grep -v 'echo.*claude update' \
    | grep 'claude update' \
    || true
)
if [[ -z "$bare_claude_update" ]]; then
    pass "No bare 'claude update' invocation in run_cmd_claude_update() body"
else
    fail "Found bare 'claude update' invocation in run_cmd_claude_update(): $bare_claude_update"
fi

# ============================================================
section "Test 2: Static Analysis — update_run_verified_installer is called"
# ============================================================
installer_calls=$(echo "$func_body" | grep -c 'update_run_verified_installer' || true)
if [[ "$installer_calls" -gt 0 ]]; then
    pass "run_cmd_claude_update() calls update_run_verified_installer ($installer_calls occurrences)"
else
    fail "run_cmd_claude_update() does NOT call update_run_verified_installer"
fi

# ============================================================
section "Test 3: Dry-run behavior"
# ============================================================
# Source update.sh in a subshell. The BASH_SOURCE guard at line ~2444 prevents
# main() from running when sourced. Then call run_cmd_claude_update with
# DRY_RUN=true and verify it returns 0 without executing anything.
dry_run_output=$(
    bash -c '
        # Provide required globals
        DRY_RUN=true
        VERBOSE=false
        QUIET=true
        FORCE_MODE=false
        YES_MODE=false
        ABORT_ON_FAILURE=false
        UPDATE_LOG_FILE="/dev/null"
        SUCCESS_COUNT=0
        SKIP_COUNT=0
        FAIL_COUNT=0
        NO_COLOR=1
        RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""
        declare -gA VERSION_BEFORE=()
        declare -gA VERSION_AFTER=()

        source "'"$UPDATE_SH"'"

        run_cmd_claude_update
        echo "DRY_RUN_EXIT=$?"
    ' 2>&1
) || true

if echo "$dry_run_output" | grep -q 'DRY_RUN_EXIT=0'; then
    pass "Dry-run mode returns 0 without executing installer"
else
    fail "Dry-run mode did not return 0. Output: $dry_run_output"
fi

# ============================================================
section "Test 4: Function instrumentation (mock)"
# ============================================================
# Source update.sh, override update_run_verified_installer with a mock,
# call run_cmd_claude_update, verify the mock was called with "claude latest".
# NOTE: The non-verbose code path runs update_run_verified_installer inside
# a $() subshell, so shell variable changes are lost. We use a temp file
# as a signal instead, and run in VERBOSE mode so the mock runs in-process.
MOCK_SIGNAL="/tmp/test_update_channel_mock_$$"
rm -f "$MOCK_SIGNAL"
mock_output=$(
    bash -c '
        DRY_RUN=false
        VERBOSE=true
        QUIET=true
        FORCE_MODE=false
        YES_MODE=false
        ABORT_ON_FAILURE=false
        UPDATE_LOG_FILE="/dev/null"
        SUCCESS_COUNT=0
        SKIP_COUNT=0
        FAIL_COUNT=0
        NO_COLOR=1
        RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""
        declare -gA VERSION_BEFORE=()
        declare -gA VERSION_AFTER=()

        source "'"$UPDATE_SH"'"

        # Override with mock — write args to a temp file signal
        update_run_verified_installer() {
            echo "$*" > "'"$MOCK_SIGNAL"'"
            return 0
        }

        run_cmd_claude_update 2>&1
    ' 2>&1
) || true

if [[ -f "$MOCK_SIGNAL" ]]; then
    mock_args=$(cat "$MOCK_SIGNAL")
    rm -f "$MOCK_SIGNAL"
    if [[ "$mock_args" == "claude latest" ]]; then
        pass "Mock update_run_verified_installer called with 'claude latest'"
    else
        fail "Mock called but with wrong args: '$mock_args'"
    fi
else
    fail "Mock update_run_verified_installer was NOT called. Output: $mock_output"
fi

# ============================================================
section "Test 5: Security fallback"
# ============================================================
# Source update.sh, mock update_require_security to fail,
# verify update_run_verified_installer returns non-zero with a warning.
security_output=$(
    bash -c '
        DRY_RUN=false
        VERBOSE=false
        QUIET=true
        FORCE_MODE=false
        YES_MODE=false
        ABORT_ON_FAILURE=false
        UPDATE_LOG_FILE="/dev/null"
        SUCCESS_COUNT=0
        SKIP_COUNT=0
        FAIL_COUNT=0
        NO_COLOR=1
        RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""
        declare -gA VERSION_BEFORE=()
        declare -gA VERSION_AFTER=()

        source "'"$UPDATE_SH"'"

        # Override security check to always fail
        update_require_security() { return 1; }

        # Call the verified installer directly — it should fail gracefully
        update_run_verified_installer claude latest 2>&1 || echo "SECURITY_EXIT=$?"
    ' 2>&1
) || true

if echo "$security_output" | grep -q 'SECURITY_EXIT='; then
    if echo "$security_output" | grep -qi 'security\|unavailable\|missing'; then
        pass "Security fallback produces warning and non-zero exit when security unavailable"
    else
        pass "Security fallback returns non-zero when update_require_security fails"
    fi
else
    fail "update_run_verified_installer did not fail when security was unavailable. Output: $security_output"
fi

# ============================================================
section "Test 6: uca alias definition"
# ============================================================
if [[ -f "$ZSHRC" ]]; then
    uca_line=$(grep "alias uca=" "$ZSHRC" || true)
    if [[ -z "$uca_line" ]]; then
        fail "uca alias not found in acfs.zshrc"
    else
        # Check 1: no bare "claude update" in the alias
        if echo "$uca_line" | grep -q 'claude update'; then
            fail "uca alias contains bare 'claude update': $uca_line"
        else
            # Check 2: uses install.sh with latest (the verified approach)
            if echo "$uca_line" | grep -q 'install.sh.*latest'; then
                pass "uca alias uses install.sh with latest channel (no bare 'claude update')"
            else
                pass "uca alias does not contain bare 'claude update'"
            fi
        fi

        # Check 3: codex and gemini are preserved in the alias chain
        has_codex=false
        has_gemini=false
        echo "$uca_line" | grep -q 'codex' && has_codex=true
        echo "$uca_line" | grep -q 'gemini' && has_gemini=true
        if $has_codex && $has_gemini; then
            pass "uca alias preserves codex and gemini components"
        else
            fail "uca alias missing components: codex=$has_codex gemini=$has_gemini"
        fi
    fi
else
    skip "acfs.zshrc not found at $ZSHRC"
fi

# ============================================================
section "Test 7: Completeness sweep — no bare 'claude update' in repo"
# ============================================================
# Grep across the whole repo for "claude update", excluding:
# - comments (lines starting with #)
# - this test file itself
# - .beads/ directories
# - node_modules/target/.git
# - known-safe patterns (update_run_verified_installer, install.sh, cmd_display=, FIX(bd-gsjqf)
# - lines with INTENTIONAL marker
sweep_hits=$(
    grep -rn "claude update" "$REPO_ROOT" \
        --include='*.sh' --include='*.zsh' --include='*.zshrc' --include='*.bashrc' \
        --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='.beads' \
        --exclude-dir='target' \
        2>/dev/null \
    | grep -v 'update_run_verified_installer' \
    | grep -v 'install\.sh.*latest' \
    | grep -v '^\s*#' \
    | grep -v 'test_update_channel' \
    | grep -v 'cmd_display=' \
    | grep -v 'FIX(bd-gsjqf' \
    | grep -v 'INTENTIONAL' \
    | grep -v 'PLAN_TO_CREATE' \
    || true
)
if [[ -z "$sweep_hits" ]]; then
    pass "No unprotected bare 'claude update' found in shell files"
else
    log "  Bare hits found:"
    echo "$sweep_hits" | while IFS= read -r line; do log "    $line"; done
    fail "Found bare 'claude update' in shell files (see above)"
fi

# ============================================================
section "Test 8: Channel version alignment (live, optional)"
# ============================================================
if command -v npm &>/dev/null && command -v claude &>/dev/null; then
    dist_tags=$(npm view @anthropic-ai/claude-code dist-tags 2>/dev/null || true)
    installed=$(claude --version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' || true)
    latest=$(echo "$dist_tags" | grep -oP "latest: '\K[^']+" || true)
    stable=$(echo "$dist_tags" | grep -oP "stable: '\K[^']+" || true)
    log "  Installed: ${installed:-unknown}"
    log "  Latest:    ${latest:-unknown}"
    log "  Stable:    ${stable:-unknown}"
    if [[ -z "$installed" ]] || [[ -z "$latest" ]]; then
        skip "Could not determine version info for live channel check"
    elif [[ "$installed" == "$latest" ]]; then
        pass "Installed claude version matches latest channel ($installed)"
    elif [[ "$installed" == "$stable" ]]; then
        fail "Installed claude version matches STABLE channel ($installed) — possible downgrade!"
    else
        skip "Version $installed matches neither latest ($latest) nor stable ($stable)"
    fi
else
    skip "npm or claude not available — skipping live channel check"
fi

# ============================================================
section "Summary"
# ============================================================
log ""
log "Results: $PASS passed, $FAIL failed, $SKIP skipped"
log "Log: $LOG_FILE"

if [[ "$FAIL" -gt 0 ]]; then
    log "RESULT: FAIL"
    exit 1
else
    log "RESULT: PASS"
    exit 0
fi
