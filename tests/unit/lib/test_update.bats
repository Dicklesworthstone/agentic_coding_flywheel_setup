#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    
    unset TARGET_USER TARGET_HOME ACFS_BIN_DIR ACFS_STATE_FILE ACFS_HOME

    # update.sh logic relies on being sourced or executed
    # We source it.
    # It has a guard at the end `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi`
    # When sourced by bats, this guard prevents main.
    
    # Mock environment for update.sh
    export HOME=$(create_temp_dir)
    export TARGET_HOME="$HOME"
    export UPDATE_LOG_DIR="$HOME/.acfs/logs/updates"
    
    source_lib "update"
    
    # Mock date
    stub_command "date" "2025-01-01"
}

teardown() {
    common_teardown
}

@test "get_version: detects bun" {
    mkdir -p "$HOME/.bun/bin"
    # Create stub script at location
    cat > "$HOME/.bun/bin/bun" <<EOF
#!/bin/bash
echo "1.0.0"
EOF
    chmod +x "$HOME/.bun/bin/bun"
    
    run get_version "bun"
    assert_output "1.0.0"
}

@test "get_version: detects rust" {
    mkdir -p "$HOME/.cargo/bin"
    cat > "$HOME/.cargo/bin/rustc" <<EOF
#!/bin/bash
echo "rustc 1.75.0 (hash)"
EOF
    chmod +x "$HOME/.cargo/bin/rustc"
    
    run get_version "rust"
    assert_output "1.75.0"
}

@test "get_version: detects source-built stack binaries in cargo bin" {
    mkdir -p "$HOME/.cargo/bin"
    cat > "$HOME/.cargo/bin/aadc" <<'EOF'
#!/bin/bash
echo "aadc 0.1.0"
EOF
    chmod +x "$HOME/.cargo/bin/aadc"

    cat > "$HOME/.cargo/bin/rust_proxy" <<'EOF'
#!/bin/bash
echo "rust_proxy 0.1.0"
EOF
    chmod +x "$HOME/.cargo/bin/rust_proxy"

    run get_version "aadc"
    assert_success
    assert_output "aadc 0.1.0"

    run get_version "rust_proxy"
    assert_success
    assert_output "rust_proxy 0.1.0"
}

@test "get_version: detects ntm via version subcommand" {
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/ntm" <<'EOF'
#!/bin/bash
case "${1:-}" in
  version)
    echo "ntm version 1.14.0"
    ;;
  --version)
    echo "Error: unknown flag: --version" >&2
    exit 1
    ;;
  *)
    exit 2
    ;;
esac
EOF
    chmod +x "$HOME/.local/bin/ntm"

    run get_version "ntm"
    assert_success
    assert_output "ntm version 1.14.0"
}

@test "get_version: prefers target runtime binaries when HOME differs" {
    local current_home
    local target_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER
    unset ACFS_BIN_DIR
    unset ACFS_STATE_FILE
    unset ACFS_HOME

    mkdir -p "$current_home/.bun/bin" "$current_home/.cargo/bin" "$current_home/.local/bin"
    mkdir -p "$target_home/.bun/bin" "$target_home/.cargo/bin" "$target_home/.local/bin"

    cat > "$current_home/.bun/bin/bun" <<'EOF'
#!/usr/bin/env bash
echo "0.9.0"
EOF
    chmod +x "$current_home/.bun/bin/bun"

    cat > "$target_home/.bun/bin/bun" <<'EOF'
#!/usr/bin/env bash
echo "1.3.12"
EOF
    chmod +x "$target_home/.bun/bin/bun"

    cat > "$current_home/.cargo/bin/rustc" <<'EOF'
#!/usr/bin/env bash
echo "rustc 1.70.0 (old)"
EOF
    chmod +x "$current_home/.cargo/bin/rustc"

    cat > "$target_home/.cargo/bin/rustc" <<'EOF'
#!/usr/bin/env bash
echo "rustc 1.88.0 (target)"
EOF
    chmod +x "$target_home/.cargo/bin/rustc"

    cat > "$current_home/.local/bin/uv" <<'EOF'
#!/usr/bin/env bash
echo "uv 0.10.0"
EOF
    chmod +x "$current_home/.local/bin/uv"

    cat > "$target_home/.local/bin/uv" <<'EOF'
#!/usr/bin/env bash
echo "uv 0.11.6"
EOF
    chmod +x "$target_home/.local/bin/uv"

    run get_version "bun"
    assert_success
    assert_output "1.3.12"

    run get_version "rust"
    assert_success
    assert_output "1.88.0"

    run get_version "uv"
    assert_success
    assert_output "0.11.6"
}

@test "get_version: handles unknown" {
    run get_version "nonexistent"
    assert_output "unknown"
}

@test "update_target_home: ignores slash TARGET_HOME and uses passwd resolution" {
    local resolved_home
    resolved_home="$(create_temp_dir)"

    export TARGET_HOME="/"
    export HOME="/"

    update_getent_passwd_entry() {
        if [[ "${1:-}" == "tester" ]]; then
            printf 'tester:x:1000:1000::%s:/bin/bash\n' "$resolved_home"
            return 0
        fi
        return 2
    }

    run update_target_home "tester"
    assert_success
    assert_output "$resolved_home"
}

@test "update_target_home: ignores stale TARGET_HOME and uses passwd resolution" {
    local resolved_home
    local stale_home
    resolved_home="$(create_temp_dir)"
    stale_home="$BATS_TEST_TMPDIR/stale-target-home"
    mkdir -p "$stale_home"

    export TARGET_HOME="$stale_home"
    export HOME="$stale_home"

    update_getent_passwd_entry() {
        if [[ "${1:-}" == "tester" ]]; then
            printf 'tester:x:1000:1000::%s:/bin/bash\n' "$resolved_home"
            return 0
        fi
        return 2
    }

    run update_target_home "tester"
    assert_success
    assert_output "$resolved_home"
}

@test "update_target_home: current HOME fallback cannot override explicit TARGET_HOME" {
    local current_home
    local target_home

    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export TARGET_USER="tester"
    export TARGET_HOME="$target_home"
    export HOME="$current_home"

    update_current_user() {
        printf 'tester\n'
    }

    update_getent_passwd_entry() {
        return 2
    }

    run update_target_home "tester"
    assert_success
    assert_output "$target_home"

    export TARGET_HOME="$current_home"
    run update_target_home "tester"
    assert_success
    assert_output "$current_home"
}

@test "update.sh: source-time HOME repair does not make stale TARGET_HOME explicit" {
    local current_user
    local current_home
    local stale_home

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    [[ -n "$current_user" ]] || fail "Unable to resolve current user"
    current_home="$(command getent passwd "$current_user" | cut -d: -f6)"
    [[ -n "$current_home" && -d "$current_home" ]] || fail "Unable to resolve current user home"

    stale_home="$BATS_TEST_TMPDIR/stale-source-home"
    mkdir -p "$stale_home"

    run env TARGET_USER="$current_user" TARGET_HOME="$stale_home" HOME="$stale_home" bash -c 'source "$1"; printf "HOME=%s target=%s\n" "$HOME" "$(update_target_home "$TARGET_USER")"' _ "$PROJECT_ROOT/scripts/lib/update.sh"
    assert_success
    assert_output "HOME=$current_home target=$current_home"
}

@test "update.sh: source-time HOME repair prefers TARGET_USER passwd over stale TARGET_HOME" {
    local current_user
    local current_home
    local caller_home
    local stale_home

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    [[ -n "$current_user" ]] || fail "Unable to resolve current user"
    current_home="$(command getent passwd "$current_user" | cut -d: -f6)"
    [[ -n "$current_home" && -d "$current_home" ]] || fail "Unable to resolve current user home"

    caller_home="$(create_temp_dir)"
    stale_home="$BATS_TEST_TMPDIR/stale-source-target-home"
    mkdir -p "$stale_home"

    run env TARGET_USER="$current_user" TARGET_HOME="$stale_home" HOME="$caller_home" bash -c 'source "$1"; printf "HOME=%s target=%s\n" "$HOME" "$(update_target_home "$TARGET_USER")"' _ "$PROJECT_ROOT/scripts/lib/update.sh"
    assert_success
    assert_output "HOME=$current_home target=$current_home"
}

@test "update.sh: source-time HOME repair fails closed for unresolved target with stale TARGET_HOME" {
    local stale_home
    stale_home="$(create_temp_dir)"

    run env TARGET_USER="missinguser" TARGET_HOME="$stale_home" HOME="$stale_home" bash -c 'source "$1"; printf "HOME=%s target=%s\n" "$HOME" "$(update_target_home "$TARGET_USER" 2>/dev/null || true)"' _ "$PROJECT_ROOT/scripts/lib/update.sh"
    assert_success
    assert_output "HOME=$stale_home target="
}

@test "update_target_home: rejects invalid fallback usernames" {
    export TARGET_HOME="/"
    export HOME="/"

    getent() {
        return 2
    }

    run update_target_home "../bad-user"
    assert_failure
}

@test "update_target_home: fails closed when valid user home is unresolved" {
    export TARGET_HOME="/"
    export HOME="/"

    update_getent_passwd_entry() {
        return 2
    }

    run update_target_home "missinguser"
    assert_failure
}

@test "update_target_home: fails closed for unresolved target with stale TARGET_HOME" {
    local stale_home
    stale_home="$(create_temp_dir)"

    export TARGET_USER="missinguser"
    export TARGET_HOME="$stale_home"
    export HOME="$stale_home"

    update_current_user() {
        printf 'calleruser\n'
    }

    update_getent_passwd_entry() {
        return 2
    }

    run update_target_home "missinguser"
    assert_failure
    assert_output ""
}

@test "update.sh: sources under set -u without HOME" {
    local update="$PROJECT_ROOT/scripts/lib/update.sh"

    run env -i PATH="/usr/bin:/bin" bash -c 'set -euo pipefail; source "$1"; printf "home=%s\nlog=%s\n" "${HOME:-}" "$UPDATE_LOG_DIR"' _ "$update"
    assert_success
    refute_output --partial "unbound variable"
    assert_output --partial ".acfs/logs/updates"

    run grep -F 'if [[ -n "${HOME:-}" ]]; then' "$update"
    assert_success
}

@test "install.sh: read-only module listing tolerates unset HOME" {
    run env -i PATH="/usr/bin:/bin" bash "$PROJECT_ROOT/install.sh" --list-modules
    assert_success
    refute_output --partial "unbound variable"
    assert_output --partial "base.filesystem"
}

@test "install.sh: ref flags reject empty equals-form values" {
    run env -i PATH="/usr/bin:/bin" bash "$PROJECT_ROOT/install.sh" --print-plan --ref=
    assert_failure
    assert_output --partial "--ref requires a ref"

    run env -i PATH="/usr/bin:/bin" bash "$PROJECT_ROOT/install.sh" --print-plan --checksums-ref=
    assert_failure
    assert_output --partial "--checksums-ref requires a ref"
}

@test "install.sh: ref flags reject unsafe git ref syntax" {
    run env -i PATH="/usr/bin:/bin" bash "$PROJECT_ROOT/install.sh" --print-plan "--ref=bad;touch"
    assert_failure
    assert_output --partial "--ref contains unsafe ref characters"

    run env -i PATH="/usr/bin:/bin" bash "$PROJECT_ROOT/install.sh" --print-plan "--checksums-ref=feature/../main"
    assert_failure
    assert_output --partial "--checksums-ref has invalid git ref syntax"

    run env -i PATH="/usr/bin:/bin" ACFS_REF="bad ref" bash "$PROJECT_ROOT/install.sh" --print-plan
    assert_failure
    assert_output --partial "ACFS_REF contains unsafe ref characters"
}

@test "install.sh: Ubuntu upgrade state override does not use RETURN trap" {
    local installer="$PROJECT_ROOT/install.sh"

    run bash -c 'sed -n "/^run_ubuntu_upgrade_phase()/,/^restore_previous_acfs_state_file()/p" "$1" | grep -F "trap "' _ "$installer"
    assert_failure

    run bash -c 'sed -n "/^run_ubuntu_upgrade_phase()/,/^restore_previous_acfs_state_file()/p" "$1" | grep -F "restore_previous_acfs_state_file \"\$had_state_file\" \"\$previous_state_file\"" | wc -l' _ "$installer"
    assert_success
    [[ "$output" -ge 10 ]] || fail "expected explicit ACFS_STATE_FILE restores in Ubuntu upgrade exits"
}

@test "install.sh: Supabase release installer does not use RETURN trap cleanup" {
    local installer="$PROJECT_ROOT/install.sh"

    run bash -c 'sed -n "/^install_supabase_cli_release()/,/^}/p" "$1" | grep -F "trap "' _ "$installer"
    assert_failure

    run bash -c 'sed -n "/^install_supabase_cli_release()/,/^}/p" "$1" | grep -F "cleanup_supabase_cli_release_temp \"\$tmp_dir\" \"\$tmp_tgz\" \"\$tmp_checksums\"" | wc -l' _ "$installer"
    assert_success
    [[ "$output" -ge 8 ]] || fail "expected explicit Supabase temp cleanup before every installer exit"
}

@test "update_has_nvm_node: requires executable node binary" {
    local node_bin="$HOME/.nvm/versions/node/v99.0.0/bin"

    mkdir -p "$node_bin"
    touch "$node_bin/node"

    run update_has_nvm_node
    assert_failure

    chmod +x "$node_bin/node"
    run update_has_nvm_node
    assert_success
}

@test "update_nvm_node_bin_dir: picks newest executable node binary" {
    local older_bin="$HOME/.nvm/versions/node/v20.11.1/bin"
    local newer_bin="$HOME/.nvm/versions/node/v99.0.0/bin"

    mkdir -p "$older_bin" "$newer_bin"
    cat > "$older_bin/node" <<'EOF'
#!/usr/bin/env bash
echo older node
EOF
    chmod +x "$older_bin/node"
    touch "$newer_bin/node"

    run update_nvm_node_bin_dir
    assert_success
    assert_output "$older_bin"

    chmod +x "$newer_bin/node"
    run update_nvm_node_bin_dir
    assert_success
    assert_output "$newer_bin"
}

@test "update_preferred_user_bin_dir: falls back to target home when HOME differs" {
    local current_home
    local target_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER
    unset ACFS_BIN_DIR
    unset ACFS_STATE_FILE
    unset ACFS_HOME

    run update_preferred_user_bin_dir
    assert_success
    assert_output "$target_home/.local/bin"
}

@test "update_preferred_user_bin_dir: ignores relative ACFS_BIN_DIR and falls back to target home" {
    local current_home
    local target_home
    local cwd
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    cwd="$(create_temp_dir)"

    mkdir -p "$cwd/relative/bin"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER
    export ACFS_BIN_DIR="relative/bin"
    unset ACFS_STATE_FILE
    unset ACFS_HOME

    pushd "$cwd" >/dev/null
    run update_preferred_user_bin_dir
    popd >/dev/null

    assert_success
    assert_output "$target_home/.local/bin"
}

@test "update_preferred_user_bin_dir: parses bin_dir from state without jq" {
    local current_home
    local target_home
    local state_file
    local fake_path
    local original_path="${PATH-}"
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    state_file="$BATS_TEST_TMPDIR/update-state.json"
    fake_path="$(create_temp_dir)"

    cat > "$state_file" <<EOF
{"bin_dir":"$target_home/custom-bin"}
EOF

    ln -s /usr/bin/sed "$fake_path/sed"
    ln -s /usr/bin/head "$fake_path/head"

    export HOME="$current_home"
    export PATH="$fake_path"
    export TARGET_USER="acfstestuser"
    export TARGET_HOME="$target_home"
    export ACFS_STATE_FILE="$state_file"
    unset ACFS_BIN_DIR
    unset ACFS_HOME

    run update_preferred_user_bin_dir
    PATH="${original_path:-/usr/bin:/bin}"
    assert_success
    assert_output "$target_home/custom-bin"
}

@test "update_preferred_user_bin_dir: does not fall back to current HOME for different unresolved target" {
    local current_home
    current_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_USER="missinguser"
    export TARGET_HOME="/"
    unset ACFS_BIN_DIR
    unset ACFS_STATE_FILE
    unset ACFS_HOME

    getent() {
        return 2
    }

    run update_preferred_user_bin_dir
    assert_failure
}

@test "update_default_user_bin_dir: does not fall back to current HOME for different unresolved target" {
    local current_home
    current_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_USER="missinguser"
    export TARGET_HOME="/"

    getent() {
        return 2
    }

    run update_default_user_bin_dir
    assert_failure
}

@test "update_binary_path: ignores current-shell-only PATH entries" {
    init_stub_dir

    local current_home
    local target_home
    local tool_name="acfs-test-update-tool"
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER
    unset ACFS_BIN_DIR
    unset ACFS_STATE_FILE
    unset ACFS_HOME
    mkdir -p "$target_home/.local/bin"

    cat > "$STUB_DIR/$tool_name" <<'EOF'
#!/usr/bin/env bash
echo "current-shell-only"
EOF
    chmod +x "$STUB_DIR/$tool_name"
    export PATH="$STUB_DIR:/usr/bin:/bin"

    run update_binary_path "$tool_name"
    assert_failure

    cat > "$target_home/.local/bin/$tool_name" <<'EOF'
#!/usr/bin/env bash
echo "target-home"
EOF
    chmod +x "$target_home/.local/bin/$tool_name"

    run update_binary_path "$tool_name"
    assert_success
    assert_output "$target_home/.local/bin/$tool_name"
}

@test "update_curl: ignores shell function curl" {
    local curl_marker="${BATS_TEST_TMPDIR}/update-curl-poison.marker"

    curl() {
        : > "$curl_marker"
        return 42
    }

    run update_curl "https://127.0.0.1:9/"

    assert_failure
    [[ "$status" -ne 42 ]]
    [[ "$status" -ne 127 ]]
    [[ ! -e "$curl_marker" ]]
}

@test "update_sha256_file: ignores shell function sha256sum" {
    local probe_file="${BATS_TEST_TMPDIR}/update-sha-probe"
    local expected

    printf '%s' "real-content" > "$probe_file"
    expected="$(update_sha256_file "$probe_file")"

    sha256sum() {
        printf 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff  %s\n' "$1"
    }

    run update_sha256_file "$probe_file"

    assert_success
    assert_output "$expected"
    refute_output "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
}

@test "refresh_checksums: uses trusted update_curl helper" {
    local update="$PROJECT_ROOT/scripts/lib/update.sh"

    run grep -F 'if update_curl --connect-timeout 5 --max-time 30 -o "$tmp_checksums" "$CHECKSUMS_URL" 2>/dev/null; then' "$update"
    assert_success

    run grep -F 'curl "${_refresh_curl_args[@]}" -o "$tmp_checksums" "$CHECKSUMS_URL"' "$update"
    assert_failure
}

@test "self-update hash comparisons use trusted update_sha256_file helper" {
    local update="$PROJECT_ROOT/scripts/lib/update.sh"

    run grep -F 'repo_sec_hash=$(update_sha256_file "$repo_security" 2>/dev/null) || true' "$update"
    assert_success

    run grep -F 'installed_sec_hash=$(update_sha256_file "$installed_security" 2>/dev/null) || true' "$update"
    assert_success

    run grep -F 'old_hash=$(update_sha256_file "$update_script" 2>/dev/null) || true' "$update"
    assert_success

    run grep -F 'new_hash=$(update_sha256_file "$update_script" 2>/dev/null) || true' "$update"
    assert_success

    run grep -F 'sha256sum "$update_script"' "$update"
    assert_failure

    run grep -F 'sha256sum "$repo_security"' "$update"
    assert_failure

    run grep -F 'sha256sum "$installed_security"' "$update"
    assert_failure
}

@test "update_binary_path: ignores relative ACFS_BIN_DIR shim when target bin exists" {
    local current_home
    local target_home
    local cwd
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    cwd="$(create_temp_dir)"

    mkdir -p "$cwd/relative/bin" "$target_home/.local/bin"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER
    export ACFS_BIN_DIR="relative/bin"
    unset ACFS_STATE_FILE
    unset ACFS_HOME
    export PATH="/usr/bin:/bin"

    cat > "$cwd/relative/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "wrong-relative-gh"
EOF
    chmod +x "$cwd/relative/bin/gh"

    cat > "$target_home/.local/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "target-gh"
EOF
    chmod +x "$target_home/.local/bin/gh"

    pushd "$cwd" >/dev/null
    run update_binary_path "gh"
    popd >/dev/null

    assert_success
    assert_output "$target_home/.local/bin/gh"
}

@test "update_binary_path: finds target gcloud in google-cloud-sdk bin" {
    init_stub_dir

    local current_home
    local target_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER
    unset ACFS_BIN_DIR
    unset ACFS_STATE_FILE
    unset ACFS_HOME
    mkdir -p "$target_home/google-cloud-sdk/bin"

    cat > "$STUB_DIR/gcloud" <<'EOF'
#!/usr/bin/env bash
echo "current-shell-gcloud"
EOF
    chmod +x "$STUB_DIR/gcloud"
    export PATH="$STUB_DIR:/usr/bin:/bin"

    cat > "$target_home/google-cloud-sdk/bin/gcloud" <<'EOF'
#!/usr/bin/env bash
echo "target-gcloud"
EOF
    chmod +x "$target_home/google-cloud-sdk/bin/gcloud"

    run update_binary_path "gcloud"
    assert_success
    assert_output "$target_home/google-cloud-sdk/bin/gcloud"
}

@test "update_binary_path: does not fall back to current HOME for different unresolved target" {
    local current_home
    current_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_USER="missinguser"
    export TARGET_HOME="/"
    unset ACFS_BIN_DIR
    unset ACFS_STATE_FILE
    unset ACFS_HOME
    mkdir -p "$current_home/.local/bin"

    getent() {
        return 2
    }

    cat > "$current_home/.local/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "wrong-home-gh"
EOF
    chmod +x "$current_home/.local/bin/gh"

    run update_binary_path "gh"
    assert_failure
}

@test "update_tool_binary_path: prefers target atuin over current HOME" {
    local current_home
    local target_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER
    unset ACFS_BIN_DIR
    unset ACFS_STATE_FILE
    unset ACFS_HOME
    mkdir -p "$current_home/.atuin/bin" "$target_home/.atuin/bin"

    cat > "$current_home/.atuin/bin/atuin" <<'EOF'
#!/usr/bin/env bash
echo "current-home"
EOF
    chmod +x "$current_home/.atuin/bin/atuin"

    cat > "$target_home/.atuin/bin/atuin" <<'EOF'
#!/usr/bin/env bash
echo "target-home"
EOF
    chmod +x "$target_home/.atuin/bin/atuin"

    run update_tool_binary_path "atuin"
    assert_success
    assert_output "$target_home/.atuin/bin/atuin"
}

@test "update_tool_binary_path: does not fall back to current HOME atuin for different unresolved target" {
    local current_home
    current_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_USER="missinguser"
    export TARGET_HOME="/"
    unset ACFS_BIN_DIR
    unset ACFS_STATE_FILE
    unset ACFS_HOME
    mkdir -p "$current_home/.atuin/bin"

    getent() {
        return 2
    }

    cat > "$current_home/.atuin/bin/atuin" <<'EOF'
#!/usr/bin/env bash
echo "wrong-home-atuin"
EOF
    chmod +x "$current_home/.atuin/bin/atuin"

    run update_tool_binary_path "atuin"
    assert_failure
}

@test "capture_version: tracks changes" {
    mkdir -p "$HOME/.bun/bin"
    
    # Before
    cat > "$HOME/.bun/bin/bun" <<EOF
#!/bin/bash
echo "1.0.0"
EOF
    chmod +x "$HOME/.bun/bin/bun"
    
    capture_version_before "bun"
    assert_equal "${VERSION_BEFORE[bun]}" "1.0.0"
    
    # After (update)
    cat > "$HOME/.bun/bin/bun" <<EOF
#!/bin/bash
echo "1.0.1"
EOF
    chmod +x "$HOME/.bun/bin/bun"
    
    capture_version_after "bun"
    assert_equal "${VERSION_AFTER[bun]}" "1.0.1"
}

@test "update_cargo_tools: runs cargo install --force" {
    mkdir -p "$HOME/.cargo/bin"
    
    # Mock cargo
    local log_file="$HOME/cargo.log"
    cat > "$HOME/.cargo/bin/cargo" <<EOF
#!/bin/bash
echo "\$@" >> "$log_file"
EOF
    chmod +x "$HOME/.cargo/bin/cargo"
    
    # Mock existing tools so update_cargo_tools attempts update
    # sg needs to exist in PATH or .cargo/bin
    touch "$HOME/.cargo/bin/sg"
    chmod +x "$HOME/.cargo/bin/sg"
    
    # Mock get_version for sg
    # We need sg in PATH for get_version
    export PATH="$HOME/.cargo/bin:$PATH"
    cat > "$HOME/.cargo/bin/sg" <<EOF
#!/bin/bash
echo "0.1.0"
EOF
    chmod +x "$HOME/.cargo/bin/sg"
    
    # Run update
    UPDATE_RUNTIME=true
    run update_cargo_tools
    assert_success
    
    # Verify cargo install called
    run cat "$log_file"
    assert_output --partial "install ast-grep --locked --force"
}

@test "update.sh: runtime resolver gates avoid inherited PATH leaks" {
    local update="$PROJECT_ROOT/scripts/lib/update.sh"

    run grep -F 'cargo_bin="$(update_binary_path cargo 2>/dev/null || true)"' "$update"
    assert_success

    run grep -F 'bun_bin="$(update_binary_path bun 2>/dev/null || true)"' "$update"
    assert_success

    run grep -F 'rustup_bin="$(update_binary_path rustup 2>/dev/null || true)"' "$update"
    assert_success

    run grep -F 'uv_bin="$(update_binary_path uv 2>/dev/null || true)"' "$update"
    assert_success

    run grep -F 'if ! update_binary_exists "$binary_name"; then' "$update"
    assert_success

    run grep -F 'update_run_in_target_context "" "$cargo_bin" install --git https://github.com/Dicklesworthstone/meta_skill --force' "$update"
    assert_success

    run grep -F 'run_cmd "Update $tool" update_run_in_target_context "" "$cargo_bin" install "$tool" --locked --force' "$update"
    assert_success

    run grep -F 'run_cmd "Update $tool" "$cargo_bin" install "$tool" --locked --force' "$update"
    assert_failure

    run grep -F 'bun_runtime_home="$(update_runtime_shell_home 2>/dev/null || true)"' "$update"
    assert_success

    run grep -F 'output=$(update_run_in_target_context "" "$bun_bin" install -g --trust "$pkg" 2>&1)' "$update"
    assert_success

    run grep -F 'output=$("$bun_bin" install -g --trust "$pkg" 2>&1)' "$update"
    assert_failure

    run grep -F 'run_cmd_bun_with_retry "Gemini CLI" update_run_in_target_context "" "$bun_bin" install -g --trust @google/gemini-cli@latest' "$update"
    assert_success

    run grep -F 'run_cmd_bun_with_retry "Wrangler (Cloudflare)" update_run_in_target_context "" "$bun_bin" install -g --trust wrangler@latest' "$update"
    assert_success

    run grep -F 'run_cmd_bun_with_retry "Vercel CLI" update_run_in_target_context "" "$bun_bin" install -g --trust vercel@latest' "$update"
    assert_success

    run grep -F 'run_cmd_bun_with_retry "Gemini CLI" "$bun_bin" install -g --trust @google/gemini-cli@latest' "$update"
    assert_failure

    run grep -F 'run_cmd_bun_with_retry "Wrangler (Cloudflare)" "$bun_bin" install -g --trust wrangler@latest' "$update"
    assert_failure

    run grep -F 'run_cmd_bun_with_retry "Vercel CLI" "$bun_bin" install -g --trust vercel@latest' "$update"
    assert_failure

    run grep -F 'update_run_verified_installer_or_existing_on_transient "Meta Skill" ms ms ms --easy-mode || true' "$update"
    assert_success

    run grep -F 'run_cmd "Meta Skill" update_run_verified_installer ms --easy-mode' "$update"
    assert_failure

    run grep -F 'run_cmd "Supabase CLI" update_run_in_target_context "ACFS_PRIMARY_BIN_DIR=$supabase_primary_bin" bash -c "$(supabase_release_update_script)"' "$update"
    assert_success

    run grep -F 'run_cmd "Supabase CLI" env "ACFS_PRIMARY_BIN_DIR=$supabase_primary_bin" bash -c "$(supabase_release_update_script)"' "$update"
    assert_failure

    run grep -F 'run_cmd "AADC" update_run_cargo_git_source_install https://github.com/Dicklesworthstone/aadc.git aadc' "$update"
    assert_success

    run grep -F 'run_cmd "Rust Proxy" update_run_cargo_git_source_install https://github.com/Dicklesworthstone/rust_proxy.git rust_proxy' "$update"
    assert_success

    run grep -F 'run_cmd "AADC" bash -c' "$update"
    assert_failure

    run grep -F 'run_cmd "Rust Proxy" bash -c' "$update"
    assert_failure

    run grep -F 'run_cmd "DCG Hook" "$dcg_bin" install --force' "$update"
    assert_success

    run grep -F 'update_run_verified_installer_or_existing_on_transient "NTM" ntm ntm ntm' "$update"
    assert_success

    run grep -F 'update_run_verified_installer_or_existing_on_transient "Meta Skill" ms ms ms --easy-mode' "$update"
    assert_success

    run grep -F '"$target_home/.atuin/bin/atuin"' "$update"
    assert_success

    run rg -n '\$HOME/\.bun/bin/bun' "$update"
    assert_failure

    run grep -F 'command -v "$binary_name"' "$update"
    assert_failure
}

@test "supabase release updater uses trusted curl and SHA helpers" {
    local script=""

    script="$(supabase_release_update_script)"

    [[ "$script" == *"supabase_system_binary_path() {"* ]]
    [[ "$script" == *'SUPABASE_CURL_BIN="$(supabase_system_binary_path curl 2>/dev/null || true)"'* ]]
    [[ "$script" == *'supabase_curl -o "$tmp_tgz"'* ]]
    [[ "$script" == *'supabase_curl -o "$tmp_checksums"'* ]]
    [[ "$script" == *'actual_sha="$(supabase_sha256_file "$tmp_tgz")"'* ]]
    [[ "$script" != *'command -v curl'* ]]
    [[ "$script" != *'sha256sum "$tmp_tgz"'* ]]
    [[ "$script" != *'shasum -a 256 "$tmp_tgz"'* ]]
}

@test "update_stack continues after Meta Skill retry exhaustion" {
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    UPDATE_STACK=true
    ABORT_ON_FAILURE=false
    ACFS_UPDATE_RETRY_MAX_ATTEMPTS=1
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    SKIP_COUNT=0

    declare -gA KNOWN_INSTALLERS=([mcp_agent_mail]="https://example.test/install-am.sh")

    update_require_security() { return 0; }
    get_checksum() { printf '%s\n' "abc123"; }
    verify_checksum() {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'exit 0'
    }
    update_target_user() { id -un; }
    update_target_home() { printf '%s\n' "$HOME"; }
    update_run_logged_passthrough() { return 0; }
    update_source_stack_lib() { return 1; }
    capture_version_before() { :; }
    capture_version_after() { return 1; }
    update_binary_exists() { return 1; }
    update_run_verified_installer() {
        case "${1:-}" in
            ms)
                printf '%s\n' "download failed: rate limit exceeded" >&2
                return 7
                ;;
            apr)
                : > "$HOME/apr-ran"
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    }
    update_run_verified_installer_with_env() { return 0; }
    update_run_slb_source_install() { return 0; }
    update_run_fsfs_installer() { return 0; }

    run update_stack
    assert_success
    assert_output --partial "[fail] Meta Skill"
    [[ -f "$HOME/apr-ran" ]]
}

@test "update_stack records MCP Agent Mail target-home failure and continues" {
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    UPDATE_STACK=true
    ABORT_ON_FAILURE=false
    ACFS_UPDATE_RETRY_MAX_ATTEMPTS=1
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    SKIP_COUNT=0

    declare -gA KNOWN_INSTALLERS=([mcp_agent_mail]="https://example.test/install-am.sh")

    update_require_security() { return 0; }
    get_checksum() { printf '%s\n' "abc123"; }
    verify_checksum() {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'exit 0'
    }
    update_target_user() { printf '%s\n' "missinguser"; }
    update_target_home() { return 1; }
    update_run_logged_passthrough() {
        : > "$HOME/mcp-agent-mail-installer-ran"
        return 0
    }
    update_source_stack_lib() { return 0; }
    capture_version_before() { :; }
    capture_version_after() { return 1; }
    update_binary_exists() { return 1; }
    update_run_verified_installer() {
        case "${1:-}" in
            apr)
                : > "$HOME/apr-ran"
                ;;
        esac
        return 0
    }
    update_run_verified_installer_with_env() { return 0; }
    update_run_slb_source_install() { return 0; }
    update_run_fsfs_installer() { return 0; }

    run update_stack
    assert_success
    assert_output --partial "[fail] MCP Agent Mail"
    [[ ! -f "$HOME/mcp-agent-mail-installer-ran" ]]
    [[ -f "$HOME/apr-ran" ]]
}

@test "update_stack honors abort-on-failure for MCP Agent Mail target-home failure" {
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    UPDATE_STACK=true
    ABORT_ON_FAILURE=true
    ACFS_UPDATE_RETRY_MAX_ATTEMPTS=1
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    SKIP_COUNT=0

    declare -gA KNOWN_INSTALLERS=([mcp_agent_mail]="https://example.test/install-am.sh")

    update_require_security() { return 0; }
    get_checksum() { printf '%s\n' "abc123"; }
    verify_checksum() {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'exit 0'
    }
    update_target_user() { printf '%s\n' "missinguser"; }
    update_target_home() { return 1; }
    update_run_logged_passthrough() {
        : > "$HOME/mcp-agent-mail-installer-ran"
        return 0
    }
    update_source_stack_lib() { return 0; }
    capture_version_before() { :; }
    capture_version_after() { return 1; }
    update_binary_exists() { return 1; }
    update_run_verified_installer() {
        case "${1:-}" in
            apr)
                : > "$HOME/apr-ran"
                ;;
        esac
        return 0
    }
    update_run_verified_installer_with_env() { return 0; }
    update_run_slb_source_install() { return 0; }
    update_run_fsfs_installer() { return 0; }

    run update_stack
    assert_failure
    assert_output --partial "[fail] MCP Agent Mail"
    assert_output --partial "Aborting due to failure (--abort-on-failure)"
    [[ ! -f "$HOME/mcp-agent-mail-installer-ran" ]]
    [[ ! -f "$HOME/apr-ran" ]]
}

@test "update_stack honors abort-on-failure for MCP Agent Mail installer failure" {
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    UPDATE_STACK=true
    ABORT_ON_FAILURE=true
    ACFS_UPDATE_RETRY_MAX_ATTEMPTS=1
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    SKIP_COUNT=0

    declare -gA KNOWN_INSTALLERS=([mcp_agent_mail]="https://example.test/install-am.sh")

    update_require_security() { return 0; }
    get_checksum() { printf '%s\n' "abc123"; }
    verify_checksum() {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'exit 0'
    }
    update_target_user() { id -un; }
    update_target_home() { printf '%s\n' "$HOME"; }
    update_run_logged_passthrough() {
        : > "$HOME/mcp-agent-mail-installer-ran"
        return 17
    }
    update_source_stack_lib() { return 0; }
    capture_version_before() { :; }
    capture_version_after() { return 1; }
    update_binary_exists() { return 1; }
    update_run_verified_installer() {
        case "${1:-}" in
            apr)
                : > "$HOME/apr-ran"
                ;;
        esac
        return 0
    }
    update_run_verified_installer_with_env() { return 0; }
    update_run_slb_source_install() { return 0; }
    update_run_fsfs_installer() { return 0; }

    run update_stack

    assert_failure
    assert_output --partial "[fail] MCP Agent Mail"
    assert_output --partial "installer failed"
    assert_output --partial "Aborting due to failure (--abort-on-failure)"
    [[ -f "$HOME/mcp-agent-mail-installer-ran" ]]
    [[ ! -f "$HOME/apr-ran" ]]
}

@test "self-update dirty fast-forward uses the selected remote branch" {
    local temp_root
    local seed_repo
    local origin_repo
    local work_repo
    local intermediate_commit
    local local_head
    local remote_head
    local upstream_ref

    temp_root="$(create_temp_dir)"
    seed_repo="$temp_root/seed"
    origin_repo="$temp_root/origin.git"
    work_repo="$temp_root/work"

    mkdir -p "$seed_repo/scripts/lib"
    git -C "$seed_repo" init -b main >/dev/null
    git -C "$seed_repo" config user.email test@example.invalid
    git -C "$seed_repo" config user.name "ACFS Test"
    printf "base-update\n" > "$seed_repo/scripts/lib/update.sh"
    git -C "$seed_repo" add scripts/lib/update.sh
    git -C "$seed_repo" commit -m base >/dev/null

    git clone --bare "$seed_repo" "$origin_repo" >/dev/null 2>&1
    git clone "$origin_repo" "$work_repo" >/dev/null 2>&1
    git -C "$seed_repo" remote add origin "$origin_repo"

    git -C "$seed_repo" switch -c release/test >/dev/null
    printf "intermediate-update\n" > "$seed_repo/scripts/lib/update.sh"
    git -C "$seed_repo" add scripts/lib/update.sh
    git -C "$seed_repo" commit -m intermediate >/dev/null
    intermediate_commit="$(git -C "$seed_repo" rev-parse HEAD)"
    git -C "$seed_repo" push origin release/test >/dev/null 2>&1

    printf "final-update\n" > "$seed_repo/scripts/lib/update.sh"
    git -C "$seed_repo" add scripts/lib/update.sh
    git -C "$seed_repo" commit -m final >/dev/null
    git -C "$seed_repo" push origin release/test >/dev/null 2>&1

    git -C "$work_repo" fetch origin release/test >/dev/null 2>&1
    git -C "$work_repo" show "$intermediate_commit:scripts/lib/update.sh" > "$work_repo/scripts/lib/update.sh"

    ACFS_REPO_ROOT="$work_repo"
    ACFS_HOME="$work_repo"
    UPDATE_LOG_FILE="/dev/null"
    NO_COLOR=1
    RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""

    log_item() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}"; }
    update_runtime_acfs_home() { printf "%s\n" "$work_repo"; }

    local_head="$(git -C "$work_repo" rev-parse HEAD)"
    remote_head="$(git -C "$work_repo" rev-parse origin/release/test)"

    run _acfs_try_upstream_derived_dirty_fast_forward "main" "$local_head" "$remote_head" "release/test"
    assert_success
    assert_output --partial "fix|ACFS self-update|tracked changes match upstream history; completing fast-forward"

    [[ "$(git -C "$work_repo" rev-parse HEAD)" == "$remote_head" ]]
    [[ -z "$(git -C "$work_repo" status --porcelain --untracked-files=no)" ]]
    upstream_ref="$(git -C "$work_repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"
    [[ "$upstream_ref" == "origin/release/test" ]]
}

@test "apt_lock_is_held: uses plain fuser when accessible" {
    init_stub_dir
    local lockfile="$HOME/dpkg.lock"
    local fuser_log="$HOME/fuser.log"
    : > "$lockfile"

    cat > "$STUB_DIR/fuser" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$fuser_log"
exit 0
EOF
    chmod +x "$STUB_DIR/fuser"

    update_system_binary_path() {
        case "${1:-}" in
            fuser) printf '%s\n' "$STUB_DIR/fuser" ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }

    run apt_lock_is_held "$lockfile"
    assert_success

    run cat "$fuser_log"
    assert_output --partial "$lockfile"
}

@test "apt_lock_is_held: falls back to sudo -n without prompting" {
    init_stub_dir
    local lockfile="$HOME/dpkg.lock"
    local sudo_log="$HOME/sudo.log"
    : > "$lockfile"

    cat > "$STUB_DIR/fuser" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$STUB_DIR/fuser"

    cat > "$STUB_DIR/sudo" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$sudo_log"
if [[ "\$1" == "-n" ]]; then
  exit 0
fi
exit 1
EOF
    chmod +x "$STUB_DIR/sudo"

    update_system_binary_path() {
        case "${1:-}" in
            fuser) printf '%s\n' "$STUB_DIR/fuser" ;;
            sudo) printf '%s\n' "$STUB_DIR/sudo" ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }

    run apt_lock_is_held "$lockfile"
    assert_success

    run cat "$sudo_log"
    assert_output --partial "-n $STUB_DIR/fuser $lockfile"
}

@test "wait_for_apt_lock: uses trusted fuser resolver instead of caller PATH" {
    init_stub_dir
    local empty_path="$HOME/empty-path"
    local log_file="$HOME/update.log"
    local old_path="$PATH"
    mkdir -p "$empty_path"
    : > "$log_file"

    QUIET=true
    DIM=""
    NC=""

    update_system_binary_path() {
        case "${1:-}" in
            fuser) printf '%s\n' "$STUB_DIR/fuser" ;;
            *) return 1 ;;
        esac
    }

    apt_lock_is_held() {
        return 1
    }

    apt_lock_holder_details() {
        return 1
    }

    log_to_file() {
        printf '%s\n' "$*" >> "$log_file"
    }

    log_item() {
        :
    }

    PATH="$empty_path"
    run wait_for_apt_lock 1
    PATH="$old_path"

    assert_success
    run grep -F "fuser not available" "$log_file"
    assert_failure
}

@test "fix_apt_issues: fails when interrupted dpkg repair fails" {
    init_stub_dir
    export PATH="$STUB_DIR:$PATH"
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    ABORT_ON_FAILURE=false
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0

    cat > "$STUB_DIR/ls" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  /var/lib/dpkg/updates/*) exit 0 ;;
  *) exit 1 ;;
esac
EOF
    chmod +x "$STUB_DIR/ls"

    cat > "$STUB_DIR/dpkg" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --configure)
    echo "dpkg repair failed" >&2
    exit 27
    ;;
  -l)
    exit 0
    ;;
esac
exit 0
EOF
    chmod +x "$STUB_DIR/dpkg"

    get_sudo() { printf '%s\n' ""; }

    run fix_apt_issues

    assert_failure
    assert_output --partial "[fail] dpkg repair"
    assert_output --partial "dpkg --configure -a failed (exit 27)"
    run grep -F "dpkg output: dpkg repair failed" "$UPDATE_LOG_FILE"
    assert_success
}

@test "fix_apt_issues: fails when broken dependency repair fails" {
    init_stub_dir
    export PATH="$STUB_DIR:$PATH"
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    ABORT_ON_FAILURE=false
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0

    cat > "$STUB_DIR/dpkg" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -l)
    exit 0
    ;;
esac
exit 0
EOF
    chmod +x "$STUB_DIR/dpkg"

    cat > "$STUB_DIR/apt-get" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  check)
    echo "broken dependencies" >&2
    exit 1
    ;;
  -f)
    echo "fix install failed" >&2
    exit 42
    ;;
esac
exit 0
EOF
    chmod +x "$STUB_DIR/apt-get"

    get_sudo() { printf '%s\n' ""; }

    run fix_apt_issues

    assert_failure
    assert_output --partial "[fail] apt repair"
    assert_output --partial "apt-get -f install failed (exit 42)"
    run grep -F "apt-get -f output: fix install failed" "$UPDATE_LOG_FILE"
    assert_success
}

@test "update_apt: skips apt update and upgrade when repair fails" {
    init_stub_dir
    export PATH="$STUB_DIR:$PATH"
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    UPDATE_APT=true
    ABORT_ON_FAILURE=false
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0

    cat > "$STUB_DIR/apt-get" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$HOME/apt-get-called"
exit 0
EOF
    chmod +x "$STUB_DIR/apt-get"

    update_disable_needrestart_apt_hook() { :; }
    check_apt_lock() { return 0; }
    fix_apt_issues() {
        update_finish_cmd_fail "apt repair" "synthetic repair failure"
        return 1
    }
    check_reboot_required() {
        : > "$HOME/reboot-check-called"
    }

    run update_apt

    assert_success
    assert_output --partial "[fail] apt repair"
    [[ ! -f "$HOME/apt-get-called" ]]
    [[ ! -f "$HOME/reboot-check-called" ]]
}

@test "update_require_security: sources repo-local scripts/lib/security.sh" {
    local repo_root
    local marker_file

    repo_root="$(create_temp_dir)"
    marker_file="$repo_root/security-sourced.marker"

    mkdir -p "$repo_root/scripts/lib"
    cat > "$repo_root/scripts/lib/security.sh" <<EOF
#!/usr/bin/env bash
load_checksums() {
    : > "$marker_file"
    return 0
}
EOF
    chmod +x "$repo_root/scripts/lib/security.sh"

    export ACFS_BIN_DIR="$repo_root/missing-bin"
    export ACFS_HOME="$repo_root/missing-home"
    export ACFS_REPO_ROOT="$repo_root"
    export CHECKSUMS_LOCAL="$repo_root/checksums.yaml"
    UPDATE_SECURITY_READY=false

    refresh_checksums() {
        return 0
    }

    run update_require_security
    assert_success
    [[ -f "$marker_file" ]]
}

@test "update_require_security: does not probe bogus repo path when ACFS_REPO_ROOT is unset" {
    export ACFS_BIN_DIR="$HOME/missing-bin"
    export ACFS_HOME="$HOME/missing-home"
    unset ACFS_REPO_ROOT
    export CHECKSUMS_LOCAL="$HOME/checksums.yaml"
    UPDATE_SECURITY_READY=false

    refresh_checksums() {
        return 0
    }

    run update_require_security
    assert_failure
    assert_output --partial "$ACFS_BIN_DIR/security.sh"
    assert_output --partial "$HOME/.acfs/scripts/lib/security.sh"
    refute_output --partial "$ACFS_HOME/scripts/lib/security.sh"
    refute_output --partial "    - /scripts/lib/security.sh"
}

@test "update_run_logged_passthrough streams command output and writes update log" {
    QUIET=false
    UPDATE_LOG_FILE="$HOME/update.log"

    run update_run_logged_passthrough bash -c 'echo installer detail; echo installer warning >&2'
    assert_success
    assert_output --partial "installer detail"
    assert_output --partial "installer warning"

    run grep -F -- "----- COMMAND:" "$UPDATE_LOG_FILE"
    assert_success
    run grep -F "installer detail" "$UPDATE_LOG_FILE"
    assert_success
    run grep -F "installer warning" "$UPDATE_LOG_FILE"
    assert_success
}

@test "update_run_logged_passthrough keeps quiet console quiet but logs output" {
    QUIET=true
    UPDATE_LOG_FILE="$HOME/update.log"

    run update_run_logged_passthrough bash -c 'echo quiet detail; echo quiet warning >&2'
    assert_success
    refute_output --partial "quiet detail"
    refute_output --partial "quiet warning"

    run grep -F "quiet detail" "$UPDATE_LOG_FILE"
    assert_success
    run grep -F "quiet warning" "$UPDATE_LOG_FILE"
    assert_success
}

@test "update_run_logged_passthrough preserves command failure status" {
    QUIET=true
    UPDATE_LOG_FILE="$HOME/update.log"

    run update_run_logged_passthrough bash -c 'echo failing detail; exit 7'
    [[ "$status" -eq 7 ]]
    run grep -F "failing detail" "$UPDATE_LOG_FILE"
    assert_success
}

@test "update_atuin: falls back to reinstall after failed self-update" {
    init_stub_dir
    export PATH="$STUB_DIR:$PATH"
    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=1
    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=0
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    YES_MODE=false
    ABORT_ON_FAILURE=false
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    SKIP_COUNT=0

    cat > "$STUB_DIR/atuin" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --help)
    echo "self-update"
    ;;
  self-update)
    echo "curl: (28) operation timed out" >&2
    exit 1
    ;;
  --version)
    echo "atuin 1.0.0"
    ;;
  *)
    echo "atuin 1.0.0"
    ;;
esac
EOF
    chmod +x "$STUB_DIR/atuin"

    update_require_security() {
        return 0
    }

    update_run_verified_installer() {
        : > "$HOME/atuin-reinstall-ran"
        return 0
    }

    update_atuin

    [[ -f "$HOME/atuin-reinstall-ran" ]]
    [[ "$SUCCESS_COUNT" -eq 1 ]]
    [[ "$FAIL_COUNT" -eq 0 ]]
}

@test "update_repair_atuin_install: uses target atuin as shim source when HOME differs" {
    local current_home
    local target_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER
    export ACFS_BIN_DIR="$target_home/custom-bin"
    mkdir -p "$current_home/.atuin/bin" "$target_home/.atuin/bin"

    cat > "$current_home/.atuin/bin/atuin" <<'EOF'
#!/usr/bin/env bash
echo "current-home"
EOF
    chmod +x "$current_home/.atuin/bin/atuin"

    cat > "$target_home/.atuin/bin/atuin" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "atuin 18.14.1"
else
  echo "target-home"
fi
EOF
    chmod +x "$target_home/.atuin/bin/atuin"

    run update_repair_atuin_install
    assert_success

    [[ -L "$ACFS_BIN_DIR/atuin" ]]
    [[ -L "$target_home/.local/bin/atuin" ]]

    run readlink "$ACFS_BIN_DIR/atuin"
    assert_output "$target_home/.atuin/bin/atuin"

    run readlink "$target_home/.local/bin/atuin"
    assert_output "$target_home/.atuin/bin/atuin"
}

@test "update_repair_atuin_install: normalizes custom and local shims" {
    export ACFS_BIN_DIR="$HOME/custom-bin"
    mkdir -p "$HOME/.atuin/bin"

    cat > "$HOME/.atuin/bin/atuin" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "atuin 18.14.1"
else
  echo "atuin 18.14.1"
fi
EOF
    chmod +x "$HOME/.atuin/bin/atuin"

    run update_repair_atuin_install
    assert_success

    [[ -L "$ACFS_BIN_DIR/atuin" ]]
    [[ -L "$HOME/.local/bin/atuin" ]]

    run readlink "$ACFS_BIN_DIR/atuin"
    assert_output "$HOME/.atuin/bin/atuin"

    run readlink "$HOME/.local/bin/atuin"
    assert_output "$HOME/.atuin/bin/atuin"
}

@test "update_repair_atuin_install: does not repair from current HOME for different unresolved target" {
    local current_home
    current_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_USER="missinguser"
    export TARGET_HOME="/"
    export ACFS_BIN_DIR="$current_home/custom-bin"
    mkdir -p "$current_home/.atuin/bin" "$ACFS_BIN_DIR"

    getent() {
        return 2
    }

    cat > "$current_home/.atuin/bin/atuin" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "atuin 18.14.1"
else
  echo "wrong-home-atuin"
fi
EOF
    chmod +x "$current_home/.atuin/bin/atuin"

    run update_repair_atuin_install
    assert_failure
    [[ ! -e "$ACFS_BIN_DIR/atuin" ]]
}

@test "update_repair_zoxide_install: normalizes custom shim to target local bin" {
    export ACFS_BIN_DIR="$HOME/custom-bin"
    mkdir -p "$HOME/.local/bin" "$ACFS_BIN_DIR"

    cat > "$HOME/.local/bin/zoxide" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "zoxide 0.9.9"
else
  echo "zoxide 0.9.9"
fi
EOF
    chmod +x "$HOME/.local/bin/zoxide"

    cat > "$ACFS_BIN_DIR/zoxide" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "zoxide 0.9.8"
else
  echo "stale-custom-copy"
fi
EOF
    chmod +x "$ACFS_BIN_DIR/zoxide"

    run update_repair_zoxide_install
    assert_success

    [[ -L "$ACFS_BIN_DIR/zoxide" ]]

    run readlink "$ACFS_BIN_DIR/zoxide"
    assert_output "$HOME/.local/bin/zoxide"
}

@test "update_repair_uv_install: normalizes custom shim to target local bin" {
    export ACFS_BIN_DIR="$HOME/custom-bin"
    mkdir -p "$HOME/.local/bin" "$ACFS_BIN_DIR"

    cat > "$HOME/.local/bin/uv" <<'EOF'
#!/usr/bin/env bash
echo "uv 0.8.0"
EOF
    chmod +x "$HOME/.local/bin/uv"

    cat > "$HOME/.local/bin/uvx" <<'EOF'
#!/usr/bin/env bash
echo "uvx 0.8.0"
EOF
    chmod +x "$HOME/.local/bin/uvx"

    cat > "$ACFS_BIN_DIR/uv" <<'EOF'
#!/usr/bin/env bash
echo "uv 0.7.0"
EOF
    chmod +x "$ACFS_BIN_DIR/uv"

    run update_repair_uv_install
    assert_success

    [[ -L "$ACFS_BIN_DIR/uv" ]]
    [[ -L "$ACFS_BIN_DIR/uvx" ]]

    run readlink "$ACFS_BIN_DIR/uv"
    assert_output "$HOME/.local/bin/uv"

    run readlink "$ACFS_BIN_DIR/uvx"
    assert_output "$HOME/.local/bin/uvx"
}

@test "install_atuin: does not skip target install because of a global atuin or partial target dir" {
    source_lib "cli_tools"
    init_stub_dir

    export PATH="$STUB_DIR:$PATH"
    export TARGET_USER="tester"
    export TARGET_HOME="$HOME/target-home"
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/.atuin"

    cat > "$STUB_DIR/atuin" <<'EOF'
#!/usr/bin/env bash
echo "global atuin"
EOF
    chmod +x "$STUB_DIR/atuin"

    CLI_RUN_AS_USER_CALLS=0

    _cli_target_home() {
        printf '%s\n' "$TARGET_HOME"
    }

    _cli_require_security() {
        return 0
    }

    _cli_normalize_atuin_shims() {
        :
    }

    _cli_run_as_user() {
        CLI_RUN_AS_USER_CALLS=$((CLI_RUN_AS_USER_CALLS + 1))
        mkdir -p "$TARGET_HOME/.atuin/bin"
        cat > "$TARGET_HOME/.atuin/bin/atuin" <<'EOF'
#!/usr/bin/env bash
echo "atuin 18.14.1"
EOF
        chmod +x "$TARGET_HOME/.atuin/bin/atuin"
        return 0
    }

    declare -gA KNOWN_INSTALLERS=(["atuin"]="https://example.com")
    get_checksum() {
        echo "deadbeef"
    }

    install_atuin

    [[ "$CLI_RUN_AS_USER_CALLS" -eq 1 ]]
    [[ -x "$TARGET_HOME/.atuin/bin/atuin" ]]
}

@test "_cli_target_has_command: ignores current-shell-only PATH entries" {
    source_lib "cli_tools"
    init_stub_dir

    export PATH="$STUB_DIR:$PATH"
    export TARGET_USER="tester"
    export TARGET_HOME="$HOME/target-home"
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$TARGET_HOME/.local/bin"

    cat > "$STUB_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
echo "current shell only"
EOF
    chmod +x "$STUB_DIR/current-shell-only-tool"

    _cli_target_home() {
        printf '%s\n' "$TARGET_HOME"
    }

    run _cli_target_has_command "current-shell-only-tool"
    assert_failure
}

@test "acfs.zshrc: loads atuin env before atuin init" {
    local zshrc="$PROJECT_ROOT/acfs/zsh/acfs.zshrc"
    local env_line=""
    local init_line=""

    env_line="$(grep -nF 'source "$HOME/.atuin/bin/env"' "$zshrc" | cut -d: -f1)"
    init_line="$(grep -nF 'eval "$("$_ACFS_ATUIN_BIN" init zsh)"' "$zshrc" | cut -d: -f1)"

    [[ -n "$env_line" ]]
    [[ -n "$init_line" ]]
    (( env_line < init_line ))
}

@test "acfs.zshrc: resolves atuin binary once for init and bindings" {
    local zshrc="$PROJECT_ROOT/acfs/zsh/acfs.zshrc"

    run grep -F '_ACFS_ATUIN_BIN=""' "$zshrc"
    assert_success

    run grep -F 'eval "$("$_ACFS_ATUIN_BIN" init zsh)"' "$zshrc"
    assert_success

    run grep -F 'if [[ -n "$_ACFS_ATUIN_BIN" ]]; then' "$zshrc"
    assert_success
}

@test "sync_acfs_zsh_loader: removes duplicate local override sourcing" {
    cat > "$HOME/.zshrc" <<'EOF'
# ACFS loader
source "$HOME/.acfs/zsh/acfs.zshrc"

# User overrides live here forever
  [ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
EOF

    run sync_acfs_zsh_loader
    assert_success

    run cat "$HOME/.zshrc"
    refute_output --partial '[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"'
    assert_output --partial 'source "$HOME/.acfs/zsh/acfs.zshrc"'
}

@test "sync_acfs_zsh_loader: leaves non-ACFS zshrc untouched" {
    cat > "$HOME/.zshrc" <<'EOF'
# custom zshrc
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
EOF

    run sync_acfs_zsh_loader
    assert_success

    run cat "$HOME/.zshrc"
    assert_output --partial '[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"'
    refute_output --partial 'source "$HOME/.acfs/zsh/acfs.zshrc"'
}

@test "sync_acfs_zsh_loader: ignores commented ACFS loader references" {
    cat > "$HOME/.zshrc" <<'EOF'
# source "$HOME/.acfs/zsh/acfs.zshrc"
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
EOF

    run sync_acfs_zsh_loader
    assert_success

    run cat "$HOME/.zshrc"
    assert_output --partial '[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"'
}

@test "_update_sed_literal: keeps parentheses literal in sed BRE replacements" {
    local literal='export PATH="$HOME/(weird)[bin]*.^$|\end:$PATH"'
    local escaped

    escaped="$(_update_sed_literal "$literal")"

    run bash -c 'printf "%s\n" "$1" | sed "s|^$2$|replaced|"' _ "$literal" "$escaped"
    assert_success
    assert_output "replaced"
}

@test "sync_acfs_profile_paths: upgrades legacy ACFS login PATH line" {
    cat > "$HOME/.profile" <<'EOF'
# ~/.profile: executed by bash for login shells

# User binary paths
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
EOF

    run sync_acfs_profile_paths
    assert_success

    run cat "$HOME/.profile"
    assert_output --partial 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
    refute_output --partial 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
}

@test "sync_acfs_zprofile_paths: upgrades legacy ACFS zsh login PATH line" {
    cat > "$HOME/.zprofile" <<'EOF'
# ~/.zprofile: executed by zsh for login shells

# User binary paths
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
EOF

    run sync_acfs_zprofile_paths
    assert_success

    run cat "$HOME/.zprofile"
    assert_output --partial 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
    refute_output --partial 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
}

@test "sync_acfs_profile_paths: creates missing profile with Atuin login PATH" {
    [[ ! -e "$HOME/.profile" ]]

    run sync_acfs_profile_paths
    assert_success

    run cat "$HOME/.profile"
    assert_output --partial '# ~/.profile: executed by bash for login shells'
    assert_output --partial '# User binary paths'
    assert_output --partial 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
}

@test "sync_acfs_zprofile_paths: creates missing zprofile with Atuin login PATH" {
    [[ ! -e "$HOME/.zprofile" ]]

    run sync_acfs_zprofile_paths
    assert_success

    run cat "$HOME/.zprofile"
    assert_output --partial '# ~/.zprofile: executed by zsh for login shells'
    assert_output --partial '# User binary paths'
    assert_output --partial 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
}

@test "sync_acfs_profile_paths: adds Atuin login PATH when custom profile lacks it" {
    cat > "$HOME/.profile" <<'EOF'
# custom login profile
export PATH="$HOME/.local/bin:/opt/custom/bin:$PATH"
EOF

    run sync_acfs_profile_paths
    assert_success

    run cat "$HOME/.profile"
    assert_output --partial '# custom login profile'
    assert_output --partial 'export PATH="$HOME/.local/bin:/opt/custom/bin:$PATH"'
    assert_output --partial '# Added by ACFS - user binary paths'
    assert_output --partial 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
}

@test "sync_acfs_profile_paths: ignores commented Atuin mention when repairing login PATH" {
    cat > "$HOME/.profile" <<'EOF'
# .atuin/bin appears in this comment but not in the active PATH
# export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
export PATH="$HOME/.local/bin:/opt/custom/bin:$PATH"
EOF

    run sync_acfs_profile_paths
    assert_success

    run cat "$HOME/.profile"
    assert_output --partial '# .atuin/bin appears in this comment but not in the active PATH'
    assert_output --partial '# export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
    assert_output --partial '# Added by ACFS - user binary paths'
    assert_output --partial 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
}

@test "sync_acfs_zprofile_paths: adds Atuin login PATH when custom zprofile lacks it" {
    cat > "$HOME/.zprofile" <<'EOF'
# custom zsh login profile
export PATH="$HOME/.local/bin:/opt/custom/bin:$PATH"
EOF

    run sync_acfs_zprofile_paths
    assert_success

    run cat "$HOME/.zprofile"
    assert_output --partial '# custom zsh login profile'
    assert_output --partial 'export PATH="$HOME/.local/bin:/opt/custom/bin:$PATH"'
    assert_output --partial '# Added by ACFS - user binary paths'
    assert_output --partial 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
}

@test "sync_acfs_zprofile_paths: ignores commented Atuin mention when repairing login PATH" {
    cat > "$HOME/.zprofile" <<'EOF'
# .atuin/bin appears in this comment but not in the active PATH
# export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
export PATH="$HOME/.local/bin:/opt/custom/bin:$PATH"
EOF

    run sync_acfs_zprofile_paths
    assert_success

    run cat "$HOME/.zprofile"
    assert_output --partial '# .atuin/bin appears in this comment but not in the active PATH'
    assert_output --partial '# export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
    assert_output --partial '# Added by ACFS - user binary paths'
    assert_output --partial 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
}

@test "sync_acfs_profile_paths: respects TARGET_HOME when HOME differs" {
    local current_home
    local target_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER

    cat > "$current_home/.profile" <<'EOF'
# current profile
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
EOF

    cat > "$target_home/.profile" <<'EOF'
# target profile
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
EOF

    run sync_acfs_profile_paths
    assert_success

    run cat "$target_home/.profile"
    assert_output --partial 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'

    run cat "$current_home/.profile"
    refute_output --partial '.atuin/bin'
}

@test "sync_acfs_profile_paths: does not touch current HOME for unresolved explicit target" {
    local current_home
    current_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_USER="missinguser"
    export TARGET_HOME="/"

    cat > "$current_home/.profile" <<'EOF'
# current profile
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
EOF

    getent() {
        return 2
    }

    run sync_acfs_profile_paths
    assert_success

    run cat "$current_home/.profile"
    refute_output --partial '.atuin/bin'
}

@test "sync_acfs_zprofile_paths: respects TARGET_HOME when HOME differs" {
    local current_home
    local target_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER

    cat > "$current_home/.zprofile" <<'EOF'
# current zprofile
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
EOF

    cat > "$target_home/.zprofile" <<'EOF'
# target zprofile
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
EOF

    run sync_acfs_zprofile_paths
    assert_success

    run cat "$target_home/.zprofile"
    assert_output --partial 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'

    run cat "$current_home/.zprofile"
    refute_output --partial '.atuin/bin'
}

@test "sync_acfs_zsh_loader: respects TARGET_HOME when HOME differs" {
    local current_home
    local target_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER

    cat > "$current_home/.zshrc" <<'EOF'
# current zshrc
source "$HOME/.acfs/zsh/acfs.zshrc"
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
EOF

    cat > "$target_home/.zshrc" <<'EOF'
# target zshrc
source "$HOME/.acfs/zsh/acfs.zshrc"
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
EOF

    run sync_acfs_zsh_loader
    assert_success

    run cat "$target_home/.zshrc"
    refute_output --partial '[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"'

    run cat "$current_home/.zshrc"
    assert_output --partial '[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"'
}

@test "cleanup_legacy_git_safety_guard: respects TARGET_HOME when HOME differs" {
    local current_home
    local target_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER

    mkdir -p "$current_home/.claude/hooks" "$target_home/.claude/hooks"
    printf 'current\n' > "$current_home/.claude/hooks/git_safety_guard.sh"
    printf 'target\n' > "$target_home/.claude/hooks/git_safety_guard.sh"

    run cleanup_legacy_git_safety_guard
    assert_success

    [[ -f "$current_home/.claude/hooks/git_safety_guard.sh" ]]
    [[ ! -e "$target_home/.claude/hooks/git_safety_guard.sh" ]]
}

@test "cleanup_legacy_git_safety_guard: detects only real Claude hook commands" {
    local settings_file
    command -v jq >/dev/null 2>&1 || skip "jq required for Claude settings parsing"

    settings_file="$BATS_TEST_TMPDIR/settings.json"

    cat > "$settings_file" <<'EOF'
{
  "notes": "git_safety_guard was replaced by DCG",
  "hooks": {
    "PreToolUse": []
  }
}
EOF
    run update_claude_settings_has_legacy_git_safety_guard_hook "$settings_file"
    assert_failure

    cat > "$settings_file" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/home/ubuntu/.claude/hooks/git_safety_guard.sh"
          }
        ]
      }
    ]
  }
}
EOF
    run update_claude_settings_has_legacy_git_safety_guard_hook "$settings_file"
    assert_success
}

@test "cleanup_legacy_git_safety_guard: removes only legacy command hook entries" {
    local target_home
    local settings_file
    command -v jq >/dev/null 2>&1 || skip "jq required for Claude settings cleanup"

    target_home="$(create_temp_dir)"
    settings_file="$target_home/.claude/settings.json"

    export HOME="$target_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER

    mkdir -p "$(dirname "$settings_file")"
    cat > "$settings_file" <<'EOF'
{
  "notes": "git_safety_guard was replaced by DCG",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "description": "old git_safety_guard docs, not a command",
        "hooks": [
          {
            "type": "command",
            "command": "dcg guard --source claude"
          },
          {
            "type": "command",
            "command": "/home/ubuntu/.claude/hooks/git_safety_guard.sh"
          }
        ]
      }
    ]
  }
}
EOF

    run cleanup_legacy_git_safety_guard
    assert_success

    run jq -r '.notes' "$settings_file"
    assert_success
    assert_output "git_safety_guard was replaced by DCG"

    run jq -r '.hooks.PreToolUse[0].description' "$settings_file"
    assert_success
    assert_output "old git_safety_guard docs, not a command"

    run jq -r '.hooks.PreToolUse[0].hooks | length' "$settings_file"
    assert_success
    assert_output "1"

    run jq -r '.hooks.PreToolUse[0].hooks[0].command' "$settings_file"
    assert_success
    assert_output "dcg guard --source claude"
}

@test "cleanup_legacy_bv_alias: respects TARGET_HOME when HOME differs" {
    local current_home
    local target_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER

    cat > "$current_home/.zshrc.local" <<'EOF'
alias bv="current"
EOF

    cat > "$target_home/.zshrc.local" <<'EOF'
alias bv="target"
EOF

    run cleanup_legacy_bv_alias
    assert_success

    run cat "$current_home/.zshrc.local"
    assert_output --partial 'alias bv="current"'

    run cat "$target_home/.zshrc.local"
    refute_output --partial 'alias bv='
}

@test "cleanup_legacy_bv_alias: ignores commented legacy bv examples" {
    local target_home
    target_home="$(create_temp_dir)"

    export HOME="$target_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER

    cat > "$target_home/.zshrc.local" <<'EOF'
# alias bv="old"
# if [ -x "$HOME/.local/bin/bv" ]; then
#   alias bv="$HOME/.local/bin/bv"
# fi
alias keep_me="true"
EOF

    run cleanup_legacy_bv_alias
    assert_success

    run cat "$target_home/.zshrc.local"
    assert_output --partial '# alias bv="old"'
    assert_output --partial '# if [ -x "$HOME/.local/bin/bv" ]; then'
    assert_output --partial 'alias keep_me="true"'
}

@test "cleanup_legacy_bv_alias: removes indented legacy bv alias block" {
    local target_home
    target_home="$(create_temp_dir)"

    export HOME="$target_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER

    cat > "$target_home/.zshrc.local" <<'EOF'
before=1
  if [ -x "$HOME/.local/bin/bv" ]; then
    alias bv="$HOME/.local/bin/bv"
  fi
after=1
EOF

    run cleanup_legacy_bv_alias
    assert_success

    run cat "$target_home/.zshrc.local"
    assert_output --partial 'before=1'
    assert_output --partial 'after=1'
    refute_output --partial 'alias bv='
    refute_output --partial '.local/bin/bv'
}

@test "cleanup_legacy_br_alias: respects TARGET_HOME when HOME differs" {
    local current_home
    local target_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER

    mkdir -p "$current_home/.acfs/zsh" "$target_home/.acfs/zsh"
    cat > "$current_home/.acfs/zsh/acfs.zshrc" <<'EOF'
alias br='bun run dev'
EOF

    cat > "$target_home/.acfs/zsh/acfs.zshrc" <<'EOF'
alias br='bun run dev'
EOF

    run cleanup_legacy_br_alias
    assert_success

    run cat "$current_home/.acfs/zsh/acfs.zshrc"
    assert_output --partial "alias br='bun run dev'"

    run grep -n "^alias br='bun run dev'$" "$target_home/.acfs/zsh/acfs.zshrc"
    assert_failure

    run cat "$target_home/.acfs/zsh/acfs.zshrc"
    assert_output --partial "# alias br='bun run dev'"
}

@test "generated install_shell: uses minimal loader and Atuin-aware login paths" {
    local generated="$PROJECT_ROOT/scripts/generated/install_shell.sh"

    run grep -F 'echo '\''source "$HOME/.acfs/zsh/acfs.zshrc"'\'' >> ~/.zshrc' "$generated"
    assert_success

    run grep -F 'acfs_zshrc_is_managed_loader() {' "$generated"
    assert_success

    run grep -F 'acfs_external_shell_handoff_configured() {' "$generated"
    assert_success

    run grep -F "grep -q 'ACFS externally-managed shell handoff' ~/.bashrc" "$generated"
    assert_failure

    run grep -F 'grep -q "ACFS loader" ~/.zshrc' "$generated"
    assert_failure

    run grep -F 'echo '\''[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"'\'' >> ~/.zshrc' "$generated"
    assert_failure

    run grep -F 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"' "$generated"
    assert_success

    run grep -F 'grep -Fxq "$legacy_profile_path_line"' "$generated"
    assert_success
}

@test "generated install_cloud: preserves wrangler bun shim fallback" {
    local generated="$PROJECT_ROOT/scripts/generated/install_cloud.sh"

    run grep -F 'command -v node >/dev/null 2>&1' "$generated"
    assert_success

    run grep -F 'exec "$HOME/.bun/bin/bun" x wrangler@latest "$@"' "$generated"
    assert_success

    run grep -F 'acfs_install_executable_into_primary_bin "$wrapper_tmp" "wrangler"' "$generated"
    assert_success
}

@test "generated installers: reject invalid TARGET_HOME and ACFS_BIN_DIR" {
    local generated="$PROJECT_ROOT/scripts/generated/install_all.sh"
    local doctor_checks="$PROJECT_ROOT/scripts/generated/doctor_checks.sh"

    run grep -F '_acfs_validate_target_user "${TARGET_USER}" "TARGET_USER" || exit 1' "$generated"
    assert_success

    run grep -F '[[ "${TARGET_HOME}" == "/" ]]' "$generated"
    assert_success

    run grep -F "Invalid TARGET_HOME for '\${TARGET_USER}': \${TARGET_HOME:-<empty>} (must be an absolute path and cannot be '/')" "$generated"
    assert_success

    run grep -F '[[ "$_acfs_current_home" != "/" ]]' "$generated"
    assert_success

    run grep -F '_ACFS_EXPLICIT_TARGET_HOME="${TARGET_HOME:-}"' "$generated"
    assert_success

    run grep -F '_ACFS_RESOLVED_TARGET_HOME="$(_acfs_resolve_target_home "${TARGET_USER}" "$_ACFS_EXPLICIT_TARGET_HOME" || true)"' "$generated"
    assert_success

    run grep -F 'TARGET_HOME="$_ACFS_EXPLICIT_TARGET_HOME"' "$generated"
    assert_failure

    run grep -F '_ACFS_RESOLVED_TARGET_HOME="$_acfs_current_home"' "$generated"
    assert_success

    run grep -F 'TARGET_HOME="${HOME%/}"' "$generated"
    assert_failure

    run grep -F '{ [[ -z "$_ACFS_EXPLICIT_TARGET_HOME" ]] || [[ "$_acfs_current_home" == "$_ACFS_EXPLICIT_TARGET_HOME" ]]; }' "$generated"
    assert_success

    run grep -F "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: \${ACFS_BIN_DIR:-<empty>})" "$generated"
    assert_success

    run grep -F "Invalid TARGET_HOME for '\$target_user': \${target_home:-<empty>} (must be an absolute path and cannot be '/')" "$doctor_checks"
    assert_success

    run grep -F '[[ "$current_home" != "/" ]]' "$doctor_checks"
    assert_success

    run grep -F 'explicit_target_home="$target_home"' "$doctor_checks"
    assert_success

    run grep -F 'resolved_target_home="$current_home"' "$doctor_checks"
    assert_success

    run grep -F 'target_home="${HOME%/}"' "$doctor_checks"
    assert_failure

    run grep -F '{ [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }' "$doctor_checks"
    assert_success

    run grep -F '_acfs_validate_target_user "$target_user" "TARGET_USER" || return 1' "$doctor_checks"
    assert_success

    run grep -F "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: \${target_bin:-<empty>})" "$doctor_checks"
    assert_success
}

@test "scripts/lib/zsh.sh: mirrors Atuin-aware login PATH setup" {
    local zsh_lib="$PROJECT_ROOT/scripts/lib/zsh.sh"

    run grep -F 'local user_zprofile="$HOME/.zprofile"' "$zsh_lib"
    assert_success

    run grep -F '_zsh_is_managed_loader() {' "$zsh_lib"
    assert_success

    run grep -F 'zsh_external_shell_handoff_configured() {' "$zsh_lib"
    assert_success

    run grep -F "grep -q 'ACFS externally-managed shell handoff' \"\$bashrc\"" "$zsh_lib"
    assert_failure

    run grep -F 'grep -q "ACFS loader" "$user_zshrc"' "$zsh_lib"
    assert_failure

    run grep -F 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"' "$zsh_lib"
    assert_success

    run grep -F 'grep -Fxq "$legacy_profile_path_line"' "$zsh_lib"
    assert_success

    run grep -F '# ACFS loader — user overrides go in ~/.zshrc.local (sourced by acfs.zshrc)' "$zsh_lib"
    assert_success
}

@test "scripts/lib/zsh.sh: resolves shell user via trusted helpers" {
    local zsh_lib="$PROJECT_ROOT/scripts/lib/zsh.sh"

    run grep -F 'current_user="$(zsh_resolve_current_user 2>/dev/null || true)"' "$zsh_lib"
    assert_success

    run grep -F 'passwd_entry="$(zsh_getent_passwd_entry "$current_user" 2>/dev/null || true)"' "$zsh_lib"
    assert_success

    run grep -F 'if zsh_is_externally_managed_user "$current_user"; then' "$zsh_lib"
    assert_success

    run grep -F '$SUDO "$chsh_path" -s "$zsh_path" "$current_user"' "$zsh_lib"
    assert_success

    run grep -F 'getent passwd "$(whoami)"' "$zsh_lib"
    assert_failure
}

@test "scripts/preflight.sh: resolves identity and passwd data via trusted helpers" {
    local preflight="$PROJECT_ROOT/scripts/preflight.sh"

    run grep -F 'id_bin="$(preflight_system_binary_path id 2>/dev/null || true)"' "$preflight"
    assert_success

    run grep -F 'whoami_bin="$(preflight_system_binary_path whoami 2>/dev/null || true)"' "$preflight"
    assert_success

    run grep -F 'done < <(preflight_getent_passwd_entry 2>/dev/null || true)' "$preflight"
    assert_success

    run grep -F 'passwd_entry="$(preflight_getent_passwd_entry "$user" 2>/dev/null || true)"' "$preflight"
    assert_success

    run grep -F 'current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"' "$preflight"
    assert_failure

    run grep -F 'getent passwd "$user"' "$preflight"
    assert_failure
}

@test "scripts/lib/smoke_test.sh: validates bin dirs via trusted passwd helpers" {
    local smoke_lib="$PROJECT_ROOT/scripts/lib/smoke_test.sh"

    run grep -F 'if [[ -z "$user" ]]; then' "$smoke_lib"
    assert_success

    run grep -F 'done < <(_smoke_getent_passwd_entry 2>/dev/null || true)' "$smoke_lib"
    assert_success

    run grep -F 'done < <(getent passwd 2>/dev/null || true)' "$smoke_lib"
    assert_failure
}

@test "scripts/lib/github_api.sh: validates bin dirs via trusted passwd helpers" {
    local github_api="$PROJECT_ROOT/scripts/lib/github_api.sh"

    run grep -F '_github_api_system_binary_path() {' "$github_api"
    assert_success

    run grep -F '_github_api_getent_passwd_entry() {' "$github_api"
    assert_success

    run grep -F 'done < <(_github_api_getent_passwd_entry 2>/dev/null || true)' "$github_api"
    assert_success

    run grep -F 'done < <(getent passwd 2>/dev/null || true)' "$github_api"
    assert_failure
}

@test "services-setup and wrappers parse passwd homes via helpers" {
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local update_wrapper="$PROJECT_ROOT/scripts/acfs-update"
    local global_wrapper="$PROJECT_ROOT/scripts/acfs-global"

    run grep -F 'services_setup_passwd_home_from_entry() {' "$services_setup"
    assert_success

    run grep -F 'home="$(services_setup_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"' "$services_setup"
    assert_success

    run grep -F 'done < <(services_setup_getent_passwd_entry 2>/dev/null || true)' "$services_setup"
    assert_success

    run grep -F 'cut -d: -f6' "$services_setup"
    assert_failure

    run grep -F 'awk -F: -v u=' "$services_setup"
    assert_failure

    run grep -F 'done < <(getent_passwd_entry 2>/dev/null || true)' "$update_wrapper"
    assert_success

    run grep -F 'done < <(getent_passwd_entry 2>/dev/null || true)' "$global_wrapper"
    assert_success

    run grep -F 'cut -d: -f6' "$update_wrapper"
    assert_failure

    run grep -F 'cut -d: -f6' "$global_wrapper"
    assert_failure
}

@test "auxiliary libs parse passwd homes via helpers" {
    local support="$PROJECT_ROOT/scripts/lib/support.sh"
    local status_lib="$PROJECT_ROOT/scripts/lib/status.sh"
    local info="$PROJECT_ROOT/scripts/lib/info.sh"
    local dashboard="$PROJECT_ROOT/scripts/lib/dashboard.sh"
    local export_config="$PROJECT_ROOT/scripts/lib/export-config.sh"
    local cheatsheet="$PROJECT_ROOT/scripts/lib/cheatsheet.sh"
    local continue_lib="$PROJECT_ROOT/scripts/lib/continue.sh"
    local changelog_lib="$PROJECT_ROOT/scripts/lib/changelog.sh"
    local notifications_lib="$PROJECT_ROOT/scripts/lib/notifications.sh"
    local notify_lib="$PROJECT_ROOT/scripts/lib/notify.sh"
    local webhook_lib="$PROJECT_ROOT/scripts/lib/webhook.sh"
    local agents_lib="$PROJECT_ROOT/scripts/lib/agents.sh"
    local cli_tools_lib="$PROJECT_ROOT/scripts/lib/cli_tools.sh"
    local languages_lib="$PROJECT_ROOT/scripts/lib/languages.sh"
    local cloud_db_lib="$PROJECT_ROOT/scripts/lib/cloud_db.sh"
    local stack_lib="$PROJECT_ROOT/scripts/lib/stack.sh"
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local doctor_fix_lib="$PROJECT_ROOT/scripts/lib/doctor_fix.sh"
    local user_lib="$PROJECT_ROOT/scripts/lib/user.sh"

    run grep -F 'support_passwd_home_from_entry() {' "$support"
    assert_success

    run grep -F 'done < <(support_getent_passwd_entry 2>/dev/null || true)' "$support"
    assert_success

    run grep -F '_status_passwd_home_from_entry() {' "$status_lib"
    assert_success

    run grep -F 'done < <(_status_getent_passwd_entry 2>/dev/null || true)' "$status_lib"
    assert_success

    run grep -F 'info_passwd_home_from_entry() {' "$info"
    assert_success

    run grep -F 'done < <(info_getent_passwd_entry 2>/dev/null || true)' "$info"
    assert_success

    run grep -F 'dashboard_passwd_home_from_entry() {' "$dashboard"
    assert_success

    run grep -F 'done < <(dashboard_getent_passwd_entry 2>/dev/null || true)' "$dashboard"
    assert_success

    run grep -F 'export_passwd_home_from_entry() {' "$export_config"
    assert_success

    run grep -F 'done < <(export_getent_passwd_entry 2>/dev/null || true)' "$export_config"
    assert_success

    run grep -F 'cheatsheet_passwd_home_from_entry() {' "$cheatsheet"
    assert_success

    run grep -F 'done < <(cheatsheet_getent_passwd_entry 2>/dev/null || true)' "$cheatsheet"
    assert_success

    run grep -F 'continue_passwd_home_from_entry() {' "$continue_lib"
    assert_success

    run grep -F 'continue_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true' "$continue_lib"
    assert_success

    run grep -F 'changelog_passwd_home_from_entry() {' "$changelog_lib"
    assert_success

    run grep -F 'changelog_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true' "$changelog_lib"
    assert_success

    run grep -F 'notifications_passwd_home_from_entry() {' "$notifications_lib"
    assert_success

    run grep -F 'notifications_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true' "$notifications_lib"
    assert_success

    run grep -F '_acfs_notify_passwd_home_from_entry() {' "$notify_lib"
    assert_success

    run grep -F '_acfs_notify_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true' "$notify_lib"
    assert_success

    run grep -F 'webhook_passwd_home_from_entry() {' "$webhook_lib"
    assert_success

    run grep -F 'webhook_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true' "$webhook_lib"
    assert_success

    run grep -F '_agent_passwd_home_from_entry() {' "$agents_lib"
    assert_success

    run grep -F 'done < <(_agent_getent_passwd_entry 2>/dev/null || true)' "$agents_lib"
    assert_success

    run grep -F '_cli_passwd_home_from_entry() {' "$cli_tools_lib"
    assert_success

    run grep -F 'done < <(_cli_getent_passwd_entry 2>/dev/null || true)' "$cli_tools_lib"
    assert_success

    run grep -F '_lang_passwd_home_from_entry() {' "$languages_lib"
    assert_success

    run grep -F '_lang_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true' "$languages_lib"
    assert_success

    run grep -F '_cloud_passwd_home_from_entry() {' "$cloud_db_lib"
    assert_success

    run grep -F '_cloud_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true' "$cloud_db_lib"
    assert_success

    run grep -F '_stack_passwd_home_from_entry() {' "$stack_lib"
    assert_success

    run grep -F '_stack_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true' "$stack_lib"
    assert_success

    run grep -F '_acfs_doctor_passwd_home_from_entry() {' "$doctor_lib"
    assert_success

    run grep -F '_acfs_doctor_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true' "$doctor_lib"
    assert_success

    run grep -F 'doctor_fix_passwd_home_from_entry() {' "$doctor_fix_lib"
    assert_success

    run grep -F 'doctor_fix_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true' "$doctor_fix_lib"
    assert_success

    run grep -F 'user_passwd_home_from_entry() {' "$user_lib"
    assert_success

    run grep -F 'user_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true' "$user_lib"
    assert_success

    run rg -n 'cut -d: -f6' "$support" "$status_lib" "$info" "$dashboard" "$export_config" "$cheatsheet" "$continue_lib" "$changelog_lib" "$notifications_lib" "$notify_lib" "$webhook_lib" "$agents_lib" "$cli_tools_lib" "$languages_lib" "$cloud_db_lib" "$stack_lib" "$doctor_lib" "$doctor_fix_lib" "$user_lib"
    assert_failure

    run rg -n 'awk -F: -v u=|awk -F: -v user=' "$doctor_lib" "$doctor_fix_lib" "$user_lib"
    assert_failure
}

@test "services-setup: probes custom and ACFS bin dirs for target-user commands" {
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local preflight="$PROJECT_ROOT/scripts/preflight.sh"

    run grep -F "services_setup_validate_target_user() {" "$services_setup"
    assert_success

    run grep -F 'services_setup_validate_target_user "$TARGET_USER" || return 1' "$services_setup"
    assert_success

    run grep -F 'local target_path_prefix="$primary_bin_dir:$TARGET_HOME/.local/bin:$TARGET_HOME/.acfs/bin:$TARGET_HOME/.cargo/bin:$TARGET_HOME/.bun/bin:$TARGET_HOME/.atuin/bin:$TARGET_HOME/go/bin"' "$services_setup"
    assert_success

    run grep -F 'run_as_user env ACFS_TARGET_PATH_PREFIX="$target_path_prefix" bash -c' "$services_setup"
    assert_success

    run grep -F '"$TARGET_HOME/.acfs/bin/$name"' "$services_setup"
    assert_success

    run grep -F "printf '/home/%s\n' \"\$current_user\"" "$services_setup"
    assert_failure

    run grep -F "printf '/home/%s' \"\$user\"" "$services_setup"
    assert_failure

    run grep -F "printf '/home/%s\n' \"\$current_user\"" "$preflight"
    assert_failure

    run grep -F "printf '/home/%s\n' \"\$target_user\"" "$preflight"
    assert_failure
}

@test "services-setup: run_as_user ignores function-poisoned whoami on same-user fast path" {
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local current_user
    local current_home

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        current_home="/root"
    else
        current_home="$(command getent passwd "$current_user" | cut -d: -f6)"
    fi
    current_home="${current_home%/}"
    mkdir -p "$current_home/.local/bin"

    eval "$(sed -n '/^services_setup_sanitize_abs_nonroot_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_valid_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_system_binary_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_getent_passwd_entry()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_bin_dir_for_home()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_resolve_current_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^run_as_user()/,/^}$/p' "$services_setup")"

    export TARGET_USER="$current_user"
    export TARGET_HOME="$current_home"
    export HOME="$current_home"
    export ACFS_BIN_DIR="$current_home/.local/bin"

    whoami() {
        printf 'poisoned-user\n'
    }

    sudo() {
        echo 'sudo should not run' >&2
        return 1
    }

    run run_as_user bash -c 'printf "%s\n" "$HOME"'
    assert_success
    assert_output "$current_home"
}

@test "services-setup: privilege handoff ignores function-poisoned system commands" {
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local stub_dir
    local safe_sudo
    local marker
    local env_bin
    local bash_bin
    local sh_bin
    stub_dir="$(create_temp_dir)"
    safe_sudo="$stub_dir/sudo"
    marker="$stub_dir/poisoned"
    env_bin="$(command -v env)"
    bash_bin="$(command -v bash)"
    sh_bin="$(command -v sh)"
    export TEST_SERVICES_ENV_BIN="$env_bin"
    export TEST_SERVICES_BASH_BIN="$bash_bin"
    export TEST_SERVICES_SH_BIN="$sh_bin"
    export TEST_SERVICES_SAFE_SUDO="$safe_sudo"
    export TEST_SERVICES_POISON_MARKER="$marker"

    cat > "$safe_sudo" <<'EOF'
#!/usr/bin/env bash
printf 'safe-sudo:%s\n' "$*"
EOF
    chmod +x "$safe_sudo"

    eval "$(sed -n '/^services_setup_sanitize_abs_nonroot_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_valid_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_bin_dir_for_home()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^run_as_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^run_as_user_shell()/,/^}$/p' "$services_setup")"

    log_error() {
        printf '%s\n' "$*" >&2
    }

    services_setup_resolve_current_user() {
        printf 'calleruser\n'
    }

    services_setup_system_binary_path() {
        case "${1:-}" in
            env) printf '%s\n' "$TEST_SERVICES_ENV_BIN" ;;
            bash) printf '%s\n' "$TEST_SERVICES_BASH_BIN" ;;
            sh) printf '%s\n' "$TEST_SERVICES_SH_BIN" ;;
            sudo) printf '%s\n' "$TEST_SERVICES_SAFE_SUDO" ;;
            runuser|su) return 1 ;;
            *) return 1 ;;
        esac
    }

    env() {
        printf 'env\n' > "$TEST_SERVICES_POISON_MARKER"
        return 99
    }
    sudo() {
        printf 'sudo\n' > "$TEST_SERVICES_POISON_MARKER"
        return 99
    }
    runuser() {
        printf 'runuser\n' > "$TEST_SERVICES_POISON_MARKER"
        return 99
    }
    su() {
        printf 'su\n' > "$TEST_SERVICES_POISON_MARKER"
        return 99
    }

    export TARGET_USER="acfsuser"
    export TARGET_HOME="$stub_dir/home"
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$ACFS_BIN_DIR"

    run run_as_user printf ok
    assert_success
    assert_output --partial "safe-sudo:"
    [[ ! -e "$marker" ]] || fail "function-poisoned command executed: $(<"$marker")"

    run run_as_user_shell 'printf ok'
    assert_success
    assert_output --partial "safe-sudo:"
    [[ ! -e "$marker" ]] || fail "function-poisoned command executed: $(<"$marker")"
}

@test "services-setup: run_as_user normalizes env/bash infrastructure argv" {
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local target_home
    local fake_env
    local fake_bash
    local marker
    local env_bin
    local bash_bin
    local sh_bin

    target_home="$(create_temp_dir)"
    fake_env="$target_home/.local/bin/env"
    fake_bash="$target_home/.local/bin/bash"
    marker="$target_home/poisoned"
    env_bin="$(command -v env)"
    bash_bin="$(command -v bash)"
    sh_bin="$(command -v sh)"
    mkdir -p "$(dirname "$fake_bash")"
    export TEST_SERVICES_TARGET_HOME="$target_home"
    export TEST_SERVICES_MARKER="$marker"
    export TEST_SERVICES_ENV_BIN="$env_bin"
    export TEST_SERVICES_BASH_BIN="$bash_bin"
    export TEST_SERVICES_SH_BIN="$sh_bin"

    cat > "$fake_env" <<'EOF'
#!/bin/sh
printf 'fake-env\n' > "$TEST_SERVICES_MARKER"
exit 99
EOF
    chmod +x "$fake_env"

    cat > "$fake_bash" <<'EOF'
#!/usr/bin/env bash
printf 'fake-bash\n' > "$TEST_SERVICES_MARKER"
exit 99
EOF
    chmod +x "$fake_bash"

    eval "$(sed -n '/^services_setup_sanitize_abs_nonroot_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_valid_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_bin_dir_for_home()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^run_as_user()/,/^}$/p' "$services_setup")"

    log_error() {
        printf '%s\n' "$*" >&2
    }

    services_setup_resolve_current_user() {
        printf 'acfsuser\n'
    }

    services_setup_system_binary_path() {
        case "${1:-}" in
            env) printf '%s\n' "$TEST_SERVICES_ENV_BIN" ;;
            bash) printf '%s\n' "$TEST_SERVICES_BASH_BIN" ;;
            sh) printf '%s\n' "$TEST_SERVICES_SH_BIN" ;;
            sudo|runuser|su) return 1 ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }

    env() {
        printf 'env\n' > "$TEST_SERVICES_MARKER"
        return 99
    }
    bash() {
        printf 'bash\n' > "$TEST_SERVICES_MARKER"
        return 99
    }
    sh() {
        printf 'sh\n' > "$TEST_SERVICES_MARKER"
        return 99
    }

    export TARGET_USER="acfsuser"
    export TARGET_HOME="$target_home"
    export ACFS_BIN_DIR="$target_home/.local/bin"
    export PATH="$target_home/.local/bin:$PATH"

    run run_as_user env TEST_SERVICES_FLAG=ok bash -c 'printf "%s" "$TEST_SERVICES_FLAG"'
    assert_success
    assert_output "ok"
    [[ ! -e "$marker" ]] || fail "function or PATH-poisoned helper executed: $(<"$marker")"
}

@test "services-setup: init_target_context repairs stale TARGET_HOME from trusted passwd data" {
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local test_current_user
    local test_trusted_home
    local test_stale_home
    local stale_bun
    local trusted_bun
    local env_home_output

    test_current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    test_trusted_home="$(create_temp_dir)"
    test_stale_home="$(create_temp_dir)"
    stale_bun="$test_stale_home/.local/bin/bun"
    trusted_bun="$test_trusted_home/.local/bin/bun"
    mkdir -p "$test_trusted_home/.local/bin" "$test_trusted_home/.acfs" "$test_stale_home/.local/bin" "$test_stale_home/.acfs"
    touch "$stale_bun" "$trusted_bun"
    chmod +x "$stale_bun" "$trusted_bun"

    eval "$(sed -n '/^services_setup_sanitize_abs_nonroot_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_valid_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_system_binary_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_passwd_home_from_entry()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_bin_dir_for_home()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^find_user_bin()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^init_target_context()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^run_as_user()/,/^}$/p' "$services_setup")"

    log_error() {
        printf '%s\n' "$*" >&2
    }

    services_setup_resolve_current_user() {
        printf '%s\n' "$test_current_user"
    }

    services_setup_getent_passwd_entry() {
        if [[ -z "${1:-}" ]]; then
            printf '%s:x:1000:1000::%s:/bin/bash\n' "$test_current_user" "$test_trusted_home"
            printf 'stale-user:x:1001:1001::%s:/bin/bash\n' "$test_stale_home"
            return 0
        fi
        if [[ "${1:-}" == "$test_current_user" ]]; then
            printf '%s:x:1000:1000::%s:/bin/bash\n' "$test_current_user" "$test_trusted_home"
            return 0
        fi
        return 1
    }

    export TARGET_USER="$test_current_user"
    export TARGET_HOME="$test_stale_home"
    export HOME="$test_stale_home"
    export ACFS_BIN_DIR="$test_stale_home/.local/bin"
    export ACFS_HOME="$test_stale_home/.acfs"
    export BUN_BIN="$stale_bun"
    _SERVICES_SETUP_ENV_HOME="$test_stale_home"

    init_target_context

    [[ "$TARGET_HOME" == "$test_trusted_home" ]] || {
        printf 'TARGET_HOME was not repaired: %s\n' "$TARGET_HOME" >&2
        return 1
    }
    [[ "$ACFS_BIN_DIR" != "$test_stale_home/.local/bin" ]] || {
        printf 'ACFS_BIN_DIR still points at stale home\n' >&2
        return 1
    }
    [[ "$ACFS_HOME" == "$test_trusted_home/.acfs" ]] || {
        printf 'ACFS_HOME was not repaired: %s\n' "$ACFS_HOME" >&2
        return 1
    }
    [[ "$BUN_BIN" == "$trusted_bun" ]] || {
        printf 'BUN_BIN was not repaired: %s\n' "$BUN_BIN" >&2
        return 1
    }

    env_home_output="$(run_as_user bash -c 'printf "%s\n" "$HOME"')"
    [[ "$env_home_output" == "$test_trusted_home" ]] || {
        printf 'run_as_user HOME was not repaired: %s\n' "$env_home_output" >&2
        return 1
    }
}

@test "services-setup: init_target_context ignores explicit other-user TARGET_HOME" {
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local target_home
    local stale_home
    local caller_home
    local stale_bun
    local target_bun
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    caller_home="$(create_temp_dir)"
    stale_bun="$stale_home/.local/bin/bun"
    target_bun="$target_home/.local/bin/bun"

    mkdir -p "$target_home/.local/bin" "$target_home/.acfs" "$stale_home/.local/bin" "$stale_home/.acfs"
    touch "$stale_bun" "$target_bun"
    chmod +x "$stale_bun" "$target_bun"

    eval "$(sed -n '/^services_setup_sanitize_abs_nonroot_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_valid_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_passwd_home_from_entry()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_bin_dir_for_home()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^find_user_bin()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^init_target_context()/,/^}$/p' "$services_setup")"

    log_error() {
        printf '%s\n' "$*" >&2
    }

    services_setup_getent_passwd_entry() {
        if [[ -z "${1:-}" ]]; then
            printf 'acfstestuser:x:1000:1000::%s:/bin/bash\n' "$target_home"
            printf 'stale-user:x:1001:1001::%s:/bin/bash\n' "$stale_home"
            return 0
        fi
        if [[ "${1:-}" == "acfstestuser" ]]; then
            printf 'acfstestuser:x:1000:1000::%s:/bin/bash\n' "$target_home"
            return 0
        fi
        return 1
    }

    export TARGET_USER="acfstestuser"
    export TARGET_HOME="$stale_home"
    export HOME="$caller_home"
    export ACFS_BIN_DIR="$stale_home/.local/bin"
    export ACFS_HOME="$stale_home/.acfs"
    export BUN_BIN="$stale_bun"
    _SERVICES_SETUP_ENV_HOME="$caller_home"

    init_target_context

    [[ "$TARGET_HOME" == "$target_home" ]] || {
        printf 'TARGET_HOME was not repaired: %s\n' "$TARGET_HOME" >&2
        return 1
    }
    [[ "$ACFS_BIN_DIR" != "$stale_home/.local/bin" ]] || {
        printf 'ACFS_BIN_DIR still points at stale home\n' >&2
        return 1
    }
    [[ "$ACFS_HOME" == "$target_home/.acfs" ]] || {
        printf 'ACFS_HOME was not repaired: %s\n' "$ACFS_HOME" >&2
        return 1
    }
    [[ "$BUN_BIN" == "$target_bun" ]] || {
        printf 'BUN_BIN was not repaired: %s\n' "$BUN_BIN" >&2
        return 1
    }
}

@test "services-setup: init_target_context fails closed for unresolved target with explicit TARGET_HOME" {
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local stale_home

    stale_home="$(create_temp_dir)"
    mkdir -p "$stale_home/.local/bin" "$stale_home/.acfs"

    eval "$(sed -n '/^services_setup_sanitize_abs_nonroot_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_valid_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_passwd_home_from_entry()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_bin_dir_for_home()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^find_user_bin()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^init_target_context()/,/^}$/p' "$services_setup")"

    log_error() {
        printf '%s\n' "$*" >&2
    }

    services_setup_resolve_current_user() {
        printf 'calleruser\n'
    }

    services_setup_getent_passwd_entry() {
        return 1
    }

    export TARGET_USER="missinguser"
    export TARGET_HOME="$stale_home"
    export HOME="$stale_home"
    export ACFS_BIN_DIR="$stale_home/.local/bin"
    export ACFS_HOME="$stale_home/.acfs"

    run init_target_context
    assert_failure
    assert_output --partial "Unable to determine home directory for user: missinguser"
}

@test "services-setup: init_target_context honors explicit TARGET_HOME for current target without passwd" {
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local caller_home
    local stale_home

    caller_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    mkdir -p "$caller_home/.local/bin" "$stale_home/.local/bin" "$stale_home/.acfs"

    eval "$(sed -n '/^services_setup_sanitize_abs_nonroot_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_valid_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_target_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_passwd_home_from_entry()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_validate_bin_dir_for_home()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^find_user_bin()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^init_target_context()/,/^}$/p' "$services_setup")"

    log_error() {
        printf '%s\n' "$*" >&2
    }

    services_setup_resolve_current_user() {
        printf 'calleruser\n'
    }

    services_setup_getent_passwd_entry() {
        return 1
    }

    export TARGET_USER="calleruser"
    export TARGET_HOME="$stale_home"
    export HOME="$caller_home"
    export ACFS_BIN_DIR="$stale_home/.local/bin"
    export ACFS_HOME="$stale_home/.acfs"

    init_target_context
    [[ "$TARGET_HOME" == "$stale_home" ]] || {
        printf 'TARGET_HOME did not preserve explicit same-user home: %s\n' "$TARGET_HOME" >&2
        return 1
    }
}

@test "diagnostic helpers: prepend primary ACFS bin dir and ~/.acfs/bin" {
    local doctor="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local info="$PROJECT_ROOT/scripts/lib/info.sh"
    local status_lib="$PROJECT_ROOT/scripts/lib/status.sh"
    local export_config="$PROJECT_ROOT/scripts/lib/export-config.sh"
    local smoke="$PROJECT_ROOT/scripts/lib/smoke_test.sh"
    local update="$PROJECT_ROOT/scripts/lib/update.sh"

    run grep -F 'local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"' "$doctor"
    assert_success
    run grep -F 'local current_path="${PATH:-$system_path_prefix}"' "$doctor"
    assert_success
    run grep -F 'local seen_path=":$current_path:"' "$doctor"
    assert_success
    run grep -F 'seen_path="${seen_path}${dir}:"' "$doctor"
    assert_success
    run grep -F 'local primary_bin_dir="${ACFS_BIN_DIR:-$primary_home/.local/bin}"' "$doctor"
    assert_success
    run grep -F 'target_path="$target_path_prefix${PATH:+:$PATH}"' "$doctor"
    assert_success
    run grep -F 'local -a target_path_entries=()' "$doctor"
    assert_success
    run grep -F '"$_acfs_doctor_current_home/google-cloud-sdk/bin"' "$doctor"
    assert_success
    run grep -F "Invalid TARGET_USER '\${target_user:-<empty>}' (expected: lowercase user name like 'ubuntu')" "$doctor"
    assert_success
    run grep -F 'target_home="/home/$target_user"' "$doctor"
    assert_failure
    run grep -F '"$sudo_bin" -n "$env_bin" TARGET_USER="$target_user" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"' "$doctor"
    assert_success
    run grep -F 'export PATH="$prefix${current_path:+:$current_path}"' "$doctor"
    assert_success

    run grep -F 'update_sanitize_abs_nonroot_path() {' "$update"
    assert_success
    run grep -F 'local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"' "$update"
    assert_success
    run grep -F 'local current_path="${PATH:-$system_path_prefix}"' "$update"
    assert_success
    run grep -F 'local seen_path=":$current_path:"' "$update"
    assert_success
    run grep -F 'sanitized_primary_bin="$(update_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "${HOME:-}" 2>/dev/null || true)"' "$update"
    assert_success
    run grep -F '$HOME/google-cloud-sdk/bin' "$update"
    assert_success
    run grep -F '$target_home/google-cloud-sdk/bin/$tool' "$update"
    assert_success
    run grep -F 'path_prefix=$(IFS=:; echo "${path_entries[*]}")' "$update"
    assert_success
    run grep -F 'local current_state_file=""' "$update"
    assert_success
    run grep -F 'local acfs_home_state_file=""' "$update"
    assert_success
    run grep -F 'local target_state_file=""' "$update"
    assert_success
    run grep -F 'local explicit_bin_dir=""' "$update"
    assert_success
    run grep -F 'local explicit_state_file=""' "$update"
    assert_success
    run grep -F 'local sanitized_acfs_home=""' "$update"
    assert_success
    run grep -F '$current_state_file' "$update"
    assert_success
    run grep -F 'explicit_bin_dir="$(update_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$target_home" 2>/dev/null || true)"' "$update"
    assert_success
    run grep -F 'explicit_state_file="$(update_sanitize_abs_nonroot_path "${ACFS_STATE_FILE:-}" 2>/dev/null || true)"' "$update"
    assert_success
    run grep -F 'sanitized_acfs_home="$(update_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"' "$update"
    assert_success
    run grep -F 'user_bin="$(update_default_user_bin_dir 2>/dev/null || true)"' "$update"
    assert_success
    run grep -F 'local -a candidates=()' "$update"
    assert_success
    run grep -F 'configured_bin="$(update_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$target_home" 2>/dev/null || true)"' "$update"
    assert_success
    run grep -F '[[ -n "$target_home" ]] && preferred_src="$target_home/.atuin/bin/atuin"' "$update"
    assert_success
    run grep -F "printf '/home/%s\n'" "$update"
    assert_failure
    run grep -F '$HOME/.atuin/bin/atuin' "$update"
    assert_failure
    run grep -F "printf '%s\n' \"\$HOME/.local/bin\"" "$update"
    assert_failure
    run grep -F '"${ACFS_HOME:-}/state.json"' "$update"
    assert_failure
    run grep -F 'target_state_file="$target_home/.acfs/state.json"' "$update"
    assert_success
    run grep -F 'export PATH="$prefix${current_path:+:$current_path}"' "$update"
    assert_success
    run grep -F 'export PATH="${prefix}:$PATH"' "$update"
    assert_failure

    run grep -F 'primary_bin_dir="$(info_preferred_bin_dir "$base_home" 2>/dev/null || true)"' "$info"
    assert_success
    run grep -F '[[ -n "$primary_bin_dir" ]] || primary_bin_dir="$base_home/.local/bin"' "$info"
    assert_success
    run grep -F '"$base_home/.acfs/bin"' "$info"
    assert_success

    run grep -F 'primary_bin_dir="$(_status_preferred_bin_dir "$base_home" 2>/dev/null || true)"' "$status_lib"
    assert_success
    run grep -F '[[ -n "$primary_bin_dir" ]] || primary_bin_dir="$base_home/.local/bin"' "$status_lib"
    assert_success
    run grep -F '"$base_home/.acfs/bin"' "$status_lib"
    assert_success

    run grep -F 'local primary_bin_dir="${ACFS_BIN_DIR:-$target_home/.local/bin}"' "$export_config"
    assert_success
    run grep -F '"$target_home/.acfs/bin"' "$export_config"
    assert_success

    run grep -F '_smoke_prepend_user_paths "$_SMOKE_TARGET_HOME"' "$smoke"
    assert_success
    run grep -F 'primary_bin_dir="$(_smoke_preferred_bin_dir "$base_home" 2>/dev/null || true)"' "$smoke"
    assert_success
    run grep -F '[[ -n "$primary_bin_dir" ]] || primary_bin_dir="$base_home/.local/bin"' "$smoke"
    assert_success

    run grep -F '"$HOME/.acfs/bin"' "$update"
    assert_success
}

@test "wrappers and nightly update sanitize invalid path env" {
    local nightly="$PROJECT_ROOT/scripts/lib/nightly_update.sh"
    local global_wrapper="$PROJECT_ROOT/scripts/acfs-global"
    local update_wrapper="$PROJECT_ROOT/scripts/acfs-update"

    run grep -F 'sanitize_abs_nonroot_path()' "$nightly"
    assert_success
    run grep -F 'HOME="$(resolve_current_home)" || {' "$nightly"
    assert_success
    run grep -F 'ACFS_STATE_FILE="$(sanitize_abs_nonroot_path "${ACFS_STATE_FILE:-}" 2>/dev/null || true)"' "$nightly"
    assert_success
    run grep -F 'ACFS_SYSTEM_STATE_FILE="$(sanitize_abs_nonroot_path "${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}" 2>/dev/null || true)"' "$nightly"
    assert_success
    run grep -F 'ACFS_BIN_DIR="$(sanitize_abs_nonroot_path "${ACFS_BIN_DIR:-}" 2>/dev/null || true)"' "$nightly"
    assert_success

    run grep -F 'sanitize_abs_nonroot_path()' "$global_wrapper"
    assert_success
    run grep -F 'resolve_current_home()' "$global_wrapper"
    assert_success
    run grep -F 'ACFS_STATE_FILE="$(sanitize_abs_nonroot_path "${ACFS_STATE_FILE:-}" 2>/dev/null || true)"' "$global_wrapper"
    assert_success
    run grep -F 'ACFS_SYSTEM_STATE_FILE="$(sanitize_abs_nonroot_path "${ACFS_SYSTEM_STATE_FILE:-}" 2>/dev/null || true)"' "$global_wrapper"
    assert_success
    run grep -F 'ACFS_BIN_DIR="$(sanitize_abs_nonroot_path "${ACFS_BIN_DIR:-}" 2>/dev/null || true)"' "$global_wrapper"
    assert_success
    run grep -F 'state_bin_dir="$(read_validated_bin_dir_from_state_file "$ACFS_STATE_FILE" "$runtime_target_home" 2>/dev/null || true)"' "$global_wrapper"
    assert_success
    run grep -F 'ACFS_BIN_DIR="${state_bin_dir:-}"' "$global_wrapper"
    assert_success
    run grep -F 'current_home="$(resolve_current_home 2>/dev/null || true)"' "$global_wrapper"
    assert_success
    run grep -F '[[ -n "$sanitized_state_file" ]] && env_args+=("ACFS_STATE_FILE=$sanitized_state_file")' "$global_wrapper"
    assert_success
    run grep -F '[[ -n "$sanitized_system_state_file" ]] && env_args+=("ACFS_SYSTEM_STATE_FILE=$sanitized_system_state_file")' "$global_wrapper"
    assert_success
    run grep -F '[[ -n "$sanitized_target_home" ]] && env_args+=("HOME=$sanitized_target_home" "TARGET_HOME=$sanitized_target_home")' "$global_wrapper"
    assert_success

    run grep -F 'sanitize_abs_nonroot_path()' "$update_wrapper"
    assert_success
    run grep -F 'resolve_current_home()' "$update_wrapper"
    assert_success
    run grep -F 'ACFS_STATE_FILE="$(sanitize_abs_nonroot_path "${ACFS_STATE_FILE:-}" 2>/dev/null || true)"' "$update_wrapper"
    assert_success
    run grep -F 'ACFS_SYSTEM_STATE_FILE="$(sanitize_abs_nonroot_path "${ACFS_SYSTEM_STATE_FILE:-}" 2>/dev/null || true)"' "$update_wrapper"
    assert_success
    run grep -F 'ACFS_BIN_DIR="$(sanitize_abs_nonroot_path "${ACFS_BIN_DIR:-}" 2>/dev/null || true)"' "$update_wrapper"
    assert_success
    run grep -F 'state_bin_dir="$(read_validated_bin_dir_from_state_file "$ACFS_STATE_FILE" "$runtime_target_home" 2>/dev/null || true)"' "$update_wrapper"
    assert_success
    run grep -F 'ACFS_BIN_DIR="${state_bin_dir:-}"' "$update_wrapper"
    assert_success
    run grep -F 'current_home="$(resolve_current_home 2>/dev/null || true)"' "$update_wrapper"
    assert_success
    run grep -F '[[ -n "$sanitized_state_file" ]] && env_args+=("ACFS_STATE_FILE=$sanitized_state_file")' "$update_wrapper"
    assert_success
    run grep -F '[[ -n "$sanitized_system_state_file" ]] && env_args+=("ACFS_SYSTEM_STATE_FILE=$sanitized_system_state_file")' "$update_wrapper"
    assert_success
    run grep -F '[[ -n "$sanitized_target_home" ]] && env_args+=("HOME=$sanitized_target_home" "TARGET_HOME=$sanitized_target_home")' "$update_wrapper"
    assert_success
}

setup_nightly_update_identity_stubs() {
    init_stub_dir

    cat > "$STUB_DIR/id" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    cat > "$STUB_DIR/getent" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
    cat > "$STUB_DIR/nproc" <<'EOF'
#!/usr/bin/env bash
printf '128\n'
EOF
    cat > "$STUB_DIR/awk" <<'EOF'
#!/usr/bin/env bash
case "${*: -1}" in
    /proc/loadavg) printf '0.01\n' ;;
    *) exec /usr/bin/awk "$@" ;;
esac
EOF
    chmod +x "$STUB_DIR/id" "$STUB_DIR/getent" "$STUB_DIR/nproc" "$STUB_DIR/awk"
    printf '%s\n' "$STUB_DIR:/usr/bin:/bin"
}

@test "nightly update honors explicit system state and repairs target runtime home" {
    local nightly="$PROJECT_ROOT/scripts/lib/nightly_update.sh"
    local nightly_path
    local root_home
    local target_home
    local system_state

    root_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    system_state="$root_home/system-state.json"

    mkdir -p \
        "$root_home/.acfs/scripts/lib" \
        "$target_home/.acfs/scripts/lib" \
        "$target_home/.acfs/logs/updates" \
        "$target_home/.local/bin"

    cat > "$root_home/.acfs/scripts/lib/notify.sh" <<'EOF'
acfs_notify_update_success() { :; }
acfs_notify_update_failure() { :; }
EOF
    cat > "$target_home/.acfs/scripts/lib/notify.sh" <<'EOF'
acfs_notify_update_success() { :; }
acfs_notify_update_failure() { :; }
EOF
    cat > "$system_state" <<EOF
{
  "target_home": "$target_home",
  "bin_dir": "$target_home/.local/bin"
}
EOF
    cat > "$target_home/.local/bin/acfs-update" <<'EOF'
#!/usr/bin/env bash
printf 'CHILD_HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    chmod +x "$target_home/.local/bin/acfs-update"

    nightly_path="$(setup_nightly_update_identity_stubs)"
    run env -i PATH="$nightly_path" HOME="$root_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash "$nightly"

    assert_success
    assert_output --partial "Running: $target_home/.local/bin/acfs-update --yes --quiet --no-self-update"
    assert_output --partial "CHILD_HOME=$target_home TARGET_HOME=$target_home ACFS_HOME=$target_home/.acfs"
    [[ -f "$target_home/.acfs/logs/updates/nightly-2025-01-01.log" ]]
}

@test "nightly update prefers live target-home updater over stale persisted bin dir" {
    local nightly="$PROJECT_ROOT/scripts/lib/nightly_update.sh"
    local nightly_path
    local root_home
    local target_home
    local stale_home
    local system_state

    root_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    system_state="$root_home/system-state.json"

    mkdir -p         "$root_home/.acfs/scripts/lib"         "$target_home/.acfs/bin"         "$target_home/.acfs/scripts/lib"         "$target_home/.acfs/logs/updates"         "$stale_home/.local/bin"

    cat > "$root_home/.acfs/scripts/lib/notify.sh" <<'EOF'
acfs_notify_update_success() { :; }
acfs_notify_update_failure() { :; }
EOF
    cat > "$target_home/.acfs/scripts/lib/notify.sh" <<'EOF'
acfs_notify_update_success() { :; }
acfs_notify_update_failure() { :; }
EOF
    cat > "$system_state" <<EOF
{
  "target_home": "$target_home",
  "bin_dir": "$stale_home/.local/bin"
}
EOF
    cat > "$target_home/.acfs/bin/acfs-update" <<'EOF'
#!/usr/bin/env bash
printf 'LIVE_HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    cat > "$stale_home/.local/bin/acfs-update" <<'EOF'
#!/usr/bin/env bash
printf 'STALE_HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    chmod +x "$target_home/.acfs/bin/acfs-update" "$stale_home/.local/bin/acfs-update"

    nightly_path="$(setup_nightly_update_identity_stubs)"
    run env -i PATH="$nightly_path" HOME="$root_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash "$nightly"

    assert_success
    assert_output --partial "Running: $target_home/.acfs/bin/acfs-update --yes --quiet --no-self-update"
    refute_output --partial "STALE_HOME="
    assert_output --partial "LIVE_HOME=$target_home TARGET_HOME=$target_home ACFS_HOME=$target_home/.acfs"
    [[ -f "$target_home/.acfs/logs/updates/nightly-2025-01-01.log" ]]
}

@test "nightly update falls back to target home binaries when system state omits bin dir" {
    local nightly="$PROJECT_ROOT/scripts/lib/nightly_update.sh"
    local nightly_path
    local root_home
    local target_home
    local system_state

    root_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    system_state="$root_home/system-state.json"

    mkdir -p \
        "$root_home/.acfs/scripts/lib" \
        "$target_home/.acfs/bin" \
        "$target_home/.acfs/scripts/lib" \
        "$target_home/.acfs/logs/updates"

    cat > "$root_home/.acfs/scripts/lib/notify.sh" <<'EOF'
acfs_notify_update_success() { :; }
acfs_notify_update_failure() { :; }
EOF
    cat > "$target_home/.acfs/scripts/lib/notify.sh" <<'EOF'
acfs_notify_update_success() { :; }
acfs_notify_update_failure() { :; }
EOF
    cat > "$system_state" <<EOF
{
  "target_home": "$target_home"
}
EOF
    cat > "$target_home/.acfs/bin/acfs-update" <<'EOF'
#!/usr/bin/env bash
printf 'CHILD_HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    chmod +x "$target_home/.acfs/bin/acfs-update"

    nightly_path="$(setup_nightly_update_identity_stubs)"
    run env -i PATH="$nightly_path" HOME="$root_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash "$nightly"

    assert_success
    assert_output --partial "Running: $target_home/.acfs/bin/acfs-update --yes --quiet --no-self-update"
    assert_output --partial "CHILD_HOME=$target_home TARGET_HOME=$target_home ACFS_HOME=$target_home/.acfs"
    [[ -f "$target_home/.acfs/logs/updates/nightly-2025-01-01.log" ]]
}

@test "nightly update honors explicit TARGET_HOME over stale system state" {
    local nightly="$PROJECT_ROOT/scripts/lib/nightly_update.sh"
    local nightly_path
    local root_home
    local target_home
    local stale_home
    local system_state

    root_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    system_state="$root_home/system-state.json"

    mkdir -p         "$root_home/.acfs/scripts/lib"         "$target_home/.acfs/scripts/lib"         "$target_home/.acfs/logs/updates"         "$target_home/.local/bin"         "$stale_home/.acfs/scripts/lib"         "$stale_home/.acfs/logs/updates"         "$stale_home/.local/bin"

    cat > "$root_home/.acfs/scripts/lib/notify.sh" <<'EOF'
acfs_notify_update_success() { :; }
acfs_notify_update_failure() { :; }
EOF
    cat > "$target_home/.acfs/scripts/lib/notify.sh" <<'EOF'
acfs_notify_update_success() { :; }
acfs_notify_update_failure() { :; }
EOF
    cat > "$stale_home/.acfs/scripts/lib/notify.sh" <<'EOF'
acfs_notify_update_success() { :; }
acfs_notify_update_failure() { :; }
EOF
    cat > "$system_state" <<EOF
{
  "target_home": "$stale_home",
  "bin_dir": "$stale_home/.local/bin"
}
EOF
    cat > "$target_home/.local/bin/acfs-update" <<'EOF'
#!/usr/bin/env bash
printf 'LIVE_NIGHTLY HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    cat > "$stale_home/.local/bin/acfs-update" <<'EOF'
#!/usr/bin/env bash
printf 'STALE_NIGHTLY HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    chmod +x "$target_home/.local/bin/acfs-update" "$stale_home/.local/bin/acfs-update"

    nightly_path="$(setup_nightly_update_identity_stubs)"
    run env -i PATH="$nightly_path" HOME="$root_home" TARGET_HOME="$target_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash "$nightly"

    assert_success
    assert_output --partial "Running: $target_home/.local/bin/acfs-update --yes --quiet --no-self-update"
    refute_output --partial "STALE_NIGHTLY"
    assert_output --partial "LIVE_NIGHTLY HOME=$target_home TARGET_HOME=$target_home ACFS_HOME=$target_home/.acfs"
    [[ -f "$target_home/.acfs/logs/updates/nightly-2025-01-01.log" ]]
}

@test "acfs-update wrapper honors explicit TARGET_HOME over stale system state" {
    local update_wrapper="$PROJECT_ROOT/scripts/acfs-update"
    local wrapper_dir
    local root_home
    local target_home
    local stale_home
    local system_state
    local current_user

    wrapper_dir="$(create_temp_dir)"
    root_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    system_state="$BATS_TEST_TMPDIR/update-wrapper-system-state.json"
    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p "$target_home/.acfs/scripts/lib" "$stale_home/.acfs/scripts/lib"
    cp "$update_wrapper" "$wrapper_dir/acfs-update"
    chmod +x "$wrapper_dir/acfs-update"

    cat > "$target_home/.acfs/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'LIVE_SCRIPT HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    cat > "$stale_home/.acfs/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'STALE_SCRIPT HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    chmod +x "$target_home/.acfs/scripts/lib/update.sh" "$stale_home/.acfs/scripts/lib/update.sh"

    cat > "$system_state" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$stale_home"
}
EOF

    run env HOME="$root_home" TARGET_HOME="$target_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash "$wrapper_dir/acfs-update"

    assert_success
    refute_output --partial "STALE_SCRIPT"
    assert_output --partial "LIVE_SCRIPT HOME=$target_home TARGET_HOME=$target_home ACFS_HOME=$target_home/.acfs"
}

@test "acfs-update dispatch validation rejects current user with mismatched target home" {
    local update_wrapper="$PROJECT_ROOT/scripts/acfs-update"
    local current_user
    local target_home
    local stale_home
    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"

    eval "$(sed -n '/^sanitize_abs_nonroot_path()/,/^}$/p' "$update_wrapper")"
    eval "$(sed -n '/^is_valid_username()/,/^}$/p' "$update_wrapper")"
    eval "$(sed -n '/^validated_target_user_for_dispatch()/,/^}$/p' "$update_wrapper")"

    resolve_current_user() {
        printf '%s\n' "$TEST_CURRENT_USER"
    }

    resolve_home_for_user() {
        if [[ "${1:-}" == "$TEST_CURRENT_USER" ]]; then
            printf '%s\n' "$TEST_TARGET_HOME"
            return 0
        fi
        return 1
    }

    export TEST_CURRENT_USER="$current_user"
    export TEST_TARGET_HOME="$target_home"
    export TEST_STALE_HOME="$stale_home"
    export HOME="$TEST_STALE_HOME"

    run validated_target_user_for_dispatch "$TEST_CURRENT_USER" "$TEST_STALE_HOME"
    assert_failure

    run validated_target_user_for_dispatch "$TEST_CURRENT_USER" "$TEST_TARGET_HOME"
    assert_success
    assert_output "$TEST_CURRENT_USER"
}

@test "acfs-global dispatch validation rejects current user with mismatched target home" {
    local global_wrapper="$PROJECT_ROOT/scripts/acfs-global"
    local current_user
    local target_home
    local stale_home
    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"

    eval "$(sed -n '/^sanitize_abs_nonroot_path()/,/^}$/p' "$global_wrapper")"
    eval "$(sed -n '/^is_valid_username()/,/^}$/p' "$global_wrapper")"
    eval "$(sed -n '/^validated_target_user_for_dispatch()/,/^}$/p' "$global_wrapper")"

    resolve_current_user() {
        printf '%s\n' "$TEST_CURRENT_USER"
    }

    resolve_home_for_user() {
        if [[ "${1:-}" == "$TEST_CURRENT_USER" ]]; then
            printf '%s\n' "$TEST_TARGET_HOME"
            return 0
        fi
        return 1
    }

    export TEST_CURRENT_USER="$current_user"
    export TEST_TARGET_HOME="$target_home"
    export TEST_STALE_HOME="$stale_home"
    export HOME="$TEST_STALE_HOME"

    run validated_target_user_for_dispatch "$TEST_CURRENT_USER" "$TEST_STALE_HOME"
    assert_failure

    run validated_target_user_for_dispatch "$TEST_CURRENT_USER" "$TEST_TARGET_HOME"
    assert_success
    assert_output "$TEST_CURRENT_USER"
}

@test "acfs-update wrapper resolves non-current owner home after owner discovery" {
    local update_wrapper="$PROJECT_ROOT/scripts/acfs-update"
    local target_home
    target_home="$(create_temp_dir)"
    export TEST_UPDATE_WRAPPER_TARGET_HOME="$target_home"

    mkdir -p "$target_home/.acfs/scripts/lib"
    touch "$target_home/.acfs/scripts/lib/update.sh"

    eval "$(sed -n '/^sanitize_abs_nonroot_path()/,/^}$/p' "$update_wrapper")"
    eval "$(sed -n '/^is_valid_username()/,/^}$/p' "$update_wrapper")"
    eval "$(sed -n '/^find_update_script_for_home()/,/^}$/p' "$update_wrapper")"
    eval "$(sed -n '/^find_update_script_for_user()/,/^}$/p' "$update_wrapper")"

    validated_target_user_for_dispatch() {
        return 1
    }

    resolve_current_user() {
        printf 'caller\n'
    }

    current_home_matches_update_install() {
        return 1
    }

    resolve_home_for_user() {
        if [[ "${1:-}" == "acfsuser" ]]; then
            printf '%s\n' "$TEST_UPDATE_WRAPPER_TARGET_HOME"
            return 0
        fi
        return 1
    }

    unset TARGET_HOME

    run find_update_script_for_user "acfsuser"
    assert_success
    assert_output "$target_home/.acfs/scripts/lib/update.sh"
}

@test "acfs global wrapper resolves non-current owner home after owner discovery" {
    local global_wrapper="$PROJECT_ROOT/scripts/acfs-global"
    local target_home
    target_home="$(create_temp_dir)"
    export TEST_GLOBAL_WRAPPER_TARGET_HOME="$target_home"

    mkdir -p "$target_home/.local/bin"
    touch "$target_home/.local/bin/acfs"
    chmod +x "$target_home/.local/bin/acfs"

    eval "$(sed -n '/^sanitize_abs_nonroot_path()/,/^}$/p' "$global_wrapper")"
    eval "$(sed -n '/^is_valid_username()/,/^}$/p' "$global_wrapper")"
    eval "$(sed -n '/^find_acfs_bin_for_home()/,/^}$/p' "$global_wrapper")"
    eval "$(sed -n '/^find_acfs_bin()/,/^}$/p' "$global_wrapper")"

    validated_target_user_for_dispatch() {
        return 1
    }

    resolve_current_user() {
        printf 'caller\n'
    }

    current_home_matches_acfs_install() {
        return 1
    }

    resolve_home_for_user() {
        if [[ "${1:-}" == "acfsuser" ]]; then
            printf '%s\n' "$TEST_GLOBAL_WRAPPER_TARGET_HOME"
            return 0
        fi
        return 1
    }

    unset TARGET_HOME

    run find_acfs_bin "acfsuser"
    assert_success
    assert_output "$target_home/.local/bin/acfs"
}

@test "acfs-update wrapper only promotes system state homes with an update script" {
    local update_wrapper="$PROJECT_ROOT/scripts/acfs-update"
    local stale_home

    stale_home="$(create_temp_dir)"
    mkdir -p "$stale_home/.acfs"

    ACFS_SYSTEM_STATE_FILE="$stale_home/.acfs/state.json"
    resolve_target_home_from_state_hint() { printf '%s\n' "$stale_home"; }
    find_update_script_for_home() { return 1; }
    eval "$(sed -n '/^resolve_live_system_state_home()/,/^}/p' "$update_wrapper")"

    run resolve_live_system_state_home
    assert_failure
}

@test "acfs-update wrapper prefers valid HOME install over stale live system state" {
    local update_wrapper="$PROJECT_ROOT/scripts/acfs-update"
    local wrapper_dir
    local target_home
    local stale_home
    local system_state
    local current_user

    wrapper_dir="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    system_state="$BATS_TEST_TMPDIR/update-wrapper-live-stale-system-state.json"
    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p "$target_home/.acfs/scripts/lib" "$stale_home/.acfs/scripts/lib"
    cp "$update_wrapper" "$wrapper_dir/acfs-update"
    chmod +x "$wrapper_dir/acfs-update"

    cat > "$target_home/.acfs/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$target_home"
}
EOF
    cat > "$system_state" <<EOF
{
  "target_home": "$stale_home"
}
EOF
    cat > "$target_home/.acfs/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'LIVE_HOME_INSTALL HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    cat > "$stale_home/.acfs/scripts/lib/update.sh" <<'EOF'
#!/usr/bin/env bash
printf 'STALE_SYSTEM_STATE HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    chmod +x "$target_home/.acfs/scripts/lib/update.sh" "$stale_home/.acfs/scripts/lib/update.sh"

    run env HOME="$target_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash "$wrapper_dir/acfs-update" --no-self-update

    assert_success
    refute_output --partial "STALE_SYSTEM_STATE"
    assert_output --partial "LIVE_HOME_INSTALL HOME=$target_home TARGET_HOME=$target_home ACFS_HOME=$target_home/.acfs"
}

@test "acfs global wrapper honors explicit TARGET_HOME over stale system state" {
    local global_wrapper="$PROJECT_ROOT/scripts/acfs-global"
    local wrapper_dir
    local root_home
    local target_home
    local stale_home
    local system_state
    local current_user

    wrapper_dir="$(create_temp_dir)"
    root_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    system_state="$BATS_TEST_TMPDIR/global-wrapper-system-state.json"
    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p "$target_home/.local/bin" "$target_home/.acfs" "$stale_home/.local/bin" "$stale_home/.acfs"
    cp "$global_wrapper" "$wrapper_dir/acfs"
    chmod +x "$wrapper_dir/acfs"

    cat > "$target_home/.local/bin/acfs" <<'EOF'
#!/usr/bin/env bash
printf 'LIVE_ACFS HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    cat > "$stale_home/.local/bin/acfs" <<'EOF'
#!/usr/bin/env bash
printf 'STALE_ACFS HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    chmod +x "$target_home/.local/bin/acfs" "$stale_home/.local/bin/acfs"

    cat > "$system_state" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$stale_home"
}
EOF

    run env HOME="$root_home" TARGET_HOME="$target_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash "$wrapper_dir/acfs"

    assert_success
    refute_output --partial "STALE_ACFS"
    assert_output --partial "LIVE_ACFS HOME=$target_home TARGET_HOME=$target_home ACFS_HOME=$target_home/.acfs"
}

@test "acfs global wrapper prefers valid HOME install over stale live system state" {
    local global_wrapper="$PROJECT_ROOT/scripts/acfs-global"
    local wrapper_dir
    local target_home
    local stale_home
    local system_state
    local current_user

    wrapper_dir="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    system_state="$BATS_TEST_TMPDIR/global-wrapper-live-stale-system-state.json"
    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"

    mkdir -p "$target_home/.local/bin" "$target_home/.acfs" "$stale_home/.local/bin" "$stale_home/.acfs"
    cp "$global_wrapper" "$wrapper_dir/acfs"
    chmod +x "$wrapper_dir/acfs"

    cat > "$target_home/.acfs/state.json" <<EOF
{
  "target_user": "$current_user",
  "target_home": "$target_home"
}
EOF
    cat > "$system_state" <<EOF
{
  "target_home": "$stale_home"
}
EOF
    cat > "$target_home/.local/bin/acfs" <<'EOF'
#!/usr/bin/env bash
printf 'LIVE_HOME_ACFS HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    cat > "$stale_home/.local/bin/acfs" <<'EOF'
#!/usr/bin/env bash
printf 'STALE_SYSTEM_ACFS HOME=%s TARGET_HOME=%s ACFS_HOME=%s\n' "$HOME" "${TARGET_HOME:-}" "${ACFS_HOME:-}"
EOF
    chmod +x "$target_home/.local/bin/acfs" "$stale_home/.local/bin/acfs"

    run env HOME="$target_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash "$wrapper_dir/acfs"

    assert_success
    refute_output --partial "STALE_SYSTEM_ACFS"
    assert_output --partial "LIVE_HOME_ACFS HOME=$target_home TARGET_HOME=$target_home ACFS_HOME=$target_home/.acfs"
}

@test "global wrappers repair stale ACFS env before cross-user re-exec" {
    local update_wrapper="$PROJECT_ROOT/scripts/acfs-update"
    local global_wrapper="$PROJECT_ROOT/scripts/acfs-global"
    local wrapper=""
    local function_body=""
    local target_home
    local stale_home
    local fake_sudo
    local label

    for wrapper in "$update_wrapper" "$global_wrapper"; do
        label="${wrapper##*/}"
        target_home="$(create_temp_dir)"
        stale_home="$(create_temp_dir)"
        fake_sudo="$BATS_TEST_TMPDIR/$label-sudo"

        mkdir -p "$target_home/.acfs" "$stale_home/.acfs"
        cat > "$target_home/.acfs/state.json" <<EOF
{
  "target_user": "acfstestuser",
  "target_home": "$target_home"
}
EOF
        cat > "$stale_home/.acfs/state.json" <<EOF
{
  "target_user": "staleuser",
  "target_home": "$stale_home"
}
EOF
        cat > "$fake_sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
        chmod +x "$fake_sudo"

        if [[ "$wrapper" == "$update_wrapper" ]]; then
            function_body="$(sed -n '/^exec_as_target_user()/,/^}/p' "$wrapper")"
        else
            function_body="$(sed -n '/^    exec_as_target_user()/,/^    }/p' "$wrapper")"
        fi

        run env -i \
            PATH="/usr/bin:/bin" \
            TARGET_HOME="$target_home" \
            ACFS_HOME="$stale_home/.acfs" \
            ACFS_STATE_FILE="$stale_home/.acfs/state.json" \
            ACFS_SYSTEM_STATE_FILE="$stale_home/.acfs/state.json" \
            TEST_FAKE_SUDO="$fake_sudo" \
            TEST_FUNCTION_BODY="$function_body" \
            bash -c '
                set -euo pipefail
                eval "$TEST_FUNCTION_BODY"
                sanitize_abs_nonroot_path() {
                    local path_value="${1:-}"
                    [[ -n "$path_value" ]] || return 1
                    path_value="${path_value%/}"
                    [[ -n "$path_value" ]] || return 1
                    [[ "$path_value" == /* ]] || return 1
                    [[ "$path_value" != "/" ]] || return 1
                    printf "%s\n" "$path_value"
                }
                is_valid_username() {
                    [[ "${1:-}" =~ ^[a-z_][a-z0-9._-]*$ ]]
                }
                validate_target_user_or_die() {
                    is_valid_username "${1:-}" || exit 77
                }
                state_file_matches_target_home() {
                    [[ "${1:-}" == "$TARGET_HOME/.acfs/state.json" ]] && [[ "${2:-}" == "$TARGET_HOME" ]]
                }
                system_binary_path() {
                    case "${1:-}" in
                        env) printf "/usr/bin/env\n" ;;
                        sudo) printf "%s\n" "$TEST_FAKE_SUDO" ;;
                        runuser) return 1 ;;
                        *) return 1 ;;
                    esac
                }
                exec_as_target_user acfstestuser bash /tmp/acfs-child
            '
        assert_success
        assert_output --partial "HOME=$target_home"
        assert_output --partial "TARGET_HOME=$target_home"
        assert_output --partial "ACFS_HOME=$target_home/.acfs"
        assert_output --partial "ACFS_STATE_FILE=$target_home/.acfs/state.json"
        refute_output --partial "ACFS_HOME=$stale_home/.acfs"
        refute_output --partial "ACFS_STATE_FILE=$stale_home/.acfs/state.json"
        refute_output --partial "ACFS_SYSTEM_STATE_FILE=$stale_home/.acfs/state.json"
    done
}

@test "ACFS home resolvers honor explicit TARGET_HOME over stale system state" {
    local current_home
    local target_home
    local stale_home
    local system_state
    local label
    local script
    local func
    local expected

    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    system_state="$BATS_TEST_TMPDIR/resolver-system-state.json"

    mkdir -p "$current_home" "$target_home/.acfs" "$stale_home/.acfs"
    printf 'live\n' > "$target_home/.acfs/VERSION"
    printf 'stale\n' > "$stale_home/.acfs/VERSION"
    printf '{}\n' > "$target_home/.acfs/state.json"
    printf '{}\n' > "$stale_home/.acfs/state.json"
    printf '# live\n' > "$target_home/.acfs/CHANGELOG.md"
    printf '# stale\n' > "$stale_home/.acfs/CHANGELOG.md"

    cat > "$system_state" <<EOF
{
  "target_home": "$stale_home"
}
EOF

    while IFS='|' read -r label script func expected; do
        run env -i PATH="/usr/bin:/bin" HOME="$current_home" TARGET_HOME="$target_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash -c 'source "$1" >/dev/null 2>&1; func="$2"; "$func"' _ "$script" "$func"
        assert_success
        assert_output "$expected"
    done <<EOF
status|$PROJECT_ROOT/scripts/lib/status.sh|_status_resolve_acfs_home|$target_home/.acfs
dashboard|$PROJECT_ROOT/scripts/lib/dashboard.sh|dashboard_resolve_acfs_home|$target_home/.acfs
export-config|$PROJECT_ROOT/scripts/lib/export-config.sh|resolve_acfs_home|$target_home/.acfs
support|$PROJECT_ROOT/scripts/lib/support.sh|support_resolve_acfs_home|$target_home/.acfs
cheatsheet|$PROJECT_ROOT/scripts/lib/cheatsheet.sh|cheatsheet_resolve_acfs_home|$target_home/.acfs
continue|$PROJECT_ROOT/scripts/lib/continue.sh|get_install_state_file|$target_home/.acfs/state.json
changelog|$PROJECT_ROOT/scripts/lib/changelog.sh|resolve_changelog_acfs_home|$target_home/.acfs
EOF
}

@test "target home resolvers honor explicit TARGET_HOME over stale system state" {
    local current_home
    local target_home
    local stale_home
    local system_state
    local label
    local script
    local func

    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    system_state="$BATS_TEST_TMPDIR/target-home-resolver-system-state.json"

    mkdir -p "$current_home" "$target_home/.acfs" "$stale_home/.acfs"
    printf '{}\n' > "$target_home/.acfs/state.json"
    printf '{}\n' > "$stale_home/.acfs/state.json"

    cat > "$system_state" <<EOF
{
  "target_home": "$stale_home"
}
EOF

    while IFS='|' read -r label script func; do
        run env -i PATH="/usr/bin:/bin" HOME="$current_home" TARGET_HOME="$target_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash -c 'source "$1" >/dev/null 2>&1; func="$2"; "$func" "$3"' _ "$script" "$func" "$target_home/.acfs/state.json"
        assert_success
        assert_output "$target_home"
    done <<EOF
status|$PROJECT_ROOT/scripts/lib/status.sh|_status_resolve_target_home
export-config|$PROJECT_ROOT/scripts/lib/export-config.sh|resolve_target_home
support|$PROJECT_ROOT/scripts/lib/support.sh|support_resolve_target_home
info|$PROJECT_ROOT/scripts/lib/info.sh|info_resolve_target_home
EOF
}

@test "context builders and info paths honor explicit TARGET_HOME over stale system state" {
    local current_home
    local target_home
    local stale_home
    local system_state

    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    system_state="$BATS_TEST_TMPDIR/context-builder-system-state.json"

    mkdir -p "$current_home" "$target_home/.acfs" "$stale_home/.acfs"
    printf 'live\n' > "$target_home/.acfs/VERSION"
    printf 'stale\n' > "$stale_home/.acfs/VERSION"
    printf '{}\n' > "$target_home/.acfs/state.json"
    printf '{}\n' > "$stale_home/.acfs/state.json"

    cat > "$system_state" <<EOF
{
  "target_home": "$stale_home"
}
EOF

    run env -i PATH="/usr/bin:/bin" HOME="$current_home" TARGET_HOME="$target_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash -c 'source "$1" >/dev/null 2>&1; printf "data_home=%s\nstate_file=%s\ntarget_home=%s\n" "$(info_get_data_home 2>/dev/null || true)" "$(info_get_install_state_file 2>/dev/null || true)" "$(info_resolve_target_home "$(info_get_install_state_file 2>/dev/null || true)" 2>/dev/null || true)"' _ "$PROJECT_ROOT/scripts/lib/info.sh"
    assert_success
    assert_output --partial "data_home=$target_home/.acfs"
    assert_output --partial "state_file=$target_home/.acfs/state.json"
    assert_output --partial "target_home=$target_home"

    run env -i PATH="/usr/bin:/bin" HOME="$current_home" TARGET_HOME="$target_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash -c 'source "$1" >/dev/null 2>&1; dashboard_prepare_context >/dev/null 2>&1; printf "%s\n" "${_DASHBOARD_RESOLVED_TARGET_HOME:-}"' _ "$PROJECT_ROOT/scripts/lib/dashboard.sh"
    assert_success
    assert_output "$target_home"

    run env -i PATH="/usr/bin:/bin" HOME="$current_home" TARGET_HOME="$target_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash -c 'source "$1" >/dev/null 2>&1; support_initialize_context >/dev/null 2>&1; printf "%s\n" "${SUPPORT_TARGET_HOME:-}"' _ "$PROJECT_ROOT/scripts/lib/support.sh"
    assert_success
    assert_output "$target_home"

    run env -i PATH="/usr/bin:/bin" HOME="$current_home" TARGET_HOME="$target_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash -c 'source "$1" >/dev/null 2>&1; cheatsheet_prepare_context >/dev/null 2>&1; printf "%s\n" "${_CHEATSHEET_RESOLVED_TARGET_HOME:-}"' _ "$PROJECT_ROOT/scripts/lib/cheatsheet.sh"
    assert_success
    assert_output "$target_home"
}

@test "current HOME install resolvers beat stale system state" {
    local target_home
    local stale_home
    local system_state
    local label
    local script
    local func
    local expected

    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    system_state="$BATS_TEST_TMPDIR/current-home-stale-system-state.json"

    mkdir -p "$target_home/.acfs/onboard" "$stale_home/.acfs/onboard"
    cat > "$target_home/.acfs/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$target_home"
}
EOF
    cat > "$stale_home/.acfs/state.json" <<EOF
{
  "target_user": "staleuser",
  "target_home": "$stale_home"
}
EOF
    printf 'live\n' > "$target_home/.acfs/VERSION"
    printf 'stale\n' > "$stale_home/.acfs/VERSION"
    printf '# live\n' > "$target_home/.acfs/CHANGELOG.md"
    printf '# stale\n' > "$stale_home/.acfs/CHANGELOG.md"

    cat > "$system_state" <<EOF
{
  "target_home": "$stale_home"
}
EOF

    while IFS='|' read -r label script func expected; do
        run env -i PATH="/usr/bin:/bin" HOME="$target_home" ACFS_SYSTEM_STATE_FILE="$system_state" bash -c '
            source "$1" >/dev/null 2>&1
            target_home="$2"
            system_state="$3"
            label="$4"
            func="$5"

            case "$label" in
                status)
                    _STATUS_CURRENT_HOME="$target_home"
                    _STATUS_DEFAULT_ACFS_HOME="$target_home/.acfs"
                    _STATUS_SYSTEM_STATE_WAS_EXPLICIT=true
                    _STATUS_SYSTEM_STATE_FILE="$system_state"
                    _STATUS_RESOLVED_ACFS_HOME=""
                    _status_resolve_current_user() { printf "tester\n"; }
                    _status_home_for_user() { [[ "${1:-}" == "tester" ]] && printf "%s\n" "$target_home"; }
                    ;;
                info)
                    _INFO_CURRENT_HOME="$target_home"
                    _INFO_DEFAULT_ACFS_HOME="$target_home/.acfs"
                    _INFO_SYSTEM_STATE_WAS_EXPLICIT=true
                    _INFO_SYSTEM_STATE_FILE="$system_state"
                    _INFO_RESOLVED_ACFS_HOME=""
                    info_resolve_current_user() { printf "tester\n"; }
                    info_home_for_user() { [[ "${1:-}" == "tester" ]] && printf "%s\n" "$target_home"; }
                    ;;
                support)
                    _SUPPORT_CURRENT_HOME="$target_home"
                    _SUPPORT_DEFAULT_ACFS_HOME="$target_home/.acfs"
                    SUPPORT_SYSTEM_STATE_WAS_EXPLICIT=true
                    SUPPORT_SYSTEM_STATE_FILE="$system_state"
                    support_resolve_current_user() { printf "tester\n"; }
                    support_home_for_user() { [[ "${1:-}" == "tester" ]] && printf "%s\n" "$target_home"; }
                    ;;
                dashboard)
                    _DASHBOARD_CURRENT_HOME="$target_home"
                    _DASHBOARD_DEFAULT_ACFS_HOME="$target_home/.acfs"
                    _DASHBOARD_SYSTEM_STATE_WAS_EXPLICIT=true
                    _DASHBOARD_SYSTEM_STATE_FILE="$system_state"
                    _DASHBOARD_RESOLVED_ACFS_HOME=""
                    dashboard_resolve_current_user() { printf "tester\n"; }
                    dashboard_home_for_user() { [[ "${1:-}" == "tester" ]] && printf "%s\n" "$target_home"; }
                    ;;
                export-config)
                    _EXPORT_CURRENT_HOME="$target_home"
                    _EXPORT_DEFAULT_ACFS_HOME="$target_home/.acfs"
                    _EXPORT_SYSTEM_STATE_WAS_EXPLICIT=true
                    _EXPORT_SYSTEM_STATE_FILE="$system_state"
                    _EXPORT_RESOLVED_ACFS_HOME=""
                    export_resolve_current_user() { printf "tester\n"; }
                    home_for_user() { [[ "${1:-}" == "tester" ]] && printf "%s\n" "$target_home"; }
                    ;;
                cheatsheet)
                    _CHEATSHEET_CURRENT_HOME="$target_home"
                    _CHEATSHEET_DEFAULT_ACFS_HOME="$target_home/.acfs"
                    _CHEATSHEET_SYSTEM_STATE_WAS_EXPLICIT=true
                    _CHEATSHEET_SYSTEM_STATE_FILE="$system_state"
                    _CHEATSHEET_RESOLVED_ACFS_HOME=""
                    cheatsheet_resolve_current_user() { printf "tester\n"; }
                    cheatsheet_home_for_user() { [[ "${1:-}" == "tester" ]] && printf "%s\n" "$target_home"; }
                    ;;
                onboard)
                    _ONBOARD_CURRENT_HOME="$target_home"
                    _ONBOARD_DEFAULT_ACFS_HOME="$target_home/.acfs"
                    _ONBOARD_SYSTEM_STATE_FILE="$system_state"
                    _ONBOARD_ACFS_HOME=""
                    _ONBOARD_ACFS_HOME_SOURCE=""
                    _ONBOARD_RUNTIME_HOME=""
                    _ONBOARD_RUNTIME_HOME_SOURCE=""
                    onboard_resolve_current_user() { printf "tester\n"; }
                    onboard_home_for_user() { [[ "${1:-}" == "tester" ]] && printf "%s\n" "$target_home"; }
                    onboard_probe_current_home() {
                        _ONBOARD_ACFS_HOME="$(onboard_resolve_acfs_home 2>/dev/null || true)"
                        onboard_resolve_runtime_home >/dev/null 2>&1 || true
                        printf "%s|%s\n" "${_ONBOARD_ACFS_HOME:-}" "${_ONBOARD_RUNTIME_HOME:-}"
                    }
                    ;;
                continue)
                    _CONTINUE_CURRENT_HOME="$target_home"
                    _CONTINUE_DEFAULT_ACFS_HOME="$target_home/.acfs"
                    _CONTINUE_SYSTEM_STATE_FILE="$system_state"
                    _CONTINUE_STATE_FILE=""
                    _CONTINUE_EXPLICIT_ACFS_HOME=""
                    _CONTINUE_EXPLICIT_TARGET_HOME_RAW=""
                    _CONTINUE_EXPLICIT_TARGET_USER_RAW=""
                    continue_resolve_current_user() { printf "tester\n"; }
                    home_for_user() { [[ "${1:-}" == "tester" ]] && printf "%s\n" "$target_home"; }
                    ;;
                changelog)
                    _CHANGELOG_CURRENT_HOME="$target_home"
                    _CHANGELOG_DEFAULT_ACFS_HOME="$target_home/.acfs"
                    _CHANGELOG_ACFS_HOME="$target_home/.acfs"
                    _CHANGELOG_SYSTEM_STATE_WAS_EXPLICIT=true
                    _CHANGELOG_SYSTEM_STATE_FILE="$system_state"
                    _CHANGELOG_RESOLVED_ACFS_HOME=""
                    changelog_resolve_current_user() { printf "tester\n"; }
                    changelog_home_for_user() { [[ "${1:-}" == "tester" ]] && printf "%s\n" "$target_home"; }
                    ;;
                smoke)
                    _SMOKE_CURRENT_USER="tester"
                    _SMOKE_CURRENT_HOME="$target_home"
                    _SMOKE_DEFAULT_ACFS_HOME="$target_home/.acfs"
                    _SMOKE_SYSTEM_STATE_FILE="$system_state"
                    _smoke_resolve_current_user() { printf "tester\n"; }
                    _smoke_home_for_user() { [[ "${1:-}" == "tester" ]] && printf "%s\n" "$target_home"; }
                    ;;
            esac

            "$func"
        ' _ "$script" "$target_home" "$system_state" "$label" "$func"
        assert_success
        assert_output "$expected"
    done <<EOF
status|$PROJECT_ROOT/scripts/lib/status.sh|_status_resolve_acfs_home|$target_home/.acfs
info|$PROJECT_ROOT/scripts/lib/info.sh|info_get_data_home|$target_home/.acfs
support|$PROJECT_ROOT/scripts/lib/support.sh|support_resolve_acfs_home|$target_home/.acfs
dashboard|$PROJECT_ROOT/scripts/lib/dashboard.sh|dashboard_resolve_acfs_home|$target_home/.acfs
export-config|$PROJECT_ROOT/scripts/lib/export-config.sh|resolve_acfs_home|$target_home/.acfs
cheatsheet|$PROJECT_ROOT/scripts/lib/cheatsheet.sh|cheatsheet_resolve_acfs_home|$target_home/.acfs
onboard|$PROJECT_ROOT/packages/onboard/onboard.sh|onboard_probe_current_home|$target_home/.acfs|$target_home
continue|$PROJECT_ROOT/scripts/lib/continue.sh|get_install_state_file|$target_home/.acfs/state.json
changelog|$PROJECT_ROOT/scripts/lib/changelog.sh|resolve_changelog_acfs_home|$target_home/.acfs
smoke|$PROJECT_ROOT/scripts/lib/smoke_test.sh|_smoke_resolve_bootstrap_state_file|$target_home/.acfs/state.json
EOF
}

@test "doctor ignores stale caller ACFS_HOME when resolving install state" {
    local target_home
    local stale_home

    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"

    mkdir -p "$target_home/.acfs" "$stale_home/.acfs"
    cat > "$target_home/.acfs/state.json" <<EOF
{
  "target_user": "tester",
  "target_home": "$target_home"
}
EOF
    cat > "$stale_home/.acfs/state.json" <<EOF
{
  "target_user": "staleuser",
  "target_home": "$stale_home"
}
EOF

    run env -i PATH="/usr/bin:/bin" HOME="$target_home" TARGET_USER="tester" TARGET_HOME="$target_home" ACFS_HOME="$stale_home/.acfs" bash -c '
        eval "$(sed -n "1,/^export ACFS_HOME$/p" "$1")"
        printf "TARGET_USER=%s\nTARGET_HOME=%s\nACFS_HOME=%s\n" "$TARGET_USER" "$TARGET_HOME" "$ACFS_HOME"
    ' _ "$PROJECT_ROOT/scripts/lib/doctor.sh"
    assert_success
    refute_output --partial "staleuser"
    refute_output --partial "$stale_home"
}

@test "home-to-user helpers ignore PATH-poisoned id/whoami/getent shims" {
    local current_user
    local current_home
    local fake_home
    local fake_bin
    local label
    local script
    local func
    local current_home_var

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        current_home="/root"
    else
        current_home="$(getent passwd "$current_user" | cut -d: -f6)"
    fi
    current_home="${current_home%/}"

    fake_home="$(create_temp_dir)"
    fake_bin="$BATS_TEST_TMPDIR/path-poison-bin"
    mkdir -p "$fake_home/.local/bin" "$fake_bin"

    cat > "$fake_bin/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-un" ]]; then
    printf 'poisoned-user\n'
    exit 0
fi
exit 2
EOF
    cat > "$fake_bin/whoami" <<'EOF'
#!/usr/bin/env bash
printf 'poisoned-user\n'
EOF
    cat > "$fake_bin/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]]; then
    printf 'poisoned-user:x:1000:1000::%s:/bin/bash\n' "$fake_home"
    exit 0
fi
exit 2
EOF
    chmod +x "$fake_bin/id" "$fake_bin/whoami" "$fake_bin/getent"

    while IFS='|' read -r label script func current_home_var; do
        run env -i PATH="$fake_bin:/usr/bin:/bin" HOME="$fake_home" bash -s -- "$script" "$label" "$func" "$current_home" "$current_home_var" <<'EOF_HELPER'
script="$1"
label="$2"
func="$3"
current_home="$4"
current_home_var="$5"
case "$label" in
    status)
        eval "$(sed -n "/^_status_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^_status_system_binary_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^_status_resolve_current_user()/,/^}$/p" "$script")"
        eval "$(sed -n "/^_status_read_user_for_home()/,/^}$/p" "$script")"
        ;;
    support)
        eval "$(sed -n "/^support_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^support_system_binary_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^support_resolve_current_user()/,/^}$/p" "$script")"
        eval "$(sed -n "/^support_read_user_for_home()/,/^}$/p" "$script")"
        ;;
    info)
        eval "$(sed -n "/^info_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^info_system_binary_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^info_resolve_current_user()/,/^}$/p" "$script")"
        eval "$(sed -n "/^info_read_user_for_home()/,/^}$/p" "$script")"
        ;;
    export-config)
        eval "$(sed -n "/^export_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^export_system_binary_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^export_resolve_current_user()/,/^}$/p" "$script")"
        eval "$(sed -n "/^read_user_for_home()/,/^}$/p" "$script")"
        ;;
    dashboard)
        eval "$(sed -n "/^dashboard_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^dashboard_system_binary_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^dashboard_resolve_current_user()/,/^}$/p" "$script")"
        eval "$(sed -n "/^dashboard_read_user_for_home()/,/^}$/p" "$script")"
        ;;
    cheatsheet)
        eval "$(sed -n "/^cheatsheet_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^cheatsheet_system_binary_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^cheatsheet_resolve_current_user()/,/^}$/p" "$script")"
        eval "$(sed -n "/^cheatsheet_read_user_for_home()/,/^}$/p" "$script")"
        ;;
esac
export "$current_home_var=$current_home"
"$func" "$current_home"
EOF_HELPER
        assert_success
        assert_output "$current_user"
    done <<EOF
status|$PROJECT_ROOT/scripts/lib/status.sh|_status_read_user_for_home|_STATUS_CURRENT_HOME
support|$PROJECT_ROOT/scripts/lib/support.sh|support_read_user_for_home|_SUPPORT_CURRENT_HOME
info|$PROJECT_ROOT/scripts/lib/info.sh|info_read_user_for_home|_INFO_CURRENT_HOME
export-config|$PROJECT_ROOT/scripts/lib/export-config.sh|read_user_for_home|_EXPORT_CURRENT_HOME
dashboard|$PROJECT_ROOT/scripts/lib/dashboard.sh|dashboard_read_user_for_home|_DASHBOARD_CURRENT_HOME
cheatsheet|$PROJECT_ROOT/scripts/lib/cheatsheet.sh|cheatsheet_read_user_for_home|_CHEATSHEET_CURRENT_HOME
EOF
}

@test "bin-dir validators ignore PATH-poisoned getent passwd streams" {
    local current_user
    local current_home
    local fake_home
    local fake_bin
    local fake_bin_dir
    local label
    local script
    local func

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        current_home="/root"
    else
        current_home="$(getent passwd "$current_user" | cut -d: -f6)"
    fi
    current_home="${current_home%/}"

    fake_home="$(create_temp_dir)"
    fake_bin_dir="$current_home/.local/bin"
    fake_bin="$BATS_TEST_TMPDIR/validate-path-poison-bin"
    mkdir -p "$fake_bin"

    cat > "$fake_bin/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]]; then
    printf 'poisoned-user:x:1000:1000::%s:/bin/bash\n' "$fake_home"
    exit 0
fi
exit 2
EOF
    chmod +x "$fake_bin/getent"

    while IFS='|' read -r label script func; do
        run env -i PATH="$fake_bin:/usr/bin:/bin" HOME="$current_home" bash -s -- "$script" "$label" "$func" "$fake_bin_dir" "$current_home" <<'EOF_VALIDATOR'
script="$1"
label="$2"
func="$3"
fake_bin_dir="$4"
current_home="$5"
case "$label" in
    status)
        eval "$(sed -n "/^_status_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^_status_system_binary_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^_status_validate_bin_dir_for_home()/,/^}$/p" "$script")"
        ;;
    info)
        eval "$(sed -n "/^info_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^info_system_binary_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^info_validate_bin_dir_for_home()/,/^}$/p" "$script")"
        ;;
    export-config)
        eval "$(sed -n "/^export_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^export_system_binary_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^export_validate_bin_dir_for_home()/,/^}$/p" "$script")"
        ;;
    cheatsheet)
        eval "$(sed -n "/^cheatsheet_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^cheatsheet_system_binary_path()/,/^}$/p" "$script")"
        eval "$(sed -n "/^cheatsheet_validate_bin_dir_for_home()/,/^}$/p" "$script")"
        ;;
esac
"$func" "$fake_bin_dir" "$current_home"
EOF_VALIDATOR
        assert_success
        assert_output "$fake_bin_dir"
    done <<EOF
status|$PROJECT_ROOT/scripts/lib/status.sh|_status_validate_bin_dir_for_home
info|$PROJECT_ROOT/scripts/lib/info.sh|info_validate_bin_dir_for_home
export-config|$PROJECT_ROOT/scripts/lib/export-config.sh|export_validate_bin_dir_for_home
cheatsheet|$PROJECT_ROOT/scripts/lib/cheatsheet.sh|cheatsheet_validate_bin_dir_for_home
EOF
}


@test "continue state-file scan ignores PATH-poisoned getent output" {
    local safe_home
    local poisoned_home
    local safe_bin
    local poison_bin

    safe_home="$(create_temp_dir)"
    poisoned_home="$(create_temp_dir)"
    safe_bin="$BATS_TEST_TMPDIR/continue-safe-bin"
    poison_bin="$BATS_TEST_TMPDIR/continue-poison-bin"

    mkdir -p "$safe_home/.acfs" "$poisoned_home/.acfs" "$safe_bin" "$poison_bin"
    printf '{}\n' > "$safe_home/.acfs/state.json"
    printf '{}\n' > "$poisoned_home/.acfs/state.json"

    cat > "$safe_bin/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]]; then
    printf 'safe-user:x:1000:1000::%s:/bin/bash\n' "$safe_home"
    exit 0
fi
exit 2
EOF
    cat > "$poison_bin/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]]; then
    printf 'poisoned-user:x:1000:1000::%s:/bin/bash\n' "$poisoned_home"
    exit 0
fi
exit 2
EOF
    chmod +x "$safe_bin/getent" "$poison_bin/getent"

    run env -i PATH="$poison_bin:/usr/bin:/bin" SAFE_BIN="$safe_bin" bash -s -- "$PROJECT_ROOT/scripts/lib/continue.sh" <<'EOF_CONTINUE_SCAN'
script="$1"
eval "$(sed -n "/^find_scanned_install_state_file()/,/^}$/p" "$script")"
continue_system_binary_path() {
    local name="${1:-}"
    [[ "$name" == "getent" ]] || return 1
    printf '%s\n' "$SAFE_BIN/getent"
}
find_scanned_install_state_file
EOF_CONTINUE_SCAN
    assert_success
    assert_output "$safe_home/.acfs/state.json"
}

@test "support environment summary ignores PATH-poisoned whoami fallback" {
    local current_user
    local current_home
    local fake_bin
    local bundle_dir
    local acfs_home
    local jq_real

    jq_real="$(command -v jq 2>/dev/null || true)"
    [[ -n "$jq_real" ]] || skip "jq required"

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        current_home="/root"
    else
        current_home="$(getent passwd "$current_user" | cut -d: -f6)"
    fi
    current_home="${current_home%/}"

    fake_bin="$BATS_TEST_TMPDIR/support-path-poison-bin"
    bundle_dir="$(create_temp_dir)"
    acfs_home="$(create_temp_dir)/.acfs"
    mkdir -p "$fake_bin" "$bundle_dir" "$acfs_home"

    cat > "$fake_bin/whoami" <<'EOF'
#!/usr/bin/env bash
printf 'poisoned-user\n'
EOF
    cat > "$fake_bin/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_real" "\$@"
EOF
    chmod +x "$fake_bin/whoami" "$fake_bin/jq"
    printf '0.0.0-test\n' > "$acfs_home/VERSION"

    run env -i PATH="$fake_bin:/usr/bin:/bin" HOME="$current_home" SHELL="/bin/bash" bash -s -- "$PROJECT_ROOT/scripts/lib/support.sh" "$bundle_dir" "$acfs_home" <<'EOF_SUPPORT_ENV'
script="$1"
bundle_dir="$2"
acfs_home="$3"
record_bundle_file() { :; }
log_warn() { :; }
eval "$(sed -n "/^support_system_binary_path()/,/^}$/p" "$script")"
eval "$(sed -n "/^support_resolve_current_user()/,/^}$/p" "$script")"
eval "$(sed -n "/^capture_env_summary()/,/^}$/p" "$script")"
_SUPPORT_CURRENT_HOME="$HOME"
_SUPPORT_ACFS_HOME="$acfs_home"
SUPPORT_TARGET_HOME="$HOME"
SUPPORT_TARGET_USER=""
capture_env_summary "$bundle_dir"
jq -r '.user' "$bundle_dir/environment.json"
EOF_SUPPORT_ENV
    assert_success
    assert_output "$current_user"
}

@test "dashboard serve banner ignores PATH-poisoned whoami fallback" {
    local current_user
    local current_home
    local fake_bin
    local acfs_home
    local port

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        current_home="/root"
    else
        current_home="$(getent passwd "$current_user" | cut -d: -f6)"
    fi
    current_home="${current_home%/}"

    fake_bin="$BATS_TEST_TMPDIR/dashboard-path-poison-bin"
    acfs_home="$(create_temp_dir)/.acfs"
    port=18080
    mkdir -p "$fake_bin" "$acfs_home/dashboard"
    printf '<html></html>\n' > "$acfs_home/dashboard/index.html"

    cat > "$fake_bin/whoami" <<'EOF'
#!/usr/bin/env bash
printf 'poisoned-user\n'
EOF
    cat > "$fake_bin/python3" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$fake_bin/whoami" "$fake_bin/python3"

    run env -i PATH="$fake_bin:/usr/bin:/bin" HOME="$current_home" bash -s -- "$PROJECT_ROOT/scripts/lib/dashboard.sh" "$acfs_home" "$port" <<'EOF_DASHBOARD_SERVE'
script="$1"
acfs_home="$2"
port="$3"
validate_port() { return 0; }
dashboard_generate() { return 0; }
eval "$(sed -n "/^dashboard_system_binary_path()/,/^}$/p" "$script")"
eval "$(sed -n "/^dashboard_resolve_current_user()/,/^}$/p" "$script")"
eval "$(sed -n "/^dashboard_serve()/,/^}$/p" "$script")"
_DASHBOARD_ACFS_HOME="$acfs_home"
_DASHBOARD_RESOLVED_TARGET_USER=""
dashboard_serve --port "$port"
EOF_DASHBOARD_SERVE
    assert_success
    [[ "$output" == *"${current_user}@"* ]]
    [[ "$output" != *"poisoned-user@"* ]]
}

@test "dashboard generate failure clears cleanup RETURN trap under set -u" {
    local acfs_home
    local fake_info
    local test_home

    acfs_home="$(create_temp_dir)/.acfs"
    fake_info="$(create_temp_dir)/info.sh"
    test_home="$(create_temp_dir)"
    mkdir -p "$acfs_home/dashboard"

    cat > "$fake_info" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
    chmod +x "$fake_info"

    run env -i PATH="/usr/bin:/bin" HOME="$test_home" ACFS_HOME="$acfs_home" bash -s -- "$PROJECT_ROOT/scripts/lib/dashboard.sh" "$fake_info" "$acfs_home" <<'EOF_DASHBOARD_TRAP'
set -euo pipefail
script="$1"
fake_info="$2"
acfs_home="$3"

source "$script"
set -euo pipefail

find_info_script() {
    printf '%s\n' "$fake_info"
}

dashboard_prepare_context() {
    _DASHBOARD_ACFS_HOME="$acfs_home"
}

dashboard_generate --force >/dev/null 2>&1 || true
source /dev/null
trap -p RETURN
EOF_DASHBOARD_TRAP

    assert_success
    assert_output ""
}

@test "username helpers and wrappers allow dotted usernames and validate before re-exec" {
    local update_wrapper="$PROJECT_ROOT/scripts/acfs-update"
    local global_wrapper="$PROJECT_ROOT/scripts/acfs-global"
    local preflight="$PROJECT_ROOT/scripts/preflight.sh"
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local onboard="$PROJECT_ROOT/packages/onboard/onboard.sh"

    run grep -F '[[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]' "$update_wrapper"
    assert_success

    run grep -F '[[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]' "$global_wrapper"
    assert_success

    run grep -F "validate_target_user_or_die \"\$user\"" "$update_wrapper"
    assert_success

    run grep -F "validate_target_user_or_die \"\$user\"" "$global_wrapper"
    assert_success

    run grep -F '[[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]' "$preflight"
    assert_success

    run grep -F '[[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]]' "$services_setup"
    assert_success

    run grep -F 'onboard_passwd_home_from_entry() {' "$onboard"
    assert_success

    run grep -F 'home_candidate="$(onboard_lookup_passwd_home "$user" 2>/dev/null || true)"' "$onboard"
    assert_success

    run grep -F 'home_candidate="$(onboard_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"' "$onboard"
    assert_success

    run grep -F 'done < <(onboard_getent_passwd_entry 2>/dev/null || true)' "$onboard"
    assert_success

    run grep -F 'jq_bin="$(onboard_system_binary_path jq 2>/dev/null || true)"' "$onboard"
    assert_success

    run grep -F 'sed_bin="$(onboard_system_binary_path sed 2>/dev/null || true)"' "$onboard"
    assert_success

    run grep -F 'cut -d: -f6' "$onboard"
    assert_failure

    run grep -F 'awk -F: -v u=' "$onboard"
    assert_failure

    run grep -F "printf '/home/%s\n' \"\$user\"" "$onboard"
    assert_failure
}

@test "onboard_home_for_user prefers passwd home over stale cached current home" {
    local onboard="$PROJECT_ROOT/packages/onboard/onboard.sh"
    local passwd_home
    local stale_home

    passwd_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"

    eval "$(sed -n '/^onboard_sanitize_abs_nonroot_path()/,/^}$/p' "$onboard")"
    eval "$(sed -n '/^onboard_passwd_home_from_entry()/,/^}$/p' "$onboard")"
    eval "$(sed -n '/^onboard_lookup_passwd_home()/,/^}$/p' "$onboard")"
    eval "$(sed -n '/^onboard_home_for_user()/,/^}$/p' "$onboard")"

    onboard_resolve_current_user() { printf 'tester\n'; }
    onboard_getent_passwd_entry() {
        if [[ "${1:-}" == "tester" ]]; then
            printf 'tester:x:1000:1000::%s:/bin/bash\n' "$passwd_home"
            return 0
        fi
        return 1
    }

    _ONBOARD_CURRENT_HOME="$stale_home"
    export HOME="$stale_home"

    run onboard_home_for_user "tester"
    assert_success
    assert_output "$passwd_home"

    onboard_getent_passwd_entry() { return 1; }

    run onboard_home_for_user "tester"
    assert_success
    assert_output "$stale_home"
}

@test "run-as-user helper libs validate target context and preserve repaired env" {
    local cli_tools="$PROJECT_ROOT/scripts/lib/cli_tools.sh"
    local agents="$PROJECT_ROOT/scripts/lib/agents.sh"
    local languages="$PROJECT_ROOT/scripts/lib/languages.sh"
    local cloud_db="$PROJECT_ROOT/scripts/lib/cloud_db.sh"
    local stack="$PROJECT_ROOT/scripts/lib/stack.sh"

    run grep -F '_cli_validate_target_user "$target_user" || return 1' "$cli_tools"
    assert_success
    run grep -F 'wrapped_cmd="export TARGET_USER=$target_user_q TARGET_HOME=$target_home_q HOME=$target_home_q;"' "$cli_tools"
    assert_success
    run grep -F 'wrapped_cmd+=" export PATH=$target_path_prefix_q:\$PATH; set -o pipefail; cd \"\$HOME\" || exit 1; $cmd"' "$cli_tools"
    assert_success

    run grep -F '_agent_validate_target_user "$target_user" || return 1' "$agents"
    assert_success
    run grep -F 'wrapped_cmd="export TARGET_USER=$target_user_q TARGET_HOME=$target_home_q HOME=$target_home_q;"' "$agents"
    assert_success
    run grep -F 'wrapped_cmd+=" export PATH=$target_path_prefix_q:\$PATH; set -o pipefail; cd \"\$HOME\" || exit 1; $cmd"' "$agents"
    assert_success

    run grep -F '_lang_validate_target_user "$target_user" || return 1' "$languages"
    assert_success
    run grep -F 'wrapped_cmd="export TARGET_USER=$target_user_q TARGET_HOME=$target_home_q HOME=$target_home_q;"' "$languages"
    assert_success
    run grep -F 'wrapped_cmd+=" export PATH=$target_path_prefix_q:\$PATH; set -o pipefail; cd \"\$HOME\" || exit 1; $cmd"' "$languages"
    assert_success

    run grep -F '_cloud_validate_target_user "$target_user" || return 1' "$cloud_db"
    assert_success
    run grep -F 'wrapped_cmd="export TARGET_USER=$target_user_q TARGET_HOME=$target_home_q HOME=$target_home_q;"' "$cloud_db"
    assert_success
    run grep -F 'wrapped_cmd+=" export PATH=$target_path_prefix_q:\$PATH; set -o pipefail; cd \"\$HOME\" || exit 1; $cmd"' "$cloud_db"
    assert_success

    run grep -F '_stack_validate_target_user "$target_user" || return 1' "$stack"
    assert_success
    run grep -F 'printf -v target_path_prefix_q' "$stack"
    assert_success
    run grep -F 'wrapped_cmd+=" export PATH=$target_path_prefix_q:$system_path_prefix:\$PATH; set -o pipefail; cd \"\$HOME\" || exit 1; $cmd"' "$stack"
    assert_success
}

@test "stack run-as-user treats target PATH as inert shell data" {
    local marker="$BATS_TEST_TMPDIR/stack-path-pwn"
    local poisoned_home="$BATS_TEST_TMPDIR/home-\$(printf pwn > $marker)"

    mkdir -p "$poisoned_home/.local/bin"
    export HOME="$poisoned_home"
    export TARGET_HOME="$poisoned_home"
    export ACFS_BIN_DIR="$poisoned_home/.local/bin"
    unset TARGET_USER

    source_lib "stack"
    _stack_resolve_current_user() {
        printf 'ubuntu\n'
    }

    run _stack_run_as_user "printf 'ok\n'"
    assert_success
    assert_output "ok"
    [[ ! -e "$marker" ]] || fail "_stack_run_as_user executed target PATH as shell source"
}

@test "stack helpers can trust explicitly resolved TARGET_HOME for doctor/update repairs" {
    source_lib "stack"

    local target_home="$BATS_TEST_TMPDIR/target-home"
    local target_am="$target_home/mcp_agent_mail/am"
    mkdir -p "$(dirname "$target_am")"
    cat > "$target_am" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$target_am"

    export TARGET_USER="ubuntu"
    export TARGET_HOME="$target_home"
    export ACFS_BIN_DIR="/home/ubuntu/.local/bin"
    export ACFS_STACK_TRUST_TARGET_HOME=true

    run _stack_agent_mail_cli_path
    assert_success
    assert_output "$target_am"
}

@test "stack SLB installer checks active Go PATH lines only" {
    local stack="$PROJECT_ROOT/scripts/lib/stack.sh"

    run grep -F 'acfs_has_active_go_bin_path() {' "$stack"
    assert_success

    run grep -F 'if ! acfs_has_active_go_bin_path ~/.zshrc; then' "$stack"
    assert_success

    run grep -F "grep -q 'export PATH=.*\$HOME/go/bin' ~/.zshrc" "$stack"
    assert_failure
}

@test "run-as-user helper libs reject invalid TARGET_USER before sudo" {
    export TARGET_USER="../bad user"
    export TARGET_HOME="/home/tester"
    export ACFS_BIN_DIR="/home/tester/.local/bin"

    source_lib "cli_tools"
    spy_command "sudo"
    run _cli_run_as_user env
    assert_failure
    assert_output --partial "Invalid TARGET_USER '../bad user'"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_cli_run_as_user should not invoke sudo for invalid TARGET_USER"

    source_lib "agents"
    : > "$STUB_DIR/sudo.log"
    run _agent_run_as_user env
    assert_failure
    assert_output --partial "Invalid TARGET_USER '../bad user'"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_agent_run_as_user should not invoke sudo for invalid TARGET_USER"

    source_lib "languages"
    : > "$STUB_DIR/sudo.log"
    run _lang_run_as_user env
    assert_failure
    assert_output --partial "Invalid TARGET_USER '../bad user'"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_lang_run_as_user should not invoke sudo for invalid TARGET_USER"

    source_lib "cloud_db"
    : > "$STUB_DIR/sudo.log"
    run _cloud_run_as_user env
    assert_failure
    assert_output --partial "Invalid TARGET_USER '../bad user'"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_cloud_run_as_user should not invoke sudo for invalid TARGET_USER"

    source_lib "stack"
    : > "$STUB_DIR/sudo.log"
    run _stack_run_as_user env
    assert_failure
    assert_output --partial "Invalid TARGET_USER '../bad user'"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_stack_run_as_user should not invoke sudo for invalid TARGET_USER"
}

@test "helper home resolvers ignore stale explicit TARGET_HOME" {
    local current_user
    local resolved_home
    local stale_home
    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    [[ -n "$current_user" ]] || fail "Unable to resolve current user"
    resolved_home="$(getent passwd "$current_user" | cut -d: -f6)"
    [[ -n "$resolved_home" && -d "$resolved_home" ]] || fail "Unable to resolve current user home"
    stale_home="$BATS_TEST_TMPDIR/stale-target-home"
    mkdir -p "$stale_home"

    export TARGET_USER="$current_user"
    export TARGET_HOME="$stale_home"
    export HOME="$stale_home"

    source_lib "cli_tools"
    run _cli_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "agents"
    run _agent_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "languages"
    run _lang_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "cloud_db"
    run _cloud_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "stack"
    run _stack_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"
}

@test "helper target-home resolvers do not let current HOME override explicit TARGET_HOME without passwd" {
    local current_home
    local target_home

    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    export TARGET_USER="tester"
    export TARGET_HOME="$target_home"
    export HOME="$current_home"
    unset ACFS_BIN_DIR ACFS_INITIAL_ENV_HOME _UPDATE_INITIAL_ENV_HOME SUDO_USER

    source_lib "cli_tools"
    _cli_resolve_current_user() { printf 'tester\n'; }
    _cli_getent_passwd_entry() { return 2; }
    run _cli_target_home "tester"
    assert_success
    assert_output "$target_home"

    export TARGET_HOME="$current_home"
    run _cli_target_home "tester"
    assert_success
    assert_output "$current_home"
    export TARGET_HOME="$target_home"

    source_lib "agents"
    _agent_resolve_current_user() { printf 'tester\n'; }
    _agent_getent_passwd_entry() { return 2; }
    run _agent_target_home "tester"
    assert_success
    assert_output "$target_home"

    source_lib "languages"
    _lang_resolve_current_user() { printf 'tester\n'; }
    _lang_getent_passwd_entry() { return 2; }
    run _lang_target_home "tester"
    assert_success
    assert_output "$target_home"

    source_lib "cloud_db"
    _cloud_resolve_current_user() { printf 'tester\n'; }
    _cloud_getent_passwd_entry() { return 2; }
    run _cloud_target_home "tester"
    assert_success
    assert_output "$target_home"

    source_lib "stack"
    _stack_resolve_current_user() { printf 'tester\n'; }
    _stack_getent_passwd_entry() { return 2; }
    run _stack_target_home "tester"
    assert_success
    assert_output "$target_home"

    source_lib "autofix"
    autofix_resolve_current_user() { printf 'tester\n'; }
    autofix_lookup_passwd_home() { return 1; }
    run autofix_runtime_home
    assert_success
    assert_output "$target_home"
}

@test "helper home resolvers ignore pre-repair HOME after update.sh fixes HOME" {
    local current_user
    local resolved_home
    local stale_home

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    [[ -n "$current_user" ]] || fail "Unable to resolve current user"
    resolved_home="$(command getent passwd "$current_user" | cut -d: -f6)"
    [[ -n "$resolved_home" && -d "$resolved_home" ]] || fail "Unable to resolve current user home"
    stale_home="$BATS_TEST_TMPDIR/stale-initial-env-home"
    mkdir -p "$stale_home/.local/bin"

    export TARGET_USER="$current_user"
    export TARGET_HOME="$stale_home"
    export HOME="$resolved_home"
    export ACFS_INITIAL_ENV_HOME="$stale_home"
    export ACFS_BIN_DIR="$stale_home/.local/bin"

    source_lib "cli_tools"
    run _cli_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "agents"
    run _agent_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "languages"
    run _lang_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "cloud_db"
    run _cloud_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "stack"
    run _stack_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "autofix"
    run autofix_runtime_home
    assert_success
    assert_output "$resolved_home"
}

@test "helper home resolvers prefer TARGET_USER passwd over stale TARGET_HOME and ACFS_BIN_DIR" {
    local current_user
    local resolved_home
    local caller_home
    local stale_home

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    [[ -n "$current_user" ]] || fail "Unable to resolve current user"
    resolved_home="$(command getent passwd "$current_user" | cut -d: -f6)"
    [[ -n "$resolved_home" && -d "$resolved_home" ]] || fail "Unable to resolve current user home"
    caller_home="$(create_temp_dir)"
    stale_home="$BATS_TEST_TMPDIR/stale-target-home-with-bin"
    mkdir -p "$stale_home/.local/bin"

    export TARGET_USER="$current_user"
    export TARGET_HOME="$stale_home"
    export HOME="$caller_home"
    export ACFS_BIN_DIR="$stale_home/.local/bin"

    source_lib "cli_tools"
    run _cli_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "agents"
    run _agent_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "languages"
    run _lang_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "cloud_db"
    run _cloud_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "stack"
    run _stack_target_home "$current_user"
    assert_success
    assert_output "$resolved_home"

    source_lib "autofix"
    run autofix_runtime_home
    assert_success
    assert_output "$resolved_home"
}

@test "autofix runtime homes fail closed for unresolved target with stale TARGET_HOME" {
    local stale_home

    stale_home="$(create_temp_dir)"
    export TARGET_USER="missinguser"
    export TARGET_HOME="$stale_home"
    export HOME="$stale_home"
    unset SUDO_USER

    source_lib "autofix"
    source_lib "autofix_existing"

    autofix_resolve_current_user() {
        printf 'calleruser\n'
    }

    autofix_lookup_passwd_home() {
        return 1
    }

    run autofix_runtime_home
    assert_failure
    assert_output ""

    run autofix_existing_runtime_home
    assert_failure
    assert_output ""
}

@test "helper home resolvers prefer root home over stale explicit TARGET_HOME" {
    local stale_home
    stale_home="$BATS_TEST_TMPDIR/stale-root-target-home"
    mkdir -p "$stale_home/.local/bin"

    export TARGET_USER="root"
    export TARGET_HOME="$stale_home"
    export HOME="$stale_home"
    export ACFS_BIN_DIR="$stale_home/.local/bin"

    run env TARGET_USER="root" TARGET_HOME="$stale_home" HOME="$stale_home" ACFS_BIN_DIR="$stale_home/.local/bin" bash -c 'source "$1"; printf "%s\n" "$HOME"' _ "$PROJECT_ROOT/scripts/lib/update.sh"
    assert_success
    assert_output "/root"

    run update_target_home "root"
    assert_success
    assert_output "/root"

    source_lib "cli_tools"
    run _cli_target_home "root"
    assert_success
    assert_output "/root"

    source_lib "agents"
    run _agent_target_home "root"
    assert_success
    assert_output "/root"

    source_lib "languages"
    run _lang_target_home "root"
    assert_success
    assert_output "/root"

    source_lib "cloud_db"
    run _cloud_target_home "root"
    assert_success
    assert_output "/root"

    source_lib "stack"
    run _stack_target_home "root"
    assert_success
    assert_output "/root"

    source_lib "autofix"
    run autofix_runtime_home
    assert_success
    assert_output "/root"

    source_lib "github_api"
    run _github_api_runtime_home
    assert_success
    assert_output "/root"
}

@test "helper home resolvers ignore function-poisoned passwd and identity shims" {
    local current_user
    local current_home
    local poisoned_home

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    [[ "$current_user" != "root" ]] || skip "requires non-root current user"
    current_home="$(command getent passwd "$current_user" | cut -d: -f6)"
    current_home="${current_home%/}"
    poisoned_home="$(create_temp_dir)"

    export TARGET_USER=""
    export TARGET_HOME=""
    export HOME="$current_home"

    getent() {
        if [[ "$1" == "passwd" && "$2" == "$current_user" ]]; then
            printf '%s:x:1000:1000::%s:/bin/bash\n' "$current_user" "$poisoned_home"
            return 0
        fi
        command getent "$@"
    }

    id() {
        if [[ "$1" == "-un" ]]; then
            printf 'poisoned-user\n'
            return 0
        fi
        command id "$@"
    }

    whoami() {
        printf 'poisoned-user\n'
    }

    source_lib "cli_tools"
    run _cli_target_home "$current_user"
    assert_success
    assert_output "$current_home"

    source_lib "agents"
    run _agent_target_home "$current_user"
    assert_success
    assert_output "$current_home"

    source_lib "languages"
    run _lang_target_home "$current_user"
    assert_success
    assert_output "$current_home"

    source_lib "cloud_db"
    run _cloud_target_home "$current_user"
    assert_success
    assert_output "$current_home"

    source_lib "stack"
    run _stack_target_home "$current_user"
    assert_success
    assert_output "$current_home"
}

@test "run-as-user helper libs ignore function-poisoned whoami on same-user fast path" {
    local current_user
    local current_home

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    [[ "$current_user" != "root" ]] || skip "requires non-root current user"
    current_home="$(command getent passwd "$current_user" | cut -d: -f6)"
    current_home="${current_home%/}"
    mkdir -p "$current_home/.local/bin"

    export TARGET_USER="$current_user"
    export TARGET_HOME="$current_home"
    export HOME="$current_home"
    export ACFS_BIN_DIR="$current_home/.local/bin"

    whoami() {
        printf 'poisoned-user\n'
    }

    source_lib "cli_tools"
    spy_command "sudo"
    run _cli_run_as_user 'printf "%s\n" "$HOME"'
    assert_success
    assert_output "$current_home"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_cli_run_as_user should not invoke sudo for same-user fast path"

    source_lib "agents"
    : > "$STUB_DIR/sudo.log"
    run _agent_run_as_user 'printf "%s\n" "$HOME"'
    assert_success
    assert_output "$current_home"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_agent_run_as_user should not invoke sudo for same-user fast path"

    source_lib "languages"
    : > "$STUB_DIR/sudo.log"
    run _lang_run_as_user 'printf "%s\n" "$HOME"'
    assert_success
    assert_output "$current_home"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_lang_run_as_user should not invoke sudo for same-user fast path"

    source_lib "cloud_db"
    : > "$STUB_DIR/sudo.log"
    run _cloud_run_as_user 'printf "%s\n" "$HOME"'
    assert_success
    assert_output "$current_home"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_cloud_run_as_user should not invoke sudo for same-user fast path"

    source_lib "stack"
    : > "$STUB_DIR/sudo.log"
    run _stack_run_as_user 'printf "%s\n" "$HOME"'
    assert_success
    assert_output "$current_home"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_stack_run_as_user should not invoke sudo for same-user fast path"
}

@test "run-as-user helper libs ignore function-poisoned privilege helpers" {
    local target_home
    local safe_sudo
    local bash_bin
    local marker

    target_home="$(create_temp_dir)"
    safe_sudo="$target_home/safe-sudo"
    bash_bin="$(command -v bash)"
    marker="$target_home/poisoned"
    mkdir -p "$target_home/.local/bin"
    export TARGET_USER="acfsuser"
    export TARGET_HOME="$target_home"
    export ACFS_BIN_DIR="$target_home/.local/bin"
    export TEST_PRIV_TARGET_HOME="$target_home"
    export TEST_PRIV_SAFE_SUDO="$safe_sudo"
    export TEST_PRIV_BASH_BIN="$bash_bin"
    export TEST_PRIV_MARKER="$marker"

    cat > "$safe_sudo" <<'EOF'
#!/usr/bin/env bash
printf 'safe-sudo:%s\n' "$*"
EOF
    chmod +x "$safe_sudo"

    bash() {
        printf 'bash\n' > "$TEST_PRIV_MARKER"
        return 99
    }
    sudo() {
        printf 'sudo\n' > "$TEST_PRIV_MARKER"
        return 99
    }
    runuser() {
        printf 'runuser\n' > "$TEST_PRIV_MARKER"
        return 99
    }
    su() {
        printf 'su\n' > "$TEST_PRIV_MARKER"
        return 99
    }

    source_lib "cli_tools"
    _cli_resolve_current_user() { printf 'calleruser\n'; }
    _cli_target_home() { printf '%s\n' "$TEST_PRIV_TARGET_HOME"; }
    _cli_system_binary_path() {
        case "${1:-}" in
            bash) printf '%s\n' "$TEST_PRIV_BASH_BIN" ;;
            sudo) printf '%s\n' "$TEST_PRIV_SAFE_SUDO" ;;
            runuser|su) return 1 ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }
    run _cli_run_as_user "printf ok"
    assert_success
    assert_output --partial "safe-sudo:"
    [[ ! -e "$marker" ]] || fail "_cli_run_as_user executed function-poisoned helper: $(<"$marker")"

    source_lib "agents"
    _agent_resolve_current_user() { printf 'calleruser\n'; }
    _agent_target_home() { printf '%s\n' "$TEST_PRIV_TARGET_HOME"; }
    _agent_system_binary_path() {
        case "${1:-}" in
            bash) printf '%s\n' "$TEST_PRIV_BASH_BIN" ;;
            sudo) printf '%s\n' "$TEST_PRIV_SAFE_SUDO" ;;
            runuser|su) return 1 ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }
    run _agent_run_as_user "printf ok"
    assert_success
    assert_output --partial "safe-sudo:"
    [[ ! -e "$marker" ]] || fail "_agent_run_as_user executed function-poisoned helper: $(<"$marker")"

    source_lib "languages"
    _lang_resolve_current_user() { printf 'calleruser\n'; }
    _lang_target_home() { printf '%s\n' "$TEST_PRIV_TARGET_HOME"; }
    _lang_system_binary_path() {
        case "${1:-}" in
            bash) printf '%s\n' "$TEST_PRIV_BASH_BIN" ;;
            sudo) printf '%s\n' "$TEST_PRIV_SAFE_SUDO" ;;
            runuser|su) return 1 ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }
    run _lang_run_as_user "printf ok"
    assert_success
    assert_output --partial "safe-sudo:"
    [[ ! -e "$marker" ]] || fail "_lang_run_as_user executed function-poisoned helper: $(<"$marker")"

    source_lib "cloud_db"
    _cloud_resolve_current_user() { printf 'calleruser\n'; }
    _cloud_target_home() { printf '%s\n' "$TEST_PRIV_TARGET_HOME"; }
    _cloud_system_binary_path() {
        case "${1:-}" in
            bash) printf '%s\n' "$TEST_PRIV_BASH_BIN" ;;
            sudo) printf '%s\n' "$TEST_PRIV_SAFE_SUDO" ;;
            runuser|su) return 1 ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }
    run _cloud_run_as_user "printf ok"
    assert_success
    assert_output --partial "safe-sudo:"
    [[ ! -e "$marker" ]] || fail "_cloud_run_as_user executed function-poisoned helper: $(<"$marker")"

    source_lib "stack"
    _stack_resolve_current_user() { printf 'calleruser\n'; }
    _stack_target_home() { printf '%s\n' "$TEST_PRIV_TARGET_HOME"; }
    _stack_target_bin_dir() { printf '%s\n' "$TEST_PRIV_TARGET_HOME/.local/bin"; }
    _stack_system_binary_path() {
        case "${1:-}" in
            bash) printf '%s\n' "$TEST_PRIV_BASH_BIN" ;;
            sudo) printf '%s\n' "$TEST_PRIV_SAFE_SUDO" ;;
            runuser|su) return 1 ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }
    run _stack_run_as_user "printf ok"
    assert_success
    assert_output --partial "safe-sudo:"
    [[ ! -e "$marker" ]] || fail "_stack_run_as_user executed function-poisoned helper: $(<"$marker")"
}

@test "helper bin-dir selectors ignore function-poisoned getent passwd streams" {
    local current_user
    local current_home
    local fake_home
    local fake_bin_dir

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    current_home="$(command getent passwd "$current_user" | cut -d: -f6)"
    current_home="${current_home%/}"
    fake_home="$(create_temp_dir)"
    fake_bin_dir="$fake_home/.local/bin"
    mkdir -p "$fake_bin_dir" "$current_home/.local/bin"

    export TARGET_USER="$current_user"
    export TARGET_HOME="$current_home"
    export HOME="$current_home"
    export ACFS_BIN_DIR="$fake_bin_dir"

    getent() {
        if [[ "$1" == "passwd" ]]; then
            printf 'poisoned-user:x:1000:1000::%s:/bin/bash\n' "$fake_home"
            return 0
        fi
        command getent "$@"
    }

    source_lib "cli_tools"
    run _cli_validate_bin_dir_for_home "$fake_bin_dir" ""
    assert_success
    assert_output "$fake_bin_dir"

    source_lib "agents"
    run _agent_validate_bin_dir_for_home "$fake_bin_dir" ""
    assert_success
    assert_output "$fake_bin_dir"

    source_lib "stack"
    run _stack_target_bin_dir "$current_user"
    assert_success
    assert_output "$current_home/.local/bin"
}

@test "services-setup: resolve_home_dir prefers current HOME over guessed standard path" {
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local resolved_home
    resolved_home="$(create_temp_dir)"

    eval "$(sed -n '/^services_setup_sanitize_abs_nonroot_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_system_binary_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_resolve_current_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_getent_passwd_entry()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$services_setup")"

    export HOME="$resolved_home"

    services_setup_resolve_current_user() {
        printf 'tester\n'
    }

    services_setup_getent_passwd_entry() {
        return 1
    }

    run resolve_home_dir "tester"
    assert_success
    assert_output "$resolved_home"
}

@test "services-setup: resolve_home_dir does not let current HOME override explicit target home" {
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local current_home
    local target_home

    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    eval "$(sed -n '/^services_setup_sanitize_abs_nonroot_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_system_binary_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_resolve_current_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_getent_passwd_entry()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$services_setup")"

    export HOME="$current_home"

    services_setup_resolve_current_user() {
        printf 'tester\n'
    }

    services_setup_getent_passwd_entry() {
        return 1
    }

    run resolve_home_dir "tester" "$target_home"
    assert_failure

    run resolve_home_dir "tester" "$current_home"
    assert_success
    assert_output "$current_home"
}

@test "services-setup: resolve_current_home fails closed when HOME is invalid and passwd lookup fails" {
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"

    eval "$(sed -n '/^services_setup_sanitize_abs_nonroot_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_system_binary_path()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_resolve_current_user()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_getent_passwd_entry()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_passwd_home_from_entry()/,/^}$/p' "$services_setup")"
    eval "$(sed -n '/^services_setup_resolve_current_home()/,/^}$/p' "$services_setup")"

    export HOME="relative-home"

    services_setup_resolve_current_user() {
        printf 'tester\n'
    }

    services_setup_getent_passwd_entry() {
        return 1
    }

    run services_setup_resolve_current_home
    assert_failure
    assert_output ""
}

@test "remaining helpers: resolve_current_home prefers passwd home over mismatched absolute HOME" {
    local current_user
    local passwd_home
    local poisoned_home
    local failures=""
    local label
    local script
    local func

    current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    passwd_home="$(create_temp_dir)"
    poisoned_home="$(create_temp_dir)"
    mkdir -p "$passwd_home" "$poisoned_home"
    export ACFS_TEST_CURRENT_USER="$current_user"
    export ACFS_TEST_PASSWD_HOME="$passwd_home"

    getent() {
        if [[ "${1:-}" == "passwd" ]] && [[ "${2:-}" == "$ACFS_TEST_CURRENT_USER" ]]; then
            printf '%s:x:1000:1000::%s:/bin/bash\n' "$ACFS_TEST_CURRENT_USER" "$ACFS_TEST_PASSWD_HOME"
            return 0
        fi
        return 2
    }

    id() {
        if [[ "${1:-}" == "-un" ]]; then
            printf '%s\n' "$ACFS_TEST_CURRENT_USER"
            return 0
        fi
        command id "$@"
    }

    whoami() {
        printf '%s\n' "$ACFS_TEST_CURRENT_USER"
    }

    while IFS='|' read -r label script func; do
        [[ -n "$label" ]] || continue

        case "$label" in
            preflight)
                local preflight_bin_dir="$BATS_TEST_TMPDIR/preflight-bin"
                mkdir -p "$preflight_bin_dir"
                cat > "$preflight_bin_dir/id" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-un" ]]; then
    echo "$current_user"
    exit 0
fi
exit 2
EOF
                cat > "$preflight_bin_dir/whoami" <<EOF
#!/usr/bin/env bash
echo "$current_user"
EOF
                cat > "$preflight_bin_dir/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "$current_user" ]]; then
    echo "$current_user:x:1000:1000::$passwd_home:/bin/bash"
    exit 0
fi
if [[ "\${1:-}" == "passwd" ]] && [[ -z "\${2:-}" ]]; then
    echo "$current_user:x:1000:1000::$passwd_home:/bin/bash"
    exit 0
fi
exit 2
EOF
                chmod +x "$preflight_bin_dir/id" "$preflight_bin_dir/whoami" "$preflight_bin_dir/getent"
                eval "$(sed -n '/^preflight_sanitize_abs_nonroot_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^preflight_system_binary_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^preflight_getent_passwd_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^resolve_current_user()/,/^}$/p' "$script")"
                eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$script")"
                eval "$(sed -n '/^resolve_current_home()/,/^}$/p' "$script")"
                preflight_system_binary_path() {
                    local name="${1:-}"
                    [[ -n "$name" ]] || return 1
                    echo "$preflight_bin_dir/$name"
                }
                ;;
            services-setup)
                local services_bin_dir="$BATS_TEST_TMPDIR/services-setup-bin"
                mkdir -p "$services_bin_dir"
                cat > "$services_bin_dir/id" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-un" ]]; then
    printf '%s\n' "$current_user"
    exit 0
fi
exit 2
EOF
                cat > "$services_bin_dir/whoami" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$current_user"
EOF
                cat > "$services_bin_dir/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "$current_user" ]]; then
    printf '%s:x:1000:1000::%s:/bin/bash\n' "$current_user" "$passwd_home"
    exit 0
fi
exit 2
EOF
                chmod +x "$services_bin_dir/id" "$services_bin_dir/whoami" "$services_bin_dir/getent"
                eval "$(sed -n '/^services_setup_sanitize_abs_nonroot_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^services_setup_system_binary_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^services_setup_resolve_current_user()/,/^}$/p' "$script")"
                eval "$(sed -n '/^services_setup_getent_passwd_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^services_setup_passwd_home_from_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^services_setup_resolve_current_home()/,/^}$/p' "$script")"
                services_setup_system_binary_path() {
                    local name="${1:-}"
                    [[ -n "$name" ]] || return 1
                    printf '%s/%s\n' "$services_bin_dir" "$name"
                }
                ;;
            notifications)
                local notifications_bin_dir="$BATS_TEST_TMPDIR/notifications-bin"
                mkdir -p "$notifications_bin_dir"
                cat > "$notifications_bin_dir/id" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-un" ]]; then
    printf '%s\n' "$current_user"
    exit 0
fi
exit 2
EOF
                cat > "$notifications_bin_dir/whoami" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$current_user"
EOF
                cat > "$notifications_bin_dir/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "$current_user" ]]; then
    printf '%s:x:1000:1000::%s:/bin/bash\n' "$current_user" "$passwd_home"
    exit 0
fi
exit 2
EOF
                chmod +x "$notifications_bin_dir/id" "$notifications_bin_dir/whoami" "$notifications_bin_dir/getent"
                eval "$(sed -n '/^notifications_sanitize_abs_nonroot_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^notifications_system_binary_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^notifications_resolve_current_user()/,/^}$/p' "$script")"
                eval "$(sed -n '/^notifications_getent_passwd_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^notifications_passwd_home_from_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^notifications_resolve_current_home()/,/^}$/p' "$script")"
                notifications_system_binary_path() {
                    local name="${1:-}"
                    [[ -n "$name" ]] || return 1
                    printf '%s/%s\n' "$notifications_bin_dir" "$name"
                }
                ;;
            notify)
                local notify_bin_dir="$BATS_TEST_TMPDIR/notify-bin"
                mkdir -p "$notify_bin_dir"
                cat > "$notify_bin_dir/id" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-un" ]]; then
    printf '%s\n' "$current_user"
    exit 0
fi
exit 2
EOF
                cat > "$notify_bin_dir/whoami" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$current_user"
EOF
                cat > "$notify_bin_dir/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "$current_user" ]]; then
    printf '%s:x:1000:1000::%s:/bin/bash\n' "$current_user" "$passwd_home"
    exit 0
fi
exit 2
EOF
                chmod +x "$notify_bin_dir/id" "$notify_bin_dir/whoami" "$notify_bin_dir/getent"
                eval "$(sed -n '/^_acfs_notify_sanitize_abs_nonroot_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_acfs_notify_system_binary_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_acfs_notify_resolve_current_user()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_acfs_notify_getent_passwd_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_acfs_notify_passwd_home_from_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_acfs_notify_resolve_current_home()/,/^}$/p' "$script")"
                _acfs_notify_system_binary_path() {
                    local name="${1:-}"
                    [[ -n "$name" ]] || return 1
                    printf '%s/%s\n' "$notify_bin_dir" "$name"
                }
                ;;
            webhook)
                local webhook_bin_dir="$BATS_TEST_TMPDIR/webhook-bin"
                mkdir -p "$webhook_bin_dir"
                cat > "$webhook_bin_dir/id" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-un" ]]; then
    printf '%s\n' "$current_user"
    exit 0
fi
exit 2
EOF
                cat > "$webhook_bin_dir/whoami" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$current_user"
EOF
                cat > "$webhook_bin_dir/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "$current_user" ]]; then
    printf '%s:x:1000:1000::%s:/bin/bash\n' "$current_user" "$passwd_home"
    exit 0
fi
exit 2
EOF
                chmod +x "$webhook_bin_dir/id" "$webhook_bin_dir/whoami" "$webhook_bin_dir/getent"
                eval "$(sed -n '/^webhook_sanitize_abs_nonroot_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^webhook_system_binary_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^webhook_resolve_current_user()/,/^}$/p' "$script")"
                eval "$(sed -n '/^webhook_getent_passwd_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^webhook_passwd_home_from_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^webhook_resolve_current_home()/,/^}$/p' "$script")"
                webhook_system_binary_path() {
                    local name="${1:-}"
                    [[ -n "$name" ]] || return 1
                    printf '%s/%s\n' "$webhook_bin_dir" "$name"
                }
                ;;
            doctor)
                local doctor_bin_dir="$BATS_TEST_TMPDIR/doctor-bin"
                mkdir -p "$doctor_bin_dir"
                cat > "$doctor_bin_dir/id" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-un" ]]; then
    printf '%s\n' "$current_user"
    exit 0
fi
exit 2
EOF
                cat > "$doctor_bin_dir/whoami" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$current_user"
EOF
                cat > "$doctor_bin_dir/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "$current_user" ]]; then
    printf '%s:x:1000:1000::%s:/bin/bash\n' "$current_user" "$passwd_home"
    exit 0
fi
exit 2
EOF
                chmod +x "$doctor_bin_dir/id" "$doctor_bin_dir/whoami" "$doctor_bin_dir/getent"
                eval "$(sed -n '/^_acfs_doctor_sanitize_abs_nonroot_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_acfs_doctor_system_binary_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_acfs_doctor_resolve_current_user()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_acfs_doctor_getent_passwd_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_acfs_doctor_passwd_home_from_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_acfs_doctor_resolve_current_home()/,/^}$/p' "$script")"
                _acfs_doctor_system_binary_path() {
                    local name="${1:-}"
                    [[ -n "$name" ]] || return 1
                    printf '%s/%s\n' "$doctor_bin_dir" "$name"
                }
                ;;
            doctor-fix)
                local doctor_fix_bin_dir="$BATS_TEST_TMPDIR/doctor-fix-bin"
                mkdir -p "$doctor_fix_bin_dir"
                cat > "$doctor_fix_bin_dir/id" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-un" ]]; then
    printf '%s\n' "$current_user"
    exit 0
fi
exit 2
EOF
                cat > "$doctor_fix_bin_dir/whoami" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$current_user"
EOF
                cat > "$doctor_fix_bin_dir/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "$current_user" ]]; then
    printf '%s:x:1000:1000::%s:/bin/bash\n' "$current_user" "$passwd_home"
    exit 0
fi
exit 2
EOF
                chmod +x "$doctor_fix_bin_dir/id" "$doctor_fix_bin_dir/whoami" "$doctor_fix_bin_dir/getent"
                eval "$(sed -n '/^doctor_fix_sanitize_abs_nonroot_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^doctor_fix_is_valid_username()/,/^}$/p' "$script")"
                eval "$(sed -n '/^doctor_fix_system_binary_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^doctor_fix_getent_passwd_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^doctor_fix_current_user()/,/^}$/p' "$script")"
                eval "$(sed -n '/^doctor_fix_passwd_home_from_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^doctor_fix_resolve_home_for_user()/,/^}$/p' "$script")"
                eval "$(sed -n '/^doctor_fix_resolve_current_home()/,/^}$/p' "$script")"
                doctor_fix_system_binary_path() {
                    local name="${1:-}"
                    [[ -n "$name" ]] || return 1
                    printf '%s/%s\n' "$doctor_fix_bin_dir" "$name"
                }
                ;;
            nightly-update)
                local nightly_bin_dir="$BATS_TEST_TMPDIR/nightly-update-bin"
                mkdir -p "$nightly_bin_dir"
                cat > "$nightly_bin_dir/id" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-un" ]]; then
    printf '%s\n' "$current_user"
    exit 0
fi
exit 2
EOF
                cat > "$nightly_bin_dir/whoami" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$current_user"
EOF
                cat > "$nightly_bin_dir/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "$current_user" ]]; then
    printf '%s:x:1000:1000::%s:/bin/bash\n' "$current_user" "$passwd_home"
    exit 0
fi
exit 2
EOF
                chmod +x "$nightly_bin_dir/id" "$nightly_bin_dir/whoami" "$nightly_bin_dir/getent"
                eval "$(sed -n '/^sanitize_abs_nonroot_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^system_binary_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^resolve_current_user()/,/^}$/p' "$script")"
                eval "$(sed -n '/^getent_passwd_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^passwd_home_from_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^resolve_current_home()/,/^}$/p' "$script")"
                system_binary_path() {
                    local name="${1:-}"
                    [[ -n "$name" ]] || return 1
                    printf '%s/%s\n' "$nightly_bin_dir" "$name"
                }
                ;;
            smoke)
                local smoke_bin_dir="$BATS_TEST_TMPDIR/smoke-bin"
                mkdir -p "$smoke_bin_dir"
                cat > "$smoke_bin_dir/id" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-un" ]]; then
    printf '%s\\n' "$current_user"
    exit 0
fi
exit 2
EOF
                cat > "$smoke_bin_dir/whoami" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "$current_user"
EOF
                cat > "$smoke_bin_dir/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "$current_user" ]]; then
    printf '%s:x:1000:1000::%s:/bin/bash\\n' "$current_user" "$passwd_home"
    exit 0
fi
exit 2
EOF
                chmod +x "$smoke_bin_dir/id" "$smoke_bin_dir/whoami" "$smoke_bin_dir/getent"
                eval "$(sed -n '/^_smoke_sanitize_abs_nonroot_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_smoke_system_binary_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_smoke_getent_passwd_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_smoke_resolve_current_user()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_smoke_passwd_home_from_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^_smoke_resolve_current_home()/,/^}$/p' "$script")"
                _smoke_system_binary_path() {
                    local name="${1:-}"
                    [[ -n "$name" ]] || return 1
                    printf '%s/%s\n' "$smoke_bin_dir" "$name"
                }
                ;;
            state)
                local state_bin_dir="$BATS_TEST_TMPDIR/state-bin"
                mkdir -p "$state_bin_dir"
                cat > "$state_bin_dir/id" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-un" ]]; then
    printf '%s\n' "$current_user"
    exit 0
fi
exit 2
EOF
                cat > "$state_bin_dir/whoami" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$current_user"
EOF
                cat > "$state_bin_dir/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" ]] && [[ "\${2:-}" == "$current_user" ]]; then
    printf '%s:x:1000:1000::%s:/bin/bash\n' "$current_user" "$passwd_home"
    exit 0
fi
exit 2
EOF
                chmod +x "$state_bin_dir/id" "$state_bin_dir/whoami" "$state_bin_dir/getent"
                eval "$(sed -n '/^state_sanitize_abs_nonroot_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^state_system_binary_path()/,/^}$/p' "$script")"
                eval "$(sed -n '/^state_resolve_current_user()/,/^}$/p' "$script")"
                eval "$(sed -n '/^state_getent_passwd_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^state_passwd_home_from_entry()/,/^}$/p' "$script")"
                eval "$(sed -n '/^state_resolve_current_home()/,/^}$/p' "$script")"
                state_system_binary_path() {
                    local name="${1:-}"
                    [[ -n "$name" ]] || return 1
                    printf '%s/%s\n' "$state_bin_dir" "$name"
                }
                ;;
        esac

        HOME="$poisoned_home"
        run "$func"
        if [[ "$status" -ne 0 ]] || [[ "$output" != "$passwd_home" ]]; then
            printf -v failures '%s%s: status=%s output=%s\n' "$failures" "$label" "$status" "$output"
        fi
    done <<EOF
preflight|$PROJECT_ROOT/scripts/preflight.sh|resolve_current_home
services-setup|$PROJECT_ROOT/scripts/services-setup.sh|services_setup_resolve_current_home
notifications|$PROJECT_ROOT/scripts/lib/notifications.sh|notifications_resolve_current_home
notify|$PROJECT_ROOT/scripts/lib/notify.sh|_acfs_notify_resolve_current_home
webhook|$PROJECT_ROOT/scripts/lib/webhook.sh|webhook_resolve_current_home
doctor|$PROJECT_ROOT/scripts/lib/doctor.sh|_acfs_doctor_resolve_current_home
doctor-fix|$PROJECT_ROOT/scripts/lib/doctor_fix.sh|doctor_fix_resolve_current_home
nightly-update|$PROJECT_ROOT/scripts/lib/nightly_update.sh|resolve_current_home
smoke|$PROJECT_ROOT/scripts/lib/smoke_test.sh|_smoke_resolve_current_home
state|$PROJECT_ROOT/scripts/lib/state.sh|state_resolve_current_home
EOF

    if [[ -n "$failures" ]]; then
        printf '%s' "$failures" >&2
        return 1
    fi
}

@test "state: resolve_current_home fails closed when HOME is invalid and passwd lookup fails" {
    local state_lib="$PROJECT_ROOT/scripts/lib/state.sh"

    eval "$(sed -n '/^state_sanitize_abs_nonroot_path()/,/^}$/p' "$state_lib")"
    eval "$(sed -n '/^state_passwd_home_from_entry()/,/^}$/p' "$state_lib")"
    eval "$(sed -n '/^state_resolve_current_home()/,/^}$/p' "$state_lib")"

    export HOME="relative-home"

    getent() {
        return 2
    }

    id() {
        if [[ "${1:-}" == "-un" ]]; then
            printf 'tester\n'
            return 0
        fi
        command id "$@"
    }

    whoami() {
        printf 'tester\n'
    }

    run state_resolve_current_home
    assert_failure
    assert_output ""
}

@test "notification runtime homes prefer TARGET_USER passwd over stale TARGET_HOME" {
    local stale_home
    local target_home
    local failures=""

    stale_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    while IFS='|' read -r label script runtime_func; do
        [[ -n "$label" ]] || continue

        if ! bash -c '
            set -euo pipefail
            label="$1"
            script="$2"
            runtime_func="$3"
            stale_home="$4"
            target_home="$5"

            case "$label" in
                notifications)
                    eval "$(sed -n "/^notifications_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^notifications_resolve_current_user()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^notifications_getent_passwd_entry()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^notifications_passwd_home_from_entry()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^notifications_resolve_current_home()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^notifications_runtime_home()/,/^}$/p" "$script")"
                    notifications_resolve_current_user() { printf "calleruser\n"; }
                    notifications_getent_passwd_entry() {
                        if [[ "${1:-}" == "targetuser" ]]; then
                            printf "targetuser:x:1000:1000::%s:/bin/bash\n" "$target_home"
                            return 0
                        fi
                        return 1
                    }
                    ;;
                notify)
                    eval "$(sed -n "/^_acfs_notify_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^_acfs_notify_resolve_current_user()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^_acfs_notify_getent_passwd_entry()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^_acfs_notify_passwd_home_from_entry()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^_acfs_notify_resolve_current_home()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^_acfs_notify_runtime_home()/,/^}$/p" "$script")"
                    _acfs_notify_resolve_current_user() { printf "calleruser\n"; }
                    _acfs_notify_getent_passwd_entry() {
                        if [[ "${1:-}" == "targetuser" ]]; then
                            printf "targetuser:x:1000:1000::%s:/bin/bash\n" "$target_home"
                            return 0
                        fi
                        return 1
                    }
                    ;;
                webhook)
                    eval "$(sed -n "/^webhook_sanitize_abs_nonroot_path()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^webhook_resolve_current_user()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^webhook_getent_passwd_entry()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^webhook_passwd_home_from_entry()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^webhook_resolve_current_home()/,/^}$/p" "$script")"
                    eval "$(sed -n "/^webhook_runtime_home()/,/^}$/p" "$script")"
                    webhook_resolve_current_user() { printf "calleruser\n"; }
                    webhook_getent_passwd_entry() {
                        if [[ "${1:-}" == "targetuser" ]]; then
                            printf "targetuser:x:1000:1000::%s:/bin/bash\n" "$target_home"
                            return 0
                        fi
                        return 1
                    }
                    ;;
            esac

            export TARGET_USER="targetuser"
            export TARGET_HOME="$stale_home"
            export HOME="$stale_home"
            resolved="$("$runtime_func")"
            [[ "$resolved" == "$target_home" ]] || {
                printf "%s passwd mode resolved %s, expected %s\n" "$label" "$resolved" "$target_home" >&2
                exit 1
            }

            export TARGET_USER="bad/user"
            resolved="$("$runtime_func" 2>/dev/null || true)"
            [[ -z "$resolved" ]] || {
                printf "%s invalid mode resolved %s\n" "$label" "$resolved" >&2
                exit 1
            }

            export TARGET_USER="missinguser"
            resolved="$("$runtime_func" 2>/dev/null || true)"
            [[ -z "$resolved" ]] || {
                printf "%s unresolved mode resolved %s\n" "$label" "$resolved" >&2
                exit 1
            }
        ' _ "$label" "$script" "$runtime_func" "$stale_home" "$target_home"; then
            printf -v failures '%s%s failed\n' "$failures" "$label"
        fi
    done <<EOF
notifications|$PROJECT_ROOT/scripts/lib/notifications.sh|notifications_runtime_home
notify|$PROJECT_ROOT/scripts/lib/notify.sh|_acfs_notify_runtime_home
webhook|$PROJECT_ROOT/scripts/lib/webhook.sh|webhook_runtime_home
EOF

    if [[ -n "$failures" ]]; then
        printf '%s' "$failures" >&2
        return 1
    fi
}

@test "notification source-time paths fail closed for unresolved target user" {
    local stale_home
    local notify_script="$PROJECT_ROOT/scripts/lib/notify.sh"
    local notifications_script="$PROJECT_ROOT/scripts/lib/notifications.sh"

    stale_home="$(create_temp_dir)"

    run env TARGET_USER="missinguser" TARGET_HOME="$stale_home" HOME="$stale_home" bash -c 'source "$1"; printf "runtime=%s state=%s\n" "${_ACFS_NOTIFY_RUNTIME_HOME:-}" "${_ACFS_NOTIFY_STATE_DIR:-}"' _ "$notify_script"
    assert_success
    assert_output "runtime= state="

    run env TARGET_USER="missinguser" TARGET_HOME="$stale_home" HOME="$stale_home" bash -c 'source "$1" status >/dev/null || true; printf "runtime=%s dir=%s file=%s\n" "${_ACFS_NOTIFICATIONS_RUNTIME_HOME:-}" "${ACFS_CONFIG_DIR:-}" "${ACFS_CONFIG_FILE:-}"' _ "$notifications_script"
    assert_success
    assert_output "runtime= dir= file="
}

@test "preflight: resolve_current_home fails closed when HOME is invalid and passwd lookup fails" {
    local preflight="$PROJECT_ROOT/scripts/preflight.sh"

    eval "$(sed -n '/^preflight_sanitize_abs_nonroot_path()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_is_valid_username()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_system_binary_path()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_getent_passwd_entry()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_current_user()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_current_home()/,/^}$/p' "$preflight")"

    export HOME="relative-home"

    preflight_system_binary_path() {
        return 1
    }

    run resolve_current_home
    assert_failure
    assert_output ""
}

@test "preflight: resolve_install_target_home fails closed for different unresolved target" {
    local preflight="$PROJECT_ROOT/scripts/preflight.sh"

    eval "$(sed -n '/^preflight_sanitize_abs_nonroot_path()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_is_valid_username()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_system_binary_path()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_getent_passwd_entry()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_current_user()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_current_home()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_install_target_home()/,/^}$/p' "$preflight")"

    export HOME="$(create_temp_dir)"
    export TARGET_USER="missinguser"
    export TARGET_HOME="/"

    resolve_current_user() {
        printf 'tester\n'
    }

    preflight_getent_passwd_entry() {
        return 1
    }

    run resolve_install_target_home
    assert_failure
    assert_output ""
}

@test "preflight: resolve_install_target_home prefers target user passwd home over stale TARGET_HOME" {
    local preflight="$PROJECT_ROOT/scripts/preflight.sh"
    local stale_home
    local target_home

    eval "$(sed -n '/^preflight_sanitize_abs_nonroot_path()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_is_valid_username()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_getent_passwd_entry()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_current_user()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_current_home()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_install_target_home()/,/^}$/p' "$preflight")"

    stale_home="$(create_temp_dir)"
    trusted_home="$(create_temp_dir)"
    export HOME="$stale_home"
    export TARGET_USER="targetuser"
    export TARGET_HOME="$stale_home"
    export TEST_PREFLIGHT_TARGET_HOME="$trusted_home"

    resolve_current_user() {
        printf 'calleruser\n'
    }

    preflight_getent_passwd_entry() {
        if [[ "${1:-}" == "targetuser" ]]; then
            printf 'targetuser:x:1000:1000::%s:/bin/bash\n' "$TEST_PREFLIGHT_TARGET_HOME"
            return 0
        fi
        return 1
    }

    run resolve_install_target_home
    assert_success
    assert_output "$trusted_home"
}

@test "preflight: resolve_install_target_home rejects invalid TARGET_USER before TARGET_HOME" {
    local preflight="$PROJECT_ROOT/scripts/preflight.sh"
    local target_home

    eval "$(sed -n '/^preflight_sanitize_abs_nonroot_path()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_is_valid_username()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_install_target_home()/,/^}$/p' "$preflight")"

    target_home="$(create_temp_dir)"
    export TARGET_USER="bad/user"
    export TARGET_HOME="$target_home"

    run resolve_install_target_home
    assert_failure
    assert_output ""
}

@test "preflight: resolve_install_target_home fails closed for unresolved target with stale TARGET_HOME" {
    local preflight="$PROJECT_ROOT/scripts/preflight.sh"
    local stale_home

    eval "$(sed -n '/^preflight_sanitize_abs_nonroot_path()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_is_valid_username()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_getent_passwd_entry()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_current_user()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_current_home()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_install_target_home()/,/^}$/p' "$preflight")"

    stale_home="$(create_temp_dir)"
    export HOME="$stale_home"
    export TARGET_USER="missinguser"
    export TARGET_HOME="$stale_home"

    resolve_current_user() {
        printf 'calleruser\n'
    }

    preflight_getent_passwd_entry() {
        return 1
    }

    run resolve_install_target_home
    assert_failure
    assert_output ""
}

@test "preflight: resolve_install_target_home honors explicit TARGET_HOME for current target without passwd" {
    local preflight="$PROJECT_ROOT/scripts/preflight.sh"
    local caller_home
    local stale_home

    eval "$(sed -n '/^preflight_sanitize_abs_nonroot_path()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_is_valid_username()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_getent_passwd_entry()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_current_user()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_current_home()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_install_target_home()/,/^}$/p' "$preflight")"

    caller_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    export HOME="$caller_home"
    export TARGET_USER="calleruser"
    export TARGET_HOME="$stale_home"

    resolve_current_user() {
        printf 'calleruser\n'
    }

    preflight_getent_passwd_entry() {
        return 1
    }

    run resolve_install_target_home
    assert_success
    assert_output "$stale_home"

    export TARGET_HOME="$caller_home"

    run resolve_install_target_home
    assert_success
    assert_output "$caller_home"
}

@test "preflight: binary helper ignores stale other-user ACFS_BIN_DIR" {
    local preflight="$PROJECT_ROOT/scripts/preflight.sh"
    local current_home
    local target_home
    local tool_name="acfs-preflight-test-tool"

    eval "$(sed -n '/^preflight_sanitize_abs_nonroot_path()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_is_valid_username()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_system_binary_path()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_getent_passwd_entry()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_current_user()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_validate_bin_dir_for_home()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_home_dir()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_current_home()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^resolve_install_target_home()/,/^}$/p' "$preflight")"
    eval "$(sed -n '/^preflight_binary_path()/,/^}$/p' "$preflight")"

    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    mkdir -p "$current_home/.local/bin" "$target_home/.local/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$current_home/.local/bin/$tool_name"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$target_home/.local/bin/$tool_name"
    chmod +x "$current_home/.local/bin/$tool_name" "$target_home/.local/bin/$tool_name"

    export HOME="$current_home"
    export TARGET_HOME="$target_home"
    unset TARGET_USER
    export ACFS_BIN_DIR="$current_home/.local/bin"

    run preflight_binary_path "$tool_name"
    assert_success
    assert_output "$target_home/.local/bin/$tool_name"
}

@test "run-as-user helper libs reject unresolved TARGET_HOME before sudo" {
    export TARGET_USER="missinguser"
    export TARGET_HOME=""
    export ACFS_BIN_DIR="/home/tester/.local/bin"

    getent() {
        return 2
    }

    source_lib "cli_tools"
    spy_command "sudo"
    run _cli_run_as_user env
    assert_failure
    assert_output --partial "Invalid TARGET_HOME for 'missinguser': <empty>"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_cli_run_as_user should not invoke sudo for unresolved TARGET_HOME"

    source_lib "agents"
    : > "$STUB_DIR/sudo.log"
    run _agent_run_as_user env
    assert_failure
    assert_output --partial "Invalid TARGET_HOME for 'missinguser': <empty>"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_agent_run_as_user should not invoke sudo for unresolved TARGET_HOME"

    source_lib "languages"
    : > "$STUB_DIR/sudo.log"
    run _lang_run_as_user env
    assert_failure
    assert_output --partial "Invalid TARGET_HOME for 'missinguser': <empty>"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_lang_run_as_user should not invoke sudo for unresolved TARGET_HOME"

    source_lib "cloud_db"
    : > "$STUB_DIR/sudo.log"
    run _cloud_run_as_user env
    assert_failure
    assert_output --partial "Invalid TARGET_HOME for 'missinguser': <empty>"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_cloud_run_as_user should not invoke sudo for unresolved TARGET_HOME"

    source_lib "stack"
    : > "$STUB_DIR/sudo.log"
    run _stack_run_as_user env
    assert_failure
    assert_output --partial "Invalid TARGET_HOME for 'missinguser': <empty>"
    [[ ! -s "$STUB_DIR/sudo.log" ]] || fail "_stack_run_as_user should not invoke sudo for unresolved TARGET_HOME"
}

@test "cloud_db username validation accepts dotted target usernames" {
    source_lib "cloud_db"

    run _cloud_validate_username "john.doe"
    assert_success
}

@test "github_api runtime home ignores stale TARGET_HOME and falls back to existing HOME" {
    source_lib "github_api"

    local runtime_home
    local stale_home
    runtime_home="$(create_temp_dir)"
    stale_home="$BATS_TEST_TMPDIR/stale-runtime-home"
    mkdir -p "$stale_home"

    export TARGET_HOME="$stale_home"
    export HOME="$runtime_home"

    run _github_api_runtime_home
    assert_success
    assert_output "$runtime_home"
}

@test "github_api runtime home prefers non-root TARGET_USER home over caller HOME" {
    source_lib "github_api"

    local current_user
    local current_home
    local caller_home

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    [[ -n "$current_user" ]] || fail "Unable to resolve current user"
    [[ "$current_user" != "root" ]] || skip "requires non-root current user"
    current_home="$(command getent passwd "$current_user" | cut -d: -f6)"
    [[ -n "$current_home" && -d "$current_home" ]] || fail "Unable to resolve current user home"
    caller_home="$(create_temp_dir)"

    export TARGET_USER="$current_user"
    export TARGET_HOME=""
    export HOME="$caller_home"

    run _github_api_runtime_home
    assert_success
    assert_output "$current_home"
}

@test "github_api runtime home fails closed for unresolved TARGET_USER with stale TARGET_HOME" {
    source_lib "github_api"

    local stale_home
    stale_home="$(create_temp_dir)"

    export TARGET_USER="missinguser"
    export TARGET_HOME="$stale_home"
    export HOME="$stale_home"

    _github_api_getent_passwd_entry() {
        return 1
    }

    run _github_api_runtime_home
    assert_failure
    assert_output ""
}

@test "ubuntu upgrade target home fails closed for unresolved target with stale TARGET_HOME" {
    source_lib "ubuntu_upgrade"

    local stale_home
    stale_home="$(create_temp_dir)"

    export TARGET_USER="missinguser"
    export TARGET_HOME="$stale_home"
    export HOME="$stale_home"

    ubuntu_lookup_passwd_home() {
        return 1
    }

    ubuntu_resolve_current_user() {
        printf 'calleruser\n'
    }

    run ubuntu_resolve_target_home "missinguser"
    assert_failure
    assert_output ""
}

@test "update init honors explicit TARGET_HOME for early runtime paths" {
    local update="$PROJECT_ROOT/scripts/lib/update.sh"
    local current_home
    local target_home

    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    run env -i PATH="/usr/bin:/bin" HOME="$current_home" TARGET_HOME="$target_home" bash -c '
        source "$1" >/dev/null 2>&1
        printf "HOME=%s\nUPDATE_LOG_DIR=%s\nCHECKSUMS_LOCAL=%s\n" "$HOME" "$UPDATE_LOG_DIR" "$CHECKSUMS_LOCAL"
    ' _ "$update"

    assert_success
    assert_output --partial "HOME=$target_home"
    assert_output --partial "UPDATE_LOG_DIR=$target_home/.acfs/logs/updates"
    assert_output --partial "CHECKSUMS_LOCAL=$target_home/.acfs/checksums.yaml"
}

@test "agent mail MCP path detection prefers target install over current-shell am" {
    source_lib "agents"

    local target_home="$BATS_TEST_TMPDIR/target-home"
    local target_am="$target_home/mcp_agent_mail/am"
    local global_bin="$BATS_TEST_TMPDIR/global-bin"
    mkdir -p "$(dirname "$target_am")" "$global_bin"

    cat > "$target_am" <<'EOF'
#!/usr/bin/env bash
printf 'mcp-agent-mail 0.2.19\n'
EOF
    chmod +x "$target_am"

    cat > "$global_bin/am" <<'EOF'
#!/usr/bin/env bash
printf 'am 0.2.39\n'
EOF
    chmod +x "$global_bin/am"

    export PATH="$global_bin:/usr/bin:/bin"

    run _agent_detect_am_mcp_path "$target_home"
    assert_success
    assert_output "/api/"
}

@test "agent mail MCP path detection ignores current-shell-only am" {
    source_lib "agents"

    local target_home="$BATS_TEST_TMPDIR/target-home"
    local global_bin="$BATS_TEST_TMPDIR/global-bin"
    mkdir -p "$global_bin"

    cat > "$global_bin/am" <<'EOF'
#!/usr/bin/env bash
printf 'mcp-agent-mail 0.2.19\n'
EOF
    chmod +x "$global_bin/am"

    export PATH="$global_bin:/usr/bin:/bin"

    run _agent_detect_am_mcp_path "$target_home"
    assert_success
    assert_output "/mcp/"
}

@test "agent mail resolvers avoid system am fallback" {
    local agents_lib="$PROJECT_ROOT/scripts/lib/agents.sh"
    local stack_lib="$PROJECT_ROOT/scripts/lib/stack.sh"
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local doctor_fix_lib="$PROJECT_ROOT/scripts/lib/doctor_fix.sh"
    local installer="$PROJECT_ROOT/install.sh"

    run rg -n 'command -v am' "$agents_lib" "$stack_lib" "$doctor_lib" "$doctor_fix_lib" "$installer"
    assert_failure

    run rg -n '"/(usr/local/bin|usr/bin|bin|snap/bin)/am"' "$agents_lib" "$stack_lib" "$doctor_lib" "$doctor_fix_lib"
    assert_failure

    run grep -F 'resolve_target_am() {' "$installer"
    assert_success

    run grep -F 'doctor_agent_mail_cli_path() {' "$doctor_lib"
    assert_success

    run grep -F 'doctor_fix_agent_mail_cli_path() {' "$doctor_fix_lib"
    assert_success
}

@test "configure_gemini_settings repairs stale agent mail url after migration" {
    source_lib "agents"

    local target_home="$BATS_TEST_TMPDIR/target-home"
    local settings_dir="$target_home/.gemini"
    local settings_file="$settings_dir/settings.json"
    local target_am="$target_home/mcp_agent_mail/am"
    mkdir -p "$settings_dir" "$(dirname "$target_am")"

    cat > "$target_am" <<'EOF'
#!/usr/bin/env bash
printf 'am 0.2.39\n'
EOF
    chmod +x "$target_am"

    cat > "$settings_file" <<'EOF'
{
  "selectedType": "gemini-api-key",
  "tools": {
    "shell": {
      "enableInteractiveShell": true
    }
  },
  "mcpServers": {
    "mcp-agent-mail": {
      "httpUrl": "http://127.0.0.1:8765/api/"
    }
  }
}
EOF

    _agent_run_as_user() {
        bash -c "$1"
    }

    run _configure_gemini_settings "$target_home"
    assert_success

    run jq -r '.selectedType' "$settings_file"
    assert_success
    assert_output 'oauth-personal'

    run jq -r '.tools.shell.enableInteractiveShell' "$settings_file"
    assert_success
    assert_output 'false'

    run jq -r '.mcpServers."mcp-agent-mail".httpUrl' "$settings_file"
    assert_success
    assert_output 'http://127.0.0.1:8765/mcp/'
}

@test "install and update deploy all acfs doctor-dispatched runtime scripts" {
    local installer="$PROJECT_ROOT/install.sh"
    local update="$PROJECT_ROOT/scripts/lib/update.sh"

    run grep -F 'install_asset "scripts/lib/status.sh" "$ACFS_HOME/scripts/lib/status.sh"' "$installer"
    assert_success
    run grep -F 'install_asset "scripts/lib/changelog.sh" "$ACFS_HOME/scripts/lib/changelog.sh"' "$installer"
    assert_success
    run grep -F 'install_asset "scripts/lib/export-config.sh" "$ACFS_HOME/scripts/lib/export-config.sh"' "$installer"
    assert_success
    run grep -F 'install_asset "scripts/lib/support.sh" "$ACFS_HOME/scripts/lib/support.sh"' "$installer"
    assert_success
    run grep -F 'install_asset "scripts/lib/stack.sh" "$ACFS_HOME/scripts/lib/stack.sh"' "$installer"
    assert_success

    run grep -F '"scripts/lib/status.sh:scripts/lib/status.sh"' "$update"
    assert_success
    run grep -F '"scripts/lib/changelog.sh:scripts/lib/changelog.sh"' "$update"
    assert_success
    run grep -F '"scripts/lib/export-config.sh:scripts/lib/export-config.sh"' "$update"
    assert_success
    run grep -F '"scripts/lib/support.sh:scripts/lib/support.sh"' "$update"
    assert_success
    run grep -F '"scripts/lib/stack.sh:scripts/lib/stack.sh"' "$update"
    assert_success
    run grep -F '"/data/projects/agentic_coding_flywheel_setup/scripts/lib/stack.sh"' "$update"
    assert_success
    run grep -F '"scripts/lib/doctor.sh:bin/acfs"' "$update"
    assert_success
    run grep -F '"scripts/acfs-update:bin/acfs-update"' "$update"
    assert_success
    run grep -F 'for generated_script in "$ACFS_REPO_ROOT/scripts/generated/"*.sh; do' "$update"
    assert_success
    run grep -F 'sync_acfs_global_wrapper' "$update"
    assert_success
}

@test "update_source_stack_lib skips stale stack candidates missing Agent Mail helpers" {
    local stale_lib="$BATS_TEST_TMPDIR/stale-lib"
    local runtime_acfs="$BATS_TEST_TMPDIR/runtime-acfs"
    local repo_root="$BATS_TEST_TMPDIR/repo"
    local log_file="$BATS_TEST_TMPDIR/update.log"

    mkdir -p "$stale_lib" "$runtime_acfs/scripts/lib" "$repo_root/scripts/lib"

    cat > "$stale_lib/stack.sh" <<'EOF'
#!/usr/bin/env bash
_stack_configure_agent_mail_service() { printf 'stale-config\n'; }
EOF

    cat > "$runtime_acfs/scripts/lib/stack.sh" <<'EOF'
#!/usr/bin/env bash
_stack_agent_mail_cli_path() { printf 'runtime-cli\n'; }
_stack_repair_agent_mail_cli_symlink() { printf 'runtime-symlink\n'; }
_stack_wait_for_agent_mail_health() { printf 'runtime-health\n'; }
EOF

    cat > "$repo_root/scripts/lib/stack.sh" <<'EOF'
#!/usr/bin/env bash
_stack_agent_mail_cli_path() { printf 'fresh-cli\n'; }
_stack_repair_agent_mail_cli_symlink() { printf 'fresh-symlink\n'; }
_stack_configure_agent_mail_service() { printf 'fresh-config\n'; }
_stack_wait_for_agent_mail_health() { printf 'fresh-health\n'; }
EOF

    SCRIPT_DIR="$stale_lib"
    ACFS_REPO_ROOT="$repo_root"
    UPDATE_LOG_FILE="$log_file"
    update_runtime_acfs_home() { printf '%s\n' "$runtime_acfs"; }

    update_source_stack_lib

    run _stack_agent_mail_cli_path
    assert_success
    assert_output "fresh-cli"

    run _stack_configure_agent_mail_service
    assert_success
    assert_output "fresh-config"

    run grep -F "Ignoring stack.sh from $stale_lib/stack.sh: missing Agent Mail service helpers" "$log_file"
    assert_success
}

@test "doctor_fix_source_stack_lib skips stale stack candidates missing Agent Mail helpers" {
    local doctor_fix="$PROJECT_ROOT/scripts/lib/doctor_fix.sh"
    local stale_lib="$BATS_TEST_TMPDIR/stale-lib"
    local runtime_acfs="$BATS_TEST_TMPDIR/runtime-acfs"
    local repo_root="$BATS_TEST_TMPDIR/repo"

    mkdir -p "$stale_lib" "$runtime_acfs/scripts/lib" "$repo_root/scripts/lib"

    cat > "$stale_lib/stack.sh" <<'EOF'
#!/usr/bin/env bash
_stack_configure_agent_mail_service() { printf 'stale-config\n'; }
EOF

    cat > "$runtime_acfs/scripts/lib/stack.sh" <<'EOF'
#!/usr/bin/env bash
_stack_agent_mail_cli_path() { printf 'runtime-cli\n'; }
_stack_repair_agent_mail_cli_symlink() { printf 'runtime-symlink\n'; }
_stack_wait_for_agent_mail_health() { printf 'runtime-health\n'; }
EOF

    cat > "$repo_root/scripts/lib/stack.sh" <<'EOF'
#!/usr/bin/env bash
_stack_agent_mail_cli_path() { printf 'fresh-cli\n'; }
_stack_repair_agent_mail_cli_symlink() { printf 'fresh-symlink\n'; }
_stack_configure_agent_mail_service() { printf 'fresh-config\n'; }
_stack_wait_for_agent_mail_health() { printf 'fresh-health\n'; }
EOF

    eval "$(sed -n '/^doctor_fix_stack_agent_mail_helpers_loaded()/,/^}$/p' "$doctor_fix")"
    eval "$(sed -n '/^doctor_fix_clear_stack_agent_mail_helpers()/,/^}$/p' "$doctor_fix")"
    eval "$(sed -n '/^doctor_fix_source_stack_lib()/,/^}$/p' "$doctor_fix")"

    SCRIPT_DIR="$stale_lib"
    ACFS_REPO_ROOT="$repo_root"
    doctor_fix_runtime_acfs_home() { printf '%s\n' "$runtime_acfs"; }

    doctor_fix_source_stack_lib

    run _stack_agent_mail_cli_path
    assert_success
    assert_output "fresh-cli"

    run _stack_configure_agent_mail_service
    assert_success
    assert_output "fresh-config"
}

@test "finalize keeps legacy runtime deployment after generated acfs phase" {
    local installer="$PROJECT_ROOT/install.sh"
    local block=""

    block="$(sed -n '/if acfs_use_generated_category "acfs"/,/^    # Copy tmux config/p' "$installer")"

    [[ "$block" == *'acfs_run_generated_category_phase "acfs" "10" || return 1'* ]]
    [[ "$block" == *'continuing legacy finalize for full runtime deployment parity'* ]]
    [[ "$block" != *$'\n        return 0'* ]]
}

@test "custom bin dir persists in state and nightly service PATH includes runtime bins" {
    local state_lib="$PROJECT_ROOT/scripts/lib/state.sh"
    local nightly="$PROJECT_ROOT/scripts/lib/nightly_update.sh"
    local service_template="$PROJECT_ROOT/scripts/templates/acfs-nightly-update.service"
    local global_wrapper="$PROJECT_ROOT/scripts/acfs-global"
    local update_wrapper="$PROJECT_ROOT/scripts/acfs-update"

    run grep -F 'bin_dir: $bin_dir,' "$state_lib"
    assert_success
    run grep -F '"bin_dir": "${ACFS_BIN_DIR:-$resolved_target_home/.local/bin}",' "$state_lib"
    assert_success

    run grep -F 'ACFS_BIN_DIR="$(read_bin_dir_from_state_file "$state_candidate" 2>/dev/null || true)"' "$nightly"
    assert_success
    run grep -F 'ACFS_BIN_DIR="$(sanitize_abs_nonroot_path "${ACFS_BIN_DIR:-}" 2>/dev/null || true)"' "$nightly"
    assert_success
    run grep -F '"$HOME/.acfs/bin/acfs-update"' "$nightly"
    assert_success
    run grep -F '%h/.acfs/bin:%h/.local/bin:%h/.cargo/bin:%h/.bun/bin:%h/.atuin/bin:%h/go/bin' "$service_template"
    assert_success

    run grep -F '[[ -n "$sanitized_bin_dir" ]] && env_args+=("ACFS_BIN_DIR=$sanitized_bin_dir")' "$global_wrapper"
    assert_success
    run grep -F '[[ -n "$sanitized_bin_dir" ]] && env_args+=("ACFS_BIN_DIR=$sanitized_bin_dir")' "$update_wrapper"
    assert_success
}

@test "nightly update only promotes state target homes with update entrypoint" {
    local nightly="$PROJECT_ROOT/scripts/lib/nightly_update.sh"
    local block=""

    block="$(sed -n '/if ! nightly_home_has_update_entrypoint "$state_target_home"; then/,/fi/p' "$nightly")"
    [[ "$block" == *'if ! nightly_home_has_update_entrypoint "$state_target_home"; then'* ]]
    [[ "$block" == *'continue'* ]]
}

@test "install execution helpers preserve ACFS bootstrap context" {
    local installer="$PROJECT_ROOT/install.sh"
    local install_helpers="$PROJECT_ROOT/scripts/lib/install_helpers.sh"

    for context_var in \
        ACFS_BOOTSTRAP_DIR \
        ACFS_LIB_DIR \
        ACFS_GENERATED_DIR \
        ACFS_ASSETS_DIR \
        ACFS_CHECKSUMS_YAML \
        ACFS_MANIFEST_YAML \
        CHECKSUMS_FILE \
        SCRIPT_DIR \
        ACFS_RAW \
        ACFS_VERSION \
        ACFS_REF
    do
        local expected="env_args+=(\"$context_var=\$$context_var\")"

        run grep -F "$expected" "$installer"
        assert_success

        run bash -c 'grep -F "$1" "$2" | wc -l' _ "$expected" "$install_helpers"
        assert_success
        [[ "$output" -ge 2 ]] || fail "Expected $context_var in both target and root helper env allowlists"
    done

    run grep -F 'export CHECKSUMS_FILE="${ACFS_CHECKSUMS_YAML:-${CHECKSUMS_FILE:-}}"' "$installer"
    assert_success
}

@test "install.sh target-home contexts repair stale TARGET_HOME from passwd" {
    local installer="$PROJECT_ROOT/install.sh"

    run grep -F 'local acfs_home_for_target=""' "$installer"
    assert_success

    run grep -F 'if [[ -n "$acfs_home_for_target" ]]; then env_args+=("ACFS_HOME=$acfs_home_for_target"); fi' "$installer"
    assert_success

    run grep -F 'resolved_target_home="$(acfs_home_for_user "$TARGET_USER" "$explicit_target_home" 2>/dev/null || true)"' "$installer"
    assert_success

    run grep -F 'resolved_target_home="$(acfs_home_for_user "${TARGET_USER:-ubuntu}" "$explicit_target_home" 2>/dev/null || true)"' "$installer"
    assert_success

    run grep -F 'TARGET_HOME="${TARGET_HOME%/}"' "$installer"
    assert_failure

    run grep -F 'resolved_target_home="${resolved_target_home%/}"' "$installer"
    assert_success

    run bash -c 'sed -n "/^acfs_summary_emit()/,/^}/p" "$1" | grep -F "[[ \"\$resolved_target_home\" == \"/\" ]]"' _ "$installer"
    assert_success

    run bash -c 'sed -n "/^acfs_summary_emit()/,/^}/p" "$1" | grep -F "local explicit_target_home=\"\""' _ "$installer"
    assert_success

    run bash -c 'sed -n "/^acfs_summary_emit()/,/^}/p" "$1" | grep -F "acfs_home_for_user \"\${TARGET_USER:-ubuntu}\" 2>/dev/null"' _ "$installer"
    assert_failure

    run bash -c 'sed -n "/^init_target_paths()/,/^}/p" "$1" | grep -F "local explicit_target_home_raw=\"\${TARGET_HOME:-}\""' _ "$installer"
    assert_success

    run bash -c 'sed -n "/^init_target_paths()/,/^}/p" "$1" | grep -F "local explicit_target_home=\"\""' _ "$installer"
    assert_success

    run bash -c 'sed -n "/^init_target_paths()/,/^}/p" "$1" | grep -F "elif [[ -n \"\${TARGET_HOME:-}\" ]]; then"' _ "$installer"
    assert_failure

    run grep -F 'local explicit_user_home_for_repair=""' "$installer"
    assert_success

    run bash -c 'sed -n "/^init_target_paths()/,/^}/p" "$1" | grep -F "ACFS_BIN_DIR=\"\$TARGET_HOME/.local/bin\""' _ "$installer"
    assert_success

    run bash -c 'sed -n "/^init_target_paths()/,/^}/p" "$1" | grep -F "ACFS_HOME=\"\$TARGET_HOME/.acfs\""' _ "$installer"
    assert_success

    run bash -c 'sed -n "/^init_target_paths()/,/^}/p" "$1" | grep -F "ACFS_STATE_FILE=\"\$ACFS_HOME/state.json\""' _ "$installer"
    assert_success

    run bash -c 'sed -n "/^init_target_paths()/,/^}/p" "$1" | grep -F "if [[ -z \"\${TARGET_HOME:-}\" ]]; then"' _ "$installer"
    assert_failure

    run bash -c 'sed -n "/^acfs_summary_emit()/,/^}/p" "$1" | grep -F "local resolved_target_home=\"\${TARGET_HOME:-}\""' _ "$installer"
    assert_failure
}

@test "install_helpers run_as_target fails closed for unresolved target with stale TARGET_HOME" {
    local install_helpers="$PROJECT_ROOT/scripts/lib/install_helpers.sh"
    local stale_home

    stale_home="$(create_temp_dir)"
    # shellcheck source=scripts/lib/install_helpers.sh
    source "$install_helpers"

    export TARGET_USER="missinguser"
    export TARGET_HOME="$stale_home"
    export HOME="$stale_home"

    _acfs_getent_passwd_entry() {
        return 1
    }

    _acfs_resolve_current_user() {
        printf 'calleruser\n'
    }

    sudo() {
        printf 'sudo-called\n'
        return 0
    }

    runuser() {
        printf 'runuser-called\n'
        return 0
    }

    su() {
        printf 'su-called\n'
        return 0
    }

    run run_as_target true
    assert_failure
    refute_output --partial "sudo-called"
    refute_output --partial "runuser-called"
    refute_output --partial "su-called"
}

@test "install_helpers shell wrappers ignore poisoned env/bash and target PATH bash" {
    local install_helpers="$PROJECT_ROOT/scripts/lib/install_helpers.sh"
    local target_home
    local fake_env
    local fake_bash
    local marker

    target_home="$(create_temp_dir)"
    fake_env="$target_home/.local/bin/env"
    fake_bash="$target_home/.local/bin/bash"
    marker="$target_home/poisoned"
    mkdir -p "$(dirname "$fake_bash")"
    export TEST_INSTALL_HELPERS_TARGET_HOME="$target_home"
    export TEST_INSTALL_HELPERS_MARKER="$marker"

    cat > "$fake_env" <<'EOF'
#!/bin/sh
printf 'fake-env\n' > "$TEST_INSTALL_HELPERS_MARKER"
exit 99
EOF
    chmod +x "$fake_env"

    cat > "$fake_bash" <<'EOF'
#!/usr/bin/env bash
printf 'fake-bash\n' > "$TEST_INSTALL_HELPERS_MARKER"
exit 99
EOF
    chmod +x "$fake_bash"

    # shellcheck source=scripts/lib/install_helpers.sh
    source "$install_helpers"

    log_error() {
        printf '%s\n' "$*" >&2
    }

    _acfs_resolve_current_user() {
        printf 'calleruser\n'
    }

    _acfs_getent_passwd_entry() {
        if [[ "${1:-}" == "calleruser" ]]; then
            printf 'calleruser:x:1000:1000::%s:/bin/bash\n' "$TEST_INSTALL_HELPERS_TARGET_HOME"
            return 0
        fi
        return 1
    }

    env() {
        printf 'env\n' > "$TEST_INSTALL_HELPERS_MARKER"
        return 99
    }
    bash() {
        printf 'bash\n' > "$TEST_INSTALL_HELPERS_MARKER"
        return 99
    }
    sh() {
        printf 'sh\n' > "$TEST_INSTALL_HELPERS_MARKER"
        return 99
    }

    export TARGET_USER="calleruser"
    export TARGET_HOME="$target_home"
    export HOME="$target_home"
    export ACFS_BIN_DIR="$target_home/.local/bin"
    export PATH="$target_home/.local/bin:$PATH"

    run run_as_current_shell 'printf current'
    assert_success
    assert_output "current"
    [[ ! -e "$marker" ]] || fail "function or PATH-poisoned helper executed: $(<"$marker")"

    run run_as_target_shell 'printf target'
    assert_success
    assert_output "target"
    [[ ! -e "$marker" ]] || fail "function or PATH-poisoned helper executed: $(<"$marker")"

    run run_as_target env TEST_INSTALL_HELPERS_FLAG=ok bash -c 'printf "%s" "$TEST_INSTALL_HELPERS_FLAG"'
    assert_success
    assert_output "ok"
    [[ ! -e "$marker" ]] || fail "function or PATH-poisoned helper executed: $(<"$marker")"
}

@test "install_helpers run_as_target ignores function-poisoned privilege helpers" {
    local install_helpers="$PROJECT_ROOT/scripts/lib/install_helpers.sh"
    local target_home
    local safe_sudo
    local env_bin
    local bash_bin
    local sh_bin
    local marker

    target_home="$(create_temp_dir)"
    safe_sudo="$target_home/safe-sudo"
    marker="$target_home/poisoned"
    env_bin="$(command -v env)"
    bash_bin="$(command -v bash)"
    sh_bin="$(command -v sh)"
    mkdir -p "$target_home/.local/bin"
    export TEST_INSTALL_HELPERS_TARGET_HOME="$target_home"
    export TEST_INSTALL_HELPERS_SAFE_SUDO="$safe_sudo"
    export TEST_INSTALL_HELPERS_ENV_BIN="$env_bin"
    export TEST_INSTALL_HELPERS_BASH_BIN="$bash_bin"
    export TEST_INSTALL_HELPERS_SH_BIN="$sh_bin"
    export TEST_INSTALL_HELPERS_MARKER="$marker"

    cat > "$safe_sudo" <<'EOF'
#!/usr/bin/env bash
printf 'safe-sudo:%s\n' "$*"
EOF
    chmod +x "$safe_sudo"

    # shellcheck source=scripts/lib/install_helpers.sh
    source "$install_helpers"

    log_error() {
        printf '%s\n' "$*" >&2
    }

    _acfs_resolve_current_user() {
        printf 'calleruser\n'
    }

    _acfs_getent_passwd_entry() {
        if [[ "${1:-}" == "acfsuser" ]]; then
            printf 'acfsuser:x:1000:1000::%s:/bin/bash\n' "$TEST_INSTALL_HELPERS_TARGET_HOME"
            return 0
        fi
        return 1
    }

    _acfs_system_binary_path() {
        case "${1:-}" in
            env) printf '%s\n' "$TEST_INSTALL_HELPERS_ENV_BIN" ;;
            bash) printf '%s\n' "$TEST_INSTALL_HELPERS_BASH_BIN" ;;
            sh) printf '%s\n' "$TEST_INSTALL_HELPERS_SH_BIN" ;;
            sudo) printf '%s\n' "$TEST_INSTALL_HELPERS_SAFE_SUDO" ;;
            runuser|su) return 1 ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }

    env() {
        printf 'env\n' > "$TEST_INSTALL_HELPERS_MARKER"
        return 99
    }
    bash() {
        printf 'bash\n' > "$TEST_INSTALL_HELPERS_MARKER"
        return 99
    }
    sh() {
        printf 'sh\n' > "$TEST_INSTALL_HELPERS_MARKER"
        return 99
    }
    sudo() {
        printf 'sudo\n' > "$TEST_INSTALL_HELPERS_MARKER"
        return 99
    }
    runuser() {
        printf 'runuser\n' > "$TEST_INSTALL_HELPERS_MARKER"
        return 99
    }
    su() {
        printf 'su\n' > "$TEST_INSTALL_HELPERS_MARKER"
        return 99
    }

    export TARGET_USER="acfsuser"
    export TARGET_HOME="$target_home"
    export ACFS_BIN_DIR="$target_home/.local/bin"

    run run_as_target true
    assert_success
    assert_output --partial "safe-sudo:"
    [[ ! -e "$marker" ]] || fail "function-poisoned helper executed: $(<"$marker")"
}

@test "install.sh run_as_target normalizes env/bash infrastructure argv" {
    local installer="$PROJECT_ROOT/install.sh"
    local target_home
    local fake_env
    local fake_bash
    local marker
    local env_bin
    local bash_bin
    local sh_bin

    target_home="$(create_temp_dir)"
    fake_env="$target_home/.local/bin/env"
    fake_bash="$target_home/.local/bin/bash"
    marker="$target_home/poisoned"
    env_bin="$(command -v env)"
    bash_bin="$(command -v bash)"
    sh_bin="$(command -v sh)"
    mkdir -p "$(dirname "$fake_bash")"
    export TEST_INSTALL_SH_TARGET_HOME="$target_home"
    export TEST_INSTALL_SH_MARKER="$marker"
    export TEST_INSTALL_SH_ENV_BIN="$env_bin"
    export TEST_INSTALL_SH_BASH_BIN="$bash_bin"
    export TEST_INSTALL_SH_SH_BIN="$sh_bin"

    cat > "$fake_env" <<'EOF'
#!/bin/sh
printf 'fake-env\n' > "$TEST_INSTALL_SH_MARKER"
exit 99
EOF
    chmod +x "$fake_env"

    cat > "$fake_bash" <<'EOF'
#!/usr/bin/env bash
printf 'fake-bash\n' > "$TEST_INSTALL_SH_MARKER"
exit 99
EOF
    chmod +x "$fake_bash"

    eval "$(sed -n '/^run_as_target()/,/^}$/p' "$installer")"

    log_error() {
        printf '%s\n' "$*" >&2
    }

    acfs_early_system_binary_path() {
        case "${1:-}" in
            env) printf '%s\n' "$TEST_INSTALL_SH_ENV_BIN" ;;
            bash) printf '%s\n' "$TEST_INSTALL_SH_BASH_BIN" ;;
            sh) printf '%s\n' "$TEST_INSTALL_SH_SH_BIN" ;;
            sudo|runuser|su) return 1 ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }

    acfs_early_resolve_current_user() {
        printf 'calleruser\n'
    }

    acfs_early_getent_passwd_entry() {
        if [[ "${1:-}" == "calleruser" ]]; then
            printf 'calleruser:x:1000:1000::%s:/bin/bash\n' "$TEST_INSTALL_SH_TARGET_HOME"
            return 0
        fi
        return 1
    }

    acfs_home_for_user() {
        if [[ "${1:-}" == "calleruser" ]]; then
            printf '%s\n' "$TEST_INSTALL_SH_TARGET_HOME"
            return 0
        fi
        return 1
    }

    env() {
        printf 'env\n' > "$TEST_INSTALL_SH_MARKER"
        return 99
    }
    bash() {
        printf 'bash\n' > "$TEST_INSTALL_SH_MARKER"
        return 99
    }
    sh() {
        printf 'sh\n' > "$TEST_INSTALL_SH_MARKER"
        return 99
    }

    export TARGET_USER="calleruser"
    export TARGET_HOME="$target_home"
    export HOME="$target_home"
    export ACFS_BIN_DIR="$target_home/.local/bin"
    export PATH="$target_home/.local/bin:$PATH"

    run run_as_target bash -c 'printf direct'
    assert_success
    assert_output "direct"
    [[ ! -e "$marker" ]] || fail "function or PATH-poisoned helper executed: $(<"$marker")"

    run run_as_target env TEST_INSTALL_SH_FLAG=ok bash -c 'printf "%s" "$TEST_INSTALL_SH_FLAG"'
    assert_success
    assert_output "ok"
    [[ ! -e "$marker" ]] || fail "function or PATH-poisoned helper executed: $(<"$marker")"
}

@test "install.sh sudo resolver ignores bare SUDO and function-poisoned sudo" {
    local installer="$PROJECT_ROOT/install.sh"
    local safe_sudo
    local marker

    safe_sudo="$BATS_TEST_TMPDIR/safe-sudo"
    marker="$BATS_TEST_TMPDIR/poisoned"
    printf '#!/bin/sh\nexit 0\n' > "$safe_sudo"
    chmod +x "$safe_sudo"
    export TEST_INSTALL_SH_SAFE_SUDO="$safe_sudo"
    export TEST_INSTALL_SH_MARKER="$marker"
    export SUDO="sudo"

    eval "$(sed -n '/^acfs_early_sudo_binary_path()/,/^}/p' "$installer")"

    acfs_early_system_binary_path() {
        case "${1:-}" in
            sudo) printf '%s\n' "$TEST_INSTALL_SH_SAFE_SUDO" ;;
            *) return 1 ;;
        esac
    }

    sudo() {
        printf 'sudo\n' > "$TEST_INSTALL_SH_MARKER"
        return 99
    }

    run acfs_early_sudo_binary_path
    assert_success
    assert_output "$safe_sudo"
    [[ ! -e "$marker" ]] || fail "function-poisoned sudo executed: $(<"$marker")"
}

@test "install.sh install_asset_from_path uses resolved sudo and coreutils argv" {
    [[ $EUID -ne 0 ]] || skip "sudo branch requires non-root test user"

    local installer="$PROJECT_ROOT/install.sh"
    local src_path
    local parent_dir
    local dest_path
    local safe_sudo
    local sudo_log
    local marker
    local mkdir_bin
    local cp_bin

    src_path="$BATS_TEST_TMPDIR/source.txt"
    parent_dir="$BATS_TEST_TMPDIR/protected-parent"
    dest_path="$parent_dir/nested/dest.txt"
    safe_sudo="$BATS_TEST_TMPDIR/safe-sudo"
    sudo_log="$BATS_TEST_TMPDIR/sudo.log"
    marker="$BATS_TEST_TMPDIR/poisoned"
    mkdir_bin="$(command -v mkdir)"
    cp_bin="$(command -v cp)"

    printf 'payload\n' > "$src_path"
    mkdir -p "$parent_dir"
    chmod u-w "$parent_dir"
    trap 'chmod u+w "${TEST_INSTALL_SH_PARENT:-}" 2>/dev/null || true' RETURN

    export TEST_INSTALL_SH_PARENT="$parent_dir"
    export TEST_INSTALL_SH_SAFE_SUDO="$safe_sudo"
    export TEST_INSTALL_SH_SUDO_LOG="$sudo_log"
    export TEST_INSTALL_SH_MARKER="$marker"
    export TEST_INSTALL_SH_MKDIR_BIN="$mkdir_bin"
    export TEST_INSTALL_SH_CP_BIN="$cp_bin"

    cat > "$safe_sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_INSTALL_SH_SUDO_LOG"
case "${1:-}" in
    "$TEST_INSTALL_SH_MKDIR_BIN")
        shift
        chmod u+w "$TEST_INSTALL_SH_PARENT"
        "$TEST_INSTALL_SH_MKDIR_BIN" "$@"
        chmod u-w "$TEST_INSTALL_SH_PARENT"
        ;;
    "$TEST_INSTALL_SH_CP_BIN")
        shift
        "$TEST_INSTALL_SH_CP_BIN" "$@"
        ;;
    *)
        exit 97
        ;;
esac
EOF
    chmod +x "$safe_sudo"

    eval "$(sed -n '/^install_asset_from_path()/,/^}$/p' "$installer")"

    log_error() {
        printf '%s\n' "$*" >&2
    }

    acfs_early_sudo_binary_path() {
        printf '%s\n' "$TEST_INSTALL_SH_SAFE_SUDO"
    }

    acfs_early_system_binary_path() {
        case "${1:-}" in
            mkdir) printf '%s\n' "$TEST_INSTALL_SH_MKDIR_BIN" ;;
            cp) printf '%s\n' "$TEST_INSTALL_SH_CP_BIN" ;;
            *) command -v -- "${1:-}" 2>/dev/null || return 1 ;;
        esac
    }

    sudo() {
        printf 'sudo\n' > "$TEST_INSTALL_SH_MARKER"
        return 99
    }
    mkdir() {
        printf 'mkdir\n' > "$TEST_INSTALL_SH_MARKER"
        return 99
    }
    cp() {
        printf 'cp\n' > "$TEST_INSTALL_SH_MARKER"
        return 99
    }

    run install_asset_from_path "$src_path" "$dest_path"
    assert_success
    run cat "$dest_path"
    assert_success
    assert_output "payload"
    run grep -F "$safe_sudo" "$sudo_log"
    assert_failure
    run grep -F "$mkdir_bin -p $parent_dir/nested" "$sudo_log"
    assert_success
    run grep -F "$cp_bin $src_path $dest_path" "$sudo_log"
    assert_success
    [[ ! -e "$marker" ]] || fail "function-poisoned helper executed: $(<"$marker")"
}

@test "install.sh: target install checks avoid inherited PATH leaks" {
    local installer="$PROJECT_ROOT/install.sh"

    run grep -F 'binary_path() {' "$installer"
    assert_success

    run grep -F 'if ! binary_installed "zsh"; then' "$installer"
    assert_success

    run grep -F 'if ! binary_installed "go"; then' "$installer"
    assert_success

    run grep -F 'if binary_installed "uv"; then' "$installer"
    assert_success

    run grep -F 'if [[ -d "$TARGET_HOME/.atuin" ]] || binary_installed "atuin"; then' "$installer"
    assert_success

    run grep -F 'if binary_installed "zoxide"; then' "$installer"
    assert_success

    run grep -F 'if binary_installed "gum"; then' "$installer"
    assert_success

    run grep -F 'if binary_installed "gh"; then' "$installer"
    assert_success

    run grep -F 'if ! binary_installed "lazygit"; then' "$installer"
    assert_success

    run grep -F 'if ! binary_installed "lazydocker"; then' "$installer"
    assert_success

    run grep -F 'elif psql_bin="$(binary_path psql 2>/dev/null || true)" && [[ -n "$psql_bin" ]]; then' "$installer"
    assert_success

    run grep -F 'elif vault_bin="$(binary_path vault 2>/dev/null || true)" && [[ -n "$vault_bin" ]]; then' "$installer"
    assert_success

    run grep -F 'binary_installed "go" || missing_lang+=("go")' "$installer"
    assert_success

    run grep -F 'gh_bin="$(binary_path gh 2>/dev/null || true)"' "$installer"
    assert_success

    run grep -F 'psql_bin="$(binary_path psql 2>/dev/null || true)"' "$installer"
    assert_success

    run grep -F 'vault_bin="$(binary_path vault 2>/dev/null || true)"' "$installer"
    assert_success

    run grep -F 'export PATH="${ACFS_BIN_DIR:-$HOME/.local/bin}:$HOME/.local/bin:$HOME/.acfs/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:/snap/bin"' "$installer"
    assert_success

    run grep -F 'run_as_target env "ACFS_AGENT_MAIL_TARGET_DIR=$target_dir" bash -c' "$installer"
    assert_success

    run grep -F 'am_src="$ACFS_AGENT_MAIL_TARGET_DIR/am"' "$installer"
    assert_success

    run grep -F '"$am_bin" migrate >>"$fallback_log_file" 2>&1' "$installer"
    assert_success

    run grep -F '"$am_bin" serve-http --no-tui --host 127.0.0.1 --port 8765 --path "$am_mcp_path"' "$installer"
    assert_success

    run grep -F "if run_as_target bash -c 'set -euo pipefail" "$installer"
    assert_success

    run grep -F 'if ! command_exists zsh; then' "$installer"
    assert_failure

    run grep -F 'if ! command_exists go; then' "$installer"
    assert_failure

    run grep -F 'if command_exists gum; then' "$installer"
    assert_failure

    run grep -F 'if command_exists gh; then' "$installer"
    assert_failure

    run grep -F 'if ! command_exists lazygit; then' "$installer"
    assert_failure

    run grep -F 'if ! command_exists lazydocker; then' "$installer"
    assert_failure

    run grep -F 'elif command_exists psql; then' "$installer"
    assert_failure

    run grep -F 'elif command_exists vault; then' "$installer"
    assert_failure

    run grep -F 'command_exists go || missing_lang+=("go")' "$installer"
    assert_failure

    run grep -F "$(gh --version 2>/dev/null | head -1 || echo 'gh')" "$installer"
    assert_failure

    run grep -F "$(psql --version 2>/dev/null | head -1 || echo 'psql')" "$installer"
    assert_failure

    run grep -F "$(vault --version 2>/dev/null | head -1 || echo 'vault')" "$installer"
    assert_failure

    run grep -F 'command -v uv &>/dev/null' "$installer"
    assert_failure

    run grep -F 'command -v atuin &>/dev/null' "$installer"
    assert_failure

    run grep -F 'command -v zoxide &>/dev/null' "$installer"
    assert_failure
}

@test "install.sh: run_as_target same-user branch confines cd to subshell" {
    local installer="$PROJECT_ROOT/install.sh"

    run bash -c 'sed -n "/^run_as_target()/,/^}/p" "$1" | grep -E "^        \\($"' _ "$installer"
    assert_success

    run bash -c 'sed -n "/^run_as_target()/,/^}/p" "$1" | grep -F "            if ! cd \"\$user_home\"; then"' _ "$installer"
    assert_success

    run bash -c 'sed -n "/^run_as_target()/,/^}/p" "$1" | grep -F "            \"\$env_bin\" \"\${env_args[@]}\" \"\${command_argv[@]}\""' _ "$installer"
    assert_success

    run bash -c 'sed -n "/^run_as_target()/,/^}/p" "$1" | grep -E "^        if ! cd \"\\$user_home\"; then$"' _ "$installer"
    assert_failure

    run bash -c 'sed -n "/^run_as_target()/,/^}/p" "$1" | grep -E "^        \"\\$env_bin\" \"\\$\\{env_args\\[@\\]\\}\" \"\\$\\{command_argv\\[@\\]\\}\"$"' _ "$installer"
    assert_failure
}

@test "install.sh: Gemini trusted folders creation JSON-escapes target home" {
    local installer="$PROJECT_ROOT/install.sh"

    run grep -F 'jq -n --arg home "$1"' "$installer"
    assert_success

    run grep -F '{"/data/projects": "TRUST_FOLDER", ($home): "TRUST_FOLDER"}' "$installer"
    assert_success

    run grep -F '{"/data/projects": "TRUST_FOLDER", "$TARGET_HOME": "TRUST_FOLDER"}' "$installer"
    assert_failure
}

@test "install.sh: DCG hook installer passes target paths as argv/env data" {
    local installer="$PROJECT_ROOT/install.sh"
    local try_step_line="try_step \"Installing DCG hook\" \\"
    local env_line="env \"TARGET_USER=\$TARGET_USER\" \"TARGET_HOME=\$TARGET_HOME\" \\"

    run grep -F "$try_step_line" "$installer"
    assert_success

    run grep -F "$env_line" "$installer"
    assert_success

    run grep -F '"$ACFS_HOME/scripts/services-setup.sh" --install-claude-guard --yes' "$installer"
    assert_success

    run grep -F 'try_step_eval "Installing DCG hook"' "$installer"
    assert_failure

    run grep -F "TARGET_USER='\$TARGET_USER' TARGET_HOME='\$TARGET_HOME'" "$installer"
    assert_failure
}

@test "install.sh: resolves target user and shell via trusted helpers" {
    local installer="$PROJECT_ROOT/install.sh"

    run grep -F '_ACFS_DETECTED_USER="$(acfs_early_resolve_current_user 2>/dev/null || true)"' "$installer"
    assert_success

    run grep -F 'passwd_entry="$(acfs_early_getent_passwd_entry "$user" 2>/dev/null || true)"' "$installer"
    assert_success

    run grep -F 'current_user="$(acfs_early_resolve_current_user 2>/dev/null || true)"' "$installer"
    assert_success

    run grep -F 'current_shell_entry="$(acfs_early_getent_passwd_entry "$TARGET_USER" 2>/dev/null || true)"' "$installer"
    assert_success

    run grep -F '$SUDO "$chsh_path" -s "$zsh_path" "$TARGET_USER"' "$installer"
    assert_success

    run grep -F '_ACFS_DETECTED_USER="${SUDO_USER:-$(whoami)}"' "$installer"
    assert_failure

    run grep -F 'passwd_entry="$(getent passwd "$user" 2>/dev/null || true)"' "$installer"
    assert_failure

    run grep -F 'current_shell=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f7 || true)' "$installer"
    assert_failure
}

@test "install.sh: current HOME fallback cannot override explicit TARGET_HOME" {
    local installer="$PROJECT_ROOT/install.sh"
    local current_home
    local target_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"

    eval "$(sed -n '/^acfs_home_for_user()/,/^}$/p' "$installer")"

    acfs_early_getent_passwd_entry() {
        return 1
    }

    acfs_early_resolve_current_user() {
        printf 'acfstestuser\n'
    }

    export HOME="$current_home"

    run acfs_home_for_user "acfstestuser" "$target_home"
    assert_failure

    run acfs_home_for_user "acfstestuser" "$current_home"
    assert_success
    assert_output "$current_home"

    run acfs_home_for_user "acfstestuser"
    assert_success
    assert_output "$current_home"
}

@test "packages/manifest generator emits trusted passwd and identity helpers" {
    local generator="$PROJECT_ROOT/packages/manifest/src/generate.ts"

    run grep -F 'acfs_generated_getent_passwd_entry() {' "$generator"
    assert_success

    run grep -F 'acfs_generated_passwd_home_from_entry() {' "$generator"
    assert_success

    run grep -F '_ACFS_DETECTED_USER="\${SUDO_USER:-\$(whoami)}"' "$generator"
    assert_failure

    run grep -F 'cut -d: -f6' "$generator"
    assert_failure

    run grep -F 'current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"' "$generator"
    assert_success
}

@test "packages/manifest generator preserves explicit TARGET_HOME against stale HOME fallback" {
    local generator="$PROJECT_ROOT/packages/manifest/src/generate.ts"

    run grep -F '_ACFS_EXPLICIT_TARGET_HOME="\${TARGET_HOME:-}"' "$generator"
    assert_success

    run grep -F '_ACFS_RESOLVED_TARGET_HOME="\$(_acfs_resolve_target_home "\${TARGET_USER}" "\$_ACFS_EXPLICIT_TARGET_HOME" || true)"' "$generator"
    assert_success

    run grep -F '{ [[ -z "\$_ACFS_EXPLICIT_TARGET_HOME" ]] || [[ "\$_acfs_current_home" == "\$_ACFS_EXPLICIT_TARGET_HOME" ]]; }' "$generator"
    assert_success

    run grep -F 'explicit_target_home="$target_home"' "$generator"
    assert_success

    run grep -F 'resolved_target_home="$(_acfs_resolve_target_home "$target_user" "$explicit_target_home" || true)"' "$generator"
    assert_success

    run grep -F 'target_home="$explicit_target_home"' "$generator"
    assert_failure

    run grep -F '{ [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }' "$generator"
    assert_success
}

@test "acfs.manifest inline shell blocks use trusted passwd and identity helpers" {
    local manifest="$PROJECT_ROOT/acfs.manifest.yaml"

    run grep -F 'acfs_generated_getent_passwd_entry "${TARGET_USER:-ubuntu}"' "$manifest"
    assert_success

    run grep -F 'acfs_generated_passwd_home_from_entry "$_acfs_passwd_entry"' "$manifest"
    assert_success

    run grep -F 'current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"' "$manifest"
    assert_success

    run grep -F '_acfs_passwd_entry="$(getent passwd "${TARGET_USER:-ubuntu}" 2>/dev/null || true)"' "$manifest"
    assert_failure

    run grep -F 'target_home="$(printf '\''%s\n'\'' "$_acfs_passwd_entry" | cut -d: -f6)"' "$manifest"
    assert_failure

    run grep -F 'passwd_entry="$(getent passwd "$(whoami)" 2>/dev/null || true)"' "$manifest"
    assert_failure

    run grep -F 'sudo chsh -s "$zsh_path" "$(whoami)"' "$manifest"
    assert_failure
}

@test "acfs.manifest inline shell blocks preserve explicit TARGET_HOME against stale HOME fallback" {
    local manifest="$PROJECT_ROOT/acfs.manifest.yaml"

    run grep -F 'explicit_target_home="${TARGET_HOME:-}"' "$manifest"
    assert_success

    run grep -F '{ [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }' "$manifest"
    assert_success

    run grep -F 'target_home="$current_home"' "$manifest"
    assert_success

    run grep -F 'target_home="${HOME%/}"' "$manifest"
    assert_failure
}

@test "install.sh: binary_path ignores current-shell-only PATH entries" {
    local installer="$PROJECT_ROOT/install.sh"

    init_stub_dir

    # shellcheck disable=SC1090
    eval "$(sed -n '/^binary_path()/,/^}$/p' "$installer")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^binary_installed()/,/^}$/p' "$installer")"

    export TARGET_HOME="$HOME/target-home"
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$ACFS_BIN_DIR"

    cat > "$STUB_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
echo "current-shell-only-tool"
EOF
    chmod +x "$STUB_DIR/current-shell-only-tool"
    export PATH="$STUB_DIR:/usr/bin:/bin"

    run binary_path "current-shell-only-tool"
    assert_failure

    cat > "$ACFS_BIN_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
echo "target-local-tool"
EOF
    chmod +x "$ACFS_BIN_DIR/current-shell-only-tool"

    run binary_path "current-shell-only-tool"
    assert_success
    assert_output "$ACFS_BIN_DIR/current-shell-only-tool"

    run binary_installed "current-shell-only-tool"
    assert_success
}

@test "install.sh: smoke helper ignores current-shell-only PATH entries" {
    local installer="$PROJECT_ROOT/install.sh"

    init_stub_dir

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_smoke_target_path()/,/^}$/p' "$installer")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_smoke_run_as_target()/,/^}$/p' "$installer")"

    export TARGET_USER="tester"
    export TARGET_HOME="$HOME/target-home"
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$ACFS_BIN_DIR"

    cat > "$STUB_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
echo "current-shell-only-tool"
EOF
    chmod +x "$STUB_DIR/current-shell-only-tool"
    export PATH="$STUB_DIR:/usr/bin:/bin"

    run_as_target() {
        "$@"
    }

    run _smoke_run_as_target "command -v current-shell-only-tool >/dev/null && current-shell-only-tool --help >/dev/null 2>&1"
    assert_failure

    cat > "$ACFS_BIN_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--help" ]]; then
  exit 0
fi
exit 0
EOF
    chmod +x "$ACFS_BIN_DIR/current-shell-only-tool"

    run _smoke_run_as_target "command -v current-shell-only-tool >/dev/null && current-shell-only-tool --help >/dev/null 2>&1"
    assert_success
}

@test "smoke_test.sh: binary helper ignores current-shell-only PATH entries" {
    local smoke="$PROJECT_ROOT/scripts/lib/smoke_test.sh"

    init_stub_dir

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_smoke_preferred_bin_dir()/,/^}$/p' "$smoke")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_smoke_binary_path()/,/^}$/p' "$smoke")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_smoke_binary_exists()/,/^}$/p' "$smoke")"

    export TARGET_HOME="$HOME/target-home"
    export _SMOKE_TARGET_HOME="$TARGET_HOME"
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$ACFS_BIN_DIR"

    cat > "$STUB_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
echo "current-shell-only-tool"
EOF
    chmod +x "$STUB_DIR/current-shell-only-tool"
    export PATH="$STUB_DIR:/usr/bin:/bin"

    run _smoke_binary_path "current-shell-only-tool"
    assert_failure

    run _smoke_binary_exists "current-shell-only-tool"
    assert_failure

    cat > "$ACFS_BIN_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
echo "target-local-tool"
EOF
    chmod +x "$ACFS_BIN_DIR/current-shell-only-tool"

    run _smoke_binary_path "current-shell-only-tool"
    assert_success
    assert_output "$ACFS_BIN_DIR/current-shell-only-tool"

    run _smoke_binary_exists "current-shell-only-tool"
    assert_success
}

@test "cheatsheet.sh: prepend_user_paths prefers ACFS bin and skips missing dirs" {
    local cheatsheet="$PROJECT_ROOT/scripts/lib/cheatsheet.sh"
    local test_home
    local expected_path=""

    test_home="$(create_temp_dir)"
    mkdir -p "$test_home/custom-bin" "$test_home/.acfs/bin" "$test_home/google-cloud-sdk/bin"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^cheatsheet_sanitize_abs_nonroot_path()/,/^}$/p' "$cheatsheet")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^cheatsheet_prepend_user_paths()/,/^}$/p' "$cheatsheet")"

    export ACFS_BIN_DIR="$test_home/custom-bin"
    PATH="/usr/bin:/bin"
    cheatsheet_prepend_user_paths "$test_home"

    expected_path="$test_home/custom-bin:$test_home/.acfs/bin:$test_home/google-cloud-sdk/bin:/usr/bin:/bin"
    [ "$PATH" = "$expected_path" ]
}

@test "cheatsheet.sh: parse_zshrc sees tools installed only in ACFS bins" {
    local cheatsheet="$PROJECT_ROOT/scripts/lib/cheatsheet.sh"
    local test_home
    local zshrc

    test_home="$(create_temp_dir)"
    zshrc="$test_home/acfs.zshrc"
    mkdir -p "$test_home/.acfs/bin" "$test_home/google-cloud-sdk/bin"

    cat > "$test_home/.acfs/bin/am" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$test_home/google-cloud-sdk/bin/gcloud" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$test_home/.acfs/bin/am" "$test_home/google-cloud-sdk/bin/gcloud"

    cat > "$zshrc" <<'EOF'
# --- Agents ---
command -v am &>/dev/null && alias amserve='am serve-http'
command -v gcloud &>/dev/null && alias gbq='gcloud bq'
EOF

    # shellcheck disable=SC1090
    eval "$(sed -n '/^cheatsheet_sanitize_abs_nonroot_path()/,/^}$/p' "$cheatsheet")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^cheatsheet_prepend_user_paths()/,/^}$/p' "$cheatsheet")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^normalize_category()/,/^}$/p' "$cheatsheet")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^infer_category()/,/^}$/p' "$cheatsheet")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^cheatsheet_parse_zshrc()/,/^}$/p' "$cheatsheet")"

    export ACFS_BIN_DIR=""
    export CHEATSHEET_DELIM=$'	'
    PATH="/usr/bin:/bin"
    cheatsheet_prepend_user_paths "$test_home"

    run cheatsheet_parse_zshrc "$zshrc"

    assert_success
    assert_output --partial $'Agents	amserve	am serve-http	alias'
    assert_output --partial $'gbq	gcloud bq	alias'
}

@test "info.sh: prepend_user_paths preserves primary bin priority" {
    local info_lib="$PROJECT_ROOT/scripts/lib/info.sh"
    local test_home
    local expected_path=""

    test_home="$(create_temp_dir)"
    mkdir -p "$test_home/custom-bin" "$test_home/.acfs/bin" "$test_home/google-cloud-sdk/bin"

    info_preferred_bin_dir() { printf '%s\n' "$ACFS_BIN_DIR"; }
    # shellcheck disable=SC1090
    eval "$(sed -n '/^info_prepend_user_paths()/,/^}$/p' "$info_lib")"

    export ACFS_BIN_DIR="$test_home/custom-bin"
    PATH="/usr/bin:/bin"
    info_prepend_user_paths "$test_home"

    expected_path="$test_home/custom-bin:$test_home/.acfs/bin:$test_home/google-cloud-sdk/bin:/usr/bin:/bin"
    [ "$PATH" = "$expected_path" ]
}

@test "status.sh: prepend_user_paths preserves primary bin priority" {
    local status_lib="$PROJECT_ROOT/scripts/lib/status.sh"
    local test_home
    local expected_path=""

    test_home="$(create_temp_dir)"
    mkdir -p "$test_home/custom-bin" "$test_home/.acfs/bin" "$test_home/google-cloud-sdk/bin"

    _status_preferred_bin_dir() { printf '%s\n' "$ACFS_BIN_DIR"; }
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_status_prepend_user_paths()/,/^}$/p' "$status_lib")"

    export ACFS_BIN_DIR="$test_home/custom-bin"
    PATH="/usr/bin:/bin"
    _status_prepend_user_paths "$test_home"

    expected_path="$test_home/custom-bin:$test_home/.acfs/bin:$test_home/google-cloud-sdk/bin:/usr/bin:/bin"
    [ "$PATH" = "$expected_path" ]
}

@test "export-config.sh: augment_path_for_target_user preserves primary bin priority" {
    local export_config="$PROJECT_ROOT/scripts/lib/export-config.sh"
    local test_home
    local expected_path=""

    test_home="$(create_temp_dir)"
    mkdir -p "$test_home/custom-bin" "$test_home/.acfs/bin" "$test_home/google-cloud-sdk/bin"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^augment_path_for_target_user()/,/^}$/p' "$export_config")"

    export TARGET_HOME="$test_home"
    export ACFS_BIN_DIR="$test_home/custom-bin"
    PATH="/usr/bin:/bin"
    augment_path_for_target_user

    expected_path="$test_home/custom-bin:$test_home/.acfs/bin:$test_home/google-cloud-sdk/bin:/usr/bin:/bin"
    [ "$PATH" = "$expected_path" ]
}

@test "smoke_test.sh: prepend_user_paths preserves primary bin priority" {
    local smoke_lib="$PROJECT_ROOT/scripts/lib/smoke_test.sh"
    local test_home
    local expected_path=""

    test_home="$(create_temp_dir)"
    mkdir -p "$test_home/custom-bin" "$test_home/.acfs/bin" "$test_home/google-cloud-sdk/bin"

    _smoke_preferred_bin_dir() { printf '%s\n' "$ACFS_BIN_DIR"; }
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_smoke_prepend_user_paths()/,/^}$/p' "$smoke_lib")"

    export ACFS_BIN_DIR="$test_home/custom-bin"
    PATH="/usr/bin:/bin"
    _smoke_prepend_user_paths "$test_home"

    expected_path="$test_home/custom-bin:$test_home/.acfs/bin:$test_home/google-cloud-sdk/bin:/usr/bin:/bin"
    [ "$PATH" = "$expected_path" ]
}

@test "info.sh: binary helper ignores current-shell-only PATH entries" {
    local info_lib="$PROJECT_ROOT/scripts/lib/info.sh"

    init_stub_dir

    # shellcheck disable=SC1090
    eval "$(sed -n '/^info_binary_path()/,/^}$/p' "$info_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^info_binary_exists()/,/^}$/p' "$info_lib")"

    export TARGET_HOME="$HOME/target-home"
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$ACFS_BIN_DIR"

    cat > "$STUB_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
echo "current-shell-only-tool"
EOF
    chmod +x "$STUB_DIR/current-shell-only-tool"
    export PATH="$STUB_DIR:/usr/bin:/bin"

    run info_binary_path "current-shell-only-tool"
    assert_failure

    run info_binary_exists "current-shell-only-tool"
    assert_failure

    cat > "$ACFS_BIN_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
echo "target-local-tool"
EOF
    chmod +x "$ACFS_BIN_DIR/current-shell-only-tool"

    run info_binary_path "current-shell-only-tool"
    assert_success
    assert_output "$ACFS_BIN_DIR/current-shell-only-tool"

    run info_binary_exists "current-shell-only-tool"
    assert_success
}

@test "update.sh: ensure_path dedupes primary bin and restores system PATH when empty" {
    local update="$PROJECT_ROOT/scripts/lib/update.sh"
    local test_home="$BATS_TEST_TMPDIR/update-home"
    local expected_path=""
    mkdir -p "$test_home/.local/bin" "$test_home/.acfs/bin" "$test_home/google-cloud-sdk/bin"

    run env -u TARGET_HOME -u ACFS_BIN_DIR HOME="$test_home" PATH="/usr/bin:/bin" bash -c 'source "$1"; ACFS_BIN_DIR=""; PATH=""; ensure_path; printf "%s\n" "$PATH"' _ "$update"
    assert_success

    expected_path="$test_home/.local/bin:$test_home/.acfs/bin:$test_home/google-cloud-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
    [ "$output" = "$expected_path" ]
}

@test "update.sh: ensure_path ignores relative ACFS_BIN_DIR when PATH is empty" {
    local update="$PROJECT_ROOT/scripts/lib/update.sh"
    local test_home="$BATS_TEST_TMPDIR/update-home-relative"
    local cwd="$BATS_TEST_TMPDIR/update-relative-cwd"
    local expected_path=""
    mkdir -p "$test_home/.local/bin" "$test_home/.acfs/bin" "$test_home/google-cloud-sdk/bin" "$cwd/relative/bin"

    run env -u TARGET_HOME -u ACFS_BIN_DIR HOME="$test_home" PATH="/usr/bin:/bin" bash -c 'cd "$3"; source "$1"; ACFS_BIN_DIR="relative/bin"; PATH=""; ensure_path; printf "%s\n" "$PATH"' _ "$update" unused "$cwd"
    assert_success

    expected_path="$test_home/.local/bin:$test_home/.acfs/bin:$test_home/google-cloud-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
    [ "$output" = "$expected_path" ]
}

@test "doctor.sh: defaults ACFS_SYSTEM_STATE_FILE to system state path" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local test_home

    test_home="$(create_temp_dir)"
    mkdir -p "$test_home"

    unset TARGET_USER TARGET_HOME ACFS_HOME ACFS_STATE_FILE ACFS_SYSTEM_STATE_FILE ACFS_BIN_DIR
    export HOME="$test_home"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_sanitize_abs_nonroot_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_system_binary_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_resolve_current_user()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_getent_passwd_entry()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_passwd_home_from_entry()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_resolve_current_home()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_current_home="\$(_acfs_doctor_resolve_current_home/,/^export TARGET_HOME ACFS_HOME ACFS_STATE_FILE ACFS_SYSTEM_STATE_FILE ACFS_BIN_DIR$/p' "$doctor_lib")"

    [[ "$ACFS_SYSTEM_STATE_FILE" == "/var/lib/acfs/state.json" ]]
}

@test "doctor.sh: Vault config check requires active VAULT_ADDR assignment" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local test_home
    local zshrc_local

    doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    test_home="$(create_temp_dir)"
    zshrc_local="$test_home/.zshrc.local"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_shell_has_active_assignment()/,/^}$/p' "$doctor_lib")"

    cat > "$zshrc_local" <<'EOF'
# export VAULT_ADDR="https://vault.example"
alias keep_me="true"
EOF
    run _acfs_doctor_shell_has_active_assignment "$zshrc_local" "VAULT_ADDR"
    assert_failure

    cat > "$zshrc_local" <<'EOF'
export VAULT_ADDR=""
EOF
    run _acfs_doctor_shell_has_active_assignment "$zshrc_local" "VAULT_ADDR"
    assert_failure

    cat > "$zshrc_local" <<'EOF'
  export VAULT_ADDR="https://vault.example"
EOF
    run _acfs_doctor_shell_has_active_assignment "$zshrc_local" "VAULT_ADDR"
    assert_success
}

@test "shell auth helpers reject placeholder tokens" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local services_setup="$PROJECT_ROOT/scripts/services-setup.sh"
    local agents_lib="$PROJECT_ROOT/scripts/lib/agents.sh"
    local auth_file="$BATS_TEST_TMPDIR/auth.json"
    local env_file="$BATS_TEST_TMPDIR/auth.env"

    cat > "$auth_file" <<'JSON'
{
  "token": "your-token-here",
  "accessToken": "your_token_here"
}
JSON

    # shellcheck disable=SC1090
    eval "$(sed -n '/^normalize_config_value()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^is_placeholder_secret()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^has_usable_secret()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^json_file_has_usable_jq_value()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^json_file_has_usable_string_key()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^strip_shell_inline_comment()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^read_configured_var_from_file()/,/^}$/p' "$doctor_lib")"

    run has_usable_secret "your-token-here"
    assert_failure
    run json_file_has_usable_string_key "$auth_file" "token" "accessToken"
    assert_failure
    if command -v jq >/dev/null 2>&1; then
        run json_file_has_usable_jq_value "$auth_file" '[.token, .accessToken] | .[]? | strings'
        assert_failure
    fi
    run has_usable_secret "your-gemini-api-key"
    assert_failure

    cat > "$env_file" <<'EOF'
GEMINI_API_KEY="YOUR_GEMINI_API_KEY" # replace me
EOF
    run read_configured_var_from_file "GEMINI_API_KEY" "$env_file"
    assert_success
    assert_output "YOUR_GEMINI_API_KEY"
    local configured_value="$output"
    run has_usable_secret "$configured_value"
    assert_failure

    cat > "$env_file" <<'EOF'
GEMINI_API_KEY=real#hash
EOF
    run read_configured_var_from_file "GEMINI_API_KEY" "$env_file"
    assert_success
    assert_output "real#hash"

    cat > "$auth_file" <<'JSON'
{
  "token": "real-token"
}
JSON
    run json_file_has_usable_string_key "$auth_file" "token"
    assert_success

    # shellcheck disable=SC1090
    eval "$(sed -n '/^services_setup_normalize_config_value()/,/^}$/p' "$services_setup")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^services_setup_is_placeholder_secret()/,/^}$/p' "$services_setup")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^services_setup_has_usable_secret()/,/^}$/p' "$services_setup")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^json_file_has_usable_string_key()/,/^}$/p' "$services_setup")"

    run services_setup_has_usable_secret "your_vercel_token"
    assert_failure
    run json_file_has_usable_string_key "$auth_file" "token"
    assert_success

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_agent_normalize_config_value()/,/^}$/p' "$agents_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_agent_is_placeholder_secret()/,/^}$/p' "$agents_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_agent_has_usable_secret()/,/^}$/p' "$agents_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_agent_json_file_has_usable_string_key()/,/^}$/p' "$agents_lib")"

    run _agent_has_usable_secret "your_openai_api_key"
    assert_failure
    run _agent_json_file_has_usable_string_key "$auth_file" "token"
    assert_success
}

@test "doctor.sh cloud auth checks scan fallback files after placeholders" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local test_auth_home="$BATS_TEST_TMPDIR/auth-home"
    local supabase_primary="$test_auth_home/.supabase/access-token"
    local supabase_fallback="$test_auth_home/.config/supabase/access-token"
    local vercel_primary="$test_auth_home/.config/vercel/auth.json"
    local vercel_fallback="$test_auth_home/.vercel/auth.json"

    mkdir -p "$(dirname "$supabase_primary")" "$(dirname "$supabase_fallback")" \
        "$(dirname "$vercel_primary")" "$(dirname "$vercel_fallback")"
    printf '%s\n' 'your_supabase_access_token' > "$supabase_primary"
    printf '%s\n' 'real-supabase-credential' > "$supabase_fallback"
    printf '%s\n' '{"token":"your_vercel_token"}' > "$vercel_primary"
    printf '%s\n' '{"token":"real-vercel-credential"}' > "$vercel_fallback"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^normalize_config_value()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^is_placeholder_secret()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^has_usable_secret()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^json_file_has_usable_jq_value()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^json_file_has_usable_string_key()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^check_supabase_auth()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^check_vercel_auth()/,/^}$/p' "$doctor_lib")"

    doctor_runtime_home() { printf '%s\n' "$test_auth_home"; }
    doctor_binary_path() {
        case "${1:-}" in
            supabase|vercel) printf '/bin/true\n' ;;
            *) return 1 ;;
        esac
    }
    default_auth_config_files() { return 0; }
    get_configured_secret() { return 1; }
    get_cached_result() { return 1; }
    cache_result() { :; }
    run_with_timeout() { return 1; }
    check() { printf '%s=%s:%s\n' "$1" "$3" "$4"; }
    DEEP_CHECK_TIMEOUT=1

    run check_supabase_auth
    assert_success
    assert_output --partial "deep.cloud.supabase_auth=pass:access-token file present"

    run check_vercel_auth
    assert_success
    assert_output --partial "deep.cloud.vercel_auth=pass:auth file present"
}

@test "doctor.sh: Claude hook status requires real hook command entries" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local settings_file
    local pattern

    command -v jq >/dev/null 2>&1 || skip "jq required for Claude settings parsing"

    settings_file="$BATS_TEST_TMPDIR/claude-settings.json"
    pattern='(^|[[:space:]/])dcg([[:space:]]|$)'

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_claude_settings_has_command_hook()/,/^}$/p' "$doctor_lib")"

    cat > "$settings_file" <<'EOF'
{
  "notes": "dcg should be installed",
  "hooks": {
    "PreToolUse": []
  }
}
EOF
    run _acfs_doctor_claude_settings_has_command_hook "$settings_file" "$pattern"
    assert_failure

    cat > "$settings_file" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "type": "command",
        "command": "dcg guard --source claude"
      }
    ]
  }
}
EOF
    run _acfs_doctor_claude_settings_has_command_hook "$settings_file" "$pattern"
    assert_success

    cat > "$settings_file" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/home/ubuntu/.local/bin/dcg guard --source claude"
          }
        ]
      }
    ]
  }
}
EOF
    run _acfs_doctor_claude_settings_has_command_hook "$settings_file" "$pattern"
    assert_success
}

@test "stack hook checks do not accept raw settings text matches" {
    grep -q "_stack_claude_settings_has_command_hook()" "$PROJECT_ROOT/scripts/lib/stack.sh"
    grep -q "claude_settings_has_command_hook()" "$PROJECT_ROOT/scripts/services-setup.sh"

    run grep -q 'grep -q "claude-post-compact-reminder"' "$PROJECT_ROOT/scripts/lib/stack.sh"
    assert_failure

    run grep -q 'grep -q "dcg"' "$PROJECT_ROOT/scripts/services-setup.sh"
    assert_failure

    run grep -q 'grep -q "dcg" "\$settings"' "$PROJECT_ROOT/scripts/generated/install_stack.sh"
    assert_failure

    run grep -q 'grep -q "claude-post-compact-reminder" "\$settings"' "$PROJECT_ROOT/scripts/generated/install_stack.sh"
    assert_failure
}

@test "legacy stack RCH installer keeps daemon and fleet setup active" {
    run grep -F '_stack_run_installer "$tool" --easy-mode' "$PROJECT_ROOT/scripts/lib/stack.sh"
    assert_success
}

@test "stack FrankenSearch release resolution ignores shell function curl" {
    local stack_lib="$PROJECT_ROOT/scripts/lib/stack.sh"
    local curl_marker="${BATS_TEST_TMPDIR}/stack-curl-poison.marker"

    # shellcheck disable=SC1090
    source "$stack_lib"

    unset ACFS_FSFS_VERSION
    log_detail() { :; }
    curl() {
        : > "$curl_marker"
        return 42
    }
    _stack_system_curl() {
        case "$*" in
            *"releases?per_page=10"*)
                printf '%s\n' \
                    '    "tag_name": "v1.2.5",' \
                    '    "tag_name": "v1.2.4",'
                ;;
            *"v1.2.5"*.sha256*)
                return 22
                ;;
            *"v1.2.4"*.sha256*)
                printf '%s  %s\n' \
                    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" \
                    "fsfs-lite-1.2.4-x86_64-unknown-linux-musl.tar.xz"
                ;;
            *"releases/latest"*)
                printf '%s\n' "https://github.com/Dicklesworthstone/frankensearch/releases/tag/v1.2.5"
                ;;
            *)
                return 1
                ;;
        esac
    }

    run _stack_resolve_fsfs_artifact_contract "x86_64-unknown-linux-musl"

    assert_success
    assert_output --partial "v1.2.4"
    assert_output --partial "https://github.com/Dicklesworthstone/frankensearch/releases/download/v1.2.4/fsfs-lite-1.2.4-x86_64-unknown-linux-musl.tar.xz"
    assert_output --partial "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    [[ ! -e "$curl_marker" ]]
}

@test "stack Agent Mail target shell snippets use a local curl wrapper" {
    local stack_lib="$PROJECT_ROOT/scripts/lib/stack.sh"

    run grep -F 'stack_service_curl() {' "$stack_lib"
    assert_success

    run rg -n '(^|[[:space:]])curl -fsS --max-time 5 http://127\.0\.0\.1:8765/health' "$stack_lib"
    assert_failure

    run rg -n '(^|[[:space:]])_stack_curl -fsS --max-time 5 http://127\.0\.0\.1:8765/health' "$stack_lib"
    assert_failure
}

@test "Agent Mail installer health checks do not use bare curl" {
    local installer="$PROJECT_ROOT/install.sh"
    local manifest="$PROJECT_ROOT/acfs.manifest.yaml"
    local generated_stack="$PROJECT_ROOT/scripts/generated/install_stack.sh"

    run grep -F 'agent_mail_service_curl() {' "$installer"
    assert_success

    run grep -F 'agent_mail_service_curl() {' "$manifest"
    assert_success

    run grep -F 'agent_mail_service_curl() {' "$generated_stack"
    assert_success

    run rg -n '(^|[[:space:]])curl -fsS --max-time (5|10) http://127\.0\.0\.1:8765/health' "$installer" "$manifest" "$generated_stack"
    assert_failure
}

@test "stack verified installer command quotes inline env assignment values" {
    local stack_lib="$PROJECT_ROOT/scripts/lib/stack.sh"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_stack_run_verified_installer_with_env()/,/^}$/p' "$stack_lib")"

    declare -gA KNOWN_INSTALLERS=([test_tool]="https://example.test/install.sh")
    _stack_require_security() { return 0; }
    get_checksum() { printf '%s\n' "abc123"; }
    log_warn() { printf '%s\n' "$*" >&2; }
    _stack_run_as_user() { printf '%s\n' "$1"; }
    STACK_SCRIPT_DIR="/tmp/acfs stack's dir"

    run _stack_run_verified_installer_with_env "test_tool" "TEST_ENV=ok;touch /tmp/acfs-pwned" "--flag"
    assert_success
    assert_output --partial "TEST_ENV=ok\\;touch\\ /tmp/acfs-pwned"
    refute_output --partial "TEST_ENV=ok;touch /tmp/acfs-pwned"
    assert_output --partial "set -o pipefail; source /tmp/acfs\\ stack\\'s\\ dir/security.sh"
    assert_output --partial "bash -s -- --flag"
}

@test "stack verified installer command fails when checksum verifier fails" {
    local stack_lib="$PROJECT_ROOT/scripts/lib/stack.sh"
    local security_dir="$BATS_TEST_TMPDIR/stack-security"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_stack_run_verified_installer_with_env()/,/^}$/p' "$stack_lib")"

    mkdir -p "$security_dir"
    cat > "$security_dir/security.sh" <<'SECURITY'
verify_checksum() {
    return 1
}
SECURITY

    declare -gA KNOWN_INSTALLERS=([test_tool]="https://example.test/install.sh")
    _stack_require_security() { return 0; }
    get_checksum() { printf '%s\n' "abc123"; }
    log_warn() { printf '%s\n' "$*" >&2; }
    _stack_run_as_user() { bash -c "$1"; }
    STACK_SCRIPT_DIR="$security_dir"

    run _stack_run_verified_installer_with_env "test_tool" "" "--flag"
    assert_failure
}

@test "stack Agent Mail unit escapes dynamic systemd values" {
    local stack_lib="$PROJECT_ROOT/scripts/lib/stack.sh"

    run grep -F 'systemd_unit_path_escape() {' "$stack_lib"
    assert_success

    run grep -F 'value="${value//%/%%}"' "$stack_lib"
    assert_success

    run grep -F 'value="${value//\$/\$\$}"' "$stack_lib"
    assert_success

    run grep -Fx 'WorkingDirectory=$storage_root' "$stack_lib"
    assert_failure

    run grep -Fx 'WorkingDirectory=$storage_root_unit' "$stack_lib"
    assert_success

    run grep -Fx 'Environment=STORAGE_ROOT=$storage_root' "$stack_lib"
    assert_failure

    run grep -Fx 'Environment=$storage_root_env' "$stack_lib"
    assert_success

    run grep -F 'ExecStart=$am_bin serve-http' "$stack_lib"
    assert_failure

    run grep -F 'ExecStart=${am_bin_exec} serve-http' "$stack_lib"
    assert_success
}

@test "install.sh Agent Mail unit escapes dynamic systemd values" {
    local installer="$PROJECT_ROOT/install.sh"

    run grep -F 'systemd_unit_path_escape() {' "$installer"
    assert_success

    run grep -F 'value="${value//%/%%}"' "$installer"
    assert_success

    run grep -F 'value="${value//\$/\$\$}"' "$installer"
    assert_success

    run grep -Fx 'WorkingDirectory=$storage_root' "$installer"
    assert_failure

    run grep -Fx 'WorkingDirectory=$storage_root_unit' "$installer"
    assert_success

    run grep -Fx 'Environment=STORAGE_ROOT=$storage_root' "$installer"
    assert_failure

    run grep -Fx 'Environment=$storage_root_env' "$installer"
    assert_success

    run grep -F 'ExecStart=$am_bin serve-http' "$installer"
    assert_failure

    run grep -F 'ExecStart=${am_bin_exec} serve-http' "$installer"
    assert_success
}

@test "stack Agent Mail service accepts a healthy existing runtime" {
    local stack_lib="$PROJECT_ROOT/scripts/lib/stack.sh"

    run grep -F 'agent_mail_endpoint_ready() {' "$stack_lib"
    assert_success

    run grep -F 'if agent_mail_endpoint_ready && ! systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1; then' "$stack_lib"
    assert_success

    run grep -F 'systemctl --user reset-failed agent-mail.service >/dev/null 2>&1 || true' "$stack_lib"
    assert_success

    run grep -F 'healthy existing runtime detected; skipping managed service restart' "$stack_lib"
    assert_success
}

@test "update verified installer env assignment values are argv-safe data" {
    declare -gA KNOWN_INSTALLERS=([test_tool]="https://example.test/install.sh")

    update_require_security() { return 0; }
    get_checksum() { printf '%s\n' "abc123"; }
    verify_checksum() {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'exit 0'
    }
    update_run_in_target_context() {
        printf 'env=%s\n' "$1"
        printf 'cmd=%s\n' "$2"
        printf 'script=%s\n' "$3"
        printf 'arg=%s\n' "$4"
    }

    run update_run_verified_installer_with_env "test_tool" "TEST_ENV=ok; touch /tmp/acfs pwned" "--flag"
    assert_success
    assert_output --partial "env=TEST_ENV=ok; touch /tmp/acfs pwned"
    assert_output --partial "cmd=bash"
    assert_output --partial "arg=--flag"
}

@test "update verified installer rejects invalid env assignment names" {
    declare -gA KNOWN_INSTALLERS=([test_tool]="https://example.test/install.sh")

    update_require_security() { return 0; }
    get_checksum() { printf '%s\n' "abc123"; }

    run update_run_verified_installer_with_env "test_tool" "TEST-ENV=value" "--flag"
    assert_failure
    assert_output --partial "Invalid inline env assignment"
}

@test "update PCR installer uses install repair path and verifies doctor state" {
    local hook_script="$HOME/.local/bin/claude-post-compact-reminder"
    local call_log="$HOME/pcr-calls.log"

    update_run_verified_installer() {
        printf '%s\n' "$*" >> "$call_log"
        if [[ "$1" == "pcr" && "$2" == "--yes" ]]; then
            mkdir -p "$(dirname "$hook_script")"
            printf '#!/usr/bin/env bash\nexit 0\n' > "$hook_script"
            chmod +x "$hook_script"
            return 0
        fi
        if [[ "$1" == "pcr" && "$2" == "--doctor" && "$3" == "--json" ]]; then
            [[ -x "$hook_script" ]]
            return $?
        fi
        return 1
    }

    run update_run_pcr_installer_and_verify "$hook_script"
    assert_success

    run cat "$call_log"
    assert_success
    assert_output --partial "pcr --yes"
    assert_output --partial "pcr --doctor --json"
    refute_output --partial "pcr --update"
}

@test "update PCR installer fails if the hook is still missing after install" {
    local hook_script="$HOME/.local/bin/claude-post-compact-reminder"

    update_run_verified_installer() {
        return 0
    }

    run update_run_pcr_installer_and_verify "$hook_script"
    assert_failure
    assert_output --partial "PCR installer completed but hook is missing or not executable"
}

@test "update cargo git source installer delegates through target context" {
    update_run_in_target_context() {
        printf 'env=%s\n' "$1"
        printf 'cmd=%s\n' "$2"
        printf 'mode=%s\n' "$3"
        printf 'script=%s\n' "$4"
        printf 'sentinel=%s\n' "$5"
        printf 'repo=%s\n' "$6"
        printf 'binary=%s\n' "$7"
    }

    run update_run_cargo_git_source_install "https://example.test/tool.git" "tool-bin"
    assert_success
    assert_output --partial "env="
    assert_output --partial "cmd=bash"
    assert_output --partial "mode=-c"
    assert_output --partial "ACFS_UPDATE_TMPDIR"
    assert_output --partial "/data/tmp"
    assert_output --partial 'mktemp -d "$candidate/acfs_cargo_build.XXXXXX"'
    assert_output --partial "sentinel=_"
    assert_output --partial "repo=https://example.test/tool.git"
    assert_output --partial "binary=tool-bin"
}

@test "update fsfs installer uses Linux lite release artifact args" {
    update_fsfs_linux_target_triple() { printf '%s\n' "x86_64-unknown-linux-musl"; }
    update_resolve_fsfs_artifact_contract() {
        printf '%s\n%s\n%s\n' \
            "v1.2.5" \
            "https://github.com/Dicklesworthstone/frankensearch/releases/download/v1.2.5/fsfs-lite-1.2.5-x86_64-unknown-linux-musl.tar.xz" \
            "e82922dc1e3fad90e4b4fc145853f9c30b821c51ef4496a16b4f93d39da6b01a"
    }
    log_to_file() { :; }
    update_run_verified_installer() {
        printf 'arg=%s\n' "$@"
    }

    run update_run_fsfs_installer --easy-mode

    assert_success
    assert_output --partial "arg=fsfs"
    assert_output --partial "arg=--easy-mode"
    assert_output --partial "arg=--version"
    assert_output --partial "arg=v1.2.5"
    assert_output --partial "arg=--artifact-url"
    assert_output --partial "arg=https://github.com/Dicklesworthstone/frankensearch/releases/download/v1.2.5/fsfs-lite-1.2.5-x86_64-unknown-linux-musl.tar.xz"
    assert_output --partial "arg=--checksum"
    assert_output --partial "arg=e82922dc1e3fad90e4b4fc145853f9c30b821c51ef4496a16b4f93d39da6b01a"
}

@test "update fsfs artifact contract falls back when latest checksum is not ready" {
    unset ACFS_FSFS_VERSION
    log_to_file() { :; }
    update_curl() {
        case "$*" in
            *"releases?per_page=10"*)
                printf '%s\n' \
                    '    "tag_name": "v1.2.5",' \
                    '    "tag_name": "v1.2.4",'
                ;;
            *"v1.2.5"*.sha256*)
                return 22
                ;;
            *"v1.2.4"*.sha256*)
                printf '%s  %s\n' \
                    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" \
                    "fsfs-lite-1.2.4-x86_64-unknown-linux-musl.tar.xz"
                ;;
            *"releases/latest"*)
                printf '%s\n' "https://github.com/Dicklesworthstone/frankensearch/releases/tag/v1.2.5"
                ;;
            *)
                return 1
                ;;
        esac
    }

    run update_resolve_fsfs_artifact_contract "x86_64-unknown-linux-musl"

    assert_success
    assert_output --partial "v1.2.4"
    assert_output --partial "https://github.com/Dicklesworthstone/frankensearch/releases/download/v1.2.4/fsfs-lite-1.2.4-x86_64-unknown-linux-musl.tar.xz"
    assert_output --partial "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}

@test "update fsfs version resolver falls back to release redirect" {
    unset ACFS_FSFS_VERSION
    update_curl() {
        case "$*" in
            *api.github.com*) return 22 ;;
            *releases/latest*) printf '%s\n' "https://github.com/Dicklesworthstone/frankensearch/releases/tag/v1.2.5" ;;
            *) return 1 ;;
        esac
    }

    run update_resolve_fsfs_latest_version

    assert_success
    assert_output "v1.2.5"
}

@test "update fsfs version resolver rejects malformed override" {
    export ACFS_FSFS_VERSION="../v1.2.5"

    run update_resolve_fsfs_latest_version

    assert_failure
}

@test "agents verified installer commands shell-quote dynamic command parts" {
    local agents_lib="$PROJECT_ROOT/scripts/lib/agents.sh"

    run grep -F "source '\$AGENTS_SCRIPT_DIR/security.sh'; verify_checksum" "$agents_lib"
    assert_failure

    run grep -F "export PATH='\$node_bin_dir':" "$agents_lib"
    assert_failure

    run grep -F "printf -v security_lib_q '%q' \"\$AGENTS_SCRIPT_DIR/security.sh\"" "$agents_lib"
    assert_success
}

@test "installer shell command builders quote dynamic paths and installer inputs" {
    local agents_lib="$PROJECT_ROOT/scripts/lib/agents.sh"
    local languages_lib="$PROJECT_ROOT/scripts/lib/languages.sh"
    local cli_tools_lib="$PROJECT_ROOT/scripts/lib/cli_tools.sh"
    local cloud_db_lib="$PROJECT_ROOT/scripts/lib/cloud_db.sh"
    local stack_lib="$PROJECT_ROOT/scripts/lib/stack.sh"

    run grep -F "_agent_run_as_user \"mkdir -p '\$target_home/.local/bin'\"" "$agents_lib"
    assert_failure
    run grep -F "cat > '\$settings_file'" "$agents_lib"
    assert_failure
    run grep -F "mv '\$tmp_file' '\$settings_file'" "$agents_lib"
    assert_failure

    run grep -F "_lang_run_as_user \"source '\$LANG_SCRIPT_DIR/security.sh'; verify_checksum '\$url' '\$expected_sha256'" "$languages_lib"
    assert_failure
    run grep -F "_lang_run_as_user \"\$bun_bin --version\"" "$languages_lib"
    assert_failure

    run grep -F "_cli_run_as_user \"source '\$CLI_TOOLS_SCRIPT_DIR/security.sh'; verify_checksum '\$url' '\$expected_sha256'" "$cli_tools_lib"
    assert_failure
    run grep -F "_cli_run_as_user \"\$cargo_bin install" "$cli_tools_lib"
    assert_failure

    run grep -F "_cloud_run_as_user \"\\\"\$bun_bin\\\" install -g \$cli@latest\"" "$cloud_db_lib"
    assert_failure

    run grep -F "_stack_run_as_user \"mkdir -p '\$dir'" "$stack_lib"
    assert_failure

    run grep -F "printf -v wrapper_path_q '%q' \"\$wrapper_path\"" "$agents_lib"
    assert_success
    run grep -F "printf -v security_lib_q '%q' \"\$LANG_SCRIPT_DIR/security.sh\"" "$languages_lib"
    assert_success
    run grep -F "printf -v security_lib_q '%q' \"\$CLI_TOOLS_SCRIPT_DIR/security.sh\"" "$cli_tools_lib"
    assert_success
    run grep -F "printf -v cli_package_q '%q' \"\$cli@latest\"" "$cloud_db_lib"
    assert_success
    run grep -F "printf -v am_dest_q '%q' \"\$dir/am\"" "$stack_lib"
    assert_success
}

@test "installer recovery suggestions use stable module selectors" {
    local installer="$PROJECT_ROOT/install.sh"
    local agents_lib="$PROJECT_ROOT/scripts/lib/agents.sh"
    local smoke_lib="$PROJECT_ROOT/scripts/lib/smoke_test.sh"

    run grep -E '(Fix:|re-run:|Re-run:|Install bun first:).*--only-phase' "$installer" "$agents_lib" "$smoke_lib"
    assert_failure

    run grep -F 'acfs_smoke_install_fix_command lang.bun lang.uv lang.rust lang.go' "$installer"
    assert_success

    run grep -F 'acfs_smoke_install_fix_command agents.claude agents.codex agents.gemini' "$installer"
    assert_success

    run grep -F 'acfs_smoke_install_fix_command stack.ntm' "$installer"
    assert_success

    run grep -F 'acfs_smoke_install_fix_command acfs.onboard' "$installer"
    assert_success

    run grep -F 'acfs_smoke_install_fix_command stack.mcp_agent_mail' "$installer"
    assert_success

    run grep -F -- '--force-reinstall --only stack.ntm' "$smoke_lib"
    assert_success

    run grep -F -- '--force-reinstall --only lang.bun' "$agents_lib"
    assert_success
}

@test "install.sh: smoke fix command preserves pinned ref" {
    local installer="$PROJECT_ROOT/install.sh"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^acfs_smoke_install_fix_command()/,/^}$/p' "$installer")"

    ACFS_REPO_OWNER="Dicklesworthstone"
    ACFS_REPO_NAME="agentic_coding_flywheel_setup"
    ACFS_COMMIT_SHA_FULL="abc1234"
    ACFS_REF_INPUT="feature/test"

    run acfs_smoke_install_fix_command "stack.ntm"
    assert_success
    assert_output --partial "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/abc1234/install.sh"
    assert_output --partial "bash -s -- --yes --force-reinstall --only stack.ntm --ref abc1234"

    unset ACFS_COMMIT_SHA_FULL
    ACFS_REF_INPUT="feature/test"

    run acfs_smoke_install_fix_command "stack.ntm"
    assert_success
    assert_output --partial "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/feature/test/install.sh"
    assert_output --partial "bash -s -- --yes --force-reinstall --only stack.ntm --ref feature/test"

    ACFS_REF_INPUT="main"
    run acfs_smoke_install_fix_command "stack.ntm"
    assert_success
    assert_output --partial "https://agent-flywheel.com/install"
    refute_output --partial "--ref"
}

@test "doctor.sh: state mode is validated before sudo policy and fix suggestions" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_normalize_mode()/,/^}$/p' "$doctor_lib")"

    run _acfs_doctor_normalize_mode "safe"
    assert_success
    assert_output "safe"

    run _acfs_doctor_normalize_mode "safe --skip-cloud"
    assert_failure

    run grep -F 'ACFS_MODE="$(_acfs_doctor_normalize_mode "${ACFS_MODE:-}" 2>/dev/null || true)"' "$doctor_lib"
    assert_success

    run grep -F 'ACFS_MODE="${ACFS_MODE:-vibe}"' "$doctor_lib"
    assert_success
}

@test "doctor.sh: manifest check runner ignores poisoned env and bash functions" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local target_home="$BATS_TEST_TMPDIR/doctor-target-home"
    local output_file="$BATS_TEST_TMPDIR/doctor-manifest-check.out"
    local marker="$BATS_TEST_TMPDIR/poisoned-command.marker"
    local output_q

    mkdir -p "$target_home"
    printf -v output_q '%q' "$output_file"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_sanitize_abs_nonroot_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_system_binary_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_passwd_home_from_entry()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_doctor_run_manifest_check()/,/^}$/p' "$doctor_lib")"

    _acfs_doctor_getent_passwd_entry() {
        printf 'tester:x:1000:1000::%s:/bin/bash\n' "$target_home"
    }
    _acfs_doctor_resolve_current_user() {
        printf 'tester\n'
    }
    _acfs_doctor_validate_bin_dir_for_home() {
        return 1
    }
    log_error() {
        printf '%s\n' "$*" >&2
    }
    env() {
        printf 'env\n' > "$marker"
        return 127
    }
    bash() {
        printf 'bash\n' > "$marker"
        return 127
    }

    TARGET_USER="tester"
    TARGET_HOME="$target_home"
    ACFS_BIN_DIR=""

    run _doctor_run_manifest_check target_user "printf '%s\n' \"\$TARGET_USER:\$TARGET_HOME\" > $output_q"
    assert_success
    [[ ! -e "$marker" ]] || fail "poisoned shell function executed: $(<"$marker")"
    [[ "$(<"$output_file")" == "tester:$target_home" ]] || fail "manifest check did not run in target context"
}

@test "doctor.sh: fix suggestions do not emit malicious pinned refs from state" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local fixture_state_file="$BATS_TEST_TMPDIR/doctor-state.json"

    cat > "$fixture_state_file" <<'EOF'
{
  "pinned_ref": "main\"; touch /tmp/acfs-pwned #"
}
EOF

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_system_binary_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_read_json_string_key()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_normalize_mode()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_normalize_ref()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^build_fix_suggestion()/,/^}$/p' "$doctor_lib")"

    _acfs_doctor_find_project_path() {
        [[ "${1:-}" == "state.json" ]] || return 1
        printf '%s\n' "$fixture_state_file"
    }

    ACFS_MODE="safe --skip-cloud"
    run build_fix_suggestion "stack.ntm"
    assert_success
    assert_output --partial "--mode vibe"
    refute_output --partial "ACFS_REF="
    refute_output --partial "touch /tmp/acfs-pwned"
    refute_output --partial "--ref"

    cat > "$fixture_state_file" <<'EOF'
{
  "pinned_ref": "abc1234"
}
EOF

    ACFS_MODE="safe"
    run build_fix_suggestion "stack.ntm"
    assert_success
    assert_output --partial "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/abc1234/install.sh"
    assert_output --partial "bash -s -- --yes --force-reinstall --mode safe --only stack.ntm --ref abc1234"
    refute_output --partial "ACFS_REF="

    cat > "$fixture_state_file" <<'EOF'
{
  "pinned_ref": "-bad-ref"
}
EOF

    run build_fix_suggestion "stack.ntm"
    assert_success
    assert_output --partial "curl -fsSL https://agent-flywheel.com/install | bash -s --"
    refute_output --partial "--ref"
}

@test "doctor.sh: passwd target home repairs stale inherited TARGET_HOME" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local test_current_user
    local test_trusted_home
    local test_stale_home

    test_current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    test_trusted_home="$(create_temp_dir)"
    test_stale_home="$(create_temp_dir)"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_sanitize_abs_nonroot_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_passwd_home_from_entry()/,/^}$/p' "$doctor_lib")"

    _acfs_doctor_getent_passwd_entry() {
        if [[ "${1:-}" == "$test_current_user" ]]; then
            printf '%s:x:1000:1000::%s:/bin/bash\n' "$test_current_user" "$test_trusted_home"
            return 0
        fi
        return 1
    }

    _acfs_doctor_resolve_current_user() {
        printf '%s\n' "$test_current_user"
    }

    TARGET_USER="$test_current_user"
    TARGET_HOME="$test_stale_home"
    _ACFS_DOCTOR_ENV_TARGET_HOME="$test_stale_home"
    _acfs_doctor_current_home="$test_stale_home"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_resolved_target_home=""/,/^unset _acfs_doctor_resolved_target_home$/p' "$doctor_lib")"

    [[ "$TARGET_HOME" == "$test_trusted_home" ]] || {
        printf 'doctor TARGET_HOME was not repaired: %s\n' "$TARGET_HOME" >&2
        return 1
    }
}

@test "doctor.sh: explicit unresolved TARGET_USER is not replaced by installed state" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local stale_home

    stale_home="$(create_temp_dir)"

    run env \
        TARGET_USER="missinguser" \
        TARGET_HOME="$stale_home" \
        HOME="$stale_home" \
        PATH="/usr/bin:/bin" \
        bash -c 'source <(sed "$ d" "$1"); printf "TARGET_USER=%s TARGET_HOME=%s ACFS_HOME=%s\n" "${TARGET_USER:-}" "${TARGET_HOME:-}" "${ACFS_HOME:-}"' _ "$doctor_lib"
    assert_success
    assert_output "TARGET_USER=missinguser TARGET_HOME= ACFS_HOME="
}

@test "doctor manifest checks and fresh-vps heuristic repair stale TARGET_HOME" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local os_detect_lib="$PROJECT_ROOT/scripts/lib/os_detect.sh"

    run grep -F 'local explicit_target_home=""' "$doctor_lib"
    assert_success
    run grep -F 'local resolved_target_home=""' "$doctor_lib"
    assert_success
    run grep -F 'explicit_target_home="$target_home"' "$doctor_lib"
    assert_success
    run grep -F 'resolved_target_home="$(_acfs_doctor_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"' "$doctor_lib"
    assert_success
    run grep -F 'target_home="${resolved_target_home%/}"' "$doctor_lib"
    assert_success
    run grep -E '^[[:space:]]+target_home="\$explicit_target_home"' "$doctor_lib"
    assert_failure
    run grep -F '{ [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }' "$doctor_lib"
    assert_success
    run grep -F 'target_home="${target_home%/}"' "$doctor_lib"
    assert_failure
    run grep -F 'if [[ -z "$target_home" ]]; then' "$doctor_lib"
    assert_failure

    run grep -F 'resolved_target_home="$(os_detect_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"' "$os_detect_lib"
    assert_success
    run grep -F 'target_home="${resolved_target_home%/}"' "$os_detect_lib"
    assert_success
    run grep -F 'local explicit_target_home="${TARGET_HOME:-}"' "$os_detect_lib"
    assert_success
    run grep -F 'current_home="${HOME%/}"' "$os_detect_lib"
    assert_success
    run grep -F '{ [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }' "$os_detect_lib"
    assert_success
    run grep -F 'resolved_target_home="$explicit_target_home"' "$os_detect_lib"
    assert_success
    run grep -E '^[[:space:]]+target_home="\$explicit_target_home"' "$os_detect_lib"
    assert_failure
    run grep -E '^[[:space:]]+target_home="\$\{TARGET_HOME:-\}"' "$os_detect_lib"
    assert_failure
}

@test "doctor manifest checks do not let current HOME override explicit TARGET_HOME" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local target_home
    local stale_home

    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"

    eval "$(sed -n '/^_acfs_doctor_system_binary_path()/,/^}$/p' "$doctor_lib")"
    eval "$(sed -n '/^_doctor_run_manifest_check()/,/^}/p' "$doctor_lib")"

    _acfs_doctor_sanitize_abs_nonroot_path() {
        local path_value="${1:-}"
        [[ -n "$path_value" ]] || return 1
        path_value="${path_value%/}"
        [[ -n "$path_value" ]] || return 1
        [[ "$path_value" == /* ]] || return 1
        [[ "$path_value" != "/" ]] || return 1
        printf '%s\n' "$path_value"
    }

    _acfs_doctor_getent_passwd_entry() {
        return 1
    }

    _acfs_doctor_resolve_current_user() {
        printf 'acfstestuser\n'
    }

    _acfs_doctor_validate_bin_dir_for_home() {
        return 1
    }

    log_error() {
        printf '%s\n' "$*" >&2
    }

    export TARGET_USER="acfstestuser"
    export TARGET_HOME="$target_home"
    export _acfs_doctor_current_home="$stale_home"

    run _doctor_run_manifest_check current 'printf "TARGET_HOME=%s\n" "$TARGET_HOME"'
    assert_success
    assert_output "TARGET_HOME=$target_home"

    export TARGET_HOME="$stale_home"
    run _doctor_run_manifest_check current 'printf "TARGET_HOME=%s\n" "$TARGET_HOME"'
    assert_success
    assert_output "TARGET_HOME=$stale_home"
}

@test "fresh-vps heuristic does not let current HOME override explicit TARGET_HOME" {
    local os_detect_lib="$PROJECT_ROOT/scripts/lib/os_detect.sh"
    local target_home
    local stale_home

    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    printf '# default ubuntu profile\n' >"$target_home/.bashrc"
    printf '# ACFS managed profile\n' >"$stale_home/.bashrc"

    run bash -c '
        set -euo pipefail
        os_detect_lib="$1"
        target_home="$2"
        stale_home="$3"

        eval "$(sed -n "/^is_fresh_vps()/,/^}/p" "$os_detect_lib")"

        os_detect_getent_passwd_entry() {
            return 1
        }

        os_detect_resolve_current_user() {
            printf "acfstestuser\n"
        }

        log_detail() {
            :
        }

        command() {
            if [[ "${1:-}" == "-v" && "${2:-}" == "git" ]]; then
                return 1
            fi
            builtin command "$@"
        }

        dpkg() {
            local i
            for ((i = 0; i < 600; i++)); do
                printf "pkg\n"
            done
        }

        export TARGET_USER="acfstestuser"
        export TARGET_HOME="$target_home"
        export HOME="$stale_home"

        is_fresh_vps
    ' _ "$os_detect_lib" "$target_home" "$stale_home"
    assert_success

    run bash -c '
        set -euo pipefail
        os_detect_lib="$1"
        stale_home="$2"

        eval "$(sed -n "/^is_fresh_vps()/,/^}/p" "$os_detect_lib")"

        os_detect_getent_passwd_entry() {
            return 1
        }

        os_detect_resolve_current_user() {
            printf "acfstestuser\n"
        }

        log_detail() {
            :
        }

        command() {
            if [[ "${1:-}" == "-v" && "${2:-}" == "git" ]]; then
                return 1
            fi
            builtin command "$@"
        }

        dpkg() {
            local i
            for ((i = 0; i < 600; i++)); do
                printf "pkg\n"
            done
        }

        export TARGET_USER="acfstestuser"
        export TARGET_HOME="$stale_home"
        export HOME="$stale_home"

        is_fresh_vps
    ' _ "$os_detect_lib" "$stale_home"
    assert_failure
}

@test "read-only context helpers repair stale TARGET_HOME for current target user" {
    local current_user
    local current_home
    local stale_home
    local label
    local script
    local prepare_cmd
    local target_var
    local failures=""

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    current_home="$(command getent passwd "$current_user" 2>/dev/null | cut -d: -f6)"
    [[ -n "$current_user" && -n "$current_home" ]] || skip "Could not resolve current user home"
    stale_home="$(create_temp_dir)"

    while IFS='|' read -r label script prepare_cmd target_var; do
        [[ -n "$label" ]] || continue
        run env \
            TARGET_USER="$current_user" \
            TARGET_HOME="$stale_home" \
            HOME="$stale_home" \
            PATH="/usr/bin:/bin" \
            bash -c '
                set -euo pipefail
                source "$1"
                eval "$2"
                printf "%s\n" "${!3}"
            ' _ "$script" "$prepare_cmd" "$target_var"

        if [[ "$status" -ne 0 || "$output" != "$current_home" ]]; then
            printf -v failures '%s%s: status=%s output=%s\n' "$failures" "$label" "$status" "$output"
        fi
    done <<EOF
status|$PROJECT_ROOT/scripts/lib/status.sh|_status_prepare_context|TARGET_HOME
info|$PROJECT_ROOT/scripts/lib/info.sh|info_prepare_context|TARGET_HOME
export-config|$PROJECT_ROOT/scripts/lib/export-config.sh|prepare_target_context|TARGET_HOME
smoke|$PROJECT_ROOT/scripts/lib/smoke_test.sh|:|_SMOKE_TARGET_HOME
EOF

    if [[ -n "$failures" ]]; then
        printf '%s' "$failures" >&2
        return 1
    fi
}

@test "read-only explicit target resolvers fail closed for unresolved target user with stale TARGET_HOME" {
    local stale_home
    local label
    local script
    local func
    local failures=""

    stale_home="$(create_temp_dir)"

    while IFS='|' read -r label script func; do
        [[ -n "$label" ]] || continue
        run env \
            TARGET_USER="missinguser" \
            TARGET_HOME="$stale_home" \
            HOME="$stale_home" \
            PATH="/usr/bin:/bin" \
            bash -c '
                set -euo pipefail
                source "$1" >/dev/null
                "$2"
            ' _ "$script" "$func"

        if [[ "$status" -eq 0 || -n "$output" ]]; then
            printf -v failures '%s%s: status=%s output=%s\n' "$failures" "$label" "$status" "$output"
        fi
    done <<EOF
status|$PROJECT_ROOT/scripts/lib/status.sh|_status_resolve_explicit_target_home
support|$PROJECT_ROOT/scripts/lib/support.sh|support_resolve_explicit_target_home
cheatsheet|$PROJECT_ROOT/scripts/lib/cheatsheet.sh|cheatsheet_resolve_explicit_target_home
continue|$PROJECT_ROOT/scripts/lib/continue.sh|continue_resolve_explicit_target_home
changelog|$PROJECT_ROOT/scripts/lib/changelog.sh|changelog_resolve_explicit_target_home
info|$PROJECT_ROOT/scripts/lib/info.sh|info_resolve_explicit_target_home
dashboard|$PROJECT_ROOT/scripts/lib/dashboard.sh|dashboard_resolve_explicit_target_home
export-config|$PROJECT_ROOT/scripts/lib/export-config.sh|resolve_explicit_target_home
onboard|$PROJECT_ROOT/packages/onboard/onboard.sh|onboard_resolve_explicit_runtime_home
EOF

    if [[ -n "$failures" ]]; then
        printf '%s' "$failures" >&2
        return 1
    fi
}

@test "sourced current-home helpers prefer passwd home over stale HOME" {
    local current_user
    local current_home
    local stale_home
    local label
    local script
    local target_var
    local failures=""

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null || true)"
    current_home="$(command getent passwd "$current_user" 2>/dev/null | cut -d: -f6)"
    [[ -n "$current_user" && -n "$current_home" ]] || skip "Could not resolve current user home"
    stale_home="$(create_temp_dir)"

    while IFS='|' read -r label script target_var; do
        [[ -n "$label" ]] || continue
        run env \
            TARGET_USER="$current_user" \
            TARGET_HOME="$stale_home" \
            HOME="$stale_home" \
            PATH="/usr/bin:/bin" \
            bash -c '
                set -euo pipefail
                source "$1" >/dev/null
                printf "%s\n" "${!2}"
            ' _ "$script" "$target_var"

        if [[ "$status" -ne 0 || "$output" != "$current_home" ]]; then
            printf -v failures '%s%s: status=%s output=%s\n' "$failures" "$label" "$status" "$output"
        fi
    done <<EOF
support|$PROJECT_ROOT/scripts/lib/support.sh|_SUPPORT_CURRENT_HOME
status|$PROJECT_ROOT/scripts/lib/status.sh|_STATUS_CURRENT_HOME
dashboard|$PROJECT_ROOT/scripts/lib/dashboard.sh|_DASHBOARD_CURRENT_HOME
info|$PROJECT_ROOT/scripts/lib/info.sh|_INFO_CURRENT_HOME
continue|$PROJECT_ROOT/scripts/lib/continue.sh|_CONTINUE_CURRENT_HOME
cheatsheet|$PROJECT_ROOT/scripts/lib/cheatsheet.sh|_CHEATSHEET_CURRENT_HOME
changelog|$PROJECT_ROOT/scripts/lib/changelog.sh|_CHANGELOG_CURRENT_HOME
export-config|$PROJECT_ROOT/scripts/lib/export-config.sh|_EXPORT_CURRENT_HOME
smoke|$PROJECT_ROOT/scripts/lib/smoke_test.sh|_SMOKE_CURRENT_HOME
EOF

    if [[ -n "$failures" ]]; then
        printf '%s' "$failures" >&2
        return 1
    fi
}

@test "read-only helper home_for_user functions prefer passwd over stale current home" {
    local passwd_home
    local stale_home
    local label
    local script
    local sanitize_func
    local passwd_func
    local home_func
    local current_func
    local getent_func
    local current_home_var
    local expected_output
    local failures=""

    passwd_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    expected_output="${passwd_home}"$'\n'"${stale_home}"

    while IFS='|' read -r label script sanitize_func passwd_func home_func current_func getent_func current_home_var; do
        [[ -n "$label" ]] || continue

        run env HOME="$stale_home" PATH="/usr/bin:/bin" bash -s -- \
            "$script" "$sanitize_func" "$passwd_func" "$home_func" \
            "$current_func" "$getent_func" "$current_home_var" \
            "$passwd_home" "$stale_home" <<'EOF'
set -euo pipefail

script="$1"
sanitize_func="$2"
passwd_func="$3"
home_func="$4"
current_func="$5"
getent_func="$6"
current_home_var="$7"
passwd_home="$8"
stale_home="$9"

export ACFS_TEST_CURRENT_USER="tester"
export ACFS_TEST_PASSWD_HOME="$passwd_home"

eval "$(sed -n "/^${sanitize_func}()/,/^}$/p" "$script")"
eval "$(sed -n "/^${passwd_func}()/,/^}$/p" "$script")"
eval "$(sed -n "/^${home_func}()/,/^}$/p" "$script")"
eval "${current_func}() { printf '%s\n' \"\$ACFS_TEST_CURRENT_USER\"; }"
eval "${getent_func}() { if [[ \"\${1:-}\" == \"\$ACFS_TEST_CURRENT_USER\" ]]; then printf '%s:x:1000:1000::%s:/bin/bash\n' \"\$ACFS_TEST_CURRENT_USER\" \"\$ACFS_TEST_PASSWD_HOME\"; return 0; fi; return 1; }"

printf -v "$current_home_var" '%s' "$stale_home"
"$home_func" "$ACFS_TEST_CURRENT_USER"

eval "${getent_func}() { return 1; }"
"$home_func" "$ACFS_TEST_CURRENT_USER"
EOF

        if [[ "$status" -ne 0 || "$output" != "$expected_output" ]]; then
            printf -v failures '%s%s: status=%s output=%s\n' "$failures" "$label" "$status" "$output"
        fi
    done <<EOF
support|$PROJECT_ROOT/scripts/lib/support.sh|support_sanitize_abs_nonroot_path|support_passwd_home_from_entry|support_home_for_user|support_resolve_current_user|support_getent_passwd_entry|_SUPPORT_CURRENT_HOME
status|$PROJECT_ROOT/scripts/lib/status.sh|_status_sanitize_abs_nonroot_path|_status_passwd_home_from_entry|_status_home_for_user|_status_resolve_current_user|_status_getent_passwd_entry|_STATUS_CURRENT_HOME
info|$PROJECT_ROOT/scripts/lib/info.sh|info_sanitize_abs_nonroot_path|info_passwd_home_from_entry|info_home_for_user|info_resolve_current_user|info_getent_passwd_entry|_INFO_CURRENT_HOME
continue|$PROJECT_ROOT/scripts/lib/continue.sh|continue_sanitize_abs_nonroot_path|continue_passwd_home_from_entry|home_for_user|continue_resolve_current_user|continue_getent_passwd_entry|_CONTINUE_CURRENT_HOME
changelog|$PROJECT_ROOT/scripts/lib/changelog.sh|changelog_sanitize_abs_nonroot_path|changelog_passwd_home_from_entry|changelog_home_for_user|changelog_resolve_current_user|changelog_getent_passwd_entry|_CHANGELOG_CURRENT_HOME
export-config|$PROJECT_ROOT/scripts/lib/export-config.sh|export_sanitize_abs_nonroot_path|export_passwd_home_from_entry|home_for_user|export_resolve_current_user|export_getent_passwd_entry|_EXPORT_CURRENT_HOME
EOF

    if [[ -n "$failures" ]]; then
        printf '%s' "$failures" >&2
        return 1
    fi
}

@test "doctor.sh: ensure_path restores system PATH when empty" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local test_home="$BATS_TEST_TMPDIR/doctor-home"
    local expected_path=""
    mkdir -p "$test_home/.local/bin" "$test_home/.acfs/bin" "$test_home/google-cloud-sdk/bin"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_sanitize_abs_nonroot_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_system_binary_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_getent_passwd_entry()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_passwd_home_from_entry()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_validate_bin_dir_for_home()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^ensure_path()/,/^}$/p' "$doctor_lib")"

    export TARGET_HOME="$test_home"
    export ACFS_BIN_DIR=""
    _acfs_doctor_current_home="$test_home"
    # shellcheck disable=SC2123
    PATH=""
    ensure_path

    expected_path="$test_home/.local/bin:$test_home/.acfs/bin:$test_home/google-cloud-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
    [ "$PATH" = "$expected_path" ]
}

@test "doctor.sh: runtime path includes hardened system PATH once when PATH is empty" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"
    local test_home="$BATS_TEST_TMPDIR/doctor-runtime-home"
    local original_path="${PATH-}"
    mkdir -p "$test_home/.local/bin" "$test_home/.acfs/bin" "$test_home/google-cloud-sdk/bin"

    # shellcheck disable=SC1090
    eval "$(sed -n '/^_acfs_doctor_sanitize_abs_nonroot_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^doctor_runtime_home()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^doctor_runtime_path()/,/^}$/p' "$doctor_lib")"

    export TARGET_HOME="$test_home"
    export ACFS_HOME=""
    export ACFS_BIN_DIR=""
    _acfs_doctor_current_home="$test_home"
    # shellcheck disable=SC2123
    PATH=""

    run doctor_runtime_path
    PATH="${original_path:-/usr/bin:/bin}"
    assert_success
    [ "$output" = "$test_home/.local/bin:$test_home/.acfs/bin:$test_home/.bun/bin:$test_home/.cargo/bin:$test_home/.atuin/bin:$test_home/go/bin:$test_home/google-cloud-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin" ]
}

@test "update.sh: target path includes google cloud sdk bin and hardened system PATH" {
    local update="$PROJECT_ROOT/scripts/lib/update.sh"
    local target_home="$BATS_TEST_TMPDIR/update-target-home"
    mkdir -p "$target_home"

    run env HOME="$target_home" PATH="/usr/bin:/bin" /bin/bash -c 'source "$1"; ACFS_BIN_DIR=""; PATH=""; update_target_path "$2"' _ "$update" "$target_home"
    assert_success
    [ "$output" = "$target_home/.local/bin:$target_home/.acfs/bin:$target_home/.bun/bin:$target_home/.cargo/bin:$target_home/.atuin/bin:$target_home/go/bin:$target_home/google-cloud-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin" ]
}

@test "update.sh: run_in_target_context rejects unresolved target_home before sudo" {
    local sudo_log="$BATS_TEST_TMPDIR/update-sudo.log"
    : > "$sudo_log"

    export TARGET_USER="missinguser"
    export TARGET_HOME="/"

    getent() {
        return 2
    }

    sudo() {
        echo "sudo-called=$*" >> "$sudo_log"
        return 0
    }

    run update_run_in_target_context "" printf unreachable
    assert_failure
    assert_output --partial "Unable to resolve TARGET_HOME for 'missinguser'; export TARGET_HOME explicitly"

    run cat "$sudo_log"
    assert_success
    assert_output ""
}

@test "doctor.sh: binary helper ignores current-shell-only PATH entries" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"

    init_stub_dir

    # shellcheck disable=SC1090
    eval "$(sed -n '/^doctor_binary_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^doctor_binary_exists()/,/^}$/p' "$doctor_lib")"

    doctor_runtime_home() {
        printf '%s\n' "$TARGET_HOME"
    }

    export TARGET_HOME="$HOME/target-home"
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$ACFS_BIN_DIR"

    cat > "$STUB_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
echo "current-shell-only-tool"
EOF
    chmod +x "$STUB_DIR/current-shell-only-tool"
    export PATH="$STUB_DIR:/usr/bin:/bin"

    run doctor_binary_path "current-shell-only-tool"
    assert_failure

    run doctor_binary_exists "current-shell-only-tool"
    assert_failure

    cat > "$ACFS_BIN_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
echo "target-local-tool"
EOF
    chmod +x "$ACFS_BIN_DIR/current-shell-only-tool"

    run doctor_binary_path "current-shell-only-tool"
    assert_success
    assert_output "$ACFS_BIN_DIR/current-shell-only-tool"

    run doctor_binary_exists "current-shell-only-tool"
    assert_success
}

@test "doctor.sh: check_command ignores current-shell-only PATH entries" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"

    init_stub_dir

    # shellcheck disable=SC1090
    eval "$(sed -n '/^doctor_binary_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^doctor_binary_exists()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^doctor_version_probe()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^get_version_line()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^check_command()/,/^}$/p' "$doctor_lib")"

    doctor_runtime_home() {
        printf '%s\n' "$TARGET_HOME"
    }

    check() {
        printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "${4:-}" "${5:-}"
    }

    export TARGET_HOME="$HOME/target-home"
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    DOCTOR_VERSION_TIMEOUT=2
    mkdir -p "$ACFS_BIN_DIR"

    cat > "$STUB_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "current-shell-only-tool 9.9.9"
  exit 0
fi
echo "current-shell-only-tool"
EOF
    chmod +x "$STUB_DIR/current-shell-only-tool"
    export PATH="$STUB_DIR:/usr/bin:/bin"

    run check_command "test.id" "Tool Label" "current-shell-only-tool" "fix me"
    assert_success
    assert_output 'test.id|Tool Label|fail|not found|fix me'

    cat > "$ACFS_BIN_DIR/current-shell-only-tool" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "target-local-tool 1.2.3"
  exit 0
fi
echo "target-local-tool"
EOF
    chmod +x "$ACFS_BIN_DIR/current-shell-only-tool"

    run check_command "test.id" "Tool Label" "current-shell-only-tool" "fix me"
    assert_success
    assert_output 'test.id|Tool Label (target-local-tool 1.2.3)|pass|installed|'
}

@test "doctor.sh: agent mail CLI helper ignores current-shell am and direct install without shim" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"

    init_stub_dir

    # shellcheck disable=SC1090
    eval "$(sed -n '/^doctor_binary_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^doctor_agent_mail_cli_path()/,/^}$/p' "$doctor_lib")"

    doctor_runtime_home() {
        printf '%s\n' "$TARGET_HOME"
    }

    export TARGET_HOME="$HOME/target-home"
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$TARGET_HOME/mcp_agent_mail" "$ACFS_BIN_DIR"

    cat > "$STUB_DIR/am" <<'EOF'
#!/usr/bin/env bash
echo "current-shell am"
EOF
    chmod +x "$STUB_DIR/am"
    export PATH="$STUB_DIR:/usr/bin:/bin"

    cat > "$TARGET_HOME/mcp_agent_mail/am" <<'EOF'
#!/usr/bin/env bash
echo "direct install"
EOF
    chmod +x "$TARGET_HOME/mcp_agent_mail/am"

    run doctor_agent_mail_cli_path
    assert_failure

    cat > "$ACFS_BIN_DIR/am" <<'EOF'
#!/usr/bin/env bash
echo "target shim"
EOF
    chmod +x "$ACFS_BIN_DIR/am"

    run doctor_agent_mail_cli_path
    assert_success
    assert_output "$ACFS_BIN_DIR/am"
}

@test "doctor.sh: agent mail doctor check uses target CLI instead of current-shell am" {
    local doctor_lib="$PROJECT_ROOT/scripts/lib/doctor.sh"

    init_stub_dir

    # shellcheck disable=SC1090
    eval "$(sed -n '/^doctor_binary_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^doctor_agent_mail_cli_path()/,/^}$/p' "$doctor_lib")"
    # shellcheck disable=SC1090
    eval "$(sed -n '/^agent_mail_doctor_check_json()/,/^}$/p' "$doctor_lib")"

    doctor_runtime_home() {
        printf '%s\n' "$TARGET_HOME"
    }

    run_with_timeout() {
        local _timeout="$1"
        local _description="$2"
        shift 2
        "$@"
    }

    export DEEP_CHECK_TIMEOUT=5
    export TARGET_HOME="$HOME/target-home"
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$ACFS_BIN_DIR"

    cat > "$STUB_DIR/am" <<'EOF'
#!/usr/bin/env bash
: > "$HOME/global-am-used"
echo '{"healthy":false,"source":"global"}'
EOF
    chmod +x "$STUB_DIR/am"
    export PATH="$STUB_DIR:/usr/bin:/bin"

    cat > "$ACFS_BIN_DIR/am" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "doctor" && "${2:-}" == "check" && "${3:-}" == "--json" ]]; then
  echo '{"healthy":true,"source":"target"}'
  exit 0
fi
exit 1
EOF
    chmod +x "$ACFS_BIN_DIR/am"

    run agent_mail_doctor_check_json
    assert_success
    assert_output '{"healthy":true,"source":"target"}'
    [[ ! -f "$HOME/global-am-used" ]]
}

@test "update_retry_max_attempts: defaults malformed values and clamps zero" {
    unset ACFS_UPDATE_RETRY_MAX_ATTEMPTS
    run update_retry_max_attempts
    assert_success
    assert_output "3"

    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=bogus
    run update_retry_max_attempts
    assert_success
    assert_output "3"

    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=0
    run update_retry_max_attempts
    assert_success
    assert_output "1"

    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=2
    run update_retry_max_attempts
    assert_success
    assert_output "2"

    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=08
    run update_retry_max_attempts
    assert_success
    assert_output "8"

    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=999
    run update_retry_max_attempts
    assert_success
    assert_output "20"
}

@test "update_retry_sleep_seconds: defaults malformed values and preserves zero override" {
    unset ACFS_UPDATE_RETRY_SLEEP_SECONDS
    run update_retry_sleep_seconds 3
    assert_success
    assert_output "6"

    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=bogus
    run update_retry_sleep_seconds 3
    assert_success
    assert_output "6"

    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=-1
    run update_retry_sleep_seconds 3
    assert_success
    assert_output "6"

    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=0
    run update_retry_sleep_seconds 3
    assert_success
    assert_output "0"

    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=08
    run update_retry_sleep_seconds 3
    assert_success
    assert_output "8"

    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=9999
    run update_retry_sleep_seconds 3
    assert_success
    assert_output "300"
}

@test "update_retry_sleep_seconds: normalizes direct attempt argument before fallback" {
    unset ACFS_UPDATE_RETRY_SLEEP_SECONDS

    run update_retry_sleep_seconds 08
    assert_success
    assert_output "16"

    run update_retry_sleep_seconds 9999
    assert_success
    assert_output "40"

    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=bogus
    run update_retry_sleep_seconds 9999
    assert_success
    assert_output "40"
}

@test "update_run_command_capture_with_retry: malformed retry sleep still retries transient failure" {
    init_stub_dir
    export PATH="$STUB_DIR:$PATH"
    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=2
    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=bogus
    UPDATE_LOG_FILE="$HOME/update.log"

    cat > "$STUB_DIR/transient-capture" <<'EOF'
#!/usr/bin/env bash
attempts_file="$HOME/transient-capture-attempts"
attempts=0
if [[ -f "$attempts_file" ]]; then
  attempts="$(cat "$attempts_file")"
fi
attempts=$((attempts + 1))
printf '%s\n' "$attempts" > "$attempts_file"
if [[ "$attempts" -eq 1 ]]; then
  echo "download failed: rate limit exceeded" >&2
  exit 7
fi
exit 0
EOF
    chmod +x "$STUB_DIR/transient-capture"

    sleep() {
        printf '%s\n' "$1" > "$HOME/capture-sleep"
    }

    run update_run_command_capture_with_retry "captured command" transient-capture

    assert_success
    [[ "$(cat "$HOME/transient-capture-attempts")" == "2" ]]
    [[ "$(cat "$HOME/capture-sleep")" == "2" ]]
}

@test "update_run_command_capture_with_retry: zero retry max still runs once and fails" {
    init_stub_dir
    export PATH="$STUB_DIR:$PATH"
    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=0
    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=0
    UPDATE_LOG_FILE="$HOME/update.log"

    cat > "$STUB_DIR/fail-capture" <<'EOF'
#!/usr/bin/env bash
attempts_file="$HOME/capture-attempts"
attempts=0
if [[ -f "$attempts_file" ]]; then
  attempts="$(cat "$attempts_file")"
fi
attempts=$((attempts + 1))
printf '%s\n' "$attempts" > "$attempts_file"
echo "ordinary failure" >&2
exit 7
EOF
    chmod +x "$STUB_DIR/fail-capture"

    run update_run_command_capture_with_retry "captured command" fail-capture

    [[ "$status" -eq 7 ]]
    [[ "$(cat "$HOME/capture-attempts")" == "1" ]]
}

@test "run_cmd_attempt_with_retry: zero retry max still runs once and fails" {
    init_stub_dir
    export PATH="$STUB_DIR:$PATH"
    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=0
    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=0
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    ABORT_ON_FAILURE=false
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0

    cat > "$STUB_DIR/fail-retry" <<'EOF'
#!/usr/bin/env bash
attempts_file="$HOME/retry-attempts"
attempts=0
if [[ -f "$attempts_file" ]]; then
  attempts="$(cat "$attempts_file")"
fi
attempts=$((attempts + 1))
printf '%s\n' "$attempts" > "$attempts_file"
echo "ordinary failure" >&2
exit 9
EOF
    chmod +x "$STUB_DIR/fail-retry"

    run run_cmd_attempt_with_retry "zero max fallback" fail-retry

    [[ "$status" -eq 9 ]]
    [[ "$(cat "$HOME/retry-attempts")" == "1" ]]
}

@test "run_cmd_bun_with_retry: honors configured retry max and sleep" {
    init_stub_dir
    export PATH="$STUB_DIR:$PATH"
    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=2
    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=0
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    ABORT_ON_FAILURE=false
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    SKIP_COUNT=0

    cat > "$STUB_DIR/fail-bun" <<'EOF'
#!/usr/bin/env bash
attempts_file="$HOME/bun-retry-attempts"
attempts=0
if [[ -f "$attempts_file" ]]; then
  attempts="$(cat "$attempts_file")"
fi
attempts=$((attempts + 1))
printf '%s\n' "$attempts" > "$attempts_file"
echo "download failed: rate limit exceeded" >&2
exit 7
EOF
    chmod +x "$STUB_DIR/fail-bun"

    sleep() {
        printf '%s\n' "$1" >> "$HOME/bun-retry-sleeps"
    }

    run_cmd_bun_with_retry "Bun transient command" fail-bun

    [[ "$(cat "$HOME/bun-retry-attempts")" == "2" ]]
    [[ "$(cat "$HOME/bun-retry-sleeps")" == "0" ]]
    [[ "$SUCCESS_COUNT" -eq 0 ]]
    [[ "$FAIL_COUNT" -eq 1 ]]
}

@test "update_agents: Codex fallback failure honors abort-on-failure" {
    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=1
    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=0
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    FORCE_MODE=false
    ABORT_ON_FAILURE=true
    UPDATE_AGENTS=true
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    SKIP_COUNT=0

    update_target_user() { printf 'tester\n'; }
    update_target_home() { printf '%s\n' "$HOME"; }
    update_binary_path() {
        case "${1:-}" in
            bun) printf '%s\n' "$HOME/.local/bin/bun" ;;
            *) return 1 ;;
        esac
    }
    update_binary_exists() {
        [[ "${1:-}" == "codex" ]]
    }
    get_version() { printf 'unknown\n'; }
    capture_version_before() { :; }
    capture_version_after() { return 1; }
    update_run_in_target_context() {
        local attempts_file="$HOME/codex-update-attempts"
        local attempts=0
        if [[ -f "$attempts_file" ]]; then
            attempts="$(cat "$attempts_file")"
        fi
        attempts=$((attempts + 1))
        printf '%s\n' "$attempts" > "$attempts_file"
        echo "codex install failed" >&2
        return 17
    }
    sleep() { :; }

    run update_agents

    assert_failure
    assert_output --partial "Aborting due to failure (--abort-on-failure)"
    [[ "$(cat "$HOME/codex-update-attempts")" == "3" ]]
}

@test "update_zoxide: retries transient reinstall failures before succeeding" {
    init_stub_dir
    export PATH="$STUB_DIR:$PATH"
    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=2
    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=0
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    YES_MODE=false
    ABORT_ON_FAILURE=false
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    SKIP_COUNT=0

    cat > "$STUB_DIR/zoxide" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "zoxide 0.9.9"
else
  echo "zoxide 0.9.9"
fi
EOF
    chmod +x "$STUB_DIR/zoxide"

    update_require_security() {
        return 0
    }

    update_run_verified_installer() {
        local attempts_file="$HOME/zoxide-attempts"
        local attempts=0
        if [[ -f "$attempts_file" ]]; then
            attempts="$(cat "$attempts_file")"
        fi
        attempts=$((attempts + 1))
        printf '%s\n' "$attempts" > "$attempts_file"
        if [[ "$attempts" -lt 2 ]]; then
            echo "download failed: rate limit exceeded" >&2
            return 1
        fi
        return 0
    }

    update_zoxide

    [[ "$(cat "$HOME/zoxide-attempts")" == "2" ]]
    [[ "$SUCCESS_COUNT" -eq 1 ]]
    [[ "$FAIL_COUNT" -eq 0 ]]
}

@test "update_zoxide: skips transient reinstall failure when existing binary remains healthy" {
    init_stub_dir
    export PATH="$STUB_DIR:$PATH"
    export ACFS_UPDATE_RETRY_MAX_ATTEMPTS=1
    export ACFS_UPDATE_RETRY_SLEEP_SECONDS=0
    QUIET=true
    VERBOSE=false
    DRY_RUN=false
    YES_MODE=false
    ABORT_ON_FAILURE=false
    UPDATE_LOG_FILE="$HOME/update.log"
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    SKIP_COUNT=0

    cat > "$STUB_DIR/zoxide" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "zoxide 0.9.9"
else
  echo "zoxide 0.9.9"
fi
EOF
    chmod +x "$STUB_DIR/zoxide"

    update_require_security() {
        return 0
    }

    update_run_verified_installer() {
        echo "Error: you have exceeded GitHub's API rate limit. Please try again later." >&2
        return 1
    }

    update_zoxide

    [[ "$SUCCESS_COUNT" -eq 0 ]]
    [[ "$SKIP_COUNT" -eq 1 ]]
    [[ "$FAIL_COUNT" -eq 0 ]]
}

@test "update uses retry/fallback paths for transient apt and uv failures" {
    local update="$PROJECT_ROOT/scripts/lib/update.sh"

    run grep -F 'run_cmd_sudo_attempt_with_retry "apt upgrade"' "$update"
    assert_success
    run grep -F 'apt-get upgrade -y --fix-missing' "$update"
    assert_success
    run grep -F 'run_cmd_attempt_with_retry "uv self-update"' "$update"
    assert_success
    run grep -F 'update_run_verified_installer_with_shell_repair "uv verified installer fallback" "uv" update_repair_uv_install' "$update"
    assert_success
}


@test "update_preferred_user_bin_dir: ignores stale other-user ACFS_BIN_DIR" {
    local current_home
    local target_home
    local stale_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"

    mkdir -p "$stale_home/.local/bin"

    export HOME="$current_home"
    export TARGET_USER="acfstestuser"
    export TARGET_HOME="$target_home"
    export ACFS_BIN_DIR="$stale_home/.local/bin"
    export TEST_UPDATE_TARGET_HOME="$target_home"
    unset ACFS_STATE_FILE
    unset ACFS_HOME

    update_getent_passwd_entry() {
        if [[ "${1:-}" == "acfstestuser" ]]; then
            printf 'acfstestuser:x:1000:1000::%s:/bin/bash\n' "$TEST_UPDATE_TARGET_HOME"
            return 0
        fi
        if [[ -z "${1:-}" ]]; then
            printf 'acfstestuser:x:1000:1000::%s:/bin/bash\n' "$TEST_UPDATE_TARGET_HOME"
            printf 'other:x:1001:1001::%s:/bin/bash\n' "$stale_home"
            return 0
        fi
        return 1
    }

    run update_preferred_user_bin_dir
    assert_success
    assert_output "$target_home/.local/bin"
}

@test "update_binary_path: ignores stale other-user ACFS_BIN_DIR when target binary exists" {
    local current_home
    local target_home
    local stale_home
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"

    mkdir -p "$target_home/.local/bin" "$stale_home/.local/bin"

    export HOME="$current_home"
    export TARGET_USER="acfstestuser"
    export TARGET_HOME="$target_home"
    export ACFS_BIN_DIR="$stale_home/.local/bin"
    export TEST_UPDATE_TARGET_HOME="$target_home"
    unset ACFS_STATE_FILE
    unset ACFS_HOME

    cat > "$stale_home/.local/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "stale-home-gh"
EOF
    chmod +x "$stale_home/.local/bin/gh"

    cat > "$target_home/.local/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "target-home-gh"
EOF
    chmod +x "$target_home/.local/bin/gh"

    update_getent_passwd_entry() {
        if [[ "${1:-}" == "acfstestuser" ]]; then
            printf 'acfstestuser:x:1000:1000::%s:/bin/bash\n' "$TEST_UPDATE_TARGET_HOME"
            return 0
        fi
        if [[ -z "${1:-}" ]]; then
            printf 'acfstestuser:x:1000:1000::%s:/bin/bash\n' "$TEST_UPDATE_TARGET_HOME"
            printf 'other:x:1001:1001::%s:/bin/bash\n' "$stale_home"
            return 0
        fi
        return 1
    }

    run update_binary_path "gh"
    assert_success
    assert_output "$target_home/.local/bin/gh"
}

@test "update.sh: target path ignores stale other-user ACFS_BIN_DIR" {
    local target_home
    local stale_home
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"

    mkdir -p "$target_home/.local/bin" "$target_home/.acfs/bin" "$target_home/google-cloud-sdk/bin" "$stale_home/.local/bin"

    export TARGET_USER="acfstestuser"
    export TARGET_HOME="$target_home"
    export ACFS_BIN_DIR="$stale_home/.local/bin"
    PATH="/usr/bin:/bin"

    getent() {
        if [[ "$1" == "passwd" && -z "${2:-}" ]]; then
            printf 'ubuntu:x:1000:1000::%s:/bin/bash\n' "$target_home"
            printf 'other:x:1001:1001::%s:/bin/bash\n' "$stale_home"
            return 0
        fi
        command getent "$@"
    }

    run update_target_path "$target_home"
    assert_success
    [[ "$output" == "$target_home/.local/bin:"* ]]
    refute_output --partial "$stale_home/.local/bin"
}

@test "update_require_security: ignores stale other-user ACFS_BIN_DIR" {
    local current_home
    local target_home
    local stale_home
    local target_marker
    local stale_marker
    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    stale_home="$(create_temp_dir)"
    target_marker="$BATS_TEST_TMPDIR/target-security.marker"
    stale_marker="$BATS_TEST_TMPDIR/stale-security.marker"

    mkdir -p "$target_home/.local/bin" "$stale_home/.local/bin"

    cat > "$target_home/.local/bin/security.sh" <<EOF
#!/usr/bin/env bash
load_checksums() {
    : > "$target_marker"
    return 0
}
EOF
    chmod +x "$target_home/.local/bin/security.sh"

    cat > "$stale_home/.local/bin/security.sh" <<EOF
#!/usr/bin/env bash
load_checksums() {
    : > "$stale_marker"
    return 0
}
EOF
    chmod +x "$stale_home/.local/bin/security.sh"

    export HOME="$current_home"
    export TARGET_USER="acfstestuser"
    export TARGET_HOME="$target_home"
    export ACFS_BIN_DIR="$stale_home/.local/bin"
    export ACFS_HOME="$current_home/missing-acfs"
    export TEST_UPDATE_TARGET_HOME="$target_home"
    unset ACFS_REPO_ROOT
    export CHECKSUMS_LOCAL="$current_home/checksums.yaml"
    UPDATE_SECURITY_READY=false

    refresh_checksums() {
        return 0
    }

    update_getent_passwd_entry() {
        if [[ "${1:-}" == "acfstestuser" ]]; then
            printf 'acfstestuser:x:1000:1000::%s:/bin/bash\n' "$TEST_UPDATE_TARGET_HOME"
            return 0
        fi
        if [[ -z "${1:-}" ]]; then
            printf 'acfstestuser:x:1000:1000::%s:/bin/bash\n' "$TEST_UPDATE_TARGET_HOME"
            printf 'other:x:1001:1001::%s:/bin/bash\n' "$stale_home"
            return 0
        fi
        return 1
    }

    run update_require_security
    assert_success
    [[ -f "$target_marker" ]]
    [[ ! -e "$stale_marker" ]]
}


@test "update_runtime_primary_bin_dir: fails closed for different unresolved target" {
    local current_home
    current_home="$(create_temp_dir)"

    mkdir -p "$current_home/.local/bin"

    export HOME="$current_home"
    export TARGET_USER="missinguser"
    export TARGET_HOME="/"
    export ACFS_BIN_DIR="$current_home/.local/bin"

    getent() {
        return 2
    }

    run update_runtime_primary_bin_dir
    assert_failure
}

@test "update_runtime_acfs_home: fails closed for different unresolved target" {
    local current_home
    current_home="$(create_temp_dir)"

    mkdir -p "$current_home/.acfs"

    export HOME="$current_home"
    export TARGET_USER="missinguser"
    export TARGET_HOME="/"
    export ACFS_HOME="$current_home/.acfs"

    getent() {
        return 2
    }

    run update_runtime_acfs_home
    assert_failure
}

@test "update_require_security: does not fall back to current HOME when different target is unresolved" {
    local current_home
    local bin_marker
    local acfs_marker
    current_home="$(create_temp_dir)"
    bin_marker="$BATS_TEST_TMPDIR/current-bin-security.marker"
    acfs_marker="$BATS_TEST_TMPDIR/current-acfs-security.marker"

    mkdir -p "$current_home/.local/bin" "$current_home/.acfs/scripts/lib"

    cat > "$current_home/.local/bin/security.sh" <<EOF
#!/usr/bin/env bash
load_checksums() {
    : > "$bin_marker"
    return 0
}
EOF
    chmod +x "$current_home/.local/bin/security.sh"

    cat > "$current_home/.acfs/scripts/lib/security.sh" <<EOF
#!/usr/bin/env bash
load_checksums() {
    : > "$acfs_marker"
    return 0
}
EOF
    chmod +x "$current_home/.acfs/scripts/lib/security.sh"

    export HOME="$current_home"
    export TARGET_USER="missinguser"
    export TARGET_HOME="/"
    export ACFS_BIN_DIR="$current_home/.local/bin"
    export ACFS_HOME="$current_home/.acfs"
    unset ACFS_REPO_ROOT
    export CHECKSUMS_LOCAL="$current_home/checksums.yaml"
    UPDATE_SECURITY_READY=false

    refresh_checksums() {
        return 0
    }

    getent() {
        return 2
    }

    run update_require_security
    assert_failure
    [[ ! -e "$bin_marker" ]]
    [[ ! -e "$acfs_marker" ]]
}

@test "refresh_checksums: does not fall back to current HOME when different target is unresolved" {
    local current_home
    local curl_marker
    current_home="$(create_temp_dir)"
    curl_marker="$BATS_TEST_TMPDIR/refresh-curl.marker"

    mkdir -p "$current_home/.acfs"

    export HOME="$current_home"
    export TARGET_USER="missinguser"
    export TARGET_HOME="/"
    export ACFS_HOME="$current_home/.acfs"
    export CHECKSUMS_LOCAL="$current_home/fallback-checksums.yaml"

    curl() {
        : > "$curl_marker"
        return 0
    }

    getent() {
        return 2
    }

    run refresh_checksums true
    assert_failure
    [[ ! -e "$curl_marker" ]]
    [[ ! -e "$current_home/.acfs/checksums.yaml" ]]
    [[ ! -e "$CHECKSUMS_LOCAL" ]]
}
