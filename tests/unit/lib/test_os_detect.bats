#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
    source_lib "os_detect"
    
    # Mock OS release file
    export ACFS_OS_RELEASE_PATH=$(create_temp_file)
}

teardown() {
    common_teardown
}

@test "os_detect: parses ubuntu 24.04" {
    cat > "$ACFS_OS_RELEASE_PATH" <<EOF
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME=noble
PRETTY_NAME="Ubuntu 24.04 LTS"
EOF

    detect_os
    assert_equal "$?" "0"
    
    assert_equal "$OS_ID" "ubuntu"
    assert_equal "$OS_VERSION" "24.04"
    assert_equal "$OS_VERSION_MAJOR" "24"
    assert_equal "$OS_CODENAME" "noble"
    # assert_output --partial "Detected: Ubuntu 24.04 LTS"
}

@test "os_detect: fails if file missing" {
    export ACFS_OS_RELEASE_PATH="/non/existent/path"
    run detect_os
    assert_failure
    assert_output --partial "Cannot detect OS"
}

@test "validate_os: accepts ubuntu 24.04+" {
    cat > "$ACFS_OS_RELEASE_PATH" <<EOF
ID=ubuntu
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04"
EOF

    run validate_os
    assert_success
    assert_output --partial "OS validated"
}

@test "validate_os: warns on debian (non-ubuntu)" {
    cat > "$ACFS_OS_RELEASE_PATH" <<EOF
ID=debian
VERSION_ID="12"
PRETTY_NAME="Debian 12"
EOF

    run validate_os
    assert_failure # Returns 1
    assert_output --partial "ACFS is designed for Ubuntu but detected: debian"
}

@test "validate_os: warns on old ubuntu 22.04" {
    cat > "$ACFS_OS_RELEASE_PATH" <<EOF
ID=ubuntu
VERSION_ID="22.04"
PRETTY_NAME="Ubuntu 22.04"
EOF

    run validate_os
    assert_failure # Returns 1
    assert_output --partial "Recommended: Ubuntu 24.04 or 26.04 LTS"
}

@test "is_wsl: detects microsoft kernel" {
    export ACFS_PROC_VERSION=$(create_temp_file "Linux version 5.15.153.1-microsoft-standard-WSL2")
    
    run is_wsl
    assert_success
}

@test "is_wsl: detects standard kernel (not wsl)" {
    export ACFS_PROC_VERSION=$(create_temp_file "Linux version 5.15.0-105-generic")
    
    run is_wsl
    assert_failure
}

@test "is_docker: detects .dockerenv" {
    export ACFS_DOCKERENV=$(create_temp_file)
    
    run is_docker
    assert_success
}

@test "is_docker: detects cgroup" {
    # No dockerenv
    export ACFS_DOCKERENV="/non/existent"
    export ACFS_CGROUP=$(create_temp_file "1:name=systemd:/docker/container_id")
    
    run is_docker
    assert_success
}

@test "is_fresh_vps: refuses to guess a home for unresolved different target user" {
    export TARGET_USER="missinguser"
    unset TARGET_HOME

    stub_command "getent" "" 2
    stub_command "whoami" "ubuntu"

    run is_fresh_vps
    assert_failure
}

@test "get_arch: maps x86_64 to amd64" {
    stub_command "uname" "x86_64"
    
    run get_arch
    assert_output "amd64"
}

@test "get_arch: maps aarch64 to arm64" {
    stub_command "uname" "aarch64"
    
    run get_arch
    assert_output "arm64"
}
