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
    run grep -F '"$timeout_bin" 300 "${sudo_cmd[@]}" "$apt_get_bin"' install.sh
    assert_success
    [ "$(grep -Fc '"$timeout_bin" 300 "${sudo_cmd[@]}" "$apt_get_bin"' install.sh)" -eq 2 ]
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

        grep '"\$apt_get_bin"' install.sh | \
            grep -v "^[[:space:]]*\[\[" | \
            grep -v "log_" | \
            grep -v "DPkg::Lock::Timeout=120" || true
    '
    assert_success
    assert_output ""
}

@test "installer: sourced apt libraries pass DPkg::Lock::Timeout=120" {
    run bash -c '
        grep "apt-get" \
            scripts/lib/autofix_unattended.sh \
            scripts/lib/cli_tools.sh \
            scripts/lib/cloud_db.sh \
            scripts/lib/doctor_fix.sh \
            scripts/lib/gum_ui.sh \
            scripts/lib/languages.sh \
            scripts/lib/tailscale.sh \
            scripts/lib/ubuntu_upgrade.sh \
            scripts/lib/zsh.sh | \
            grep -v "^[^:]*:[[:space:]]*#" | \
            grep -v "log_" | \
            grep -v "pgrep" | \
            grep -v "command -v" | \
            grep -v "system_binary_path" | \
            grep -v "DPkg::Lock::Timeout=120" || true
    '
    assert_success
    assert_output ""
}
