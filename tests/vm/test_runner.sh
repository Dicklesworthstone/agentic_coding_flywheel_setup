#!/bin/bash
set -euo pipefail

# This script runs INSIDE the Docker container

ARTIFACTS_DIR="/repo/tests/artifacts"
mkdir -p "$ARTIFACTS_DIR"

# /repo is the host checkout. Hand everything this root container writes there
# back to the invoking host user on every exit, so Linux hosts are not left with
# root-owned artifacts they cannot clean up (test_install_ubuntu.sh passes ids).
return_host_artifacts() {
    local dir
    [[ "${ACFS_HOST_UID:-}" =~ ^[0-9]+$ && "${ACFS_HOST_GID:-}" =~ ^[0-9]+$ ]] || return 0
    for dir in "$ARTIFACTS_DIR" /repo/tests/e2e/logs; do
        [[ -d "$dir" && ! -L "$dir" ]] || continue
        chown -R -P "$ACFS_HOST_UID:$ACFS_HOST_GID" "$dir" || echo "[WARN] could not return $dir to the host user" >&2
    done
}
trap return_host_artifacts EXIT

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

TEST_MODE="${ACFS_TEST_MODE:-vibe}"
INSTALL_ARGS=(--yes --skip-ubuntu-upgrade --mode "${TEST_MODE}")
if [[ "${ACFS_TEST_STRICT:-false}" == "true" ]]; then
    INSTALL_ARGS+=(--strict)
fi

# PHASE 1: Fresh Install
# With ACFS_TEST_INTERRUPT_RESUME=true the first run is hung up (SIGHUP, as an
# SSH drop would) once INTERRUPT_AFTER_PHASE is checkpointed, so the kill lands
# inside the next phase. The rerun with --resume must skip every checkpointed
# phase and finish the install.
STATE_FILE="/home/ubuntu/.acfs/state.json"
INTERRUPT_AFTER_PHASE="${ACFS_TEST_INTERRUPT_AFTER_PHASE:-cli_tools}"

completed_phases() {
    jq -r '(.completed_phases // [])[]' "$STATE_FILE" 2>/dev/null
}

if [[ "${ACFS_TEST_INTERRUPT_RESUME:-false}" == "true" ]]; then
    log "PHASE 1a: Interrupted install (mode=${TEST_MODE}, hang up after ${INTERRUPT_AFTER_PHASE})"
    bash install.sh "${INSTALL_ARGS[@]}" > "${ARTIFACTS_DIR}/install-interrupted.log" 2>&1 &
    install_pid=$!
    waited=0
    until completed_phases | grep -qx "$INTERRUPT_AFTER_PHASE"; do
        if ! kill -0 "$install_pid" 2>/dev/null; then
            tail -n 50 "${ARTIFACTS_DIR}/install-interrupted.log"
            fail "Installer exited before ${INTERRUPT_AFTER_PHASE} was checkpointed"
        fi
        if (( waited >= 3600 )); then
            kill -KILL "$install_pid" 2>/dev/null || true
            fail "Timed out waiting for ${INTERRUPT_AFTER_PHASE} to be checkpointed"
        fi
        sleep 5
        waited=$((waited + 5))
    done
    kill -HUP "$install_pid"
    interrupted_status=0
    wait "$install_pid" || interrupted_status=$?
    [[ $interrupted_status -ne 0 ]] || fail "Hung-up installer reported success"
    mapfile -t checkpointed < <(completed_phases)
    [[ ${#checkpointed[@]} -gt 0 ]] || fail "No checkpointed phases survived the interruption"
    printf '%s\n' "${checkpointed[@]}" | grep -qx "$INTERRUPT_AFTER_PHASE" \
        || fail "Checkpoint for ${INTERRUPT_AFTER_PHASE} was lost by the interruption"
    if completed_phases | grep -qx finalize; then
        fail "Interruption landed after the final phase; nothing was left to resume"
    fi
    log "Interrupted with exit ${interrupted_status}; checkpointed: ${checkpointed[*]}"

    log "PHASE 1b: Resume (mode=${TEST_MODE})"
    if bash install.sh "${INSTALL_ARGS[@]}" --resume > "${ARTIFACTS_DIR}/install.log" 2>&1; then
        log "Resumed install successful"
    else
        log "Resumed install failed! Last 50 lines:"
        tail -n 50 "${ARTIFACTS_DIR}/install.log"
        fail "Resume phase failed"
    fi
    skipped=$(grep -c 'Skipped (already completed)' "${ARTIFACTS_DIR}/install.log" || true)
    if (( skipped < ${#checkpointed[@]} )); then
        fail "Resume re-ran checkpointed phases: ${skipped} skipped, ${#checkpointed[@]} checkpointed"
    fi
    completed_phases | grep -qx finalize || fail "Resumed install did not checkpoint the final phase"
    log "Resume skipped ${skipped} checkpointed phase(s) and completed the install"
else
    log "PHASE 1: Fresh Install (mode=${TEST_MODE})"
    if bash install.sh "${INSTALL_ARGS[@]}" > "${ARTIFACTS_DIR}/install.log" 2>&1; then
        log "Install successful"
    else
        log "Install failed! Last 50 lines:"
        tail -n 50 "${ARTIFACTS_DIR}/install.log"
        fail "Install phase failed"
    fi
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
run_check "onboard_noninteractive_lesson" "zsh -ic 'progress=\$(mktemp); exec </dev/null; ACFS_PROGRESS_FILE=\"\$progress\" onboard 1 >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "onboard_noninteractive_menu" "zsh -ic 'out=\$(mktemp); if timeout 5s onboard </dev/null >\"\$out\" 2>&1; then false; else menu_status=\$?; command grep -q \"Interactive menu requires a TTY\" \"\$out\" && [ \"\$menu_status\" -eq 1 ]; fi'" || failed_checks=$((failed_checks + 1))
run_check "ntm" "zsh -ic 'ntm --help >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "gh" "zsh -ic 'gh --version >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "jq" "zsh -ic 'jq --version >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "sg" "zsh -ic 'sg --version >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "codex" "zsh -ic 'codex --version >/dev/null'" || failed_checks=$((failed_checks + 1))
# Gemini CLI retired 2026-06-18; its successor is Antigravity (agy), with the
# legacy gmi alias routing to the locked agy launcher.
run_check "agy" "zsh -ic 'command -v agy >/dev/null && command -v gmi >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "claude" "zsh -ic 'claude --version >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "ru" "zsh -ic 'ru --version >/dev/null'" || failed_checks=$((failed_checks + 1))
run_check "dcg" "zsh -ic 'dcg --version >/dev/null'" || failed_checks=$((failed_checks + 1))

# Check DCG hook
run_check "dcg_hook" "zsh -ic 'set -o pipefail; dcg doctor --format json 2>/dev/null | jq -e \".hook_registered == true\" >/dev/null || (command -v script >/dev/null 2>&1 && tty_output=\$(script -q -c \"dcg doctor\" /dev/null 2>/dev/null || true) && printf \"%s\" \"\$tty_output\" | grep -qi \"hook wiring.*OK\")'" || failed_checks=$((failed_checks + 1))
run_check "dcg_block" "zsh -ic 'dcg_output=\$(dcg test \"git reset --hard\" 2>&1 || true); printf \"%s\" \"\$dcg_output\" | command grep -Eqi \"deny|block\"'" || failed_checks=$((failed_checks + 1))
# "allow" alone also matched "not allowed"; require an allow verdict with no deny/block wording.
run_check "dcg_allow" "zsh -ic 'dcg_output=\$(dcg test \"git status\" 2>&1 || true); printf \"%s\" \"\$dcg_output\" | command grep -Eqi \"allow\" && ! printf \"%s\" \"\$dcg_output\" | command grep -Eqi \"deny|block|not allowed\"'" || failed_checks=$((failed_checks + 1))

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

# PHASE 2.4: Optional Real Cross-Agent Resume E2E
# Requires authenticated codex/claude/gemini accounts in the test environment.
if [[ "${ACFS_RUN_REAL_AGENT_RESUME_E2E:-false}" == "true" ]]; then
    log "PHASE 2.4: Real Cross-Agent Resume E2E"
    REAL_RESUME_LOG="${ARTIFACTS_DIR}/cross_agent_resume.log"
    if su - ubuntu -c "zsh -ic 'cd /repo && bash tests/e2e/test_cross_agent_resume_e2e.sh'" > "$REAL_RESUME_LOG" 2>&1; then
        log "Real cross-agent resume E2E passed"
    else
        log "Real cross-agent resume E2E failed! See $REAL_RESUME_LOG"
        cat "$REAL_RESUME_LOG"
        fail "Real cross-agent resume E2E failed"
    fi

    for f in /repo/tests/e2e/logs/cross_agent_resume_*; do
        [[ -e "$f" ]] || continue
        cp "$f" "$ARTIFACTS_DIR/" 2>/dev/null || true
    done
else
    log "Skipping real cross-agent resume E2E (set ACFS_RUN_REAL_AGENT_RESUME_E2E=true)"
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

# PHASE 2.7: Expanded New Tools E2E coverage
log "PHASE 2.7: Expanded New Tools E2E"
NEW_TOOLS_LOG="${ARTIFACTS_DIR}/new_tools_e2e.log"
if su - ubuntu -c "zsh -ic 'cd /repo && bash tests/e2e/test_new_tools_e2e.sh'" > "$NEW_TOOLS_LOG" 2>&1; then
    log "Expanded new tools E2E passed"
    cp /tmp/acfs_e2e_tools_*.log "$ARTIFACTS_DIR/" 2>/dev/null || true
    cp /tmp/acfs_e2e_results_*.json "$ARTIFACTS_DIR/" 2>/dev/null || true
else
    log "Expanded new tools E2E failed! See $NEW_TOOLS_LOG"
    cat "$NEW_TOOLS_LOG"
    cp /tmp/acfs_e2e_tools_*.log "$ARTIFACTS_DIR/" 2>/dev/null || true
    cp /tmp/acfs_e2e_results_*.json "$ARTIFACTS_DIR/" 2>/dev/null || true
    fail "Expanded new tools E2E failed"
fi

# PHASE 3: Idempotency
log "PHASE 3: Idempotency Check"
if bash install.sh "${INSTALL_ARGS[@]}" > "${ARTIFACTS_DIR}/idempotency.log" 2>&1; then
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
