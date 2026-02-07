#!/bin/bash
set -euo pipefail

# This script runs INSIDE the Docker container

ARTIFACTS_DIR="/repo/tests/artifacts"
mkdir -p "$ARTIFACTS_DIR"

log() {
    echo "[TEST] $1"
}

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

# Install dependencies
log "Installing bootstrap dependencies..."
apt-get update -qq
apt-get install -y -qq sudo curl git ca-certificates jq unzip tar xz-utils gnupg >/dev/null

# Pre-install checks
bash /repo/tests/vm/bootstrap_offline_checks.sh
bash /repo/tests/vm/selection_checks.sh

cd /repo

STRICT_FLAG=""
if [[ "${ACFS_TEST_STRICT:-false}" == "true" ]]; then
    STRICT_FLAG="--strict"
fi

# PHASE 1: Fresh Install
log "PHASE 1: Fresh Install (mode=${ACFS_TEST_MODE})"
if bash install.sh --yes --skip-ubuntu-upgrade --mode "${ACFS_TEST_MODE}" ${STRICT_FLAG} > "${ARTIFACTS_DIR}/install.log" 2>&1; then
    log "Install successful"
else
    log "Install failed! Last 50 lines:"
    tail -n 50 "${ARTIFACTS_DIR}/install.log"
    fail "Install phase failed"
fi

# PHASE 2: Verification
log "PHASE 2: Verification"
VERIFY_LOG="${ARTIFACTS_DIR}/verify.log"

run_check() {
    local name="$1"
    local cmd="$2"
    if su - ubuntu -c "$cmd" >> "$VERIFY_LOG" 2>&1; then
        echo "  [ok] $name"
    else
        echo "  [fail] $name"
        return 1
    fi
}

failed_checks=0

run_check "doctor" "zsh -ic 'acfs doctor'" || failed_checks=$((failed_checks + 1))
run_check "state_file" "test -f ~/.acfs/VERSION" || failed_checks=$((failed_checks + 1))
run_check "onboard" "zsh -ic 'onboard --help >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "ntm" "zsh -ic 'ntm --help >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "gh" "zsh -ic 'gh --version >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "jq" "zsh -ic 'jq --version >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "sg" "zsh -ic 'sg --version >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "codex" "zsh -ic 'codex --version >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "gemini" "zsh -ic 'gemini --version >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "claude" "zsh -ic 'claude --version >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "ru" "zsh -ic 'ru --version >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "dcg" "zsh -ic 'dcg --version >/dev/null'" || failed_checks=$((failed_checks + 1))

# Check DCG hook
run_check "dcg_hook" "zsh -ic 'set -o pipefail; dcg doctor --format json 2>/dev/null | jq -e \".hook_registered == true\" >/dev/null || dcg doctor 2>/dev/null | grep -qi \"hook wiring.*OK\"'" || failed_checks=$((failed_checks + 1))
run_check "dcg_block" "zsh -ic 'dcg test \"git reset --hard\" | grep -Eqi \"deny|block\"'" || failed_checks=$((failed_checks + 1))
run_check "dcg_allow" "zsh -ic 'dcg test \"git status\" | grep -Eqi \"allow\"'" || failed_checks=$((failed_checks + 1))

# Resume checks
if bash /repo/tests/vm/resume_checks.sh >> "$VERIFY_LOG" 2>&1; then
    echo "  [ok] resume_checks"
else
    echo "  [fail] resume_checks"
    failed_checks=$((failed_checks + 1))
fi

if [[ $failed_checks -gt 0 ]]; then
    log "Verification failed with $failed_checks errors. See $VERIFY_LOG"
    fail "Verification phase failed"
fi

# PHASE 2.5: Install Artifacts (bd-31ps.3.3)
log "PHASE 2.5: Install Artifacts Validation"
ARTIFACTS_LOG="${ARTIFACTS_DIR}/artifacts_test.log"
if bash /repo/tests/vm/test_install_artifacts.sh --user ubuntu --home /home/ubuntu > "$ARTIFACTS_LOG" 2>&1; then
    log "Install artifacts validation passed"
    # Copy any test logs for debugging
    cp /tmp/acfs_install_artifacts_test_*.log "$ARTIFACTS_DIR/" 2>/dev/null || true
else
    log "Install artifacts validation failed! See $ARTIFACTS_LOG"
    cat "$ARTIFACTS_LOG"
    # Copy test logs for debugging
    cp /tmp/acfs_install_artifacts_test_*.log "$ARTIFACTS_DIR/" 2>/dev/null || true
    fail "Install artifacts validation failed"
fi

# PHASE 2.6: git_safety_guard Removal Verification (bd-33vh.8)
log "PHASE 2.6: git_safety_guard Removal Verification"
GUARD_REMOVAL_LOG="${ARTIFACTS_DIR}/git_safety_guard_removal.log"
if bash /repo/tests/e2e/test_git_safety_guard_removal.sh --user ubuntu --home /home/ubuntu > "$GUARD_REMOVAL_LOG" 2>&1; then
    log "git_safety_guard removal verification passed"
    cp /tmp/git_safety_guard_removal_*.log "$ARTIFACTS_DIR/" 2>/dev/null || true
    cp /tmp/git_safety_guard_removal_*.json "$ARTIFACTS_DIR/" 2>/dev/null || true
else
    log "git_safety_guard removal verification failed! See $GUARD_REMOVAL_LOG"
    cat "$GUARD_REMOVAL_LOG"
    cp /tmp/git_safety_guard_removal_*.log "$ARTIFACTS_DIR/" 2>/dev/null || true
    cp /tmp/git_safety_guard_removal_*.json "$ARTIFACTS_DIR/" 2>/dev/null || true
    fail "git_safety_guard removal verification failed"
fi

# PHASE 3: Idempotency
log "PHASE 3: Idempotency Check"
if bash install.sh --yes --skip-ubuntu-upgrade --mode "${ACFS_TEST_MODE}" ${STRICT_FLAG} > "${ARTIFACTS_DIR}/idempotency.log" 2>&1; then
    log "Idempotency run successful"
else
    log "Idempotency run failed! Last 50 lines:"
    tail -n 50 "${ARTIFACTS_DIR}/idempotency.log"
    fail "Idempotency phase failed"
fi

# Check that nothing major broke after re-run
if ! su - ubuntu -c "zsh -ic 'acfs doctor'" >/dev/null 2>&1; then
    fail "Doctor failed after idempotency run"
fi

log "ALL TESTS PASSED"
exit 0
