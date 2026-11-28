#!/usr/bin/env bats
# shellcheck disable=SC2088,SC2329 # literal ~ config values; stubs called by doctor code

# Doctor checks that read local configuration the way the configured tool does:
#   #460 shell.atuin_daemon compared a "~/..." socket_path as literal text, so
#        a daemon bound to the expanded path was reported as a "socket mismatch".
#   #462 deep.network.apt_mirror only understood one-line "deb http" entries,
#        missed deb822 *.sources and "deb [options] URL" lines, and stripped the
#        repository path, so it probed <host>/dists/ instead of <base>/dists/.
#
# doctor.sh ends in `main "$@"`, so it cannot be sourced directly; the same
# technique as test_doctor_distro_family.bats loads its functions alone.

load '../test_helper'

setup() {
    common_setup
    DOCTOR_SH="$PROJECT_ROOT/scripts/lib/doctor.sh"
    [[ -f "$DOCTOR_SH" ]] || fail "doctor.sh not found at $DOCTOR_SH"
}

teardown() {
    common_teardown
}

load_doctor_functions() {
    local last_line=""
    last_line="$(tail -n 1 "$DOCTOR_SH")"
    [[ "$last_line" == 'main "$@"' ]] \
        || fail "doctor.sh no longer ends in 'main \"\$@\"' (got: $last_line)"
    # shellcheck disable=SC1090
    source <(sed '$d' "$DOCTOR_SH") >/dev/null 2>&1 || true
    # Most configuration tests record results instead of rendering them. Scope
    # tests exercise the production JSON counters and repair dispatch too.
    if [[ "${1:-}" != production ]]; then
        check() { printf '%s|%s|%s|%s\n' "$1" "$3" "$4" "${5:-}"; }
    fi
}

# ------------------------------------------------------------
# #460: atuin daemon socket
# ------------------------------------------------------------

# A fake runtime home with atuin, a daemon config, and an `ss` that reports
# the given socket as listening.
atuin_fixture() {
    local socket_path_value="$1"
    local bound_socket="$2"
    ATUIN_HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$ATUIN_HOME/.atuin/bin" "$ATUIN_HOME/.config/atuin" "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\necho "atuin 18.23.0"\n' > "$ATUIN_HOME/.atuin/bin/atuin"
    chmod +x "$ATUIN_HOME/.atuin/bin/atuin"
    printf '[daemon]\nenabled = true\nsocket_path = "%s"\n' "$socket_path_value" > "$ATUIN_HOME/.config/atuin/config.toml"
    cat > "$BATS_TEST_TMPDIR/bin/ss" <<EOF
#!/usr/bin/env bash
printf 'Netid State  Recv-Q Send-Q Local Address:Port Peer Address:Port\n'
printf 'u_str LISTEN 0      4096   %s 4242 * 0\n' '$bound_socket'
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/ss"
    export TARGET_HOME="$ATUIN_HOME"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "atuin socket: a ~ socket_path matches the daemon bound to the expanded path (#460)" {
    load_doctor_functions
    atuin_fixture "~/.local/share/atuin/atuin.sock" "$BATS_TEST_TMPDIR/home/.local/share/atuin/atuin.sock"

    run check_atuin_daemon
    [ "$status" -eq 0 ]
    [[ "$output" == "shell.atuin_daemon|pass|daemon bound to configured socket (~/.local/share/atuin/atuin.sock -> $ATUIN_HOME/.local/share/atuin/atuin.sock)|" ]] \
        || fail "unexpected: $output"
}

@test "atuin socket: \$HOME and \${HOME} forms resolve to the runtime home (#460)" {
    load_doctor_functions
    local form=""
    for form in '$HOME/.local/share/atuin/atuin.sock' '${HOME}/.local/share/atuin/atuin.sock'; do
        atuin_fixture "$form" "$BATS_TEST_TMPDIR/home/.local/share/atuin/atuin.sock"
        run check_atuin_daemon
        [[ "$output" == "shell.atuin_daemon|pass|"* ]] || fail "$form: $output"
    done
}

@test "atuin socket: a real mismatch is still reported against the resolved path (#460)" {
    load_doctor_functions
    atuin_fixture "~/.local/share/atuin/atuin.sock" "/tmp/atuin-1000/atuin.sock"

    run check_atuin_daemon
    [[ "$output" == "shell.atuin_daemon|warn|socket mismatch: config=~/.local/share/atuin/atuin.sock -> $ATUIN_HOME/.local/share/atuin/atuin.sock bound=/tmp/atuin-1000/atuin.sock"* ]] \
        || fail "unexpected: $output"
}

@test "atuin socket: an absolute socket_path behaves as before (#460)" {
    load_doctor_functions
    atuin_fixture "$BATS_TEST_TMPDIR/home/.local/share/atuin/atuin-daemon.sock" "$BATS_TEST_TMPDIR/home/.local/share/atuin/atuin-daemon.sock"

    run check_atuin_daemon
    [[ "$output" == "shell.atuin_daemon|pass|daemon bound to configured socket ($ATUIN_HOME/.local/share/atuin/atuin-daemon.sock)|" ]] \
        || fail "unexpected: $output"
}

@test "atuin socket: a socket_path built from other variables is flagged, not compared (#460)" {
    load_doctor_functions
    atuin_fixture '$TMPDIR/atuin-$UID/atuin.sock' "/tmp/atuin-1000/atuin.sock"

    run check_atuin_daemon
    [[ "$output" == 'shell.atuin_daemon|warn|socket_path ($TMPDIR/atuin-$UID/atuin.sock) depends on environment variables'* ]] \
        || fail "unexpected: $output"
}

@test "atuin socket: path resolver handles each supported form" {
    load_doctor_functions
    run doctor_atuin_resolve_socket_path "~" /home/u
    [ "$output" = "/home/u" ]
    run doctor_atuin_resolve_socket_path "~/s.sock" /home/u
    [ "$output" = "/home/u/s.sock" ]
    run doctor_atuin_resolve_socket_path '$HOME' /home/u
    [ "$output" = "/home/u" ]
    run doctor_atuin_resolve_socket_path '/srv/$HOMEDIR/s.sock' /home/u
    [ "$status" -eq 1 ]
    run doctor_atuin_resolve_socket_path '~/s.sock' '/home/a&b'
    [ "$output" = "/home/a&b/s.sock" ]
}

# ------------------------------------------------------------
# #462: APT mirror detection
# ------------------------------------------------------------

@test "apt mirror: deb822-only Ubuntu sources yield the archive base URI (#462)" {
    load_doctor_functions
    local apt="$BATS_TEST_TMPDIR/apt"
    mkdir -p "$apt/sources.list.d"
    printf '# Ubuntu sources have moved to /etc/apt/sources.list.d/ubuntu.sources\n' > "$apt/sources.list"
    cat > "$apt/sources.list.d/ubuntu.sources" <<'EOF'
Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: resolute-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: resolute resolute-updates resolute-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

    run _acfs_doctor_apt_mirror_url "$apt"
    [ "$status" -eq 0 ]
    [ "$output" = "http://archive.ubuntu.com/ubuntu" ]
}

@test "apt mirror: one-line entries with [options] are parsed; vendor repos are never chosen (#462)" {
    load_doctor_functions
    local apt="$BATS_TEST_TMPDIR/apt"
    mkdir -p "$apt/sources.list.d"
    printf 'deb [arch=amd64 signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main\n' \
        > "$apt/sources.list.d/a-nodesource.list"
    printf 'deb [ arch=arm64 signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg ] http://ports.ubuntu.com/ubuntu-ports noble main\n' \
        > "$apt/sources.list.d/b-ubuntu.list"

    run _acfs_doctor_apt_mirror_url "$apt"
    [ "$output" = "http://ports.ubuntu.com/ubuntu-ports" ]
}

@test "apt mirror: disabled deb822 stanzas, deb-src and comments are ignored (#462)" {
    load_doctor_functions
    local apt="$BATS_TEST_TMPDIR/apt"
    mkdir -p "$apt/sources.list.d"
    printf '# deb http://old.example.com/ubuntu noble main\ndeb-src http://src.example.com/ubuntu noble main\n' > "$apt/sources.list"
    # apt reads Enabled: as a boolean, so every false spelling disables a stanza.
    printf 'Types: deb\nURIs: http://false.example.com/debian\nSuites: bookworm\nComponents: main\nEnabled: False \n\nTypes: deb\nURIs: http://off.example.com/debian\nSuites: bookworm\nComponents: main\nEnabled: off\n' \
        > "$apt/sources.list.d/a-disabled.sources"
    cat > "$apt/sources.list.d/debian.sources" <<'EOF'
Types: deb
URIs: http://disabled.example.com/debian
Suites: bookworm
Components: main
Enabled: no

Types: deb deb-src
URIs:
 http://deb.debian.org/debian
Suites: bookworm bookworm-updates
Components: main
EOF

    run _acfs_doctor_apt_mirror_url "$apt"
    [ "$output" = "http://deb.debian.org/debian" ]
}

@test "apt mirror: only a security host is used when no regional archive exists (#462)" {
    load_doctor_functions
    local apt="$BATS_TEST_TMPDIR/apt"
    mkdir -p "$apt/sources.list.d"
    printf 'deb http://security.ubuntu.com/ubuntu noble-security main\n' > "$apt/sources.list"

    run _acfs_doctor_apt_mirror_url "$apt"
    [ "$output" = "http://security.ubuntu.com/ubuntu" ]
}

@test "apt mirror: a mirror serving Ubuntu under another path is found by its components (#462)" {
    load_doctor_functions
    local apt="$BATS_TEST_TMPDIR/apt"
    mkdir -p "$apt/sources.list.d"
    # Vendor repositories whose paths contain "ubuntu" or that use "main" only.
    printf 'deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/24.04/prod noble main\n' \
        > "$apt/sources.list.d/a-microsoft.list"
    printf 'deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable\n' \
        > "$apt/sources.list.d/b-docker.list"
    printf 'Types: deb\nURIs: https://repo.charm.sh/apt/\nSuites: *\nComponents: *\n' > "$apt/sources.list.d/charm.sources"
    # A provider mirror that serves the archive and security pockets under its
    # own paths; the security stanza comes first and must not win.
    cat > "$apt/sources.list.d/ubuntu.sources" <<'EOF'
Types: deb
URIs: https://mirror.example.net/ubuntu/security
Suites: noble-security
Components: main restricted
 universe multiverse

Types: deb
URIs: https://mirror.example.net/ubuntu/packages
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
EOF

    run _acfs_doctor_apt_mirror_url "$apt"
    [ "$output" = "https://mirror.example.net/ubuntu/packages" ] || fail "unexpected: $output"

    # Without the packages stanza the security pocket is still a usable mirror.
    printf 'Types: deb\nURIs: https://mirror.example.net/ubuntu/security\nSuites: noble-security\nComponents: main universe\n' \
        > "$apt/sources.list.d/ubuntu.sources"
    run _acfs_doctor_apt_mirror_url "$apt"
    [ "$output" = "https://mirror.example.net/ubuntu/security" ] || fail "unexpected: $output"

    # Vendor repositories alone never qualify.
    printf '# moved\n' > "$apt/sources.list.d/ubuntu.sources"
    run _acfs_doctor_apt_mirror_url "$apt"
    [ -z "$output" ] || fail "unexpected: $output"

    # The same rule applies to one-line entries.
    printf 'deb http://mirror.example.org/pub/ubuntu/ noble main universe # regional\n' > "$apt/sources.list"
    run _acfs_doctor_apt_mirror_url "$apt"
    [ "$output" = "http://mirror.example.org/pub/ubuntu" ] || fail "unexpected: $output"
}

@test "apt mirror: the probe requests <base>/dists/ and passes on 200 (#462)" {
    load_doctor_functions
    local apt="$BATS_TEST_TMPDIR/apt" curl_log="$BATS_TEST_TMPDIR/curl.log"
    mkdir -p "$apt/sources.list.d" "$BATS_TEST_TMPDIR/bin"
    printf 'Types: deb\nURIs: http://archive.ubuntu.com/ubuntu/\nSuites: noble\nComponents: main\n' > "$apt/sources.list.d/ubuntu.sources"
    cat > "$BATS_TEST_TMPDIR/bin/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\${@: -1}" >> '$curl_log'
printf '200'
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
    _acfs_doctor_system_binary_path() { [[ "$1" == curl ]] && printf '%s\n' "$BATS_TEST_TMPDIR/bin/curl"; }

    run check_network_apt_mirror "$apt"
    [[ "$output" == "deep.network.apt_mirror|pass|archive.ubuntu.com reachable|" ]] || fail "unexpected: $output"
    [ "$(cat "$curl_log")" = "http://archive.ubuntu.com/ubuntu/dists/" ]
}

@test "apt mirror: no APT directory is a skip, not a warning (#462)" {
    load_doctor_functions
    _acfs_doctor_system_binary_path() { printf '/usr/bin/%s\n' "$1"; }

    run check_network_apt_mirror "$BATS_TEST_TMPDIR/no-apt-here"
    [[ "$output" == "deep.network.apt_mirror|skip|"* ]] || fail "unexpected: $output"
}

# ------------------------------------------------------------
# #482: shell.login_shell blamed the account when user.sh did not load
# ------------------------------------------------------------

# Point doctor at a fixture validator instead of the deployed runtime.
login_shell_validator_fixture() {
    LOGIN_SHELL_VALIDATOR="$BATS_TEST_TMPDIR/user.sh"
    printf '%s\n' "$1" > "$LOGIN_SHELL_VALIDATOR"
    _acfs_doctor_find_lib_script() { [[ "$1" == user.sh ]] && printf '%s\n' "$LOGIN_SHELL_VALIDATOR"; }
    export TARGET_USER="ubuntu"
}

@test "login shell: the shipped user.sh parses and defines the functions its callers use (#482)" {
    run bash -n "$PROJECT_ROOT/scripts/lib/user.sh"
    [ "$status" -eq 0 ] || fail "user.sh does not parse: $output"
    run bash -c 'source "$1" >/dev/null 2>&1 || exit 2
        declare -F user_login_shell_configured user_verify_local_account_identity set_default_shell >/dev/null' \
        _ "$PROJECT_ROOT/scripts/lib/user.sh"
    [ "$status" -eq 0 ] || fail "user.sh did not load its login-shell functions (status $status)"
}

@test "login shell: a validator with a syntax error is a deployment failure, not an account verdict (#482)" {
    load_doctor_functions
    login_shell_validator_fixture 'user_login_shell_configured() { [[ "$1" == x && "$1" != *
}'

    run check_login_shell_policy
    [ "$status" -eq 0 ]
    [[ "$output" == "shell.login_shell|fail|the deployed login-shell validator ($LOGIN_SHELL_VALIDATOR) failed to load, so the account was not checked|Run acfs-update"* ]] \
        || fail "unexpected: $output"
}

@test "login shell: a validator without the verifier is a deployment failure (#482)" {
    load_doctor_functions
    login_shell_validator_fixture 'user_other_helper() { :; }'

    run check_login_shell_policy
    [[ "$output" == "shell.login_shell|fail|the deployed login-shell validator ("*") failed to load, so the account was not checked|"* ]] \
        || fail "unexpected: $output"
}

@test "login shell: the verifier's verdict decides pass and fail for a loadable validator (#482)" {
    load_doctor_functions
    login_shell_validator_fixture 'user_login_shell_configured() { [[ "$1" == ubuntu ]]; }'
    run check_login_shell_policy
    [ "$output" = "shell.login_shell|pass|approved zsh path verified for ubuntu|" ] || fail "unexpected: $output"

    login_shell_validator_fixture 'user_login_shell_configured() { return 1; }'
    run check_login_shell_policy
    [[ "$output" == "shell.login_shell|fail|the effective login shell for ubuntu is not an approved, executable zsh path from /etc/shells|Re-run ACFS shell setup"* ]] \
        || fail "unexpected: $output"
}

# ------------------------------------------------------------
# #476: an absent nightly timer after --skip acfs.nightly is the user's choice
# ------------------------------------------------------------

nightly_state_fixture() {
    NIGHTLY_STATE="$BATS_TEST_TMPDIR/state.json"
    printf '%s\n' "$1" > "$NIGHTLY_STATE"
    _acfs_doctor_find_project_path() { [[ "$1" == state.json ]] && printf '%s\n' "$NIGHTLY_STATE"; }
    fix_for_module() { printf 'enable %s' "$1"; }
}

@test "nightly timer: missing after a recorded --skip is a skip, not a warning (#476)" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    load_doctor_functions
    nightly_state_fixture '{"skipped_tools":["tools.atuin","acfs.nightly"]}'

    run report_nightly_timer_status missing
    [ "$output" = "acfs.nightly|skip|not installed (skipped during installation)|" ] || fail "unexpected: $output"
}

@test "nightly timer: missing without a recorded skip still warns (#476)" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    load_doctor_functions
    nightly_state_fixture '{"skipped_tools":["tools.atuin"]}'

    run report_nightly_timer_status missing
    [ "$output" = "acfs.nightly|warn|not installed (optional)|enable acfs.nightly" ] || fail "unexpected: $output"

    _acfs_doctor_find_project_path() { return 1; }
    run report_nightly_timer_status missing
    [ "$output" = "acfs.nightly|warn|not installed (optional)|enable acfs.nightly" ] || fail "no state: $output"
}

@test "nightly timer: an enabled timer passes even if an earlier run skipped it (#476)" {
    load_doctor_functions
    nightly_state_fixture '{"skipped_tools":["acfs.nightly"]}'

    run report_nightly_timer_status enabled
    [ "$output" = "acfs.nightly|pass|enabled|" ] || fail "unexpected: $output"
}

@test "login shell: a missing validator still reports that user.sh is not deployed" {
    load_doctor_functions
    _acfs_doctor_find_lib_script() { return 1; }
    export TARGET_USER="ubuntu"

    run check_login_shell_policy
    [ "$output" = "shell.login_shell|fail|user.sh validator is not deployed|Run acfs-update to redeploy the ACFS runtime, then run acfs doctor again" ] \
        || fail "unexpected: $output"
}

# ------------------------------------------------------------
# Persisted subset installs: diagnose and repair the intended capabilities.
# ------------------------------------------------------------

doctor_selection_fixture() {
    load_doctor_functions production
    TARGET_HOME="$BATS_TEST_TMPDIR/selected-target"
    TARGET_USER="$(id -un)"
    ACFS_HOME="$TARGET_HOME/.acfs"
    ACFS_STATE_FILE=""
    ACFS_SYSTEM_STATE_FILE="$BATS_TEST_TMPDIR/no-system-state.json"
    DOCTOR_TEST_STATE="$ACFS_HOME/state.json"
    DOCTOR_TEST_BIN="$BATS_TEST_TMPDIR/selected-bin"
    DOCTOR_TEST_PROBES="$BATS_TEST_TMPDIR/probes"
    mkdir -p "$DOCTOR_TEST_BIN" "$ACFS_HOME"
    printf '%s\n' "$1" > "$DOCTOR_TEST_STATE"
    export DOCTOR_TEST_PROBES
    _acfs_doctor_find_project_path() {
        if [[ "$1" == state.json ]]; then
            [[ -f "$DOCTOR_TEST_STATE" ]] || return 1
            printf '%s\n' "$DOCTOR_TEST_STATE"
        elif [[ -f "$PROJECT_ROOT/$1" ]]; then
            printf '%s\n' "$PROJECT_ROOT/$1"
        else
            return 1
        fi
    }
    # Load the real generated check data in a subshell: its shell options and
    # PATH exports must not leak into Bats, just as in the production loader.
    mapfile -t MANIFEST_CHECKS < <(
        source "$PROJECT_ROOT/scripts/generated/doctor_checks.sh"
        printf '%s\n' "${MANIFEST_CHECKS[@]}"
    )
    [[ ${#MANIFEST_CHECKS[@]} -gt 50 ]] || fail "manifest check fixture did not load"
    MANIFEST_CHECKS_LOADED=true
    JSON_MODE=true
    HAS_GUM=false
    FIX_MODE=false
    section() { :; }
    blank_line() { :; }
    doctor_binary_path() {
        [[ -x "$DOCTOR_TEST_BIN/$1" ]] || return 1
        printf '%s\n' "$DOCTOR_TEST_BIN/$1"
    }
    doctor_agent_mail_cli_path() { doctor_binary_path am; }
    doctor_load_module_selection
}

doctor_selection_binary() {
    cat > "$DOCTOR_TEST_BIN/$1" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" >> "$DOCTOR_TEST_PROBES"
printf '%s 1.0\n' "${0##*/}"
EOF
    chmod +x "$DOCTOR_TEST_BIN/$1"
}

doctor_selection_json() {
    local joined=""
    joined=$(IFS=,; printf '%s' "${JSON_CHECKS[*]}")
    printf '[%s]\n' "$joined"
}

# Managed-service diagnostics exercise the real target runner and guardian.
doctor_service_drift_fixture() {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["stack.cm","lang.bun"]}}'
    # Exercise the real same-account transport without writing into its home.
    # All checkpoints, executable fixtures and output stay in Bats tmp.
    local passwd_entry=""
    passwd_entry="$(_acfs_doctor_getent_passwd_entry "$TARGET_USER")"
    TARGET_HOME="$(_acfs_doctor_passwd_home_from_entry "$passwd_entry")"
    [[ "$TARGET_HOME" == /* && -d "$TARGET_HOME" ]] || fail "current account home is unavailable"
    ACFS_HOME="$TARGET_HOME/.acfs"
    ACFS_BIN_DIR="$DOCTOR_TEST_BIN"
    DOCTOR_SELECTION_STATE_FILE="$BATS_TEST_TMPDIR/drift selection.json"
    jq --arg home "$TARGET_HOME" --arg user "$TARGET_USER" \
        '.target_home = $home | .target_user = $user' \
        "$DOCTOR_TEST_STATE" > "$DOCTOR_SELECTION_STATE_FILE"
    state_load_module_selection "$DOCTOR_SELECTION_STATE_FILE" "$TARGET_HOME" "$TARGET_USER"
    # Only the validated path above may reach the service command.
    ACFS_STATE_FILE="$BATS_TEST_TMPDIR/unrelated-checkpoint.json"

    export DOCTOR_DRIFT_SCRIPT="$BATS_TEST_TMPDIR/drift manager with spaces.sh"
    export DOCTOR_DRIFT_CONTEXT="$BATS_TEST_TMPDIR/drift-context"
    export DOCTOR_DRIFT_ARGS="$BATS_TEST_TMPDIR/drift-args"
    export DOCTOR_DRIFT_STARTED="$BATS_TEST_TMPDIR/drift-started"
    export DOCTOR_DRIFT_CHILD="$BATS_TEST_TMPDIR/drift-child"
    export DOCTOR_DRIFT_ESCAPED="$BATS_TEST_TMPDIR/drift-escaped"
    export DOCTOR_DRIFT_MODE=stale
    _acfs_doctor_find_lib_script() {
        if [[ "$1" == acfs-services.sh ]]; then
            printf '%s\n' "$DOCTOR_DRIFT_SCRIPT"
        elif [[ -f "$PROJECT_ROOT/scripts/lib/$1" ]]; then
            printf '%s/scripts/lib/%s\n' "$PROJECT_ROOT" "$1"
        else
            return 1
        fi
    }
    cat > "$DOCTOR_DRIFT_SCRIPT" <<'EOF'
#!/bin/bash
printf started > "$DOCTOR_DRIFT_STARTED"
printf '%s\n' "$@" > "$DOCTOR_DRIFT_ARGS"
{
    printf 'UID=%s\n' "$EUID"
    for name in HOME ACFS_HOME ACFS_STATE_FILE ACFS_BIN_DIR PATH BASH_ENV ENV \
        XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID \
        DBUS_SYSTEM_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE \
        SYSTEMD_BUS_ADDRESS SYSTEMD_HOST SYSTEMD_MACHINE TMUX TMUX_PANE TMUX_TMPDIR; do
        printf '%s=%s\n' "$name" "${!name-}"
    done
} > "$DOCTOR_DRIFT_CONTEXT"
case "$DOCTOR_DRIFT_MODE" in
    healthy) printf 'cm|ok|installed bytes match\n' ;;
    not-running) printf 'cm|not-running|no live process\n' ;;
    unknown) printf 'cm|unknown|cannot read the running executable\n' ;;
    stale) printf 'cm|stale|replaced binary with a | in its path\n'; exit 1 ;;
    agent-mail) printf 'agent-mail|stale|replaced Agent Mail binary\n'; exit 1 ;;
    failed) printf 'cm|stale|partial stale observation\n'; exit 42 ;;
    empty) exit 1 ;;
    malformed) printf 'unstructured output\n' ;;
    duplicate) printf 'cm|ok|first\ncm|ok|second\n' ;;
    unexpected) printf 'agent-mail|ok|outside the selected scope\n' ;;
    partial) printf 'cm|ok|cass result is missing\n' ;;
    empty-detail) printf 'cm|unknown|\n' ;;
    bad-state) printf 'cm|unrecognized|invalid state\n' ;;
    inconsistent) printf 'cm|stale|stale row without its stale exit status\n' ;;
    stalled)
        trap '' TERM
        sleep 8 &
        printf '%s\n' "$!" > "$DOCTOR_DRIFT_CHILD"
        wait
        printf escaped > "$DOCTOR_DRIFT_ESCAPED"
        printf 'cm|stale|late observation\n'
        exit 1
        ;;
    orphaned)
        (
            trap '' TERM
            sleep 8
            printf escaped > "$DOCTOR_DRIFT_ESCAPED"
            printf 'cm|stale|late orphan observation\n'
        ) &
        printf '%s\n' "$!" > "$DOCTOR_DRIFT_CHILD"
        exit 0
        ;;
esac
EOF
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true
}

@test "doctor service drift: valid stale reports use the target context and exact checkpoint without automatic repair" {
    doctor_service_drift_fixture
    local startup_hook="$BATS_TEST_TMPDIR/ambient-startup"
    export DOCTOR_DRIFT_POISON="$BATS_TEST_TMPDIR/startup-executed"
    printf 'printf poisoned > "$DOCTOR_DRIFT_POISON"\n' > "$startup_hook"
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/foreign-runtime"
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/foreign/session-bus
    export DBUS_SESSION_BUS_PID=1234 DBUS_SYSTEM_BUS_ADDRESS=unix:path=/foreign/system-bus
    export DBUS_STARTER_ADDRESS=unix:path=/foreign/starter DBUS_STARTER_BUS_TYPE=session
    export SYSTEMD_BUS_ADDRESS=unix:path=/foreign/systemd SYSTEMD_HOST=foreign SYSTEMD_MACHINE=foreign
    export TMUX=/foreign/socket,123,0 TMUX_PANE=%99 TMUX_TMPDIR="$BATS_TEST_TMPDIR/foreign-tmux"

    BASH_ENV="$startup_hook" ENV="$startup_hook" \
        HOME="$BATS_TEST_TMPDIR/foreign-home" ACFS_HOME="$BATS_TEST_TMPDIR/foreign-acfs" \
        PATH="$BATS_TEST_TMPDIR/foreign-bin:$PATH" check_service_binary_drift

    [ -s "$DOCTOR_DRIFT_STARTED" ]
    [ ! -e "$DOCTOR_DRIFT_POISON" ]
    [ "$(cat "$DOCTOR_DRIFT_ARGS")" = $'drift\n--robot' ]
    grep -Fx "UID=$(id -u)" "$DOCTOR_DRIFT_CONTEXT"
    grep -Fx "HOME=$TARGET_HOME" "$DOCTOR_DRIFT_CONTEXT"
    grep -Fx "ACFS_HOME=$TARGET_HOME/.acfs" "$DOCTOR_DRIFT_CONTEXT"
    grep -Fx "ACFS_STATE_FILE=$DOCTOR_SELECTION_STATE_FILE" "$DOCTOR_DRIFT_CONTEXT"
    grep -Fx "ACFS_BIN_DIR=$ACFS_BIN_DIR" "$DOCTOR_DRIFT_CONTEXT"
    if grep -Fq "$BATS_TEST_TMPDIR/foreign-bin" "$DOCTOR_DRIFT_CONTEXT"; then
        fail "service inspection inherited the caller's PATH"
    fi
    if grep -Fq "$BATS_TEST_TMPDIR/foreign-acfs" "$DOCTOR_DRIFT_CONTEXT"; then
        fail "service inspection inherited the caller's ACFS home"
    fi
    local name=""
    for name in BASH_ENV ENV DBUS_SESSION_BUS_PID DBUS_SYSTEM_BUS_ADDRESS \
        DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE SYSTEMD_BUS_ADDRESS \
        SYSTEMD_HOST SYSTEMD_MACHINE TMUX TMUX_PANE TMUX_TMPDIR; do
        grep -Fx "$name=" "$DOCTOR_DRIFT_CONTEXT"
    done
    local runtime_dir="/run/user/$(id -u)" expected_runtime="" expected_bus=""
    if [[ -d "$runtime_dir" && ! -L "$runtime_dir" && -O "$runtime_dir" ]]; then
        expected_runtime="$runtime_dir"
        if [[ -S "$runtime_dir/bus" && ! -L "$runtime_dir/bus" && -O "$runtime_dir/bus" ]]; then
            expected_bus="unix:path=$runtime_dir/bus"
        fi
    fi
    grep -Fx "XDG_RUNTIME_DIR=$expected_runtime" "$DOCTOR_DRIFT_CONTEXT"
    grep -Fx "DBUS_SESSION_BUS_ADDRESS=$expected_bus" "$DOCTOR_DRIFT_CONTEXT"
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    doctor_selection_json | jq -e '
        length == 1 and .[0].id == "services.binary_drift.cm" and
        .[0].status == "warn" and
        .[0].details == "replaced binary with a | in its path" and
        (.[0].fix | contains("acfs services restart cm"))' >/dev/null
}

@test "doctor service drift: Agent Mail uses a valid report ID and retains its actual service name" {
    doctor_service_drift_fixture
    jq -n --arg home "$TARGET_HOME" --arg user "$TARGET_USER" \
        '{target_home:$home,target_user:$user,module_selection:{schema_version:1,selected_modules:["stack.mcp_agent_mail"]}}' \
        > "$DOCTOR_SELECTION_STATE_FILE"
    state_load_module_selection "$DOCTOR_SELECTION_STATE_FILE" "$TARGET_HOME" "$TARGET_USER"
    export DOCTOR_DRIFT_MODE=agent-mail

    check_service_binary_drift

    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    [ "$(doctor_check_module_id services.binary_drift.agent_mail)" = stack.mcp_agent_mail ]
    [ "$(doctor_check_module_id services.binary_drift.cm)" = stack.cm ]
    [ "$(doctor_check_module_id services.binary_drift.cass)" = stack.cass ]
    doctor_selection_json | jq -e '
        length == 1 and .[0].id == "services.binary_drift.agent_mail" and
        .[0].status == "warn" and
        (.[0].fix | contains("acfs services restart agent-mail"))' >/dev/null
}

@test "doctor service drift: current and stopped services stay quiet while unknown observations remain visible" {
    doctor_service_drift_fixture
    local mode=""
    for mode in healthy not-running; do
        export DOCTOR_DRIFT_MODE="$mode"
        check_service_binary_drift
        [ "${#JSON_CHECKS[@]}" -eq 0 ]
    done
    export DOCTOR_DRIFT_MODE=unknown
    check_service_binary_drift
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    doctor_selection_json | jq -e '
        length == 1 and .[0].id == "services.binary_drift.cm" and
        .[0].status == "warn" and .[0].fix == null and
        .[0].details == "cannot read the running executable"' >/dev/null
}

@test "doctor service drift: failed malformed partial and inconsistent reports cannot authorize restart suggestions" {
    doctor_service_drift_fixture
    local mode=""
    for mode in failed empty malformed duplicate unexpected partial empty-detail bad-state inconsistent; do
        export DOCTOR_DRIFT_MODE="$mode"
        JSON_CHECKS=()
        WARN_COUNT=0
        ACFS_STATE_SELECTED_MODULES=(stack.cm lang.bun)
        if [[ "$mode" == partial ]]; then
            ACFS_STATE_SELECTED_MODULES+=(stack.cass)
        fi
        check_service_binary_drift
        [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
        doctor_selection_json | jq -e '
            length == 1 and .[0].id == "services.binary_drift" and
            .[0].status == "warn" and .[0].fix == null' >/dev/null
        if [[ "$mode" == failed ]]; then
            doctor_selection_json | jq -e '.[0].details | contains("exit 42")' >/dev/null
        else
            doctor_selection_json | jq -e '.[0].details | contains("invalid or incomplete")' >/dev/null
        fi
    done
}

@test "doctor service drift: TERM-resistant and orphaned output writers are bounded and later diagnostics continue" {
    doctor_service_drift_fixture
    DEEP_CHECK_TIMEOUT=1
    local mode="" child_state="" attempt=0
    for mode in stalled orphaned; do
        export DOCTOR_DRIFT_MODE="$mode"
        export DOCTOR_DRIFT_STARTED="$BATS_TEST_TMPDIR/drift-started-$mode"
        export DOCTOR_DRIFT_CHILD="$BATS_TEST_TMPDIR/drift-child-$mode"
        export DOCTOR_DRIFT_ESCAPED="$BATS_TEST_TMPDIR/drift-escaped-$mode"
        JSON_CHECKS=()
        WARN_COUNT=0
        check_service_binary_drift
        [ -s "$DOCTOR_DRIFT_STARTED" ]
        [ -s "$DOCTOR_DRIFT_CHILD" ]
        [ ! -e "$DOCTOR_DRIFT_ESCAPED" ]
        for attempt in {1..20}; do
            child_state="$(ps -o stat= -p "$(cat "$DOCTOR_DRIFT_CHILD")" 2>/dev/null || true)"
            [[ -z "$child_state" || "$child_state" == Z* ]] && break
            sleep 0.05
        done
        [[ -z "$child_state" || "$child_state" == Z* ]] \
            || fail "$mode service child is still running: $child_state"
        [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
        doctor_selection_json | jq -e '
            length == 1 and .[0].id == "services.binary_drift" and
            .[0].status == "timeout" and (.[0].details | contains("deadline")) and
            .[0].fix == null' >/dev/null
    done
    doctor_selection_binary bun
    check_command tool.bun Bun bun "install bun"
    doctor_selection_json | jq -e '.[-1].id == "tool.bun" and .[-1].status == "pass"' >/dev/null
}

@test "doctor service drift: missing timeout support refuses execution and unselected services stay unprobed" {
    doctor_service_drift_fixture
    _acfs_doctor_system_binary_path() {
        [[ "$1" != timeout ]] || return 1
        [[ -x "/usr/bin/$1" ]] || return 1
        printf '/usr/bin/%s\n' "$1"
    }
    check_service_binary_drift
    [ ! -e "$DOCTOR_DRIFT_STARTED" ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    doctor_selection_json | jq -e '
        length == 1 and .[0].id == "services.binary_drift" and
        .[0].status == "warn" and .[0].fix == null and
        (.[0].details | contains("timeout"))' >/dev/null

    JSON_CHECKS=()
    ACFS_STATE_SELECTED_MODULES=(lang.bun)
    check_service_binary_drift
    [ ! -e "$DOCTOR_DRIFT_STARTED" ]
    [ "${#JSON_CHECKS[@]}" -eq 0 ]
}

doctor_custom_checkpoint_fixture() {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["agents.claude"]}}'
    TARGET_HOME="$BATS_TEST_TMPDIR/custom-target"
    TARGET_USER="$(id -un)"
    ACFS_HOME="$TARGET_HOME/.acfs"
    ACFS_STATE_FILE="$BATS_TEST_TMPDIR/custom-checkpoint.json"
    mkdir -p "$ACFS_HOME"
    jq -n --arg home "$TARGET_HOME" --arg user "$TARGET_USER" \
        '{target_home:$home,target_user:$user,module_selection:{schema_version:1,selected_modules:["lang.bun"]}}' > "$ACFS_STATE_FILE"
}

doctor_checkpoint_startup_fixture() {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["lang.bun"]}}'
    DOCTOR_CONTEXT_HOME="$BATS_TEST_TMPDIR/doctor context"
    DOCTOR_CONTEXT_USER=acfs_context_target
    DOCTOR_CONTEXT_CHECKPOINT="$BATS_TEST_TMPDIR/selected checkpoint.json"
    DOCTOR_TEST_STATE="$DOCTOR_CONTEXT_HOME/.acfs/state.json"
    mkdir -p "$DOCTOR_CONTEXT_HOME/.acfs" "$DOCTOR_CONTEXT_HOME/canonical-bin" \
        "$DOCTOR_CONTEXT_HOME/selected-bin" "$DOCTOR_CONTEXT_HOME/.local/bin"
    jq -n --arg home "$DOCTOR_CONTEXT_HOME" --arg user "$DOCTOR_CONTEXT_USER" \
        '{target_home:$home,target_user:$user,bin_dir:($home+"/canonical-bin"),mode:"vibe",
          module_selection:{schema_version:1,selected_modules:["lang.bun","agents.claude"]}}' > "$DOCTOR_TEST_STATE"
    jq -n --arg home "$DOCTOR_CONTEXT_HOME" --arg user "$DOCTOR_CONTEXT_USER" \
        '{target_home:$home,target_user:$user,bin_dir:($home+"/selected-bin"),mode:"safe",
          module_selection:{schema_version:1,selected_modules:["lang.bun"]}}' > "$DOCTOR_CONTEXT_CHECKPOINT"
    local bin=""
    for bin in canonical-bin selected-bin .local/bin; do
        printf '#!/bin/bash\nprintf "%%s\\n" %q\n' "$bin" > "$DOCTOR_CONTEXT_HOME/$bin/bun"
        chmod +x "$DOCTOR_CONTEXT_HOME/$bin/bun"
    done
    # Exercise the unmodified production startup block with an isolated NSS
    # account. This is the path that chooses the bin directory before the
    # scope loader runs; loading scope functions alone misses its precedence.
    _acfs_doctor_getent_passwd_entry() {
        [[ $# -eq 0 || "$1" == "$DOCTOR_CONTEXT_USER" ]] || return 1
        printf '%s:x:12345:12345::%s:/bin/bash\n' "$DOCTOR_CONTEXT_USER" "$DOCTOR_CONTEXT_HOME"
    }
    # Restore the production lookup overridden by doctor_selection_fixture.
    eval "$(sed -n '/^doctor_binary_path()/,/^}$/p' "$DOCTOR_SH")"
    ACFS_STATE_FILE="$DOCTOR_CONTEXT_CHECKPOINT"
}

doctor_checkpoint_startup() {
    _ACFS_DOCTOR_ENV_TARGET_USER_WAS_SET=true
    _ACFS_DOCTOR_ENV_TARGET_USER="$DOCTOR_CONTEXT_USER"
    _ACFS_DOCTOR_ENV_TARGET_HOME="$DOCTOR_CONTEXT_HOME"
    _ACFS_DOCTOR_ENV_BIN_DIR=""
    _acfs_doctor_current_home="$DOCTOR_CONTEXT_HOME"
    _acfs_doctor_script_acfs_home=""
    _ACFS_DOCTOR_STATE_PATHS=()
    _ACFS_DOCTOR_STATE_VALUES=()
    ACFS_HOME="$DOCTOR_CONTEXT_HOME/.acfs"
    ACFS_BIN_DIR=""
    eval "$(sed -n '/^# Prefer authoritative installed\/system state/,/^export ACFS_HOME$/p' "$DOCTOR_SH")"
    doctor_load_module_selection
}

@test "doctor context: custom checkpoint bin controls real command discovery after startup" {
    doctor_checkpoint_startup_fixture
    doctor_checkpoint_startup
    [[ "$TARGET_USER" == "$DOCTOR_CONTEXT_USER" && "$TARGET_HOME" == "$DOCTOR_CONTEXT_HOME" ]]
    [[ "$ACFS_MODE" == safe ]]
    state_module_is_selected lang.bun
    if state_module_is_selected agents.claude; then fail "canonical scope replaced custom scope"; fi
    run get_version_line bun
    assert_success
    [[ "$output" == selected-bin ]] || fail "custom scope probed the wrong installation: $output"
}

@test "doctor context: custom checkpoint without bin metadata never borrows canonical custom bin" {
    doctor_checkpoint_startup_fixture
    jq -n --arg home "$DOCTOR_CONTEXT_HOME" --arg user "$DOCTOR_CONTEXT_USER" \
        '{target_home:$home,target_user:$user,mode:"safe",
          module_selection:{schema_version:1,selected_modules:["lang.bun"]}}' > "$DOCTOR_CONTEXT_CHECKPOINT"
    doctor_checkpoint_startup
    run get_version_line bun
    assert_success
    [[ "$output" == .local/bin ]] || fail "custom checkpoint inherited unrelated bin metadata: $output"
}

@test "doctor context: canonical startup retains installed bin metadata and mode" {
    doctor_checkpoint_startup_fixture
    ACFS_STATE_FILE=""
    doctor_checkpoint_startup
    [[ "$ACFS_MODE" == vibe ]]
    state_module_is_selected agents.claude
    run get_version_line bun
    assert_success
    [[ "$output" == canonical-bin ]] || fail "$output"
}

@test "doctor context: resolved target checkpoint owns bin discovery before runtime-relative metadata" {
    doctor_checkpoint_startup_fixture
    ACFS_STATE_FILE=""
    DOCTOR_TEST_STATE="$BATS_TEST_TMPDIR/other-runtime-state.json"
    jq -n --arg home "$DOCTOR_CONTEXT_HOME" --arg user "$DOCTOR_CONTEXT_USER" \
        '{target_home:$home,target_user:$user,bin_dir:($home+"/selected-bin"),mode:"safe"}' > "$DOCTOR_TEST_STATE"
    doctor_checkpoint_startup
    [[ "$ACFS_MODE" == vibe ]]
    run get_version_line bun
    assert_success
    [[ "$output" == canonical-bin ]] || fail "runtime metadata replaced the resolved target bin: $output"
}

doctor_capture_repair_command() {
    local repair="$1"
    local capture_bin="$BATS_TEST_TMPDIR/repair-capture-bin"
    export DOCTOR_REPAIR_URL_CAPTURE="$BATS_TEST_TMPDIR/repair-url"
    export DOCTOR_REPAIR_ARGV_CAPTURE="$BATS_TEST_TMPDIR/repair-argv"
    export DOCTOR_REPAIR_SOURCE_CAPTURE="$BATS_TEST_TMPDIR/repair-source"
    mkdir -p "$capture_bin"
    cat > "$capture_bin/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$DOCTOR_REPAIR_URL_CAPTURE"
cat <<'INSTALLER'
printf '%s\0' "${TARGET_USER:-}" "${TARGET_HOME:-}" "${ACFS_HOME:-}" \
    "${ACFS_STATE_FILE:-}" "${ACFS_BIN_DIR:-}" "$@" > "$DOCTOR_REPAIR_ARGV_CAPTURE"
printf '%s\0' "${ACFS_REPO_OWNER:-}" "${ACFS_REPO_NAME:-}" \
    "${ACFS_CHECKSUMS_REF-unset}" > "$DOCTOR_REPAIR_SOURCE_CAPTURE"
INSTALLER
EOF
    chmod +x "$capture_bin/curl"
    # Execute the rendered command itself against a non-installing transport.
    # A root/admin shell or the next session can have unrelated exported hints.
    (
        cd "$BATS_TEST_TMPDIR"
        env PATH="$capture_bin:/usr/bin:/bin" TARGET_USER=unrelated_caller \
            TARGET_HOME=/unrelated/caller ACFS_HOME=/unrelated/runtime \
            ACFS_STATE_FILE=/unrelated/checkpoint.json ACFS_BIN_DIR=/unrelated/bin ACFS_REF=unrelated/source \
            ACFS_REPO_OWNER=unrelated-owner ACFS_REPO_NAME=unrelated-repository ACFS_CHECKSUMS_REF=unrelated/checksums \
            bash --noprofile --norc -c "$repair"
    )
    mapfile -d '' -t DOCTOR_REPAIR_CAPTURED < "$DOCTOR_REPAIR_ARGV_CAPTURE"
    mapfile -d '' -t DOCTOR_REPAIR_SOURCE_CAPTURED < "$DOCTOR_REPAIR_SOURCE_CAPTURE"
}

@test "doctor repair handoff: both parsers use only the top-level pin from the diagnosed checkpoint" {
    doctor_custom_checkpoint_fixture
    local parser="" metadata="" repair="" checkpoint="$ACFS_STATE_FILE"
    command() {
        if [[ "$parser" == python && "${1:-}" == -v && "${2:-}" == jq ]]; then return 1; fi
        builtin command "$@"
    }
    for parser in jq python; do
        for metadata in '{}' '{"nested":{"pinned_ref":"other/revision"}}' \
            '{"pinned_ref":null,"nested":{"pinned_ref":"other/revision"}}' \
            '{"pinned_ref":["wrong"],"nested":{"pinned_ref":"other/revision"}}' \
            '{"pinned_ref":"release\nutils.lsr","nested":{"pinned_ref":"other/revision"}}'; do
            jq -n --arg home "$TARGET_HOME" --arg user "$TARGET_USER" --argjson metadata "$metadata" '
                {target_home:$home,target_user:$user} + $metadata' > "$checkpoint"
            doctor_load_module_selection
            repair=$(build_fix_suggestion lang.bun)
            [[ "$repair" == *" --ref main" && "$repair" != *other/revision* ]]
        done
        jq -n --arg home "$TARGET_HOME" --arg user "$TARGET_USER" '
            {target_home:$home,target_user:$user,pinned_ref:"release/known",
             nested:{pinned_ref:"other/revision"}}' > "$checkpoint"
        doctor_load_module_selection
        jq '.pinned_ref = "release/later"' "$checkpoint" > "$checkpoint.tmp"
        mv "$checkpoint.tmp" "$checkpoint"
        repair=$(build_fix_suggestion lang.bun)
        [[ "$repair" == *"/release/known/install.sh"* && "$repair" == *" --ref release/known" ]]
        doctor_load_module_selection
        repair=$(build_fix_suggestion lang.bun)
        [[ "$repair" == *" --ref release/later" ]]
    done
}

@test "doctor repair handoff: rendered command preserves validated custom scope source and target" {
    doctor_custom_checkpoint_fixture
    TARGET_HOME="$BATS_TEST_TMPDIR/"'repair $(touch injected) `touch backtick` ; home'
    ACFS_HOME="$TARGET_HOME/.acfs"
    ACFS_BIN_DIR="$TARGET_HOME/selected bin"
    ACFS_STATE_FILE="$BATS_TEST_TMPDIR/"'selected $(touch checkpoint-injected).json'
    mkdir -p "$ACFS_HOME" "$ACFS_BIN_DIR"
    jq -n --arg home "$TARGET_HOME" --arg user "$TARGET_USER" --arg bin "$ACFS_BIN_DIR" \
        '{target_home:$home,target_user:$user,bin_dir:$bin,mode:"safe",pinned_ref:"selected/revision",
          module_selection:{schema_version:1,selected_modules:["lang.bun"]}}' > "$ACFS_STATE_FILE"
    # Installed metadata deliberately names a different source revision.
    printf '%s\n' '{"pinned_ref":"canonical-revision"}' > "$DOCTOR_TEST_STATE"
    doctor_load_module_selection
    local repair=""
    repair="$(build_fix_suggestion lang.bun)"
    doctor_capture_repair_command "$repair"
    [[ "${DOCTOR_REPAIR_CAPTURED[0]}" == "$TARGET_USER" ]] || fail "repair lost target user"
    [[ "${DOCTOR_REPAIR_CAPTURED[1]}" == "$TARGET_HOME" ]] || fail "repair lost target home"
    [[ "${DOCTOR_REPAIR_CAPTURED[2]}" == "$TARGET_HOME/.acfs" ]] || fail "repair inherited caller runtime"
    [[ "${DOCTOR_REPAIR_CAPTURED[3]}" == "$ACFS_STATE_FILE" ]] || fail "repair lost custom checkpoint"
    [[ "${DOCTOR_REPAIR_CAPTURED[4]}" == "$ACFS_BIN_DIR" ]] || fail "repair lost custom bin directory"
    [[ "${DOCTOR_REPAIR_CAPTURED[*]:5}" == '--yes --force-reinstall --mode safe --only lang.bun --no-deps --ref selected/revision' ]] \
        || fail "unexpected installer arguments: ${DOCTOR_REPAIR_CAPTURED[*]:5}"
    [[ "$(tail -n 1 "$DOCTOR_REPAIR_URL_CAPTURE")" == https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/selected/revision/install.sh ]]
    [[ "${DOCTOR_REPAIR_SOURCE_CAPTURED[0]}" == Dicklesworthstone ]] || fail "repair inherited an unrelated repository owner"
    [[ "${DOCTOR_REPAIR_SOURCE_CAPTURED[1]}" == agentic_coding_flywheel_setup ]] || fail "repair inherited an unrelated repository name"
    [[ "${DOCTOR_REPAIR_SOURCE_CAPTURED[2]}" == "" ]] || fail "repair inherited an explicit checksum source"
    [[ ! -e "$BATS_TEST_TMPDIR/injected" && ! -e "$BATS_TEST_TMPDIR/backtick" && ! -e "$BATS_TEST_TMPDIR/checkpoint-injected" ]]
}

@test "doctor repair handoff: canonical phase repairs retain resolved account even in an unrelated shell" {
    doctor_checkpoint_startup_fixture
    ACFS_STATE_FILE=""
    doctor_checkpoint_startup
    local repair=""
    repair="$(build_fix_suggestion "" --phase 6)"
    doctor_capture_repair_command "$repair"
    [[ "${DOCTOR_REPAIR_CAPTURED[0]}" == "$DOCTOR_CONTEXT_USER" ]] || fail "repair targeted the invoking shell account"
    [[ "${DOCTOR_REPAIR_CAPTURED[1]}" == "$DOCTOR_CONTEXT_HOME" ]]
    [[ "${DOCTOR_REPAIR_CAPTURED[2]}" == "$DOCTOR_CONTEXT_HOME/.acfs" ]]
    [[ "${DOCTOR_REPAIR_CAPTURED[3]}" == "$DOCTOR_TEST_STATE" ]]
    [[ "${DOCTOR_REPAIR_CAPTURED[4]}" == "$DOCTOR_CONTEXT_HOME/canonical-bin" ]]
    [[ "${DOCTOR_REPAIR_CAPTURED[*]:5}" == '--yes --force-reinstall --mode vibe --only lang.bun --no-deps --ref main' ]]
    [[ "$(tail -n 1 "$DOCTOR_REPAIR_URL_CAPTURE")" == https://agent-flywheel.com/install ]]
    [[ "${DOCTOR_REPAIR_SOURCE_CAPTURED[0]}" == Dicklesworthstone && "${DOCTOR_REPAIR_SOURCE_CAPTURED[1]}" == agentic_coding_flywheel_setup ]]
    [[ "${DOCTOR_REPAIR_SOURCE_CAPTURED[2]}" == "" ]] || fail "canonical repair inherited an explicit checksum source"
}

@test "doctor repair handoff: the actual installer plan stays inside the diagnosed module or phase" {
    doctor_custom_checkpoint_fixture
    jq '.module_selection.selected_modules = ["agents.codex", "agents.claude", "lang.rust"]' \
        "$ACFS_STATE_FILE" > "$ACFS_STATE_FILE.new"
    mv "$ACFS_STATE_FILE.new" "$ACFS_STATE_FILE"
    doctor_load_module_selection

    source "$PROJECT_ROOT/scripts/lib/install_helpers.sh"
    source "$PROJECT_ROOT/scripts/generated/manifest_index.sh"
    eval "$(sed -n -e '/^parse_args() {$/,/^}$/p' -e '/^append_comma_or_space_separated() {$/,/^}$/p' \
        -e '/^acfs_require_ref_arg_value() {$/,/^}$/p' "$PROJECT_ROOT/install.sh")"
    local ACFS_REPO_OWNER=Dicklesworthstone ACFS_REPO_NAME=agentic_coding_flywheel_setup
    local kind repair expected
    for kind in module phase; do
        if [[ "$kind" == module ]]; then
            repair="$(fix_for_module agents.codex)"
            expected=agents.codex
        else
            repair="$(fix_for_phase 7)"
            expected="agents.claude agents.codex"
        fi
        doctor_capture_repair_command "$repair"
        ONLY_MODULES=()
        ONLY_PHASES=()
        NO_DEPS=false
        parse_args "${DOCTOR_REPAIR_CAPTURED[@]:5}"
        acfs_resolve_selection
        [[ "${ACFS_EFFECTIVE_PLAN[*]}" == "$expected" ]] \
            || fail "$kind repair selected: ${ACFS_EFFECTIVE_PLAN[*]}"
    done
    [[ -z "$(fix_for_module agents.gemini)" ]]
    [[ -z "$(fix_for_phase 8)" ]]
}

@test "doctor repair handoff: a missing saved bin directory is retained as the repair destination" {
    doctor_checkpoint_startup_fixture
    jq -n --arg home "$DOCTOR_CONTEXT_HOME" --arg user "$DOCTOR_CONTEXT_USER" \
        '{target_home:$home,target_user:$user,bin_dir:($home+"/missing bin"),mode:"safe",
          module_selection:{schema_version:1,selected_modules:["lang.bun"]}}' > "$DOCTOR_CONTEXT_CHECKPOINT"
    doctor_checkpoint_startup
    [[ ! -d "$DOCTOR_CONTEXT_HOME/missing bin" ]]
    local repair=""
    repair="$(build_fix_suggestion lang.bun)"
    doctor_capture_repair_command "$repair"
    [[ "${DOCTOR_REPAIR_CAPTURED[4]}" == "$DOCTOR_CONTEXT_HOME/missing bin" ]] || fail "repair changed the saved bin destination"
    [[ ! -d "$DOCTOR_CONTEXT_HOME/missing bin" ]] || fail "rendering the repair created an installation directory"
}

@test "doctor repair handoff: custom runtime roots are preserved without inheriting another account's runtime" {
    doctor_custom_checkpoint_fixture
    ACFS_HOME="$BATS_TEST_TMPDIR/shared runtime"
    doctor_load_module_selection
    local repair=""
    repair="$(build_fix_suggestion lang.bun)"
    doctor_capture_repair_command "$repair"
    [[ "${DOCTOR_REPAIR_CAPTURED[2]}" == "$ACFS_HOME" ]] || fail "repair relocated the custom runtime"

    # The runtime used to inspect a different target can live under another
    # account. Do not copy that source location into the target's repair.
    ACFS_HOME=/root/.acfs
    repair="$(build_fix_suggestion lang.bun)"
    doctor_capture_repair_command "$repair"
    [[ "${DOCTOR_REPAIR_CAPTURED[2]}" == "$TARGET_HOME/.acfs" ]] || fail "repair inherited another account's runtime"
}

@test "doctor repair handoff: failed custom validation clears the accepted checkpoint and emits no repair" {
    doctor_custom_checkpoint_fixture
    doctor_load_module_selection
    ACFS_STATE_FILE="$BATS_TEST_TMPDIR/missing-custom-checkpoint.json"
    if doctor_load_module_selection; then fail "missing custom checkpoint was accepted"; fi
    [[ -z "$DOCTOR_SELECTION_STATE_FILE" ]] || fail "an earlier accepted checkpoint survived validation failure"
    run build_fix_suggestion lang.bun
    assert_failure
    assert_output ""
}

@test "doctor repair handoff: an absent canonical checkpoint retains legacy defaults without borrowing another pin" {
    doctor_custom_checkpoint_fixture
    printf '%s\n' '{"pinned_ref":"unrelated/revision"}' > "$DOCTOR_TEST_STATE"
    ACFS_STATE_FILE="$ACFS_HOME/state.json"
    ACFS_BIN_DIR=""
    doctor_load_module_selection
    [[ "$ACFS_STATE_SELECTION_MODE" == legacy ]]
    local repair=""
    repair="$(build_fix_suggestion lang.bun)"
    doctor_capture_repair_command "$repair"
    [[ "${DOCTOR_REPAIR_CAPTURED[3]}" == "$ACFS_STATE_FILE" ]]
    [[ "${DOCTOR_REPAIR_CAPTURED[4]}" == "$TARGET_HOME/.local/bin" ]]
    [[ "${DOCTOR_REPAIR_CAPTURED[*]:5}" == '--yes --force-reinstall --mode vibe --only lang.bun --ref main' ]]
    [[ "$(tail -n 1 "$DOCTOR_REPAIR_URL_CAPTURE")" == https://agent-flywheel.com/install ]]
    doctor_capture_repair_command "$(fix_for_phase 6)"
    [[ "${DOCTOR_REPAIR_CAPTURED[*]:5}" == '--yes --force-reinstall --mode vibe --only-phase 6 --ref main' ]]
}

@test "doctor selection: an explicit custom checkpoint overrides installed scope for the resolved account" {
    doctor_custom_checkpoint_fixture
    doctor_load_module_selection
    state_module_is_selected lang.bun
    if state_module_is_selected agents.claude; then fail "installed scope replaced the explicit custom checkpoint"; fi
    check agent.claude Claude fail missing "install claude"
    check tool.bun Bun fail missing "install bun"
    doctor_selection_json | jq -e '
        .[0].status == "skip" and .[0].fix == null and
        .[1].status == "fail" and .[1].fix == "install bun"
    ' >/dev/null
}

@test "doctor selection: missing malformed or foreign custom checkpoints never fall back or authorize repairs" {
    doctor_custom_checkpoint_fixture
    check_identity() { printf 'unexpected diagnostic\n' >> "$DOCTOR_TEST_PROBES"; }
    doctor_fix_init() { printf 'unexpected repair\n' >> "$DOCTOR_TEST_PROBES"; }
    custom_scope_doctor() { main --json --fix 2> "$BATS_TEST_TMPDIR/custom-selection-error"; }

    local state_kind=""
    for state_kind in missing malformed foreign_home foreign_user missing_identity; do
        ACFS_STATE_FILE="$BATS_TEST_TMPDIR/custom-$state_kind.json"
        case "$state_kind" in
            missing) ;;
            malformed) printf '%s\n' '{broken' > "$ACFS_STATE_FILE" ;;
            foreign_home)
                jq -n --arg user "$TARGET_USER" '{target_home:"/other/account",target_user:$user,module_selection:{schema_version:1,selected_modules:["lang.bun"]}}' > "$ACFS_STATE_FILE"
                ;;
            foreign_user)
                jq -n --arg home "$TARGET_HOME" '{target_home:$home,target_user:"other_account",module_selection:{schema_version:1,selected_modules:["lang.bun"]}}' > "$ACFS_STATE_FILE"
                ;;
            missing_identity)
                printf '%s\n' '{"module_selection":{"schema_version":1,"selected_modules":["lang.bun"]}}' > "$ACFS_STATE_FILE"
                ;;
        esac
        run custom_scope_doctor
        [[ "$status" -eq 1 ]] || fail "$state_kind returned $status: $output"
        [[ ! -e "$DOCTOR_TEST_PROBES" ]] || fail "$state_kind ran a diagnostic or repair"
        printf '%s\n' "$output" | jq -e '.summary.fail == 1 and .checks[0].id == "config.module_selection"' >/dev/null
    done
}

@test "doctor selection: an exported missing canonical checkpoint keeps legacy behavior" {
    doctor_custom_checkpoint_fixture
    ACFS_STATE_FILE="$ACFS_HOME/state.json"
    doctor_load_module_selection
    [[ "$ACFS_STATE_SELECTION_MODE" == legacy ]]
    state_module_is_selected agents.claude
    state_module_is_selected lang.bun
}

@test "doctor selection: canonical checkpoints reject conflicting identities before any diagnostics or repairs" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["lang.bun"]}}'
    check_identity() { printf 'unexpected diagnostic\n' >> "$DOCTOR_TEST_PROBES"; }
    run_doctor_fix() { printf 'unexpected repair initialization\n' >> "$DOCTOR_TEST_PROBES"; }
    canonical_scope_doctor() { main --json --fix 2> "$BATS_TEST_TMPDIR/canonical-selection-error"; }

    local discovery="" identity=""
    for discovery in automatic explicit; do
        ACFS_STATE_FILE=""
        [[ "$discovery" != explicit ]] || ACFS_STATE_FILE="$DOCTOR_TEST_STATE"
        for identity in foreign_home foreign_user null_home null_user; do
            case "$identity" in
                foreign_home)
                    jq -n --arg user "$TARGET_USER" '{target_home:"/other/account",target_user:$user}' > "$DOCTOR_TEST_STATE"
                    ;;
                foreign_user)
                    jq -n --arg home "$TARGET_HOME" '{target_home:$home,target_user:"other_account"}' > "$DOCTOR_TEST_STATE"
                    ;;
                null_home)
                    jq -n --arg user "$TARGET_USER" '{target_home:null,target_user:$user}' > "$DOCTOR_TEST_STATE"
                    ;;
                null_user)
                    jq -n --arg home "$TARGET_HOME" '{target_home:$home,target_user:null}' > "$DOCTOR_TEST_STATE"
                    ;;
            esac
            run doctor_load_module_selection
            [[ "$status" -eq 1 ]] || fail "$discovery $identity authorized foreign installation policy"
            run canonical_scope_doctor
            [[ "$status" -eq 1 ]] || fail "$discovery $identity returned $status: $output"
            [[ ! -e "$DOCTOR_TEST_PROBES" ]] || fail "$discovery $identity authorized diagnostics or repairs"
            printf '%s\n' "$output" | jq -e '
                .summary.fail == 1 and (.checks | length) == 1 and
                .checks[0].id == "config.module_selection" and .checks[0].fix == null
            ' >/dev/null
        done
    done
}

@test "doctor selection: legacy canonical checkpoints without identity still diagnose their saved scope" {
    doctor_selection_fixture '{"mode":"safe","module_selection":{"schema_version":1,"selected_modules":["lang.bun"]}}'
    ACFS_STATE_FILE="$DOCTOR_TEST_STATE"
    doctor_load_module_selection
    state_module_is_selected lang.bun
    if state_module_is_selected agents.claude; then fail "legacy checkpoint lost its selected scope"; fi
    check tool.bun Bun fail missing "install bun"
    check agent.claude Claude fail missing "install claude"
    doctor_selection_json | jq -e '.[0].status == "fail" and .[1].status == "skip"' >/dev/null
}

@test "doctor selection: system fallback requires the resolved target identity and never replaces an unsafe canonical checkpoint" {
    doctor_custom_checkpoint_fixture
    DOCTOR_TEST_STATE="$ACFS_HOME/state.json"
    ACFS_STATE_FILE=""
    ACFS_SYSTEM_STATE_FILE="$BATS_TEST_TMPDIR/system-state.json"
    jq -n --arg home "$TARGET_HOME" --arg user "$TARGET_USER" \
        '{target_home:$home,target_user:$user,mode:"safe",module_selection:{schema_version:1,selected_modules:["lang.bun"]}}' > "$ACFS_SYSTEM_STATE_FILE"
    doctor_load_module_selection
    state_module_is_selected lang.bun
    if state_module_is_selected agents.claude; then fail "system fallback used unrelated installed scope"; fi

    ln -s "$BATS_TEST_TMPDIR/missing-canonical-state.json" "$DOCTOR_TEST_STATE"
    run doctor_load_module_selection
    [[ "$status" -eq 1 ]] || fail "system fallback replaced a dangling canonical checkpoint"

    # A fresh target with no canonical checkpoint must also reject a foreign
    # or unidentified system state instead of treating it as a legacy install.
    TARGET_HOME="$BATS_TEST_TMPDIR/other-system-target"
    ACFS_HOME="$TARGET_HOME/.acfs"
    DOCTOR_TEST_STATE="$ACFS_HOME/state.json"
    mkdir -p "$ACFS_HOME"
    local identity=""
    for identity in foreign_home foreign_user missing_identity; do
        case "$identity" in
            foreign_home)
                jq -n --arg user "$TARGET_USER" '{target_home:"/other/account",target_user:$user}' > "$ACFS_SYSTEM_STATE_FILE"
                ;;
            foreign_user)
                jq -n --arg home "$TARGET_HOME" '{target_home:$home,target_user:"other_account"}' > "$ACFS_SYSTEM_STATE_FILE"
                ;;
            missing_identity) printf '{}\n' > "$ACFS_SYSTEM_STATE_FILE" ;;
        esac
        run doctor_load_module_selection
        [[ "$status" -eq 1 ]] || fail "$identity system checkpoint authorized a diagnostic run"
    done
}

@test "doctor selection: the validated checkpoint determines safe or vibe sudo diagnostics" {
    doctor_custom_checkpoint_fixture
    _acfs_doctor_resolve_current_user() { printf '%s\n' "$TARGET_USER"; }
    _acfs_doctor_system_binary_path() { return 1; }
    _acfs_doctor_has_sudo_entitlement() { return 0; }

    local mode="" expected_id="" expected_status=""
    for mode in safe vibe; do
        jq -n --arg home "$TARGET_HOME" --arg user "$TARGET_USER" --arg mode "$mode" \
            '{target_home:$home,target_user:$user,mode:$mode,module_selection:{schema_version:1,selected_modules:["users.ubuntu"]}}' > "$ACFS_STATE_FILE"
        ACFS_MODE=vibe
        expected_id=identity.sudo
        expected_status=pass
        if [[ "$mode" == vibe ]]; then
            ACFS_MODE=safe
            expected_id=identity.passwordless_sudo
            expected_status=fail
        fi
        JSON_CHECKS=()
        doctor_load_module_selection
        check_identity
        [[ "$ACFS_MODE" == "$mode" ]] || fail "saved $mode policy was overridden by ambient mode"
        doctor_selection_json | jq -e --arg id "$expected_id" --arg status "$expected_status" '
            .[1].id == $id and .[1].status == $status
        ' >/dev/null
    done
}

doctor_managed_sudo_fixture() {
    doctor_selection_fixture '{"mode":"safe","module_selection":{"schema_version":1,"selected_modules":["users.ubuntu"]}}'
    DOCTOR_TEST_SUDO_FILE="$BATS_TEST_TMPDIR/90-ubuntu-acfs"
    DOCTOR_TEST_REAL_STAT="$(command -v stat)"
    DOCTOR_TEST_STAT="$BATS_TEST_TMPDIR/policy-stat"
    # The fixture is owned by the unprivileged test account. Substitute only
    # the kernel owner field; file contents, modes, link counts, and all actual
    # policy-reader/diagnostic behavior remain unchanged.
    cat > "$DOCTOR_TEST_STAT" <<EOF
#!/bin/bash
metadata=\$("$DOCTOR_TEST_REAL_STAT" "\$@") || exit \$?
printf '0:%s\\n' "\${metadata#*:}"
EOF
    chmod +x "$DOCTOR_TEST_STAT"
    _acfs_doctor_managed_sudo_policy_file() { printf '%s\n' "$DOCTOR_TEST_SUDO_FILE"; }
    _acfs_doctor_system_binary_path() {
        case "$1" in
            stat) printf '%s\n' "$DOCTOR_TEST_STAT" ;;
            sudo) return 1 ;;
            *) PATH=/usr/sbin:/usr/bin:/sbin:/bin command -v "$1" ;;
        esac
    }
    _acfs_doctor_resolve_current_user() { printf '%s\n' "$TARGET_USER"; }
    _acfs_doctor_has_sudo_entitlement() { return 0; }
}

@test "doctor safe mode: stale ACFS passwordless policy cannot pass as safe sudo" {
    doctor_managed_sudo_fixture
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$TARGET_USER" > "$DOCTOR_TEST_SUDO_FILE"
    chmod 0440 "$DOCTOR_TEST_SUDO_FILE"
    check_identity
    [[ "$FAIL_COUNT" -eq 1 ]] || fail "stale vibe policy was not a failure"
    doctor_selection_json | jq -e '
        any(.id == "identity.sudo" and .status == "pass") and
        any(.id == "identity.acfs_sudo_policy" and .status == "fail" and
            (.details | contains("passwordless")) and (.fix | contains("--mode safe")))
    ' >/dev/null
}

@test "doctor safe mode: absent and password-required managed rules report only ACFS policy" {
    doctor_managed_sudo_fixture
    local state=""
    for state in absent password; do
        if [[ "$state" == password ]]; then
            printf '%s ALL=(ALL) PASSWD:ALL\n' "$TARGET_USER" > "$DOCTOR_TEST_SUDO_FILE"
            chmod 0440 "$DOCTOR_TEST_SUDO_FILE"
        fi
        JSON_CHECKS=()
        check_identity
        doctor_selection_json | jq -e '
            any(.id == "identity.acfs_sudo_policy" and .status == "pass" and
                (.details | contains("other sudo policies are not evaluated")))
        ' >/dev/null
    done
}

@test "doctor safe mode: custom unsafe and linked managed rules cannot certify the checkpoint" {
    doctor_managed_sudo_fixture
    local scenario=""
    for scenario in custom writable symlink hardlink foreign-owner; do
        DOCTOR_TEST_SUDO_FILE="$BATS_TEST_TMPDIR/policy-$scenario"
        printf '%s ALL=(ALL) PASSWD:ALL\n' "$TARGET_USER" > "$DOCTOR_TEST_SUDO_FILE"
        chmod 0440 "$DOCTOR_TEST_SUDO_FILE"
        case "$scenario" in
            custom)
                chmod 0640 "$DOCTOR_TEST_SUDO_FILE"
                printf 'another-user ALL=(ALL) NOPASSWD:ALL\n' > "$DOCTOR_TEST_SUDO_FILE"
                chmod 0440 "$DOCTOR_TEST_SUDO_FILE"
                ;;
            writable) chmod 0660 "$DOCTOR_TEST_SUDO_FILE" ;;
            symlink)
                ln -s "$DOCTOR_TEST_SUDO_FILE" "$DOCTOR_TEST_SUDO_FILE.link"
                DOCTOR_TEST_SUDO_FILE+=".link"
                ;;
            hardlink) ln "$DOCTOR_TEST_SUDO_FILE" "$DOCTOR_TEST_SUDO_FILE.link" ;;
            foreign-owner)
                # Keep the fixture independent of whether the test runner is
                # root by returning an explicitly foreign owner.
                cat > "$DOCTOR_TEST_STAT" <<EOF
#!/bin/bash
metadata=\$("$DOCTOR_TEST_REAL_STAT" "\$@") || exit \$?
printf '1234:%s\\n' "\${metadata#*:}"
EOF
                ;;
        esac
        JSON_CHECKS=()
        check_identity
        doctor_selection_json | jq -e '
            any(.id == "identity.acfs_sudo_policy" and .status == "fail")
        ' >/dev/null || fail "$scenario was accepted as a safe managed rule"
    done
}

@test "doctor safe mode: an unreadable managed-policy directory is unknown rather than absent" {
    doctor_managed_sudo_fixture
    # A non-directory parent cannot authorize an absent rule. Use it instead
    # of chmod 000 so the test retains its meaning when run as root.
    printf 'unreadable parent fixture\n' > "$BATS_TEST_TMPDIR/policy-parent"
    DOCTOR_TEST_SUDO_FILE="$BATS_TEST_TMPDIR/policy-parent/90-ubuntu-acfs"
    check_identity
    doctor_selection_json | jq -e '
        any(.id == "identity.acfs_sudo_policy" and .status == "warn" and
            (.details | contains("could not inspect")))
    ' >/dev/null
}

@test "doctor safe mode: excluded user normalization and vibe mode do not inspect safe policy" {
    doctor_managed_sudo_fixture
    _acfs_doctor_managed_sudo_policy_file() { printf 'read\n' >> "$BATS_TEST_TMPDIR/policy-read"; return 1; }
    ACFS_STATE_SELECTED_MODULES=(lang.bun)
    check_identity
    [[ ! -e "$BATS_TEST_TMPDIR/policy-read" ]]
    ACFS_STATE_SELECTED_MODULES=(users.ubuntu)
    ACFS_MODE=vibe
    check_identity
    [[ ! -e "$BATS_TEST_TMPDIR/policy-read" ]]
}

@test "doctor entrypoints: invalid explicit checkpoint paths fail before dispatch" {
    local entrypoint="" state_path=""
    for entrypoint in "$DOCTOR_SH" "$PROJECT_ROOT/scripts/acfs-global"; do
        for state_path in relative-state.json /; do
            run env ACFS_STATE_FILE="$state_path" bash "$entrypoint" doctor --json
            [[ "$status" -eq 1 ]] || fail "$entrypoint accepted $state_path: $output"
            [[ "$output" == *'ACFS_STATE_FILE must be an absolute non-root path'* ]] || fail "$output"
        done
    done
}

doctor_wrapper_checkpoint_fixture() {
    DOCTOR_WRAPPER_HOME="$BATS_TEST_TMPDIR/wrapper-home"
    DOCTOR_WRAPPER_CHECKPOINT="$BATS_TEST_TMPDIR/wrapper-custom.json"
    DOCTOR_WRAPPER_DISPATCH="$BATS_TEST_TMPDIR/wrapper-dispatch"
    DOCTOR_WRAPPER_USER="$(id -un)"
    mkdir -p "$DOCTOR_WRAPPER_HOME/.local/bin" "$DOCTOR_WRAPPER_HOME/.acfs"
    jq -n --arg home "$DOCTOR_WRAPPER_HOME" --arg user "$DOCTOR_WRAPPER_USER" \
        '{target_home:$home,target_user:$user,module_selection:{schema_version:1,selected_modules:["agents.claude"]}}' > "$DOCTOR_WRAPPER_HOME/.acfs/state.json"
    jq -n --arg home "$DOCTOR_WRAPPER_HOME" --arg user "$DOCTOR_WRAPPER_USER" \
        '{target_home:$home,target_user:$user,module_selection:{schema_version:1,selected_modules:["lang.bun"]}}' > "$DOCTOR_WRAPPER_CHECKPOINT"
    # The real wrapper launches this child. Use the production state reader to
    # verify the checkpoint transported across exec, independent of the wrapper's
    # discovery parser and the normal installed checkpoint beside the child.
    cat > "$DOCTOR_WRAPPER_HOME/.local/bin/acfs" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$ACFS_STATE_FILE" > "$DOCTOR_WRAPPER_DISPATCH"
source "$DOCTOR_WRAPPER_STATE_LIBRARY"
state_load_module_selection "$ACFS_STATE_FILE" "$TARGET_HOME" "$DOCTOR_WRAPPER_USER"
printf 'SELECTED=%s\n' "${ACFS_STATE_SELECTED_MODULES[*]}"
EOF
    chmod +x "$DOCTOR_WRAPPER_HOME/.local/bin/acfs"
}

run_doctor_wrapper_checkpoint() {
    run env HOME="$DOCTOR_WRAPPER_HOME" TARGET_HOME="$DOCTOR_WRAPPER_HOME" \
        ACFS_HOME="$DOCTOR_WRAPPER_HOME/.acfs" ACFS_STATE_FILE="$DOCTOR_WRAPPER_CHECKPOINT" \
        ACFS_SYSTEM_STATE_FILE="$BATS_TEST_TMPDIR/no-system-state.json" \
        DOCTOR_WRAPPER_DISPATCH="$DOCTOR_WRAPPER_DISPATCH" DOCTOR_WRAPPER_USER="$DOCTOR_WRAPPER_USER" \
        DOCTOR_WRAPPER_STATE_LIBRARY="$PROJECT_ROOT/scripts/lib/state.sh" \
        bash "$PROJECT_ROOT/scripts/acfs-global" doctor --json
}

@test "doctor wrapper: real dispatch preserves the requested custom checkpoint" {
    doctor_wrapper_checkpoint_fixture
    run_doctor_wrapper_checkpoint
    [[ "$status" -eq 0 ]] || fail "$output"
    [[ "$output" == 'SELECTED=lang.bun' ]] || fail "$output"
    [[ "$(cat "$DOCTOR_WRAPPER_DISPATCH")" == "$DOCTOR_WRAPPER_CHECKPOINT" ]]
}

@test "doctor wrapper: broken custom checkpoints reach validation instead of installed-state fallback" {
    doctor_wrapper_checkpoint_fixture
    local state_kind=""
    for state_kind in missing malformed foreign; do
        DOCTOR_WRAPPER_CHECKPOINT="$BATS_TEST_TMPDIR/wrapper-$state_kind.json"
        case "$state_kind" in
            missing) ;;
            malformed) printf '%s\n' '{broken' > "$DOCTOR_WRAPPER_CHECKPOINT" ;;
            foreign)
                jq -n --arg user "$DOCTOR_WRAPPER_USER" '{target_home:"/other/account",target_user:$user,module_selection:{schema_version:1,selected_modules:["lang.bun"]}}' > "$DOCTOR_WRAPPER_CHECKPOINT"
                ;;
        esac
        run_doctor_wrapper_checkpoint
        [[ "$status" -eq 1 ]] || fail "$state_kind returned $status: $output"
        [[ "$(cat "$DOCTOR_WRAPPER_DISPATCH")" == "$DOCTOR_WRAPPER_CHECKPOINT" ]] || fail "$state_kind checkpoint was replaced"
        [[ "$output" != *SELECTED=* ]] || fail "$state_kind bypassed validation"
    done
}

@test "doctor selection: excluded agent and cloud binaries are never executed; selected Bun passes" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["base.system","lang.bun"]}}'
    doctor_selection_binary claude
    doctor_selection_binary vercel
    doctor_selection_binary bun

    check_command agent.claude Claude claude "install claude"
    check_optional_command cloud.vercel Vercel vercel "install vercel"
    check_command tool.bun Bun bun "install bun"
    check_command tool.minisign Minisign minisign "install minisign"
    check_command tool.zstd Zstd zstd "install zstd"

    [ "$(cat "$DOCTOR_TEST_PROBES")" = bun ]
    [ "$PASS_COUNT:$WARN_COUNT:$FAIL_COUNT:$SKIP_COUNT" = 1:0:0:4 ]
    doctor_selection_json | jq -e '
        .[0].id == "agent.claude" and .[0].status == "skip" and .[0].fix == null and
        .[1].id == "cloud.vercel" and .[1].status == "skip" and .[1].fix == null and
        .[2].id == "tool.bun" and .[2].status == "pass" and
        .[3].id == "tool.minisign" and .[3].status == "skip" and
        .[4].id == "tool.zstd" and .[4].status == "skip"' >/dev/null
}

@test "doctor selection: selected missing capabilities still fail and only their repairs are queued" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["base.system","lang.bun"]}}'
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_command agent.claude Claude claude "install claude"
    check_command tool.bun Bun bun "install bun"

    [ "$FAIL_COUNT:$SKIP_COUNT" = 1:1 ]
    [ "${DOCTOR_FIX_OBSERVED_IDS[*]}" = 'agent.claude tool.bun' ]
    [ "${DOCTOR_FIX_PENDING_IDS[*]}" = tool.bun ]
    [ "${DOCTOR_FIX_PENDING_HINTS[*]}" = 'install bun' ]
    doctor_selection_json | jq -e '.[1].status == "fail" and .[1].fix == "install bun"' >/dev/null
}

@test "doctor selection: broken selected agent launchers fail despite executable files and plausible banners" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["agents.codex","agents.claude","lang.bun"]}}'
    doctor_selection_binary bun
    doctor_selection_binary agy
    cat > "$DOCTOR_TEST_BIN/codex" <<'EOF'
#!/bin/bash
exec /nonexistent-acfs-fixture-runtime "$@"
EOF
    cat > "$DOCTOR_TEST_BIN/claude" <<'EOF'
#!/bin/bash
printf 'claude fixture 99.0\n'
exit 42
EOF
    chmod +x "$DOCTOR_TEST_BIN/codex" "$DOCTOR_TEST_BIN/claude"
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    # These checks replace the manifest probes, so they must establish actual
    # launcher readiness before a selected installation can be certified.
    _is_bespoke_covered agents.codex
    _is_bespoke_covered agents.claude
    check_command agent.codex Codex codex "repair codex"
    check_command agent.claude Claude claude "repair claude"
    check_command tool.bun Bun bun "repair bun"
    check_command agent.antigravity Antigravity agy "repair agy"

    [ "$FAIL_COUNT:$PASS_COUNT:$SKIP_COUNT" = 2:1:1 ]
    [ "${DOCTOR_FIX_PENDING_IDS[*]}" = 'agent.codex agent.claude' ]
    [ "$(cat "$DOCTOR_TEST_PROBES")" = bun ]
    doctor_selection_json | jq -e '
        .[0].status == "fail" and .[0].fix == "repair codex" and
        .[1].status == "fail" and .[1].fix == "repair claude" and
        .[2].status == "pass" and .[3].status == "skip"' >/dev/null
}

@test "doctor selection: broken optional utilities honor requested severity and excluded tools stay untouched" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["utils.toon_rust","utils.rano"],"requested_modules":["utils.toon_rust"]}}'
    local binary=""
    for binary in toon rano xf; do
        cat > "$DOCTOR_TEST_BIN/$binary" <<'EOF'
#!/bin/bash
printf '%s\n' "${0##*/}" >> "$DOCTOR_TEST_PROBES"
printf 'plausible version 1.0\n'
exit 42
EOF
        chmod +x "$DOCTOR_TEST_BIN/$binary"
    done
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_utilities

    [ "$FAIL_COUNT:$WARN_COUNT:$SKIP_COUNT" = 1:1:7 ]
    [ "${DOCTOR_FIX_PENDING_IDS[*]}" = 'util.tru util.rano' ]
    run grep -q xf "$DOCTOR_TEST_PROBES"
    assert_failure 1
    doctor_selection_json | jq -e '
        ([.[] | select(.status == "fail") | .id] == ["util.tru"]) and
        ([.[] | select(.status == "warn") | .id] == ["util.rano"]) and
        all(.[] | select(.status == "fail" or .status == "warn");
            (.details | contains("verification failed")) and (.fix | contains("--only")))' >/dev/null
}

@test "doctor selection: Antigravity runs its generated locked-settings and hook verification" {
    doctor_selection_fixture '{"mode":"vibe","module_selection":{"schema_version":1,"selected_modules":["agents.antigravity"]}}'
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$ACFS_BIN_DIR"
    local binary="" entry="" agy_check=""
    for binary in agy agy-locked agy-real gmi; do
        printf '#!/bin/bash\nprintf "agy fixture 1.0\\n"\n' > "$ACFS_BIN_DIR/$binary"
        chmod +x "$ACFS_BIN_DIR/$binary"
    done
    # Resolve the target account to this isolated home while retaining the
    # real target-user transport and the unmodified generated verification.
    _acfs_doctor_getent_passwd_entry() {
        printf '%s:x:%s:%s::%s:/bin/bash\n' "$TARGET_USER" "$UID" "$(id -g)" "$TARGET_HOME"
    }
    for entry in "${MANIFEST_CHECKS[@]}"; do
        if [[ "$entry" == agents.antigravity$'\t'* ]]; then
            agy_check="$entry"
            break
        fi
    done
    [[ -n "$agy_check" ]] || fail "generated Antigravity verification was not found"
    MANIFEST_CHECKS=("$agy_check")
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    # The actual shipped launcher establishes the expected settings and hook.
    HOME="$TARGET_HOME" /usr/bin/python3 "$PROJECT_ROOT/scripts/lib/agy_locked.py" --acfs-prime-settings
    check_manifest_supplemental
    [ "$PASS_COUNT:$FAIL_COUNT" = 1:0 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]

    # A working --version is insufficient after hook registration is lost.
    printf '{}\n' > "$TARGET_HOME/.gemini/config/hooks.json"
    check_manifest_supplemental
    [ "$PASS_COUNT:$FAIL_COUNT" = 1:1 ]
    [ "${DOCTOR_FIX_PENDING_IDS[*]}" = agents.antigravity ]
    doctor_selection_json | jq -e '
        .[0].id == "agents.antigravity" and .[0].status == "pass" and
        .[1].id == "agents.antigravity" and .[1].status == "fail" and
        (.[1].fix | contains("--only agents.antigravity"))' >/dev/null
}

@test "doctor selection: Antigravity honors saved Safe mode in generated manifest checks" {
    doctor_selection_fixture '{"mode":"safe","module_selection":{"schema_version":1,"selected_modules":["agents.antigravity"]}}'
    export ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    mkdir -p "$ACFS_BIN_DIR"
    local binary="" entry="" agy_check=""
    for binary in agy agy-locked agy-real gmi; do
        printf '#!/bin/bash\nprintf "agy fixture 1.0\\n"\n' > "$ACFS_BIN_DIR/$binary"
        chmod +x "$ACFS_BIN_DIR/$binary"
    done
    # Resolve the target account to this isolated home while retaining the
    # real target-user transport and the unmodified generated verification.
    _acfs_doctor_getent_passwd_entry() {
        printf '%s:x:%s:%s::%s:/bin/bash\n' "$TARGET_USER" "$UID" "$(id -g)" "$TARGET_HOME"
    }
    for entry in "${MANIFEST_CHECKS[@]}"; do
        if [[ "$entry" == agents.antigravity$'\t'* ]]; then
            agy_check="$entry"
            break
        fi
    done
    [[ -n "$agy_check" ]] || fail "generated Antigravity verification was not found"
    MANIFEST_CHECKS=("$agy_check")
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    # The actual shipped launcher establishes the expected settings and hook.
    HOME="$TARGET_HOME" /usr/bin/python3 "$PROJECT_ROOT/scripts/lib/agy_locked.py" --acfs-prime-settings
    check_manifest_supplemental
    [ "$PASS_COUNT:$FAIL_COUNT" = 1:0 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]

    # A working --version is insufficient after hook registration is lost.
    sed -i 's/"request-review"/"always-proceed"/' "$TARGET_HOME/.gemini/antigravity-cli/settings.json"
    check_manifest_supplemental
    [ "$PASS_COUNT:$FAIL_COUNT" = 1:1 ]
    [ "${DOCTOR_FIX_PENDING_IDS[*]}" = agents.antigravity ]
    doctor_selection_json | jq -e '
        .[0].id == "agents.antigravity" and .[0].status == "pass" and
        .[1].id == "agents.antigravity" and .[1].status == "fail" and
        (.[1].fix | contains("--only agents.antigravity"))' >/dev/null
}

@test "doctor selection: bespoke stack checks reject broken launchers before service and hook checks" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["stack.dcg","stack.beads_viewer","stack.mcp_agent_mail","stack.rch"],"requested_modules":["stack.dcg","stack.mcp_agent_mail","stack.rch"]}}'
    local binary=""
    for binary in dcg bv am rch; do
        cat > "$DOCTOR_TEST_BIN/$binary" <<'EOF'
#!/bin/bash
printf 'plausible version 1.0\n'
exit 42
EOF
        chmod +x "$DOCTOR_TEST_BIN/$binary"
    done
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_stack

    [ "$FAIL_COUNT:$WARN_COUNT:$PASS_COUNT" = 4:0:0 ]
    doctor_selection_json | jq -e '
        ([.[] | select(.status == "fail") | .id] | sort) ==
            ["stack.bv","stack.dcg","stack.mcp_agent_mail","stack.rch"] and
        all(.[] | select(.status == "fail"); .details | contains("verification failed"))' >/dev/null
}

@test "doctor selection: missing explicitly requested stack tools fail and queue only their repairs" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["stack.dcg","stack.mcp_agent_mail","stack.ru","stack.beads_rust","stack.meta_skill","stack.rch"],"requested_modules":["stack.dcg","stack.mcp_agent_mail","stack.ru","stack.beads_rust","stack.meta_skill","stack.rch"]}}'
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_stack

    [ "$FAIL_COUNT:$WARN_COUNT:$PASS_COUNT" = 6:0:0 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 6 ]
    doctor_selection_json | jq -e '
        ([.[] | select(.status == "fail") | .id] | sort) ==
            ["stack.beads_rust","stack.dcg","stack.mcp_agent_mail","stack.meta_skill","stack.rch","stack.ru"] and
        all(.[] | select(.status == "fail"); .details == "not installed" and (.fix | contains("--only"))) and
        all(.[] | select(.status == "skip"); .fix == null)' >/dev/null
    [ ! -e "$DOCTOR_TEST_PROBES" ]
}

doctor_dcg_settings_fixture() {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["stack.dcg","agents.claude"]}}'
    doctor_selection_binary dcg
    doctor_selection_binary claude
    unset CLAUDE_CONFIG_DIR
    mkdir -p "$TARGET_HOME/.claude"
    printf '{}\n' > "$TARGET_HOME/.claude/settings.json"
}

doctor_dcg_registered_settings() {
    mkdir -p "$1"
    printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"dcg"}]}]}}' > "$1/settings.json"
}

@test "doctor DCG settings: the configured same-account directory is authoritative" {
    doctor_dcg_settings_fixture
    export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/custom Claude configuration"
    doctor_dcg_registered_settings "$CLAUDE_CONFIG_DIR"

    check_dcg_hook_status
    [ "$PASS_COUNT:$WARN_COUNT" = 1:0 ]

    # A hook in the inactive default cannot hide a broken selected profile.
    doctor_dcg_registered_settings "$TARGET_HOME/.claude"
    printf '{}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
    check_dcg_hook_status
    [ "$PASS_COUNT:$WARN_COUNT" = 1:1 ]
    doctor_selection_json | jq -e '
        .[0].status == "pass" and .[1].status == "warn" and
        (.[1].details | contains("hook not registered"))' >/dev/null
}

@test "doctor DCG settings: relative and home-relative config paths match the repair location" {
    doctor_dcg_settings_fixture
    cd "$BATS_TEST_TMPDIR"
    local config=""
    for config in 'relative Claude configuration' '~/.custom Claude configuration'; do
        export CLAUDE_CONFIG_DIR="$config"
        case "$config" in
            \~/*) doctor_dcg_registered_settings "$TARGET_HOME/${config#\~/}" ;;
            *) doctor_dcg_registered_settings "$PWD/$config" ;;
        esac
        check_dcg_hook_status
    done
    [ "$PASS_COUNT:$WARN_COUNT" = 2:0 ]
}

@test "doctor DCG settings: invoking-home hooks cannot certify another target" {
    doctor_dcg_settings_fixture
    local caller_home="$BATS_TEST_TMPDIR/caller-home"
    doctor_dcg_registered_settings "$caller_home/.claude"
    # No target settings file: only the caller has a registered hook.
    TARGET_HOME="$BATS_TEST_TMPDIR/target-without-settings"
    mkdir -p "$TARGET_HOME"

    HOME="$caller_home" check_dcg_hook_status
    [ "$PASS_COUNT:$WARN_COUNT" = 0:1 ]
    doctor_selection_json | jq -e '.[0].status == "warn" and (.[0].details | contains("settings.json missing"))' >/dev/null
}

@test "doctor DCG settings: another account's override is ignored and invalid same-account selectors cannot authorize repairs" {
    doctor_dcg_settings_fixture
    doctor_dcg_registered_settings "$TARGET_HOME/.claude"
    export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/foreign-config"
    _acfs_doctor_resolve_current_user() { printf '%s\n' other-account; }
    check_dcg_hook_status
    [ "$PASS_COUNT:$WARN_COUNT" = 1:0 ]

    _acfs_doctor_resolve_current_user() { printf '%s\n' "$TARGET_USER"; }
    CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/custom"$'\nRU_NON_INTERACTIVE=1'
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true
    check_dcg_hook_status
    [ "$PASS_COUNT:$WARN_COUNT" = 1:1 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    doctor_selection_json | jq -e '.[1].status == "warn" and (.[1].details | contains("configuration directory"))' >/dev/null
}

doctor_tailscale_fixture() {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["network.tailscale","lang.bun"],"requested_modules":["network.tailscale"]}}'
    ACFS_DOCTOR_CI=false
    # This fixture exercises only Tailscale; keep SSH service discovery local
    # and avoid querying the runner's service manager.
    DOCTOR_TEST_DEADLINE_BIN="$(_acfs_doctor_system_binary_path timeout)" || return 1
    _acfs_doctor_system_binary_path() {
        case "$1" in
            sshd|systemctl) return 1 ;;
            timeout) printf '%s\n' "$DOCTOR_TEST_DEADLINE_BIN"; return ;;
        esac
        [[ -x "/usr/bin/$1" ]] || return 1
        printf '/usr/bin/%s\n' "$1"
    }
    cat > "$DOCTOR_TEST_BIN/tailscale" <<'EOF'
#!/bin/bash
printf 'tailscale %s\n' "$*" >> "$DOCTOR_TEST_PROBES"
case "$DOCTOR_TAILSCALE_CASE" in
    running) printf '{"BackendState":"Running"}\n' ;;
    login) printf '{"BackendState":"NeedsLogin"}\n' ;;
    failed) printf '{"BackendState":"Running"}\n'; exit 42 ;;
    malformed) printf 'not JSON\n' ;;
    stalled)
        trap '' TERM
        sleep 12 &
        printf '%s\n' "$!" > "$DOCTOR_TEST_CHILD_PID"
        wait
        printf escaped >> "$DOCTOR_TEST_ESCAPED"
        printf '{"BackendState":"Running"}\n'
        ;;
    orphaned)
        (
            trap '' TERM
            sleep 12
            printf escaped >> "$DOCTOR_TEST_ESCAPED"
            printf '{"BackendState":"Running"}\n'
        ) &
        printf '%s\n' "$!" > "$DOCTOR_TEST_CHILD_PID"
        exit 0
        ;;
esac
EOF
    chmod +x "$DOCTOR_TEST_BIN/tailscale"
    export DOCTOR_TAILSCALE_CASE=running
}

@test "doctor Tailscale: requested missing and nonzero launchers cannot pass as installed" {
    doctor_tailscale_fixture
    export DOCTOR_TAILSCALE_CASE=failed
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true
    check_cloud
    doctor_selection_json | jq -e '
        any(.[]; .id == "network.tailscale" and .status == "fail" and
            (.details | contains("exit 42")))' >/dev/null

    DOCTOR_TEST_BIN="$BATS_TEST_TMPDIR/no-tailscale"
    mkdir -p "$DOCTOR_TEST_BIN"
    check_cloud
    doctor_selection_json | jq -e '
        [.[] | select(.id == "network.tailscale")] | length == 2 and
        all(.status == "fail") and (.[1].fix | contains("--only network.tailscale"))' >/dev/null
}

@test "doctor Tailscale: successful status distinguishes connected from login-required and malformed output" {
    doctor_tailscale_fixture
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true
    local mode=""
    for mode in running login malformed; do
        export DOCTOR_TAILSCALE_CASE="$mode"
        check_cloud
    done
    doctor_selection_json | jq -e '
        [.[] | select(.id == "network.tailscale")] |
        .[0].status == "pass" and .[0].details == "connected" and
        .[1].status == "warn" and .[1].details == "needs login" and
        .[2].status == "warn" and (.[2].details | contains("invalid status"))' >/dev/null
    # Login requires user action. Invalid output must not authorize a repair.
    [[ " ${DOCTOR_FIX_PENDING_IDS[*]} " != *' network.tailscale '* ]] \
        || fail "an inconclusive or authentication-only result queued a repair"
}

@test "doctor Tailscale: a TERM-resistant status child is bounded and does not block later checks or authorize repair" {
    doctor_tailscale_fixture
    export DOCTOR_TAILSCALE_CASE=stalled
    export DOCTOR_TEST_CHILD_PID="$BATS_TEST_TMPDIR/tailscale-child"
    export DOCTOR_TEST_ESCAPED="$BATS_TEST_TMPDIR/tailscale-escaped"
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_cloud
    [ -s "$DOCTOR_TEST_CHILD_PID" ]
    [ ! -e "$DOCTOR_TEST_ESCAPED" ]
    local child_state=""
    child_state="$(ps -o stat= -p "$(cat "$DOCTOR_TEST_CHILD_PID")" 2>/dev/null || true)"
    [[ -z "$child_state" || "$child_state" == Z* ]] || fail "status child is still running: $child_state"
    [[ " ${DOCTOR_FIX_PENDING_IDS[*]} " != *' network.tailscale '* ]] \
        || fail "timeout queued a repair"
    doctor_selection_json | jq -e '
        any(.[]; .id == "network.tailscale" and .status == "timeout" and
            (.details | contains("deadline")))' >/dev/null

    doctor_selection_binary bun
    check_command tool.bun Bun bun "install bun"
    doctor_selection_json | jq -e '.[-1].id == "tool.bun" and .[-1].status == "pass"' >/dev/null
}

@test "doctor Tailscale: an exited launcher cannot leave an orphaned output writer past the deadline" {
    doctor_tailscale_fixture
    export DOCTOR_TAILSCALE_CASE=orphaned
    export DOCTOR_TEST_CHILD_PID="$BATS_TEST_TMPDIR/tailscale-child"
    export DOCTOR_TEST_ESCAPED="$BATS_TEST_TMPDIR/tailscale-escaped"
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_cloud
    [ -s "$DOCTOR_TEST_CHILD_PID" ]
    [ ! -e "$DOCTOR_TEST_ESCAPED" ]
    local child_state=""
    child_state="$(ps -o stat= -p "$(cat "$DOCTOR_TEST_CHILD_PID")" 2>/dev/null || true)"
    [[ -z "$child_state" || "$child_state" == Z* ]] || fail "orphaned output writer is still running: $child_state"
    [[ " ${DOCTOR_FIX_PENDING_IDS[*]} " != *' network.tailscale '* ]] \
        || fail "orphaned output writer queued a repair"
    doctor_selection_json | jq -e '
        any(.[]; .id == "network.tailscale" and .status == "timeout" and
            (.details | contains("deadline")))' >/dev/null

    doctor_selection_binary bun
    check_command tool.bun Bun bun "install bun"
    doctor_selection_json | jq -e '.[-1].id == "tool.bun" and .[-1].status == "pass"' >/dev/null
}

@test "doctor Tailscale: missing timeout support refuses execution and excluded tools remain unprobed" {
    doctor_tailscale_fixture
    _acfs_doctor_system_binary_path() {
        case "$1" in timeout|sshd|systemctl) return 1 ;; esac
        [[ -x "/usr/bin/$1" ]] || return 1
        printf '/usr/bin/%s\n' "$1"
    }
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true
    check_cloud
    [ ! -e "$DOCTOR_TEST_PROBES" ]
    [[ " ${DOCTOR_FIX_PENDING_IDS[*]} " != *' network.tailscale '* ]] \
        || fail "missing timeout support queued a repair"
    doctor_selection_json | jq -e '
        any(.[]; .id == "network.tailscale" and .status == "fail" and
            (.details | contains("verification unavailable")))' >/dev/null

    ACFS_STATE_SELECTED_MODULES=(lang.bun)
    check_cloud
    [ ! -e "$DOCTOR_TEST_PROBES" ]
    doctor_selection_json | jq -e '
        [.[] | select(.id == "network.tailscale")] | .[-1].status == "skip" and .[-1].fix == null' >/dev/null
}

@test "doctor selection: default-selected missing stack tools keep their warning policy" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["stack.dcg","stack.mcp_agent_mail","stack.ru","stack.beads_rust","stack.meta_skill","stack.rch"]}}'
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_stack

    [ "$FAIL_COUNT:$WARN_COUNT:$PASS_COUNT" = 0:6:0 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 6 ]
    doctor_selection_json | jq -e '
        ([.[] | select(.status == "warn") | .id] | sort) ==
            ["stack.beads_rust","stack.dcg","stack.mcp_agent_mail","stack.meta_skill","stack.rch","stack.ru"] and
        all(.[] | select(.status == "warn"); .details == "not installed" and .fix != null)' >/dev/null
    [ ! -e "$DOCTOR_TEST_PROBES" ]
}

@test "doctor selection: legacy missing bespoke stack tools keep their warning policy" {
    doctor_selection_fixture '{}'
    # The fixture has no tools; do not query the runner's systemd user session.
    _acfs_doctor_system_binary_path() { return 1; }

    check_stack

    doctor_selection_json | jq -e '
        [.[] | select(.id == "stack.beads_rust" or .id == "stack.dcg" or
            .id == "stack.mcp_agent_mail" or .id == "stack.meta_skill" or
            .id == "stack.rch" or .id == "stack.ru")] |
        length == 6 and all(.status == "warn" and .details == "not installed")' >/dev/null
    [ ! -e "$DOCTOR_TEST_PROBES" ]
}

@test "doctor selection: leftover install artifacts and unavailable releases cannot hide requested missing tools" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["stack.mcp_agent_mail","stack.meta_skill","stack.rch"],"requested_modules":["stack.mcp_agent_mail","stack.meta_skill","stack.rch"]}}'
    mkdir -p "$TARGET_HOME/mcp_agent_mail" "$TARGET_HOME/.config/rch"
    printf '%s\n' '[workers]' > "$TARGET_HOME/.config/rch/config.toml"
    uname() {
        case "${1:-}" in
            -m) printf '%s\n' mips64 ;;
            -s) printf '%s\n' Linux ;;
            *) return 1 ;;
        esac
    }
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_stack

    [ "$FAIL_COUNT:$WARN_COUNT:$PASS_COUNT" = 3:0:0 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 3 ]
    doctor_selection_json | jq -e '
        ([.[] | select(.status == "fail") | .id] | sort) ==
            ["stack.mcp_agent_mail","stack.meta_skill","stack.rch"] and
        any(.[]; .id == "stack.mcp_agent_mail" and .details == "install directory present but am CLI is missing") and
        any(.[]; .id == "stack.rch" and .details == "config exists but binary not in PATH") and
        any(.[]; .id == "stack.meta_skill" and (.fix | contains("no checksum-anchored installer for mips64-Linux")))' >/dev/null
    [ ! -e "$DOCTOR_TEST_PROBES" ]
}

@test "doctor selection: explicitly requested missing nightly timer fails despite a stale skipped marker" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["acfs.nightly"],"requested_modules":["acfs.nightly"]},"skipped_tools":["acfs.nightly"]}'
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    report_nightly_timer_status missing

    [ "$FAIL_COUNT:$WARN_COUNT:$SKIP_COUNT" = 1:0:0 ]
    [ "${DOCTOR_FIX_PENDING_IDS[*]}" = acfs.nightly ]
    doctor_selection_json | jq -e '
        length == 1 and .[0].id == "acfs.nightly" and .[0].status == "fail" and
        (.[0].fix | contains("--only acfs.nightly"))' >/dev/null
}

@test "doctor selection: excluded bespoke stack tools remain unprobed and never queue repairs" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["lang.bun"]}}'
    local binary=""
    for binary in dcg am ru br ms rch; do
        doctor_selection_binary "$binary"
    done
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_stack

    [ "$FAIL_COUNT:$WARN_COUNT:$PASS_COUNT" = 0:0:0 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    doctor_selection_json | jq -e 'length > 0 and all(.status == "skip" and .fix == null)' >/dev/null
    [ ! -e "$DOCTOR_TEST_PROBES" ]
}

@test "doctor selection: inconclusive launcher probes never queue or dispatch reinstallations" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["agents.codex","lang.bun"]}}'
    doctor_selection_binary bun
    cat > "$DOCTOR_TEST_BIN/codex" <<'EOF'
#!/bin/bash
printf 'credible version 1.0\n'
sleep 30
EOF
    chmod +x "$DOCTOR_TEST_BIN/codex"
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true
    DOCTOR_VERSION_TIMEOUT=0.1
    check_command agent.codex Codex codex "repair codex"
    DOCTOR_VERSION_TIMEOUT=0
    check_command tool.bun Bun bun "repair bun"

    [ "$WARN_COUNT:$PASS_COUNT:$FAIL_COUNT" = 2:0:0 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    [ "${DOCTOR_FIX_OBSERVED_IDS[*]}" = 'agent.codex tool.bun' ]
    [ ! -e "$DOCTOR_TEST_PROBES" ]
    doctor_selection_json | jq -e '
        .[0].status == "timeout" and .[1].status == "warn" and .[1].fix == null' >/dev/null

    DOCTOR_FIX_SCOPED=false
    dispatch_fix() { printf 'unexpected repair\n' >> "$DOCTOR_TEST_PROBES"; }
    check_command tool.bun Bun bun "repair bun"
    [ ! -e "$DOCTOR_TEST_PROBES" ]
}

@test "doctor selection: missing selected utilities and optional stack tools retain installation intent" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["utils.toon_rust","utils.rust_proxy","utils.rano","utils.xf","utils.mdwb","stack.process_triage","utils.aadc","utils.s2p","utils.caut","stack.wezterm_automata","stack.brenner_bot"],"requested_modules":["utils.toon_rust","stack.process_triage","stack.wezterm_automata"]},"skipped_tools":["utils.toon_rust","utils.rano"]}'
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_utilities
    check_stack

    [ "$FAIL_COUNT:$WARN_COUNT" = 3:8 ]
    doctor_selection_json | jq -e '
        ([.[] | select(.status == "fail") | .id] | sort) ==
            ["stack.wezterm_automata","util.pt","util.tru"] and
        ([.[] | select(.status == "warn")] | length) == 8 and
        all(.[] | select(.status == "fail" or .status == "warn");
            (.fix | contains("--only")) and (.details | contains("not installed"))) and
        all(.[] | select(.status == "skip"); .fix == null)' >/dev/null
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 11 ]
    [ ! -e "$DOCTOR_TEST_PROBES" ]
}

@test "doctor selection: excluded utility executables are not probed or queued for repair" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["lang.bun"]}}'
    local binary=""
    for binary in toon rust_proxy rano xf mdwb pt aadc s2p caut; do
        doctor_selection_binary "$binary"
    done
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_utilities

    [ "$FAIL_COUNT:$WARN_COUNT:$SKIP_COUNT" = 0:0:9 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    [ ! -e "$DOCTOR_TEST_PROBES" ]
    doctor_selection_json | jq -e 'length == 9 and all(.status == "skip" and .fix == null)' >/dev/null
}

@test "doctor selection: legacy optional utilities remain nonfatal skips without repair hints" {
    doctor_selection_fixture '{"skipped_tools":["utils.toon_rust","utils.rano"]}'
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_utilities

    [ "$FAIL_COUNT:$WARN_COUNT:$SKIP_COUNT" = 0:0:9 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    doctor_selection_json | jq -e 'length == 9 and all(.status == "skip" and .fix == null)' >/dev/null
}

@test "doctor selection: requested optional cloud tools fail while selected defaults warn" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["cloud.vercel","cloud.supabase"],"requested_modules":["cloud.vercel"]}}'
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_optional_command cloud.vercel Vercel vercel "repair vercel"
    check_optional_command cloud.supabase Supabase supabase "repair supabase"
    check_optional_command cloud.wrangler Wrangler wrangler "repair wrangler"

    [ "$FAIL_COUNT:$WARN_COUNT:$SKIP_COUNT" = 1:1:1 ]
    [ "${DOCTOR_FIX_PENDING_IDS[*]}" = 'cloud.vercel cloud.supabase' ]
    doctor_selection_json | jq -e '
        .[0].status == "fail" and .[0].fix == "repair vercel" and
        .[1].status == "warn" and .[1].fix == "repair supabase" and
        .[2].status == "skip" and .[2].fix == null' >/dev/null
}

@test "doctor selection: GIIL CSCTF and future utility manifest checks execute without blanket suppression" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["utils.giil","utils.csctf"],"requested_modules":["utils.giil"]}}'
    # Real generated catalog membership validates the saved selection above.
    # Controlled commands exercise the production bounded subprocess runner:
    # GIIL fails, CSCTF succeeds, and an excluded future module must not execute.
    MANIFEST_CHECKS=(
        $'utils.giil\tGIIL functional check\tprintf giil >> "$DOCTOR_TEST_PROBES"; false\toptional\tcurrent'
        $'utils.csctf\tCSCTF functional check\tprintf csctf >> "$DOCTOR_TEST_PROBES"; true\toptional\tcurrent'
        $'utils.future_tool\tExcluded utility\tprintf EXCLUDED >> "$DOCTOR_TEST_PROBES"; false\toptional\tcurrent'
    )
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_manifest_supplemental

    [ "$(cat "$DOCTOR_TEST_PROBES")" = giilcsctf ]
    [ "$FAIL_COUNT:$PASS_COUNT:$SKIP_COUNT" = 1:1:1 ]
    [ "${DOCTOR_FIX_PENDING_IDS[*]}" = utils.giil ]
    doctor_selection_json | jq -e '
        .[0].id == "utils.giil" and .[0].status == "fail" and (.[0].fix | contains("--only utils.giil")) and
        .[1].id == "utils.csctf" and .[1].status == "pass" and
        .[2].id == "utils.future_tool" and .[2].status == "skip" and .[2].fix == null' >/dev/null
}

# Keep the authored manifest probes intact while isolating their target home.
# A fixture identity avoids inspecting /root when the suite runs as root; the
# actual manifest runner still executes each verification in a subprocess.
doctor_manifest_home_fixture() {
    doctor_selection_fixture "$1"
    TARGET_USER=acfs_manifest_fixture
    ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
    # Import the generated resolver functions without leaking its shell options
    # or PATH. Only account lookup is replaced with the isolated fixture below.
    # shellcheck disable=SC1090
    source <(
        source "$PROJECT_ROOT/scripts/generated/doctor_checks.sh"
        declare -f acfs_generated_system_binary_path acfs_generated_resolve_current_user \
            acfs_generated_passwd_home_from_entry
    )
    _acfs_doctor_resolve_current_user() { printf '%s\n' "$TARGET_USER"; }
    _acfs_doctor_getent_passwd_entry() {
        printf '%s:x:%s:%s::%s:/bin/bash\n' "$TARGET_USER" "$UID" "$(id -g)" "$TARGET_HOME"
    }
    acfs_generated_getent_passwd_entry() {
        printf '%s:x:%s:%s::%s:/bin/bash\n' "$TARGET_USER" "$UID" "$(id -g)" "$TARGET_HOME"
    }
    doctor_load_module_selection
}

doctor_keep_generated_checks() {
    local entry="" requested="" id=""
    local -a selected=()
    for entry in "${MANIFEST_CHECKS[@]}"; do
        id="${entry%%$'\t'*}"
        for requested in "$@"; do
            [[ "$id" == "$requested" ]] || continue
            selected+=("$entry")
            break
        done
    done
    if [[ ${#selected[@]} -ne $# ]]; then
        fail "requested generated verification was not found"
        return 1
    fi
    MANIFEST_CHECKS=("${selected[@]}")
}

@test "doctor selection: working Cargo still verifies required nightly without automatic installation" {
    doctor_manifest_home_fixture '{"module_selection":{"schema_version":1,"selected_modules":["lang.rust"]}}'
    doctor_keep_generated_checks lang.rust.2
    mkdir -p "$TARGET_HOME/.cargo/bin"
    export DOCTOR_TEST_DOWNLOADS="$BATS_TEST_TMPDIR/unexpected-install"
    export RUSTUP_AUTO_INSTALL=1
    cat > "$DOCTOR_TEST_BIN/cargo" <<'EOF'
#!/bin/bash
if [[ "${RUSTUP_AUTO_INSTALL:-1}" != 0 ]]; then
    printf 'cargo\n' >> "$DOCTOR_TEST_DOWNLOADS"
    exit 3
fi
printf 'cargo\n' >> "$DOCTOR_TEST_PROBES"
printf 'cargo fixture 1.0\n'
EOF
    cat > "$TARGET_HOME/.cargo/bin/rustup" <<'EOF'
#!/bin/bash
[[ "$1" == show ]] || exit 2
if [[ "${RUSTUP_AUTO_INSTALL:-1}" != 0 ]]; then
    printf 'rustup\n' >> "$DOCTOR_TEST_DOWNLOADS"
    exit 3
fi
printf 'rustup\n' >> "$DOCTOR_TEST_PROBES"
cat "$HOME/toolchains"
EOF
    chmod +x "$DOCTOR_TEST_BIN/cargo" "$TARGET_HOME/.cargo/bin/rustup"
    printf 'stable-x86_64-unknown-linux-gnu (default)\n' > "$TARGET_HOME/toolchains"
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_command tool.cargo Cargo cargo "repair rust"
    check_manifest_supplemental

    [ ! -e "$DOCTOR_TEST_DOWNLOADS" ]
    [ "$RUSTUP_AUTO_INSTALL" = 1 ]
    [ "$PASS_COUNT:$FAIL_COUNT" = 1:1 ]
    [ "${DOCTOR_FIX_PENDING_IDS[*]}" = lang.rust.2 ]
    [ "$(cat "$DOCTOR_TEST_PROBES")" = $'cargo\nrustup' ]
    doctor_selection_json | jq -e '
        .[0].id == "tool.cargo" and .[0].status == "pass" and
        .[1].id == "lang.rust.2" and .[1].status == "fail" and
        (.[1].fix | contains("--only lang.rust"))' >/dev/null

    printf 'nightly-x86_64-unknown-linux-gnu (default)\n' > "$TARGET_HOME/toolchains"
    check_manifest_supplemental
    [ ! -e "$DOCTOR_TEST_DOWNLOADS" ]
    [ "$PASS_COUNT:$FAIL_COUNT" = 2:1 ]
    doctor_selection_json | jq -e '.[-1].id == "lang.rust.2" and .[-1].status == "pass"' >/dev/null
}

@test "doctor selection: workspace policy template is verified independently of the project directory" {
    doctor_manifest_home_fixture '{"module_selection":{"schema_version":1,"selected_modules":["base.filesystem"]}}'
    doctor_keep_generated_checks base.filesystem.2
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_manifest_supplemental

    [ "$FAIL_COUNT:$WARN_COUNT:$PASS_COUNT" = 1:0:0 ]
    [ "${DOCTOR_FIX_PENDING_IDS[*]}" = base.filesystem.2 ]
    doctor_selection_json | jq -e '
        .[0].id == "base.filesystem.2" and .[0].status == "fail" and
        (.[0].fix | contains("--only base.filesystem"))' >/dev/null

    mkdir -p "$TARGET_HOME/.acfs/docs"
    printf 'Workspace policy fixture\n' > "$TARGET_HOME/.acfs/docs/AGENTS.workspace.md"
    check_manifest_supplemental

    [ "$FAIL_COUNT:$PASS_COUNT" = 1:1 ]
    doctor_selection_json | jq -e '.[-1].id == "base.filesystem.2" and .[-1].status == "pass"' >/dev/null
}

@test "doctor selection: excluded Rust and workspace invariants do not execute or queue repairs" {
    doctor_manifest_home_fixture '{"module_selection":{"schema_version":1,"selected_modules":["lang.bun"]}}'
    doctor_keep_generated_checks base.filesystem.2 lang.rust.2
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true
    _doctor_run_manifest_check() {
        printf 'unexpected verification\n' >> "$DOCTOR_TEST_PROBES"
        return 1
    }

    check_manifest_supplemental

    [ ! -e "$DOCTOR_TEST_PROBES" ]
    [ "$FAIL_COUNT:$WARN_COUNT:$PASS_COUNT:$SKIP_COUNT" = 0:0:0:2 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    doctor_selection_json | jq -e 'length == 2 and all(.status == "skip" and .fix == null)' >/dev/null
}

@test "doctor selection: legacy failures in skipped_tools do not hide broken tools" {
    doctor_selection_fixture '{"skipped_tools":["lang.bun","agents.claude"]}'
    [ "$ACFS_STATE_SELECTION_MODE" = legacy ]
    check_command tool.bun Bun bun "install bun"
    check_command agent.claude Claude claude "install claude"
    [ "$FAIL_COUNT:$SKIP_COUNT" = 2:0 ]
}

@test "doctor selection: intended nightly installation overrides a stale skipped_tools marker" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["base.system","acfs.nightly"]},"skipped_tools":["acfs.nightly"]}'
    report_nightly_timer_status missing
    [ "$WARN_COUNT:$SKIP_COUNT" = 1:0 ]
    doctor_selection_json | jq -e '.[0].id == "acfs.nightly" and .[0].status == "warn" and .[0].fix != null' >/dev/null
}

@test "doctor selection: account workspace and shell requirements follow their owning modules" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["base.system","lang.bun"]}}'
    check identity.passwordless_sudo Sudo fail "requires password" "repair account"
    check workspace.data_projects Workspace fail "missing directory" "create workspace"
    check shell.login_shell Shell fail "bash login" "change login shell"
    check system.ubuntu_archive_suites Archives fail "mixed suites" "repair sources"
    [ "$FAIL_COUNT:$SKIP_COUNT" = 1:3 ]

    printf '%s\n' '{"module_selection":{"schema_version":1,"selected_modules":["users.ubuntu","base.filesystem","shell.login"]}}' > "$DOCTOR_TEST_STATE"
    doctor_load_module_selection
    check identity.passwordless_sudo Sudo fail "requires password" "repair account"
    check workspace.data_projects Workspace fail "missing directory" "create workspace"
    check shell.login_shell Shell fail "bash login" "change login shell"
    [ "$FAIL_COUNT:$SKIP_COUNT" = 4:3 ]
}

@test "doctor selection: selected stack aliases stay checked while excluded service and deep probes do not run" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["base.system","stack.ultimate_bug_scanner","stack.beads_viewer","stack.cass","stack.cm"]}}'
    doctor_selection_binary am
    doctor_selection_binary rch
    doctor_selection_binary claude
    doctor_selection_binary vercel

    check_stack
    deep_check_optional_probe deep.stack.rch RCH rch "repair rch" "rch doctor"
    check_claude_auth
    check_vercel_auth

    [ ! -e "$DOCTOR_TEST_PROBES" ]
    doctor_selection_json | jq -e '
        ([.[] | select(.status == "fail") | .id] | sort) ==
            ["stack.bv","stack.cass","stack.cm","stack.ubs"] and
        ([.[] | select(.id == "stack.mcp_agent_mail" or .id == "deep.stack.rch" or
                         .id == "deep.agent.claude_auth" or .id == "deep.cloud.vercel_auth") |
            .status] | all(. == "skip"))' >/dev/null
}

@test "doctor selection: supplemental probes run selected opt-in agents and omit excluded modules" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["base.system","agents.opencode","agents.omp","agents.grok","agents.gemini"]}}'
    # Use real subprocesses, not a replacement _doctor_run_manifest_check.
    # Failure must be observed; merely seeing an installed executable is not
    # enough for agents outside the three bespoke checks.
    MANIFEST_CHECKS=(
        $'agents.opencode\tOpenCode functional check\tprintf opencode >> "$DOCTOR_TEST_PROBES"; false\trequired\tcurrent'
        $'agents.omp\tOMP functional check\tprintf omp >> "$DOCTOR_TEST_PROBES"; false\trequired\tcurrent'
        $'agents.grok\tGrok functional check\tprintf grok >> "$DOCTOR_TEST_PROBES"; false\trequired\tcurrent'
        $'agents.gemini\tGemini functional check\tprintf gemini >> "$DOCTOR_TEST_PROBES"; false\trequired\tcurrent'
        $'tools.lazygit\tExcluded probe\tprintf EXCLUDED >> "$DOCTOR_TEST_PROBES"; false\trequired\tcurrent'
    )
    check_manifest_supplemental
    [ "$(cat "$DOCTOR_TEST_PROBES")" = opencodeompgrokgemini ]
    [ "$FAIL_COUNT:$SKIP_COUNT" = 4:1 ]
    doctor_selection_json | jq -e '.[4].id == "tools.lazygit" and .[4].status == "skip" and .[4].fix == null' >/dev/null
}

@test "doctor manifest probes: every execution context bounds a TERM-resistant child" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["agents.grok"]}}'
    # Leave time for shell/transport startup while keeping the deadline plus
    # its five-second kill grace below the finite seven-second stalled probe.
    DEEP_CHECK_TIMEOUT=1
    local context=""
    for context in current target_user root; do
        export DOCTOR_TEST_STARTED="$BATS_TEST_TMPDIR/started-$context"
        run _doctor_run_manifest_check "$context" \
            'printf started > "$DOCTOR_TEST_STARTED"; trap "" TERM; (trap "" TERM; sleep 7; printf escaped >> "$DOCTOR_TEST_PROBES") & wait'
        [[ "$status" -eq 124 || "$status" -eq 137 ]] \
            || fail "$context did not enforce the probe deadline (status $status): $output"
        [[ -s "$DOCTOR_TEST_STARTED" ]] || fail "$context never reached the probe"
        [[ ! -e "$DOCTOR_TEST_PROBES" ]] || fail "$context left a probe running past its deadline"
    done
}

@test "doctor manifest probes: a timed-out selected tool does not block later checks or authorize repair" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["agents.opencode","agents.grok"]}}'
    DEEP_CHECK_TIMEOUT=1
    export DOCTOR_TEST_STARTED="$BATS_TEST_TMPDIR/started-grok"
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true
    MANIFEST_CHECKS=(
        $'agents.grok\tGrok functional check\tprintf started > "$DOCTOR_TEST_STARTED"; trap "" TERM; sleep 7\toptional\tcurrent'
        $'agents.opencode\tOpenCode functional check\tprintf opencode >> "$DOCTOR_TEST_PROBES"\trequired\tcurrent'
        $'tools.lazygit\tExcluded probe\tprintf EXCLUDED >> "$DOCTOR_TEST_PROBES"; sleep 7\trequired\tcurrent'
    )

    check_manifest_supplemental
    [ -s "$DOCTOR_TEST_STARTED" ]
    [ "$(cat "$DOCTOR_TEST_PROBES")" = opencode ]
    [ "$PASS_COUNT:$WARN_COUNT:$FAIL_COUNT:$SKIP_COUNT" = 1:1:0:1 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    [[ " ${DOCTOR_FIX_OBSERVED_IDS[*]} " == *" agents.grok "* ]]
    doctor_selection_json | jq -e '
        .[0].id == "agents.grok" and .[0].status == "timeout" and
        (.[0].details | contains("deadline")) and
        .[1].id == "agents.opencode" and .[1].status == "pass" and
        .[2].id == "tools.lazygit" and .[2].status == "skip" and .[2].fix == null' >/dev/null
}

@test "doctor manifest probes: missing timeout support refuses the command instead of running unbounded" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["agents.grok"]}}'
    _acfs_doctor_system_binary_path() {
        [[ "$1" != timeout ]] || return 1
        [[ -x "/usr/bin/$1" ]] || return 1
        printf '/usr/bin/%s\n' "$1"
    }

    run -127 _doctor_run_manifest_check current 'printf UNBOUNDED >> "$DOCTOR_TEST_PROBES"'
    [ "$status" -eq 127 ]
    [ ! -e "$DOCTOR_TEST_PROBES" ]
}

@test "doctor manifest probes: stalled sudo admission is bounded without falling back to a different identity" {
    [[ "$EUID" -ne 0 ]] || skip "sudo admission is only used by non-root doctor"
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["agents.grok"]}}'
    DEEP_CHECK_TIMEOUT=1
    export DOCTOR_TEST_STARTED="$BATS_TEST_TMPDIR/started-sudo"
    cat > "$DOCTOR_TEST_BIN/sudo" <<'EOF'
#!/bin/bash
printf started > "$DOCTOR_TEST_STARTED"
trap '' TERM
sleep 7
exit 1
EOF
    chmod +x "$DOCTOR_TEST_BIN/sudo"
    local doctor_test_deadline_bin
    doctor_test_deadline_bin="$(_acfs_doctor_system_binary_path timeout)"
    _acfs_doctor_system_binary_path() {
        if [[ "$1" == timeout ]]; then
            printf '%s\n' "$doctor_test_deadline_bin"
        elif [[ "$1" == sudo ]]; then
            printf '%s/sudo\n' "$DOCTOR_TEST_BIN"
        elif [[ -x "/usr/bin/$1" ]]; then
            printf '/usr/bin/%s\n' "$1"
        else
            return 1
        fi
    }

    run _doctor_run_manifest_check root 'printf FALLBACK >> "$DOCTOR_TEST_PROBES"'
    [[ "$status" -eq 124 || "$status" -eq 137 ]] || fail "sudo admission was not bounded: $status"
    [ -s "$DOCTOR_TEST_STARTED" ]
    [ ! -e "$DOCTOR_TEST_PROBES" ]

    # An ordinary explicit denial still supports read-only checks in safe mode.
    printf '#!/bin/bash\nexit 1\n' > "$DOCTOR_TEST_BIN/sudo"
    DEEP_CHECK_TIMEOUT=15
    run _doctor_run_manifest_check root 'printf safe-mode >> "$DOCTOR_TEST_PROBES"'
    [ "$status" -eq 0 ]
    [ "$(cat "$DOCTOR_TEST_PROBES")" = safe-mode ]
}

@test "doctor selection: excluded timed-out checks cannot become warnings or autofixes" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["base.system"]}}'
    FIX_MODE=true
    dispatch_fix() { printf 'unexpected repair\n' >> "$DOCTOR_TEST_PROBES"; }
    check_with_timeout_status deep.cloud.vercel_auth Vercel timeout "hung" "install vercel"
    check agent.codex Codex fail "missing" "install codex"
    [ "$WARN_COUNT:$FAIL_COUNT:$SKIP_COUNT" = 0:0:2 ]
    [ ! -e "$DOCTOR_TEST_PROBES" ]
    doctor_selection_json | jq -e 'all(.status == "skip" and .fix == null)' >/dev/null
}

doctor_auth_probe_fixture() {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["agents.claude","agents.codex","agents.antigravity","agents.gemini","lang.bun"]}}'
    mkdir -p "$TARGET_HOME/.claude" "$TARGET_HOME/.codex" "$TARGET_HOME/.gemini/antigravity-cli"
    printf '%s\n' '{"claudeAiOauth":{"accessToken":"fixture-claude-oauth"}}' > "$TARGET_HOME/.claude/.credentials.json"
    printf '%s\n' '{"tokens":{"access_token":"fixture-codex-oauth"}}' > "$TARGET_HOME/.codex/auth.json"
    printf '%s\n' fixture-antigravity-oauth > "$TARGET_HOME/.gemini/antigravity-cli/antigravity-oauth-token"
    printf '%s\n' '{"access_token":"fixture-gemini-oauth"}' > "$TARGET_HOME/.gemini/oauth_creds.json"
    CODEX_HOME="$TARGET_HOME/.codex"
    ANTIGRAVITY_HOME="$TARGET_HOME/.gemini/antigravity-cli"
    GEMINI_CLI_HOME="$TARGET_HOME"
    # Keep legacy Gemini's alternate providers outside this local OAuth fixture.
    get_configured_secret() { return 1; }
    configured_truthy_value() { return 1; }
}

@test "doctor auth probes: selected stalled agents cannot pass from cached credentials or block later checks" {
    doctor_auth_probe_fixture
    DEEP_CHECK_TIMEOUT=1
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true
    export DOCTOR_TEST_STARTED="$BATS_TEST_TMPDIR/auth-started"
    export DOCTOR_TEST_CHILD_PIDS="$BATS_TEST_TMPDIR/auth-child-pids"
    local binary=""
    for binary in claude codex agy gemini; do
        cat > "$DOCTOR_TEST_BIN/$binary" <<'EOF'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >> "$DOCTOR_TEST_STARTED"
trap '' TERM
sleep 7 &
printf '%s\n' "$!" >> "$DOCTOR_TEST_CHILD_PIDS"
wait
printf escaped >> "$DOCTOR_TEST_PROBES"
EOF
        chmod +x "$DOCTOR_TEST_BIN/$binary"
    done

    check_claude_auth
    check_codex_auth
    check_antigravity_auth
    check_gemini_auth
    [ ! -e "$DOCTOR_TEST_PROBES" ]
    [[ "$(wc -l < "$DOCTOR_TEST_STARTED")" -eq 4 ]] \
        || fail "not all agents reached their probe: $(cat "$DOCTOR_TEST_STARTED"); $(doctor_selection_json)"
    local child_pid="" child_state=""
    while IFS= read -r child_pid; do
        child_state="$(ps -o stat= -p "$child_pid" 2>/dev/null || true)"
        [[ -z "$child_state" || "$child_state" == Z* ]] \
            || fail "agent probe left child $child_pid running ($child_state)"
    done < "$DOCTOR_TEST_CHILD_PIDS"
    if grep -q -- --help "$DOCTOR_TEST_STARTED"; then
        fail "timed-out Antigravity version check triggered a fallback"
    fi
    [ "$PASS_COUNT:$WARN_COUNT:$FAIL_COUNT:$SKIP_COUNT" = 0:4:0:0 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    doctor_selection_json | jq -e '
        length == 4 and all(.status == "timeout" and (.details | contains("deadline")))
    ' >/dev/null

    doctor_selection_binary bun
    check_command tool.bun Bun bun "install bun"
    [ "$PASS_COUNT" -eq 1 ]
    [ "$(cat "$DOCTOR_TEST_PROBES")" = bun ]
}

@test "doctor auth probes: ordinary version success and Antigravity help fallback preserve authentication" {
    doctor_auth_probe_fixture
    doctor_selection_binary claude
    doctor_selection_binary codex
    doctor_selection_binary gemini
    cat > "$DOCTOR_TEST_BIN/agy" <<'EOF'
#!/bin/bash
printf 'agy %s\n' "$*" >> "$DOCTOR_TEST_PROBES"
[[ "$1" == --help ]]
EOF
    chmod +x "$DOCTOR_TEST_BIN/agy"

    check_claude_auth
    check_codex_auth
    check_antigravity_auth
    check_gemini_auth

    [ "$PASS_COUNT:$WARN_COUNT:$FAIL_COUNT:$SKIP_COUNT" = 4:0:0:0 ]
    doctor_selection_json | jq -e 'length == 4 and all(.status == "pass")' >/dev/null
    [ "$(cat "$DOCTOR_TEST_PROBES")" = $'claude\ncodex\nagy --version\nagy --help\ngemini' ]
}

@test "doctor auth probes: missing timeout support refuses execution despite saved credentials" {
    doctor_auth_probe_fixture
    local binary=""
    for binary in claude codex agy gemini; do doctor_selection_binary "$binary"; done
    _acfs_doctor_system_binary_path() {
        [[ "$1" != timeout ]] || return 1
        [[ -x "/usr/bin/$1" ]] || return 1
        printf '/usr/bin/%s\n' "$1"
    }

    check_claude_auth
    check_codex_auth
    check_antigravity_auth
    check_gemini_auth

    [ ! -e "$DOCTOR_TEST_PROBES" ]
    [ "$PASS_COUNT:$WARN_COUNT:$FAIL_COUNT:$SKIP_COUNT" = 0:0:4:0 ]
    doctor_selection_json | jq -e 'length == 4 and all(.status == "fail")' >/dev/null
}

@test "doctor auth probes: Antigravity help fallback shares the version probe deadline" {
    doctor_auth_probe_fixture
    DEEP_CHECK_TIMEOUT=1
    cat > "$DOCTOR_TEST_BIN/agy" <<'EOF'
#!/bin/bash
printf 'agy %s\n' "$*" >> "$DOCTOR_TEST_PROBES"
sleep 0.7
[[ "$1" == --help ]]
EOF
    chmod +x "$DOCTOR_TEST_BIN/agy"

    check_antigravity_auth

    [ "$(cat "$DOCTOR_TEST_PROBES")" = $'agy --version\nagy --help' ]
    [ "$PASS_COUNT:$WARN_COUNT:$FAIL_COUNT" = 0:1:0 ]
    doctor_selection_json | jq -e 'length == 1 and .[0].status == "timeout"' >/dev/null
}

@test "doctor auth probes: nonzero binaries remain failures despite saved credentials" {
    doctor_auth_probe_fixture
    local binary=""
    for binary in claude codex agy gemini; do
        printf '#!/bin/bash\nexit 2\n' > "$DOCTOR_TEST_BIN/$binary"
        chmod +x "$DOCTOR_TEST_BIN/$binary"
    done

    check_claude_auth
    check_codex_auth
    check_antigravity_auth
    check_gemini_auth

    [ "$PASS_COUNT:$WARN_COUNT:$FAIL_COUNT" = 0:0:4 ]
    doctor_selection_json | jq -e 'length == 4 and all(.status == "fail" and .details == "binary error")' >/dev/null
}

@test "doctor auth probes: omitted agents never execute their responsiveness commands" {
    doctor_auth_probe_fixture
    printf '%s\n' '{"module_selection":{"schema_version":1,"selected_modules":["lang.bun"]}}' > "$DOCTOR_TEST_STATE"
    doctor_load_module_selection
    local binary=""
    for binary in claude codex agy gemini; do doctor_selection_binary "$binary"; done

    check_claude_auth
    check_codex_auth
    check_antigravity_auth
    check_gemini_auth

    [ ! -e "$DOCTOR_TEST_PROBES" ]
    [ "$PASS_COUNT:$WARN_COUNT:$FAIL_COUNT:$SKIP_COUNT" = 0:0:0:4 ]
    doctor_selection_json | jq -e 'length == 4 and all(.status == "skip" and .fix == null)' >/dev/null
}

@test "doctor auth probes: stalled Gemini ADC cannot fall through to saved OAuth or leave a child running" {
    doctor_auth_probe_fixture
    doctor_selection_binary gemini
    configured_truthy_value() { [[ "$1" == GOOGLE_GENAI_USE_VERTEXAI ]]; }
    get_configured_value() {
        case "$1" in
            GOOGLE_CLOUD_PROJECT) printf fixture-project ;;
            GOOGLE_CLOUD_LOCATION) printf fixture-region ;;
            *) return 1 ;;
        esac
    }
    export DOCTOR_TEST_STARTED="$BATS_TEST_TMPDIR/adc-started"
    export DOCTOR_TEST_ESCAPED="$BATS_TEST_TMPDIR/adc-escaped"
    export DOCTOR_TEST_CHILD_PIDS="$BATS_TEST_TMPDIR/adc-child-pids"
    cat > "$DOCTOR_TEST_BIN/gcloud" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" > "$DOCTOR_TEST_STARTED"
trap '' TERM
sleep 11 &
printf '%s\n' "$!" > "$DOCTOR_TEST_CHILD_PIDS"
wait
printf escaped > "$DOCTOR_TEST_ESCAPED"
EOF
    chmod +x "$DOCTOR_TEST_BIN/gcloud"
    FIX_MODE=true
    DOCTOR_FIX_SCOPED=true

    check_gemini_auth

    [ "$(cat "$DOCTOR_TEST_STARTED")" = 'auth application-default print-access-token' ]
    [ ! -e "$DOCTOR_TEST_ESCAPED" ]
    local child_state=""
    child_state="$(ps -o stat= -p "$(cat "$DOCTOR_TEST_CHILD_PIDS")" 2>/dev/null || true)"
    [[ -z "$child_state" || "$child_state" == Z* ]] || fail "ADC probe left its child running ($child_state)"
    [ "$PASS_COUNT:$WARN_COUNT:$FAIL_COUNT" = 0:1:0 ]
    [ "${#DOCTOR_FIX_PENDING_IDS[@]}" -eq 0 ]
    doctor_selection_json | jq -e 'length == 1 and .[0].status == "timeout" and
        (.[0].details | contains("Vertex AI"))' >/dev/null
}

@test "doctor selection: malformed saved scope stops main before diagnostics and repair initialization" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["base.system"]}}'
    printf '%s\n' '{"module_selection":{"schema_version":1,"selected_modules":[]}}' > "$DOCTOR_TEST_STATE"
    run_doctor_fix() { printf 'unexpected fix init\n' >> "$DOCTOR_TEST_PROBES"; }
    check_identity() { printf 'unexpected diagnostic\n' >> "$DOCTOR_TEST_PROBES"; }

    invalid_scope_doctor() { main --json --fix 2> "$BATS_TEST_TMPDIR/selection-error"; }
    run invalid_scope_doctor
    [ "$status" -eq 1 ]
    [ ! -e "$DOCTOR_TEST_PROBES" ]
    [ -s "$BATS_TEST_TMPDIR/selection-error" ]
    # The state parser writes its diagnostic to stderr; stdout remains one
    # complete report even when the invocation requested automatic repair.
    printf '%s\n' "$output" | jq -e '
        .summary.fail == 1 and (.checks | length) == 1 and
        .checks[0].id == "config.module_selection" and
        .checks[0].status == "fail" and .checks[0].fix == null' >/dev/null
}

@test "doctor selection: unknown saved module IDs cannot hide all checks" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["base.system"]}}'
    printf '%s\n' '{"module_selection":{"schema_version":1,"selected_modules":["stack.no_such_module"]}}' > "$DOCTOR_TEST_STATE"
    check_identity() { printf 'unexpected diagnostic\n' >> "$DOCTOR_TEST_PROBES"; }
    unknown_scope_doctor() { main --json 2> "$BATS_TEST_TMPDIR/selection-error"; }

    run unknown_scope_doctor
    [ "$status" -eq 1 ]
    [ ! -e "$DOCTOR_TEST_PROBES" ]
    printf '%s\n' "$output" | jq -e '
        .summary.fail == 1 and .checks[0].id == "config.module_selection" and
        (.checks[0].details | contains("absent from the deployed manifest"))' >/dev/null
}

@test "doctor selection: a missing generated catalog cannot authorize repairs" {
    doctor_selection_fixture '{"module_selection":{"schema_version":1,"selected_modules":["base.system"]}}'
    MANIFEST_CHECKS=()
    MANIFEST_CHECKS_LOADED=false
    run_doctor_fix() { printf 'unexpected fix init\n' >> "$DOCTOR_TEST_PROBES"; }
    missing_catalog_doctor() { main --json --fix 2> "$BATS_TEST_TMPDIR/selection-error"; }

    run missing_catalog_doctor
    [ "$status" -eq 1 ]
    [ ! -e "$DOCTOR_TEST_PROBES" ]
    printf '%s\n' "$output" | jq -e '
        .summary.fail == 1 and .checks[0].id == "config.module_selection" and
        (.checks[0].details | contains("deployed manifest"))' >/dev/null
}
