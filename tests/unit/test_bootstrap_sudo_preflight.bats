#!/usr/bin/env bats
#
# Issue #475: with --yes, the curl|bash bootstrap handed off to the verified
# installer under setsid, which has no controlling terminal. A non-root caller
# whose sudo still needed a password could never authenticate, so every
# privileged step failed in turn. acfs_bootstrap_sudo_preflight() now settles
# sudo on the caller's terminal first and tells the handoff whether the child
# must stay on that terminal. These tests exercise the shipped function bodies
# extracted from install.sh with a fake sudo.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    INSTALL_SH="$PROJECT_ROOT/install.sh"

    [[ "$EUID" -ne 0 ]] || skip "the non-root sudo paths cannot be exercised as root"

    eval "$(sed -n '/^acfs_bootstrap_sudo_preflight() {$/,/^}$/p' "$INSTALL_SH")"
    [[ "$(type -t acfs_bootstrap_sudo_preflight)" == "function" ]]

    FAKE_SUDO="$BATS_TEST_TMPDIR/sudo"
    SUDO_LOG="$BATS_TEST_TMPDIR/sudo.log"
    cat > "$FAKE_SUDO" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SUDO_LOG"
# Like real sudo: a cached timestamp satisfies -n and -v, but -k ignores it.
case "$*" in
    "-n -k true") [[ "${FAKE_SUDO_PASSWORDLESS:-0}" == 1 ]] ;;
    "-n true") [[ "${FAKE_SUDO_PASSWORDLESS:-0}" == 1 || "${FAKE_SUDO_CACHED:-0}" == 1 ]] ;;
    "-v") [[ "${FAKE_SUDO_AUTH_OK:-0}" == 1 || "${FAKE_SUDO_CACHED:-0}" == 1 ]] ;;
    *) exit 64 ;;
esac
EOF
    chmod +x "$FAKE_SUDO"
    export SUDO_LOG FAKE_SUDO_PASSWORDLESS=0 FAKE_SUDO_AUTH_OK=0 FAKE_SUDO_CACHED=0

    acfs_early_sudo_binary_path() { printf '%s\n' "$FAKE_SUDO"; }
    HAS_TERMINAL=1
    acfs_bootstrap_has_terminal() { [[ "$HAS_TERMINAL" == 1 ]]; }
    log_warn() { printf 'WARN: %s\n' "$*"; }
    log_error() { printf 'ERROR: %s\n' "$*"; }
}

sudo_calls() {
    [[ -f "$SUDO_LOG" ]] && cat "$SUDO_LOG"
    return 0
}

@test "passwordless sudo keeps the setsid handoff and never prompts" {
    FAKE_SUDO_PASSWORDLESS=1

    run acfs_bootstrap_sudo_preflight
    [ "$status" -eq 0 ]
    [ "$(sudo_calls)" = "-n -k true" ]
}

@test "password sudo with a terminal authenticates there and keeps the child on it (#475)" {
    FAKE_SUDO_AUTH_OK=1

    run acfs_bootstrap_sudo_preflight
    [ "$status" -eq 2 ]
    [[ "$output" == *"sudo needs your password"* ]]
    [ "$(sudo_calls)" = $'-n -k true\n-v' ]
}

@test "failed sudo authentication stops before anything is installed (#475)" {
    run acfs_bootstrap_sudo_preflight
    [ "$status" -eq 1 ]
    [[ "$output" == *"sudo authentication failed; nothing was installed"* ]]
    [ "$(sudo_calls)" = $'-n -k true\n-v' ]
}

@test "password sudo without a terminal fails fast with the ways out (#475)" {
    HAS_TERMINAL=0

    run acfs_bootstrap_sudo_preflight
    [ "$status" -eq 1 ]
    [[ "$output" == *"with no terminal it cannot ask for one"* ]]
    [[ "$output" == *"configure passwordless sudo"* ]]
    # It must not try to prompt where nobody can answer.
    [ "$(sudo_calls)" = "-n -k true" ]
}

# A sudo run a moment earlier on this terminal (say, to install curl) leaves a
# timestamp that plain `sudo -n true` accepts. The setsid child has no terminal
# and cannot use it, so treating that as passwordless sudo failed exactly as
# #475 did. Verified against sudo 1.9 and sudo-rs: the timestamp is per terminal.
@test "a cached sudo timestamp is not mistaken for passwordless sudo (#475)" {
    FAKE_SUDO_CACHED=1

    run acfs_bootstrap_sudo_preflight
    [ "$status" -eq 2 ]
    [ "$(sudo_calls)" = $'-n -k true\n-v' ]
}

@test "a cached sudo timestamp without a terminal still fails fast (#475)" {
    FAKE_SUDO_CACHED=1
    HAS_TERMINAL=0

    run acfs_bootstrap_sudo_preflight
    [ "$status" -eq 1 ]
    [[ "$output" == *"with no terminal it cannot ask for one"* ]]
}

@test "a missing sudo is left for ensure_root to report" {
    acfs_early_sudo_binary_path() { return 1; }

    run acfs_bootstrap_sudo_preflight
    [ "$status" -eq 0 ]
    [ -z "$(sudo_calls)" ]
}

@test "read-only modes decide the handoff before the sudo preflight can run" {
    local body="" readonly_line="" yes_line="" preflight_line=""
    body="$(sed -n '/^acfs_run_verified_bootstrap_installer() {$/,/^}$/p' "$INSTALL_SH")"
    readonly_line="$(grep -n 'RESET_STATE_ONLY:-false' <<<"$body" | head -1 | cut -d: -f1)"
    yes_line="$(grep -n 'elif \[\[ "${YES_MODE:-false}" == "true" \]\]; then' <<<"$body" | head -1 | cut -d: -f1)"
    preflight_line="$(grep -n 'acfs_bootstrap_sudo_preflight || sudo_preflight_status=\$?' <<<"$body" | head -1 | cut -d: -f1)"

    [[ -n "$readonly_line" && -n "$yes_line" && -n "$preflight_line" ]]
    (( readonly_line < yes_line && yes_line < preflight_line ))
}
