#!/usr/bin/env bats
# ============================================================
# Unit tests for installer APT lock timeout handling (bd-9blsl)
# ============================================================

load '../test_helper'

setup() {
    common_setup
}

teardown() {
    common_teardown
}

@test "installer: ensure_base_deps passes DPkg::Lock::Timeout=120 to apt-get" {
    local fake_bin="$BATS_TEST_TMPDIR/fake_bin"
    mkdir -p "$fake_bin"
    local log_file="$BATS_TEST_TMPDIR/apt_calls.log"

    cat > "$fake_bin/apt-get" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$log_file"
exit 0
EOF
    chmod +x "$fake_bin/apt-get"
    cat > "$fake_bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
    chmod +x "$fake_bin/sudo"

    run env PATH="$fake_bin:$PATH" DRY_RUN="false" FAKE_SUDO="$fake_bin/sudo" bash -c '
        acfs_early_system_binary_path() { echo "$1"; }
        acfs_early_sudo_binary_path() { echo "$FAKE_SUDO"; }
        log_detail() { :; }
        try_step() { shift; "$@"; }
        eval "$(sed -n "/^ensure_base_deps() {/,/^}/p" install.sh)"
        ensure_base_deps
    '
    assert_success

    # Verify both update and install calls used -o DPkg::Lock::Timeout=120
    run grep -F "DPkg::Lock::Timeout=120" "$log_file"
    assert_success
    [ "$(grep -c "DPkg::Lock::Timeout=120" "$log_file")" -ge 2 ]
}

@test "installer: canonical manifest apt-get commands wait for the dpkg lock" {
    run bash -c '
        grep "apt-get" acfs.manifest.yaml | \
            grep -v "^[[:space:]]*#" | \
            grep -v "DPkg::Lock::Timeout=120" || true
    '
    assert_success
    assert_output ""
}

@test "installer: gum outer timeout leaves time to operate after lock acquisition" {
    local timeout_log="$BATS_TEST_TMPDIR/gum_timeout_calls.log"
    local apt_log="$BATS_TEST_TMPDIR/gum_apt_calls.log"

    # Exercise the actual bootstrap function with inert commands. This checks
    # the timeout and lock-wait budgets independently of sudo/session ordering.
    run env TEST_TIMEOUT_LOG="$timeout_log" TEST_APT_LOG="$apt_log" bash -c '
        set -euo pipefail
        ACFS_DISTRO_FAMILY=ubuntu
        ACFS_EARLY_CURL_ARGS=()
        DRY_RUN=false
        PRINT_MODE=false
        HAS_GUM=false
        _acfs_os_release_field() { printf "24.04\n"; }
        acfs_early_system_binary_path() {
            [[ "$1" != gum ]] || return 1
            printf "fixture_%s\n" "$1"
        }
        acfs_early_sudo_binary_path() { printf "fixture_sudo\n"; }
        fixture_sudo() { "$@"; }
        fixture_curl() { printf "fixture-key\n"; }
        fixture_gpg() { cat >/dev/null; }
        fixture_mkdir() { :; }
        fixture_tee() { cat >/dev/null; }
        fixture_env() {
            [[ "$1" == DEBIAN_FRONTEND=noninteractive ]] || return 97
            shift
            DEBIAN_FRONTEND=noninteractive "$@"
        }
        fixture_bash() {
            [[ "$1" == -p && "$2" == -c ]] || return 97
            local runner="$3"
            shift 3
            shift # bash -c command name
            ( eval "$runner" )
        }
        fixture_setsid() {
            [[ "$1" == --wait ]] || return 97
            shift
            "$@"
        }
        fixture_timeout() {
            while [[ "$1" == -* ]]; do
                case "$1" in
                    --kill-after=*) shift ;;
                    *) return 97 ;;
                esac
            done
            printf "%s\n" "$1" >> "$TEST_TIMEOUT_LOG"
            [[ "$1" == 300 ]] || return 98
            shift
            "$@"
        }
        fixture_apt-get() {
            [[ "${DEBIAN_FRONTEND:-}" == noninteractive ]] || return 97
            printf "%s\n" "$*" >> "$TEST_APT_LOG"
            [[ "$*" == *"DPkg::Lock::Timeout=120"* ]] || return 98
        }
        eval "$(sed -n "/^acfs_run_early_apt() {/,/^}/p" install.sh)"
        eval "$(sed -n "/^install_gum_early() {/,/^}/p" install.sh)"
        install_gum_early
        [[ "$HAS_GUM" == true ]]
    '
    assert_success
    [ "$(grep -c '^300$' "$timeout_log")" -eq 2 ]
    [ "$(wc -l < "$timeout_log")" -eq 2 ]
    [ "$(grep -c 'DPkg::Lock::Timeout=120 update ' "$apt_log")" -eq 1 ]
    [ "$(grep -c 'DPkg::Lock::Timeout=120 install ' "$apt_log")" -eq 1 ]
    [ "$(wc -l < "$apt_log")" -eq 2 ]
}

@test "installer: Agent Mail service migration never hard-kills a live owner" {
    run grep -F 'kill -9 "$existing_pid"' install.sh acfs.manifest.yaml
    assert_failure

    run grep -F 'did not stop after SIGTERM; refusing a hard kill' install.sh acfs.manifest.yaml
    assert_success

    run grep -F 'systemctl --user show agent-mail.service -p MainPID --value' install.sh acfs.manifest.yaml
    assert_success
}

@test "installer: install_github_cli passes DPkg::Lock::Timeout=120 to apt-get" {
    local fake_bin="$BATS_TEST_TMPDIR/fake_bin"
    mkdir -p "$fake_bin"
    local log_file="$BATS_TEST_TMPDIR/apt_calls.log"

    cat > "$fake_bin/apt-get" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$log_file"
exit 0
EOF
    chmod +x "$fake_bin/apt-get"

    run env PATH="$fake_bin:$PATH" DRY_RUN="false" SUDO="" bash -c '
        log_detail() { :; }
        eval "$(sed -n "/^install_github_cli() {/,/^}/p" install.sh)"
        install_github_cli
    '
    assert_success

    run grep -F "DPkg::Lock::Timeout=120" "$log_file"
    assert_success
}

@test "installer: all apt-get invocations in install.sh pass DPkg::Lock::Timeout=120" {
    # Scan install.sh for any apt-get command lines (excluding comments, echo/printf logs, dry-run echoes, and command existence checks)
    run bash -c '
        grep -w "apt-get" install.sh | \
            grep -v "^[[:space:]]*#" | \
            grep -v "^[[:space:]]*\[\[" | \
            grep -v "echo " | \
            grep -v "printf " | \
            grep -v "command -v" | \
            grep -v "acfs_early_system_binary_path" | \
            grep -v "dry-run:" | \
            grep -v "log_warn" | \
            grep -v "log_error" | \
            grep -v "DPkg::Lock::Timeout=120" || true
    '
    assert_success
    assert_output ""
}

@test "installer: sourced apt libraries pass DPkg::Lock::Timeout=120" {
    run bash -c '
        grep "apt-get" \
            scripts/lib/autofix_unattended.sh \
            scripts/lib/doctor_fix.sh \
            scripts/lib/gum_ui.sh \
            scripts/lib/tailscale.sh \
            scripts/lib/ubuntu_upgrade.sh | \
            grep -v "^[^:]*:[[:space:]]*#" | \
            grep -v "log_" | \
            grep -v "doctor_fix_log" | \
            grep -v "pgrep" | \
            grep -v "command -v" | \
            grep -v "binary_path" | \
            grep -v "DPkg::Lock::Timeout=120" || true
    '
    assert_success
    assert_output ""
}
