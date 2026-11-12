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
    DOCTOR_TEST_STATE="$BATS_TEST_TMPDIR/selected-state.json"
    DOCTOR_TEST_BIN="$BATS_TEST_TMPDIR/selected-bin"
    DOCTOR_TEST_PROBES="$BATS_TEST_TMPDIR/probes"
    mkdir -p "$DOCTOR_TEST_BIN"
    printf '%s\n' "$1" > "$DOCTOR_TEST_STATE"
    export DOCTOR_TEST_PROBES
    _acfs_doctor_find_project_path() {
        if [[ "$1" == state.json ]]; then
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
