#!/usr/bin/env bash
# ============================================================
# Unit tests for scripts/lib/doctor_fix.sh
#
# Tests each fixer function in both normal and dry-run modes.
# Validates guard conditions, change recording, and undo support.
#
# Run with: bash tests/unit/test_doctor_fix.sh
# ============================================================

set -uo pipefail

# Get the absolute path to the scripts directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Set SCRIPT_DIR for the libraries to find each other
export SCRIPT_DIR="$REPO_ROOT/scripts/lib"

# Source autofix first, then doctor_fix
source "$REPO_ROOT/scripts/lib/autofix.sh"
source "$REPO_ROOT/scripts/lib/doctor_fix.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================
# Test Helpers
# ============================================================

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
}

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    echo "Running: $test_name..."
    if "$test_name"; then
        test_pass "$test_name"
    else
        test_fail "$test_name"
    fi
}

# Setup test environment
setup_test_env() {
    local test_id="${FUNCNAME[1]:-$$}_$(date +%s%N)"

    autofix_release_session_lock 2>/dev/null || true
    ACFS_SESSION_ID=""
    unset -f record_change 2>/dev/null || true
    unset -f sudo 2>/dev/null || true
    unset -f systemctl 2>/dev/null || true
    unset -f sshd 2>/dev/null || true
    unset -f git 2>/dev/null || true
    unset -f cp 2>/dev/null || true
    unset -f ln 2>/dev/null || true
    unset -f uname 2>/dev/null || true
    unset -f getent 2>/dev/null || true
    unset -f id 2>/dev/null || true
    unset -f whoami 2>/dev/null || true
    unset -f doctor_fix_run_verified_installer 2>/dev/null || true
    unset -f doctor_fix_system_curl 2>/dev/null || true
    unset _ACFS_AUTOFIX_SOURCED
    unset _ACFS_DOCTOR_FIX_LOADED
    # shellcheck source=../../scripts/lib/autofix.sh
    source "$REPO_ROOT/scripts/lib/autofix.sh"
    # shellcheck source=../../scripts/lib/doctor_fix.sh
    source "$REPO_ROOT/scripts/lib/doctor_fix.sh"

    # Autofix state
    export ACFS_STATE_DIR="/tmp/test_doctor_fix_${test_id}"
    export ACFS_CHANGES_FILE="$ACFS_STATE_DIR/changes.jsonl"
    export ACFS_UNDOS_FILE="$ACFS_STATE_DIR/undos.jsonl"
    export ACFS_BACKUPS_DIR="$ACFS_STATE_DIR/backups"
    export ACFS_LOCK_FILE="$ACFS_STATE_DIR/.lock"
    export ACFS_INTEGRITY_FILE="$ACFS_STATE_DIR/.integrity"

    # Doctor fix state
    export DOCTOR_FIX_LOG="$ACFS_STATE_DIR/doctor.log"
    export DOCTOR_FIX_DRY_RUN=false
    export DOCTOR_FIX_YES=false
    export DOCTOR_FIX_PROMPT=false
    export DOCTOR_FIX_SECURITY_READY=false

    # Reset counters
    FIX_APPLIED=0
    FIX_SKIPPED=0
    FIX_FAILED=0
    FIX_MANUAL=0
    FIXES_APPLIED=()
    FIXES_DRY_RUN=()
    FIXES_MANUAL=()
    FIXES_PROMPTED=()

    # Reset autofix state
    ACFS_CHANGE_RECORDS=()
    ACFS_CHANGE_ORDER=()
    ACFS_AUTOFIX_INITIALIZED=false

    # Create test directories
    rm -rf "$ACFS_STATE_DIR"
    mkdir -p "$ACFS_STATE_DIR"
    mkdir -p "$ACFS_BACKUPS_DIR"

    # Create empty files
    : > "$ACFS_CHANGES_FILE"
    : > "$ACFS_UNDOS_FILE"

    # Test home directory simulation
    export TEST_HOME="$ACFS_STATE_DIR/home"
    mkdir -p "$TEST_HOME/.acfs/zsh"
    mkdir -p "$TEST_HOME/.local/bin"
    mkdir -p "$TEST_HOME/.cargo/bin"
    mkdir -p "$TEST_HOME/.config/claude-code"

    # Save original HOME and override
    export ORIGINAL_HOME="$HOME"
    export ORIGINAL_PATH="$PATH"
    export HOME="$TEST_HOME"
    unset TARGET_USER
    export TARGET_HOME="$TEST_HOME"
    export ACFS_HOME="$TEST_HOME/.acfs"
    export ACFS_BIN_DIR="$TEST_HOME/.local/bin"
    unset DOCTOR_FIX_SSHD_CONFIG
}

# Cleanup test environment
cleanup_test_env() {
    autofix_release_session_lock 2>/dev/null || true
    ACFS_SESSION_ID=""
    unset -f record_change 2>/dev/null || true
    unset -f sudo 2>/dev/null || true
    unset -f systemctl 2>/dev/null || true
    unset -f sshd 2>/dev/null || true
    unset -f git 2>/dev/null || true
    unset -f cp 2>/dev/null || true
    unset -f ln 2>/dev/null || true
    unset -f uname 2>/dev/null || true
    unset -f getent 2>/dev/null || true
    unset -f id 2>/dev/null || true
    unset -f whoami 2>/dev/null || true
    unset -f doctor_fix_run_verified_installer 2>/dev/null || true
    unset -f doctor_fix_system_curl 2>/dev/null || true

    # Restore HOME
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    unset TARGET_USER
    unset TARGET_HOME
    unset ACFS_HOME
    unset ACFS_BIN_DIR
    unset DOCTOR_FIX_SSHD_CONFIG
    rm -rf "/tmp/test_doctor_fix_"* 2>/dev/null || true
}

stub_doctor_fix_agent_mail_health_ready() {
    doctor_fix_system_curl() {
        case "$*" in
            *"/health/liveness"*)
                return 0
                ;;
            *"/health"*)
                printf '%s\n' '{"status":"ready"}'
                ;;
            *)
                return 1
                ;;
        esac
    }
}

test_doctor_fix_prefers_target_home_for_autofix_state() {
    local temp_root=""
    temp_root="$(mktemp -d)"

    local root_home="$temp_root/root-home"
    local target_home="$temp_root/target-home"
    local installed_lib="$target_home/.acfs/scripts/lib"
    mkdir -p "$root_home" "$installed_lib"

    cp "$REPO_ROOT/scripts/lib/doctor_fix.sh" "$installed_lib/doctor_fix.sh"
    cp "$REPO_ROOT/scripts/lib/autofix.sh" "$installed_lib/autofix.sh"

    local state_dir=""
    state_dir=$(env -u SCRIPT_DIR \
        -u ACFS_STATE_DIR \
        -u ACFS_CHANGES_FILE \
        -u ACFS_UNDOS_FILE \
        -u ACFS_BACKUPS_DIR \
        -u ACFS_LOCK_FILE \
        -u ACFS_INTEGRITY_FILE \
        HOME="$root_home" \
        TARGET_HOME="$target_home" \
        bash -lc 'source "$1"; printf "%s\n" "${ACFS_STATE_DIR:-unset}"' _ \
        "$installed_lib/doctor_fix.sh")

    if [[ "$state_dir" != "$target_home/.acfs/autofix" ]]; then
        echo "  Expected ACFS_STATE_DIR=$target_home/.acfs/autofix, got $state_dir"
        rm -rf "$temp_root"
        return 1
    fi

    rm -rf "$temp_root"
    return 0
}

test_doctor_fix_prefers_target_home_over_poisoned_acfs_home() {
    local temp_root=""
    temp_root="$(mktemp -d)"

    local root_home="$temp_root/root-home"
    local target_home="$temp_root/target-home"
    local poisoned_acfs_home="$temp_root/poisoned/.acfs"
    local installed_lib="$target_home/.acfs/scripts/lib"
    mkdir -p "$root_home" "$poisoned_acfs_home" "$installed_lib"

    cp "$REPO_ROOT/scripts/lib/doctor_fix.sh" "$installed_lib/doctor_fix.sh"
    cp "$REPO_ROOT/scripts/lib/autofix.sh" "$installed_lib/autofix.sh"

    local output=""
    output=$(env -u SCRIPT_DIR         -u ACFS_STATE_DIR         -u ACFS_CHANGES_FILE         -u ACFS_UNDOS_FILE         -u ACFS_BACKUPS_DIR         -u ACFS_LOCK_FILE         -u ACFS_INTEGRITY_FILE         HOME="$root_home"         TARGET_HOME="$target_home"         ACFS_HOME="$poisoned_acfs_home"         bash -lc 'source "$1"; printf "%s\n%s\n" "${ACFS_STATE_DIR:-unset}" "$(doctor_fix_runtime_acfs_home)"' _         "$installed_lib/doctor_fix.sh")

    local expected_state_dir="$target_home/.acfs/autofix"
    local expected_acfs_home="$target_home/.acfs"
    local actual_state_dir=""
    local actual_acfs_home=""
    actual_state_dir="$(printf '%s\n' "$output" | sed -n '1p')"
    actual_acfs_home="$(printf '%s\n' "$output" | sed -n '2p')"

    if [[ "$actual_state_dir" != "$expected_state_dir" ]]; then
        echo "  Expected ACFS_STATE_DIR=$expected_state_dir, got $actual_state_dir"
        rm -rf "$temp_root"
        return 1
    fi

    if [[ "$actual_acfs_home" != "$expected_acfs_home" ]]; then
        echo "  Expected doctor_fix_runtime_acfs_home=$expected_acfs_home, got $actual_acfs_home"
        rm -rf "$temp_root"
        return 1
    fi

    rm -rf "$temp_root"
    return 0
}

test_doctor_fix_binary_path_ignores_relative_bin_dir() {
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin"
    cat > "$TARGET_HOME/.local/bin/example-tool" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TARGET_HOME/.local/bin/example-tool"
    export ACFS_BIN_DIR="relative/bin"

    local resolved=""
    resolved="$(doctor_fix_binary_path example-tool)"

    if [[ "$resolved" != "$TARGET_HOME/.local/bin/example-tool" ]]; then
        echo "  Expected sanitized fallback bin path, got $resolved"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_doctor_fix_runtime_path_ignores_relative_bin_dir() {
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin"
    export ACFS_BIN_DIR="relative/bin"

    local runtime_path=""
    runtime_path="$(doctor_fix_runtime_path)"

    if [[ "$runtime_path" != "$TARGET_HOME/.local/bin:"* ]]; then
        echo "  Expected runtime PATH to start with sanitized target bin dir, got $runtime_path"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_doctor_fix_runtime_path_prefers_system_bins_over_current_shell_path() {
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    local fake_bin="$ACFS_STATE_DIR/fake-bin"
    mkdir -p "$TARGET_HOME/.local/bin" "$fake_bin"
    export PATH="$fake_bin:/usr/bin:/bin"

    local runtime_path=""
    runtime_path="$(doctor_fix_runtime_path)"

    if [[ "$runtime_path" != *":/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$fake_bin:/usr/bin:/bin" ]]; then
        echo "  Expected runtime PATH to place trusted system dirs before inherited PATH, got $runtime_path"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_doctor_fix_runtime_home_ignores_relative_home() {
    setup_test_env

    unset TARGET_HOME
    export HOME="relative-home"

    local resolved_home=""
    resolved_home="$(doctor_fix_runtime_home)"

    if [[ "$resolved_home" == /* ]] && [[ "$resolved_home" != "/" ]] && [[ "$resolved_home" != "relative-home" ]]; then
        cleanup_test_env
        return 0
    fi

    echo "  Expected absolute non-root runtime home, got $resolved_home"
    cleanup_test_env
    return 1
}

test_doctor_fix_runtime_home_fails_closed_for_different_unresolved_target() {
    setup_test_env

    local current_home="$ACFS_STATE_DIR/current-home"
    mkdir -p "$current_home"

    export HOME="$current_home"
    export TARGET_USER="missinguser"
    export TARGET_HOME="/"

    getent() {
        return 2
    }

    id() {
        if [[ "$1" == "-un" ]]; then
            printf 'tester\n'
            return 0
        fi
        command id "$@"
    }

    whoami() {
        printf 'tester\n'
    }

    local resolved_home=""
    resolved_home="$(doctor_fix_runtime_home 2>/dev/null || true)"

    if [[ -z "$resolved_home" ]]; then
        cleanup_test_env
        return 0
    fi

    echo "  Expected runtime home resolution to fail closed, got $resolved_home"
    cleanup_test_env
    return 1
}

test_doctor_fix_runtime_home_prefers_target_user_passwd_home_over_stale_target_home() {
    setup_test_env

    local stale_home="$ACFS_STATE_DIR/stale-home"
    local passwd_home="$ACFS_STATE_DIR/passwd-home"
    mkdir -p "$stale_home" "$passwd_home"

    export TARGET_USER="targetuser"
    export TARGET_HOME="$stale_home"
    export HOME="$stale_home"
    export TEST_DOCTOR_FIX_PASSWD_HOME="$passwd_home"

    doctor_fix_current_user() {
        printf 'calleruser\n'
    }

    doctor_fix_resolve_home_for_user() {
        if [[ "${1:-}" == "targetuser" ]]; then
            printf '%s\n' "$TEST_DOCTOR_FIX_PASSWD_HOME"
            return 0
        fi
        return 1
    }

    local resolved_home=""
    resolved_home="$(doctor_fix_runtime_home 2>/dev/null || true)"

    if [[ "$resolved_home" == "$passwd_home" ]]; then
        unset TEST_DOCTOR_FIX_PASSWD_HOME
        cleanup_test_env
        return 0
    fi

    echo "  Expected target user's passwd home $passwd_home, got $resolved_home"
    unset TEST_DOCTOR_FIX_PASSWD_HOME
    cleanup_test_env
    return 1
}

test_doctor_fix_runtime_home_rejects_invalid_target_user_before_target_home() {
    setup_test_env

    local target_home="$ACFS_STATE_DIR/target-home"
    mkdir -p "$target_home"

    export TARGET_USER="bad/user"
    export TARGET_HOME="$target_home"

    local resolved_home=""
    resolved_home="$(doctor_fix_runtime_home 2>/dev/null || true)"

    if [[ -z "$resolved_home" ]]; then
        cleanup_test_env
        return 0
    fi

    echo "  Expected invalid TARGET_USER to fail closed, got $resolved_home"
    cleanup_test_env
    return 1
}

test_doctor_fix_runtime_home_fails_closed_for_unresolved_target_with_stale_target_home() {
    setup_test_env

    local stale_home="$ACFS_STATE_DIR/stale-home"
    mkdir -p "$stale_home"

    export TARGET_USER="missinguser"
    export TARGET_HOME="$stale_home"
    export HOME="$stale_home"

    doctor_fix_current_user() {
        printf 'calleruser\n'
    }

    doctor_fix_resolve_home_for_user() {
        return 1
    }

    local resolved_home=""
    resolved_home="$(doctor_fix_runtime_home 2>/dev/null || true)"

    if [[ -z "$resolved_home" ]]; then
        cleanup_test_env
        return 0
    fi

    echo "  Expected unresolved different TARGET_USER to fail closed, got $resolved_home"
    cleanup_test_env
    return 1
}

test_doctor_fix_runtime_bin_dir_ignores_other_user_bin_dir() {
    setup_test_env

    local current_home="$ACFS_STATE_DIR/current-home"
    local target_home="$ACFS_STATE_DIR/target-home"
    mkdir -p "$current_home/.local/bin" "$target_home/.local/bin"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    export ACFS_BIN_DIR="$current_home/.local/bin"

    local resolved_bin=""
    resolved_bin="$(doctor_fix_runtime_bin_dir)"

    if [[ "$resolved_bin" == "$target_home/.local/bin" ]]; then
        cleanup_test_env
        return 0
    fi

    echo "  Expected runtime bin dir to ignore stale other-user ACFS_BIN_DIR, got $resolved_bin"
    cleanup_test_env
    return 1
}

test_doctor_fix_binary_path_ignores_other_user_bin_dir() {
    setup_test_env

    local current_home="$ACFS_STATE_DIR/current-home"
    local target_home="$ACFS_STATE_DIR/target-home"
    local tool_name="example-tool"
    mkdir -p "$current_home/.local/bin" "$target_home/.local/bin"

    cat > "$current_home/.local/bin/$tool_name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$target_home/.local/bin/$tool_name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$current_home/.local/bin/$tool_name" "$target_home/.local/bin/$tool_name"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    export ACFS_BIN_DIR="$current_home/.local/bin"

    local resolved=""
    resolved="$(doctor_fix_binary_path "$tool_name")"

    if [[ "$resolved" == "$target_home/.local/bin/$tool_name" ]]; then
        cleanup_test_env
        return 0
    fi

    echo "  Expected binary lookup to ignore stale other-user ACFS_BIN_DIR, got $resolved"
    cleanup_test_env
    return 1
}

test_doctor_fix_run_rollback_command_uses_system_bash_and_clean_path() {
    local temp_dir=""
    local temp_bin=""
    local marker=""
    local poison_marker=""
    local old_path=""
    local status=0

    temp_dir="$(mktemp -d)"
    temp_bin="$temp_dir/bin"
    marker="$temp_dir/rollback-ran"
    poison_marker="$temp_dir/poison-ran"
    mkdir -p "$temp_bin"

    cat > "$temp_bin/bash" <<EOF
#!/bin/sh
: > "$poison_marker"
exit 99
EOF
    chmod +x "$temp_bin/bash"

    cat > "$temp_bin/dirname" <<EOF
#!/bin/sh
: > "$poison_marker"
exit 99
EOF
    chmod +x "$temp_bin/dirname"

    doctor_fix_log() {
        :
    }

    old_path="$PATH"
    PATH="$temp_bin"
    doctor_fix_run_rollback_command "dirname /tmp/example > '$marker'" false >/dev/null 2>&1
    status=$?
    PATH="$old_path"

    if [[ $status -ne 0 ]]; then
        echo "  Expected rollback to run with resolved system bash and sanitized PATH"
        return 1
    fi
    if [[ -e "$poison_marker" ]]; then
        echo "  Rollback used PATH-controlled bash or rollback utility"
        return 1
    fi
    if [[ "$(cat "$marker" 2>/dev/null)" != "/tmp" ]]; then
        echo "  Rollback command did not run through the expected system utilities"
        return 1
    fi

    return 0
}

test_doctor_fix_run_rollback_command_requires_root_fails_without_sudo() {
    local temp_dir=""
    local original_resolver=""
    local resolved_bash_bin=""
    local resolved_env_bin=""
    local marker=""
    local status=0

    if [[ $EUID -eq 0 ]]; then
        return 0
    fi

    original_resolver="$(declare -f doctor_fix_system_binary_path)"
    resolved_bash_bin="$(doctor_fix_system_binary_path bash 2>/dev/null || true)"
    resolved_env_bin="$(doctor_fix_system_binary_path env 2>/dev/null || true)"
    [[ -n "$resolved_bash_bin" && -n "$resolved_env_bin" ]] || return 1
    temp_dir="$(mktemp -d)"
    marker="$temp_dir/rollback-ran"

    doctor_fix_log() {
        :
    }

    doctor_fix_system_binary_path() {
        case "${1:-}" in
            bash) printf '%s\n' "$resolved_bash_bin" ;;
            env) printf '%s\n' "$resolved_env_bin" ;;
            sudo) return 1 ;;
            *) return 1 ;;
        esac
    }

    doctor_fix_run_rollback_command "printf ran > '$marker'" true >/dev/null 2>&1
    status=$?
    eval "$original_resolver"

    if [[ $status -eq 0 ]]; then
        echo "  Expected root-required rollback to fail without sudo"
        return 1
    fi
    if [[ -e "$marker" ]]; then
        echo "  Rollback command ran without required root privileges"
        return 1
    fi

    return 0
}

test_doctor_fix_run_rollback_command_uses_noninteractive_sudo() {
    local temp_dir=""
    local temp_bin=""
    local original_resolver=""
    local resolved_bash_bin=""
    local resolved_env_bin=""
    local marker=""
    local sudo_log=""
    local sudo_args=""
    local expected_prefix=""
    local status=0

    if [[ $EUID -eq 0 ]]; then
        return 0
    fi

    temp_dir="$(mktemp -d)"
    temp_bin="$temp_dir/bin"
    marker="$temp_dir/rollback-ran"
    sudo_log="$temp_dir/sudo-args"
    mkdir -p "$temp_bin"

    original_resolver="$(declare -f doctor_fix_system_binary_path)"
    resolved_bash_bin="$(doctor_fix_system_binary_path bash 2>/dev/null || true)"
    resolved_env_bin="$(doctor_fix_system_binary_path env 2>/dev/null || true)"
    [[ -n "$resolved_bash_bin" && -n "$resolved_env_bin" ]] || return 1

    cat > "$temp_bin/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$ACFS_FAKE_SUDO_LOG"
if [ "${1:-}" != "-n" ]; then
    exit 42
fi
shift
exec "$@"
EOF
    chmod +x "$temp_bin/sudo"

    doctor_fix_log() {
        :
    }

    doctor_fix_system_binary_path() {
        case "${1:-}" in
            bash) printf '%s\n' "$resolved_bash_bin" ;;
            env) printf '%s\n' "$resolved_env_bin" ;;
            sudo) printf '%s\n' "$temp_bin/sudo" ;;
            *) return 1 ;;
        esac
    }

    export ACFS_FAKE_SUDO_LOG="$sudo_log"
    doctor_fix_run_rollback_command "printf ran > '$marker'" true >/dev/null 2>&1
    status=$?
    unset ACFS_FAKE_SUDO_LOG
    eval "$original_resolver"

    if [[ $status -ne 0 ]]; then
        echo "  Expected root-required rollback to run through noninteractive sudo"
        return 1
    fi
    if [[ ! -e "$marker" ]]; then
        echo "  Rollback command did not run through fake sudo"
        return 1
    fi
    sudo_args="$(<"$sudo_log")"
    expected_prefix="-n $resolved_env_bin"
    expected_prefix+=" -u BASH_ENV -u ENV -u SHELLOPTS -u BASHOPTS"
    expected_prefix+=" -u CDPATH -u GLOBIGNORE"
    expected_prefix+=" PATH=/usr/sbin:/usr/bin:/sbin:/bin"
    expected_prefix+=" $resolved_bash_bin --noprofile --norc -p -c "
    if [[ "$sudo_args" != "$expected_prefix"* ]]; then
        echo "  Expected sudo to use sanitized noninteractive rollback, got: $sudo_args"
        return 1
    fi

    return 0
}

test_doctor_fix_files_json_escapes_special_paths() {
    local tricky_path='/tmp/acfs "quoted" path\bin'
    local files_json=""
    local decoded=""

    files_json="$(doctor_fix_files_json "$tricky_path")" || {
        echo "  doctor_fix_files_json should encode valid path arguments"
        return 1
    }

    decoded="$(printf '%s' "$files_json" | jq -r '.[0]' 2>/dev/null)" || {
        echo "  Encoded affected-files JSON was not parseable"
        return 1
    }

    if [[ "$decoded" != "$tricky_path" ]]; then
        echo "  Encoded affected-files JSON did not round-trip special path characters"
        return 1
    fi

    return 0
}

# ============================================================
# Test: file_contains_line helper
# ============================================================

test_file_contains_line() {
    setup_test_env

    local test_file="$TEST_HOME/test_contains.txt"
    echo "line one" > "$test_file"
    echo "line two" >> "$test_file"
    echo "specific marker text" >> "$test_file"

    # Test positive match
    if ! file_contains_line "$test_file" "specific marker"; then
        echo "  Should find 'specific marker'"
        cleanup_test_env
        return 1
    fi

    # Test negative match
    if file_contains_line "$test_file" "not in file"; then
        echo "  Should not find 'not in file'"
        cleanup_test_env
        return 1
    fi

    # Test missing file
    if file_contains_line "/nonexistent/file" "pattern"; then
        echo "  Should return false for missing file"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# ============================================================
# Test: fix_path_ordering
# ============================================================

test_fix_path_ordering_applies() {
    setup_test_env

    # Create empty .zshrc
    local zshrc="$HOME/.zshrc"
    echo "# Initial zshrc" > "$zshrc"

    # Initialize autofix session
    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    # Run fixer
    fix_path_ordering "path.ordering" >/dev/null 2>&1

    # Verify marker was added
    if ! grep -q "# ACFS PATH ordering" "$zshrc"; then
        echo "  Marker not found in .zshrc"
        cat "$zshrc"
        cleanup_test_env
        return 1
    fi

    # Verify PATH export was added
    if ! grep -q 'export PATH=' "$zshrc"; then
        echo "  PATH export not found in .zshrc"
        cleanup_test_env
        return 1
    fi

    # Verify counter incremented
    if [[ $FIX_APPLIED -ne 1 ]]; then
        echo "  FIX_APPLIED should be 1, got $FIX_APPLIED"
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null
    cleanup_test_env
    return 0
}

test_fix_path_ordering_idempotent() {
    setup_test_env

    # Create .zshrc with marker already present
    local zshrc="$HOME/.zshrc"
    echo "# Initial zshrc" > "$zshrc"
    echo "" >> "$zshrc"
    echo "# ACFS PATH ordering (added by doctor --fix)" >> "$zshrc"
    echo 'export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/go/bin:$HOME/.atuin/bin:$PATH"' >> "$zshrc"

    local initial_lines
    initial_lines=$(wc -l < "$zshrc")

    # Run fixer
    fix_path_ordering "path.ordering" >/dev/null 2>&1

    # Verify file not modified
    local final_lines
    final_lines=$(wc -l < "$zshrc")

    if [[ $initial_lines -ne $final_lines ]]; then
        echo "  File was modified when it shouldn't have been"
        echo "  Initial lines: $initial_lines, Final lines: $final_lines"
        cleanup_test_env
        return 1
    fi

    # Counter should not increment for no-op
    if [[ $FIX_APPLIED -ne 0 ]]; then
        echo "  FIX_APPLIED should be 0 for idempotent run, got $FIX_APPLIED"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_path_ordering_repairs_stale_marker_missing_atuin() {
    setup_test_env

    local zshrc="$HOME/.zshrc"
    echo "# Initial zshrc" > "$zshrc"
    echo "" >> "$zshrc"
    echo "# ACFS PATH ordering (added by doctor --fix)" >> "$zshrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$zshrc"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    fix_path_ordering "path.ordering" >/dev/null 2>&1

    if ! grep -Fq '$HOME/.atuin/bin' "$zshrc"; then
        echo "  Stale PATH ordering block was not repaired with Atuin path"
        cat "$zshrc"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if grep -Fxq 'export PATH="$HOME/.local/bin:$PATH"' "$zshrc"; then
        echo "  Stale PATH ordering export was left behind"
        cat "$zshrc"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_APPLIED -ne 1 ]]; then
        echo "  FIX_APPLIED should be 1 for stale marker repair, got $FIX_APPLIED"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_fix_path_ordering_dry_run() {
    setup_test_env

    # Create empty .zshrc
    local zshrc="$HOME/.zshrc"
    echo "# Initial zshrc" > "$zshrc"

    # Enable dry-run mode
    DOCTOR_FIX_DRY_RUN=true

    # Run fixer
    fix_path_ordering "path.ordering" >/dev/null 2>&1

    # Verify file NOT modified
    if grep -q "# ACFS PATH ordering" "$zshrc"; then
        echo "  File was modified in dry-run mode"
        cleanup_test_env
        return 1
    fi

    # Verify dry-run record added
    if [[ ${#FIXES_DRY_RUN[@]} -ne 1 ]]; then
        echo "  Expected 1 dry-run record, got ${#FIXES_DRY_RUN[@]}"
        cleanup_test_env
        return 1
    fi

    DOCTOR_FIX_DRY_RUN=false
    cleanup_test_env
    return 0
}

test_fix_path_ordering_restores_file_when_record_change_fails() {
    setup_test_env

    local zshrc="$HOME/.zshrc"
    printf '# Initial zshrc\n' > "$zshrc"
    local before_contents
    before_contents="$(cat "$zshrc")"
    local original_record_change
    original_record_change="$(declare -f record_change)"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    record_change() { return 1; }

    if fix_path_ordering "path.ordering" >/dev/null 2>&1; then
        eval "$original_record_change"
        echo "  fix_path_ordering unexpectedly succeeded when record_change failed"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    eval "$original_record_change"

    if [[ "$(cat "$zshrc")" != "$before_contents" ]]; then
        echo "  .zshrc was not restored after record_change failure"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_FAILED -ne 1 ]]; then
        echo "  FIX_FAILED should be 1 after journaling failure, got $FIX_FAILED"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_fix_path_ordering_removes_new_file_when_record_change_fails() {
    setup_test_env

    local zshrc="$HOME/.zshrc"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    record_change() {
        return 1
    }

    if fix_path_ordering "path.ordering" >/dev/null 2>&1; then
        echo "  fix_path_ordering unexpectedly succeeded when record_change failed for a new file"
        cleanup_test_env
        return 1
    fi

    if [[ -e "$zshrc" ]]; then
        echo "  Newly created .zshrc should have been removed after journaling failure"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_path_ordering_refuses_existing_file_when_backup_fails() (
    setup_test_env

    local zshrc="$HOME/.zshrc"
    local before_contents="# Existing user configuration"
    printf '%s\n' "$before_contents" > "$zshrc"

    create_backup() {
        return 1
    }

    if fix_path_ordering "path.ordering" >/dev/null 2>&1; then
        echo "  fix_path_ordering unexpectedly mutated without a recovery backup"
        cleanup_test_env
        return 1
    fi

    if [[ "$(cat "$zshrc")" != "$before_contents" ]]; then
        echo "  Existing .zshrc changed after backup creation failed"
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_FAILED -ne 1 ]]; then
        echo "  FIX_FAILED should be 1 after backup failure, got $FIX_FAILED"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
)

# ============================================================
# Test: fix_config_copy
# ============================================================

test_fix_config_copy_applies() {
    setup_test_env

    # Create source config
    local src="$ACFS_STATE_DIR/source_config.txt"
    local dest="$HOME/.acfs/test_config.txt"
    echo "config content" > "$src"

    # Initialize autofix session
    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    # Run fixer
    fix_config_copy "config.test" "$src" "$dest" >/dev/null 2>&1

    # Verify file copied
    if [[ ! -f "$dest" ]]; then
        echo "  Destination file not created"
        cleanup_test_env
        return 1
    fi

    # Verify content matches
    if ! diff -q "$src" "$dest" >/dev/null; then
        echo "  Content mismatch"
        cleanup_test_env
        return 1
    fi

    # Verify counter incremented
    if [[ $FIX_APPLIED -ne 1 ]]; then
        echo "  FIX_APPLIED should be 1, got $FIX_APPLIED"
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null
    cleanup_test_env
    return 0
}

test_fix_config_copy_idempotent() {
    setup_test_env

    # Create source and destination
    local src="$ACFS_STATE_DIR/source_config.txt"
    local dest="$HOME/.acfs/test_config.txt"
    echo "config content" > "$src"
    echo "existing content" > "$dest"

    # Run fixer
    fix_config_copy "config.test" "$src" "$dest" >/dev/null 2>&1

    # Verify original content preserved
    if [[ "$(cat "$dest")" != "existing content" ]]; then
        echo "  Existing file was overwritten"
        cleanup_test_env
        return 1
    fi

    # Counter should not increment
    if [[ $FIX_APPLIED -ne 0 ]]; then
        echo "  FIX_APPLIED should be 0, got $FIX_APPLIED"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_config_copy_missing_source() {
    setup_test_env

    # Source doesn't exist
    local src="/nonexistent/source.txt"
    local dest="$HOME/.acfs/test_config.txt"

    # Run fixer - should fail
    if fix_config_copy "config.test" "$src" "$dest" 2>/dev/null; then
        echo "  Should have failed with missing source"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_config_copy_dry_run() {
    setup_test_env

    # Create source config
    local src="$ACFS_STATE_DIR/source_config.txt"
    local dest="$HOME/.acfs/test_config.txt"
    echo "config content" > "$src"

    # Enable dry-run mode
    DOCTOR_FIX_DRY_RUN=true

    # Run fixer
    fix_config_copy "config.test" "$src" "$dest" >/dev/null 2>&1

    # Verify file NOT created
    if [[ -f "$dest" ]]; then
        echo "  File was created in dry-run mode"
        cleanup_test_env
        return 1
    fi

    # Verify dry-run record added
    if [[ ${#FIXES_DRY_RUN[@]} -ne 1 ]]; then
        echo "  Expected 1 dry-run record, got ${#FIXES_DRY_RUN[@]}"
        cleanup_test_env
        return 1
    fi

    DOCTOR_FIX_DRY_RUN=false
    cleanup_test_env
    return 0
}

test_fix_config_copy_removes_dest_when_record_change_fails() {
    setup_test_env

    local src="$ACFS_STATE_DIR/source_config.txt"
    local dest="$HOME/.acfs/test_config.txt"
    local original_record_change
    printf 'config content\n' > "$src"
    original_record_change="$(declare -f record_change)"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    record_change() { return 1; }

    if fix_config_copy "config.test" "$src" "$dest" >/dev/null 2>&1; then
        eval "$original_record_change"
        echo "  fix_config_copy unexpectedly succeeded when record_change failed"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    eval "$original_record_change"

    if [[ -e "$dest" ]]; then
        echo "  Destination file was not removed after record_change failure"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_FAILED -ne 1 ]]; then
        echo "  FIX_FAILED should be 1 after config copy journaling failure, got $FIX_FAILED"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_fix_config_copy_removes_created_dirs_when_record_change_fails() {
    setup_test_env

    local src="$ACFS_STATE_DIR/source_config_nested.txt"
    local dest="$HOME/.brand-new-acfs/zsh/acfs.zshrc"
    local original_record_change
    printf 'config content\n' > "$src"
    original_record_change="$(declare -f record_change)"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    record_change() { return 1; }

    if fix_config_copy "config.test" "$src" "$dest" >/dev/null 2>&1; then
        eval "$original_record_change"
        echo "  fix_config_copy unexpectedly succeeded when record_change failed for nested destination"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    eval "$original_record_change"

    if [[ -e "$dest" ]]; then
        echo "  Nested destination file was not removed after record_change failure"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ -d "$HOME/.brand-new-acfs" || -d "$HOME/.brand-new-acfs/zsh" ]]; then
        echo "  Nested config copy left newly created parent directories behind after journaling failure"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_fix_config_copy_cleans_created_dirs_on_copy_failure() {
    setup_test_env

    local src="$ACFS_STATE_DIR/source_config_copy_failure.txt"
    local dest="$HOME/.copy-failure-acfs/zsh/acfs.zshrc"
    printf 'config content\n' > "$src"

    cp() { return 1; }

    if fix_config_copy "config.test" "$src" "$dest" >/dev/null 2>&1; then
        echo "  fix_config_copy unexpectedly succeeded when cp failed"
        cleanup_test_env
        return 1
    fi

    if [[ -e "$dest" ]]; then
        echo "  fix_config_copy left destination behind after copy failure"
        cleanup_test_env
        return 1
    fi

    if [[ -d "$HOME/.copy-failure-acfs" || -d "$HOME/.copy-failure-acfs/zsh" ]]; then
        echo "  fix_config_copy left newly created parent directories behind after copy failure"
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_FAILED -ne 1 ]]; then
        echo "  FIX_FAILED should be 1 after copy failure, got $FIX_FAILED"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# ============================================================
# Test: fix_symlink_create
# ============================================================

test_fix_symlink_create_applies() {
    setup_test_env

    # Create binary
    local binary="$HOME/.cargo/bin/test_tool"
    local symlink="$HOME/.local/bin/test_tool"
    echo '#!/bin/bash' > "$binary"
    echo 'echo "test"' >> "$binary"
    chmod +x "$binary"

    # Initialize autofix session
    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    # Run fixer
    fix_symlink_create "symlink.test" "$binary" "$symlink" >/dev/null 2>&1

    # Verify symlink created
    if [[ ! -L "$symlink" ]]; then
        echo "  Symlink not created"
        cleanup_test_env
        return 1
    fi

    # Verify symlink points to correct target
    local target
    target=$(readlink "$symlink")
    if [[ "$target" != "$binary" ]]; then
        echo "  Symlink points to wrong target: $target"
        cleanup_test_env
        return 1
    fi

    # Verify counter incremented
    if [[ $FIX_APPLIED -ne 1 ]]; then
        echo "  FIX_APPLIED should be 1, got $FIX_APPLIED"
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null
    cleanup_test_env
    return 0
}

test_fix_symlink_create_idempotent() {
    setup_test_env

    # Create binary and existing symlink
    local binary="$HOME/.cargo/bin/test_tool"
    local symlink="$HOME/.local/bin/test_tool"
    echo '#!/bin/bash' > "$binary"
    chmod +x "$binary"
    ln -s "$binary" "$symlink"

    # Run fixer
    fix_symlink_create "symlink.test" "$binary" "$symlink" >/dev/null 2>&1

    # Counter should not increment
    if [[ $FIX_APPLIED -ne 0 ]]; then
        echo "  FIX_APPLIED should be 0, got $FIX_APPLIED"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_symlink_create_missing_binary() {
    setup_test_env

    local binary="/nonexistent/binary"
    local symlink="$HOME/.local/bin/test_tool"

    # Run fixer - should fail
    if fix_symlink_create "symlink.test" "$binary" "$symlink" 2>/dev/null; then
        echo "  Should have failed with missing binary"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_symlink_create_dry_run() {
    setup_test_env

    # Create binary
    local binary="$HOME/.cargo/bin/test_tool"
    local symlink="$HOME/.local/bin/test_tool"
    echo '#!/bin/bash' > "$binary"
    chmod +x "$binary"

    # Enable dry-run mode
    DOCTOR_FIX_DRY_RUN=true

    # Run fixer
    fix_symlink_create "symlink.test" "$binary" "$symlink" >/dev/null 2>&1

    # Verify symlink NOT created
    if [[ -L "$symlink" ]]; then
        echo "  Symlink was created in dry-run mode"
        cleanup_test_env
        return 1
    fi

    # Verify dry-run record added
    if [[ ${#FIXES_DRY_RUN[@]} -ne 1 ]]; then
        echo "  Expected 1 dry-run record, got ${#FIXES_DRY_RUN[@]}"
        cleanup_test_env
        return 1
    fi

    DOCTOR_FIX_DRY_RUN=false
    cleanup_test_env
    return 0
}

test_fix_symlink_create_removes_symlink_when_record_change_fails() {
    setup_test_env

    local binary="$HOME/.cargo/bin/test_tool"
    local symlink="$HOME/.local/bin/test_tool"
    local original_record_change
    printf '#!/bin/bash\necho test\n' > "$binary"
    chmod +x "$binary"
    original_record_change="$(declare -f record_change)"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    record_change() { return 1; }

    if fix_symlink_create "symlink.test" "$binary" "$symlink" >/dev/null 2>&1; then
        eval "$original_record_change"
        echo "  fix_symlink_create unexpectedly succeeded when record_change failed"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    eval "$original_record_change"

    if [[ -e "$symlink" || -L "$symlink" ]]; then
        echo "  Symlink was not removed after record_change failure"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_FAILED -ne 1 ]]; then
        echo "  FIX_FAILED should be 1 after symlink journaling failure, got $FIX_FAILED"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_fix_symlink_create_removes_created_dirs_when_record_change_fails() {
    setup_test_env

    local binary_dir="$HOME/bin-src"
    local binary="$binary_dir/test_tool"
    local symlink="$HOME/.new-links/bin/test_tool"
    local original_record_change
    mkdir -p "$binary_dir"
    printf '#!/bin/bash\necho test\n' > "$binary"
    chmod +x "$binary"
    original_record_change="$(declare -f record_change)"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    record_change() { return 1; }

    if fix_symlink_create "symlink.test" "$binary" "$symlink" >/dev/null 2>&1; then
        eval "$original_record_change"
        echo "  fix_symlink_create unexpectedly succeeded when record_change failed for nested destination"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    eval "$original_record_change"

    if [[ -e "$symlink" || -L "$symlink" ]]; then
        echo "  Nested symlink was not removed after record_change failure"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ -d "$HOME/.new-links" || -d "$HOME/.new-links/bin" ]]; then
        echo "  Symlink creation left newly created parent directories behind after journaling failure"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_fix_symlink_create_cleans_created_dirs_on_symlink_failure() {
    setup_test_env

    local binary_dir="$HOME/bin-src"
    local binary="$binary_dir/test_tool"
    local symlink="$HOME/.symlink-failure/bin/test_tool"
    mkdir -p "$binary_dir"
    printf '#!/bin/bash\necho test\n' > "$binary"
    chmod +x "$binary"

    ln() { return 1; }

    if fix_symlink_create "symlink.test" "$binary" "$symlink" >/dev/null 2>&1; then
        echo "  fix_symlink_create unexpectedly succeeded when ln failed"
        cleanup_test_env
        return 1
    fi

    if [[ -e "$symlink" || -L "$symlink" ]]; then
        echo "  fix_symlink_create left symlink destination behind after ln failure"
        cleanup_test_env
        return 1
    fi

    if [[ -d "$HOME/.symlink-failure" || -d "$HOME/.symlink-failure/bin" ]]; then
        echo "  fix_symlink_create left newly created parent directories behind after ln failure"
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_FAILED -ne 1 ]]; then
        echo "  FIX_FAILED should be 1 after symlink failure, got $FIX_FAILED"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_plugin_clone_removes_created_dirs_when_record_change_fails() {
    setup_test_env

    local plugin_name="zsh-autosuggestions"
    local plugin_root="$HOME/.oh-my-zsh"
    local target_dir="$plugin_root/custom/plugins/$plugin_name"
    local original_record_change

    mkdir -p "$plugin_root"
    original_record_change="$(declare -f record_change)"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    git() {
        if [[ "${1:-}" == "clone" ]]; then
            mkdir -p "$target_dir"
            printf 'plugin\n' > "$target_dir/README.md"
            return 0
        fi
        return 1
    }
    record_change() { return 1; }

    if fix_plugin_clone "shell.plugins.zsh_autosuggestions" "$plugin_name" "https://example.invalid/$plugin_name.git" >/dev/null 2>&1; then
        eval "$original_record_change"
        echo "  fix_plugin_clone unexpectedly succeeded when record_change failed"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    eval "$original_record_change"

    if [[ -d "$target_dir" ]]; then
        echo "  Plugin directory was not removed after record_change failure"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ -d "$plugin_root/custom" || -d "$plugin_root/custom/plugins" ]]; then
        echo "  Plugin clone left newly created parent directories behind after journaling failure"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_fix_plugin_clone_cleans_partial_clone_on_clone_failure() {
    setup_test_env

    local plugin_name="zsh-syntax-highlighting"
    local plugin_root="$HOME/.oh-my-zsh"
    local target_dir="$plugin_root/custom/plugins/$plugin_name"

    mkdir -p "$plugin_root"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    git() {
        if [[ "${1:-}" == "clone" ]]; then
            mkdir -p "$target_dir"
            printf 'partial\n' > "$target_dir/README.md"
            return 1
        fi
        return 1
    }

    if fix_plugin_clone "shell.plugins.zsh_syntax_highlighting" "$plugin_name" "https://example.invalid/$plugin_name.git" >/dev/null 2>&1; then
        echo "  fix_plugin_clone unexpectedly succeeded when git clone failed"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ -d "$target_dir" ]]; then
        echo "  Partial plugin clone directory was not cleaned up after clone failure"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ -d "$plugin_root/custom" || -d "$plugin_root/custom/plugins" ]]; then
        echo "  Plugin clone failure left newly created parent directories behind"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_FAILED -ne 1 ]]; then
        echo "  FIX_FAILED should be 1 after clone failure, got $FIX_FAILED"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

# ============================================================
# Test: fix_acfs_sourcing
# ============================================================

test_fix_acfs_sourcing_applies() {
    setup_test_env

    # Create .zshrc and acfs.zshrc
    local zshrc="$HOME/.zshrc"
    echo "# Initial zshrc" > "$zshrc"

    local acfs_zshrc="$HOME/.acfs/zsh/acfs.zshrc"
    echo "# ACFS config" > "$acfs_zshrc"

    # Initialize autofix session
    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    # Run fixer
    fix_acfs_sourcing "shell.acfs_sourced" >/dev/null 2>&1

    # Verify marker was added
    if ! grep -q "# ACFS configuration" "$zshrc"; then
        echo "  ACFS configuration marker not found in .zshrc"
        cleanup_test_env
        return 1
    fi

    # Verify source line was added
    if ! grep -q "source ~/.acfs/zsh/acfs.zshrc" "$zshrc"; then
        echo "  Source line not found in .zshrc"
        cleanup_test_env
        return 1
    fi

    # Verify counter incremented
    if [[ $FIX_APPLIED -ne 1 ]]; then
        echo "  FIX_APPLIED should be 1, got $FIX_APPLIED"
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null
    cleanup_test_env
    return 0
}

test_fix_acfs_sourcing_idempotent() {
    setup_test_env

    # Create .zshrc with sourcing already present
    local zshrc="$HOME/.zshrc"
    echo "# Initial zshrc" > "$zshrc"
    echo "source ~/.acfs/zsh/acfs.zshrc" >> "$zshrc"

    local acfs_zshrc="$HOME/.acfs/zsh/acfs.zshrc"
    echo "# ACFS config" > "$acfs_zshrc"

    local initial_lines
    initial_lines=$(wc -l < "$zshrc")

    # Run fixer
    fix_acfs_sourcing "shell.acfs_sourced" >/dev/null 2>&1

    # Verify file not modified
    local final_lines
    final_lines=$(wc -l < "$zshrc")

    if [[ $initial_lines -ne $final_lines ]]; then
        echo "  File was modified when it shouldn't have been"
        cleanup_test_env
        return 1
    fi

    # Counter should not increment
    if [[ $FIX_APPLIED -ne 0 ]]; then
        echo "  FIX_APPLIED should be 0, got $FIX_APPLIED"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_acfs_sourcing_ignores_commented_loader_mention() {
    setup_test_env

    local zshrc="$HOME/.zshrc"
    echo "# Initial zshrc" > "$zshrc"
    echo "# source ~/.acfs/zsh/acfs.zshrc" >> "$zshrc"

    local acfs_zshrc="$HOME/.acfs/zsh/acfs.zshrc"
    echo "# ACFS config" > "$acfs_zshrc"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    fix_acfs_sourcing "shell.acfs_sourced" >/dev/null 2>&1

    if ! grep -Fxq '[[ -f ~/.acfs/zsh/acfs.zshrc ]] && source ~/.acfs/zsh/acfs.zshrc' "$zshrc"; then
        echo "  Active ACFS source line was not added when only a comment mentioned acfs.zshrc"
        cat "$zshrc"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_APPLIED -ne 1 ]]; then
        echo "  FIX_APPLIED should be 1 for commented loader repair, got $FIX_APPLIED"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_fix_acfs_sourcing_uses_target_home() {
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.acfs/zsh"
    echo "# Target ACFS config" > "$TARGET_HOME/.acfs/zsh/acfs.zshrc"
    echo "# Target zshrc" > "$TARGET_HOME/.zshrc"
    echo "# Caller zshrc" > "$HOME/.zshrc"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    fix_acfs_sourcing "shell.acfs_sourced" >/dev/null 2>&1

    if ! grep -q "source ~/.acfs/zsh/acfs.zshrc" "$TARGET_HOME/.zshrc"; then
        echo "  Target-home .zshrc was not updated"
        cleanup_test_env
        return 1
    fi

    if grep -q "source ~/.acfs/zsh/acfs.zshrc" "$HOME/.zshrc"; then
        echo "  Caller HOME .zshrc was modified unexpectedly"
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null
    cleanup_test_env
    return 0
}

test_dispatch_fix_config_copy_uses_target_home() {
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.acfs"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    dispatch_fix "config.acfs_zshrc" "warn" >/dev/null 2>&1

    if [[ ! -f "$TARGET_HOME/.acfs/zsh/acfs.zshrc" ]]; then
        echo "  Config copy did not write into TARGET_HOME"
        cleanup_test_env
        return 1
    fi

    if [[ -e "$HOME/.acfs/zsh/acfs.zshrc" ]]; then
        echo "  Config copy wrote into caller HOME unexpectedly"
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null
    cleanup_test_env
    return 0
}

test_dispatch_fix_symlink_uses_target_home() {
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.cargo/bin" "$TARGET_HOME/.local/bin"
    printf '#!/usr/bin/env bash\necho br\n' > "$TARGET_HOME/.cargo/bin/br"
    chmod +x "$TARGET_HOME/.cargo/bin/br"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    dispatch_fix "symlink.br" "warn" >/dev/null 2>&1

    if [[ ! -L "$TARGET_HOME/.local/bin/br" ]]; then
        echo "  Symlink fix did not write into TARGET_HOME"
        cleanup_test_env
        return 1
    fi

    if [[ -e "$HOME/.local/bin/br" ]]; then
        echo "  Symlink fix wrote into caller HOME unexpectedly"
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null
    cleanup_test_env
    return 0
}

test_fix_acfs_sourcing_missing_acfs_config() {
    setup_test_env

    # Create .zshrc but no acfs.zshrc
    local zshrc="$HOME/.zshrc"
    echo "# Initial zshrc" > "$zshrc"
    rm -f "$HOME/.acfs/zsh/acfs.zshrc"

    # Run fixer - should fail
    if fix_acfs_sourcing "shell.acfs_sourced" 2>/dev/null; then
        echo "  Should have failed with missing acfs.zshrc"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_acfs_sourcing_dry_run() {
    setup_test_env

    # Create .zshrc and acfs.zshrc
    local zshrc="$HOME/.zshrc"
    echo "# Initial zshrc" > "$zshrc"

    local acfs_zshrc="$HOME/.acfs/zsh/acfs.zshrc"
    echo "# ACFS config" > "$acfs_zshrc"

    # Enable dry-run mode
    DOCTOR_FIX_DRY_RUN=true

    # Run fixer
    fix_acfs_sourcing "shell.acfs_sourced" >/dev/null 2>&1

    # Verify file NOT modified
    if grep -q "# ACFS configuration" "$zshrc"; then
        echo "  File was modified in dry-run mode"
        cleanup_test_env
        return 1
    fi

    # Verify dry-run record added
    if [[ ${#FIXES_DRY_RUN[@]} -ne 1 ]]; then
        echo "  Expected 1 dry-run record, got ${#FIXES_DRY_RUN[@]}"
        cleanup_test_env
        return 1
    fi

    DOCTOR_FIX_DRY_RUN=false
    cleanup_test_env
    return 0
}

test_fix_acfs_sourcing_removes_new_file_when_record_change_fails() {
    setup_test_env

    local zshrc="$HOME/.zshrc"
    echo "# ACFS zsh config" > "$HOME/.acfs/zsh/acfs.zshrc"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    record_change() {
        return 1
    }

    if fix_acfs_sourcing "shell.acfs_sourced" >/dev/null 2>&1; then
        echo "  fix_acfs_sourcing unexpectedly succeeded when record_change failed for a new file"
        cleanup_test_env
        return 1
    fi

    if [[ -e "$zshrc" ]]; then
        echo "  Newly created .zshrc should have been removed after ACFS sourcing journaling failure"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_acfs_sourcing_refuses_existing_file_when_backup_fails() (
    setup_test_env

    local zshrc="$HOME/.zshrc"
    local before_contents="# Existing user configuration"
    printf '%s\n' "$before_contents" > "$zshrc"
    printf '# ACFS zsh config\n' > "$HOME/.acfs/zsh/acfs.zshrc"

    create_backup() {
        return 1
    }

    if fix_acfs_sourcing "shell.acfs_sourced" >/dev/null 2>&1; then
        echo "  fix_acfs_sourcing unexpectedly mutated without a recovery backup"
        cleanup_test_env
        return 1
    fi

    if [[ "$(cat "$zshrc")" != "$before_contents" ]]; then
        echo "  Existing .zshrc changed after ACFS sourcing backup failed"
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_FAILED -ne 1 ]]; then
        echo "  FIX_FAILED should be 1 after backup failure, got $FIX_FAILED"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
)

test_fix_stack_install_applies_and_records_change() {
    setup_test_env
    export PATH="$HOME/.local/bin:$PATH"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    if ! fix_stack_install "agent.codex" "codex-test-bin" "cat > \"$HOME/.local/bin/codex-test-bin\" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x \"$HOME/.local/bin/codex-test-bin\"" >/dev/null 2>&1; then
        echo "  fix_stack_install should succeed"
        cleanup_test_env
        return 1
    fi

    if [[ ! -x "$HOME/.local/bin/codex-test-bin" ]]; then
        echo "  fix_stack_install did not create the expected binary"
        cleanup_test_env
        return 1
    fi

    if ! jq -e 'select(.description == "Installed codex-test-bin" and .reversible == false)' "$ACFS_CHANGES_FILE" >/dev/null 2>&1; then
        echo "  fix_stack_install did not record a non-reversible install change"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_stack_install_uses_target_runtime_home() {
    setup_test_env
    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin" "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    cat > "$HOME/.local/bin/codex-target-bin" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$HOME/.local/bin/codex-target-bin"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    local install_cmd='cat > "$HOME/.local/bin/codex-target-bin" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$HOME/.local/bin/codex-target-bin"'

    if ! fix_stack_install "agent.codex" "codex-target-bin" "$install_cmd" >/dev/null 2>&1; then
        echo "  fix_stack_install should succeed for TARGET_HOME installs"
        cleanup_test_env
        return 1
    fi

    if [[ ! -x "$TARGET_HOME/.local/bin/codex-target-bin" ]]; then
        echo "  fix_stack_install did not install into TARGET_HOME"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_stack_install_runs_from_target_runtime_home() {
    setup_test_env
    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    local install_cmd='[[ "$PWD" == "$HOME" ]] || exit 42
cat > "$PWD/.local/bin/codex-pwd-bin" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$PWD/.local/bin/codex-pwd-bin"'

    if ! fix_stack_install "agent.codex" "codex-pwd-bin" "$install_cmd" >/dev/null 2>&1; then
        echo "  fix_stack_install should run installer from the runtime home"
        cleanup_test_env
        return 1
    fi

    if [[ ! -x "$TARGET_HOME/.local/bin/codex-pwd-bin" ]]; then
        echo "  fix_stack_install did not create the binary under TARGET_HOME"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_stack_install_fails_when_binary_missing_after_successful_command() {
    setup_test_env
    export PATH="$HOME/.local/bin:$PATH"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    if fix_stack_install "agent.codex" "codex-missing-bin" "true" >/dev/null 2>&1; then
        echo "  fix_stack_install should fail when installer reports success but binary is missing"
        cleanup_test_env
        return 1
    fi

    if [[ -s "$ACFS_CHANGES_FILE" ]]; then
        echo "  fix_stack_install should not record a change when the binary is still missing"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_stack_install_removes_binary_when_record_change_fails() {
    setup_test_env
    export PATH="$HOME/.local/bin:$PATH"
    local original_record_change=""
    original_record_change="$(declare -f record_change)"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    record_change() { return 1; }

    if fix_stack_install "agent.codex" "codex-journal-fail" "cat > \"$HOME/.local/bin/codex-journal-fail\" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x \"$HOME/.local/bin/codex-journal-fail\"" >/dev/null 2>&1; then
        eval "$original_record_change"
        echo "  fix_stack_install should fail when record_change fails"
        cleanup_test_env
        return 1
    fi

    eval "$original_record_change"

    if [[ -e "$HOME/.local/bin/codex-journal-fail" ]]; then
        echo "  fix_stack_install left the installed binary behind after journaling failure"
        cleanup_test_env
        return 1
    fi

    if [[ -s "$ACFS_CHANGES_FILE" ]]; then
        echo "  fix_stack_install should not persist a journal entry when journaling fails"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# ============================================================
# Test: fix_verified_install
# ============================================================

test_fix_verified_install_applies() {
    setup_test_env
    local original_doctor_fix_run_verified_installer
    original_doctor_fix_run_verified_installer="$(declare -f doctor_fix_run_verified_installer)"
    export PATH="$HOME/.local/bin:$PATH"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    doctor_fix_run_verified_installer() {
        cat > "$HOME/.local/bin/ms-test-bin" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "$HOME/.local/bin/ms-test-bin"
        return 0
    }

    if ! fix_verified_install "stack.meta_skill" "ms-test-bin" "ms" --easy-mode >/dev/null 2>&1; then
        echo "  fix_verified_install should succeed"
        eval "$original_doctor_fix_run_verified_installer"
        cleanup_test_env
        return 1
    fi

    if [[ ! -x "$HOME/.local/bin/ms-test-bin" ]]; then
        echo "  Verified installer stub did not create ms-test-bin"
        eval "$original_doctor_fix_run_verified_installer"
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_APPLIED -ne 1 ]]; then
        echo "  FIX_APPLIED should be 1, got $FIX_APPLIED"
        eval "$original_doctor_fix_run_verified_installer"
        cleanup_test_env
        return 1
    fi

    if ! jq -e 'select(.description == "Installed ms-test-bin via verified installer" and .reversible == false)' "$ACFS_CHANGES_FILE" >/dev/null 2>&1; then
        echo "  fix_verified_install did not record a non-reversible install change"
        eval "$original_doctor_fix_run_verified_installer"
        cleanup_test_env
        return 1
    fi

    eval "$original_doctor_fix_run_verified_installer"
    cleanup_test_env
    return 0
}

test_fix_verified_install_uses_target_runtime_home() {
    setup_test_env
    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin" "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    local original_doctor_fix_run_verified_installer=""
    local installer_signal="$ACFS_STATE_DIR/verified-installer-invoked"
    original_doctor_fix_run_verified_installer="$(declare -f doctor_fix_run_verified_installer)"

    cat > "$HOME/.local/bin/ms-target-bin" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$HOME/.local/bin/ms-target-bin"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    doctor_fix_run_verified_installer() {
        local runtime_home=""
        runtime_home="$(doctor_fix_runtime_home)"
        : > "$installer_signal"
        mkdir -p "$runtime_home/.local/bin"
        cat > "$runtime_home/.local/bin/ms-target-bin" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "$runtime_home/.local/bin/ms-target-bin"
        return 0
    }

    if ! fix_verified_install "stack.meta_skill" "ms-target-bin" "ms" --easy-mode >/dev/null 2>&1; then
        echo "  fix_verified_install should succeed for TARGET_HOME installs"
        eval "$original_doctor_fix_run_verified_installer"
        cleanup_test_env
        return 1
    fi

    if [[ ! -f "$installer_signal" ]]; then
        echo "  fix_verified_install incorrectly treated current-shell binary as already installed"
        eval "$original_doctor_fix_run_verified_installer"
        cleanup_test_env
        return 1
    fi

    if [[ ! -x "$TARGET_HOME/.local/bin/ms-target-bin" ]]; then
        echo "  fix_verified_install did not detect the target-home binary after install"
        eval "$original_doctor_fix_run_verified_installer"
        cleanup_test_env
        return 1
    fi

    eval "$original_doctor_fix_run_verified_installer"
    cleanup_test_env
    return 0
}

test_fix_verified_install_dry_run() {
    setup_test_env

    DOCTOR_FIX_DRY_RUN=true
    if ! fix_verified_install "stack.meta_skill" "ms-test-bin" "ms" --easy-mode >/dev/null 2>&1; then
        echo "  fix_verified_install dry-run should succeed"
        cleanup_test_env
        return 1
    fi

    if [[ ${#FIXES_DRY_RUN[@]} -ne 1 ]]; then
        echo "  Expected 1 dry-run record, got ${#FIXES_DRY_RUN[@]}"
        cleanup_test_env
        return 1
    fi

    if [[ "${FIXES_DRY_RUN[0]}" != *"verified:ms --easy-mode"* ]]; then
        echo "  Dry-run record should note verified installer invocation"
        cleanup_test_env
        return 1
    fi

    DOCTOR_FIX_DRY_RUN=false
    cleanup_test_env
    return 0
}

test_dispatch_fix_routes_cass_with_target_tmpdir() {
    setup_test_env
    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin"
    export PATH="$TARGET_HOME/.local/bin:$PATH"

    local original_doctor_fix_run_verified_installer_with_env=""
    local installer_signal="$ACFS_STATE_DIR/cass-installer.env"
    original_doctor_fix_run_verified_installer_with_env="$(declare -f doctor_fix_run_verified_installer_with_env)"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    doctor_fix_run_verified_installer_with_env() {
        local tool="$1"
        local env_assignment="$2"
        shift 2

        printf '%s\n%s\n%s\n' "$tool" "$env_assignment" "$*" > "$installer_signal"
        [[ "$tool" == "cass" ]] || return 1
        case "$env_assignment" in
            "TMPDIR=$TARGET_HOME/.cache/acfs/installer-tmp/cass."*) ;;
            *) return 1 ;;
        esac
        [[ -d "${env_assignment#TMPDIR=}" ]] || return 1
        [[ "$*" == "--easy-mode --verify" ]] || return 1

        cat > "$TARGET_HOME/.local/bin/cass" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "$TARGET_HOME/.local/bin/cass"
        return 0
    }

    if ! dispatch_fix "stack.cass" "fail" "install cass" >/dev/null 2>&1; then
        echo "  dispatch_fix should route stack.cass through the target TMPDIR verified installer"
        eval "$original_doctor_fix_run_verified_installer_with_env"
        cleanup_test_env
        return 1
    fi

    if [[ ! -s "$installer_signal" ]]; then
        echo "  stack.cass did not invoke the verified installer"
        eval "$original_doctor_fix_run_verified_installer_with_env"
        cleanup_test_env
        return 1
    fi

    if [[ ! -x "$TARGET_HOME/.local/bin/cass" ]]; then
        echo "  stack.cass repair did not install cass in TARGET_HOME"
        eval "$original_doctor_fix_run_verified_installer_with_env"
        cleanup_test_env
        return 1
    fi

    eval "$original_doctor_fix_run_verified_installer_with_env"
    cleanup_test_env
    return 0
}

test_doctor_fix_build_runtime_env_args_accepts_multiple_env_assignments() {
    setup_test_env
    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin"

    local -a env_args=()
    if ! doctor_fix_build_runtime_env_args env_args $'FIRST_ENV=one\nSECOND_ENV=two words'; then
        echo "  runtime env builder should accept newline-separated installer env assignments"
        cleanup_test_env
        return 1
    fi

    if [[ " ${env_args[*]} " != *" TARGET_HOME=$TARGET_HOME "* ]]; then
        echo "  runtime env args should include TARGET_HOME"
        cleanup_test_env
        return 1
    fi

    if [[ " ${env_args[*]} " != *" FIRST_ENV=one "* ]]; then
        echo "  runtime env args should include FIRST_ENV"
        cleanup_test_env
        return 1
    fi

    if [[ " ${env_args[*]} " != *" SECOND_ENV=two words "* ]]; then
        echo "  runtime env args should include SECOND_ENV with spaces preserved"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_verified_install_ignores_gcloud_bv_shadow() {
    setup_test_env
    mkdir -p "$HOME/google-cloud-sdk/bin" "$HOME/.local/bin"
    export PATH="$HOME/google-cloud-sdk/bin:$PATH"

    local original_doctor_fix_run_verified_installer=""
    local installer_signal="$ACFS_STATE_DIR/bv-installer-invoked"
    original_doctor_fix_run_verified_installer="$(declare -f doctor_fix_run_verified_installer)"

    cat > "$HOME/google-cloud-sdk/bin/bv" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$HOME/google-cloud-sdk/bin/bv"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    doctor_fix_run_verified_installer() {
        local tool="$1"
        : > "$installer_signal"
        [[ "$tool" == "bv" ]] || return 1
        cat > "$HOME/.local/bin/bv" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "$HOME/.local/bin/bv"
        return 0
    }

    if ! fix_verified_install "stack.bv" "bv" "bv" >/dev/null 2>&1; then
        echo "  fix_verified_install should repair a gcloud-shadowed bv"
        eval "$original_doctor_fix_run_verified_installer"
        cleanup_test_env
        return 1
    fi

    if [[ ! -f "$installer_signal" ]]; then
        echo "  fix_verified_install incorrectly treated gcloud's bv as the Beads Viewer install"
        eval "$original_doctor_fix_run_verified_installer"
        cleanup_test_env
        return 1
    fi

    if [[ ! -x "$HOME/.local/bin/bv" ]]; then
        echo "  fix_verified_install did not create the target Beads Viewer binary"
        eval "$original_doctor_fix_run_verified_installer"
        cleanup_test_env
        return 1
    fi

    eval "$original_doctor_fix_run_verified_installer"
    cleanup_test_env
    return 0
}

test_fix_verified_install_ms_arm64_fallback_uses_cargo() {
    setup_test_env
    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.cargo/bin" "$TARGET_HOME/.local/bin" "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    local cargo_signal="$ACFS_STATE_DIR/target-cargo.args"
    local caller_signal="$ACFS_STATE_DIR/caller-cargo.args"
    cat > "$HOME/.local/bin/cargo" <<EOF
#!/usr/bin/env bash
: > "$caller_signal"
exit 99
EOF
    chmod +x "$HOME/.local/bin/cargo"

    cat > "$TARGET_HOME/.cargo/bin/cargo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$cargo_signal"
mkdir -p "\$HOME/.local/bin"
cat > "\$HOME/.local/bin/ms-test-bin" <<'BIN_EOF'
#!/usr/bin/env bash
exit 0
BIN_EOF
chmod +x "\$HOME/.local/bin/ms-test-bin"
exit 0
EOF
    chmod +x "$TARGET_HOME/.cargo/bin/cargo"

    local original_uname=""
    original_uname="$(declare -f uname 2>/dev/null || true)"
    local arch=""
    for arch in aarch64 arm64; do
        rm -f "$cargo_signal" "$caller_signal" "$TARGET_HOME/.local/bin/ms-test-bin"

        uname() {
            case "${1:-}" in
                -s) printf 'Linux\n' ;;
                -m) printf '%s\n' "$arch" ;;
                *) command uname "$@" ;;
            esac
        }

        if ! fix_verified_install "stack.meta_skill" "ms-test-bin" "ms" --easy-mode >/dev/null 2>&1; then
            echo "  fix_verified_install should succeed via cargo fallback on ARM64 Linux ($arch)"
            [[ -n "$original_uname" ]] && eval "$original_uname" || unset -f uname
            cleanup_test_env
            return 1
        fi

        if [[ ! -f "$cargo_signal" ]]; then
            echo "  target-home cargo fallback was not invoked for arch $arch"
            [[ -n "$original_uname" ]] && eval "$original_uname" || unset -f uname
            cleanup_test_env
            return 1
        fi

        if [[ -f "$caller_signal" ]]; then
            echo "  fix_verified_install used caller-shell cargo instead of TARGET_HOME cargo for arch $arch"
            [[ -n "$original_uname" ]] && eval "$original_uname" || unset -f uname
            cleanup_test_env
            return 1
        fi

        if ! grep -q -- '--git https://github.com/Dicklesworthstone/meta_skill --force' "$cargo_signal"; then
            echo "  cargo fallback did not force reinstall from meta_skill git source for arch $arch"
            cat "$cargo_signal"
            [[ -n "$original_uname" ]] && eval "$original_uname" || unset -f uname
            cleanup_test_env
            return 1
        fi

        if [[ ! -x "$TARGET_HOME/.local/bin/ms-test-bin" ]]; then
            echo "  cargo fallback did not produce ms-test-bin in TARGET_HOME for arch $arch"
            [[ -n "$original_uname" ]] && eval "$original_uname" || unset -f uname
            cleanup_test_env
            return 1
        fi
    done

    [[ -n "$original_uname" ]] && eval "$original_uname" || unset -f uname
    cleanup_test_env
    return 0
}
test_fix_verified_install_removes_binary_when_record_change_fails() {
    setup_test_env
    export PATH="$HOME/.local/bin:$PATH"
    local original_doctor_fix_run_verified_installer=""
    local original_record_change=""
    original_doctor_fix_run_verified_installer="$(declare -f doctor_fix_run_verified_installer)"
    original_record_change="$(declare -f record_change)"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    doctor_fix_run_verified_installer() {
        cat > "$HOME/.local/bin/ms-journal-fail" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "$HOME/.local/bin/ms-journal-fail"
        return 0
    }
    record_change() { return 1; }

    if fix_verified_install "stack.meta_skill" "ms-journal-fail" "ms" --easy-mode >/dev/null 2>&1; then
        eval "$original_doctor_fix_run_verified_installer"
        eval "$original_record_change"
        echo "  fix_verified_install should fail when record_change fails"
        cleanup_test_env
        return 1
    fi

    eval "$original_doctor_fix_run_verified_installer"
    eval "$original_record_change"

    if [[ -e "$HOME/.local/bin/ms-journal-fail" ]]; then
        echo "  fix_verified_install left the installed binary behind after journaling failure"
        cleanup_test_env
        return 1
    fi

    if [[ -s "$ACFS_CHANGES_FILE" ]]; then
        echo "  fix_verified_install should not persist a journal entry when journaling fails"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_ssh_server_records_change_when_enabling_service() {
    setup_test_env
    local created_systemd_dir=false
    local original_resolver=""
    local temp_bin=""

    if [[ ! -d /run/systemd/system ]]; then
        mkdir -p /run/systemd/system || {
            echo "  Failed to create /run/systemd/system for SSH server test"
            cleanup_test_env
            return 1
        }
        created_systemd_dir=true
    fi

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        if [[ "$created_systemd_dir" == "true" ]]; then rmdir /run/systemd/system 2>/dev/null || true; fi
        cleanup_test_env
        return 1
    }

    original_resolver="$(declare -f doctor_fix_system_binary_path)"
    temp_bin="$ACFS_STATE_DIR/bin"
    mkdir -p "$temp_bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$temp_bin/sshd"
    cat > "$temp_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    is-active) exit 1 ;;
    enable) exit 0 ;;
    *) exit 0 ;;
esac
EOF
    cat > "$temp_bin/sudo" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-n" ]] || exit 42
shift
exec "$@"
EOF
    chmod +x "$temp_bin/sshd" "$temp_bin/systemctl" "$temp_bin/sudo"

    doctor_fix_system_binary_path() {
        case "${1:-}" in
            sshd|systemctl|sudo) printf '%s\n' "$temp_bin/${1:-}" ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }

    if ! fix_ssh_server "network.ssh_server" >/dev/null 2>&1; then
        eval "$original_resolver"
        echo "  fix_ssh_server should succeed when systemctl enable/start succeeds"
        if [[ "$created_systemd_dir" == "true" ]]; then rmdir /run/systemd/system 2>/dev/null || true; fi
        cleanup_test_env
        return 1
    fi

    if ! jq -e 'select(.description == "Enabled and started SSH server")' "$ACFS_CHANGES_FILE" >/dev/null 2>&1; then
        eval "$original_resolver"
        echo "  fix_ssh_server did not record the SSH enable/start change"
        if [[ "$created_systemd_dir" == "true" ]]; then rmdir /run/systemd/system 2>/dev/null || true; fi
        cleanup_test_env
        return 1
    fi

    eval "$original_resolver"
    if [[ "$created_systemd_dir" == "true" ]]; then rmdir /run/systemd/system 2>/dev/null || true; fi
    cleanup_test_env
    return 0
}

test_fix_ssh_server_fails_when_service_enable_fails() {
    setup_test_env
    local created_systemd_dir=false
    local original_resolver=""
    local temp_bin=""

    if [[ ! -d /run/systemd/system ]]; then
        mkdir -p /run/systemd/system || {
            echo "  Failed to create /run/systemd/system for SSH server test"
            cleanup_test_env
            return 1
        }
        created_systemd_dir=true
    fi

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        if [[ "$created_systemd_dir" == "true" ]]; then rmdir /run/systemd/system 2>/dev/null || true; fi
        cleanup_test_env
        return 1
    }

    original_resolver="$(declare -f doctor_fix_system_binary_path)"
    temp_bin="$ACFS_STATE_DIR/bin"
    mkdir -p "$temp_bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$temp_bin/sshd"
    cat > "$temp_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    is-active) exit 1 ;;
    enable) exit 1 ;;
    *) exit 1 ;;
esac
EOF
    cat > "$temp_bin/sudo" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-n" ]] || exit 42
shift
exec "$@"
EOF
    chmod +x "$temp_bin/sshd" "$temp_bin/systemctl" "$temp_bin/sudo"

    doctor_fix_system_binary_path() {
        case "${1:-}" in
            sshd|systemctl|sudo) printf '%s\n' "$temp_bin/${1:-}" ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }

    if fix_ssh_server "network.ssh_server" >/dev/null 2>&1; then
        eval "$original_resolver"
        echo "  fix_ssh_server should fail when systemctl enable/start fails"
        if [[ "$created_systemd_dir" == "true" ]]; then rmdir /run/systemd/system 2>/dev/null || true; fi
        cleanup_test_env
        return 1
    fi

    if [[ -s "$ACFS_CHANGES_FILE" ]]; then
        eval "$original_resolver"
        echo "  fix_ssh_server should not record a change when enable/start fails"
        if [[ "$created_systemd_dir" == "true" ]]; then rmdir /run/systemd/system 2>/dev/null || true; fi
        cleanup_test_env
        return 1
    fi

    eval "$original_resolver"
    if [[ "$created_systemd_dir" == "true" ]]; then rmdir /run/systemd/system 2>/dev/null || true; fi
    cleanup_test_env
    return 0
}

test_fix_ssh_keepalive_applies_and_records_change() {
    setup_test_env
    local original_resolver=""
    local temp_bin=""

    export DOCTOR_FIX_SSHD_CONFIG="$ACFS_STATE_DIR/sshd_config"
    printf 'Port 22\n' > "$DOCTOR_FIX_SSHD_CONFIG"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    original_resolver="$(declare -f doctor_fix_system_binary_path)"
    temp_bin="$ACFS_STATE_DIR/bin"
    mkdir -p "$temp_bin"
    cat > "$temp_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$temp_bin/sudo" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-n" ]] || exit 42
shift
exec "$@"
EOF
    chmod +x "$temp_bin/systemctl" "$temp_bin/sudo"

    doctor_fix_system_binary_path() {
        case "${1:-}" in
            systemctl|sudo) printf '%s\n' "$temp_bin/${1:-}" ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }

    if ! fix_ssh_keepalive "network.ssh_keepalive" >/dev/null 2>&1; then
        eval "$original_resolver"
        echo "  fix_ssh_keepalive should succeed against an override sshd_config path"
        cleanup_test_env
        return 1
    fi

    if ! grep -q 'ClientAliveInterval 60' "$DOCTOR_FIX_SSHD_CONFIG"; then
        eval "$original_resolver"
        echo "  fix_ssh_keepalive did not append ClientAliveInterval"
        cleanup_test_env
        return 1
    fi

    if ! jq -e --arg path "$DOCTOR_FIX_SSHD_CONFIG" 'select(.description == ("Configured SSH keepalive in " + $path))' "$ACFS_CHANGES_FILE" >/dev/null 2>&1; then
        eval "$original_resolver"
        echo "  fix_ssh_keepalive did not record the keepalive change"
        cleanup_test_env
        return 1
    fi

    eval "$original_resolver"
    cleanup_test_env
    return 0
}

test_fix_ssh_keepalive_refuses_mutation_when_backup_fails() {
    setup_test_env
    local original_resolver=""
    local temp_bin=""

    export DOCTOR_FIX_SSHD_CONFIG="$ACFS_STATE_DIR/sshd_config"
    printf 'Port 22\n' > "$DOCTOR_FIX_SSHD_CONFIG"
    local original_content=""
    local original_create_backup=""
    original_content="$(cat "$DOCTOR_FIX_SSHD_CONFIG")"
    original_create_backup="$(declare -f create_backup)"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    create_backup() { return 1; }
    original_resolver="$(declare -f doctor_fix_system_binary_path)"
    temp_bin="$ACFS_STATE_DIR/bin"
    mkdir -p "$temp_bin"
    cat > "$temp_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$temp_bin/sudo" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-n" ]] || exit 42
shift
exec "$@"
EOF
    chmod +x "$temp_bin/systemctl" "$temp_bin/sudo"

    doctor_fix_system_binary_path() {
        case "${1:-}" in
            systemctl|sudo) printf '%s\n' "$temp_bin/${1:-}" ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }

    if fix_ssh_keepalive "network.ssh_keepalive" >/dev/null 2>&1; then
        eval "$original_resolver"
        eval "$original_create_backup"
        echo "  fix_ssh_keepalive unexpectedly succeeded when backup creation failed"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    eval "$original_resolver"
    eval "$original_create_backup"

    if [[ "$(cat "$DOCTOR_FIX_SSHD_CONFIG")" != "$original_content" ]]; then
        echo "  fix_ssh_keepalive changed sshd_config without a recovery backup"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if grep -q 'ClientAliveInterval 60' "$DOCTOR_FIX_SSHD_CONFIG"; then
        echo "  fix_ssh_keepalive left keepalive settings behind after backup failure"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_FAILED -ne 1 ]]; then
        echo "  FIX_FAILED should be 1 after keepalive backup failure, got $FIX_FAILED"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}

test_fix_dcg_hook_uninstalls_when_record_change_fails() {
    setup_test_env

    local original_record_change=""
    local original_path="$PATH"
    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin" "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
    original_record_change="$(declare -f record_change)"

    cat > "$HOME/.local/bin/dcg" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$ACFS_STATE_DIR/caller-dcg.log"
case "\$1 \${2-} \${3-}" in
    "doctor --format json")
        printf '{"hook_installed":false,"checks":[]}\n'
        exit 0
        ;;
    "install  "|"uninstall  ")
        exit 0
        ;;
esac
exit 1
EOF
    chmod +x "$HOME/.local/bin/dcg"

    cat > "$TARGET_HOME/.local/bin/dcg" <<EOF
#!/usr/bin/env bash
case "\$1 \${2-} \${3-}" in
    "doctor --format json")
        printf '{"hook_installed":false,"checks":[]}\n'
        exit 0
        ;;
    "install  ")
        : > "$ACFS_STATE_DIR/dcg-installed"
        exit 0
        ;;
    "uninstall  ")
        : > "$ACFS_STATE_DIR/dcg-uninstalled"
        exit 0
        ;;
esac
exit 1
EOF
    chmod +x "$TARGET_HOME/.local/bin/dcg"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        export PATH="$original_path"
        cleanup_test_env
        return 1
    }

    record_change() { return 1; }

    if fix_dcg_hook "hook.dcg.test" >/dev/null 2>&1; then
        eval "$original_record_change"
        export PATH="$original_path"
        echo "  fix_dcg_hook unexpectedly succeeded when record_change failed"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    eval "$original_record_change"
    export PATH="$original_path"

    if [[ ! -f "$ACFS_STATE_DIR/dcg-uninstalled" ]]; then
        echo "  fix_dcg_hook did not roll back install after record_change failure"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ -f "$ACFS_STATE_DIR/caller-dcg.log" ]]; then
        echo "  fix_dcg_hook used caller-shell dcg instead of TARGET_HOME dcg"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    if [[ $FIX_FAILED -ne 1 ]]; then
        echo "  FIX_FAILED should be 1 after dcg hook journaling failure, got $FIX_FAILED"
        end_autofix_session >/dev/null 2>&1 || true
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null 2>&1 || true
    cleanup_test_env
    return 0
}
test_dcg_hook_already_installed_detects_hook_wiring() {
    setup_test_env
    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin" "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    cat > "$HOME/.local/bin/dcg" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$ACFS_STATE_DIR/caller-dcg.log"
exit 1
EOF
    chmod +x "$HOME/.local/bin/dcg"

    cat > "$TARGET_HOME/.local/bin/dcg" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "doctor" && "${2:-}" == "--format" && "${3:-}" == "json" ]]; then
    cat <<'JSON_EOF'
{"checks":[{"id":"hook_wiring","status":"ok","message":"dcg hook registered"}]}
JSON_EOF
    exit 0
fi
exit 1
EOF
    chmod +x "$TARGET_HOME/.local/bin/dcg"

    if ! dcg_hook_already_installed; then
        echo "  Expected hook_wiring=ok to be treated as installed"
        cleanup_test_env
        return 1
    fi

    if [[ -f "$ACFS_STATE_DIR/caller-dcg.log" ]]; then
        echo "  dcg_hook_already_installed used caller-shell dcg instead of TARGET_HOME dcg"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}
test_agent_mail_fix_stop_fallback_cleans_up_matching_pid() {
    setup_test_env
    export PATH="$HOME/.local/bin:$PATH"

    mkdir -p "$HOME/.mcp_agent_mail_git_mailbox_repo"
    cat > "$HOME/.local/bin/am" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$HOME/.local/bin/am"

    local fallback_pid_file="$HOME/.mcp_agent_mail_git_mailbox_repo/agent-mail.pid"
    echo "4242" > "$fallback_pid_file"

    kill() {
        if [[ "${1:-}" == "-0" ]]; then
            if [[ "${2:-}" == "4242" && ! -f "$HOME/.terminated" ]]; then
                return 0
            fi
            return 1
        fi

        if [[ "${1:-}" == "4242" ]]; then
            : > "$HOME/.terminated"
            return 0
        fi

        if [[ "${1:-}" == "-9" && "${2:-}" == "4242" ]]; then
            : > "$HOME/.terminated"
            return 0
        fi

        return 1
    }

    ps() {
        if [[ "${1:-}" == "-p" && "${2:-}" == "4242" && "${3:-}" == "-o" && "${4:-}" == "args=" ]]; then
            printf '%s\n' "$HOME/.local/bin/am serve-http --host 127.0.0.1 --port 8765"
            return 0
        fi
        return 1
    }

    if ! agent_mail_fix_stop_fallback; then
        echo "  agent_mail_fix_stop_fallback should succeed"
        unset -f kill ps
        cleanup_test_env
        return 1
    fi

    if [[ -f "$fallback_pid_file" ]]; then
        echo "  Fallback PID file should be removed"
        unset -f kill ps
        cleanup_test_env
        return 1
    fi

    if [[ ! -f "$HOME/.terminated" ]]; then
        echo "  Matching fallback process should have been terminated"
        unset -f kill ps
        cleanup_test_env
        return 1
    fi

    unset -f kill ps
    cleanup_test_env
    return 0
}

test_agent_mail_fix_stop_fallback_recognizes_bare_am_argv() {
    setup_test_env
    export PATH="$HOME/.local/bin:$PATH"

    mkdir -p "$HOME/.mcp_agent_mail_git_mailbox_repo" "$HOME/mcp_agent_mail"
    cat > "$HOME/mcp_agent_mail/am" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$HOME/mcp_agent_mail/am"

    local fallback_pid_file="$HOME/.mcp_agent_mail_git_mailbox_repo/agent-mail.pid"
    echo "4242" > "$fallback_pid_file"

    systemctl() { return 1; }
    kill() {
        if [[ "${1:-}" == "-0" ]]; then
            if [[ "${2:-}" == "4242" && ! -f "$HOME/.terminated" ]]; then
                return 0
            fi
            return 1
        fi
        if [[ "${1:-}" == "4242" ]]; then
            : > "$HOME/.terminated"
            return 0
        fi
        return 1
    }
    ps() {
        printf '%s\n' 'am serve-http --host 127.0.0.1 --port 8765'
    }

    if ! agent_mail_fix_stop_fallback; then
        echo "  bare am fallback owner should be stopped gracefully"
        unset -f systemctl kill ps
        cleanup_test_env
        return 1
    fi

    if [[ ! -f "$HOME/.terminated" ]]; then
        echo "  bare am fallback owner was mistaken for a stale PID"
        unset -f systemctl kill ps
        cleanup_test_env
        return 1
    fi

    if [[ -f "$fallback_pid_file" ]]; then
        echo "  Fallback PID file should be removed after graceful termination"
        unset -f systemctl kill ps
        cleanup_test_env
        return 1
    fi

    unset -f systemctl kill ps
    cleanup_test_env
    return 0
}

test_agent_mail_fix_stop_fallback_requires_exact_server_role() {
    setup_test_env
    export PATH="$HOME/.local/bin:$PATH"

    mkdir -p "$HOME/.mcp_agent_mail_git_mailbox_repo" "$HOME/mcp_agent_mail"
    cat > "$HOME/mcp_agent_mail/am" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$HOME/mcp_agent_mail/am"

    local fallback_pid_file="$HOME/.mcp_agent_mail_git_mailbox_repo/agent-mail.pid"
    local MOCK_AM_ARGS="am doctor health"
    echo "-1" > "$fallback_pid_file"

    systemctl() { return 1; }
    kill() {
        : > "$HOME/.kill-called"
        if [[ "${1:-}" == "-0" ]]; then
            return 0
        fi
        : > "$HOME/.signalled"
        return 0
    }
    ps() {
        printf '%s\n' "$MOCK_AM_ARGS"
    }

    if ! agent_mail_fix_stop_fallback; then
        echo "  malformed PID evidence should be discarded without signalling"
        unset -f systemctl kill ps
        cleanup_test_env
        return 1
    fi
    if [[ -f "$HOME/.kill-called" ]]; then
        echo "  malformed PID evidence reached the kill builtin"
        unset -f systemctl kill ps
        cleanup_test_env
        return 1
    fi

    echo "4242" > "$fallback_pid_file"
    if ! agent_mail_fix_stop_fallback; then
        echo "  unrelated am command should be treated as stale PID evidence"
        unset -f systemctl kill ps
        cleanup_test_env
        return 1
    fi
    if [[ -f "$HOME/.signalled" ]]; then
        echo "  unrelated am command was signalled"
        unset -f systemctl kill ps
        cleanup_test_env
        return 1
    fi

    echo "4242" > "$fallback_pid_file"
    MOCK_AM_ARGS="am serve-http --host 127.0.0.1 --port 8766"
    if ! agent_mail_fix_stop_fallback; then
        echo "  Agent Mail server on another port should be treated as stale PID evidence"
        unset -f systemctl kill ps
        cleanup_test_env
        return 1
    fi
    if [[ -f "$HOME/.signalled" ]]; then
        echo "  Agent Mail server on another port was signalled"
        unset -f systemctl kill ps
        cleanup_test_env
        return 1
    fi

    unset -f systemctl kill ps
    cleanup_test_env
    return 0
}

test_agent_mail_fix_stop_fallback_leaves_systemd_main_pid_to_supervisor() {
    setup_test_env
    export PATH="$HOME/.local/bin:$PATH"

    mkdir -p "$HOME/.mcp_agent_mail_git_mailbox_repo"
    cat > "$HOME/.local/bin/am" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$HOME/.local/bin/am"

    local fallback_pid_file="$HOME/.mcp_agent_mail_git_mailbox_repo/agent-mail.pid"
    echo "4242" > "$fallback_pid_file"

    systemctl() {
        if [[ "${1:-}" == "--user" && "${2:-}" == "show-environment" ]]; then
            return 0
        fi
        if [[ "${1:-}" == "--user" && "${2:-}" == "show" && "${3:-}" == "agent-mail.service" ]]; then
            printf '%s\n' '4242'
            return 0
        fi
        return 1
    }
    kill() {
        if [[ "${1:-}" != "-0" ]]; then
            : > "$HOME/.signalled"
        fi
        return 0
    }

    if ! agent_mail_fix_stop_fallback; then
        echo "  agent_mail_fix_stop_fallback should leave the systemd owner to its supervisor"
        unset -f systemctl kill
        cleanup_test_env
        return 1
    fi

    if [[ -f "$fallback_pid_file" ]]; then
        echo "  Stale fallback PID file should be removed for the systemd-owned MainPID"
        unset -f systemctl kill
        cleanup_test_env
        return 1
    fi

    if [[ -f "$HOME/.signalled" ]]; then
        echo "  systemd-owned Agent Mail process was signalled directly"
        unset -f systemctl kill
        cleanup_test_env
        return 1
    fi

    unset -f systemctl kill
    cleanup_test_env
    return 0
}

test_agent_mail_fix_stop_fallback_refuses_hard_kill() {
    setup_test_env
    export PATH="$HOME/.local/bin:$PATH"

    mkdir -p "$HOME/.mcp_agent_mail_git_mailbox_repo"
    cat > "$HOME/.local/bin/am" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$HOME/.local/bin/am"

    local fallback_pid_file="$HOME/.mcp_agent_mail_git_mailbox_repo/agent-mail.pid"
    echo "4242" > "$fallback_pid_file"

    kill() {
        if [[ "${1:-}" == "-0" && "${2:-}" == "4242" ]]; then
            return 0
        fi
        if [[ "${1:-}" == "-9" ]]; then
            : > "$HOME/.hard-killed"
            return 0
        fi
        return 0
    }
    ps() {
        printf '%s\n' "$HOME/.local/bin/am serve-http --host 127.0.0.1 --port 8765"
    }
    sleep() { :; }

    if agent_mail_fix_stop_fallback >/dev/null 2>&1; then
        echo "  agent_mail_fix_stop_fallback should fail while the owner remains live"
        unset -f kill ps sleep
        cleanup_test_env
        return 1
    fi

    if [[ -f "$HOME/.hard-killed" ]]; then
        echo "  Live Agent Mail owner was hard-killed"
        unset -f kill ps sleep
        cleanup_test_env
        return 1
    fi

    if [[ ! -f "$fallback_pid_file" ]]; then
        echo "  PID evidence should remain when graceful stop fails"
        unset -f kill ps sleep
        cleanup_test_env
        return 1
    fi

    unset -f kill ps sleep
    cleanup_test_env
    return 0
}

test_agent_mail_fix_safe_to_mutate_requires_drain_attestation() {
    setup_test_env
    local fake_am="$HOME/fake-am"

    cat > "$fake_am" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"safe_to_mutate":false}'
EOF
    chmod +x "$fake_am"

    local drain_rc=0
    agent_mail_fix_safe_to_mutate "$fake_am" || drain_rc=$?
    if [[ "$drain_rc" -ne 1 ]]; then
        echo "  Explicit safe_to_mutate=false drain result did not return the live-owner status"
        cleanup_test_env
        return 1
    fi

    cat > "$fake_am" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"message":"reported safe_to_mutate true","result":{"safe_to_mutate":true}}'
EOF
    chmod +x "$fake_am"

    drain_rc=0
    agent_mail_fix_safe_to_mutate "$fake_am" || drain_rc=$?
    if [[ "$drain_rc" -ne 2 ]]; then
        echo "  Nested safe_to_mutate value was not rejected as malformed drain attestation"
        cleanup_test_env
        return 1
    fi

    cat > "$fake_am" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"safe_to_mutate":true}'
EOF
    chmod +x "$fake_am"

    if ! agent_mail_fix_safe_to_mutate "$fake_am"; then
        echo "  Explicit safe_to_mutate=true drain result was rejected"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_mcp_agent_mail_stops_after_failed_database_repair() (
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    export TARGET_USER="$(id -un)"
    mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/mcp_agent_mail"
    export PATH="$TARGET_HOME/.local/bin:$PATH"

    cat > "$TARGET_HOME/mcp_agent_mail/am" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    --version)
        printf '%s\n' 'am 1.0.0'
        ;;
    doctor)
        case "${2:-}" in
            drain)
                printf '%s\n' '{"safe_to_mutate":true}'
                ;;
            repair)
                exit 17
                ;;
            fix)
                : > "$HOME/.doctor-fix-ran-after-repair-failure"
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
esac
EOF
    chmod +x "$TARGET_HOME/mcp_agent_mail/am"
    ln -s "$TARGET_HOME/mcp_agent_mail/am" "$TARGET_HOME/.local/bin/am"

    doctor_fix_runtime_home() { printf '%s\n' "$TARGET_HOME"; }
    doctor_fix_runtime_user() { printf '%s\n' "$TARGET_USER"; }
    doctor_fix_agent_mail_bin() { printf '%s\n' "$TARGET_HOME/mcp_agent_mail/am"; }
    doctor_fix_source_stack_lib() { return 0; }
    _stack_configure_agent_mail_service() { return 75; }
    doctor_fix_system_curl() { return 0; }
    agent_mail_fix_readiness_ready() { return 0; }
    agent_mail_fix_doctor_healthy() { return 0; }

    FIX_FAILED=0
    if fix_mcp_agent_mail "fix.stack.mcp_agent_mail" >/dev/null 2>&1; then
        echo "  fix_mcp_agent_mail reported success after database repair failed"
        cleanup_test_env
        return 1
    fi

    if [[ -f "$HOME/.doctor-fix-ran-after-repair-failure" ]]; then
        echo "  doctor fix ran after database repair failed"
        cleanup_test_env
        return 1
    fi

    if [[ "$FIX_FAILED" -ne 1 ]]; then
        echo "  failed database repair was not counted exactly once"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
)

test_fix_mcp_agent_mail_does_not_mask_service_failure_with_healthy_process() (
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    export TARGET_USER="$(id -un)"
    mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/mcp_agent_mail"
    export PATH="$TARGET_HOME/.local/bin:$PATH"

    cat > "$TARGET_HOME/mcp_agent_mail/am" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    --version)
        printf '%s\n' 'am 1.0.0'
        ;;
    doctor)
        case "${2:-}" in
            drain)
                printf '%s\n' '{"safe_to_mutate":false}'
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
esac
EOF
    chmod +x "$TARGET_HOME/mcp_agent_mail/am"
    ln -s "$TARGET_HOME/mcp_agent_mail/am" "$TARGET_HOME/.local/bin/am"

    doctor_fix_runtime_home() { printf '%s\n' "$TARGET_HOME"; }
    doctor_fix_runtime_user() { printf '%s\n' "$TARGET_USER"; }
    doctor_fix_agent_mail_bin() { printf '%s\n' "$TARGET_HOME/mcp_agent_mail/am"; }
    doctor_fix_source_stack_lib() { return 0; }
    _stack_configure_agent_mail_service() { return 1; }
    doctor_fix_system_curl() { return 0; }
    agent_mail_fix_readiness_ready() { return 0; }
    agent_mail_fix_doctor_healthy() { return 0; }

    FIX_FAILED=0
    if fix_mcp_agent_mail "fix.stack.mcp_agent_mail" >/dev/null 2>&1; then
        echo "  fix_mcp_agent_mail masked a service-management failure with old-process health"
        cleanup_test_env
        return 1
    fi

    if [[ "$FIX_FAILED" -ne 1 ]]; then
        echo "  service-management failure was not counted exactly once"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
)

test_fix_mcp_agent_mail_requires_fresh_health_after_service_restart() (
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    export TARGET_USER="$(id -un)"
    mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/mcp_agent_mail"
    export PATH="$TARGET_HOME/.local/bin:$PATH"

    cat > "$TARGET_HOME/mcp_agent_mail/am" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    --version)
        printf '%s\n' 'am 1.0.0'
        ;;
    doctor)
        case "${2:-}" in
            drain)
                printf '%s\n' '{"safe_to_mutate":false}'
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
esac
EOF
    chmod +x "$TARGET_HOME/mcp_agent_mail/am"
    ln -s "$TARGET_HOME/mcp_agent_mail/am" "$TARGET_HOME/.local/bin/am"

    doctor_fix_runtime_home() { printf '%s\n' "$TARGET_HOME"; }
    doctor_fix_runtime_user() { printf '%s\n' "$TARGET_USER"; }
    doctor_fix_agent_mail_bin() { printf '%s\n' "$TARGET_HOME/mcp_agent_mail/am"; }
    doctor_fix_source_stack_lib() { return 0; }
    _stack_configure_agent_mail_service() { return 0; }
    doctor_fix_record_change_or_rollback() { return 0; }
    doctor_fix_system_curl() { return 0; }
    agent_mail_fix_readiness_ready() { return 0; }
    agent_mail_fix_wait_for_health() { return 1; }
    agent_mail_fix_doctor_healthy() { return 0; }

    FIX_FAILED=0
    FIX_APPLIED=0
    FIXES_APPLIED=()
    if fix_mcp_agent_mail "fix.stack.mcp_agent_mail" >/dev/null 2>&1; then
        echo "  fix_mcp_agent_mail reused stale pre-restart health after readiness failed"
        cleanup_test_env
        return 1
    fi

    if [[ "$FIX_FAILED" -ne 1 ]]; then
        echo "  failed post-restart readiness was not counted exactly once"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
)

test_agent_mail_fix_write_unit_prefers_target_install_over_current_shell_am() {
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/mcp_agent_mail" "$HOME/current-shell-bin"
    export PATH="$HOME/current-shell-bin:$PATH"

    cat > "$HOME/current-shell-bin/am" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    echo "mcp-agent-mail 0.2.19"
    exit 0
fi
: > "$HOME/global-am-used"
exit 0
EOF
    chmod +x "$HOME/current-shell-bin/am"

    cat > "$TARGET_HOME/mcp_agent_mail/am" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    echo "am 1.0.0"
    exit 0
fi
exit 0
EOF
    chmod +x "$TARGET_HOME/mcp_agent_mail/am"

    if ! agent_mail_fix_write_unit; then
        echo "  agent_mail_fix_write_unit should succeed"
        cleanup_test_env
        return 1
    fi

    if [[ ! -f "$TARGET_HOME/.config/systemd/user/agent-mail.service" ]]; then
        echo "  Agent Mail unit file was not written"
        cleanup_test_env
        return 1
    fi

    if ! grep -Fq "ExecStart=\"$TARGET_HOME/mcp_agent_mail/am\" serve-http" "$TARGET_HOME/.config/systemd/user/agent-mail.service"; then
        echo "  Agent Mail unit did not use the target install binary"
        cleanup_test_env
        return 1
    fi

    if ! grep -Fq 'Environment="HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED=true"' "$TARGET_HOME/.config/systemd/user/agent-mail.service"; then
        echo "  Agent Mail unit did not allow localhost unauthenticated HTTP"
        cleanup_test_env
        return 1
    fi

    if [[ -f "$HOME/global-am-used" ]]; then
        echo "  agent_mail_fix_write_unit should not invoke the current-shell am"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_agent_mail_fix_write_unit_escapes_systemd_values() {
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target home 100% \$cash"
    mkdir -p "$TARGET_HOME/mcp_agent_mail"

    cat > "$TARGET_HOME/mcp_agent_mail/am" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    echo "am 1.0.0"
    exit 0
fi
exit 0
EOF
    chmod +x "$TARGET_HOME/mcp_agent_mail/am"

    if ! agent_mail_fix_write_unit; then
        echo "  agent_mail_fix_write_unit should succeed for systemd-special paths"
        cleanup_test_env
        return 1
    fi

    local unit_file="$TARGET_HOME/.config/systemd/user/agent-mail.service"
    local storage_root="$TARGET_HOME/.mcp_agent_mail_git_mailbox_repo"
    local db_url="sqlite:///${storage_root}/storage.sqlite3"
    local expected_working_dir=""
    local expected_storage_env=""
    local expected_db_env=""
    local expected_am_bin=""
    local expected_mcp_path=""

    expected_working_dir="$(doctor_fix_systemd_unit_path_escape "$storage_root")"
    expected_storage_env="$(doctor_fix_systemd_unit_env_assignment STORAGE_ROOT "$storage_root")"
    expected_db_env="$(doctor_fix_systemd_unit_env_assignment DATABASE_URL "$db_url")"
    expected_am_bin="$(doctor_fix_systemd_unit_exec_command "$TARGET_HOME/mcp_agent_mail/am")"
    expected_mcp_path="$(doctor_fix_systemd_unit_exec_arg "/mcp/")"

    if ! grep -Fxq "WorkingDirectory=$expected_working_dir" "$unit_file"; then
        echo "  Agent Mail unit did not escape WorkingDirectory for systemd"
        cleanup_test_env
        return 1
    fi

    if ! grep -Fxq "Environment=$expected_storage_env" "$unit_file"; then
        echo "  Agent Mail unit did not quote STORAGE_ROOT for systemd"
        cleanup_test_env
        return 1
    fi

    if ! grep -Fxq "Environment=$expected_db_env" "$unit_file"; then
        echo "  Agent Mail unit did not quote DATABASE_URL for systemd"
        cleanup_test_env
        return 1
    fi

    if ! grep -Fxq "ExecStart=${expected_am_bin} serve-http --no-tui --host 127.0.0.1 --port 8765 --path ${expected_mcp_path}" "$unit_file"; then
        echo "  Agent Mail unit did not quote ExecStart arguments for systemd"
        cleanup_test_env
        return 1
    fi

    if grep -Fq "ExecStartPre=" "$unit_file"; then
        echo "  Agent Mail unit should not block serve-http startup behind a pre-start migration"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_mcp_agent_mail_repairs_missing_symlink_without_using_current_shell_am() {
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/mcp_agent_mail" "$HOME/current-shell-bin"
    export PATH="$HOME/current-shell-bin:$TARGET_HOME/.local/bin:$PATH"
    export ACFS_BIN_DIR="relative/bin"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    cat > "$HOME/current-shell-bin/am" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    echo "mcp-agent-mail 0.2.19"
    exit 0
fi
: > "$HOME/global-am-used"
if [[ "${1:-}" == "doctor" ]]; then
    case "${2:-}" in
        repair|fix)
            exit 0
            ;;
        check)
            echo '{"healthy":true}'
            exit 0
            ;;
    esac
fi
exit 0
EOF
    chmod +x "$HOME/current-shell-bin/am"

    cat > "$HOME/current-shell-bin/curl" <<'EOF'
#!/usr/bin/env bash
: > "$HOME/global-curl-used"
exit 1
EOF
    chmod +x "$HOME/current-shell-bin/curl"

    cat > "$TARGET_HOME/mcp_agent_mail/am" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    --version)
        echo "am 1.0.0"
        ;;
    doctor)
        case "${2:-}" in
            drain)
                echo '{"safe_to_mutate":true}'
                ;;
            repair|fix)
                exit 0
                ;;
            check)
                echo '{"healthy":true}'
                ;;
            *)
                exit 1
                ;;
        esac
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$TARGET_HOME/mcp_agent_mail/am"

    cat > "$TARGET_HOME/.local/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$HOME" >> "${TARGET_HOME}/systemctl-home.log"
case "${2:-}" in
    show-environment|daemon-reload|enable|restart|is-active)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$TARGET_HOME/.local/bin/systemctl"

    cat > "$TARGET_HOME/.local/bin/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *"/health"*)
        printf '%s\n' '{"status":"ready"}'
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$TARGET_HOME/.local/bin/curl"

    stub_doctor_fix_agent_mail_health_ready

    if ! fix_mcp_agent_mail "fix.stack.mcp_agent_mail" >/dev/null 2>&1; then
        echo "  fix_mcp_agent_mail should succeed when only the direct install exists"
        cleanup_test_env
        return 1
    fi

    if [[ ! -L "$TARGET_HOME/.local/bin/am" ]]; then
        echo "  Agent Mail symlink was not created"
        cleanup_test_env
        return 1
    fi

    if [[ "$(readlink "$TARGET_HOME/.local/bin/am")" != "$TARGET_HOME/mcp_agent_mail/am" ]]; then
        echo "  Agent Mail symlink did not point at the installed Rust CLI"
        cleanup_test_env
        return 1
    fi

    if [[ -f "$HOME/global-am-used" ]]; then
        echo "  fix_mcp_agent_mail should not invoke the current-shell am"
        cleanup_test_env
        return 1
    fi

    if [[ -f "$HOME/global-curl-used" ]]; then
        echo "  fix_mcp_agent_mail should not invoke the current-shell curl"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_mcp_agent_mail_uses_target_home_for_systemctl_env() {
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/mcp_agent_mail" "$HOME/current-shell-bin"
    export PATH="$HOME/current-shell-bin:$TARGET_HOME/.local/bin:$PATH"
    export ACFS_BIN_DIR="relative/bin"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    cat > "$TARGET_HOME/.local/bin/am" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    --version)
        echo "am 1.0.0"
        ;;
    doctor)
        case "${2:-}" in
            drain)
                echo '{"safe_to_mutate":true}'
                ;;
            repair|fix)
                exit 0
                ;;
            check)
                echo '{"healthy":true}'
                ;;
            *)
                exit 1
                ;;
        esac
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$TARGET_HOME/.local/bin/am"

    cat > "$HOME/current-shell-bin/curl" <<'EOF'
#!/usr/bin/env bash
: > "$HOME/global-curl-used"
exit 1
EOF
    chmod +x "$HOME/current-shell-bin/curl"

    cat > "$TARGET_HOME/.local/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$HOME" >> "${TARGET_HOME}/systemctl-home.log"
case "${2:-}" in
    show-environment|daemon-reload|enable|restart|is-active)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$TARGET_HOME/.local/bin/systemctl"

    cat > "$TARGET_HOME/.local/bin/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *"/health"*)
        printf '%s\n' '{"status":"ready"}'
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$TARGET_HOME/.local/bin/curl"

    stub_doctor_fix_agent_mail_health_ready

    if ! fix_mcp_agent_mail "fix.stack.mcp_agent_mail" >/dev/null 2>&1; then
        echo "  fix_mcp_agent_mail should succeed"
        cleanup_test_env
        return 1
    fi

    if [[ ! -f "$TARGET_HOME/.config/systemd/user/agent-mail.service" ]]; then
        echo "  Agent Mail user unit was not written into TARGET_HOME"
        cleanup_test_env
        return 1
    fi

    if [[ -f "$HOME/.config/systemd/user/agent-mail.service" ]]; then
        echo "  Agent Mail user unit was written into caller HOME unexpectedly"
        cleanup_test_env
        return 1
    fi

    if [[ ! -f "$TARGET_HOME/systemctl-home.log" ]]; then
        echo "  systemctl stub did not record HOME"
        cleanup_test_env
        return 1
    fi

    if grep -Fxq "$HOME" "$TARGET_HOME/systemctl-home.log"; then
        echo "  systemctl received caller HOME unexpectedly"
        cleanup_test_env
        return 1
    fi

    if ! grep -Fxq "$TARGET_HOME" "$TARGET_HOME/systemctl-home.log"; then
        echo "  systemctl did not receive TARGET_HOME"
        cleanup_test_env
        return 1
    fi

    if [[ -f "$HOME/global-curl-used" ]]; then
        echo "  fix_mcp_agent_mail should not invoke the current-shell curl"
        cleanup_test_env
        return 1
    fi

    if ! jq -e 'select(.description == "Ran MCP Agent Mail database repair")' "$ACFS_CHANGES_FILE" >/dev/null 2>&1; then
        echo "  MCP Agent Mail repair was not recorded in the autofix journal"
        cleanup_test_env
        return 1
    fi

    if ! jq -e 'select(.description == "Applied MCP Agent Mail doctor fixes")' "$ACFS_CHANGES_FILE" >/dev/null 2>&1; then
        echo "  MCP Agent Mail doctor fix was not recorded in the autofix journal"
        cleanup_test_env
        return 1
    fi

    if ! jq -e 'select(.description == "Repaired MCP Agent Mail managed service")' "$ACFS_CHANGES_FILE" >/dev/null 2>&1; then
        echo "  MCP Agent Mail service repair was not recorded in the autofix journal"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_fix_mcp_agent_mail_dry_run_reports_symlink_and_repair() {
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/mcp_agent_mail"
    export PATH="$TARGET_HOME/.local/bin:$PATH"

    cat > "$TARGET_HOME/.local/bin/am" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TARGET_HOME/.local/bin/am"
    local original_cli_checksum=""
    original_cli_checksum="$(calculate_backup_checksum "$TARGET_HOME/.local/bin/am")"

    cat > "$TARGET_HOME/mcp_agent_mail/am" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    --version)
        echo "am 1.0.0"
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$TARGET_HOME/mcp_agent_mail/am"

    DOCTOR_FIX_DRY_RUN=true
    FIXES_DRY_RUN=()

    if ! fix_mcp_agent_mail "fix.stack.mcp_agent_mail" >/dev/null 2>&1; then
        echo "  fix_mcp_agent_mail dry-run should succeed"
        DOCTOR_FIX_DRY_RUN=false
        cleanup_test_env
        return 1
    fi

    if ! printf '%s\n' "${FIXES_DRY_RUN[@]}" | grep -Fq 'fix.stack.mcp_agent_mail.symlink|Ensure am symlink points at installed Rust CLI'; then
        echo "  dry-run did not report the Agent Mail symlink repair"
        DOCTOR_FIX_DRY_RUN=false
        cleanup_test_env
        return 1
    fi

    if ! printf '%s\n' "${FIXES_DRY_RUN[@]}" | grep -Fq 'fix.stack.mcp_agent_mail|Inspect MCP Agent Mail drain state, repair only when safe_to_mutate=true'; then
        echo "  dry-run stopped after symlink repair and did not report the main Agent Mail repair"
        DOCTOR_FIX_DRY_RUN=false
        cleanup_test_env
        return 1
    fi

    if [[ "$(calculate_backup_checksum "$TARGET_HOME/.local/bin/am")" != "$original_cli_checksum" ]]; then
        echo "  dry-run modified the existing Agent Mail CLI entry"
        DOCTOR_FIX_DRY_RUN=false
        cleanup_test_env
        return 1
    fi

    if find "$ACFS_BACKUPS_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
        echo "  dry-run created an autofix backup"
        DOCTOR_FIX_DRY_RUN=false
        cleanup_test_env
        return 1
    fi

    DOCTOR_FIX_DRY_RUN=false
    cleanup_test_env
    return 0
}

test_fix_mcp_agent_mail_fails_when_symlink_repair_fails() {
    setup_test_env

    export TARGET_HOME="$ACFS_STATE_DIR/target-home"
    mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/mcp_agent_mail"
    export PATH="$TARGET_HOME/.local/bin:$PATH"

    start_autofix_session >/dev/null || {
        echo "  Failed to start autofix session"
        cleanup_test_env
        return 1
    }

    cat > "$TARGET_HOME/.local/bin/am" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TARGET_HOME/.local/bin/am"
    local original_cli_checksum=""
    original_cli_checksum="$(calculate_backup_checksum "$TARGET_HOME/.local/bin/am")"

    cat > "$TARGET_HOME/mcp_agent_mail/am" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    --version)
        echo "am 1.0.0"
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$TARGET_HOME/mcp_agent_mail/am"

    _stack_repair_agent_mail_cli_symlink() {
        ln -sfn "$TARGET_HOME/mcp_agent_mail/am" "$TARGET_HOME/.local/bin/am"
        return 1
    }

    if fix_mcp_agent_mail "fix.stack.mcp_agent_mail" >/dev/null 2>&1; then
        echo "  fix_mcp_agent_mail should fail when the am symlink repair fails"
        cleanup_test_env
        return 1
    fi

    if [[ -s "$ACFS_CHANGES_FILE" ]]; then
        echo "  fix_mcp_agent_mail should not record changes when symlink repair fails before repair work starts"
        cleanup_test_env
        return 1
    fi

    if [[ -L "$TARGET_HOME/.local/bin/am" ]] ||
       [[ "$(calculate_backup_checksum "$TARGET_HOME/.local/bin/am")" != "$original_cli_checksum" ]]; then
        echo "  fix_mcp_agent_mail did not restore the original CLI after a partial symlink repair"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# ============================================================
# Test: dispatch_fix routing
# ============================================================

test_dispatch_fix_skips_pass() {
    setup_test_env

    # Dispatch should skip passing checks
    dispatch_fix "path.ordering" "pass" ""

    if [[ $FIX_APPLIED -ne 0 ]] && [[ $FIX_SKIPPED -ne 0 ]]; then
        echo "  Should not apply or skip fixes for pass status"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_dispatch_fix_skips_skip() {
    setup_test_env

    # Dispatch should skip skipped checks
    dispatch_fix "path.ordering" "skip" ""

    if [[ $FIX_APPLIED -ne 0 ]] && [[ $FIX_SKIPPED -ne 0 ]]; then
        echo "  Should not apply or skip fixes for skip status"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_dispatch_fix_routes_path() {
    setup_test_env

    # Create .zshrc
    local zshrc="$HOME/.zshrc"
    echo "# Initial zshrc" > "$zshrc"

    # Initialize autofix session
    start_autofix_session >/dev/null

    # Dispatch should route to fix_path_ordering
    dispatch_fix "path.ordering" "fail" "" >/dev/null 2>&1

    # Verify fixer was called
    if ! grep -q "# ACFS PATH ordering" "$zshrc"; then
        echo "  path.* check did not route to fix_path_ordering"
        cleanup_test_env
        return 1
    fi

    end_autofix_session >/dev/null
    cleanup_test_env
    return 0
}

test_dispatch_fix_routes_manual() {
    setup_test_env

    # Dispatch manual check with hint
    dispatch_fix "shell.ohmyzsh" "fail" "curl -fsSL ... | bash" >/dev/null 2>&1

    # Verify manual fix recorded
    if [[ $FIX_MANUAL -ne 1 ]]; then
        echo "  FIX_MANUAL should be 1, got $FIX_MANUAL"
        cleanup_test_env
        return 1
    fi

    # Verify manual entry added
    if [[ ${#FIXES_MANUAL[@]} -ne 1 ]]; then
        echo "  Expected 1 manual fix, got ${#FIXES_MANUAL[@]}"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_dispatch_fix_unknown_skipped() {
    setup_test_env

    # Dispatch unknown check ID
    dispatch_fix "unknown.check.id" "fail" "" >/dev/null 2>&1

    # Verify skipped
    if [[ $FIX_SKIPPED -ne 1 ]]; then
        echo "  FIX_SKIPPED should be 1, got $FIX_SKIPPED"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# ============================================================
# Test: print_fix_summary
# ============================================================

test_print_fix_summary_dry_run() {
    setup_test_env

    DOCTOR_FIX_DRY_RUN=true
    FIXES_DRY_RUN+=("fix.test|Test action|/test/file|test command")

    local output
    output=$(print_fix_summary 2>&1)

    # Verify dry-run mode indicated
    if ! echo "$output" | grep -q "DRY-RUN"; then
        echo "  Dry-run mode not indicated in summary"
        cleanup_test_env
        return 1
    fi

    # Verify fix listed
    if ! echo "$output" | grep -q "fix.test"; then
        echo "  Fix not listed in summary"
        cleanup_test_env
        return 1
    fi

    DOCTOR_FIX_DRY_RUN=false
    cleanup_test_env
    return 0
}

test_print_fix_summary_applied() {
    setup_test_env

    FIX_APPLIED=2
    FIX_SKIPPED=1
    FIX_FAILED=0
    FIX_MANUAL=1
    FIXES_APPLIED+=("fix.one|First fix")
    FIXES_APPLIED+=("fix.two|Second fix")
    FIXES_MANUAL+=("fix.manual|Manual action|run this command")

    local output
    output=$(print_fix_summary 2>&1)

    # Verify counts
    if ! echo "$output" | grep -q "Applied: 2"; then
        echo "  Applied count not shown correctly"
        cleanup_test_env
        return 1
    fi

    # Verify manual section
    if ! echo "$output" | grep -q "Manual fixes needed"; then
        echo "  Manual fixes section not shown"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

# ============================================================
# Test: run_doctor_fix initialization
# ============================================================

test_run_doctor_fix_init() {
    setup_test_env

    # Run initialization
    run_doctor_fix >/dev/null 2>&1

    # Verify counters reset
    if [[ $FIX_APPLIED -ne 0 ]] || [[ $FIX_SKIPPED -ne 0 ]] || [[ $FIX_FAILED -ne 0 ]]; then
        echo "  Counters not reset"
        cleanup_test_env
        return 1
    fi

    cleanup_test_env
    return 0
}

test_run_doctor_fix_dry_run_flag() {
    setup_test_env

    # Run with dry-run flag
    run_doctor_fix --dry-run >/dev/null 2>&1

    # Verify dry-run mode enabled
    if [[ "$DOCTOR_FIX_DRY_RUN" != "true" ]]; then
        echo "  Dry-run mode not enabled"
        cleanup_test_env
        return 1
    fi

    DOCTOR_FIX_DRY_RUN=false
    cleanup_test_env
    return 0
}

# ============================================================
# Run all tests
# ============================================================

main() {
    echo "============================================================"
    echo "Doctor Fix Unit Tests"
    echo "============================================================"

    # Helper tests
    run_test test_file_contains_line
    run_test test_doctor_fix_prefers_target_home_for_autofix_state
    run_test test_doctor_fix_prefers_target_home_over_poisoned_acfs_home
    run_test test_doctor_fix_binary_path_ignores_relative_bin_dir
    run_test test_doctor_fix_runtime_path_ignores_relative_bin_dir
    run_test test_doctor_fix_runtime_path_prefers_system_bins_over_current_shell_path
    run_test test_doctor_fix_runtime_home_ignores_relative_home
    run_test test_doctor_fix_runtime_home_fails_closed_for_different_unresolved_target
    run_test test_doctor_fix_runtime_home_prefers_target_user_passwd_home_over_stale_target_home
    run_test test_doctor_fix_runtime_home_rejects_invalid_target_user_before_target_home
    run_test test_doctor_fix_runtime_home_fails_closed_for_unresolved_target_with_stale_target_home
    run_test test_doctor_fix_runtime_bin_dir_ignores_other_user_bin_dir
    run_test test_doctor_fix_binary_path_ignores_other_user_bin_dir
    run_test test_doctor_fix_run_rollback_command_uses_system_bash_and_clean_path
    run_test test_doctor_fix_run_rollback_command_requires_root_fails_without_sudo
    run_test test_doctor_fix_run_rollback_command_uses_noninteractive_sudo
    run_test test_doctor_fix_files_json_escapes_special_paths

    # fix_path_ordering tests
    run_test test_fix_path_ordering_applies
    run_test test_fix_path_ordering_idempotent
    run_test test_fix_path_ordering_repairs_stale_marker_missing_atuin
    run_test test_fix_path_ordering_dry_run
    run_test test_fix_path_ordering_restores_file_when_record_change_fails
    run_test test_fix_path_ordering_removes_new_file_when_record_change_fails
    run_test test_fix_path_ordering_refuses_existing_file_when_backup_fails

    # fix_config_copy tests
    run_test test_fix_config_copy_applies
    run_test test_fix_config_copy_idempotent
    run_test test_fix_config_copy_missing_source
    run_test test_fix_config_copy_dry_run
    run_test test_fix_config_copy_removes_dest_when_record_change_fails
    run_test test_fix_config_copy_removes_created_dirs_when_record_change_fails
    run_test test_fix_config_copy_cleans_created_dirs_on_copy_failure

    # fix_symlink_create tests
    run_test test_fix_symlink_create_applies
    run_test test_fix_symlink_create_idempotent
    run_test test_fix_symlink_create_missing_binary
    run_test test_fix_symlink_create_dry_run
    run_test test_fix_symlink_create_removes_symlink_when_record_change_fails
    run_test test_fix_symlink_create_removes_created_dirs_when_record_change_fails
    run_test test_fix_symlink_create_cleans_created_dirs_on_symlink_failure
    run_test test_fix_plugin_clone_removes_created_dirs_when_record_change_fails
    run_test test_fix_plugin_clone_cleans_partial_clone_on_clone_failure

    # fix_acfs_sourcing tests
    run_test test_fix_acfs_sourcing_applies
    run_test test_fix_acfs_sourcing_idempotent
    run_test test_fix_acfs_sourcing_ignores_commented_loader_mention
    run_test test_fix_acfs_sourcing_uses_target_home
    run_test test_fix_acfs_sourcing_missing_acfs_config
    run_test test_fix_acfs_sourcing_dry_run
    run_test test_fix_acfs_sourcing_removes_new_file_when_record_change_fails
    run_test test_fix_acfs_sourcing_refuses_existing_file_when_backup_fails
    run_test test_fix_stack_install_applies_and_records_change
    run_test test_fix_stack_install_uses_target_runtime_home
    run_test test_fix_stack_install_runs_from_target_runtime_home
    run_test test_fix_stack_install_fails_when_binary_missing_after_successful_command
    run_test test_fix_stack_install_removes_binary_when_record_change_fails

    # fix_verified_install tests
    run_test test_fix_verified_install_applies
    run_test test_fix_verified_install_uses_target_runtime_home
    run_test test_fix_verified_install_dry_run
    run_test test_dispatch_fix_routes_cass_with_target_tmpdir
    run_test test_doctor_fix_build_runtime_env_args_accepts_multiple_env_assignments
    run_test test_fix_verified_install_ignores_gcloud_bv_shadow
    run_test test_fix_verified_install_ms_arm64_fallback_uses_cargo
    run_test test_fix_verified_install_removes_binary_when_record_change_fails
    run_test test_fix_ssh_server_records_change_when_enabling_service
    run_test test_fix_ssh_server_fails_when_service_enable_fails
    run_test test_fix_ssh_keepalive_applies_and_records_change
    run_test test_fix_ssh_keepalive_refuses_mutation_when_backup_fails
    run_test test_fix_dcg_hook_uninstalls_when_record_change_fails
    run_test test_dcg_hook_already_installed_detects_hook_wiring
    run_test test_agent_mail_fix_stop_fallback_cleans_up_matching_pid
    run_test test_agent_mail_fix_stop_fallback_recognizes_bare_am_argv
    run_test test_agent_mail_fix_stop_fallback_requires_exact_server_role
    run_test test_agent_mail_fix_stop_fallback_leaves_systemd_main_pid_to_supervisor
    run_test test_agent_mail_fix_stop_fallback_refuses_hard_kill
    run_test test_agent_mail_fix_safe_to_mutate_requires_drain_attestation
    run_test test_fix_mcp_agent_mail_stops_after_failed_database_repair
    run_test test_fix_mcp_agent_mail_does_not_mask_service_failure_with_healthy_process
    run_test test_fix_mcp_agent_mail_requires_fresh_health_after_service_restart
    run_test test_agent_mail_fix_write_unit_prefers_target_install_over_current_shell_am
    run_test test_agent_mail_fix_write_unit_escapes_systemd_values
    run_test test_fix_mcp_agent_mail_repairs_missing_symlink_without_using_current_shell_am
    run_test test_fix_mcp_agent_mail_uses_target_home_for_systemctl_env
    run_test test_fix_mcp_agent_mail_dry_run_reports_symlink_and_repair
    run_test test_fix_mcp_agent_mail_fails_when_symlink_repair_fails

    # dispatch_fix tests
    run_test test_dispatch_fix_skips_pass
    run_test test_dispatch_fix_skips_skip
    run_test test_dispatch_fix_routes_path
    run_test test_dispatch_fix_config_copy_uses_target_home
    run_test test_dispatch_fix_symlink_uses_target_home
    run_test test_dispatch_fix_routes_manual
    run_test test_dispatch_fix_unknown_skipped

    # print_fix_summary tests
    run_test test_print_fix_summary_dry_run
    run_test test_print_fix_summary_applied

    # run_doctor_fix tests
    run_test test_run_doctor_fix_init
    run_test test_run_doctor_fix_dry_run_flag

    # Summary
    echo ""
    echo "============================================================"
    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_RUN total"
    echo "============================================================"

    # Log results
    local log_file="/tmp/acfs_doctor_fix_test_$(date +%Y%m%d_%H%M%S).log"
    {
        echo "Doctor Fix Test Results"
        echo "Date: $(date)"
        echo "Passed: $TESTS_PASSED"
        echo "Failed: $TESTS_FAILED"
        echo "Total: $TESTS_RUN"
    } > "$log_file"
    echo "Log written to: $log_file"

    # Final cleanup
    cleanup_test_env

    # Exit with appropriate code
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
