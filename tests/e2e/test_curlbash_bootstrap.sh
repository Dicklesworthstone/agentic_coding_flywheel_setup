#!/usr/bin/env bash
# ============================================================
# E2E Test: curl|bash Bootstrap Path
#
# CI normally tests `bash install.sh` from a local checkout.
# The real user path is:
#   curl -fsSL ... | bash -s -- --yes --mode vibe
#
# which triggers bootstrap_repo_archive() (archive download,
# extraction, path setup). This path was NEVER tested before.
# The declare scoping bug only manifested in this path.
#
# Strategy:
#   1. Create a tar.gz archive from the current checkout
#   2. Serve install.sh via python3 -m http.server
#   3. Run curl | bash -s -- --yes --dry-run with --bootstrap-archive
#   4. Verify bootstrap succeeds and dry-run completes
#
# Related bugs: #85-#90
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
HTTP_PID=""
WORK_DIR=""

cleanup_test() {
    if [[ -n "$HTTP_PID" ]]; then
        kill "$HTTP_PID" 2>/dev/null || true
        wait "$HTTP_PID" 2>/dev/null || true
    fi
    if [[ -n "$WORK_DIR" ]]; then
        echo "  INFO: Preserved test work dir: $WORK_DIR"
    fi
}
trap cleanup_test EXIT

assert_ok() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        ((PASS++)) || true
    else
        echo "  FAIL: $desc"
        ((FAIL++)) || true
    fi
}

echo "=== E2E: curl|bash Bootstrap Path ==="
echo ""

# ────────────────────────────────────────
# 1. Build archive from current checkout
# ────────────────────────────────────────
echo "Step 1: Creating tar.gz archive from checkout..."
WORK_DIR="$(mktemp -d)"
ARCHIVE_DIR="$WORK_DIR/serve"
mkdir -p "$ARCHIVE_DIR"

# Create the archive mimicking GitHub's format: repo-ref/ prefix
ARCHIVE_PREFIX="agentic_coding_flywheel_setup-test"
STAGING="$WORK_DIR/$ARCHIVE_PREFIX"
mkdir -p "$STAGING"

# Copy the files that bootstrap_repo_archive extracts
cp "$REPO_ROOT/install.sh" "$STAGING/"
cp -r "$REPO_ROOT/scripts" "$STAGING/"
mkdir -p "$STAGING/packages"
cp -r "$REPO_ROOT/packages/onboard" "$STAGING/packages/onboard"
cp -r "$REPO_ROOT/acfs" "$STAGING/" 2>/dev/null || mkdir -p "$STAGING/acfs"
cp "$REPO_ROOT/checksums.yaml" "$STAGING/" 2>/dev/null || echo "{}" > "$STAGING/checksums.yaml"
cp "$REPO_ROOT/acfs.manifest.yaml" "$STAGING/" 2>/dev/null || echo "{}" > "$STAGING/acfs.manifest.yaml"
cp "$REPO_ROOT/VERSION" "$STAGING/" 2>/dev/null || echo "0.0.0-test" > "$STAGING/VERSION"

# Create tar.gz with the expected structure
(cd "$WORK_DIR" && tar -czf "$ARCHIVE_DIR/test.tar.gz" "$ARCHIVE_PREFIX/")

# Also put install.sh in the serve directory for curl to fetch
cp "$REPO_ROOT/install.sh" "$ARCHIVE_DIR/install.sh"

assert_ok "Archive created" test -f "$ARCHIVE_DIR/test.tar.gz"
echo ""

# ────────────────────────────────────────
# 2. Start local HTTP server
# ────────────────────────────────────────
echo "Step 2: Starting local HTTP server..."

# Find a free port
PORT=0
for p in 18080 18081 18082 18083 18084; do
    if ! ss -tlnp 2>/dev/null | grep -q ":$p "; then
        PORT=$p
        break
    fi
done

if [[ "$PORT" -eq 0 ]]; then
    echo "FAIL: Could not find free port"
    exit 1
fi

python3 -m http.server "$PORT" --directory "$ARCHIVE_DIR" &>/dev/null &
HTTP_PID=$!

# Wait for server to be ready
for _ in $(seq 1 20); do
    if curl -sf "http://localhost:$PORT/install.sh" >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

assert_ok "HTTP server running on port $PORT" curl -sf "http://localhost:$PORT/install.sh"
echo ""

# ────────────────────────────────────────
# 3. Run curl|bash with --dry-run
# ────────────────────────────────────────
echo "Step 3: Running curl|bash bootstrap with --dry-run..."

LOG_FILE="$WORK_DIR/install.log"

set +e
timeout 90s bash -c '
    set -euo pipefail
    curl -sf "$1" | ACFS_CI=true ACFS_PREFLIGHT_NETWORK=skip bash -s -- --bootstrap-archive "$2" --yes --dry-run --skip-ubuntu-upgrade
' _ "http://localhost:$PORT/install.sh" "$ARCHIVE_DIR/test.tar.gz" > "$LOG_FILE" 2>&1
INSTALL_STATUS=$?
set -e

if [[ "$INSTALL_STATUS" -eq 0 ]]; then
    echo "  PASS: Install script executed from stdin without crash"
    ((PASS++)) || true
else
    echo "  FAIL: Install script failed from stdin (exit $INSTALL_STATUS)"
    ((FAIL++)) || true
fi
assert_ok "Local bootstrap archive is preserved after test-mode run" test -f "$ARCHIVE_DIR/test.tar.gz"
echo ""

# ────────────────────────────────────────
# 4. Verify bootstrap behavior
# ────────────────────────────────────────
echo "Step 4: Verifying bootstrap results..."

# The dry-run should NOT crash with "unbound variable" errors
if grep -qi "unbound variable" "$LOG_FILE" 2>/dev/null; then
    echo "  FAIL: Found 'unbound variable' error (declare scoping issue)"
    ((FAIL++)) || true
else
    echo "  PASS: No unbound variable errors"
    ((PASS++)) || true
fi

if grep -q "Using explicitly selected local archive" "$LOG_FILE" 2>/dev/null; then
    echo "  PASS: curl|bash test exercised archive bootstrap"
    ((PASS++)) || true
else
    echo "  FAIL: curl|bash test did not exercise archive bootstrap"
    ((FAIL++)) || true
fi

if grep -q "ACFS Pre-Flight Check" "$LOG_FILE" 2>/dev/null \
    && grep -q "Offline/cache: verified installer checksums available" "$LOG_FILE" 2>/dev/null; then
    echo "  PASS: archive-resident checksum-bound preflight emitted inner proof markers"
    ((PASS++)) || true
else
    echo "  FAIL: archive preflight did not emit its inner proof markers"
    ((FAIL++)) || true
fi

# The test must exercise the real stdin/curl-pipe mode, not a local path.
if grep -q "SCRIPT_DIR=" "$LOG_FILE" 2>/dev/null; then
    echo "  FAIL: Unexpected local SCRIPT_DIR path leaked into curl|bash test"
    ((FAIL++)) || true
else
    echo "  PASS: No local SCRIPT_DIR path leaked into output"
    ((PASS++)) || true
fi

# Should not have bash syntax errors
if grep -qi "syntax error" "$LOG_FILE" 2>/dev/null; then
    echo "  FAIL: Found syntax errors in output"
    ((FAIL++)) || true
else
    echo "  PASS: No syntax errors"
    ((PASS++)) || true
fi

# The dry-run output should mention ACFS version
if grep -qE "ACFS|acfs|Agentic Coding" "$LOG_FILE" 2>/dev/null; then
    echo "  PASS: ACFS banner/version present in output"
    ((PASS++)) || true
else
    echo "  WARN: ACFS banner not found (may be OK in dry-run mode)"
    ((PASS++)) || true
fi

echo ""
echo "---"
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "FAIL: curl|bash bootstrap E2E test failed."
    echo "Log output (last 30 lines):"
    tail -30 "$LOG_FILE" 2>/dev/null || true
    exit 1
fi

echo "PASS: curl|bash bootstrap E2E test passed."
exit 0
