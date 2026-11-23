#!/usr/bin/env bash
# ============================================================
# Sandbox Harness: Agent Mail service reconciliation (issues #327/#328/#505)
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
#   - repeated updates keep the same healthy process when executable
#     content and managed unit definition are unchanged (issue #505)
#   - an unchanged Type=notify process already initializing is allowed to
#     finish; a bounded wait still reports failure if it never becomes active
#   - changed binaries, managed units, or failed readiness still restart
#   - both public command links are repaired independently of the service;
#     missing, wrong, or blocked links never force a healthy-process restart
#   - without systemd, only the recorded, unchanged native process can no-op;
#     upgraded fallback images restart and unrelated listeners are preserved
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
    cat > "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail" <<'SERVER_EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    echo "mcp-agent-mail 0.0.0-test"
fi
exit 0
SERVER_EOF
    chmod +x "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail"

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
        if [[ -f "$state/startup-polls" ]]; then
            remaining="$(cat "$state/startup-polls")"
            if (( remaining > 0 )); then
                printf '%s\n' "$((remaining - 1))" > "$state/startup-polls"
                exit 3
            fi
        fi
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
        # A successful restart replaces the running image with the installed
        # one. Keep historical images so tests can distinguish a real restart
        # from merely rechecking service health.
        old_pid="$(cat "$state/main-pid" 2>/dev/null || echo 4241)"
        [[ "$old_pid" =~ ^[1-9][0-9]*$ ]] || old_pid=4241
        new_pid=$((old_pid + 1))
        mkdir -p "$ACFS_AM_PROC_DIR/$new_pid"
        cp "$HOME/mcp_agent_mail/am" "$ACFS_AM_PROC_DIR/$new_pid/exe"
        printf '%s\n' "$new_pid" > "$state/main-pid"
        touch "$state/active"
        [[ ! -f "$state/startup-polls" ]] || printf '0\n' > "$state/startup-polls"
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
            MainPID)
                cat "$state/main-pid" 2>/dev/null || echo 0
                ;;
            ActiveState)
                if [[ -f "$state/startup-polls" ]] && (( $(cat "$state/startup-polls") > 0 )); then
                    echo activating
                elif [[ -f "$state/active" ]]; then
                    echo active
                else
                    echo inactive
                fi
                ;;
            SubState)
                if [[ -f "$state/startup-polls" ]] && (( $(cat "$state/startup-polls") > 0 )); then
                    cat "$state/startup-substate" 2>/dev/null || echo start
                else
                    echo running
                fi
                if [[ -f "$state/rotate-pid-on-state-query" ]]; then
                    cat "$state/rotate-pid-on-state-query" > "$state/main-pid"
                fi
                ;;
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
        ACFS_AM_PROC_DIR="$SANDBOX/proc" \
        ACFS_FORCE_AGENT_MAIL_UNIT="${ACFS_FORCE_AGENT_MAIL_UNIT:-0}" \
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
            # Never probe a real Agent Mail on this machine: the service is
            # healthy and ready only when the test says so.
            _stack_agent_mail_healthy() { [[ -f "$FAKE_STATE_DIR/healthy" ]]; }
            _stack_agent_mail_readiness() {
                [[ -f "$FAKE_STATE_DIR/healthy" && ! -f "$FAKE_STATE_DIR/not-ready" ]]
            }
            _stack_configure_agent_mail_service
        ' 2> "$CONFIGURE_ERR_FILE"
    CONFIGURE_RC=$?
}

# Exercise the actual command-link helper and target-account runner. No service
# helper is called here: repairing PATH entries must have no process side effect.
LINK_REPAIR_RC=0
LINK_REPAIR_ERR_FILE=""
run_link_repair() {
    LINK_REPAIR_ERR_FILE="$SANDBOX/link-repair.stderr"
    LINK_REPAIR_RC=0
    env -i \
        PATH="$BASH_BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
        HOME="$FAKE_HOME" \
        TARGET_HOME="$FAKE_HOME" \
        TARGET_USER="$(id -un)" \
        ACFS_STACK_TRUST_TARGET_HOME=true \
        ACFS_BIN_DIR="${1:-$FAKE_HOME/.local/bin}" \
        LIB_DIR="$LIB_DIR" \
        bash -c '
            set -o pipefail
            export ACFS_BLUE="test"
            log_info() { :; }
            log_warn() { echo "[WARN] $*" >&2; }
            log_error() { echo "[ERR] $*" >&2; }
            log_detail() { :; }
            log_debug() { :; }
            log_success() { :; }
            log_fatal() { echo "[FATAL] $*" >&2; exit 1; }
            source "$LIB_DIR/stack.sh"
            # Keep the real target runner, but never resolve this test to the
            # callers passwd home (including /root when tests run as root).
            _stack_target_home() { printf "%s\n" "$HOME"; }
            _stack_repair_agent_mail_cli_symlink
        ' 2> "$LINK_REPAIR_ERR_FILE"
    LINK_REPAIR_RC=$?
}

# Invoked indirectly through check/check_not.
# shellcheck disable=SC2329
command_link_matches() {
    [[ -L "$1" && -x "$1" && "$(readlink "$1")" == "$2" ]]
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

echo "=== Agent Mail service-reconciliation sandbox harness (issues #327/#328/#505) ==="

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
# Restart regression cases: an update that changed nothing must not bounce the shared
# mail server. Every nightly and every manual `acfs update` used to restart
# it; on 2026-10-13 a forced xf retry on one host restarted it mid-day.
# ------------------------------------------------------------

# First run writes the unit and starts the service; then describe it as the
# running, healthy service whose executable is the installed binary.
settle_running_service() {
    run_configure
    echo 4242 > "$FAKE_STATE_DIR/main-pid"
    mkdir -p "$SANDBOX/proc/4242"
    cp "$FAKE_HOME/mcp_agent_mail/am" "$SANDBOX/proc/4242/exe"
    touch "$FAKE_STATE_DIR/healthy"
    : > "$FAKE_STATE_DIR/calls.log"
}

begin_test "unchanged, healthy service: not restarted"
settle_running_service
cp "$UNIT_FILE" "$SANDBOX/unchanged-unit"
for nightly_run in 1 2 3; do
    run_configure
    check "identical update $nightly_run: rc is 0" test "$CONFIGURE_RC" -eq 0
    check "identical update $nightly_run: main pid preserved" test "$(cat "$FAKE_STATE_DIR/main-pid")" = 4242
done
check_not "no restart issued" calls_match "restart agent-mail.service"
check "unit definition is unchanged" cmp -s "$UNIT_FILE" "$SANDBOX/unchanged-unit"
check "service is still active" service_active
check "skip was announced" grep -q "not restarting" "$CONFIGURE_ERR_FILE"
check "post-update assertion still ran" calls_match "show agent-mail.service -p LoadState"

begin_test "unchanged service still initializing: wait without restarting"
settle_running_service
touch "$FAKE_STATE_DIR/not-ready"
printf '2\n' > "$FAKE_STATE_DIR/startup-polls"
run_configure
check "startup completes successfully" test "$CONFIGURE_RC" -eq 0
check_not "initializing process is not restarted" calls_match "restart agent-mail.service"
check "initializing pid is preserved" test "$(cat "$FAKE_STATE_DIR/main-pid")" = 4242
check "startup wait is announced without claiming readiness" grep -q "still starting.*without restarting" "$CONFIGURE_ERR_FILE"
check_not "unready service is not described as ready" grep -q "is ready; not restarting" "$CONFIGURE_ERR_FILE"
check "post-update assertion still ran" calls_match "show agent-mail.service -p LoadState"

begin_test "unchanged initialization that never completes: fail without resetting progress"
settle_running_service
touch "$FAKE_STATE_DIR/not-ready"
printf '100\n' > "$FAKE_STATE_DIR/startup-polls"
# Model the existing bounded poll loop without waiting 30 wall-clock seconds.
# This stub only applies to this sandbox; assert every requested one-second wait.
cat > "$FAKE_HOME/.local/bin/sleep" <<'SLEEP_EOF'
#!/usr/bin/env bash
[[ "$*" == "1" ]] || exit 1
printf '%s\n' "$*" >> "$FAKE_STATE_DIR/sleeps.log"
SLEEP_EOF
chmod +x "$FAKE_HOME/.local/bin/sleep"
run_configure
check "unfinished startup remains a failure" test "$CONFIGURE_RC" -eq 1
check_not "timeout does not restart initialization" calls_match "restart agent-mail.service"
check "timed-out initialization pid is preserved" test "$(cat "$FAKE_STATE_DIR/main-pid")" = 4242
check "all thirty configured polls ran" test "$(wc -l < "$FAKE_STATE_DIR/sleeps.log")" -eq 30
check "failure names the active-state problem" grep -q "did not become active" "$CONFIGURE_ERR_FILE"

begin_test "changed executable during initialization: restarted"
settle_running_service
touch "$FAKE_STATE_DIR/not-ready"
printf '2\n' > "$FAKE_STATE_DIR/startup-polls"
printf '\n# Updated executable during startup.\n' >> "$FAKE_HOME/mcp_agent_mail/am"
run_configure
check "changed startup succeeds" test "$CONFIGURE_RC" -eq 0
check "changed executable still triggers restart" calls_match "restart agent-mail.service"
check_not "old startup pid is retained after binary change" test "$(cat "$FAKE_STATE_DIR/main-pid")" = 4242

begin_test "newly generated unit during initialization: restarted"
settle_running_service
touch "$FAKE_STATE_DIR/not-ready"
printf '2\n' > "$FAKE_STATE_DIR/startup-polls"
mv "$UNIT_FILE" "$SANDBOX/previous-unit"
run_configure
check "new unit setup succeeds" test "$CONFIGURE_RC" -eq 0
check "newly generated unit still triggers restart" calls_match "restart agent-mail.service"

begin_test "auto-restart backoff is not healthy initialization"
settle_running_service
touch "$FAKE_STATE_DIR/not-ready"
printf '2\n' > "$FAKE_STATE_DIR/startup-polls"
printf 'auto-restart\n' > "$FAKE_STATE_DIR/startup-substate"
run_configure
check "backoff recovery succeeds" test "$CONFIGURE_RC" -eq 0
check "failed service is not mistaken for startup" calls_match "restart agent-mail.service"

begin_test "startup process changes while checking: do not trust stale evidence"
settle_running_service
touch "$FAKE_STATE_DIR/not-ready"
printf '2\n' > "$FAKE_STATE_DIR/startup-polls"
printf '5000\n' > "$FAKE_STATE_DIR/rotate-pid-on-state-query"
run_configure
check "stale startup recovery succeeds" test "$CONFIGURE_RC" -eq 0
check "changed main pid invalidates startup preservation" calls_match "restart agent-mail.service"

begin_test "startup process image missing: restarted"
settle_running_service
touch "$FAKE_STATE_DIR/not-ready"
printf '2\n' > "$FAKE_STATE_DIR/startup-polls"
mv "$SANDBOX/proc/4242/exe" "$SANDBOX/proc/4242/exe.unavailable"
run_configure
check "unverifiable startup recovery succeeds" test "$CONFIGURE_RC" -eq 0
check "unverifiable startup image triggers restart" calls_match "restart agent-mail.service"

begin_test "installed binary differs from the running one: restarted"
settle_running_service
printf '#!/usr/bin/env bash\necho "am 0.0.1-new"\n' > "$FAKE_HOME/mcp_agent_mail/am"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check "restart issued" calls_match "restart agent-mail.service"
check "upgraded process uses new binary" cmp -s "$SANDBOX/proc/$(cat "$FAKE_STATE_DIR/main-pid")/exe" "$FAKE_HOME/mcp_agent_mail/am"
upgraded_pid="$(cat "$FAKE_STATE_DIR/main-pid")"
: > "$FAKE_STATE_DIR/calls.log"
run_configure
check "repeated update after upgrade succeeds" test "$CONFIGURE_RC" -eq 0
check_not "upgraded healthy process not restarted again" calls_match "restart agent-mail.service"
check "upgraded pid preserved" test "$(cat "$FAKE_STATE_DIR/main-pid")" = "$upgraded_pid"

begin_test "same-content binary replaced with a new inode: not restarted"
settle_running_service
cp "$FAKE_HOME/mcp_agent_mail/am" "$FAKE_HOME/mcp_agent_mail/am.next"
mv "$FAKE_HOME/mcp_agent_mail/am.next" "$FAKE_HOME/mcp_agent_mail/am"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check_not "unchanged executable content causes no restart" calls_match "restart agent-mail.service"

begin_test "binary content changed but version string unchanged: restarted"
settle_running_service
printf '\n# Same reported version, different installed executable bytes.\n' >> "$FAKE_HOME/mcp_agent_mail/am"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check "content change triggers restart" calls_match "restart agent-mail.service"

begin_test "service not healthy or ready: restarted"
settle_running_service
rm -f "$FAKE_STATE_DIR/healthy"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check "restart issued" calls_match "restart agent-mail.service"

begin_test "service alive but not ready: restarted"
settle_running_service
touch "$FAKE_STATE_DIR/not-ready"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check "failed readiness triggers restart" calls_match "restart agent-mail.service"

begin_test "unit rewritten: restarted"
settle_running_service
rm -f "$UNIT_FILE"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check "unit file written again" test -f "$UNIT_FILE"
check "restart issued" calls_match "restart agent-mail.service"

begin_test "managed unit definition changes: restarted once"
settle_running_service
mkdir -p "$FAKE_HOME/.config/mcp-agent-mail"
printf 'HTTP_PATH=/api/\n' > "$FAKE_HOME/.config/mcp-agent-mail/config.env"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check "changed managed unit is regenerated" grep -q 'ACFS template changed' "$CONFIGURE_ERR_FILE"
check "changed HTTP path is applied" grep -q -- '--path "/api/"' "$UNIT_FILE"
check "unit change triggers restart" calls_match "restart agent-mail.service"
: > "$FAKE_STATE_DIR/calls.log"
run_configure
check "repeat with changed unit succeeds" test "$CONFIGURE_RC" -eq 0
check_not "current managed unit causes no second restart" calls_match "restart agent-mail.service"

begin_test "operator unit edits: preserved without restarting healthy service"
settle_running_service
printf '\n[Service]\n# Operator hardening\nNoNewPrivileges=true\n' >> "$UNIT_FILE"
cp "$UNIT_FILE" "$SANDBOX/operator-unit"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check "local unit preserved" cmp -s "$UNIT_FILE" "$SANDBOX/operator-unit"
check "local modification notice printed" grep -q 'local modifications' "$CONFIGURE_ERR_FILE"
check_not "local edits do not force a healthy service restart" calls_match "restart agent-mail.service"

begin_test "explicit unit regeneration: backed up and restarted"
settle_running_service
printf '\n[Service]\nNoNewPrivileges=true\n' >> "$UNIT_FILE"
cp "$UNIT_FILE" "$SANDBOX/operator-unit"
ACFS_FORCE_AGENT_MAIL_UNIT=1 run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check "operator unit backed up" cmp -s "$UNIT_FILE.acfs-bak" "$SANDBOX/operator-unit"
check "explicit regeneration triggers restart" calls_match "restart agent-mail.service"

begin_test "running executable missing: restarted"
settle_running_service
mv "$SANDBOX/proc/4242/exe" "$SANDBOX/proc/4242/exe.unavailable"
run_configure
check "rc is 0" test "$CONFIGURE_RC" -eq 0
check "unverifiable running image triggers restart" calls_match "restart agent-mail.service"

begin_test "installed executable missing: fails without touching running service"
settle_running_service
mv "$FAKE_HOME/mcp_agent_mail/am" "$FAKE_HOME/mcp_agent_mail/am.unavailable"
run_configure
check "rc is 1" test "$CONFIGURE_RC" -eq 1
check_not "missing installed binary cannot stop a healthy process" calls_match "restart agent-mail.service"
check "missing binary reported" grep -q 'am CLI missing after install' "$CONFIGURE_ERR_FILE"

begin_test "operator disabled and stopped service: still respected"
settle_running_service
mv "$FAKE_STATE_DIR/enabled" "$FAKE_STATE_DIR/enabled.saved"
mv "$FAKE_STATE_DIR/active" "$FAKE_STATE_DIR/active.saved"
run_configure
check "rc is 75" test "$CONFIGURE_RC" -eq 75
check_not "disabled service not restarted" calls_match "restart agent-mail.service"
check "admin disable reported" grep -q 'respecting admin disable' "$CONFIGURE_ERR_FILE"

begin_test "service inactive or without a main pid: restarted"
settle_running_service
rm -f "$FAKE_STATE_DIR/active"
run_configure
check "inactive: restart issued" calls_match "restart agent-mail.service"
settle_running_service
rm -f "$FAKE_STATE_DIR/main-pid"
run_configure
check "no main pid: restart issued" calls_match "restart agent-mail.service"

# ------------------------------------------------------------
# Command links are mutable integration state, outside the release receipt.
# Reconcile both commands without reinstalling or restarting a healthy service.
# ------------------------------------------------------------
begin_test "missing CLI and server command links: repaired without restart"
settle_running_service
link_test_pid="$(cat "$FAKE_STATE_DIR/main-pid")"
run_link_repair
check "link repair succeeds" test "$LINK_REPAIR_RC" -eq 0
check "am command resolves to installed CLI" command_link_matches "$FAKE_HOME/.local/bin/am" "$FAKE_HOME/mcp_agent_mail/am"
check "server command resolves to installed server" command_link_matches "$FAKE_HOME/.local/bin/mcp-agent-mail" "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail"
check_not "link repair does not call systemctl" test -s "$FAKE_STATE_DIR/calls.log"
run_configure
check "service reconciliation succeeds after link repair" test "$CONFIGURE_RC" -eq 0
check_not "link repair does not restart healthy service" calls_match "restart agent-mail.service"
check "healthy process is unchanged" test "$(cat "$FAKE_STATE_DIR/main-pid")" = "$link_test_pid"

begin_test "correct command links: preserved across repeated repair"
run_link_repair
cli_link_inode="$(stat -c '%i' "$FAKE_HOME/.local/bin/am")"
server_link_inode="$(stat -c '%i' "$FAKE_HOME/.local/bin/mcp-agent-mail")"
run_link_repair
check "repeat link repair succeeds" test "$LINK_REPAIR_RC" -eq 0
check "correct CLI link inode is preserved" test "$(stat -c '%i' "$FAKE_HOME/.local/bin/am")" = "$cli_link_inode"
check "correct server link inode is preserved" test "$(stat -c '%i' "$FAKE_HOME/.local/bin/mcp-agent-mail")" = "$server_link_inode"

begin_test "wrong and dangling command links: repaired in configured and default bins"
configured_bin="$FAKE_HOME/operator command bin"
mkdir -p "$configured_bin"
ln -s "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail" "$configured_bin/am"
ln -s "$SANDBOX/absent-server" "$configured_bin/mcp-agent-mail"
ln -s "$SANDBOX/absent-cli" "$FAKE_HOME/.local/bin/am"
ln -s "$FAKE_HOME/mcp_agent_mail/am" "$FAKE_HOME/.local/bin/mcp-agent-mail"
run_link_repair "$configured_bin"
check "link repair succeeds for configured bin path with spaces" test "$LINK_REPAIR_RC" -eq 0
check "configured CLI link repaired" command_link_matches "$configured_bin/am" "$FAKE_HOME/mcp_agent_mail/am"
check "configured server link repaired" command_link_matches "$configured_bin/mcp-agent-mail" "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail"
check "default CLI link repaired" command_link_matches "$FAKE_HOME/.local/bin/am" "$FAKE_HOME/mcp_agent_mail/am"
check "default server link repaired" command_link_matches "$FAKE_HOME/.local/bin/mcp-agent-mail" "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail"

begin_test "canonical install directory configured as bin: binaries are preserved"
cp "$FAKE_HOME/mcp_agent_mail/am" "$SANDBOX/original-cli"
cp "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail" "$SANDBOX/original-server"
run_link_repair "$FAKE_HOME/mcp_agent_mail"
check "canonical bin repair succeeds" test "$LINK_REPAIR_RC" -eq 0
check_not "CLI binary is not replaced by a self-link" test -L "$FAKE_HOME/mcp_agent_mail/am"
check_not "server binary is not replaced by a self-link" test -L "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail"
check "CLI contents preserved" cmp -s "$SANDBOX/original-cli" "$FAKE_HOME/mcp_agent_mail/am"
check "server contents preserved" cmp -s "$SANDBOX/original-server" "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail"
check "default server link still repaired" command_link_matches "$FAKE_HOME/.local/bin/mcp-agent-mail" "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail"
ln -s "$FAKE_HOME/mcp_agent_mail" "$FAKE_HOME/canonical-bin-alias"
run_link_repair "$FAKE_HOME/canonical-bin-alias"
check "aliased canonical bin repair succeeds" test "$LINK_REPAIR_RC" -eq 0
check_not "aliased bin cannot replace CLI by self-link" test -L "$FAKE_HOME/mcp_agent_mail/am"
check_not "aliased bin cannot replace server by self-link" test -L "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail"
check "aliased bin preserves CLI contents" cmp -s "$SANDBOX/original-cli" "$FAKE_HOME/mcp_agent_mail/am"
check "aliased bin preserves server contents" cmp -s "$SANDBOX/original-server" "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail"

begin_test "directory blocks server command: explicit failure, no nested link or restart"
settle_running_service
mkdir "$FAKE_HOME/.local/bin/mcp-agent-mail"
printf 'operator-owned directory contents\n' > "$FAKE_HOME/.local/bin/mcp-agent-mail/keep"
run_link_repair
check "blocked link repair fails" test "$LINK_REPAIR_RC" -eq 1
check "blocked server link is reported" grep -q 'Unable to repair Agent Mail command link:.*mcp-agent-mail' "$LINK_REPAIR_ERR_FILE"
check "blocking directory contents preserved" grep -q 'operator-owned directory contents' "$FAKE_HOME/.local/bin/mcp-agent-mail/keep"
check_not "link is not silently placed inside the directory" test -L "$FAKE_HOME/.local/bin/mcp-agent-mail/mcp-agent-mail"
check_not "failed repair does not call systemctl" test -s "$FAKE_STATE_DIR/calls.log"
check "running service remains active" service_active

begin_test "configured bin path is blocked: fallback repaired, failure retained"
printf 'operator-owned file\n' > "$FAKE_HOME/blocked-bin"
run_link_repair "$FAKE_HOME/blocked-bin"
check "unusable configured bin makes repair fail" test "$LINK_REPAIR_RC" -eq 1
check "configured path failure is reported" grep -q 'Unable to repair Agent Mail command link:.*blocked-bin' "$LINK_REPAIR_ERR_FILE"
check "blocking file preserved" grep -q 'operator-owned file' "$FAKE_HOME/blocked-bin"
check "default CLI link is still repaired" command_link_matches "$FAKE_HOME/.local/bin/am" "$FAKE_HOME/mcp_agent_mail/am"
check "default server link is still repaired" command_link_matches "$FAKE_HOME/.local/bin/mcp-agent-mail" "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail"

begin_test "missing server payload: no command links fabricated, service untouched"
settle_running_service
mv "$FAKE_HOME/mcp_agent_mail/mcp-agent-mail" "$SANDBOX/server-unavailable"
mv "$FAKE_HOME/.local/bin/am" "$SANDBOX/cli-link-before-missing-server"
run_link_repair
check "missing server source makes repair fail" test "$LINK_REPAIR_RC" -eq 1
check "missing server source is reported" grep -q 'command missing or not executable:.*mcp-agent-mail' "$LINK_REPAIR_ERR_FILE"
check_not "no CLI link is created before validating both payloads" test -L "$FAKE_HOME/.local/bin/am"
check_not "no dangling server link is created" test -L "$FAKE_HOME/.local/bin/mcp-agent-mail"
check_not "missing server does not call systemctl" test -s "$FAKE_STATE_DIR/calls.log"

# Exercise the actual fallback helpers with harmless native sleepers. A copied
# sleep executable supplies real /proc image identity, including the old-cli
# pathname produced by an upstream installer transaction. Only HTTP responses
# and nohup's final argument translation are fixtures; no listener is opened,
# no Agent Mail binary runs, and every signalled process is our own child.
if [[ -d /proc/self && -x /bin/sleep ]] && command -v python3 >/dev/null 2>&1; then
    begin_test "native fallback upgrades, no-ops and process ownership"
    fallback_library="$SANDBOX/fallback-functions.sh"
    if python3 - "${ACFS_STACK_TEST_LIBRARY:-$LIB_DIR/stack.sh}" "$fallback_library" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text()
required = ("_stop_agent_mail_pid", "stop_agent_mail_fallback",
            "launch_agent_mail_fallback", "agent_mail_endpoint_ready",
            "agent_mail_readiness_ready")
optional = ("agent_mail_pid_matches", "agent_mail_endpoint_alive")
bodies = []
for name in (*required, *optional):
    body = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}", source, re.M | re.S)
    if body is None:
        if name in required:
            raise AssertionError("missing fallback helper: " + name)
        continue
    bodies.append(body[0])
Path(sys.argv[2]).write_text("\n\n".join(bodies) + "\n")
PY
    then
        if env -i PATH="$BASH_BIN_DIR:/usr/bin:/bin" HOME="$FAKE_HOME" \
            FALLBACK_LIBRARY="$fallback_library" bash -p <<'FALLBACK_TEST'
set -euo pipefail
# shellcheck disable=SC1090
source "$FALLBACK_LIBRARY"
am_bin="$HOME/mcp_agent_mail/am"
storage_root="$HOME/mailbox"
fallback_pid_file="$storage_root/agent-mail.pid"
fallback_log_file="$storage_root/agent-mail.log"
db_url="sqlite:///$storage_root/storage.sqlite3"
am_mcp_path=/mcp/
write_unit=true
external_listener=false
launch_log="$HOME/launches"
mkdir -p "$storage_root"
mv "$am_bin" "$am_bin.script-fixture"
cp /bin/sleep "$am_bin"
trap 'for child in $(jobs -pr); do kill "$child" 2>/dev/null || true; done; wait 2>/dev/null || true' EXIT

# Invoked by the extracted production helpers.
# shellcheck disable=SC2329
systemctl() { return 1; }
# shellcheck disable=SC2329
stack_service_curl() {
    local pid=""
    if [[ "$external_listener" != true ]]; then
        [[ -f "$fallback_pid_file" && ! -L "$fallback_pid_file" ]] || return 1
        pid="$(cat "$fallback_pid_file")"
        [[ "$pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null || return 1
    fi
    printf '{"status":"ready"}\n'
}
# shellcheck disable=SC2329
nohup() {
    printf '%s\n' "$*" >> "$launch_log"
    exec -a "$am_bin serve-http --port 8765" "$am_bin" 120
}
current_pid=""
await_running_image() {
    current_pid="$(cat "$fallback_pid_file")"
    for _ in {1..100}; do
        if cmp -s "/proc/$current_pid/exe" "$am_bin"; then
            return 0
        fi
        sleep 0.01
    done
    echo "Native fallback never ran the installed image" >&2
    return 1
}
assert_launch_count() { [[ "$(wc -l < "$launch_log")" -eq "$1" ]]; }

launch_agent_mail_fallback
await_running_image
first_pid="$current_pid"
write_unit=false
launch_agent_mail_fallback
[[ "$(cat "$fallback_pid_file")" == "$first_pid" ]]
assert_launch_count 1
echo 'FALLBACK PASS: unchanged healthy native process is preserved'

history="$HOME/mcp_agent_mail/.mcp-agent-mail-install-transaction.committed.first"
mkdir "$history"
mv "$am_bin" "$history/old-cli"
cp "$history/old-cli" "$am_bin"
launch_agent_mail_fallback
[[ "$(cat "$fallback_pid_file")" == "$first_pid" ]]
assert_launch_count 1
echo 'FALLBACK PASS: identical replacement with a new inode is preserved'

history="$HOME/mcp_agent_mail/.mcp-agent-mail-install-transaction.committed.second"
mkdir "$history"
mv "$am_bin" "$history/old-cli"
cp /bin/sleep "$am_bin"
printf '\nfixture: new release bytes\n' >> "$am_bin"
launch_agent_mail_fallback
current_pid="$(cat "$fallback_pid_file")"
if [[ "$current_pid" == "$first_pid" ]]; then
    echo 'Changed fallback release left the original PID running' >&2
    exit 1
fi
await_running_image
! kill -0 "$first_pid" 2>/dev/null
assert_launch_count 2
launch_agent_mail_fallback
[[ "$(cat "$fallback_pid_file")" == "$current_pid" ]]
assert_launch_count 2
echo 'FALLBACK PASS: archived old image is stopped; new release starts exactly once'

previous_pid="$current_pid"
write_unit=true
launch_agent_mail_fallback
await_running_image
[[ "$current_pid" != "$previous_pid" ]]
! kill -0 "$previous_pid" 2>/dev/null
assert_launch_count 3
write_unit=false
echo 'FALLBACK PASS: changed launch configuration restarts the native fallback'

# A leftover fallback PID can identify the process after systemd adopted it.
# That process belongs to its supervisor and must never receive our SIGTERM.
# shellcheck disable=SC2329
systemctl() {
    case "$*" in
        '--user show-environment') return 0 ;;
        '--user show agent-mail.service -p MainPID --value') printf '%s\n' "$current_pid" ;;
        *) return 1 ;;
    esac
}
_stop_agent_mail_pid "$current_pid"
kill -0 "$current_pid"
# shellcheck disable=SC2329
systemctl() { return 1; }
echo 'FALLBACK PASS: supervised process is left to systemd during handoff'

cp /bin/sleep "$HOME/unrelated-am"
(exec -a "$am_bin serve-http --port 8765" "$HOME/unrelated-am" 120) &
unrelated_pid=$!
for _ in {1..100}; do
    [[ "$(readlink -f "/proc/$unrelated_pid/exe")" == "$HOME/unrelated-am" ]] && break
    sleep 0.01
done
[[ "$(readlink -f "/proc/$unrelated_pid/exe")" == "$HOME/unrelated-am" ]]
printf '%s\n' "$unrelated_pid" > "$fallback_pid_file"
if launch_agent_mail_fallback; then
    echo 'Unrelated PID was accepted as the installed fallback' >&2
    exit 1
fi
kill -0 "$unrelated_pid"
kill -0 "$current_pid"
[[ "$(cat "$fallback_pid_file")" == "$unrelated_pid" ]]
assert_launch_count 3
kill "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || true
printf '%s\n' "$current_pid" > "$fallback_pid_file"
echo 'FALLBACK PASS: unrelated native process and its PID record are preserved'

kill "$current_pid"
wait "$current_pid" 2>/dev/null || true
launch_agent_mail_fallback
await_running_image
assert_launch_count 4
echo 'FALLBACK PASS: stale dead PID is replaced by a working native process'

kill "$current_pid"
wait "$current_pid" 2>/dev/null || true
mv "$fallback_pid_file" "$fallback_pid_file.retained"
external_listener=true
if launch_agent_mail_fallback; then
    echo 'Untracked healthy listener was accepted as the installed fallback' >&2
    exit 1
fi
[[ ! -e "$fallback_pid_file" ]]
assert_launch_count 4
external_listener=false
echo 'FALLBACK PASS: untracked healthy listener is not adopted or replaced'

printf 'not-a-pid\n' > "$fallback_pid_file"
if launch_agent_mail_fallback; then exit 1; fi
[[ "$(cat "$fallback_pid_file")" == not-a-pid ]]
mv "$fallback_pid_file" "$fallback_pid_file.invalid"
ln -s "$fallback_pid_file.invalid" "$fallback_pid_file"
if launch_agent_mail_fallback; then exit 1; fi
[[ -L "$fallback_pid_file" ]]
[[ "$(cat "$fallback_pid_file.invalid")" == not-a-pid ]]
assert_launch_count 4
echo 'FALLBACK PASS: invalid and symlinked PID records fail without mutation'
FALLBACK_TEST
        then
            say_pass "native fallback upgrade and ownership regressions"
        else
            say_fail "native fallback upgrade and ownership regressions"
        fi
    else
        say_fail "native fallback helper extraction"
    fi
else
    echo '[SKIP] Native fallback process checks require Linux /proc, /bin/sleep and Python 3'
fi

# ------------------------------------------------------------
# Generated install_stack.sh & install.sh port-holder pipefail regressions
# ------------------------------------------------------------
echo ""
echo "=== Test: agent_mail_port_holder under set -euo pipefail (free port lsof rc=1 & multi-line SIGPIPE) ==="
if command -v python3 >/dev/null 2>&1; then
    if python3 - "$REPO_ROOT/scripts/generated/install_stack.sh" "$REPO_ROOT/install.sh" "$BASH" <<'PORT_HOLDER_TEST'
import os
import re
import stat
import subprocess
import sys
import tempfile

install_stack_path, install_sh_path, bash_bin = sys.argv[1:4]

def extract_funcs(path, expected_count):
    text = open(path, encoding="utf-8").read()
    lines = text.splitlines()
    funcs = []
    i = 0
    while i < len(lines):
        if re.match(r"^\s*agent_mail_port_holder\(\)\s*\{$", lines[i]):
            indent = re.match(r"^(\s*)", lines[i]).group(1)
            body = [lines[i][len(indent):]]
            i += 1
            while i < len(lines):
                line = lines[i]
                body.append(line[len(indent):] if line.startswith(indent) else line)
                if line == f"{indent}}}":
                    break
                i += 1
            funcs.append("\n".join(body))
        i += 1
    assert len(funcs) == expected_count, f"{path}: expected {expected_count} agent_mail_port_holder definitions, found {len(funcs)}"
    return funcs

stack_funcs = extract_funcs(install_stack_path, 2)
install_funcs = extract_funcs(install_sh_path, 1)

# Verify install.sh has no single quotes inside its target-user agent_mail_port_holder block
assert "'" not in install_funcs[0], "install.sh target-user agent_mail_port_holder must not contain single quotes"

# Verify neither file retains unguarded lsof/ss pipelines to head/tail
for label, src_path in [("install_stack.sh", install_stack_path), ("install.sh", install_sh_path)]:
    src = open(src_path, encoding="utf-8").read()
    assert "lsof -nP -iTCP:8765 -sTCP:LISTEN 2>/dev/null | tail" not in src, f"{label} still has unguarded lsof pipeline"

def write_exec(path, content):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)
    os.chmod(path, stat.S_IRWXU)

with tempfile.TemporaryDirectory(prefix="acfs-port-holder-") as tmp:
    awk_path = subprocess.check_output(["which", "awk"], text=True).strip()

    cases = [
        ("lsof_free_port_rc1", "lsof", f"#!{bash_bin}\nexit 1\n", ""),
        (
            "lsof_six_listeners_no_sigpipe",
            "lsof",
            f"#!{bash_bin}\n"
            "printf 'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\\n'\n"
            "for i in 1 2 3 4 5 6; do printf 'cm 10%d ubuntu 5u IPv4 1 0t0 TCP 127.0.0.1:8765 (LISTEN)\\n' \"$i\"; done\n",
            "cm 101 ubuntu 5u IPv4 1 0t0 TCP 127.0.0.1:8765 (LISTEN)\n"
            "cm 102 ubuntu 5u IPv4 1 0t0 TCP 127.0.0.1:8765 (LISTEN)\n"
            "cm 103 ubuntu 5u IPv4 1 0t0 TCP 127.0.0.1:8765 (LISTEN)",
        ),
        ("ss_free_port_rc1", "ss", f"#!{bash_bin}\nexit 1\n", ""),
        (
            "ss_six_listeners_no_sigpipe",
            "ss",
            f"#!{bash_bin}\n"
            "for i in 1 2 3 4 5 6; do printf 'LISTEN 0 128 127.0.0.1:8765 0.0.0.0:* users:((\"cm\",pid=20%d,fd=5))\\n' \"$i\"; done\n",
            "LISTEN 0 128 127.0.0.1:8765 0.0.0.0:* users:((\"cm\",pid=201,fd=5))\n"
            "LISTEN 0 128 127.0.0.1:8765 0.0.0.0:* users:((\"cm\",pid=202,fd=5))\n"
            "LISTEN 0 128 127.0.0.1:8765 0.0.0.0:* users:((\"cm\",pid=203,fd=5))",
        ),
    ]

    all_funcs = [
        ("install_stack.sh#1", stack_funcs[0]),
        ("install_stack.sh#2", stack_funcs[1]),
        ("install.sh#1", install_funcs[0]),
    ]

    for case_name, tool_name, stub_body, expected_out in cases:
        bin_dir = os.path.join(tmp, case_name)
        os.makedirs(bin_dir, exist_ok=True)
        write_exec(os.path.join(bin_dir, tool_name), stub_body)
        os.symlink(awk_path, os.path.join(bin_dir, "awk"))
        env = {"PATH": bin_dir, "HOME": tmp}
        for func_label, func_src in all_funcs:
            script = f"set -euo pipefail\n{func_src}\nholder=\"$(agent_mail_port_holder)\"\nprintf '%s' \"$holder\"\n"
            proc = subprocess.run([bash_bin, "-c", script], env=env, capture_output=True, text=True)
            assert proc.returncode == 0, f"{func_label} [{case_name}] failed rc={proc.returncode} stderr={proc.stderr!r}"
            assert proc.stdout == expected_out, f"{func_label} [{case_name}] stdout mismatch:\n  got:  {proc.stdout!r}\n  want: {expected_out!r}"

    # Verify _systemctl_user_ok fallback branch survives set -euo pipefail when systemctl fails
    sys_dir = os.path.join(tmp, "systemctl_fail")
    os.makedirs(sys_dir, exist_ok=True)
    write_exec(os.path.join(sys_dir, "systemctl"), f"#!{bash_bin}\nexit 1\n")
    sys_script = """
set -euo pipefail
_systemctl_user_ok=false
XDG_RUNTIME_DIR="/nonexistent"
if command -v systemctl >/dev/null 2>&1; then
  if ! systemctl --user show-environment >/dev/null 2>&1; then
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
      export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
    fi
    if systemctl --user show-environment >/dev/null 2>&1; then
      _systemctl_user_ok=true
    fi
  else
    _systemctl_user_ok=true
  fi
fi
printf '%s' "$_systemctl_user_ok"
"""
    proc = subprocess.run([bash_bin, "-c", sys_script], env={"PATH": sys_dir, "HOME": tmp}, capture_output=True, text=True)
    assert proc.returncode == 0 and proc.stdout == "false", f"systemctl fallback failed rc={proc.returncode} out={proc.stdout!r} err={proc.stderr!r}"

print("PORT_HOLDER_PIPEFAIL_TESTS_PASS")
PORT_HOLDER_TEST
    then
        say_pass "agent_mail_port_holder pipefail free-port and multi-line regressions"
    else
        say_fail "agent_mail_port_holder pipefail free-port and multi-line regressions"
    fi
else
    echo '[SKIP] agent_mail_port_holder pipefail checks require Python 3'
fi

# ------------------------------------------------------------
# Agent Mail setsid detach & transient readiness-refresh regressions
# ------------------------------------------------------------
echo ""
echo "=== Test: Agent Mail fallback setsid detach & verify readiness lazy-refresh retry ==="
if command -v python3 >/dev/null 2>&1; then
    if python3 - "$REPO_ROOT/scripts/generated/install_stack.sh" "$REPO_ROOT/install.sh" "$REPO_ROOT/scripts/generated/manifest_index.sh" "$BASH" <<'SETSID_AND_RETRY_TEST'
import subprocess
import sys

install_stack_path, install_sh_path, manifest_index_path, bash_bin = sys.argv[1:5]

stack_src = open(install_stack_path, encoding="utf-8").read()
install_src = open(install_sh_path, encoding="utf-8").read()
index_src = open(manifest_index_path, encoding="utf-8").read()

# 1. Both install_stack.sh and install.sh detach fallback daemon via setsid when available
assert "setsid nohup env" in stack_src, "install_stack.sh missing setsid detach for Agent Mail fallback"
assert "setsid nohup env" in install_src, "install.sh missing setsid detach for Agent Mail fallback"

# 2. Live Linux setsid check: setsid nohup sleep detaches PGID while preserving $! == daemon PID
if subprocess.run(["which", "setsid"], capture_output=True).returncode == 0:
    proc = subprocess.run(
        [
            bash_bin,
            "-c",
            "set -euo pipefail; "
            "setsid nohup sleep 5 >/dev/null 2>&1 </dev/null & "
            "p=$!; sleep 0.1; "
            "parent_pgid=$(ps -o pgid= -p $$ | tr -d ' '); "
            "child_pgid=$(ps -o pgid= -p \"$p\" | tr -d ' '); "
            "kill \"$p\" 2>/dev/null || true; "
            "test -n \"$child_pgid\" && test \"$child_pgid\" != \"$parent_pgid\" && test \"$child_pgid\" = \"$p\"",
        ],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"setsid detach check failed rc={proc.returncode} err={proc.stderr!r}"

# 3. Verify stack.mcp_agent_mail.1 retries past a transient 503 database_probe_stale to ready
assert "verify_attempt" in index_src and "until agent_mail_readiness_ready" in index_src, (
    "manifest_index.sh stack.mcp_agent_mail.1 missing readiness retry loop"
)
retry_probe_script = r"""
set -euo pipefail
source "$1"
verify_cmd="${ACFS_MODULE_VERIFY_COMMAND[stack.mcp_agent_mail.1]}"
# Override curl helper and systemctl after defining them via eval-wrapped test harness
attempt_file="$(mktemp)"
printf '0\n' > "$attempt_file"
trap 'rm -f "$attempt_file"' EXIT
patched_cmd="${verify_cmd/agent_mail_service_curl()/agent_mail_service_curl_orig()}"
patched_cmd="
systemctl() { return 1; }
sleep() { :; }
agent_mail_service_curl() {
  local url=\"\${@: -1}\"
  if [[ \"\$url\" == */health/liveness ]]; then
    printf '{\"status\":\"alive\"}\n'
    return 0
  fi
  local n
  n=\$(cat \"$attempt_file\")
  n=\$((n + 1))
  printf '%s\n' \"\$n\" > \"$attempt_file\"
  # First 2 calls simulate 503 database_probe_stale on both /health/readiness and /health
  if [[ \"\$n\" -le 2 ]]; then
    return 22
  fi
  printf '{\"status\":\"ready\"}\n'
  return 0
}
$patched_cmd
"
bash -c "set -euo pipefail; $patched_cmd"
calls="$(cat "$attempt_file")"
test "$calls" -eq 3
"""
proc = subprocess.run([bash_bin, "-c", retry_probe_script, "_", manifest_index_path], capture_output=True, text=True)
assert proc.returncode == 0, f"readiness retry probe failed rc={proc.returncode} out={proc.stdout!r} err={proc.stderr!r}"

# 4. Also verify persistent failure still exits nonzero (fail-closed)
fail_probe_script = r"""
set -euo pipefail
source "$1"
verify_cmd="${ACFS_MODULE_VERIFY_COMMAND[stack.mcp_agent_mail.1]}"
patched_cmd="${verify_cmd/agent_mail_service_curl()/agent_mail_service_curl_orig()}"
patched_cmd="
systemctl() { return 1; }
sleep() { :; }
agent_mail_service_curl() {
  local url=\"\${@: -1}\"
  if [[ \"\$url\" == */health/liveness ]]; then
    printf '{\"status\":\"alive\"}\n'
    return 0
  fi
  return 22
}
$patched_cmd
"
if bash -c "set -euo pipefail; $patched_cmd"; then
  exit 1
fi
"""
proc2 = subprocess.run([bash_bin, "-c", fail_probe_script, "_", manifest_index_path], capture_output=True, text=True)
assert proc2.returncode == 0, f"readiness fail-closed probe failed rc={proc2.returncode} err={proc2.stderr!r}"

print("SETSID_AND_RETRY_TESTS_PASS")
SETSID_AND_RETRY_TEST
    then
        say_pass "Agent Mail fallback setsid detach and readiness lazy-refresh retry regressions"
    else
        say_fail "Agent Mail fallback setsid detach and readiness lazy-refresh retry regressions"
    fi
else
    echo '[SKIP] Agent Mail setsid/retry checks require Python 3'
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo ""
echo "=== Results: $passed passed, $failed failed ==="
if [[ "$failed" -gt 0 ]]; then
    exit 1
fi
exit 0
