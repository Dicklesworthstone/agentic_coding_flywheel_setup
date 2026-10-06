#!/usr/bin/env bats
#
# Issue #388: install.sh never exported BUN_INSTALL, so bun resolved its
# global bin dir from XDG_CACHE_HOME (~/.cache/.bun/bin on desktops that set
# it) and every `bun install -g` — codex, wrangler, vercel — landed off the
# ~/.bun/bin PATH entry ACFS itself configures. Every target-user runner now
# pins BUN_INSTALL=<target home>/.bun (the value acfs.zshrc exports), the
# "binary not found" path names bun's real global bin dir, and doctor
# detects binaries stranded in the fallback dir and can reinstall them.

load 'test_helper'

setup() {
    common_setup
    INSTALL_SH="$PROJECT_ROOT/install.sh"
    DOCTOR_SH="$PROJECT_ROOT/scripts/lib/doctor.sh"
}

teardown() {
    common_teardown
}

# ------------------------------------------------------------------
# Static: every runner that can execute `bun install -g` pins BUN_INSTALL
# ------------------------------------------------------------------

@test "both run_as_target copies pin BUN_INSTALL to the target home" {
    local file body
    for file in "$INSTALL_SH" "$PROJECT_ROOT/scripts/lib/install_helpers.sh"; do
        body="$(awk '
            /^[[:space:]]*run_as_target\(\) \{/ { capture=1 }
            capture { print }
            capture && /^[[:space:]]*local -a env_args=/ { exit }
        ' "$file")"
        [[ -n "$body" ]] || fail "run_as_target env block not found in $file"
        grep -Eq '^[[:space:]]*local -a env_args=\(.*"BUN_INSTALL=\$user_home/\.bun".*\)$' <<< "$body" \
            || fail "$file: run_as_target env_args does not pin BUN_INSTALL=\$user_home/.bun"
    done
}

@test "update and doctor-fix runners pin BUN_INSTALL to the target home" {
    grep -Eq '^[[:space:]]*local -a env_args=\(.*"BUN_INSTALL=\$target_home/\.bun".*\)$' "$PROJECT_ROOT/scripts/lib/update.sh" \
        || fail "update_run_in_target_context does not pin BUN_INSTALL"
    grep -Fq '"BUN_INSTALL=$runtime_home/.bun"' "$PROJECT_ROOT/scripts/lib/doctor_fix.sh" \
        || fail "doctor_fix_build_runtime_env_args does not pin BUN_INSTALL"
}

@test "the target-user shell PATH source exports BUN_INSTALL in lockstep with acfs.zshrc" {
    source_lib "logging"
    source_lib "install_helpers"
    run _acfs_user_path_export_source
    assert_success
    [[ "$output" == *'export BUN_INSTALL="$HOME/.bun"'* ]]
    # The shell config ACFS deploys is the source of truth for the value.
    grep -Fq 'export BUN_INSTALL="$HOME/.bun"' "$PROJECT_ROOT/acfs/zsh/acfs.zshrc" \
        || fail "acfs/zsh/acfs.zshrc no longer exports BUN_INSTALL=\$HOME/.bun; keep the runners in lockstep"
}

# ------------------------------------------------------------------
# Behavioural: the library run_as_target hands BUN_INSTALL to sudo/env
# ------------------------------------------------------------------

use_spy_sudo() {
    spy_command "sudo"
    export ACFS_TEST_SUDO_BIN="$STUB_DIR/sudo"

    _acfs_system_binary_path() {
        local name="${1:-}"
        local candidate=""
        [[ -n "$name" ]] || return 1
        if [[ "$name" == "sudo" && -n "${ACFS_TEST_SUDO_BIN:-}" && -x "$ACFS_TEST_SUDO_BIN" ]]; then
            printf '%s\n' "$ACFS_TEST_SUDO_BIN"
            return 0
        fi
        for candidate in "/usr/bin/$name" "/bin/$name" "/usr/sbin/$name" "/sbin/$name"; do
            [[ -x "$candidate" ]] || continue
            printf '%s\n' "$candidate"
            return 0
        done
        return 1
    }
}

@test "run_as_target passes BUN_INSTALL=<target home>/.bun in both normal and clean environments" {
    source_lib "logging"
    source_lib "install_helpers"
    export TARGET_USER="testuser"
    export TARGET_HOME="/home/testuser"
    export ACFS_BIN_DIR="/home/testuser/.local/bin"
    _acfs_getent_passwd_entry() {
        [[ "${1:-}" == "testuser" ]] || return 1
        printf 'testuser:x:1000:1000::/home/testuser:/bin/bash\n'
    }
    use_spy_sudo

    # A caller XDG_CACHE_HOME must not win over the explicit BUN_INSTALL.
    XDG_CACHE_HOME=/home/testuser/.cache run run_as_target env
    assert_success
    local captured
    captured="$(cat "$STUB_DIR/sudo.log")"
    [[ "$captured" == *" BUN_INSTALL=/home/testuser/.bun "* ]] \
        || fail "Expected BUN_INSTALL=/home/testuser/.bun in the target env, got: $captured"

    : > "$STUB_DIR/sudo.log"
    local script="$BATS_TEST_TMPDIR/verified-installer.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$script"
    run run_as_target --acfs-clean-environment bash "$script"
    assert_success
    captured="$(cat "$STUB_DIR/sudo.log")"
    [[ "$captured" == *" -i "*" BUN_INSTALL=/home/testuser/.bun "* ]] \
        || fail "Expected BUN_INSTALL in the clean (env -i) environment too, got: $captured"
}

@test "with real bun, run_as_target's BUN_INSTALL beats XDG_CACHE_HOME for the global bin dir" {
    command -v bun >/dev/null 2>&1 || skip "bun not installed"
    source_lib "logging"
    source_lib "install_helpers"

    local fake_home="$BATS_TEST_TMPDIR/home"
    # `bun pm -g bin` needs a global package.json to answer at all; put one
    # ONLY under ~/.bun so a fallback resolution to ~/.cache fails loudly.
    mkdir -p "$fake_home/.cache" "$fake_home/.bun/install/global"
    printf '{}\n' > "$fake_home/.bun/install/global/package.json"
    local me
    me="$(id -un)"
    export TARGET_USER="$me"
    export TARGET_HOME="$fake_home"
    export ACFS_BIN_DIR="$fake_home/.local/bin"
    _acfs_getent_passwd_entry() {
        [[ "${1:-}" == "$TARGET_USER" ]] || return 1
        printf '%s:x:%s:%s::%s:/bin/bash\n' "$TARGET_USER" "$(id -u)" "$(id -g)" "$TARGET_HOME"
    }

    # Same-user fast path: env is inherited, so a desktop XDG_CACHE_HOME is
    # present exactly as it would be on Omarchy/Arch. bun must still answer
    # ~/.bun/bin because BUN_INSTALL is pinned.
    local bun_bin
    bun_bin="$(command -v bun)"
    XDG_CACHE_HOME="$fake_home/.cache" run run_as_target "$bun_bin" pm -g bin
    [[ "$output" == *"$fake_home/.bun/bin"* ]] \
        || fail "bun resolved its global bin dir elsewhere: status=$status output=$output"
    [[ "$output" != *"/.cache/.bun/bin"* ]]
}

# ------------------------------------------------------------------
# install.sh: the "binary not found" path names bun's real global bin dir
# ------------------------------------------------------------------

load_install_bun_helpers() {
    eval "$(sed -n '/^acfs_bun_global_bin_dir_as_target() {$/,/^}$/p' "$INSTALL_SH")"
    eval "$(sed -n '/^acfs_note_bun_global_bin_mismatch() {$/,/^}$/p' "$INSTALL_SH")"
    eval "$(sed -n '/^acfs_warn_bun_global_binary_missing() {$/,/^}$/p' "$INSTALL_SH")"
    [[ "$(type -t acfs_warn_bun_global_binary_missing)" == "function" ]]
    WARN_LINES=()
    DETAIL_LINES=()
    log_warn() { WARN_LINES+=("$1"); }
    log_detail() { DETAIL_LINES+=("$1"); }
    TARGET_HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$TARGET_HOME/.bun/bin" "$TARGET_HOME/.cache/.bun/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TARGET_HOME/.bun/bin/bun"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TARGET_HOME/.cache/.bun/bin/wrangler"
    chmod +x "$TARGET_HOME/.bun/bin/bun" "$TARGET_HOME/.cache/.bun/bin/wrangler"
}

@test "binary-not-found warning names the stranded location and the BUN_INSTALL fix" {
    load_install_bun_helpers
    # bun (as run for the target user) reports the cache fallback dir.
    run_as_target() { printf '%s\n' "$TARGET_HOME/.cache/.bun/bin"; }

    acfs_warn_bun_global_binary_missing "wrangler" "wrangler@latest" "$TARGET_HOME/.bun/bin/bun"

    [[ ${#WARN_LINES[@]} -eq 1 ]]
    [[ "${WARN_LINES[0]}" == "wrangler: bun's global bin dir resolved to $TARGET_HOME/.cache/.bun/bin, not $TARGET_HOME/.bun/bin"* ]]
    [[ "${DETAIL_LINES[0]}" == "wrangler is stranded at $TARGET_HOME/.cache/.bun/bin/wrangler"* ]]
    [[ "${DETAIL_LINES[1]}" == 'Fix: BUN_INSTALL="$HOME/.bun" bun install -g --trust wrangler@latest'* ]]
}

@test "binary-not-found warning stays generic when bun agrees on the directory or cannot answer" {
    load_install_bun_helpers
    run_as_target() { printf '%s\n' "$TARGET_HOME/.bun/bin"; }
    acfs_warn_bun_global_binary_missing "vercel" "vercel@latest" "$TARGET_HOME/.bun/bin/bun"
    [[ ${#WARN_LINES[@]} -eq 1 ]]
    [[ "${WARN_LINES[0]}" == "vercel: install finished but binary not found in $TARGET_HOME/.bun/bin" ]]
    [[ ${#DETAIL_LINES[@]} -eq 0 ]]

    WARN_LINES=()
    run_as_target() { return 1; }
    acfs_warn_bun_global_binary_missing "vercel" "vercel@latest" "$TARGET_HOME/.bun/bin/bun"
    [[ "${WARN_LINES[0]}" == "vercel: install finished but binary not found in $TARGET_HOME/.bun/bin" ]]

    # The mismatch-only note (used after the required agents' log_error) is silent here.
    WARN_LINES=()
    run acfs_note_bun_global_bin_mismatch "codex" "@openai/codex@latest" "$TARGET_HOME/.bun/bin/bun"
    [[ "$status" -ne 0 ]]
    [[ -z "$output" ]]
}

@test "install.sh routes every bun global-install miss through the location-aware warning" {
    # One call site since ce5f8d8a removed the uncalled install_cloud_db_legacy copy.
    run grep -c 'acfs_warn_bun_global_binary_missing "$cli" "${cli}@latest" "$bun_bin"' "$INSTALL_SH"
    [[ "$output" -eq 1 ]]
    run grep -E 'log_warn "\$cli: install finished but binary not found"$' "$INSTALL_SH"
    [[ "$status" -ne 0 ]]
    grep -Fq 'acfs_note_bun_global_bin_mismatch "codex" "@openai/codex@latest" "$bun_bin"' "$INSTALL_SH"
    grep -Fq 'acfs_note_bun_global_bin_mismatch "claude" "@anthropic-ai/claude-code@latest" "$bun_bin"' "$INSTALL_SH"
}

# ------------------------------------------------------------------
# doctor: stranded global installs are detected and named with their package
# ------------------------------------------------------------------

load_doctor_functions() {
    local last_line=""
    last_line="$(tail -n 1 "$DOCTOR_SH")"
    [[ "$last_line" == 'main "$@"' ]] \
        || fail "doctor.sh no longer ends in 'main \"\$@\"' (got: $last_line)"
    # shellcheck disable=SC1090
    source <(sed '$d' "$DOCTOR_SH") >/dev/null 2>&1 || true
    [[ "$(type -t doctor_bun_stranded_global_binaries)" == "function" ]]
}

make_stranded_home() {
    local home="$1"
    local cache="${2:-$home/.cache}"
    mkdir -p "$home/.bun/bin" "$cache/.bun/bin" \
        "$cache/.bun/install/global/node_modules/@openai/codex/bin" \
        "$cache/.bun/install/global/node_modules/wrangler/bin" \
        "$cache/.bun/install/global/node_modules/vercel/dist"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$home/.bun/bin/bun"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$home/.bun/bin/wrangler"
    chmod +x "$home/.bun/bin/bun" "$home/.bun/bin/wrangler"
    local f
    for f in "@openai/codex/bin/codex.js" "wrangler/bin/wrangler.js" "wrangler/bin/cf-wrangler.js" "vercel/dist/vc.js"; do
        printf '#!/usr/bin/env node\n' > "$cache/.bun/install/global/node_modules/$f"
        chmod +x "$cache/.bun/install/global/node_modules/$f"
    done
    ln -s "../install/global/node_modules/@openai/codex/bin/codex.js" "$cache/.bun/bin/codex"
    ln -s "../install/global/node_modules/wrangler/bin/wrangler.js" "$cache/.bun/bin/wrangler"
    ln -s "../install/global/node_modules/wrangler/bin/cf-wrangler.js" "$cache/.bun/bin/cf-wrangler"
    ln -s "../install/global/node_modules/vercel/dist/vc.js" "$cache/.bun/bin/vercel"
    ln -s "../install/global/node_modules/vercel/dist/vc.js" "$cache/.bun/bin/vc"
    # bun's own launcher in the fallback dir is never "stranded".
    printf '#!/usr/bin/env bash\nexit 0\n' > "$cache/.bun/bin/bun"
    chmod +x "$cache/.bun/bin/bun"
}

@test "doctor lists binaries in ~/.cache/.bun/bin that are absent from ~/.bun/bin, with their packages" {
    load_doctor_functions
    local home="$BATS_TEST_TMPDIR/home"
    make_stranded_home "$home"
    export TARGET_HOME="$home"
    unset XDG_CACHE_HOME

    run doctor_bun_stranded_global_binaries
    assert_success
    # wrangler exists in ~/.bun/bin already (the reporter's partial fix) and
    # bun's own launcher is skipped; the rest are named with their package.
    [[ "$output" == *"$home/.cache/.bun/bin/codex	@openai/codex"* ]]
    [[ "$output" == *"$home/.cache/.bun/bin/cf-wrangler	wrangler"* ]]
    [[ "$output" == *"$home/.cache/.bun/bin/vercel	vercel"* ]]
    [[ "$output" == *"$home/.cache/.bun/bin/vc	vercel"* ]]
    [[ "$output" != *"/.cache/.bun/bin/wrangler	"* ]]
    [[ "$output" != *"/.cache/.bun/bin/bun	"* ]]
}

@test "doctor honours XDG_CACHE_HOME as the fallback dir and reports nothing when it is clean" {
    load_doctor_functions
    local home="$BATS_TEST_TMPDIR/home"
    local cache="$BATS_TEST_TMPDIR/xdg-cache"
    make_stranded_home "$home" "$cache"
    export TARGET_HOME="$home"

    XDG_CACHE_HOME="$cache" run doctor_bun_stranded_global_binaries
    assert_success
    [[ "$output" == *"$cache/.bun/bin/codex	@openai/codex"* ]]

    # Nothing stranded: empty output, still success.
    rm -rf "$cache/.bun/bin"
    XDG_CACHE_HOME="$cache" run doctor_bun_stranded_global_binaries
    assert_success
    [[ -z "$output" ]]
}

@test "doctor check bun.global_bin_dir warns with a reinstall fix listing each stranded package once" {
    load_doctor_functions
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    local home="$BATS_TEST_TMPDIR/home"
    make_stranded_home "$home"
    export TARGET_HOME="$home"
    unset XDG_CACHE_HOME
    JSON_MODE=true
    JSON_CHECKS=()
    PASS_COUNT=0 WARN_COUNT=0 FAIL_COUNT=0 SKIP_COUNT=0
    doctor_binary_path() { [[ "$1" == "bun" ]] && printf '%s\n' "$home/.bun/bin/bun"; }

    check_bun_global_bin_dir
    [[ ${#JSON_CHECKS[@]} -eq 1 ]]
    local status_field fix_field details_field
    status_field="$(jq -r '.status' <<< "${JSON_CHECKS[0]}")"
    fix_field="$(jq -r '.fix' <<< "${JSON_CHECKS[0]}")"
    details_field="$(jq -r '.details' <<< "${JSON_CHECKS[0]}")"
    [[ "$status_field" == "warn" ]]
    [[ "$details_field" == "4 global install(s) outside $home/.bun/bin: codex cf-wrangler vercel vc" ]]
    [[ "$fix_field" == 'BUN_INSTALL="$HOME/.bun" bun install -g --trust @openai/codex wrangler vercel'* ]]
    [[ "$WARN_COUNT" -eq 1 ]]
}

@test "doctor check bun.global_bin_dir passes on a clean home and skips without bun" {
    load_doctor_functions
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    local home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$home/.bun/bin"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$HOME/.bun/bin"\n' > "$home/.bun/bin/bun"
    chmod +x "$home/.bun/bin/bun"
    export TARGET_HOME="$home"
    unset XDG_CACHE_HOME
    JSON_MODE=true
    JSON_CHECKS=()
    PASS_COUNT=0 WARN_COUNT=0 FAIL_COUNT=0 SKIP_COUNT=0
    _acfs_doctor_current_home="$home"

    doctor_binary_path() { [[ "$1" == "bun" ]] && printf '%s\n' "$home/.bun/bin/bun"; }
    check_bun_global_bin_dir
    [[ "$(jq -r '.status' <<< "${JSON_CHECKS[0]}")" == "pass" ]]

    JSON_CHECKS=()
    doctor_binary_path() { return 1; }
    check_bun_global_bin_dir
    [[ "$(jq -r '.status' <<< "${JSON_CHECKS[0]}")" == "skip" ]]
}

@test "doctor check bun.global_bin_dir warns when this shell would strand future installs" {
    load_doctor_functions
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    local home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$home/.bun/bin"
    # A bun whose global bin dir (as it would resolve right now) is the cache fallback.
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$HOME/.cache/.bun/bin"\n' > "$home/.bun/bin/bun"
    chmod +x "$home/.bun/bin/bun"
    export TARGET_HOME="$home"
    JSON_MODE=true
    JSON_CHECKS=()
    PASS_COUNT=0 WARN_COUNT=0 FAIL_COUNT=0 SKIP_COUNT=0
    _acfs_doctor_current_home="$home"
    doctor_binary_path() { [[ "$1" == "bun" ]] && printf '%s\n' "$home/.bun/bin/bun"; }

    check_bun_global_bin_dir
    [[ "$(jq -r '.status' <<< "${JSON_CHECKS[0]}")" == "warn" ]]
    [[ "$(jq -r '.fix' <<< "${JSON_CHECKS[0]}")" == 'export BUN_INSTALL="$HOME/.bun"'* ]]
}

@test "doctor --fix dispatches bun.global_bin_dir to fix_bun_global_bin_dir" {
    grep -Eq '^[[:space:]]*bun\.global_bin_dir\)$' "$PROJECT_ROOT/scripts/lib/doctor_fix.sh"
    grep -Fq 'fix_bun_global_bin_dir "$check_id"' "$PROJECT_ROOT/scripts/lib/doctor_fix.sh"
}
