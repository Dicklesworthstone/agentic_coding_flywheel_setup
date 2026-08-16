#!/usr/bin/env bash
# ============================================================
# Sandbox Harness: Agent Mail mask handling (issues #327/#328)
#
# Exercises _stack_configure_agent_mail_service against a fake
# systemctl that faithfully reproduces the systemd behaviour from
# issue #328:
#   - a runtime mask can exist as /dev/null symlinks in BOTH
#     $XDG_RUNTIME_DIR/systemd/user/ and .../user.control/
#   - `systemctl --user unmask --runtime` removes ONLY the user/
#     symlink; the user.control/ one (the FragmentPath) survives
#   - a masked unit refuses enable/start and reports LoadState=masked
#
# Contract under test:
#   - PERSISTENT mask (unit path symlink -> /dev/null): deliberate
#     opt-out, rc 75, nothing touched (issue #327)
#   - RUNTIME mask (user/, user.control/, or both): cleared fully
#     (both locations + daemon-reload + reset-failed), service
#     enabled and active, rc 0 (issue #328)
#   - unclearable runtime mask: rc 1 (loud), NOT rc 75, with exact
#     remediation commands on stderr; never a half-unmask
#   - post-update assertion: LoadState must be 'loaded' and the unit
#     active, else rc 1 with a loud message
#
# No real systemd, no real network, no real agent-mail.service is
# touched: everything runs inside a mktemp sandbox with stubbed
# systemctl/ss/lsof and ACFS_AM_RUNTIME_DIR pointing into the sandbox.
# ============================================================

set -uo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "This harness needs bash >= 4 (stack.sh uses declare -gA); found $BASH_VERSION" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/scripts/lib"
# Directory of the interpreter running this harness: put it first on PATH in
# the sandbox so nested `bash` invocations also resolve to a modern bash
# (macOS /bin/bash is 3.2 and cannot source stack.sh).
BASH_BIN_DIR="$(cd "$(dirname "$BASH")" && pwd)"

passed=0
failed=0
current_test=""

say_pass() {
    echo "  [PASS] $1"
    passed=$((passed + 1))
}

say_fail() {
    echo "  [FAIL] $1"
    failed=$((failed + 1))
}

check() {
    local label="$1"
    shift
    if "$@"; then
        say_pass "$label"
    else
        say_fail "$label"
    fi
}

check_not() {
    local label="$1"
    shift
    if "$@"; then
        say_fail "$label"
    else
        say_pass "$label"
    fi
}

# ------------------------------------------------------------
# Sandbox construction
# ------------------------------------------------------------

SANDBOX=""
FAKE_HOME=""
FAKE_RTD=""
FAKE_STATE_DIR=""
UNIT_FILE=""
RT_USER_MASK=""
RT_CONTROL_MASK=""

make_sandbox() {
    SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/acfs-am-mask.XXXXXX")"
    FAKE_HOME="$SANDBOX/home"
    FAKE_RTD="$SANDBOX/run"
    FAKE_STATE_DIR="$SANDBOX/state"
    UNIT_FILE="$FAKE_HOME/.config/systemd/user/agent-mail.service"
    RT_USER_MASK="$FAKE_RTD/systemd/user/agent-mail.service"
    RT_CONTROL_MASK="$FAKE_RTD/systemd/user.control/agent-mail.service"

    mkdir -p \
        "$FAKE_HOME/.local/bin" \
        "$FAKE_HOME/.config/systemd/user" \
        "$FAKE_HOME/mcp_agent_mail" \
        "$FAKE_RTD/systemd/user" \
        "$FAKE_RTD/systemd/user.control" \
        "$FAKE_STATE_DIR"

    # Fake am CLI: identifies as the Rust binary.
    cat > "$FAKE_HOME/mcp_agent_mail/am" <<'AM_EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    echo "am 0.0.0-test"
fi
exit 0
AM_EOF
    chmod +x "$FAKE_HOME/mcp_agent_mail/am"

    # Neutralize port-holder discovery so the harness can never see (let alone
    # signal) a real Agent Mail process on the host machine.
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_HOME/.local/bin/ss"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_HOME/.local/bin/lsof"
    chmod +x "$FAKE_HOME/.local/bin/ss" "$FAKE_HOME/.local/bin/lsof"

    # Fake systemctl mimicking the issue #328 semantics.
    cat > "$FAKE_HOME/.local/bin/systemctl" <<'SC_EOF'
#!/usr/bin/env bash
set -u
state="$FAKE_STATE_DIR"
rtd="$FAKE_RTD"
home_unit="$HOME/.config/systemd/user/agent-mail.service"

args=()
for a in "$@"; do
    [[ "$a" == "--user" ]] && continue
    args+=("$a")
done
cmd="${args[0]:-}"
echo "$*" >> "$state/calls.log"

is_devnull() { [[ -L "$1" && "$(readlink "$1" 2>/dev/null)" == "/dev/null" ]]; }

mask_state() {
    if is_devnull "$home_unit"; then
        echo persistent
    elif is_devnull "$rtd/systemd/user/agent-mail.service" || \
         is_devnull "$rtd/systemd/user.control/agent-mail.service"; then
        echo runtime
    else
        echo none
    fi
}

case "$cmd" in
    show-environment|daemon-reload|reset-failed)
        exit 0
        ;;
    unmask)
        # Faithful to real systemd (issue #328): `unmask --runtime` removes
        # ONLY the user/ symlink; the user.control/ entry survives.
        rm -f "$rtd/systemd/user/agent-mail.service" 2>/dev/null
        exit 0
        ;;
    is-enabled)
        if [[ -f "$state/force-enabled-report" ]]; then
            cat "$state/force-enabled-report"
            exit 1
        fi
        case "$(mask_state)" in
            persistent) echo masked; exit 1 ;;
            runtime) echo masked-runtime; exit 1 ;;
        esac
        if [[ -f "$state/enabled" ]]; then
            echo enabled
            exit 0
        fi
        echo disabled
        exit 1
        ;;
    is-active)
        [[ -f "$state/active" ]] && exit 0
        exit 3
        ;;
    enable)
        if [[ "$(mask_state)" != "none" ]]; then
            echo "Failed to enable unit: Unit agent-mail.service is masked." >&2
            exit 1
        fi
        touch "$state/enabled"
        for a in "${args[@]}"; do
            [[ "$a" == "--now" ]] && touch "$state/active"
        done
        exit 0
        ;;
    start|restart)
        if [[ "$(mask_state)" != "none" ]]; then
            echo "Failed to start agent-mail.service: Unit agent-mail.service is masked." >&2
            exit 1
        fi
        touch "$state/active"
        exit 0
        ;;
    show)
        prop=""
        i=0
        while [[ "$i" -lt "${#args[@]}" ]]; do
            if [[ "${args[i]}" == "-p" ]]; then
                prop="${args[i+1]:-}"
            fi
            i=$((i + 1))
        done
        case "$prop" in
            LoadState)
                if [[ -f "$state/force-loadstate" ]]; then
                    cat "$state/force-loadstate"
                elif [[ "$(mask_state)" == "none" ]]; then
                    echo loaded
                else
                    echo masked
                fi
                ;;
            *)
                echo ""
                ;;
        esac
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
SC_EOF
    chmod +x "$FAKE_HOME/.local/bin/systemctl"
}

mask_symlink() {
    ln -sf /dev/null "$1"
}

# Run _stack_configure_agent_mail_service inside the sandbox.
# Captures rc in CONFIGURE_RC and stderr in CONFIGURE_ERR_FILE.
CONFIGURE_RC=0
CONFIGURE_ERR_FILE=""
run_configure() {
    CONFIGURE_ERR_FILE="$SANDBOX/configure.stderr"
    CONFIGURE_RC=0
    env -i \
        PATH="$BASH_BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
        HOME="$FAKE_HOME" \
        TMPDIR="$SANDBOX" \
        TARGET_USER="$(id -un)" \
        ACFS_BIN_DIR="$FAKE_HOME/.local/bin" \
        ACFS_AM_RUNTIME_DIR="$FAKE_RTD" \
        FAKE_STATE_DIR="$FAKE_STATE_DIR" \
        FAKE_RTD="$FAKE_RTD" \
        ACFS_SKIP_AGENT_MAIL="${ACFS_SKIP_AGENT_MAIL:-0}" \
        LIB_DIR="$LIB_DIR" \
        bash -c '
            set -o pipefail
            export ACFS_BLUE="test"
            log_info() { :; }
            log_warn() { :; }
            log_error() { echo "[ERR] $*" >&2; }
            log_detail() { :; }
            log_debug() { :; }
            log_success() { :; }
            log_fatal() { echo "[FATAL] $*" >&2; exit 1; }
            source "$LIB_DIR/stack.sh"
            _stack_run_as_user() { bash -c "$1"; }
            _stack_configure_agent_mail_service
        ' 2> "$CONFIGURE_ERR_FILE"
    CONFIGURE_RC=$?
}

# Invoked indirectly through check/check_not.
# shellcheck disable=SC2329
calls_match() {
    grep -Eq "$1" "$FAKE_STATE_DIR/calls.log" 2>/dev/null
}

# Invoked indirectly through check/check_not.
# shellcheck disable=SC2329
service_active() {
    [[ -f "$FAKE_STATE_DIR/active" ]]
}

begin_test() {
    current_test="$1"
    echo ""
    echo "--- $current_test"
    make_sandbox
}

echo "=== Agent Mail mask-recovery sandbox harness (issue #328) ==="

# ------------------------------------------------------------
# Test 1: no mask at all -> normal path succeeds
# ------------------------------------------------------------
begin_test "no mask: unit written, enabled, active, rc 0"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check "unit file written" test -f "$UNIT_FILE"
check "service is active" service_active
check "LoadState assertion ran (show LoadState called)" grep -q "show agent-mail.service -p LoadState" "$FAKE_STATE_DIR/calls.log"

# ------------------------------------------------------------
# Test 2: runtime mask in user/ only -> cleared, service comes up
# ------------------------------------------------------------
begin_test "runtime mask in user/ only: cleared, rc 0"
mask_symlink "$RT_USER_MASK"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check_not "user/ mask symlink removed" test -L "$RT_USER_MASK"
check "service is active" service_active
check "clearing was announced" grep -q "clearing stale runtime mask" "$CONFIGURE_ERR_FILE"

# ------------------------------------------------------------
# Test 3: runtime mask in user.control/ only -> cleared even though
# `unmask --runtime` cannot remove it (the issue #328 core case)
# ------------------------------------------------------------
begin_test "runtime mask in user.control/ only: cleared, rc 0"
mask_symlink "$RT_CONTROL_MASK"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check_not "user.control/ mask symlink removed" test -L "$RT_CONTROL_MASK"
check "service is active" service_active
check "daemon-reload ran after clearing" grep -q "daemon-reload" "$FAKE_STATE_DIR/calls.log"
check "reset-failed ran after clearing" grep -q "reset-failed" "$FAKE_STATE_DIR/calls.log"

# ------------------------------------------------------------
# Test 4: runtime mask in BOTH locations -> both cleared
# ------------------------------------------------------------
begin_test "runtime mask in both locations: both cleared, rc 0"
mask_symlink "$RT_USER_MASK"
mask_symlink "$RT_CONTROL_MASK"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check_not "user/ mask symlink removed" test -L "$RT_USER_MASK"
check_not "user.control/ mask symlink removed" test -L "$RT_CONTROL_MASK"
check "service is active" service_active

# ------------------------------------------------------------
# Test 5: persistent mask -> deliberate opt-out, rc 75, untouched
# ------------------------------------------------------------
begin_test "persistent mask: respected, rc 75, nothing touched"
mask_symlink "$UNIT_FILE"
run_configure
check "rc is 75" test "$CONFIGURE_RC" -eq 75
check "persistent mask symlink preserved" test -L "$UNIT_FILE"
check_not "service was never started" service_active
check_not "no enable/start attempted" calls_match "(enable|start|restart)"
check "opt-out message printed" grep -q "respecting local opt-out" "$CONFIGURE_ERR_FILE"

# ------------------------------------------------------------
# Test 6: persistent AND runtime masks -> persistent wins, rc 75,
# runtime residue is NOT cleaned behind the operator's back
# ------------------------------------------------------------
begin_test "persistent + runtime masks: persistent opt-out wins, rc 75"
mask_symlink "$UNIT_FILE"
mask_symlink "$RT_USER_MASK"
mask_symlink "$RT_CONTROL_MASK"
run_configure
check "rc is 75" test "$CONFIGURE_RC" -eq 75
check "persistent mask preserved" test -L "$UNIT_FILE"
check "user/ runtime symlink untouched" test -L "$RT_USER_MASK"
check "user.control/ runtime symlink untouched" test -L "$RT_CONTROL_MASK"
check_not "service was never started" service_active

# ------------------------------------------------------------
# Test 7: unclearable runtime mask -> rc 1 (loud), NOT rc 75,
# with exact remediation commands; interruption-safe daemon-reload
# ------------------------------------------------------------
begin_test "unclearable runtime mask: loud rc 1 with remediation"
mask_symlink "$RT_USER_MASK"
mask_symlink "$RT_CONTROL_MASK"
chmod 555 "$FAKE_RTD/systemd/user.control"
run_configure
chmod 755 "$FAKE_RTD/systemd/user.control"
check "rc is 1 (loud failure)" test "$CONFIGURE_RC" -eq 1
check_not "rc is NOT 75 (not a bogus opt-out)" test "$CONFIGURE_RC" -eq 75
check_not "service was never started" service_active
check "remediation names user.control path" grep -q "user.control/agent-mail.service" "$CONFIGURE_ERR_FILE"
check "remediation includes daemon-reload" grep -q "systemctl --user daemon-reload" "$CONFIGURE_ERR_FILE"
check "remediation includes reset-failed" grep -q "reset-failed agent-mail.service" "$CONFIGURE_ERR_FILE"
check "remediation includes start" grep -q "systemctl --user start agent-mail.service" "$CONFIGURE_ERR_FILE"
reload_calls="$(grep -c "daemon-reload" "$FAKE_STATE_DIR/calls.log" 2>/dev/null)"
check "daemon-reload ran at least twice (inline + EXIT trap resync)" test "${reload_calls:-0}" -ge 2

# ------------------------------------------------------------
# Test 8: stray runtime mask symlink while is-enabled reports a
# non-masked state -> belt-and-braces clearing still fires
# ------------------------------------------------------------
begin_test "stray runtime symlink with non-masked is-enabled: still cleared"
mask_symlink "$RT_CONTROL_MASK"
printf 'disabled\n' > "$FAKE_STATE_DIR/force-enabled-report"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check_not "stray user.control/ symlink removed" test -L "$RT_CONTROL_MASK"
check "service is active" service_active

# ------------------------------------------------------------
# Test 9: post-update assertion fails loudly on a bad LoadState
# ------------------------------------------------------------
begin_test "post-update assertion: unexpected LoadState fails loudly"
printf 'bad-state\n' > "$FAKE_STATE_DIR/force-loadstate"
run_configure
check "rc is nonzero" test "$CONFIGURE_RC" -ne 0
check_not "rc is NOT 75" test "$CONFIGURE_RC" -eq 75
check "loud post-update message printed" grep -q "post-update check failed" "$CONFIGURE_ERR_FILE"

# ------------------------------------------------------------
# Test 10: post-update assertion catches a unit still masked after
# setup (mask reappearing mid-run) with remediation output
# ------------------------------------------------------------
begin_test "post-update assertion: still-masked unit fails loudly"
printf 'masked\n' > "$FAKE_STATE_DIR/force-loadstate"
run_configure
check "rc is nonzero" test "$CONFIGURE_RC" -ne 0
check_not "rc is NOT 75" test "$CONFIGURE_RC" -eq 75
check "still-masked message printed" grep -q "still masked after service setup" "$CONFIGURE_ERR_FILE"
check "remediation commands printed" grep -q "systemctl --user unmask --runtime agent-mail.service" "$CONFIGURE_ERR_FILE"

# ------------------------------------------------------------
# Test 11: ACFS_SKIP_AGENT_MAIL=1 -> rc 75 immediately (#327 guard)
# ------------------------------------------------------------
begin_test "ACFS_SKIP_AGENT_MAIL=1: rc 75, nothing touched"
ACFS_SKIP_AGENT_MAIL=1
export ACFS_SKIP_AGENT_MAIL
run_configure
unset ACFS_SKIP_AGENT_MAIL
check "rc is 75" test "$CONFIGURE_RC" -eq 75
check_not "unit file not written" test -e "$UNIT_FILE"
check_not "service was never started" service_active

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo ""
echo "=== Results: $passed passed, $failed failed ==="
if [[ "$failed" -gt 0 ]]; then
    exit 1
fi
exit 0
