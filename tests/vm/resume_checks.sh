#!/usr/bin/env bash
# ============================================================
# ACFS Resume Behavior Integration Checks
#
# These tests validate state.sh resume logic in a realistic environment
# without re-running the full installer multiple times.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../../scripts/lib/state.sh
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/lib/state.sh"

failures=0

pass() {
  echo "✅ $1"
}

fail() {
  echo "❌ $1" >&2
  failures=$((failures + 1))
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$label"
  else
    fail "$label (expected $expected, got $actual)"
  fi
}

assert_true() {
  local label="$1"
  shift
  if "$@"; then
    pass "$label"
  else
    fail "$label"
  fi
}

assert_false() {
  local label="$1"
  shift
  if "$@"; then
    fail "$label"
  else
    pass "$label"
  fi
}

assert_file_missing() {
  local path="$1"
  local label="$2"
  if [[ -f "$path" ]]; then
    fail "$label (file still exists: $path)"
  else
    pass "$label"
  fi
}

new_state_file() {
  local tag="$1"
  local home="/tmp/acfs-home-${tag}-$$-${RANDOM}"
  echo "${home}/state.json"
}

init_state_with_completed() {
  local state_file="$1"
  shift

  export ACFS_STATE_FILE="$state_file"
  export ACFS_HOME
  ACFS_HOME="$(dirname "$state_file")"
  export MODE="vibe"
  export TARGET_USER="ubuntu"
  export ACFS_VERSION="0.3.0"

  state_init

  for phase in "$@"; do
    state_phase_complete "$phase"
  done
}

test_normal_resume() {
  local state_file
  state_file="$(new_state_file normal)"
  init_state_with_completed "$state_file" \
    "user_setup" "filesystem" "shell_setup" "cli_tools" "languages"

  export ACFS_FORCE_REINSTALL=false
  export ACFS_FORCE_RESUME=false
  export ACFS_INTERACTIVE=false

  local rc
  if confirm_resume; then rc=0; else rc=$?; fi
  assert_eq 0 "$rc" "normal resume returns 0"

  assert_true "completed phase is skipped (user_setup)" state_should_skip_phase "user_setup"
  assert_false "pending phase is not skipped (agents)" state_should_skip_phase "agents"
}

test_force_reinstall() {
  local state_file
  state_file="$(new_state_file force)"
  init_state_with_completed "$state_file" "user_setup" "filesystem"

  export ACFS_FORCE_REINSTALL=true
  export ACFS_FORCE_RESUME=false
  export ACFS_INTERACTIVE=false

  local rc
  if confirm_resume; then rc=0; else rc=$?; fi
  assert_eq 1 "$rc" "force reinstall returns 1 (fresh install)"
  assert_file_missing "$state_file" "force reinstall removes state file"
  export ACFS_FORCE_REINSTALL=false
}

test_force_resume_without_completed_phases() {
  local state_file
  state_file="$(new_state_file force-resume-empty)"
  init_state_with_completed "$state_file"
  state_update '.failed_phase = "user_setup"'

  export ACFS_FORCE_REINSTALL=false
  export ACFS_FORCE_RESUME=true
  export ACFS_INTERACTIVE=false

  local rc
  if confirm_resume; then rc=0; else rc=$?; fi
  assert_eq 0 "$rc" "force resume works when a phase failed before any phase completed"

  export ACFS_FORCE_RESUME=false
}

test_force_reinstall_without_completed_phases() {
  local state_file
  state_file="$(new_state_file force-reinstall-empty)"
  init_state_with_completed "$state_file"
  state_update '.failed_phase = "user_setup"'

  export ACFS_FORCE_REINSTALL=true
  export ACFS_FORCE_RESUME=false
  export ACFS_INTERACTIVE=false

  local rc
  if confirm_resume; then rc=0; else rc=$?; fi
  assert_eq 1 "$rc" "force reinstall works when a phase failed before any phase completed"
  assert_file_missing "$state_file" "force reinstall removes failed zero-progress state file"

  export ACFS_FORCE_REINSTALL=false
}

test_corrupted_state() {
  local state_file
  state_file="$(new_state_file corrupt)"
  mkdir -p "$(dirname "$state_file")"
  printf '%s' "not json" > "$state_file"
  export ACFS_STATE_FILE="$state_file"
  export ACFS_HOME
  ACFS_HOME="$(dirname "$state_file")"

  export ACFS_FORCE_REINSTALL=false
  export ACFS_FORCE_RESUME=false
  export ACFS_INTERACTIVE=false

  local rc
  if confirm_resume; then rc=0; else rc=$?; fi
  assert_eq 1 "$rc" "corrupted state returns fresh install"
  assert_file_missing "$state_file" "corrupted state file is removed"
}

test_interrupt_phase() {
  local state_file
  state_file="$(new_state_file interrupt)"
  init_state_with_completed "$state_file"

  phase_fail() { return 2; }
  phase_ok() { return 0; }

  run_phase "cli_tools" "4/9 CLI Tools" phase_fail || true
  assert_false "failed phase not marked complete" state_is_phase_completed "cli_tools"

  run_phase "cli_tools" "4/9 CLI Tools" phase_ok
  local rc=$?
  assert_eq 0 "$rc" "rerun phase succeeds after failure"
  assert_true "phase marked complete after rerun" state_is_phase_completed "cli_tools"
}

test_version_mismatch() {
  local state_file
  state_file="$(new_state_file version)"
  mkdir -p "$(dirname "$state_file")"
  cat > "$state_file" <<EOF
{
  "schema_version": 99,
  "version": "9.9.9",
  "completed_phases": []
}
EOF
  export ACFS_STATE_FILE="$state_file"
  export ACFS_HOME
  ACFS_HOME="$(dirname "$state_file")"

  local rc
  if state_check_version; then rc=0; else rc=$?; fi
  assert_eq 1 "$rc" "version mismatch returns incompatible"
}

main() {
  echo ""
  echo "=== ACFS Resume Behavior Checks ==="
  test_normal_resume
  test_corrupted_state
  test_force_reinstall
  test_force_resume_without_completed_phases
  test_force_reinstall_without_completed_phases
  test_interrupt_phase
  test_version_mismatch

  echo ""
  if [[ "$failures" -gt 0 ]]; then
    echo "Resume checks: ${failures} failure(s)" >&2
    exit 1
  fi

  echo "Resume checks: all passed"
}

main "$@"
