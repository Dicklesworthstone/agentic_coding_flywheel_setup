#!/usr/bin/env bash
# ============================================================
# ACFS Ubuntu Upgrade Unit Tests
# Tests for scripts/lib/ubuntu_upgrade.sh
#
# Usage: ./scripts/tests/ubuntu_upgrade_test.sh
# Related beads: agentic_coding_flywheel_setup-dwh (ubu.7)
# ============================================================

set -euo pipefail

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Test Framework
# ============================================================

log_test() {
    echo -e "${BLUE}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    ((TESTS_PASSED += 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((TESTS_FAILED += 1))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $*"
    ((TESTS_SKIPPED += 1))
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="${3:-assertion}"

    if [[ "$expected" == "$actual" ]]; then
        log_pass "$test_name: expected '$expected', got '$actual'"
        return 0
    else
        log_fail "$test_name: expected '$expected', got '$actual'"
        return 1
    fi
}

assert_not_empty() {
    local actual="$1"
    local test_name="${2:-assertion}"

    if [[ -n "$actual" ]]; then
        log_pass "$test_name: value is not empty"
        return 0
    else
        log_fail "$test_name: expected non-empty value"
        return 1
    fi
}

assert_empty() {
    local actual="$1"
    local test_name="${2:-assertion}"

    if [[ -z "$actual" ]]; then
        log_pass "$test_name: value is empty as expected"
        return 0
    else
        log_fail "$test_name: expected empty value, got '$actual'"
        return 1
    fi
}

assert_command_succeeds() {
    local test_name="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        log_pass "$test_name: command succeeded"
        return 0
    else
        log_fail "$test_name: command failed"
        return 1
    fi
}

assert_command_fails() {
    local test_name="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        log_fail "$test_name: command succeeded but should have failed"
        return 1
    else
        log_pass "$test_name: command failed as expected"
        return 0
    fi
}

# ============================================================
# Mock Functions for Testing
# ============================================================

# Mock /etc/os-release content
_create_mock_os_release() {
    local version_id="$1"
    local codename="${2:-}"

    _TEST_OS_RELEASE=$(cat <<EOF
NAME="Ubuntu"
VERSION="$version_id LTS (Noble Numbat)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu $version_id LTS"
VERSION_ID="$version_id"
VERSION_CODENAME="${codename:-noble}"
EOF
)
    export _TEST_OS_RELEASE
}

# Override ubuntu_get_version_string for testing
_mock_ubuntu_version() {
    export _TEST_UBUNTU_VERSION="$1"
}

_clear_mocks() {
    unset _TEST_OS_RELEASE
    unset _TEST_UBUNTU_VERSION
}

_write_base_state_fixture() {
    local state_file="$1"

    mkdir -p "$(dirname "$state_file")"
    cat > "$state_file" <<'JSON'
{
  "schema_version": 3,
  "version": "test",
  "target_user": "alice",
  "target_home": "/srv/alice",
  "bin_dir": "/srv/alice/.local/bin",
  "started_at": "2026-05-08T00:00:00Z",
  "last_updated": "2026-05-08T00:00:00Z",
  "mode": "vibe",
  "completed_phases": [],
  "failed_phase": null,
  "failed_step": null,
  "skip_postgres": false,
  "skip_vault": false,
  "skip_cloud": false,
  "ubuntu_upgrade": {
    "enabled": false,
    "current_stage": "none",
    "upgrade_path": [],
    "completed_upgrades": []
  }
}
JSON
}

_write_upgrade_stage_fixture() {
    local state_file="$1"
    local stage="$2"

    _write_base_state_fixture "$state_file"
    jq --arg stage "$stage" '
      .ubuntu_upgrade = {
        enabled: true,
        started_at: "2026-05-08T00:00:00Z",
        original_version: "24.04",
        target_version: "25.10",
        upgrade_path: ["25.04", "25.10"],
        current_stage: $stage,
        completed_upgrades: [],
        current_upgrade: null,
        needs_reboot: ($stage == "awaiting_reboot" or $stage == "pre_upgrade_reboot"),
        resume_after_reboot: ($stage == "awaiting_reboot" or $stage == "pre_upgrade_reboot"),
        last_error: null
      }
    ' "$state_file" > "${state_file}.tmp"
    mv "${state_file}.tmp" "$state_file"
}

_calculate_path_for_version() {
    local version="$1"
    local target="${2:-2510}"

    (
        rehearsal_version="$version"
        ubuntu_get_version_string() { printf '%s\n' "$rehearsal_version"; }
        ubuntu_calculate_upgrade_path "$target" | paste -sd ' ' -
    )
}

# ============================================================
# Source the library under test
# ============================================================

source_upgrade_lib() {
    if [[ -f "$PROJECT_ROOT/scripts/lib/ubuntu_upgrade.sh" ]]; then
        # shellcheck source=scripts/lib/ubuntu_upgrade.sh
        source "$PROJECT_ROOT/scripts/lib/ubuntu_upgrade.sh"
        return 0
    else
        echo "ERROR: Cannot find ubuntu_upgrade.sh" >&2
        return 1
    fi
}

# ============================================================
# Version Detection Tests
# ============================================================

test_version_number_conversion() {
    log_test "Version Number Conversion"

    # Test the version string to number conversion logic
    # The library uses pattern: major * 100 + minor
    # 24.04 -> 2404, 25.10 -> 2510

    # We test this by checking ubuntu_get_next_version_hardcoded which uses numeric codes
    local result

    # 2204 (22.04) should map to "24.04" as next version
    result=$(ubuntu_get_next_version_hardcoded 2204)
    if [[ "$result" == "24.04" ]]; then
        log_pass "Numeric code 2204 correctly handled"
    else
        log_fail "Expected 24.04 from 2204, got: $result"
    fi

    # 2404 (24.04) should map to "25.04" (skip 24.10, which may be EOL)
    result=$(ubuntu_get_next_version_hardcoded 2404)
    if [[ "$result" == "25.04" ]]; then
        log_pass "Numeric code 2404 correctly handled"
    else
        log_fail "Expected 25.04 from 2404, got: $result"
    fi

    # 2510 (25.10) should return empty (no next version)
    result=$(ubuntu_get_next_version_hardcoded 2510)
    if [[ -z "$result" ]]; then
        log_pass "Numeric code 2510 returns empty (end of chain)"
    else
        log_fail "Expected empty from 2510, got: $result"
    fi
}

test_version_number_parser_edge_cases() {
    log_test "Version Number Parser Edge Cases"

    local result=""

    result="$(
        ubuntu_get_version_string() { printf '%s\n' '24.04.1'; }
        ubuntu_get_version_number
    )"
    assert_equals "2404" "$result" "24.04.1 parses to 2404"

    if (
        ubuntu_get_version_string() { printf '%s\n' '24'; }
        ubuntu_get_version_number >/dev/null
    ); then
        log_fail "Bare major version should be rejected"
    else
        log_pass "Bare major version is rejected"
    fi

    if (
        ubuntu_get_version_string() { printf '%s\n' '24.04.beta'; }
        ubuntu_get_version_number >/dev/null
    ); then
        log_fail "Non-numeric patch suffix should be rejected"
    else
        log_pass "Non-numeric patch suffix is rejected"
    fi
}

test_version_comparison() {
    log_test "Version Comparison (ubuntu_version_gte)"

    # ubuntu_version_gte uses NUMERIC codes (e.g., 2510 for 25.10)

    # 2510 >= 2510 should be true (same version)
    if ubuntu_version_gte 2510 2510; then
        log_pass "2510 >= 2510 (same version)"
    else
        log_fail "2510 >= 2510 should be true"
    fi

    # 2510 >= 2404 should be true (25.10 > 24.04)
    if ubuntu_version_gte 2510 2404; then
        log_pass "2510 >= 2404 (25.10 > 24.04)"
    else
        log_fail "2510 >= 2404 should be true"
    fi

    # 2404 >= 2510 should be false (24.04 < 25.10)
    if ubuntu_version_gte 2404 2510; then
        log_fail "2404 >= 2510 should be false"
    else
        log_pass "2404 >= 2510 is false (24.04 < 25.10)"
    fi

    # 2410 >= 2404 should be true (24.10 > 24.04)
    if ubuntu_version_gte 2410 2404; then
        log_pass "2410 >= 2404 (24.10 > 24.04)"
    else
        log_fail "2410 >= 2404 should be true"
    fi
}

test_lts_detection() {
    log_test "LTS Version Detection"

    # 24.04 is LTS (even year + .04)
    if ubuntu_is_lts "24.04"; then
        log_pass "24.04 is LTS"
    else
        log_fail "24.04 should be LTS"
    fi

    # 22.04 is LTS
    if ubuntu_is_lts "22.04"; then
        log_pass "22.04 is LTS"
    else
        log_fail "22.04 should be LTS"
    fi

    # 24.10 is NOT LTS
    if ubuntu_is_lts "24.10"; then
        log_fail "24.10 should NOT be LTS"
    else
        log_pass "24.10 is not LTS"
    fi

    # 25.04 is NOT LTS (odd year)
    if ubuntu_is_lts "25.04"; then
        log_fail "25.04 should NOT be LTS (odd year)"
    else
        log_pass "25.04 is not LTS (odd year)"
    fi
}

# ============================================================
# Upgrade Path Calculation Tests
# ============================================================

test_upgrade_path_chain() {
    log_test "Upgrade Path Chain (via hardcoded function)"

    # Since ubuntu_calculate_upgrade_path requires /etc/os-release,
    # we test the upgrade chain logic via ubuntu_get_next_version_hardcoded

    local versions=()
    local current=2404  # Start at 24.04
    local target=2510   # Target 25.10

    # Build the path by following the chain
    while [[ $current -lt $target ]]; do
        local next
        next=$(ubuntu_get_next_version_hardcoded "$current")
        if [[ -z "$next" ]]; then
            break
        fi
        versions+=("$next")
        # Convert version string back to number
        local major="${next%%.*}"
        local minor="${next#*.}"
        current=$((major * 100 + minor))
    done

    # Check the path: should be 25.04, 25.10 (skip 24.10, which may be EOL)
    local path="${versions[*]}"
    if [[ "$path" == "25.04 25.10" ]]; then
        log_pass "Path from 24.04 to 25.10: 25.04 → 25.10"
    else
        log_fail "Expected '25.04 25.10', got: $path"
    fi
}

test_upgrade_path_lts_hop() {
    log_test "Upgrade Path: LTS hop (22.04 → 24.04)"

    # 22.04 should jump directly to 24.04 (LTS to LTS)
    local next
    next=$(ubuntu_get_next_version_hardcoded 2204)
    if [[ "$next" == "24.04" ]]; then
        log_pass "22.04 jumps to 24.04 (LTS hop)"
    else
        log_fail "Expected 22.04 → 24.04, got: $next"
    fi
}

test_upgrade_path_no_upgrade_needed() {
    log_test "Upgrade Path: 25.10 → 25.10 (no upgrade needed)"

    # 25.10 should have no next version
    local next
    next=$(ubuntu_get_next_version_hardcoded 2510)
    if [[ -z "$next" ]]; then
        log_pass "25.10 has no next version (end of chain)"
    else
        log_fail "Expected empty, got: $next"
    fi
}

test_next_version_hardcoded() {
    log_test "Hardcoded Next Version"

    local result

    result=$(ubuntu_get_next_version_hardcoded 2204)
    assert_equals "24.04" "$result" "22.04 → 24.04 (LTS hop)"

    result=$(ubuntu_get_next_version_hardcoded 2404)
    assert_equals "25.04" "$result" "24.04 → 25.04 (skip 24.10, which may be EOL)"

    result=$(ubuntu_get_next_version_hardcoded 2410)
    assert_equals "25.04" "$result" "24.10 → 25.04 (if on 24.10)"

    result=$(ubuntu_get_next_version_hardcoded 2504)
    assert_equals "25.10" "$result" "25.04 → 25.10"
}

test_upgrade_rehearsal_fixture_paths() {
    log_test "Upgrade Rehearsal Fixture Paths"

    local path=""
    local unsupported_output=""

    path="$(_calculate_path_for_version "22.04")"
    assert_equals "24.04 25.04 25.10" "$path" "22.04 rehearses LTS hop plus interim chain"

    path="$(_calculate_path_for_version "24.04")"
    assert_equals "25.04 25.10" "$path" "24.04 skips EOL 24.10 and reaches 25.10"

    path="$(_calculate_path_for_version "24.10")"
    assert_equals "25.04 25.10" "$path" "24.10 resumes through supported interim releases"

    path="$(_calculate_path_for_version "25.10")"
    assert_empty "$path" "25.10 already current has empty path"

    if unsupported_output="$(_calculate_path_for_version "23.10" 2>/dev/null)"; then
        log_fail "Unsupported 23.10 should not produce a path, got: ${unsupported_output:-<empty>}"
    else
        log_pass "Unsupported 23.10 fails closed"
    fi
}

test_upgrade_rehearsal_state_machine_multi_hop() {
    log_test "Upgrade Rehearsal State Machine Multi-Hop"

    if ! command -v jq >/dev/null 2>&1; then
        log_skip "jq required for state-machine rehearsal"
        return 0
    fi

    local test_dir=""
    local state_file=""
    test_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-upgrade-rehearsal.XXXXXX")"
    state_file="$test_dir/state.json"
    _write_base_state_fixture "$state_file"

    if (
        set -euo pipefail
        export ACFS_STATE_FILE="$state_file"
        # shellcheck source=scripts/lib/state.sh
        source "$PROJECT_ROOT/scripts/lib/state.sh"

        state_upgrade_init "22.04" "25.10" '["24.04","25.04","25.10"]'
        [[ "$(state_upgrade_get_next_version)" == "24.04" ]]

        state_upgrade_start "22.04" "24.04"
        jq -e '.ubuntu_upgrade.current_stage == "upgrading" and .ubuntu_upgrade.current_upgrade.to == "24.04"' "$state_file" >/dev/null
        state_upgrade_complete "24.04"
        state_upgrade_needs_reboot
        jq -e '.ubuntu_upgrade.current_stage == "awaiting_reboot" and .ubuntu_upgrade.needs_reboot == true and .ubuntu_upgrade.resume_after_reboot == true' "$state_file" >/dev/null

        state_upgrade_resumed
        [[ "$(state_upgrade_get_next_version)" == "25.04" ]]
        state_upgrade_start "24.04" "25.04"
        state_upgrade_complete "25.04"
        state_upgrade_needs_reboot

        state_upgrade_resumed
        [[ "$(state_upgrade_get_next_version)" == "25.10" ]]
        state_upgrade_start "25.04" "25.10"
        state_upgrade_complete "25.10"
        state_upgrade_is_complete

        state_upgrade_mark_complete
        jq -e '
          .ubuntu_upgrade.current_stage == "completed" and
          .ubuntu_upgrade.needs_reboot == false and
          .ubuntu_upgrade.resume_after_reboot == false and
          .ubuntu_upgrade.current_upgrade == null and
          (.ubuntu_upgrade.completed_upgrades | length) == 3
        ' "$state_file" >/dev/null
    ); then
        log_pass "Multi-hop state machine reaches terminal completed state"
    else
        log_fail "Multi-hop state machine rehearsal failed"
    fi
}

test_upgrade_rehearsal_reboot_marker_context() {
    log_test "Upgrade Rehearsal Reboot Marker Context"

    if ! command -v jq >/dev/null 2>&1; then
        log_skip "jq required for reboot marker rehearsal"
        return 0
    fi

    local test_dir=""
    local state_file=""
    local args_line=""

    test_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-upgrade-reboot-marker.XXXXXX")"
    state_file="$test_dir/pre/state.json"
    _write_upgrade_stage_fixture "$state_file" "pre_upgrade_reboot"
    if args_line="$(
        set -euo pipefail
        export ACFS_RESUME_DIR="$test_dir/pre/resume"
        export ACFS_STATE_FILE="$state_file"
        export ACFS_HOME="$test_dir/pre/home/.acfs"
        export TARGET_USER="alice"
        unset TARGET_HOME
        HOME="/root"
        ubuntu_lookup_passwd_home() { [[ "${1:-}" == "alice" ]] && printf '%s\n' "$test_dir/pre/home"; }
        ubuntu_resolve_current_user() { printf '%s\n' 'root'; }
        cp() {
            local destination="${*: -1}"
            [[ "$destination" == /etc/* ]] && return 0
            command cp "$@"
        }
        chmod() { command chmod "$@" 2>/dev/null || true; }
        systemctl() { :; }
        mkdir() {
            [[ "$*" == "-p /var/log/acfs" ]] && return 0
            command mkdir "$@"
        }
        upgrade_create_status_script() { :; }
        upgrade_setup_infrastructure "$PROJECT_ROOT" --yes --mode vibe >/dev/null
        # shellcheck disable=SC1091
        source "$ACFS_RESUME_DIR/continue_context.env"
        printf '%s\n' "${CONTINUE_INSTALL_ARGS[*]}"
    )"; then
        if [[ "$args_line" == "--yes --mode vibe" ]]; then
            log_pass "Pre-upgrade reboot marker keeps Ubuntu upgrade enabled after reboot"
        else
            log_fail "Pre-upgrade reboot marker produced unexpected args: $args_line"
        fi
    else
        log_fail "Pre-upgrade reboot marker rehearsal failed"
    fi

    state_file="$test_dir/awaiting/state.json"
    _write_upgrade_stage_fixture "$state_file" "awaiting_reboot"
    if args_line="$(
        set -euo pipefail
        export ACFS_RESUME_DIR="$test_dir/awaiting/resume"
        export ACFS_STATE_FILE="$state_file"
        export ACFS_HOME="$test_dir/awaiting/home/.acfs"
        export TARGET_USER="alice"
        unset TARGET_HOME
        HOME="/root"
        ubuntu_lookup_passwd_home() { [[ "${1:-}" == "alice" ]] && printf '%s\n' "$test_dir/awaiting/home"; }
        ubuntu_resolve_current_user() { printf '%s\n' 'root'; }
        cp() {
            local destination="${*: -1}"
            [[ "$destination" == /etc/* ]] && return 0
            command cp "$@"
        }
        chmod() { command chmod "$@" 2>/dev/null || true; }
        systemctl() { :; }
        mkdir() {
            [[ "$*" == "-p /var/log/acfs" ]] && return 0
            command mkdir "$@"
        }
        upgrade_create_status_script() { :; }
        upgrade_setup_infrastructure "$PROJECT_ROOT" --yes --mode vibe >/dev/null
        # shellcheck disable=SC1091
        source "$ACFS_RESUME_DIR/continue_context.env"
        printf '%s\n' "${CONTINUE_INSTALL_ARGS[*]}"
    )"; then
        if [[ "$args_line" == "--yes --mode vibe --skip-ubuntu-upgrade" ]]; then
            log_pass "Post-upgrade reboot marker skips repeat Ubuntu upgrade during continuation"
        else
            log_fail "Post-upgrade reboot marker produced unexpected args: $args_line"
        fi
    else
        log_fail "Post-upgrade reboot marker rehearsal failed"
    fi
}

# ============================================================
# Preflight Check Tests
# ============================================================

test_preflight_detects_docker() {
    log_test "Preflight: Docker Detection"

    # Create a mock /.dockerenv
    if [[ -f "/.dockerenv" ]]; then
        # We're actually in Docker!
        if ! ubuntu_check_not_docker 2>/dev/null; then
            log_pass "Docker environment correctly detected"
        else
            log_fail "Should have detected Docker environment"
        fi
    else
        # Not in Docker - test that it passes
        if ubuntu_check_not_docker 2>/dev/null; then
            log_pass "Non-Docker environment correctly detected"
        else
            log_fail "Should have passed Docker check when not in Docker"
        fi
    fi
}

test_preflight_disk_space_check() {
    log_test "Preflight: Disk Space Check"

    # This should pass on most systems with reasonable disk space
    if ubuntu_check_disk_space 2>/dev/null; then
        log_pass "Disk space check passed"
    else
        log_skip "Disk space check failed (may be low disk space)"
    fi
}


test_target_home_resolution_current_user_home_fallback() {
    log_test "Target Home Resolution: Current User HOME Fallback"

    local result=""
    if result="$(
        unset TARGET_HOME
        HOME="/srv/alice"
        ubuntu_lookup_passwd_home() { return 1; }
        ubuntu_resolve_current_user() { printf '%s\n' 'alice'; }
        ubuntu_resolve_target_home 'alice'
    )"; then
        assert_equals "/srv/alice" "$result" "current user HOME fallback works"
    else
        log_fail "current user HOME fallback should succeed"
    fi
}

test_target_home_resolution_rejects_missing_user_guess() {
    log_test "Target Home Resolution Rejects Guessed /home"

    if (
        unset TARGET_HOME
        HOME="/root"
        ubuntu_lookup_passwd_home() { return 1; }
        ubuntu_resolve_current_user() { printf '%s\n' 'root'; }
        ubuntu_resolve_target_home 'missinguser' >/dev/null
    ); then
        log_fail "missing user should not synthesize /home/missinguser"
    else
        log_pass "missing user does not synthesize /home/<user>"
    fi
}

test_target_home_resolution_accepts_explicit_new_user_home_for_root() {
    log_test "Target Home Resolution Accepts Explicit New User Home For Root"

    local result=""
    if result="$(
        TARGET_HOME="/srv/alice"
        HOME="/root"
        ubuntu_lookup_passwd_home() { return 1; }
        ubuntu_resolve_current_user() { printf '%s\n' 'root'; }
        ubuntu_resolve_target_home 'alice'
    )"; then
        assert_equals "/srv/alice" "$result" "root bootstrap explicit TARGET_HOME works before user creation"
    else
        log_fail "root bootstrap explicit TARGET_HOME should be accepted before user creation"
    fi
}

test_upgrade_setup_infrastructure_persists_resolved_target_home() {
    log_test "Resume Infrastructure Persists Resolved Target Home"

    local test_dir=""
    local result=""
    test_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-ubuntu-upgrade-test.XXXXXX")"

    if result="$(
        ACFS_RESUME_DIR="$test_dir/resume"
        TARGET_USER="alice"
        unset TARGET_HOME ACFS_HOME ACFS_STATE_FILE
        HOME="/root"
        ubuntu_lookup_passwd_home() {
            if [[ "${1:-}" == "alice" ]]; then
                printf '%s\n' '/srv/alice'
                return 0
            fi
            return 1
        }
        cp() { :; }
        chmod() { :; }
        systemctl() { :; }
        mkdir() {
            [[ "$*" == "-p /var/log/acfs" ]] && return 0
            command mkdir "$@"
        }
        state_get_file() { return 1; }
        upgrade_setup_infrastructure "$PROJECT_ROOT" --yes >/dev/null 2>&1 || exit 1
        # shellcheck disable=SC1090
        source "$ACFS_RESUME_DIR/continue_context.env"
        printf 'target=%s\nacfs=%s\nstate=%s\nhome=%s\n'             "$CONTINUE_TARGET_HOME" "$CONTINUE_ACFS_HOME" "$CONTINUE_ACFS_STATE_FILE" "$CONTINUE_HOME"
    )"; then
        if [[ "$result" == $'target=/srv/alice\nacfs=/srv/alice/.acfs\nstate=/srv/alice/.acfs/state.json\nhome=/srv/alice' ]]; then
            log_pass "resume context uses resolved target home"
        else
            log_fail "resume context uses resolved target home: unexpected output: $result"
        fi
    else
        log_fail "resume infrastructure should succeed with passwd-resolved target home"
    fi
}

test_upgrade_setup_infrastructure_persists_explicit_new_user_home_for_root() {
    log_test "Resume Infrastructure Persists Explicit New User Home For Root"

    local test_dir=""
    local result=""
    test_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-ubuntu-upgrade-test.XXXXXX")"

    if result="$(
        ACFS_RESUME_DIR="$test_dir/resume"
        TARGET_USER="alice"
        TARGET_HOME="/srv/alice"
        unset ACFS_HOME ACFS_STATE_FILE
        HOME="/root"
        ubuntu_lookup_passwd_home() { return 1; }
        ubuntu_resolve_current_user() { printf '%s\n' 'root'; }
        cp() { :; }
        chmod() { :; }
        systemctl() { :; }
        mkdir() {
            [[ "$*" == "-p /var/log/acfs" ]] && return 0
            command mkdir "$@"
        }
        state_get_file() { return 1; }
        upgrade_setup_infrastructure "$PROJECT_ROOT" --yes >/dev/null 2>&1 || exit 1
        # shellcheck disable=SC1090
        source "$ACFS_RESUME_DIR/continue_context.env"
        printf 'target=%s\nacfs=%s\nstate=%s\nhome=%s\n'             "$CONTINUE_TARGET_HOME" "$CONTINUE_ACFS_HOME" "$CONTINUE_ACFS_STATE_FILE" "$CONTINUE_HOME"
    )"; then
        if [[ "$result" == $'target=/srv/alice\nacfs=/srv/alice/.acfs\nstate=/srv/alice/.acfs/state.json\nhome=/srv/alice' ]]; then
            log_pass "resume context keeps explicit new-user target home"
        else
            log_fail "resume context keeps explicit new-user target home: unexpected output: $result"
        fi
    else
        log_fail "resume infrastructure should accept explicit new-user target home for root bootstrap"
    fi
}

test_upgrade_setup_infrastructure_rejects_unresolved_target_home() {
    log_test "Resume Infrastructure Rejects Unresolved Target Home"

    local test_dir=""
    test_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-ubuntu-upgrade-test.XXXXXX")"

    if (
        ACFS_RESUME_DIR="$test_dir/resume"
        TARGET_USER="missinguser"
        unset TARGET_HOME ACFS_HOME ACFS_STATE_FILE
        HOME="/root"
        ubuntu_lookup_passwd_home() { return 1; }
        ubuntu_resolve_current_user() { printf '%s\n' 'root'; }
        upgrade_setup_infrastructure "$PROJECT_ROOT" --yes >/dev/null 2>&1
    ); then
        log_fail "resume infrastructure should fail when target home cannot be resolved"
    elif [[ -e "$test_dir/resume/continue_context.env" ]] || [[ -e "$test_dir/resume/continue_install.sh" ]]; then
        log_fail "resume infrastructure should fail before writing continuation files"
    else
        log_pass "resume infrastructure fails closed when target home is unresolved"
    fi
}

test_upgrade_lock_rejects_contender_without_truncating_pid() {
    log_test "Upgrade Lock Rejects Contender Without Truncating PID"

    local test_dir=""
    local lockfile=""
    local first_pid=""
    local after_contender_pid=""
    test_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-ubuntu-upgrade-lock.XXXXXX")"
    lockfile="$test_dir/acfs-upgrade.lock"

    ACFS_UPGRADE_LOCK="$lockfile"
    ACFS_UPGRADE_LOCK_FD=""
    if ! upgrade_acquire_lock; then
        log_fail "first upgrade lock acquisition should succeed"
        return 1
    fi

    first_pid="$(cat "$lockfile" 2>/dev/null || true)"
    if [[ "$first_pid" == "$$" ]]; then
        log_pass "first lock writes holder PID"
    else
        log_fail "first lock PID mismatch: expected $$, got ${first_pid:-<empty>}"
    fi

    if bash -c '
        { exec 197>&-; } 2>/dev/null || true
        { exec 196>&-; } 2>/dev/null || true
        source "$1"
        ACFS_UPGRADE_LOCK="$2"
        ACFS_UPGRADE_LOCK_FD=""
        upgrade_acquire_lock
    ' _ "$PROJECT_ROOT/scripts/lib/ubuntu_upgrade.sh" "$lockfile" >"$test_dir/contender.out" 2>&1; then
        log_fail "contending lock acquisition should fail"
    else
        log_pass "contending lock acquisition fails"
    fi

    after_contender_pid="$(cat "$lockfile" 2>/dev/null || true)"
    assert_equals "$first_pid" "$after_contender_pid" "contender does not truncate holder PID"

    upgrade_release_lock

    if bash -c '
        source "$1"
        ACFS_UPGRADE_LOCK="$2"
        ACFS_UPGRADE_LOCK_FD=""
        upgrade_acquire_lock
        upgrade_release_lock
    ' _ "$PROJECT_ROOT/scripts/lib/ubuntu_upgrade.sh" "$lockfile" >"$test_dir/reacquire.out" 2>&1; then
        log_pass "lock can be reacquired after release"
    else
        log_fail "lock should be reacquirable after release"
    fi

    ACFS_UPGRADE_LOCK="$lockfile"
    ACFS_UPGRADE_LOCK_FD=197
    _ACFS_UPGRADE_LOCK_FILE="${lockfile}.old"
    if upgrade_acquire_lock; then
        log_pass "stale descriptor metadata is ignored"
        upgrade_release_lock
    else
        log_fail "stale descriptor metadata should not block reacquisition"
    fi
}

test_retry_with_backoff_is_argv_only_and_skips_terminal_sleep() {
    log_test "Upgrade Retry Uses Argv and Skips Terminal Sleep"

    local attempts=0
    local injected=0
    local original_system_binary_path=""
    local -a observed_delays=()
    original_system_binary_path="$(declare -f ubuntu_system_binary_path)"

    retry_failure_probe() {
        attempts=$((attempts + 1))
        return 1
    }
    retry_injected_probe() {
        injected=1
        return 0
    }
    ubuntu_system_binary_path() {
        [[ "${1:-}" == "sleep" ]] || return 1
        printf '%s\n' "retry_sleep_probe"
    }
    retry_sleep_probe() {
        observed_delays+=("${1:-}")
    }

    if ubuntu_retry_with_backoff 3 1 -- retry_failure_probe >/dev/null 2>&1; then
        log_fail "permanently failing retry probe should fail"
    elif [[ $attempts -ne 3 ]]; then
        log_fail "retry probe ran $attempts times instead of 3"
    elif [[ "${observed_delays[*]}" != "1 2" ]]; then
        log_fail "retry delays were '${observed_delays[*]}' instead of '1 2'"
    else
        log_pass "retry performs exact attempts without a terminal sleep"
    fi

    attempts=0
    observed_delays=()
    if ubuntu_retry_with_backoff ':; retry_injected_probe' 1 0 >/dev/null 2>&1; then
        log_fail "string-form retry command should not be evaluated"
    elif [[ $injected -ne 0 ]]; then
        log_fail "string-form retry command executed injected shell syntax"
    else
        log_pass "retry treats command input as argv without shell evaluation"
    fi

    attempts=0
    if ubuntu_retry_with_backoff 0 0 -- retry_failure_probe >/dev/null 2>&1; then
        log_fail "retry should reject a zero-attempt configuration"
    elif [[ $attempts -ne 0 ]]; then
        log_fail "invalid zero-attempt configuration still executed the command"
    else
        log_pass "retry rejects a zero-attempt configuration before execution"
    fi

    unset -f retry_failure_probe retry_injected_probe retry_sleep_probe ubuntu_system_binary_path
    eval "$original_system_binary_path"
}

# ============================================================
# State Function Tests
# ============================================================

test_state_upgrade_functions_exist() {
    log_test "State Upgrade Functions Exist"

    # Source state.sh for upgrade functions
    if [[ -f "$PROJECT_ROOT/scripts/lib/state.sh" ]]; then
        # shellcheck source=scripts/lib/state.sh
        source "$PROJECT_ROOT/scripts/lib/state.sh"
    fi

    local missing=()

    type -t state_upgrade_init &>/dev/null || missing+=("state_upgrade_init")
    type -t state_upgrade_start &>/dev/null || missing+=("state_upgrade_start")
    type -t state_upgrade_complete &>/dev/null || missing+=("state_upgrade_complete")
    type -t state_upgrade_needs_reboot &>/dev/null || missing+=("state_upgrade_needs_reboot")
    type -t state_upgrade_resumed &>/dev/null || missing+=("state_upgrade_resumed")
    type -t state_upgrade_is_complete &>/dev/null || missing+=("state_upgrade_is_complete")
    type -t state_upgrade_get_stage &>/dev/null || missing+=("state_upgrade_get_stage")
    type -t state_upgrade_set_error &>/dev/null || missing+=("state_upgrade_set_error")

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_pass "All state upgrade functions exist"
    else
        log_fail "Missing functions: ${missing[*]}"
    fi
}

# ============================================================
# JSON Helper Tests
# ============================================================

test_json_escape() {
    log_test "JSON Escape Function"

    # Source context.sh which has _json_escape
    if [[ -f "$PROJECT_ROOT/scripts/lib/context.sh" ]]; then
        # shellcheck source=scripts/lib/context.sh
        source "$PROJECT_ROOT/scripts/lib/context.sh"
    fi

    if type -t _json_escape &>/dev/null; then
        local result

        # Test quote escaping
        result=$(_json_escape 'test "quoted" string')
        if [[ "$result" == 'test \"quoted\" string' ]]; then
            log_pass "Quote escaping works"
        else
            log_fail "Quote escaping failed: $result"
        fi

        # Test newline escaping
        result=$(_json_escape $'line1\nline2')
        if [[ "$result" == 'line1\nline2' ]]; then
            log_pass "Newline escaping works"
        else
            log_fail "Newline escaping failed: $result"
        fi
    else
        log_skip "_json_escape function not found"
    fi
}

# ============================================================
# Test Runner
# ============================================================

run_all_tests() {
    echo ""
    echo "=============================================="
    echo "  ACFS Ubuntu Upgrade Unit Tests"
    echo "=============================================="
    echo ""

    # Source the library
    if ! source_upgrade_lib; then
        echo "FATAL: Cannot load ubuntu_upgrade.sh"
        exit 1
    fi

    # Run test suites
    echo "--- Version Detection Tests ---"
    test_version_number_conversion || true
    test_version_number_parser_edge_cases || true
    test_version_comparison || true
    test_lts_detection || true
    echo ""

    echo "--- Upgrade Path Tests ---"
    test_upgrade_path_chain || true
    test_upgrade_path_lts_hop || true
    test_upgrade_path_no_upgrade_needed || true
    test_next_version_hardcoded || true
    test_upgrade_rehearsal_fixture_paths || true
    test_upgrade_rehearsal_state_machine_multi_hop || true
    test_upgrade_rehearsal_reboot_marker_context || true
    echo ""

    echo "--- Preflight Check Tests ---"
    test_preflight_detects_docker || true
    test_preflight_disk_space_check || true
    echo ""

    echo "--- Target Home Resolution Tests ---"
    test_target_home_resolution_current_user_home_fallback || true
    test_target_home_resolution_rejects_missing_user_guess || true
    test_target_home_resolution_accepts_explicit_new_user_home_for_root || true
    test_upgrade_setup_infrastructure_persists_resolved_target_home || true
    test_upgrade_setup_infrastructure_persists_explicit_new_user_home_for_root || true
    test_upgrade_setup_infrastructure_rejects_unresolved_target_home || true
    echo ""

    echo "--- Upgrade Lock Tests ---"
    test_upgrade_lock_rejects_contender_without_truncating_pid || true
    echo ""

    echo "--- Retry Tests ---"
    test_retry_with_backoff_is_argv_only_and_skips_terminal_sleep || true
    echo ""

    echo "--- State Function Tests ---"
    test_state_upgrade_functions_exist || true
    echo ""

    echo "--- JSON Helper Tests ---"
    test_json_escape || true
    echo ""

    # Summary
    echo "=============================================="
    echo "  Test Summary"
    echo "=============================================="
    echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo "=============================================="
    echo ""

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
