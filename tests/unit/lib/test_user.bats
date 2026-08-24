#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
    source_lib "user"
    
    # Overwrite SUDO to avoid actual sudo calls
    SUDO=""
    
    # Mock system commands
    stub_command "useradd" ""
    stub_command "usermod" ""
    stub_command "chpasswd" ""
    stub_command "visudo" ""
    stub_command "chown" ""
    stub_command "chmod" ""
    
    # Mock environment
    # Note: user.sh uses TARGET_USER not ACFS_TARGET_USER
    export TARGET_USER="testuser"
    export ACFS_TARGET_HOME=$(create_temp_dir)
    export TARGET_HOME="$ACFS_TARGET_HOME"
    export HOME=$(create_temp_dir)
    
    # We need mkdir and touch to work for some tests, so we won't stub them globally
    # unless specific tests need to verify they are called.
}

teardown() {
    common_teardown
}

@test "ensure_user: creates user if missing" {
    # Mock id to fail (user missing)
    stub_command "id" "" 1
    
    # Spy on useradd
    spy_command "useradd"
    
    # Mock openssl for password gen (optional but good to avoid dependency)
    stub_command "openssl" "randpass"
    
    run ensure_user
    assert_success
    
    run cat "$STUB_DIR/useradd.log"
    assert_output --partial "-m -s /bin/bash -G sudo testuser"
}

@test "_generate_random_password: urandom fallback survives pipefail SIGPIPE" {
    stub_command "openssl" "" 127
    stub_command "python3" "" 127

    run bash -c '
        set -euo pipefail
        source "$1/scripts/lib/logging.sh"
        source "$1/scripts/lib/user.sh"
        password="$(_generate_random_password)"
        printf "len=%s\n" "${#password}"
    ' _ "$PROJECT_ROOT"

    assert_success
    assert_output "len=32"
}

@test "ensure_user: password generator failure warns without aborting setup" {
    stub_command "id" "" 1
    spy_command "useradd"

    _generate_random_password() {
        return 1
    }

    run ensure_user
    assert_success
    assert_output --partial "Could not generate password for testuser"

    run cat "$STUB_DIR/useradd.log"
    assert_output --partial "-m -s /bin/bash -G sudo testuser"
}

@test "ensure_user: skips if exists" {
    # Mock id to succeed
    stub_command "id" "uid=1000(testuser)" 0
    
    spy_command "useradd"
    
    run ensure_user
    assert_success
    
    if [[ -f "$STUB_DIR/useradd.log" ]]; then
        fail "useradd should not be called"
    fi
}

@test "ensure_user: rejects invalid TARGET_USER before useradd" {
    export TARGET_USER="../bad user"
    spy_command "useradd"

    run ensure_user
    assert_failure
    assert_output --partial "Invalid TARGET_USER '../bad user'"

    if [[ -f "$STUB_DIR/useradd.log" ]] && [[ -s "$STUB_DIR/useradd.log" ]]; then
        fail "useradd should not be called for invalid TARGET_USER"
    fi
}

@test "enable_passwordless_sudo: validates staged content before install" {
    local staged_file="$ACFS_TARGET_HOME/sudoers-stage"
    stub_command "mktemp" "$staged_file" 0
    spy_command "chmod"
    spy_command "visudo"
    cat > "$STUB_DIR/tee" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "--" && -n "${2:-}" ]] || exit 2
cat > "$2"
EOF
    chmod +x "$STUB_DIR/tee"
    spy_command "mv"
    stub_command "rm" "" 0
    user_system_binary_path() {
        printf '%s/%s\n' "$STUB_DIR" "$1"
    }

    run enable_passwordless_sudo
    assert_success

    run cat "$staged_file"
    assert_output "testuser ALL=(ALL) NOPASSWD:ALL"

    run cat "$STUB_DIR/visudo.log"
    assert_output "-c -f $staged_file"

    run cat "$STUB_DIR/mv.log"
    assert_output "-f -- $staged_file /etc/sudoers.d/90-ubuntu-acfs"
}

@test "enable_passwordless_sudo: leaves live drop-in untouched when validation fails" {
    local staged_file="$ACFS_TARGET_HOME/invalid-sudoers-stage"
    stub_command "mktemp" "$staged_file" 0
    stub_command "chmod" "" 0
    stub_command "tee" "" 0
    spy_command "visudo" 1
    spy_command "mv"
    stub_command "rm" "" 0
    user_system_binary_path() {
        printf '%s/%s\n' "$STUB_DIR" "$1"
    }

    run enable_passwordless_sudo
    assert_failure
    assert_output --partial "was left untouched"

    if [[ -f "$STUB_DIR/mv.log" ]] && [[ -s "$STUB_DIR/mv.log" ]]; then
        fail "live sudoers replacement should not run when visudo rejects the staged file"
    fi
}

@test "enable_passwordless_sudo: rejects invalid TARGET_USER before staging" {
    export TARGET_USER="../bad user"
    spy_command "mktemp"

    run enable_passwordless_sudo
    assert_failure
    assert_output --partial "Invalid TARGET_USER '../bad user'"

    if [[ -f "$STUB_DIR/mktemp.log" ]] && [[ -s "$STUB_DIR/mktemp.log" ]]; then
        fail "mktemp should not be called for invalid TARGET_USER"
    fi
}

@test "migrate_ssh_keys: copies keys" {
    # Setup source keys
    mkdir -p "$HOME/.ssh"
    echo "ssh-rsa TESTKEY" > "$HOME/.ssh/authorized_keys"
    
    user_resolve_current_user() {
        printf "%s\n" "otheruser"
    }
    
    # Use real tee for this test (remove stub if it exists from previous tests? No, separate processes)
    # But wait, tee writes to a file owned by root usually?
    # No, we set SUDO="", so it writes as current user.
    # ACFS_TARGET_HOME is a temp dir owned by current user.
    # So real tee works.
    
    # Ensure grep is real (we didn't stub it)
    
    run migrate_ssh_keys
    assert_success
    
    assert_equal "$(cat "$ACFS_TARGET_HOME/.ssh/authorized_keys")" "ssh-rsa TESTKEY"
}

@test "migrate_ssh_keys: repairs stale TARGET_HOME from resolved target home" {
    local stale_home
    local resolved_home

    stale_home="$(create_temp_dir)"
    resolved_home="$(create_temp_dir)"
    export TARGET_HOME="$stale_home"

    mkdir -p "$HOME/.ssh"
    echo "ssh-rsa TESTKEY" > "$HOME/.ssh/authorized_keys"

    user_resolve_current_user() {
        printf '%s\n' "otheruser"
    }

    user_home_for_user() {
        [[ "${1:-}" == "testuser" ]] || return 1
        printf '%s\n' "$resolved_home"
    }

    run migrate_ssh_keys
    assert_success

    assert_equal "$(cat "$resolved_home/.ssh/authorized_keys")" "ssh-rsa TESTKEY"
    [[ ! -f "$stale_home/.ssh/authorized_keys" ]]
}

@test "migrate_ssh_keys: skips if already target user" {
    user_resolve_current_user() {
        printf "%s\n" "testuser"
    }
    
    # Spy on mkdir to ensure it wasn't called
    spy_command "mkdir"
    
    run migrate_ssh_keys
    assert_success
    
    if [[ -f "$STUB_DIR/mkdir.log" ]]; then
        fail "mkdir should not be called"
    fi
}

@test "migrate_ssh_keys: root repair guidance quotes custom target home" {
    local custom_home="$BATS_TEST_TMPDIR/target home; dollar \$bad"
    local local_home=""
    local root_command=""
    local ssh_stub_dir=""
    local quoted_ssh_dir=""
    local quoted_authorized_keys=""

    export TARGET_HOME="$custom_home"
    export HOME="$(create_temp_dir)"
    export ACFS_CI=false

    user_resolve_current_user() {
        printf '%s\n' "root"
    }

    user_home_for_user() {
        [[ "${1:-}" == "testuser" ]] || return 1
        printf '%s\n' "$custom_home"
    }

    printf -v quoted_ssh_dir '%q' "$custom_home/.ssh"
    printf -v quoted_authorized_keys '%q' "$custom_home/.ssh/authorized_keys"

    run migrate_ssh_keys
    assert_success

    root_command="$(printf '%s\n' "$output" | sed -n 's/^    \(cat .*ssh root@YOUR_SERVER_IP .*\)$/\1/p')"
    [[ -n "$root_command" ]]

    local_home="$(create_temp_dir)"
    mkdir -p "$local_home/.ssh"
    printf 'ssh-ed25519 AAAATEST acfs\n' > "$local_home/.ssh/acfs_ed25519.pub"

    ssh_stub_dir="$(create_temp_dir)"
    cat > "$ssh_stub_dir/ssh" <<'EOF'
#!/usr/bin/env bash
printf 'argc=%s\n' "$#"
printf 'target=%s\n' "${1:-}"
printf 'remote=%s\n' "${2:-}"
EOF
    chmod +x "$ssh_stub_dir/ssh"

    run env HOME="$local_home" PATH="$ssh_stub_dir:$PATH" bash -c "$root_command"
    assert_success
    assert_output --partial "argc=2"
    assert_output --partial "target=root@YOUR_SERVER_IP"
    assert_output --partial "test ! -L $quoted_ssh_dir"
    assert_output --partial "tail -c 1 $quoted_authorized_keys"
    assert_output --partial '\$bad'
}

@test "migrate_ssh_keys: tolerates unset HOME when current user is not target" {
    local resolved_home

    resolved_home="$(create_temp_dir)"
    export TARGET_HOME="$resolved_home"
    export ACFS_CI=false
    unset HOME

    user_resolve_current_user() {
        printf '%s\n' "otheruser"
    }

    user_home_for_user() {
        [[ "${1:-}" == "testuser" ]] || return 1
        printf '%s\n' "$resolved_home"
    }

    run migrate_ssh_keys
    assert_success
    refute_output --partial "unbound variable"
    assert_output --partial "No SSH keys found to migrate to testuser user"
    assert_output --partial "passwordless sudo is not a login password"
    assert_output --partial "use the root fallback:"
}

@test "user_home_for_user: rejects invalid fallback usernames" {
    export HOME="/"

    getent() {
        return 2
    }

    run user_home_for_user "../bad-user"
    assert_failure
}

@test "user_home_for_user: does not guess dotted home paths" {
    export HOME="/"

    getent() {
        return 2
    }

    run user_home_for_user "john.doe"
    assert_failure
}

@test "user_home_for_user: ignores function-poisoned passwd and identity shims" {
    local current_user=""
    local current_home=""

    current_user="$(command id -un 2>/dev/null || command whoami 2>/dev/null)"
    [[ -n "$current_user" ]] || skip "Could not resolve current user"
    [[ "$current_user" != "root" ]] || skip "Test requires a non-root current user"

    current_home="$(command getent passwd "$current_user" | cut -d: -f6)"
    [[ -n "$current_home" ]] || skip "Could not resolve current home"
    export HOME="$current_home"

    getent() {
        printf '%s\n' 'poisoned:x:0:0::/tmp/poisoned:/bin/bash'
    }
    id() {
        printf '%s\n' 'poisoned'
    }
    whoami() {
        printf '%s\n' 'poisoned'
    }

    run user_home_for_user "$current_user"
    assert_success
    assert_output "$current_home"
}

@test "user_home_for_user: current HOME fallback cannot override explicit target home" {
    local current_home
    local target_home

    current_home="$(create_temp_dir)"
    target_home="$(create_temp_dir)"
    export HOME="$current_home"

    user_lookup_passwd_home() {
        return 1
    }

    user_resolve_current_user() {
        printf 'tester\n'
    }

    run user_home_for_user "tester" "$target_home"
    assert_failure

    run user_home_for_user "tester" "$current_home"
    assert_success
    assert_output "$current_home"
}

@test "set_default_shell: external handoff uses passwd home over stale TARGET_HOME" {
    local managed_user="acfs-managed-user"
    local stale_home
    local resolved_home

    stale_home="$(create_temp_dir)"
    resolved_home="$(create_temp_dir)"
    export TARGET_USER="$managed_user"
    export TARGET_HOME="$stale_home"

    user_getent_passwd_entry() {
        [[ "${1:-}" == "$managed_user" ]] || return 1
        printf '%s:x:1000:1000::%s:/bin/bash\n' "$managed_user" "$resolved_home"
    }

    run set_default_shell /bin/bash
    assert_success

    grep -q 'ACFS externally-managed shell handoff' "$resolved_home/.bashrc"
    [[ ! -f "$stale_home/.bashrc" ]]
}

@test "set_default_shell: external handoff ignores marker-only comments" {
    local managed_user="acfs-managed-user"
    local stale_home
    local resolved_home

    stale_home="$(create_temp_dir)"
    resolved_home="$(create_temp_dir)"
    export TARGET_USER="$managed_user"
    export TARGET_HOME="$stale_home"

    cat > "$resolved_home/.bashrc" <<'EOF'
# ACFS externally-managed shell handoff
# Historical note only; no active zsh handoff lives here.
EOF

    user_getent_passwd_entry() {
        [[ "${1:-}" == "$managed_user" ]] || return 1
        printf '%s:x:1000:1000::%s:/bin/bash\n' "$managed_user" "$resolved_home"
    }

    run set_default_shell /bin/bash
    assert_success

    grep -Fq 'exec "$(command -v zsh)" -l' "$resolved_home/.bashrc"
    [[ ! -f "$stale_home/.bashrc" ]]
}

@test "user.sh: sourcing leaves TARGET_HOME empty when unresolved" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        set -euo pipefail
        getent() { return 2; }
        HOME="/"
        TARGET_USER="john.doe"
        TARGET_HOME=""
        source "$PROJECT_ROOT/scripts/lib/logging.sh"
        source "$PROJECT_ROOT/scripts/lib/user.sh"
        printf "target_home=%s\n" "${TARGET_HOME:-}"
    '
    assert_success
    assert_output "target_home="
}

@test "user.sh: sourcing clears stale TARGET_HOME when target is unresolved" {
    local stale_home
    stale_home="$(create_temp_dir)"

    run env PROJECT_ROOT="$PROJECT_ROOT" TARGET_USER="john.doe" TARGET_HOME="$stale_home" HOME="$stale_home" bash -c '
        set -euo pipefail
        getent() { return 2; }
        id() { printf "caller\n"; }
        whoami() { printf "caller\n"; }
        source "$PROJECT_ROOT/scripts/lib/logging.sh"
        source "$PROJECT_ROOT/scripts/lib/user.sh"
        printf "target_home=%s\n" "${TARGET_HOME:-}"
    '
    assert_success
    assert_output "target_home="
}

@test "user.sh: sourcing preserves explicit TARGET_HOME for current target without passwd" {
    run grep -F 'elif [[ -n "$_ACFS_USER_EXPLICIT_TARGET_HOME" ]] && [[ "$TARGET_USER" == "$_ACFS_USER_CURRENT_USER" ]]; then' "$PROJECT_ROOT/scripts/lib/user.sh"
    assert_success
}

@test "prompt_ssh_key: --yes keeps existing root keys without prompting" {
    local root_keys="$BATS_TEST_TMPDIR/root_authorized_keys"
    printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey acfs\n' > "$root_keys"

    export ACFS_TEST_MODE=1
    export ACFS_TEST_ROOT_AUTHORIZED_KEYS="$root_keys"
    export YES_MODE=true

    run prompt_ssh_key
    assert_success
    assert_output --partial "SSH keys already present"
    assert_output --partial "--yes mode"
}

@test "prompt_ssh_key: --yes skips missing root keys without prompting" {
    command -v setsid >/dev/null || skip "setsid is required to detach /dev/tty"

    export ACFS_TEST_MODE=1
    export ACFS_TEST_ROOT_AUTHORIZED_KEYS="$BATS_TEST_TMPDIR/missing_authorized_keys"
    export YES_MODE=true

    run env PROJECT_ROOT="$PROJECT_ROOT" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" setsid bash -c '
        export ACFS_TEST_MODE=1
        export ACFS_TEST_ROOT_AUTHORIZED_KEYS="$BATS_TEST_TMPDIR/missing_authorized_keys"
        export TARGET_USER=testuser
        export YES_MODE=true
        source "$PROJECT_ROOT/scripts/lib/logging.sh"
        source "$PROJECT_ROOT/scripts/lib/user.sh"
        prompt_ssh_key </dev/null
    '
    assert_success
    assert_output --partial "No SSH public key found for root"
    assert_output --partial "skipping SSH key prompt in --yes mode"
}

@test "prompt_ssh_key: --yes prompts for missing root key when a tty is available" {
    command -v script >/dev/null || skip "script is required to allocate a tty"

    local root_keys="$BATS_TEST_TMPDIR/root_authorized_keys"
    local runner="$BATS_TEST_TMPDIR/prompt_key_runner.sh"
    local pubkey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey acfs"

    cat > "$runner" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export ACFS_TEST_MODE=1
export ACFS_TEST_ROOT_AUTHORIZED_KEYS="$ROOT_KEYS"
export TARGET_USER=testuser
export YES_MODE=true
source "$PROJECT_ROOT/scripts/lib/logging.sh"
source "$PROJECT_ROOT/scripts/lib/user.sh"
prompt_ssh_key
printf 'stored=%s\n' "$(cat "$ROOT_KEYS")"
EOF
    chmod +x "$runner"

    run env PROJECT_ROOT="$PROJECT_ROOT" ROOT_KEYS="$root_keys" RUNNER="$runner" PUBKEY="$pubkey" bash -c \
        'printf "%s\n" "$PUBKEY" | script -qfec "$RUNNER" /dev/null'

    assert_success
    assert_output --partial "prompting for one even in --yes mode"
    assert_output --partial "SSH key installed successfully"
    assert_output --partial "after install, reconnect with the matching private key:"
    assert_output --partial "ssh -i ~/.ssh/your_key testuser@<this_ip>"
    refute_output --partial "ssh -i ~/.ssh/your_key root@<this_ip>"
    assert_output --partial "stored=$pubkey"
}

@test "prompt_ssh_key: --yes missing root keys sets final SSH warning" {
    command -v setsid >/dev/null || skip "setsid is required to detach /dev/tty"

    run env PROJECT_ROOT="$PROJECT_ROOT" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" setsid bash -c '
        set -euo pipefail
        source "$PROJECT_ROOT/scripts/lib/logging.sh"
        source "$PROJECT_ROOT/scripts/lib/user.sh"
        export ACFS_TEST_MODE=1
        export ACFS_TEST_ROOT_AUTHORIZED_KEYS="$BATS_TEST_TMPDIR/missing_authorized_keys"
        export TARGET_USER=testuser
        export YES_MODE=true
        prompt_ssh_key
        printf "warning=%s\n" "${ACFS_SSH_KEY_WARNING:-}"
    '
    assert_success
    assert_output --partial "warning=true"
}

@test "prompt_ssh_key: noninteractive missing root keys sets final SSH warning" {
    command -v setsid >/dev/null || skip "setsid is required to detach /dev/tty"

    run env PROJECT_ROOT="$PROJECT_ROOT" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" setsid bash -c '
        set -euo pipefail
        source "$PROJECT_ROOT/scripts/lib/logging.sh"
        source "$PROJECT_ROOT/scripts/lib/user.sh"
        export ACFS_TEST_MODE=1
        export ACFS_TEST_ROOT_AUTHORIZED_KEYS="$BATS_TEST_TMPDIR/missing_authorized_keys"
        export TARGET_USER=testuser
        export YES_MODE=false
        prompt_ssh_key </dev/null
        printf "warning=%s\n" "${ACFS_SSH_KEY_WARNING:-}"
    '
    assert_success
    assert_output --partial "Non-interactive mode detected"
    assert_output --partial "final summary's root fallback"
    assert_output --partial "warning=true"
}

@test "migrate_ssh_keys: fails closed when TARGET_HOME is unresolved" {
    mkdir -p "$HOME/.ssh"
    echo "ssh-rsa TESTKEY" > "$HOME/.ssh/authorized_keys"

    export TARGET_HOME=""
    stub_command "whoami" "otheruser"

    getent() {
        return 2
    }

    run migrate_ssh_keys
    assert_failure
    assert_output --partial "Unable to resolve TARGET_HOME for 'testuser'"
}
