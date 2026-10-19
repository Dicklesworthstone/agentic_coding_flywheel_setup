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
    # Record results instead of rendering them.
    check() { printf '%s|%s|%s|%s\n' "$1" "$3" "$4" "${5:-}"; }
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
