#!/usr/bin/env bash
# Test the flywheel agent guide generator (scripts/generate-root-agents-md.sh)
#
# Covers the GH #314 contract:
#   - generation writes ONLY the ACFS-owned canonical path
#   - user-local tools (~/.local/bin) are detected even with a restricted PATH
#   - deployment is explicit, create-only, and never overwrites
#   - collisions produce an adjacent .acfs-new merge candidate + exit 3
#
# Run from: ./scripts/tests/test_agents_guide.sh

# Don't use set -e so tests can fail individually without stopping
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GENERATOR="$REPO_ROOT/scripts/generate-root-agents-md.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

log_step() { echo -e "[STEP] $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; ((TESTS_PASSED++)) || true; }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; ((TESTS_FAILED++)) || true; }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; ((TESTS_SKIPPED++)) || true; }

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

# Fresh sandbox home per test group
make_sandbox() {
    local tmpdir
    tmpdir="$(mktemp -d)" || return 1
    mkdir -p "$tmpdir/home/.local/bin" "$tmpdir/proj"
    # Fake user-local tool the restricted PATH cannot see
    cat > "$tmpdir/home/.local/bin/br" <<'EOF'
#!/usr/bin/env bash
echo "br 9.9.9"
EOF
    chmod +x "$tmpdir/home/.local/bin/br"
    echo "$tmpdir"
}

run_generator() {
    local sandbox="$1"
    shift
    env ACFS_TARGET_HOME="$sandbox/home" PATH="/usr/bin:/bin" bash "$GENERATOR" "$@"
}

# Test 1: generator exists and has valid syntax
test_generator_syntax() {
    [[ -f "$GENERATOR" ]] && bash -n "$GENERATOR"
}

# Test 2: default generation writes only the canonical ACFS-owned path
test_canonical_only() {
    local sandbox
    sandbox="$(make_sandbox)" || return 1

    run_generator "$sandbox" > /dev/null 2>&1 || return 1
    [[ -f "$sandbox/home/.acfs/docs/flywheel-agent-guide.md" ]] || return 1
    # Nothing outside the sandbox home may be created by a default run
    [[ ! -e "$sandbox/proj/AGENTS.md" ]] || return 1
    return 0
}

# Test 3: user-local tools are detected despite a restricted PATH
test_user_local_tool_detection() {
    local sandbox
    sandbox="$(make_sandbox)" || return 1

    run_generator "$sandbox" > /dev/null 2>&1 || return 1
    grep -q '| `br` | 9.9.9 |' "$sandbox/home/.acfs/docs/flywheel-agent-guide.md"
}

# Test 4: `path` prints the canonical location
test_path_subcommand() {
    local sandbox out
    sandbox="$(make_sandbox)" || return 1

    out="$(run_generator "$sandbox" path)" || return 1
    [[ "$out" == "$sandbox/home/.acfs/docs/flywheel-agent-guide.md" ]]
}

# Test 5: deploy creates the destination when absent
test_deploy_creates_when_absent() {
    local sandbox
    sandbox="$(make_sandbox)" || return 1

    run_generator "$sandbox" deploy --project "$sandbox/proj" > /dev/null 2>&1 || return 1
    [[ -f "$sandbox/proj/AGENTS.md" ]] || return 1
    grep -q 'Flywheel VPS - Agent Guidelines' "$sandbox/proj/AGENTS.md"
}

# Test 6: deploy refuses to overwrite an existing, differing destination
test_deploy_refuses_overwrite() {
    local sandbox
    sandbox="$(make_sandbox)" || return 1

    echo "USER AUTHORED RULES - MUST SURVIVE" > "$sandbox/proj/AGENTS.md"
    run_generator "$sandbox" deploy --project "$sandbox/proj" > /dev/null 2>&1
    local rc=$?

    # Exit 3 = collision; destination untouched; candidate written
    [[ $rc -eq 3 ]] || return 1
    grep -q 'USER AUTHORED RULES - MUST SURVIVE' "$sandbox/proj/AGENTS.md" || return 1
    [[ "$(wc -l < "$sandbox/proj/AGENTS.md")" -eq 1 ]] || return 1
    [[ -f "$sandbox/proj/AGENTS.md.acfs-new" ]] || return 1
    grep -q 'Flywheel VPS - Agent Guidelines' "$sandbox/proj/AGENTS.md.acfs-new"
}

# Test 7: redeploy over an identical destination is an idempotent no-op
test_deploy_idempotent() {
    local sandbox
    sandbox="$(make_sandbox)" || return 1

    run_generator "$sandbox" deploy --project "$sandbox/proj" > /dev/null 2>&1 || return 1
    # Second deploy: content matches (timestamp line is ignored) -> success, no candidate
    run_generator "$sandbox" deploy --project "$sandbox/proj" > /dev/null 2>&1 || return 1
    [[ ! -e "$sandbox/proj/AGENTS.md.acfs-new" ]]
}

# Test 8: deploy requires an explicit target
test_deploy_requires_target() {
    local sandbox
    sandbox="$(make_sandbox)" || return 1

    run_generator "$sandbox" deploy > /dev/null 2>&1
    [[ $? -eq 2 ]]
}

# Test 9: --dry-run prints to stdout and writes nothing
test_dry_run() {
    local sandbox out
    sandbox="$(make_sandbox)" || return 1

    out="$(run_generator "$sandbox" --dry-run)" || return 1
    [[ "$out" == *"Flywheel VPS - Agent Guidelines"* ]] || return 1
    [[ ! -e "$sandbox/home/.acfs/docs/flywheel-agent-guide.md" ]]
}

# ============================================================
# Run tests
# ============================================================
echo "=== Agent guide generator tests ==="
run_test "generator syntax" test_generator_syntax
run_test "default generation writes only canonical path" test_canonical_only
run_test "user-local tool detection under restricted PATH" test_user_local_tool_detection
run_test "path subcommand" test_path_subcommand
run_test "deploy creates destination when absent" test_deploy_creates_when_absent
run_test "deploy refuses overwrite + writes candidate" test_deploy_refuses_overwrite
run_test "redeploy of identical content is idempotent" test_deploy_idempotent
run_test "deploy without target is a usage error" test_deploy_requires_target
run_test "dry-run writes nothing" test_dry_run

echo ""
echo "Passed: $TESTS_PASSED, Failed: $TESTS_FAILED, Skipped: $TESTS_SKIPPED"
[[ $TESTS_FAILED -eq 0 ]]
