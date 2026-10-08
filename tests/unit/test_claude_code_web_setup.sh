#!/usr/bin/env bash
# Unit tests for scripts/claude-code-web-setup.sh (ACFS for Claude Code on the web).
#
# Drives the real script end to end with no network access: a fake curl
# serves fixture installers and a fixture checksums.yaml from a sandbox, and
# fake claude/git/go binaries record how the script called them.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/scripts/claude-code-web-setup.sh"
LEDGER_URL="https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/checksums.yaml"
PROBE_URL="https://github.com/Dicklesworthstone/beads_rust/releases/latest"
JSM_URL="https://jeffreys-skills.md/install.sh"

TESTS_PASSED=0
TESTS_FAILED=0
LAST_OUTPUT=""
LAST_STATUS=0
SANDBOX=""

url_key() {
    local key="${1#https://}"
    key="${key%%\?*}"
    printf '%s\n' "${key//\//__}"
}

# serve URL [HTTP_CODE] < content
serve() {
    local key
    key="$(url_key "$1")"
    cat > "$SANDBOX/served/$key"
    if [[ -n "${2:-}" ]]; then
        printf '%s' "$2" > "$SANDBOX/served/$key.code"
    fi
}

new_sandbox() {
    [[ -n "$SANDBOX" ]] && rm -rf "$SANDBOX"
    SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/acfs-cloud-test.XXXXXX")"
    mkdir -p "$SANDBOX/home" "$SANDBOX/bin" "$SANDBOX/served" "$SANDBOX/tmp"

    # Fake curl: understands the flags the setup script passes and maps each
    # URL to a file under served/ (missing file = HTTP failure, exit 22).
    cat > "$SANDBOX/bin/curl" <<EOF
#!/usr/bin/env bash
out="" fmt="" url=""
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -o) out="\$2"; shift 2 ;;
        -w) fmt="\$2"; shift 2 ;;
        --proto | --retry | --retry-delay | --connect-timeout | --max-time) shift 2 ;;
        -*) shift ;;
        *) url="\$1"; shift ;;
    esac
done
printf '%s\n' "\$url" >> "$SANDBOX/curl.log"
key="\${url#https://}"
key="\${key%%\?*}"
key="\${key//\//__}"
src="$SANDBOX/served/\$key"
if [[ ! -f "\$src" ]]; then
    [[ -n "\$fmt" ]] && printf '000'
    exit 22
fi
if [[ -n "\$out" ]]; then cp "\$src" "\$out"; else cat "\$src"; fi
if [[ -n "\$fmt" ]]; then
    if [[ -f "\$src.code" ]]; then cat "\$src.code"; else printf '200'; fi
fi
exit 0
EOF
    chmod +x "$SANDBOX/bin/curl"

    # GitHub release downloads work unless a test says otherwise.
    printf 'redirect' | serve "$PROBE_URL" 302
}

add_fake_claude() {
    cat > "$SANDBOX/bin/claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$SANDBOX/claude.log"
exit 0
EOF
    chmod +x "$SANDBOX/bin/claude"
}

# Prints a fake upstream installer that records its args and environment
# and drops the given binaries into ~/.local/bin.
fake_installer() {
    local name="$1" binary
    shift
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" > "$HOME/.args-%s"\n' "$name"
    printf 'env > "$HOME/.env-%s"\n' "$name"
    printf 'mkdir -p "$HOME/.local/bin"\n'
    for binary in "$@"; do
        printf 'printf "#!/usr/bin/env bash\\necho %s 1.2.3\\n" > "$HOME/.local/bin/%s"\n' "$binary" "$binary"
        printf 'chmod +x "$HOME/.local/bin/%s"\n' "$binary"
    done
}

# serve_installer KEY < installer: serves it at the URL the ledger will name.
serve_installer() {
    serve "https://fixtures.invalid/$1.sh"
}

# write_ledger KEY...: a checksums.yaml covering the served fixture installers.
write_ledger() {
    local key sha
    {
        printf '# checksums.yaml - test fixture\n\ninstallers:\n'
        for key in "$@"; do
            sha="$(sha256sum "$SANDBOX/served/fixtures.invalid__$key.sh" | awk '{ print $1 }')"
            printf '  %s:\n    url: "https://fixtures.invalid/%s.sh"\n    sha256: "%s"\n\n' "$key" "$key" "$sha"
        done
    } | serve "$LEDGER_URL"
}

# run_setup [VAR=value...]
run_setup() {
    set +e
    LAST_OUTPUT="$(
        env -i HOME="$SANDBOX/home" PATH="$SANDBOX/bin:/usr/bin:/bin" TMPDIR="$SANDBOX/tmp" "$@" \
            bash "$SETUP_SCRIPT" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
    )"
    LAST_STATUS=${PIPESTATUS[0]}
    set -u
}

expect_output() {
    [[ "$LAST_OUTPUT" == *"$1"* ]] && return 0
    printf 'expected output to contain: %s\nOutput:\n%s\n' "$1" "$LAST_OUTPUT"
    return 1
}

expect_file_contains() {
    grep -qF -- "$2" "$1" 2>/dev/null && return 0
    printf 'expected %s to contain: %s\n' "$1" "$2"
    [[ -f "$1" ]] && cat "$1"
    return 1
}

run_test() {
    local name="$1"
    shift
    printf '[TEST] %s\n' "$name"
    new_sandbox
    if "$@"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '[PASS] %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '[FAIL] %s\n' "$name"
    fi
}

test_installs_verified_tools_and_writes_guide() {
    fake_installer br br | serve_installer br
    fake_installer ubs ubs | serve_installer ubs
    fake_installer am am mcp-agent-mail | serve_installer mcp_agent_mail
    write_ledger br ubs mcp_agent_mail
    add_fake_claude

    run_setup ACFS_CLOUD_TOOLS="br ubs am"
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    [[ -x "$SANDBOX/home/.local/bin/br" && -x "$SANDBOX/home/.local/bin/ubs" ]] || return 1
    expect_output "br    br 1.2.3" || return 1
    expect_output "am    am 1.2.3" || return 1
    expect_file_contains "$SANDBOX/home/.args-br" "--skip-skills" || return 1
    expect_file_contains "$SANDBOX/home/.args-ubs" "--easy-mode --skip-hooks" || return 1
    expect_file_contains "$SANDBOX/home/.args-am" "--yes --no-service" || return 1
    expect_file_contains "$SANDBOX/home/.env-am" "AM_INSTALL_SKIP_MCP_SETUP=1" || return 1
    expect_file_contains "$SANDBOX/claude.log" \
        "mcp add --scope user mcp-agent-mail -- $SANDBOX/home/.local/bin/mcp-agent-mail" || return 1
    expect_file_contains "$SANDBOX/home/.claude/CLAUDE.md" "BEGIN ACFS CLOUD TOOLS" || return 1
    expect_file_contains "$SANDBOX/home/.claude/CLAUDE.md" '`br` (beads_rust)' || return 1
    expect_file_contains "$SANDBOX/home/.acfs/cloud/setup.log" "Summary" || return 1
}

test_refuses_installer_with_checksum_mismatch() {
    fake_installer br br | serve_installer br
    write_ledger br
    # Upstream changes the installer after the ledger was generated.
    { fake_installer br br; printf 'touch "$HOME/.tampered-installer-ran"\n'; } | serve_installer br

    run_setup ACFS_CLOUD_TOOLS="br"
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    expect_output "installer checksum mismatch" || return 1
    [[ ! -e "$SANDBOX/home/.tampered-installer-ran" ]] || return 1
    [[ ! -e "$SANDBOX/home/.local/bin/br" ]] || return 1
    expect_file_contains "$SANDBOX/home/.claude/CLAUDE.md" '- `br`: installer checksum mismatch'
}

test_exits_zero_when_everything_is_unreachable() {
    rm -f "$SANDBOX/served/"*

    run_setup ACFS_CLOUD_TOOLS="br am jsm"
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    expect_output "Could not fetch checksums.yaml" || return 1
    expect_output "refusing to run an unverified installer" || return 1
    expect_output "could not download https://jeffreys-skills.md/install.sh" || return 1
    expect_file_contains "$SANDBOX/home/.claude/CLAUDE.md" "Not installed at setup time"
}

test_skips_release_installers_when_github_is_scoped() {
    fake_installer br br | serve_installer br
    write_ledger br
    fake_installer jsm jsm | serve "$JSM_URL"
    printf '{"message":"GitHub access to this repository is not enabled for this session."}' |
        serve "$PROBE_URL" 403

    run_setup ACFS_CLOUD_TOOLS="br jsm"
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    expect_output "blocked by the session's GitHub proxy" || return 1
    expect_output "jsm   jsm 1.2.3" || return 1
    ! grep -q "fixtures.invalid/br.sh" "$SANDBOX/curl.log" || return 1
    [[ ! -e "$SANDBOX/home/.local/bin/br" ]]
}

test_guide_block_is_replaced_not_duplicated() {
    mkdir -p "$SANDBOX/home/.claude"
    printf 'Keep this preference.\n' > "$SANDBOX/home/.claude/CLAUDE.md"
    fake_installer br br | serve_installer br
    write_ledger br

    run_setup ACFS_CLOUD_TOOLS="br"
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    run_setup ACFS_CLOUD_TOOLS="br"
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    expect_output "(already installed)" || return 1

    local guide="$SANDBOX/home/.claude/CLAUDE.md"
    [[ "$(head -n 1 "$guide")" == "Keep this preference." ]] || return 1
    [[ "$(grep -c "BEGIN ACFS CLOUD TOOLS" "$guide")" -eq 1 ]] || return 1
    [[ "$(sed -n 2p "$guide")" == "" && "$(sed -n 3p "$guide")" == "<!-- BEGIN"* ]] || {
        cat -A "$guide"
        return 1
    }
}

test_times_out_a_hung_installer() {
    printf '#!/usr/bin/env bash\nsleep 60\n' | serve_installer br
    write_ledger br
    local started elapsed
    started=$(date +%s)

    run_setup ACFS_CLOUD_TOOLS="br" ACFS_CLOUD_TIMEOUT=2
    elapsed=$(( $(date +%s) - started ))
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    expect_output "installer timed out after 2s" || return 1
    [[ "$elapsed" -lt 30 ]] || { printf 'setup took %ss\n' "$elapsed"; return 1; }
}

test_builds_bv_from_source_when_release_install_fails() {
    printf '#!/usr/bin/env bash\necho "no prebuilt binary" >&2\nexit 1\n' | serve_installer bv
    write_ledger bv
    cat > "$SANDBOX/bin/git" <<'EOF'
#!/usr/bin/env bash
mkdir -p "${@: -1}/cmd/bv"
EOF
    cat > "$SANDBOX/bin/go" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then
        printf '#!/usr/bin/env bash\necho "bv v9.9.9"\n' > "$2"
        chmod +x "$2"
        exit 0
    fi
    shift
done
exit 1
EOF
    chmod +x "$SANDBOX/bin/git" "$SANDBOX/bin/go"

    run_setup ACFS_CLOUD_TOOLS="bv"
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    expect_output "bv    bv v9.9.9 (built from source)" || return 1
    expect_file_contains "$SANDBOX/home/.claude/CLAUDE.md" '`bv` (beads_viewer)'
}

test_unknown_tool_is_reported_not_fatal() {
    run_setup ACFS_CLOUD_TOOLS="nope"
    [[ "$LAST_STATUS" -eq 0 ]] || return 1
    expect_output "Unknown tool 'nope'"
}

if [[ ! -f "$SETUP_SCRIPT" ]]; then
    printf '[FAIL] missing %s\n' "$SETUP_SCRIPT"
    exit 1
fi

run_test "installs ledger-verified tools and writes the Claude guide" test_installs_verified_tools_and_writes_guide
run_test "refuses an installer whose checksum does not match the ledger" test_refuses_installer_with_checksum_mismatch
run_test "exits 0 when every download fails" test_exits_zero_when_everything_is_unreachable
run_test "skips release installers when the GitHub proxy scopes github.com" test_skips_release_installers_when_github_is_scoped
run_test "replaces the CLAUDE.md block instead of duplicating it" test_guide_block_is_replaced_not_duplicated
run_test "times out a hung installer" test_times_out_a_hung_installer
run_test "builds bv from source when the release install fails" test_builds_bv_from_source_when_release_install_fails
run_test "reports an unknown tool without failing" test_unknown_tool_is_reported_not_fatal

[[ -n "$SANDBOX" ]] && rm -rf "$SANDBOX"
printf '\nPassed: %d\nFailed: %d\n' "$TESTS_PASSED" "$TESTS_FAILED"
if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
