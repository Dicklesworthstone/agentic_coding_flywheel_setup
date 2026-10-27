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

# Test 10: --help anywhere prints usage and writes nothing (#484). `--output
# --help` and `deploy --to --help` used to take "--help" as the path.
test_help_anywhere_writes_nothing() {
    local sandbox out args
    sandbox="$(make_sandbox)" || return 1

    for args in "--output --help" "deploy --to --help" "deploy --project $sandbox/proj -h" \
        "path --help" "--dry-run --help"; do
        # shellcheck disable=SC2086 # split the case into words on purpose
        out="$(cd "$sandbox/proj" && run_generator "$sandbox" $args 2>&1)" || return 1
        [[ "$out" == *"Usage:"*"flywheel-update-agents-md deploy"* ]] || return 1
    done
    [[ ! -e "$sandbox/home/.acfs/docs/flywheel-agent-guide.md" ]] || return 1
    [[ -z "$(ls -A "$sandbox/proj")" ]]
}

# Test 11: an option value that looks like a flag is a usage error
test_flag_like_option_values_rejected() {
    local sandbox
    sandbox="$(make_sandbox)" || return 1

    (cd "$sandbox/proj" && run_generator "$sandbox" --output --dry-run > /dev/null 2>&1)
    [[ $? -eq 2 ]] || return 1
    (cd "$sandbox/proj" && run_generator "$sandbox" deploy --to --workspace > /dev/null 2>&1)
    [[ $? -eq 2 ]] || return 1
    [[ ! -e "$sandbox/home/.acfs/docs/flywheel-agent-guide.md" ]] || return 1
    [[ -z "$(ls -A "$sandbox/proj")" ]]
}

# Existing merge notes are user data, even when ACFS chose the candidate name.
test_existing_merge_candidate_is_preserved() {
    local sandbox rc
    sandbox="$(make_sandbox)" || return 1
    printf '%s\n' 'USER RULES' > "$sandbox/proj/AGENTS.md"
    printf '%s\n' 'UNMERGED NOTES' > "$sandbox/proj/AGENTS.md.acfs-new"
    run_generator "$sandbox" deploy --project "$sandbox/proj" > "$sandbox/output" 2>&1
    rc=$?
    [[ $rc -eq 3 ]] || return 1
    [[ "$(cat "$sandbox/proj/AGENTS.md")" == 'USER RULES' ]] || return 1
    [[ "$(cat "$sandbox/proj/AGENTS.md.acfs-new")" == 'UNMERGED NOTES' ]] || return 1
    local candidate found=0
    for candidate in "$sandbox/proj/AGENTS.md.acfs-new."*; do
        [[ -f "$candidate" ]] || continue
        grep -q 'Flywheel VPS - Agent Guidelines' "$candidate" || return 1
        grep -Fq "$candidate" "$sandbox/output" || return 1
        found=1
    done
    [[ $found -eq 1 ]]
}

test_deploy_preserves_dangling_destination_symlink() {
    local sandbox rc
    sandbox="$(make_sandbox)" || return 1
    ln -s "$sandbox/untouched" "$sandbox/proj/AGENTS.md"
    run_generator "$sandbox" deploy --project "$sandbox/proj" > "$sandbox/output" 2>&1
    rc=$?
    [[ $rc -ne 0 && -L "$sandbox/proj/AGENTS.md" && ! -e "$sandbox/untouched" ]]
}

test_candidate_symlink_target_is_preserved() {
    local sandbox rc
    sandbox="$(make_sandbox)" || return 1
    printf '%s\n' 'USER RULES' > "$sandbox/proj/AGENTS.md"
    printf '%s\n' 'KEEP TARGET' > "$sandbox/untouched"
    ln -s "$sandbox/untouched" "$sandbox/proj/AGENTS.md.acfs-new"
    run_generator "$sandbox" deploy --project "$sandbox/proj" > "$sandbox/output" 2>&1
    rc=$?
    [[ $rc -eq 3 && -L "$sandbox/proj/AGENTS.md.acfs-new" ]] || return 1
    [[ "$(cat "$sandbox/untouched")" == 'KEEP TARGET' ]]
}

test_explicit_output_preserves_existing_file() {
    local sandbox rc
    sandbox="$(make_sandbox)" || return 1
    printf '%s\n' 'EXPLICIT USER RULES' > "$sandbox/proj/AGENTS.md"
    run_generator "$sandbox" --output "$sandbox/proj/AGENTS.md" > "$sandbox/output" 2>&1
    rc=$?
    [[ $rc -eq 3 ]] || return 1
    [[ "$(cat "$sandbox/proj/AGENTS.md")" == 'EXPLICIT USER RULES' ]] || return 1
    grep -q 'Flywheel VPS - Agent Guidelines' "$sandbox/proj/AGENTS.md.acfs-new"
}

test_concurrent_destination_is_preserved() {
    local sandbox rc python_bin
    sandbox="$(make_sandbox)" || return 1
    python_bin="$(command -v python3)" || return 1
    mkdir -p "$sandbox/shims" "$sandbox/hook"
    cat > "$sandbox/shims/cp" <<'SH'
#!/bin/bash
if [[ "${2:-}" == "$ACFS_GUIDE_RACE_DEST" ]]; then
    (set -C; printf '%s\n' 'CONCURRENT USER RULES' > "$ACFS_GUIDE_RACE_DEST") || exit 71
fi
exec /bin/cp "$@"
SH
    printf '#!/bin/bash\nPYTHONPATH=%q exec %q "$@"\n' "$sandbox/hook" "$python_bin" > "$sandbox/shims/python3"
    cat > "$sandbox/hook/sitecustomize.py" <<'PY'
import os
original_link = os.link
def concurrent_link(source, destination, *args, **kwargs):
    if str(destination) == 'AGENTS.md':
        descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                             0o600, dir_fd=kwargs.get('dst_dir_fd'))
        with os.fdopen(descriptor, 'w') as output:
            output.write('CONCURRENT USER RULES\n')
    return original_link(source, destination, *args, **kwargs)
os.link = concurrent_link
PY
    chmod +x "$sandbox/shims/cp" "$sandbox/shims/python3"
    env ACFS_TARGET_HOME="$sandbox/home" ACFS_GUIDE_RACE_DEST="$sandbox/proj/AGENTS.md" \
        PATH="$sandbox/shims:/usr/bin:/bin" bash "$GENERATOR" deploy --project "$sandbox/proj" > "$sandbox/output" 2>&1
    rc=$?
    [[ $rc -eq 3 ]] || return 1
    [[ "$(cat "$sandbox/proj/AGENTS.md")" == 'CONCURRENT USER RULES' ]]
}

test_interrupted_canonical_refresh_preserves_previous_guide() {
    local sandbox rc canonical
    sandbox="$(make_sandbox)" || return 1
    canonical="$sandbox/home/.acfs/docs/flywheel-agent-guide.md"
    mkdir -p "$(dirname "$canonical")"
    printf '%s\n' 'PREVIOUS COMPLETE CANONICAL' > "$canonical"
    env ACFS_TARGET_HOME="$sandbox/home" PATH="/usr/bin:/bin" \
        bash -c 'ulimit -f 1; exec bash "$1"' _ "$GENERATOR" > "$sandbox/output" 2>&1
    rc=$?
    [[ $rc -ne 0 ]] || return 1
    [[ "$(cat "$canonical")" == 'PREVIOUS COMPLETE CANONICAL' ]]
}

test_deploy_preserves_hardlinked_rules_and_linked_parent() {
    local sandbox rc
    sandbox="$(make_sandbox)" || return 1
    printf '%s\n' 'HARDLINKED USER RULES' > "$sandbox/original"
    ln "$sandbox/original" "$sandbox/proj/AGENTS.md"
    run_generator "$sandbox" deploy --project "$sandbox/proj" > "$sandbox/output" 2>&1
    rc=$?
    [[ $rc -eq 3 ]] || return 1
    [[ "$sandbox/original" -ef "$sandbox/proj/AGENTS.md" ]] || return 1
    [[ "$(cat "$sandbox/original")" == 'HARDLINKED USER RULES' ]] || return 1
    mkdir "$sandbox/outside"
    ln -s "$sandbox/outside" "$sandbox/linked"
    run_generator "$sandbox" --output "$sandbox/linked/AGENTS.md" > "$sandbox/linked-output" 2>&1
    rc=$?
    [[ $rc -ne 0 && ! -e "$sandbox/outside/AGENTS.md" ]] || return 1
    run_generator "$sandbox" --output "$sandbox/linked/../via-linked-parent.md" > "$sandbox/dotdot-output" 2>&1
    rc=$?
    [[ $rc -ne 0 && ! -e "$sandbox/via-linked-parent.md" ]]
}

test_matching_explicit_output_is_not_replaced() {
    local sandbox inode_before
    sandbox="$(make_sandbox)" || return 1
    run_generator "$sandbox" --output "$sandbox/proj/AGENTS.md" > "$sandbox/output" 2>&1 || return 1
    inode_before="$(ls -i "$sandbox/proj/AGENTS.md")"
    run_generator "$sandbox" --output "$sandbox/proj/AGENTS.md" >> "$sandbox/output" 2>&1 || return 1
    [[ "$(ls -i "$sandbox/proj/AGENTS.md")" == "$inode_before" ]] || return 1
    [[ ! -e "$sandbox/proj/AGENTS.md.acfs-new" ]]
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
run_test "--help anywhere writes nothing" test_help_anywhere_writes_nothing
run_test "flag-like option values are usage errors" test_flag_like_option_values_rejected
run_test "existing merge candidate is preserved" test_existing_merge_candidate_is_preserved
run_test "dangling destination symlink is preserved" test_deploy_preserves_dangling_destination_symlink
run_test "merge candidate symlink target is preserved" test_candidate_symlink_target_is_preserved
run_test "explicit output preserves existing rules" test_explicit_output_preserves_existing_file
run_test "concurrently created destination is preserved" test_concurrent_destination_is_preserved
run_test "interrupted canonical refresh preserves previous guide" test_interrupted_canonical_refresh_preserves_previous_guide
run_test "hardlinked rules and linked parent are preserved" test_deploy_preserves_hardlinked_rules_and_linked_parent
run_test "matching explicit output is not replaced" test_matching_explicit_output_is_not_replaced

echo ""
echo "Passed: $TESTS_PASSED, Failed: $TESTS_FAILED, Skipped: $TESTS_SKIPPED"
[[ $TESTS_FAILED -eq 0 ]]
