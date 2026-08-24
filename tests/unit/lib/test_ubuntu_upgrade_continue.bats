#!/usr/bin/env bats
# ============================================================
# Unit tests for Ubuntu upgrade resume continuation script
# Verifies remote installer staging before root execution (bd-6cwfe)
# ============================================================

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
    source_lib "state"
    source_lib "ubuntu_upgrade"

    # Provide a stub systemctl in PATH for unprivileged test environments
    local stub_bin="$BATS_TEST_TMPDIR/stub_bin"
    mkdir -p "$stub_bin"
    cat > "$stub_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$stub_bin/systemctl"
    export PATH="$stub_bin:$PATH"
}

teardown() {
    common_teardown
}

@test "continue_install: template does not contain streaming curl pipe" {
    run grep -nE 'curl[^#]*\|\s*bash' "$PROJECT_ROOT/scripts/lib/ubuntu_upgrade.sh"
    assert_failure
    assert_output ""
}

@test "upgrade_setup_infrastructure: generates continue_install with staging and cleanup trap" {
    local source_dir="$BATS_TEST_TMPDIR/source"
    local resume_dir="$BATS_TEST_TMPDIR/resume_dir"
    mkdir -p "$source_dir/scripts/lib" "$source_dir/scripts/templates" "$resume_dir"
    touch "$source_dir/scripts/lib/upgrade_resume.sh"
    cat > "$source_dir/scripts/templates/acfs-upgrade-resume.service" <<'EOF'
[Unit]
Description=Test Service
[Service]
ExecStart=/bin/true
EOF

    # Stub cp to avoid writing to /etc/systemd/system in unit test
    cp() {
        if [[ "$*" == *"/etc/systemd/system"* ]]; then
            return 0
        fi
        command cp "$@"
    }

    ACFS_RESUME_DIR="$resume_dir" \
    TARGET_USER="root" \
    ACFS_REPO_OWNER="Dicklesworthstone" \
    ACFS_REPO_NAME="agentic_coding_flywheel_setup" \
    ACFS_REF="main" \
    upgrade_setup_infrastructure "$source_dir" "--yes" "--mode" "vibe"

    local continue_script="$resume_dir/continue_install.sh"
    [[ -f "$continue_script" ]]
    [[ -x "$continue_script" ]]

    # Verify script content
    run grep -F "STAGED_INSTALLER=" "$continue_script"
    assert_success

    run grep -F "trap cleanup_staged_installer" "$continue_script"
    assert_success

    run grep -F "chmod 0444" "$continue_script"
    assert_success
}

@test "continue_install: uses local source dir when present" {
    local source_dir="$BATS_TEST_TMPDIR/source"
    local resume_dir="$BATS_TEST_TMPDIR/resume_dir"
    local marker="$BATS_TEST_TMPDIR/local_installer_executed"
    mkdir -p "$source_dir/scripts/lib" "$source_dir/scripts/templates" "$resume_dir"
    touch "$source_dir/scripts/lib/upgrade_resume.sh"
    touch "$source_dir/scripts/templates/acfs-upgrade-resume.service"

    cat > "$source_dir/install.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$marker"
EOF
    chmod +x "$source_dir/install.sh"

    cp() {
        if [[ "$*" == *"/etc/systemd/system"* ]]; then
            return 0
        fi
        command cp "$@"
    }

    ACFS_RESUME_DIR="$resume_dir" \
    TARGET_USER="root" \
    ACFS_REPO_OWNER="Dicklesworthstone" \
    ACFS_REPO_NAME="agentic_coding_flywheel_setup" \
    ACFS_REF="main" \
    upgrade_setup_infrastructure "$source_dir" "--yes" "--mode" "vibe"

    run bash "$resume_dir/continue_install.sh"
    assert_success
    assert_output --partial "Using local installer"

    [[ -f "$marker" ]]
    run cat "$marker"
    assert_output --partial "--yes --mode vibe --skip-ubuntu-upgrade"
}

@test "continue_install: stages remote installer and executes with bash when local source is missing" {
    local source_dir="$BATS_TEST_TMPDIR/source"
    local resume_dir="$BATS_TEST_TMPDIR/resume_dir"
    local fake_bin="$BATS_TEST_TMPDIR/fake_bin"
    local marker="$BATS_TEST_TMPDIR/remote_installer_executed"
    mkdir -p "$source_dir/scripts/lib" "$source_dir/scripts/templates" "$resume_dir" "$fake_bin"
    touch "$source_dir/scripts/lib/upgrade_resume.sh"
    touch "$source_dir/scripts/templates/acfs-upgrade-resume.service"

    # Fake curl that writes an installer script
    cat > "$fake_bin/curl" <<EOF
#!/usr/bin/env bash
printf '#!/usr/bin/env bash\nprintf "remote-executed:%%s\\\n" "\\\$*" > "$marker"\n'
exit 0
EOF
    chmod +x "$fake_bin/curl"

    cp() {
        if [[ "$*" == *"/etc/systemd/system"* ]]; then
            return 0
        fi
        command cp "$@"
    }

    ACFS_RESUME_DIR="$resume_dir" \
    TARGET_USER="root" \
    ACFS_REPO_OWNER="Dicklesworthstone" \
    ACFS_REPO_NAME="agentic_coding_flywheel_setup" \
    ACFS_REF="main" \
    upgrade_setup_infrastructure "$source_dir" "--yes" "--mode" "vibe"

    rm -f "$source_dir/install.sh"

    local system_bash
    system_bash="$(command -v bash)"
    run env PATH="$fake_bin:$PATH" "$system_bash" "$resume_dir/continue_install.sh"
    assert_success
    assert_output --partial "Fetching installer:"

    [[ -f "$marker" ]]
    run cat "$marker"
    assert_output --partial "remote-executed:--yes --mode vibe --skip-ubuntu-upgrade"
}

@test "continue_install: never executes bash if curl fails with partial output" {
    local source_dir="$BATS_TEST_TMPDIR/source"
    local resume_dir="$BATS_TEST_TMPDIR/resume_dir"
    local fake_bin="$BATS_TEST_TMPDIR/fake_bin"
    local marker="$BATS_TEST_TMPDIR/poison_executed"
    mkdir -p "$source_dir/scripts/lib" "$source_dir/scripts/templates" "$resume_dir" "$fake_bin"
    touch "$source_dir/scripts/lib/upgrade_resume.sh"
    touch "$source_dir/scripts/templates/acfs-upgrade-resume.service"

    # Fake curl that writes a partial script and exits with error
    cat > "$fake_bin/curl" <<EOF
#!/usr/bin/env bash
printf 'touch "$marker"\n'
exit 56
EOF
    chmod +x "$fake_bin/curl"

    cp() {
        if [[ "$*" == *"/etc/systemd/system"* ]]; then
            return 0
        fi
        command cp "$@"
    }

    ACFS_RESUME_DIR="$resume_dir" \
    TARGET_USER="root" \
    ACFS_REPO_OWNER="Dicklesworthstone" \
    ACFS_REPO_NAME="agentic_coding_flywheel_setup" \
    ACFS_REF="main" \
    upgrade_setup_infrastructure "$source_dir" "--yes" "--mode" "vibe"

    rm -f "$source_dir/install.sh"

    local system_bash
    system_bash="$(command -v bash)"
    run env PATH="$fake_bin:$PATH" "$system_bash" "$resume_dir/continue_install.sh"
    assert_failure
    assert_output --partial "Failed to fetch installer"

    # Crucial assertion: partial script was never executed
    [[ ! -e "$marker" ]]
}
