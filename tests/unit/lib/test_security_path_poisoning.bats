#!/usr/bin/env bats
# ============================================================
# Unit tests for privileged PATH poisoning protection in install.sh (bd-x2p8o)
# ============================================================

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
}

teardown() {
    common_teardown
}

create_poison_shims() {
    local poison_dir="$1"
    local marker_dir="$2"
    mkdir -p "$poison_dir" "$marker_dir"

    local cmd
    for cmd in dirname mktemp grep tail awk sed chmod chown install ln mkdir cp rm sudo id whoami getent env; do
        cat > "$poison_dir/$cmd" <<EOF
#!/bin/sh
printf '%s\n' "$cmd" >> "$marker_dir/poisoned.log"
real_bin="/usr/bin/$cmd"
[ -x "\$real_bin" ] || real_bin="/bin/$cmd"
if [ -x "\$real_bin" ]; then
    exec "\$real_bin" "\$@"
fi
exit 0
EOF
        chmod +x "$poison_dir/$cmd"
    done
}

@test "security: early PATH sanitization strips caller-injected directories" {
    local poison_dir="$BATS_TEST_TMPDIR/poison"
    local marker_dir="$BATS_TEST_TMPDIR/markers"
    create_poison_shims "$poison_dir" "$marker_dir"

    run env PATH="$poison_dir:$PATH" bash -c '
        _ACFS_EARLY_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
        export PATH="$_ACFS_EARLY_PATH"
        unset _ACFS_EARLY_PATH

        printf "PATH:%s\n" "$PATH"
    '
    assert_success
    refute_output --partial "$poison_dir"
    [[ ! -f "$marker_dir/poisoned.log" ]]
}

@test "security: privileged bootstrap resolution excludes locally managed prefixes" {
    local interpreter_line
    local early_path_line
    local resolver_body

    interpreter_line="$(sed -n '1p' "$PROJECT_ROOT/install.sh")"
    early_path_line="$(grep '^_ACFS_EARLY_PATH=' "$PROJECT_ROOT/install.sh")"
    resolver_body="$(awk '
        /^acfs_early_system_binary_path\(\) \{/ { capture=1 }
        capture { print }
        capture && /^}/ { exit }
    ' "$PROJECT_ROOT/install.sh")"

    [[ "$interpreter_line" == '#!/bin/bash' ]]
    [[ "$early_path_line" == '_ACFS_EARLY_PATH="/usr/sbin:/usr/bin:/sbin:/bin"' ]]
    [[ "$resolver_body" != *'/usr/local/'* ]]
    [[ "$resolver_body" != *'/opt/homebrew/'* ]]
}

@test "security: autofix restore resolution excludes locally managed prefixes" {
    local privileged_path_line
    local resolver_body

    privileged_path_line="$(grep '^readonly AUTOFIX_PRIVILEGED_PATH=' "$PROJECT_ROOT/scripts/lib/autofix.sh")"
    resolver_body="$(awk '
        /^autofix_system_binary_path\(\) \{/ { capture=1 }
        capture { print }
        capture && /^}/ { exit }
    ' "$PROJECT_ROOT/scripts/lib/autofix.sh")"

    [[ "$resolver_body" != *'/usr/local/'* ]]
    [[ "$resolver_body" != *'/opt/homebrew/'* ]]
    [[ "$privileged_path_line" == 'readonly AUTOFIX_PRIVILEGED_PATH="/usr/sbin:/usr/bin:/sbin:/bin"' ]]

    local undo_body
    undo_body="$(awk '
        /^undo_change\(\) \{/ { capture=1 }
        capture { print }
        capture && /^}/ { exit }
    ' "$PROJECT_ROOT/scripts/lib/autofix.sh")"
    [[ "$undo_body" == *'local rollback_path="$AUTOFIX_PRIVILEGED_PATH"'* ]]
    [[ "$undo_body" == *'if [[ "$EUID" -ne 0 && "$requires_root" != "true" ]]'* ]]
}

@test "security: doctor fixes resolve privileged tools only from OS-owned prefixes" {
    local lifecycle_resolver_body
    local resolver_body
    resolver_body="$(awk '
        /^doctor_fix_system_binary_path\(\)/ { in_resolver = 1 }
        in_resolver { print }
        in_resolver && /^}/ { exit }
    ' "$PROJECT_ROOT/scripts/lib/doctor_fix.sh")"

    [[ "$resolver_body" != *'/usr/local/bin/'* ]]
    [[ "$resolver_body" != *'/usr/local/sbin/'* ]]

    lifecycle_resolver_body="$(awk '
        /^doctor_fix_lifecycle_binary_path\(\)/ { in_resolver = 1 }
        in_resolver { print }
        in_resolver && /^}/ { exit }
    ' "$PROJECT_ROOT/scripts/lib/doctor_fix.sh")"
    [[ "$lifecycle_resolver_body" == *'if [[ $EUID -eq 0 ]]'* ]]
    [[ "$lifecycle_resolver_body" == *'doctor_fix_system_binary_path "$name"'* ]]

    run grep -nE '"\$\{root_cmd\[@\]\}" env([[:space:]]|$)' "$PROJECT_ROOT/scripts/lib/doctor_fix.sh"
    [ "$status" -eq 1 ]

    run grep -nE '^[[:space:]]*(nohup env|systemctl --user|ps -p|readlink -f|rm -f "\$fallback_pid_file"|sleep 1)([[:space:]]|$)' "$PROJECT_ROOT/scripts/lib/doctor_fix.sh"
    [ "$status" -eq 1 ]
}

@test "security: global wrapper uses a fixed interpreter and OS-owned tool paths" {
    run head -n 1 "$PROJECT_ROOT/scripts/acfs-global"
    [ "$status" -eq 0 ]
    [ "$output" = "#!/bin/bash" ]

    run awk '
        /^system_binary_path\(\)/ { in_resolver = 1 }
        in_resolver { print }
        in_resolver && /^}/ { exit }
    ' "$PROJECT_ROOT/scripts/acfs-global"
    [ "$status" -eq 0 ]
    [[ "$output" != *'/usr/local/bin/'* ]]
    [[ "$output" != *'/usr/local/sbin/'* ]]
}

@test "security: doctor drops direct root execution before sourcing target-user helpers" {
    run head -n 1 "$PROJECT_ROOT/scripts/lib/doctor.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "#!/bin/bash" ]

    local drop_line
    local first_source_line
    local source_line
    drop_line="$(grep -n '_acfs_doctor_reexec_as_target_if_root "\$@"' "$PROJECT_ROOT/scripts/lib/doctor.sh" | tail -n 1 | cut -d: -f1)"
    first_source_line="$(grep -n '_acfs_doctor_source_first "output.sh"' "$PROJECT_ROOT/scripts/lib/doctor.sh" | cut -d: -f1)"
    source_line="$(grep -n '_acfs_doctor_source_first "doctor_fix.sh"' "$PROJECT_ROOT/scripts/lib/doctor.sh" | cut -d: -f1)"

    [[ -n "$drop_line" && -n "$first_source_line" && -n "$source_line" ]]
    [[ "$drop_line" -lt "$first_source_line" ]]
    [[ "$drop_line" -lt "$source_line" ]]
    grep -Fq 'readonly _ACFS_DOCTOR_PRIVILEGED_PATH="/usr/sbin:/usr/bin:/sbin:/bin"' \
        "$PROJECT_ROOT/scripts/lib/doctor.sh"
}

@test "security: early sudo resolution ignores an inherited executable override" {
    local poison_dir="$BATS_TEST_TMPDIR/poison"
    local marker_dir="$BATS_TEST_TMPDIR/markers"
    create_poison_shims "$poison_dir" "$marker_dir"

    run env SUDO="$poison_dir/sudo" bash -c '
        eval "$(awk '\''/^acfs_early_system_binary_path\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_early_sudo_binary_path\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"

        resolved="$(acfs_early_sudo_binary_path 2>/dev/null || true)"
        printf "RESOLVED:%s\n" "$resolved"
        [[ "$resolved" != "$SUDO" ]]
    '

    assert_success
    refute_output --partial "RESOLVED:$poison_dir/sudo"
    [[ ! -f "$marker_dir/poisoned.log" ]]
}

@test "security: SCRIPT_DIR discovery does not invoke caller-poisoned shims" {
    local poison_dir="$BATS_TEST_TMPDIR/poison"
    local marker_dir="$BATS_TEST_TMPDIR/markers"
    create_poison_shims "$poison_dir" "$marker_dir"

    local test_script="$BATS_TEST_TMPDIR/fake_install.sh"
    cat > "$test_script" <<'EOF'
#!/usr/bin/env bash
_ACFS_EARLY_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH="$_ACFS_EARLY_PATH"
unset _ACFS_EARLY_PATH

acfs_early_system_binary_path() {
    local name="${1:-}"
    local candidate=""
    for candidate in "/usr/bin/$name" "/bin/$name" "/usr/sbin/$name" "/sbin/$name"; do
        [[ -x "$candidate" ]] || continue
        echo "$candidate"
        return 0
    done
    return 1
}

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)" || {
        _dirname_bin="$(acfs_early_system_binary_path dirname 2>/dev/null || true)"
        if [[ -n "$_dirname_bin" ]]; then
            SCRIPT_DIR="$(cd "$("$_dirname_bin" "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
        fi
        unset _dirname_bin
    }
fi
printf "SCRIPT_DIR:%s\n" "$SCRIPT_DIR"
EOF
    chmod +x "$test_script"

    run env PATH="$poison_dir:$PATH" bash "$test_script"
    assert_success
    assert_output --partial "SCRIPT_DIR:$BATS_TEST_TMPDIR"
    [[ ! -f "$marker_dir/poisoned.log" ]]

    # Test pipe-based discovery (stdin)
    run env PATH="$poison_dir:$PATH" bash -c 'cat "'"$test_script"'" | bash -s'
    assert_success
    assert_output --partial "SCRIPT_DIR:"
    [[ ! -f "$marker_dir/poisoned.log" ]]
}

@test "security: bootstrap retry and header parsing does not execute poisoned shims" {
    local poison_dir="$BATS_TEST_TMPDIR/poison"
    local marker_dir="$BATS_TEST_TMPDIR/markers"
    create_poison_shims "$poison_dir" "$marker_dir"

    run env PATH="$poison_dir:$PATH" bash -c '
        _ACFS_EARLY_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
        export PATH="$_ACFS_EARLY_PATH"
        unset _ACFS_EARLY_PATH

        log_error() { echo "ERROR: $*" >&2; }
        log_detail() { echo "DETAIL: $*" >&2; }

        eval "$(awk '\''/^acfs_early_system_binary_path\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_retry_after_seconds\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"

        hdr_file="$1/headers.txt"
        printf "HTTP/1.1 429 Too Many Requests\r\nRetry-After: 45\r\n\r\n" > "$hdr_file"
        delay="$(acfs_retry_after_seconds "$hdr_file")"
        printf "DELAY:%s\n" "$delay"
    ' _ "$BATS_TEST_TMPDIR"

    assert_success
    assert_output --partial "DELAY:45"
    [[ ! -f "$marker_dir/poisoned.log" ]]
}

@test "security: trusted bootstrap resolution never falls back to bare command names" {
    run grep -nE 'acfs_early_system_binary_path [^[:space:]]+.*\|\| echo [A-Za-z0-9._+-]+' "$PROJECT_ROOT/install.sh"

    assert_failure
    refute_output --partial "|| echo"
}

@test "security: primary-bin directory and link helpers use trusted system binaries" {
    local poison_dir="$BATS_TEST_TMPDIR/poison"
    local marker_dir="$BATS_TEST_TMPDIR/markers"
    local target_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$target_home"
    create_poison_shims "$poison_dir" "$marker_dir"

    run env PATH="$poison_dir:$PATH" HOME="$target_home" TARGET_HOME="$target_home" TARGET_USER="$(whoami)" ACFS_BIN_DIR="$target_home/.local/bin" bash -c '
        _ACFS_EARLY_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
        export PATH="$_ACFS_EARLY_PATH"
        unset _ACFS_EARLY_PATH

        log_error() { echo "ERROR: $*" >&2; }
        log_detail() { echo "DETAIL: $*" >&2; }

        eval "$(awk '\''/^acfs_early_system_binary_path\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_early_sudo_binary_path\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_early_resolve_current_user\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_early_getent_passwd_entry\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_home_for_user\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_primary_bin_dir_uses_root\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^_acfs_primary_bin_tool_path\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^_acfs_run_root_bin_command\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_ensure_primary_bin_dir\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_link_primary_bin_command\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_install_executable_into_primary_bin\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^run_as_target\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"

        acfs_ensure_primary_bin_dir
        [[ -d "$TARGET_HOME/.local/bin" ]]

        src_script="$1/sample.sh"
        printf "%s\n" "#!/bin/sh" "echo hello" > "$src_script"
        chmod +x "$src_script"

        acfs_link_primary_bin_command "$src_script" "sample_cmd"
        [[ -L "$TARGET_HOME/.local/bin/sample_cmd" ]]

        acfs_install_executable_into_primary_bin "$src_script" "sample_inst"
        [[ -x "$TARGET_HOME/.local/bin/sample_inst" ]]
    ' _ "$BATS_TEST_TMPDIR"

    assert_success
    [[ ! -f "$marker_dir/poisoned.log" ]]
}

@test "security: target-home executable installs never write as root" {
    local function_body
    function_body="$(awk '
        /^acfs_install_executable_into_primary_bin\(\) \{/ { capture=1 }
        capture { print }
        capture && /^}/ { exit }
    ' "$PROJECT_ROOT/install.sh")"

    [[ "$function_body" == *'run_as_target "$install_bin" -m 0755 "$src_path" "$dest_path"'* ]]
    [[ "$function_body" != *'chown_bin'* ]]
    [[ "$function_body" != *'if [[ $EUID -eq 0 ]]'* ]]
}

@test "security: run_as_target explicitly passes target PATH without caller poison" {
    local poison_dir="$BATS_TEST_TMPDIR/poison"
    local marker_dir="$BATS_TEST_TMPDIR/markers"
    local target_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$target_home"
    create_poison_shims "$poison_dir" "$marker_dir"

    run env PATH="$poison_dir:$PATH" HOME="$target_home" TARGET_HOME="$target_home" TARGET_USER="$(whoami)" ACFS_BIN_DIR="$target_home/.local/bin" bash -c '
        _ACFS_EARLY_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
        export PATH="$_ACFS_EARLY_PATH"
        unset _ACFS_EARLY_PATH

        log_error() { echo "ERROR: $*" >&2; }
        log_detail() { echo "DETAIL: $*" >&2; }

        eval "$(awk '\''/^acfs_early_system_binary_path\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_early_sudo_binary_path\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_early_resolve_current_user\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_early_getent_passwd_entry\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_home_for_user\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^run_as_target\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"

        target_path="$(run_as_target bash -c "printf \"%s\" \"\$PATH\"")"
        printf "TARGET_PATH:%s\n" "$target_path"
    '

    assert_success
    assert_output --partial "TARGET_PATH:$target_home/.local/bin"
    refute_output --partial "$poison_dir"
    [[ ! -f "$marker_dir/poisoned.log" ]]
}
