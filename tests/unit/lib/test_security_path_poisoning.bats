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

# Copy install.sh's REAL side-effect-free prelude (PATH sanitization, startup
# hook scrub, early helpers, SCRIPT_DIR discovery) to $1, so the tests below
# exercise the shipped code instead of a hand-maintained replica of it.
write_real_install_prelude() {
    local out="$1"
    awk '{ print } /^SCRIPT_DIR=""$/ { in_script_dir = 1 } in_script_dir && /^fi$/ { exit }' \
        "$PROJECT_ROOT/install.sh" > "$out"
    grep -qx 'SCRIPT_DIR=""' "$out" || { echo "install.sh prelude extraction lost SCRIPT_DIR discovery" >&2; return 1; }
    [[ "$(tail -n 1 "$out")" == "fi" ]] || { echo "install.sh prelude extraction did not end at SCRIPT_DIR discovery" >&2; return 1; }
}

@test "security: early PATH sanitization strips caller-injected directories" {
    local poison_dir="$BATS_TEST_TMPDIR/poison"
    local marker_dir="$BATS_TEST_TMPDIR/markers"
    local prelude="$BATS_TEST_TMPDIR/install.sh"
    create_poison_shims "$poison_dir" "$marker_dir"
    write_real_install_prelude "$prelude"
    printf '%s\n' 'printf "PATH:%s\n" "$PATH"' >> "$prelude"

    # Local-file and curl-pipe entry must reach the same sanitized PATH.
    run env PATH="$poison_dir:$PATH" bash "$prelude"
    assert_success
    assert_output "PATH:/usr/sbin:/usr/bin:/sbin:/bin"

    run env PATH="$poison_dir:$PATH" bash -c 'bash -s < "$1"' _ "$prelude"
    assert_success
    assert_output "PATH:/usr/sbin:/usr/bin:/sbin:/bin"
    [[ ! -f "$marker_dir/poisoned.log" ]]
}

@test "security: cleanup never trusts inherited temporary paths" {
    local sentinel_dir="$BATS_TEST_TMPDIR/inherited-directory"
    local archive_sentinel="$BATS_TEST_TMPDIR/inherited-archive"
    local install_sentinel="$BATS_TEST_TMPDIR/inherited-install"
    mkdir -p "$sentinel_dir"
    printf '%s\n' "archive sentinel" > "$archive_sentinel"
    printf '%s\n' "install sentinel" > "$install_sentinel"

    run env \
        ACFS_TMP_ARCHIVE="$archive_sentinel" \
        ACFS_TMP_INSTALL="$install_sentinel" \
        ACFS_TMP_SLB="$sentinel_dir" \
        bash "$PROJECT_ROOT/install.sh" --help

    assert_success
    [[ -d "$sentinel_dir" ]]
    [[ "$(cat "$archive_sentinel")" == "archive sentinel" ]]
    [[ "$(cat "$install_sentinel")" == "install sentinel" ]]
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

@test "security: verified-installer PATH is sudo secure_path in both run_as_target copies (#386)" {
    # The clean-environment runner hands verified upstream installers a fixed
    # PATH. It must stay free of caller and user-writable entries, but it must
    # include /usr/local/{s,}bin: installers that `sudo make install` into
    # /usr/local/bin and then `command -v` their own binary (SRPS ananicy-cpp)
    # failed on every run when the sanitized PATH omitted it.
    local expected='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin'
    local file body prefix_line
    for file in "$PROJECT_ROOT/install.sh" "$PROJECT_ROOT/scripts/lib/install_helpers.sh"; do
        body="$(awk '
            /^[[:space:]]*run_as_target\(\) \{/ { capture=1 }
            capture { print }
            capture && /^[[:space:]]*local -a env_args=/ { exit }
        ' "$file")"
        [[ -n "$body" ]] || fail "run_as_target PATH block not found in $file"
        prefix_line="$(grep -E '^[[:space:]]*local system_path_prefix=' <<< "$body")"
        [[ "$prefix_line" == *"\"$expected\""* ]] \
            || fail "$file: system_path_prefix is not sudo secure_path: $prefix_line"
        grep -Eq '^[[:space:]]*command_path="\$system_path_prefix"$' <<< "$body" \
            || fail "$file: clean-environment command_path must be exactly the system prefix"
        [[ "$body" != *'command_path="/usr/sbin:/usr/bin:/sbin:/bin"'* ]] \
            || fail "$file: clean-environment PATH regressed to the OS-only set (drops /usr/local/bin)"
        # The non-clean target-user PATH must also carry the system prefix
        # explicitly instead of trusting an already-sanitized caller PATH.
        grep -Eq '^[[:space:]]*local command_path="\$target_path_prefix:\$system_path_prefix' <<< "$body" \
            || fail "$file: target-user PATH does not include the system prefix explicitly"
    done
}

@test "security: autofix restore resolution excludes locally managed prefixes" {
    local resolver_body

    resolver_body="$(awk '
        /^autofix_system_binary_path\(\) \{/ { capture=1 }
        capture { print }
        capture && /^}/ { exit }
    ' "$PROJECT_ROOT/scripts/lib/autofix.sh")"

    [[ "$resolver_body" != *'/usr/local/'* ]]
    [[ "$resolver_body" != *'/opt/homebrew/'* ]]

    # Loaded (and re-loaded after clearing the guard), the privileged PATH is
    # the OS-only set and read-only.
    run bash -ec 'source "$1"; unset _ACFS_AUTOFIX_SOURCED; source "$1" || exit 9
        [[ "$AUTOFIX_PRIVILEGED_PATH" == "/usr/sbin:/usr/bin:/sbin:/bin" ]] || exit 8
        (AUTOFIX_PRIVILEGED_PATH=/evil) 2>/dev/null && exit 7
        [[ "$AUTOFIX_PRIVILEGED_PATH" == "/usr/sbin:/usr/bin:/sbin:/bin" ]]' _ "$PROJECT_ROOT/scripts/lib/autofix.sh"
    assert_success

    # A caller-supplied read-only value is refused rather than used.
    run bash -c 'readonly AUTOFIX_PRIVILEGED_PATH=/evil; source "$1"; status=$?
        printf "status=%s sourced=%s\n" "$status" "${_ACFS_AUTOFIX_SOURCED:-unset}"' _ "$PROJECT_ROOT/scripts/lib/autofix.sh"
    assert_output --partial "status=1 sourced=unset"

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

    local test_script="$BATS_TEST_TMPDIR/install.sh"
    write_real_install_prelude "$test_script"
    printf '%s\n' 'printf "SCRIPT_DIR:%s\n" "$SCRIPT_DIR"' >> "$test_script"
    local canonical_tmpdir=""
    canonical_tmpdir="$(cd -P "$BATS_TEST_TMPDIR" && pwd -P)"

    run env PATH="$poison_dir:$PATH" bash "$test_script"
    assert_success
    assert_output "SCRIPT_DIR:$canonical_tmpdir"
    [[ ! -f "$marker_dir/poisoned.log" ]]

    # Pipe-based entry (curl | bash) has no script file and no SCRIPT_DIR.
    run env PATH="$poison_dir:$PATH" bash -c 'bash -s < "$1"' _ "$test_script"
    assert_success
    assert_output "SCRIPT_DIR:"
    [[ ! -f "$marker_dir/poisoned.log" ]]
}

@test "security: bootstrap retry and header parsing does not execute poisoned shims" {
    local poison_dir="$BATS_TEST_TMPDIR/poison"
    local marker_dir="$BATS_TEST_TMPDIR/markers"
    create_poison_shims "$poison_dir" "$marker_dir"

    # Run the real prelude (its own PATH sanitization), then the real retry
    # helper, with the caller's poisoned PATH never reset by the test itself.
    local prelude="$BATS_TEST_TMPDIR/install.sh"
    write_real_install_prelude "$prelude"
    awk '/^acfs_retry_after_seconds\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}' \
        "$PROJECT_ROOT/install.sh" >> "$prelude"
    cat >> "$prelude" <<'EOF'
log_error() { echo "ERROR: $*" >&2; }
log_detail() { echo "DETAIL: $*" >&2; }
hdr_file="$ACFS_TEST_HEADER_FILE"
printf "HTTP/1.1 429 Too Many Requests\r\nRetry-After: 45\r\n\r\n" > "$hdr_file"
printf "DELAY:%s\n" "$(acfs_retry_after_seconds "$hdr_file")"
EOF

    run env PATH="$poison_dir:$PATH" ACFS_TEST_HEADER_FILE="$BATS_TEST_TMPDIR/headers.txt" bash "$prelude"
    assert_success
    assert_output --partial "DELAY:45"
    run env PATH="$poison_dir:$PATH" ACFS_TEST_HEADER_FILE="$BATS_TEST_TMPDIR/headers.txt" bash -c 'bash -s < "$1"' _ "$prelude"
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
    local prelude="$BATS_TEST_TMPDIR/install.sh"
    mkdir -p "$target_home"
    create_poison_shims "$poison_dir" "$marker_dir"
    write_real_install_prelude "$prelude"

    # The poisoned PATH is only sanitized by install.sh's own prelude.
    run env PATH="$poison_dir:$PATH" HOME="$target_home" TARGET_HOME="$target_home" TARGET_USER="$(whoami)" ACFS_BIN_DIR="$target_home/.local/bin" ACFS_TEST_PRELUDE="$prelude" bash -c '
        source "$ACFS_TEST_PRELUDE"

        log_error() { echo "ERROR: $*" >&2; }
        log_detail() { echo "DETAIL: $*" >&2; }

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
    local prelude="$BATS_TEST_TMPDIR/install.sh"
    mkdir -p "$target_home"
    create_poison_shims "$poison_dir" "$marker_dir"
    write_real_install_prelude "$prelude"

    # The poisoned PATH is only sanitized by install.sh's own prelude.
    run env PATH="$poison_dir:$PATH" HOME="$target_home" TARGET_HOME="$target_home" TARGET_USER="$(whoami)" ACFS_BIN_DIR="$target_home/.local/bin" ACFS_TEST_PRELUDE="$prelude" bash -c '
        source "$ACFS_TEST_PRELUDE"

        log_error() { echo "ERROR: $*" >&2; }
        log_detail() { echo "DETAIL: $*" >&2; }

        eval "$(awk '\''/^acfs_early_resolve_current_user\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_early_getent_passwd_entry\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^acfs_home_for_user\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"
        eval "$(awk '\''/^run_as_target\(\) \{/{flag=1} flag; /^}$/ && flag {flag=0; exit}'\'' install.sh)"

        target_path="$(run_as_target bash -c "printf \"%s\" \"\$PATH\"")"
        printf "TARGET_PATH:%s\n" "$target_path"
    '

    # run_as_target trusts the passwd home over a caller-supplied TARGET_HOME
    # (and moves an ACFS_BIN_DIR under that stale home back to the real one),
    # so the explicit target PATH starts at the passwd home's primary bin.
    local passwd_home=""
    passwd_home="$(getent passwd "$(whoami)" | cut -d: -f6)"
    assert_success
    assert_output --partial "TARGET_PATH:$passwd_home/.local/bin:"
    refute_output --partial "$target_home"
    refute_output --partial "$poison_dir"
    [[ ! -f "$marker_dir/poisoned.log" ]]
}

@test "security: install.sh assigns the privileged process PATH exactly once" {
    # After the early sanitization, every PATH assignment must either be
    # command-scoped to the OS-only set or a target-user payload string run
    # through run_as_target. A new root-process PATH mutation fails here.
    local line=""
    local sanitize_count=0
    while IFS= read -r line; do
        case "$line" in
            *':builtin export PATH="$_ACFS_EARLY_PATH"')
                sanitize_count=$((sanitize_count + 1)) ;;
            *':'*'PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C '*) ;;
            *':'*'export PATH="${ACFS_BIN_DIR:-$HOME/.local/bin}:$HOME/.local/bin:'*) ;;
            *) fail "unexpected PATH assignment in install.sh: $line" ;;
        esac
    done < <(grep -nE '^[[:space:]]*(builtin )?(export )?PATH=' "$PROJECT_ROOT/install.sh")
    [[ "$sanitize_count" -eq 1 ]] || fail "expected exactly one early PATH sanitization, found $sanitize_count"
}

@test "security: installer, updater and autofix share one privileged PATH invariant" {
    local installer_path updater_path autofix_path
    installer_path="$(sed -n 's/^_ACFS_EARLY_PATH="\(.*\)"$/\1/p' "$PROJECT_ROOT/install.sh")"
    updater_path="$(sed -n 's/^UPDATE_PRIVILEGED_PATH="\(.*\)"$/\1/p' "$PROJECT_ROOT/scripts/lib/update.sh")"
    autofix_path="$(bash -c 'source "$1" && printf "%s" "$AUTOFIX_PRIVILEGED_PATH"' _ "$PROJECT_ROOT/scripts/lib/autofix.sh")"

    [[ "$installer_path" == "/usr/sbin:/usr/bin:/sbin:/bin" ]] || fail "installer privileged PATH: $installer_path"
    [[ "$updater_path" == "$installer_path" ]] || fail "updater privileged PATH diverged: $updater_path"
    [[ "$autofix_path" == "$installer_path" ]] || fail "autofix privileged PATH diverged: $autofix_path"
}

@test "security: root updater ignores a poisoned caller PATH (bd-fa8oi)" {
    sudo -n true 2>/dev/null || skip "requires passwordless sudo to exercise the root code path"
    local poison_dir="$BATS_TEST_TMPDIR/poison"
    local marker_dir="$BATS_TEST_TMPDIR/markers"
    create_poison_shims "$poison_dir" "$marker_dir"
    local cmd
    for cmd in git date uname cat head tr sort; do
        printf '#!/bin/sh\nprintf "%%s\\n" "%s" >> "%s/poisoned.log"\nexit 0\n' "$cmd" "$marker_dir" > "$poison_dir/$cmd"
        chmod +x "$poison_dir/$cmd"
    done
    chmod 0777 "$marker_dir"

    # Sourcing update.sh as root already runs bare utilities (git); ensure_path
    # is the per-run PATH setup used by every update category.
    run sudo -n env -i PATH="$poison_dir:/usr/sbin:/usr/bin:/sbin:/bin" HOME=/root bash -c '
        source "$1" || exit 9
        printf "PATH1:%s\n" "$PATH"
        ensure_path
        printf "PATH2:%s\n" "$PATH"
        printf "GIT:%s\n" "$(command -v git)"
    ' _ "$PROJECT_ROOT/scripts/lib/update.sh"

    assert_success
    assert_output --partial "PATH1:/usr/sbin:/usr/bin:/sbin:/bin"
    assert_output --partial "PATH2:/usr/sbin:/usr/bin:/sbin:/bin"
    refute_output --partial "$poison_dir"
    [[ ! -f "$marker_dir/poisoned.log" ]] || fail "poisoned shim ran as root: $(cat "$marker_dir/poisoned.log")"
}

@test "security: update.sh only widens PATH for non-root callers (bd-fa8oi)" {
    # Root PATH assignments are the privileged constant. The single widening
    # assignment lives in ensure_path, after its root early-return.
    local updater="$PROJECT_ROOT/scripts/lib/update.sh"
    local line=""
    local widening=0
    while IFS= read -r line; do
        case "$line" in
            *':'*'export PATH="$UPDATE_PRIVILEGED_PATH"') ;;
            *':'*'export PATH="$prefix${current_path:+:$current_path}"') widening=$((widening + 1)) ;;
            *) fail "unexpected PATH assignment in update.sh: $line" ;;
        esac
    done < <(grep -nE '^[[:space:]]*(builtin )?(export )?PATH=' "$updater")
    [[ "$widening" -eq 1 ]] || fail "expected one non-root PATH widening, found $widening"

    local ensure_path_body=""
    ensure_path_body="$(awk '/^ensure_path\(\) \{/{f=1} f{print} f && /^}/{exit}' "$updater")"
    local root_return_line widen_line
    root_return_line="$(grep -n 'export PATH="$UPDATE_PRIVILEGED_PATH"' <<< "$ensure_path_body" | head -1 | cut -d: -f1)"
    widen_line="$(grep -n 'export PATH="$prefix' <<< "$ensure_path_body" | head -1 | cut -d: -f1)"
    [[ -n "$root_return_line" && -n "$widen_line" && "$root_return_line" -lt "$widen_line" ]] \
        || fail "ensure_path must force the privileged PATH for root before any widening"
    grep -A1 'export PATH="$UPDATE_PRIVILEGED_PATH"' <<< "$ensure_path_body" | grep -q 'return 0' \
        || fail "ensure_path must return right after forcing the privileged PATH for root"
}
