#!/usr/bin/env bash
# ============================================================
# ACFS Services — Unified background daemon management
# Manages Agent Mail, CM serve, and the CASS indexer. Agent Mail reuses the
# ACFS native user service when available; tmux is the portable fallback and
# owns the CM/CASS processes.
#
# Usage:
#   acfs services start       Start all services (repairs a partial session)
#   acfs services stop        Stop all services
#   acfs services status      Show which services are running
#   acfs services restart [svc...]  Restart everything, or just named services
#   acfs services repair      Relaunch only the services that are not running
#   acfs services drift       Report services running a replaced binary
#   acfs services logs [svc]  Attach to a service pane for logs
#
# Services:
#   agent-mail: native user service, or am serve-http fallback
#   cm:         cm serve
#   cass:       cass index --watch
#
# The tmux session is named "acfs-svc" to avoid conflicts.
# Pane numbering adapts to the user's tmux pane-base-index.
# ============================================================

set -euo pipefail

# --- Constants ---
readonly ACFS_SVC_SESSION="acfs-svc"
readonly ACFS_SVC_VERSION="1.2.0"

# --- HTTP service endpoints ---
# Both `am serve-http` and `cm serve` default to 127.0.0.1:8765, so launching
# them together makes the second one fail to bind ("address already in use").
# Agent Mail's managed ACFS service owns 8765. Move CM to 8766, matching the
# manifest, installer, doctor checks, README, and the original command contract.
readonly ACFS_DEFAULT_AGENT_MAIL_HOST="127.0.0.1"
readonly ACFS_DEFAULT_AGENT_MAIL_PORT="8765"
readonly ACFS_DEFAULT_CM_HOST="127.0.0.1"
readonly ACFS_DEFAULT_CM_PORT="8766"

ACFS_AGENT_MAIL_HOST="${ACFS_AGENT_MAIL_HOST:-$ACFS_DEFAULT_AGENT_MAIL_HOST}"
ACFS_AGENT_MAIL_PORT="${ACFS_AGENT_MAIL_PORT:-$ACFS_DEFAULT_AGENT_MAIL_PORT}"
ACFS_CM_HOST="${ACFS_CM_HOST:-$ACFS_DEFAULT_CM_HOST}"
ACFS_CM_PORT="${ACFS_CM_PORT:-$ACFS_DEFAULT_CM_PORT}"

readonly -a ACFS_SERVICE_NAMES=("agent-mail" "cm" "cass")

# --- State ---
_DRY_RUN=false
_TMUX_BIN=""
_CURL_BIN=""
_SS_BIN=""
_LSOF_BIN=""
_SYSTEMCTL_BIN=""
_JOURNALCTL_BIN=""
_AM_BIN=""
_CM_BIN=""
_CASS_BIN=""

# --- Colors (degrade gracefully) ---
if [[ -t 1 ]] && [[ "${TERM:-dumb}" != "dumb" ]]; then
    _C_RESET=$'\033[0m'
    _C_BOLD=$'\033[1m'
    _C_GREEN=$'\033[32m'
    _C_RED=$'\033[31m'
    _C_YELLOW=$'\033[33m'
    _C_CYAN=$'\033[36m'
    _C_DIM=$'\033[2m'
else
    _C_RESET="" _C_BOLD="" _C_GREEN="" _C_RED="" _C_YELLOW="" _C_CYAN="" _C_DIM=""
fi

# --- Helpers ---

_info()  { printf '%s[acfs-services]%s %s\n' "$_C_CYAN" "$_C_RESET" "$*" >&2; }
_ok()    { printf '%s[acfs-services]%s %s%s%s\n' "$_C_CYAN" "$_C_RESET" "$_C_GREEN" "$*" "$_C_RESET" >&2; }
_warn()  { printf '%s[acfs-services]%s %s%s%s\n' "$_C_CYAN" "$_C_RESET" "$_C_YELLOW" "$*" "$_C_RESET" >&2; }
_err()   { printf '%s[acfs-services]%s %s%s%s\n' "$_C_CYAN" "$_C_RESET" "$_C_RED" "$*" "$_C_RESET" >&2; }

_system_binary_path() {
    local name="${1:-}"
    local dir=""

    [[ "$name" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
    for dir in /usr/bin /bin /usr/sbin /sbin /usr/local/bin /usr/local/sbin /opt/homebrew/bin; do
        if [[ -x "$dir/$name" && ! -d "$dir/$name" ]]; then
            printf '%s\n' "$dir/$name"
            return 0
        fi
    done
    return 1
}

# Directories ACFS installs user-scoped tools into, in resolution order.
# `acfs services` is routinely invoked from a noninteractive SSH command whose
# PATH does not include them (#382), so PATH alone must not decide whether a
# managed binary exists.
_user_install_dirs() {
    local home_dir="${HOME:-}"
    local dir=""
    local -a dirs=()

    [[ -n "${ACFS_BIN_DIR:-}" ]] && dirs+=("$ACFS_BIN_DIR")
    if [[ -n "$home_dir" && "$home_dir" == /* ]]; then
        dirs+=("$home_dir/.local/bin" "$home_dir/.acfs/bin" "$home_dir/.cargo/bin" "$home_dir/bin")
    fi
    dirs+=("/usr/local/bin" "/opt/homebrew/bin")

    for dir in "${dirs[@]}"; do
        [[ -n "$dir" && "$dir" == /* ]] || continue
        printf '%s\n' "$dir"
    done
}

_user_binary_path() {
    local name="${1:-}"
    local resolved=""
    local dir=""

    [[ "$name" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
    resolved="$(type -P "$name" 2>/dev/null || true)"
    if [[ -n "$resolved" && "$resolved" == /* && -x "$resolved" && ! -d "$resolved" ]]; then
        printf '%s\n' "$resolved"
        return 0
    fi

    # PATH did not resolve it: fall back to the known ACFS install locations.
    while IFS= read -r dir; do
        [[ -n "$dir" ]] || continue
        if [[ -x "$dir/$name" && ! -d "$dir/$name" ]]; then
            printf '%s\n' "$dir/$name"
            return 0
        fi
    done < <(_user_install_dirs)
    return 1
}

_initialize_bins() {
    _TMUX_BIN="$(_system_binary_path tmux 2>/dev/null || _user_binary_path tmux 2>/dev/null || true)"
    _CURL_BIN="$(_system_binary_path curl 2>/dev/null || true)"
    _SS_BIN="$(_system_binary_path ss 2>/dev/null || true)"
    _LSOF_BIN="$(_system_binary_path lsof 2>/dev/null || true)"
    _SYSTEMCTL_BIN="$(_system_binary_path systemctl 2>/dev/null || true)"
    _JOURNALCTL_BIN="$(_system_binary_path journalctl 2>/dev/null || true)"
    _AM_BIN="$(_user_binary_path am 2>/dev/null || true)"
    _CM_BIN="$(_user_binary_path cm 2>/dev/null || true)"
    _CASS_BIN="$(_user_binary_path cass 2>/dev/null || true)"
}

_service_desc() {
    case "$1" in
        agent-mail) printf '%s\n' "Agent Mail HTTP server" ;;
        cm)         printf '%s\n' "CASS Memory server" ;;
        cass)       printf '%s\n' "CASS indexer (watch mode)" ;;
        *)          return 1 ;;
    esac
}

_quote_command() {
    local quoted=""
    local arg=""
    local part=""

    for arg in "$@"; do
        printf -v part '%q' "$arg"
        quoted+="${quoted:+ }$part"
    done
    printf '%s\n' "$quoted"
}

_service_cmd() {
    case "$1" in
        agent-mail)
            _quote_command "$_AM_BIN" serve-http --no-tui --host "$ACFS_AGENT_MAIL_HOST" --port "$ACFS_AGENT_MAIL_PORT"
            ;;
        cm)
            _quote_command "$_CM_BIN" serve --host "$ACFS_CM_HOST" --port "$ACFS_CM_PORT"
            ;;
        cass)
            _quote_command "$_CASS_BIN" index --watch
            ;;
        *)
            return 1
            ;;
    esac
}

_session_exists() {
    [[ -n "$_TMUX_BIN" ]] && "$_TMUX_BIN" has-session -t "$ACFS_SVC_SESSION" 2>/dev/null
}

# Validate a value is a usable TCP port (1-65535).
_is_valid_port() {
    local p="$1"
    [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 ))
}

_is_valid_host() {
    local host="$1"
    [[ -n "$host" && "$host" =~ ^[A-Za-z0-9._:-]+$ ]]
}

_hosts_overlap() {
    local left="$1" right="$2"

    [[ "$left" == "$right" ]] && return 0
    case "$left" in
        0.0.0.0|\*|::) return 0 ;;
    esac
    case "$right" in
        0.0.0.0|\*|::) return 0 ;;
    esac
    [[ "$left" == "localhost" && ( "$right" == "127.0.0.1" || "$right" == "::1" ) ]] && return 0
    [[ "$right" == "localhost" && ( "$left" == "127.0.0.1" || "$left" == "::1" ) ]]
}

# Return 0 if something is already listening on host:port, 1 if free,
# 2 if we have no tool to check (treated as "free" by callers).
_port_is_listening() {
    local host="$1" port="$2"
    local socket_addr=""
    local bound_host=""

    if [[ -n "$_LSOF_BIN" ]]; then
        "$_LSOF_BIN" -nP "-iTCP@${host}:${port}" -sTCP:LISTEN &>/dev/null
        return $?
    elif [[ -n "$_SS_BIN" ]]; then
        while IFS= read -r socket_addr; do
            [[ -n "$socket_addr" ]] || continue
            bound_host="${socket_addr%:$port}"
            bound_host="${bound_host#[}"
            bound_host="${bound_host%]}"
            if _hosts_overlap "$host" "$bound_host"; then
                return 0
            fi
        done < <("$_SS_BIN" -H -ltn "sport = :$port" 2>/dev/null | while read -r _ _ _ local_address _; do printf '%s\n' "$local_address"; done)
        return 1
    fi
    return 2
}

_http_url_host() {
    local host="$1"
    if [[ "$host" == *:* ]]; then
        printf '[%s]\n' "$host"
    else
        printf '%s\n' "$host"
    fi
}

# Returns: 0 = alive and ready; 1 = down (liveness failed); 2 = alive but
# readiness not confirmed. Liveness stays on a tight 3s timeout, while the
# readiness probe gets 10s -- a busy Agent Mail (e.g. SQLite maintenance)
# can legitimately take >3s to answer readiness without being down (#362).
_agent_mail_is_healthy() {
    local url_host=""
    local readiness_body=""
    local readiness_path=""

    [[ -n "$_CURL_BIN" ]] || return 1
    url_host="$(_http_url_host "$ACFS_AGENT_MAIL_HOST")"
    "$_CURL_BIN" -fsS --max-time 3 \
        "http://${url_host}:${ACFS_AGENT_MAIL_PORT}/health/liveness" >/dev/null 2>&1 || return 1

    for readiness_path in /health/readiness /health; do
        readiness_body="$("$_CURL_BIN" -fsS --max-time 10 \
            "http://${url_host}:${ACFS_AGENT_MAIL_PORT}${readiness_path}" 2>/dev/null)" || continue
        if [[ "$readiness_body" =~ \"status\"[[:space:]]*:[[:space:]]*\"ready\"([[:space:]]*[,\}]) ]]; then
            return 0
        fi
    done
    return 2
}

_native_agent_mail_unit_available() {
    [[ "$ACFS_AGENT_MAIL_HOST" == "$ACFS_DEFAULT_AGENT_MAIL_HOST" ]] || return 1
    [[ "$ACFS_AGENT_MAIL_PORT" == "$ACFS_DEFAULT_AGENT_MAIL_PORT" ]] || return 1
    [[ -n "$_SYSTEMCTL_BIN" ]] || return 1
    "$_SYSTEMCTL_BIN" --user show-environment >/dev/null 2>&1 || return 1
    [[ "$("$_SYSTEMCTL_BIN" --user show agent-mail.service -p LoadState --value 2>/dev/null || true)" == "loaded" ]]
}

_native_agent_mail_is_active() {
    _native_agent_mail_unit_available || return 1
    "$_SYSTEMCTL_BIN" --user is-active --quiet agent-mail.service >/dev/null 2>&1
}

_wait_for_agent_mail() {
    local max_wait="${1:-15}"
    local waited=0

    while true; do
        _agent_mail_is_healthy && return 0
        (( waited >= max_wait )) && return 1
        sleep 1
        waited=$((waited + 1))
    done
}

# Static endpoint validation: host/port syntax and the Agent Mail / CM
# collision. Contains no live socket probing, so it is safe to run as a
# preflight while the services are still up (#382).
_validate_endpoint_config() {
    local rc=0
    local p
    local h

    for h in "ACFS_AGENT_MAIL_HOST:$ACFS_AGENT_MAIL_HOST" "ACFS_CM_HOST:$ACFS_CM_HOST"; do
        local host_name="${h%%:*}" host_value="${h#*:}"
        if ! _is_valid_host "$host_value"; then
            _err "$host_name='$host_value' is not a valid host name or IP address."
            rc=1
        fi
    done
    for p in "ACFS_AGENT_MAIL_PORT:$ACFS_AGENT_MAIL_PORT" "ACFS_CM_PORT:$ACFS_CM_PORT"; do
        local name="${p%%:*}" val="${p#*:}"
        if ! _is_valid_port "$val"; then
            _err "$name='$val' is not a valid TCP port (1-65535)."
            rc=1
        fi
    done
    (( rc )) && return 1

    if [[ "$ACFS_AGENT_MAIL_PORT" == "$ACFS_CM_PORT" ]] && \
       _hosts_overlap "$ACFS_AGENT_MAIL_HOST" "$ACFS_CM_HOST"; then
        _err "Agent Mail and CM resolve to the same endpoint ($ACFS_AGENT_MAIL_HOST:$ACFS_AGENT_MAIL_PORT)."
        _err "They cannot share a port. Override with ACFS_AGENT_MAIL_PORT / ACFS_CM_PORT."
        return 1
    fi
    return 0
}

# Validate the resolved HTTP endpoints before we create the tmux session.
# Fails fast (non-zero) with an actionable message on bad/duplicate/occupied
# ports so we never leave a dead pane behind a "started" report.
_validate_http_endpoints() {
    local rc=0

    _validate_endpoint_config || return 1

    # During --dry-run we only validate config, not live socket state.
    $_DRY_RUN && return 0

    # A healthy Agent Mail listener is the expected native-service state and is
    # reused. An unidentified listener on its endpoint remains a hard conflict.
    if _port_is_listening "$ACFS_AGENT_MAIL_HOST" "$ACFS_AGENT_MAIL_PORT" && \
       ! _agent_mail_is_healthy; then
        _err "$ACFS_AGENT_MAIL_HOST:$ACFS_AGENT_MAIL_PORT is occupied by a service that is not a ready Agent Mail server."
        rc=1
    fi
    if _port_is_listening "$ACFS_CM_HOST" "$ACFS_CM_PORT"; then
        _err "$ACFS_CM_HOST:$ACFS_CM_PORT (CM) is already in use. Stop the other process or set ACFS_CM_PORT."
        rc=1
    fi
    return $rc
}

_require_tmux() {
    if [[ -z "$_TMUX_BIN" ]]; then
        _err "tmux is not installed. Install with: sudo apt install tmux"
        return 1
    fi
}

# --- Binary preflight (issue #382) ---
#
# Every command that is about to stop or (re)launch a managed process proves
# the replacement binary can actually run FIRST. The verdict vocabulary matches
# the updater's post-install smoke check (issue #378):
#   healthy      -- a probe exited 0.
#   unsupported  -- the binary executed but rejected every probe as an unknown
#                   argument. Not a broken binary; never a reason to abort.
#   broken       -- the binary timed out, could not be executed (wrong
#                   architecture, missing loader), died by a signal, or failed
#                   every probe without a usage-style rejection.
_SMOKE_VERDICT=""
_SMOKE_DETAIL=""

_smoke_exit_status_is_fatal() {
    local status="${1:-0}"
    [[ "$status" =~ ^[0-9]+$ ]] || return 1
    ((status == 124 || status == 126 || status == 127 || status > 128))
}

_smoke_output_indicates_probe_rejected() {
    local output="${1:-}"
    local lowered=""
    # LC_ALL=C: probe output can contain bytes a UTF-8 tr rejects, and that
    # must never abort the caller under errexit.
    lowered="$(printf '%s' "$output" | LC_ALL=C tr '[:upper:]' '[:lower:]' 2>/dev/null || true)"
    case "$lowered" in
        *"usage:"*|*"usage :"*|*"unknown flag"*|*"unknown option"*|*"unknown command"*|\
        *"unknown argument"*|*"unknown subcommand"*|*"unexpected argument"*|\
        *"unrecognized argument"*|*"unrecognized option"*|*"unrecognised option"*|\
        *"no such option"*|*"no such command"*|*"invalid option"*|*"invalid flag"*|\
        *"illegal option"*|*"not a valid"*|*"try '"*"--help'"*|*"try \`"*"--help'"*)
            return 0 ;;
    esac
    return 1
}

_run_smoke_probe() {
    local binary="${1:-}"
    shift
    local timeout_bin=""

    timeout_bin="$(_system_binary_path timeout 2>/dev/null || true)"
    if [[ -n "$timeout_bin" ]]; then
        "$timeout_bin" --kill-after=5s "${ACFS_SVC_SMOKE_TIMEOUT:-15}" \
            "$binary" "$@" </dev/null 2>&1
    else
        "$binary" "$@" </dev/null 2>&1
    fi
}

# Leaves the verdict in $_SMOKE_VERDICT and the human-readable reason in
# $_SMOKE_DETAIL (globals, so callers must not run this in a subshell).
# Returns 0 only for a healthy binary.
_binary_smoke_verdict() {
    local binary="${1:-}"
    local probe="" output="" status=0
    local all_rejected=true
    local -a attempts=()

    _SMOKE_VERDICT="broken"
    _SMOKE_DETAIL=""
    if [[ -z "$binary" || ! -f "$binary" || ! -x "$binary" ]]; then
        _SMOKE_DETAIL="binary missing or not executable"
        return 1
    fi

    for probe in "--version" "--help" "version"; do
        if output="$(_run_smoke_probe "$binary" "$probe")"; then
            status=0
        else
            status=$?
        fi
        output="${output:0:4096}"
        if ((status == 0)); then
            _SMOKE_VERDICT="healthy"
            _SMOKE_DETAIL="'$binary $probe' exited 0"
            return 0
        fi
        attempts+=("'$probe' exit $status")
        if _smoke_exit_status_is_fatal "$status"; then
            case "$status" in
                124) _SMOKE_DETAIL="'$binary $probe' timed out after ${ACFS_SVC_SMOKE_TIMEOUT:-15}s" ;;
                126) _SMOKE_DETAIL="'$binary' exists but cannot be executed (wrong architecture, missing loader, or not executable)" ;;
                127) _SMOKE_DETAIL="'$binary' could not be started (missing interpreter or shared library)" ;;
                *)   _SMOKE_DETAIL="'$binary $probe' was killed by a signal (exit $status)" ;;
            esac
            return 1
        fi
        _smoke_output_indicates_probe_rejected "$output" || all_rejected=false
    done

    local summary=""
    summary="$(printf '%s; ' "${attempts[@]}")"
    summary="${summary%; }"
    if [[ "$all_rejected" == "true" ]]; then
        _SMOKE_VERDICT="unsupported"
        _SMOKE_DETAIL="'$binary' executed but rejected every probe as an unknown argument ($summary)"
    else
        _SMOKE_VERDICT="broken"
        _SMOKE_DETAIL="'$binary' failed every probe without a usage-style rejection ($summary)"
    fi
    return 1
}

_service_binary_var() {
    case "${1:-}" in
        agent-mail) printf '%s\n' "$_AM_BIN" ;;
        cm)         printf '%s\n' "$_CM_BIN" ;;
        cass)       printf '%s\n' "$_CASS_BIN" ;;
        *)          return 1 ;;
    esac
}

_service_binary_name() {
    case "${1:-}" in
        agent-mail) printf '%s\n' "am" ;;
        cm)         printf '%s\n' "cm" ;;
        cass)       printf '%s\n' "cass" ;;
        *)          return 1 ;;
    esac
}

# Set by a full restart when Agent Mail is running in our own tmux session:
# that process is about to be stopped, so the `am` binary IS required for the
# restart even though the endpoint is healthy right now.
_PREFLIGHT_AGENT_MAIL_WILL_STOP=false

# Does this service need its own binary launched by us? Agent Mail does not
# when it is already healthy or owned by the native user unit.
_service_needs_own_binary() {
    local service="${1:-}"
    [[ "$service" == "agent-mail" ]] || return 0
    $_PREFLIGHT_AGENT_MAIL_WILL_STOP && return 0
    _agent_mail_is_healthy && return 1
    _native_agent_mail_unit_available && return 1
    return 0
}

# Validate one service's launch binary. Returns 1 only when the binary is
# missing or provably broken; an unsupported probe is reported and accepted.
_preflight_service_binary() {
    local service="${1:-}"
    local binary="" name="" verdict=""

    _service_needs_own_binary "$service" || return 0
    name="$(_service_binary_name "$service")" || return 1
    binary="$(_service_binary_var "$service")" || return 1

    if [[ -z "$binary" ]]; then
        if [[ "$service" == "agent-mail" ]]; then
            _err "Missing binary: am (needed for the Agent Mail fallback)"
        else
            _err "Missing binary: $name (needed for $service)"
        fi
        _err "Looked on PATH and in: $(_user_install_dirs | tr '\n' ' ')"
        return 1
    fi

    _binary_smoke_verdict "$binary" || true
    verdict="$_SMOKE_VERDICT"
    case "$verdict" in
        healthy) return 0 ;;
        unsupported)
            _warn "$name: ${_SMOKE_DETAIL}; treating it as runnable."
            return 0
            ;;
        *)
            _err "$name is not runnable: ${_SMOKE_DETAIL}"
            return 1
            ;;
    esac
}

# Preflight everything needed to launch the given services (default: all).
# Performs no live-state changes and probes no listening sockets, so callers
# can run it while the services are still up.
_preflight_services() {
    local -a targets=()
    local service=""
    local rc=0

    (($#)) && targets=("$@")
    ((${#targets[@]})) || targets=("${ACFS_SERVICE_NAMES[@]}")

    for service in "${targets[@]}"; do
        _preflight_service_binary "$service" || rc=1
    done

    if [[ -z "$_CURL_BIN" ]]; then
        _err "Missing system binary: curl (needed for health checks)"
        rc=1
    fi

    _validate_endpoint_config || rc=1
    return $rc
}

_get_pane_ids() {
    "$_TMUX_BIN" list-panes -t "$ACFS_SVC_SESSION:services" -F '#{pane_id}' 2>/dev/null
}

_pane_id_for_service() {
    local target="$1"
    local pane_id=""
    local service_name=""

    while IFS='|' read -r pane_id service_name; do
        if [[ "$service_name" == "$target" ]]; then
            printf '%s\n' "$pane_id"
            return 0
        fi
    done < <("$_TMUX_BIN" list-panes -t "$ACFS_SVC_SESSION:services" \
        -F '#{pane_id}|#{@acfs_service}' 2>/dev/null)
    return 1
}

_pane_service_is_running() {
    local target="$1"
    local pane_id=""
    local pane_state=""
    local pane_dead=""
    local pane_command=""

    pane_id="$(_pane_id_for_service "$target" 2>/dev/null || true)"
    [[ -n "$pane_id" ]] || return 1
    pane_state="$("$_TMUX_BIN" display-message -t "$pane_id" -p \
        '#{pane_dead}|#{pane_current_command}' 2>/dev/null || true)"
    pane_dead="${pane_state%%|*}"
    pane_command="${pane_state#*|}"
    [[ "$pane_dead" != "1" && -n "$pane_command" ]] || return 1
    case "$pane_command" in
        bash|dash|fish|sh|zsh) return 1 ;;
    esac
    return 0
}

_tag_and_start_pane() {
    local pane_id="$1"
    local service_name="$2"
    local command_string=""

    command_string="$(_service_cmd "$service_name")" || return 1
    "$_TMUX_BIN" set-option -p -t "$pane_id" @acfs_service "$service_name" || return 1
    "$_TMUX_BIN" select-pane -t "$pane_id" -T "$service_name" || return 1
    "$_TMUX_BIN" send-keys -t "$pane_id" "$command_string" Enter
}

_wait_for_tmux_services() {
    local max_wait="${1:-15}"
    local waited=0

    while true; do
        if _pane_service_is_running cm && \
           _port_is_listening "$ACFS_CM_HOST" "$ACFS_CM_PORT" && \
           _pane_service_is_running cass; then
            return 0
        fi
        (( waited >= max_wait )) && return 1
        sleep 1
        waited=$((waited + 1))
    done
}

# Readiness for exactly one service, so a targeted repair or restart does not
# wait on (or fail because of) a service the operator did not touch.
_wait_for_service_ready() {
    local service="$1"
    local max_wait="${2:-15}"
    local waited=0

    if [[ "$service" == "agent-mail" ]]; then
        _wait_for_agent_mail "$max_wait"
        return $?
    fi

    while true; do
        if _pane_service_is_running "$service"; then
            if [[ "$service" != "cm" ]] || _port_is_listening "$ACFS_CM_HOST" "$ACFS_CM_PORT"; then
                return 0
            fi
        fi
        (( waited >= max_wait )) && return 1
        sleep 1
        waited=$((waited + 1))
    done
}

# --- Running-binary drift detection (issue #381) ---
#
# A tool update replaces the file on disk; the running service keeps executing
# the old (now deleted) inode until it is restarted. `cass --version` then
# reports the new release while the watcher still runs the old code. These
# helpers compare what the SERVICE actually executes against the installed
# binary ACFS resolves -- never against whatever the caller's PATH happens to
# find, because on a normal host those can legitimately differ.

_proc_fs_available() {
    [[ -d /proc/self && -r /proc/self/exe ]]
}

# Resolve /proc/<pid>/exe into the globals _EXE_PATH and _EXE_DELETED
# (globals, not stdout: a command substitution would discard the deleted flag).
# Returns 1 when the link cannot be read.
_EXE_PATH=""
_EXE_DELETED=false
_proc_exe_path() {
    local pid="$1"
    local link=""

    _EXE_PATH=""
    _EXE_DELETED=false
    link="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
    [[ -n "$link" ]] || return 1
    if [[ "$link" == *" (deleted)" ]]; then
        _EXE_DELETED=true
        link="${link% (deleted)}"
    fi
    _EXE_PATH="$link"
    return 0
}

# Device:inode identity of a path, following symlinks. Empty when unknown.
_file_identity() {
    local path="$1"
    local stat_bin=""

    stat_bin="$(_system_binary_path stat 2>/dev/null || true)"
    [[ -n "$stat_bin" && -e "$path" ]] || return 1
    "$stat_bin" -Lc '%d:%i' "$path" 2>/dev/null || return 1
}

_file_sha256() {
    local path="$1"
    local bin=""
    local out=""

    bin="$(_system_binary_path sha256sum 2>/dev/null || true)"
    if [[ -n "$bin" ]]; then
        out="$("$bin" "$path" 2>/dev/null || true)"
    else
        bin="$(_system_binary_path shasum 2>/dev/null || true)"
        [[ -n "$bin" ]] || return 1
        out="$("$bin" -a 256 "$path" 2>/dev/null || true)"
    fi
    [[ -n "$out" ]] || return 1
    printf '%s\n' "${out%% *}"
}

_short_sha() {
    local path="$1"
    local sha=""

    sha="$(_file_sha256 "$path" 2>/dev/null || true)"
    [[ -n "$sha" ]] || { printf '%s\n' "unknown"; return 0; }
    printf '%s\n' "${sha:0:12}"
}

# Direct children of a pid, from procfs. Falls back to scanning /proc when the
# kernel does not expose the children file.
_child_pids() {
    local pid="$1"
    local children=""
    local stat_line=""
    local candidate=""
    local rest=""
    local ppid=""

    children="$(cat "/proc/$pid/task/$pid/children" 2>/dev/null || true)"
    if [[ -n "$children" ]]; then
        local child=""
        for child in $children; do
            printf '%s\n' "$child"
        done
        return 0
    fi

    for candidate in /proc/[0-9]*; do
        [[ -r "$candidate/stat" ]] || continue
        stat_line="$(cat "$candidate/stat" 2>/dev/null || true)"
        [[ -n "$stat_line" ]] || continue
        # Skip "pid (comm) " -- comm can contain spaces and parentheses.
        rest="${stat_line##*) }"
        # rest is now "state ppid ..."
        ppid="$(printf '%s\n' "$rest" | while read -r _state parent _; do printf '%s\n' "$parent"; break; done)"
        [[ "$ppid" == "$pid" ]] && printf '%s\n' "${candidate##*/}"
    done
    return 0
}

# Find the pid under $1 whose executable basename is $2 (depth-limited).
_descendant_pid_for_binary() {
    local root_pid="$1"
    local want="$2"
    local -a queue=("$root_pid")
    local -a next=()
    local depth=0
    local pid="" exe="" child=""

    while ((${#queue[@]} && depth < 4)); do
        next=()
        for pid in "${queue[@]}"; do
            exe=""
            _proc_exe_path "$pid" 2>/dev/null && exe="$_EXE_PATH"
            if [[ -n "$exe" && "${exe##*/}" == "$want" ]]; then
                printf '%s\n' "$pid"
                return 0
            fi
            while IFS= read -r child; do
                [[ -n "$child" ]] && next+=("$child")
            done < <(_child_pids "$pid")
        done
        queue=("${next[@]+"${next[@]}"}")
        depth=$((depth + 1))
    done
    return 1
}

# Pid of the live process for one managed service, or nothing.
_service_process_pid() {
    local service="$1"
    local name="" pane_id="" pane_pid="" main_pid=""

    name="$(_service_binary_name "$service")" || return 1

    if [[ "$service" == "agent-mail" ]] && _native_agent_mail_is_active; then
        main_pid="$("$_SYSTEMCTL_BIN" --user show agent-mail.service -p MainPID --value 2>/dev/null || true)"
        if [[ "$main_pid" =~ ^[0-9]+$ ]] && (( main_pid > 0 )); then
            printf '%s\n' "$main_pid"
            return 0
        fi
        return 1
    fi

    _session_exists || return 1
    pane_id="$(_pane_id_for_service "$service" 2>/dev/null || true)"
    [[ -n "$pane_id" ]] || return 1
    pane_pid="$("$_TMUX_BIN" display-message -t "$pane_id" -p '#{pane_pid}' 2>/dev/null || true)"
    [[ "$pane_pid" =~ ^[0-9]+$ ]] || return 1
    _descendant_pid_for_binary "$pane_pid" "$name"
}

# Emits "<service>|<state>|<detail>" for one service.
#   ok           running the installed binary
#   stale        running a replaced/deleted/different executable
#   not-running  no live process
#   unknown      could not compare (no procfs, unreadable link, no installed
#                binary resolved)
_service_binary_drift() {
    local service="$1"
    local pid="" exe="" installed="" running_id="" installed_id=""
    local deleted=false

    # procfs first: without it we cannot even identify the service process, so
    # "no live process" would be a lie rather than an observation.
    if ! _proc_fs_available; then
        printf '%s|%s|%s\n' "$service" "unknown" "no procfs on this platform"
        return 0
    fi

    installed="$(_service_binary_var "$service" 2>/dev/null || true)"
    pid="$(_service_process_pid "$service" 2>/dev/null || true)"

    if [[ -z "$pid" ]]; then
        printf '%s|%s|%s\n' "$service" "not-running" "no live process"
        return 0
    fi
    if [[ -z "$installed" ]]; then
        printf '%s|%s|%s\n' "$service" "unknown" "no installed binary resolved for $service"
        return 0
    fi

    if ! _proc_exe_path "$pid" 2>/dev/null; then
        printf '%s|%s|%s\n' "$service" "unknown" "cannot read /proc/$pid/exe"
        return 0
    fi
    exe="$_EXE_PATH"
    deleted=$_EXE_DELETED

    if $deleted; then
        printf '%s|%s|%s\n' "$service" "stale" \
            "pid $pid runs a deleted executable ($exe); installed: $installed (sha256 $(_short_sha "$installed"))"
        return 0
    fi

    running_id="$(_file_identity "/proc/$pid/exe" 2>/dev/null || true)"
    installed_id="$(_file_identity "$installed" 2>/dev/null || true)"
    if [[ -z "$running_id" || -z "$installed_id" ]]; then
        printf '%s|%s|%s\n' "$service" "unknown" "cannot compare $exe with $installed"
        return 0
    fi
    if [[ "$running_id" == "$installed_id" ]]; then
        printf '%s|%s|%s\n' "$service" "ok" "pid $pid runs $installed"
        return 0
    fi

    printf '%s|%s|%s\n' "$service" "stale" \
        "pid $pid runs $exe (sha256 $(_short_sha "/proc/$pid/exe")); installed: $installed (sha256 $(_short_sha "$installed"))"
}

# Warn loudly about every managed service running something other than the
# installed binary. Returns 0 when everything is current, 1 when any service
# is running a stale executable.
_report_binary_drift() {
    local service="" line="" state="" detail=""
    local drift_found=false

    for service in "${ACFS_SERVICE_NAMES[@]}"; do
        line="$(_service_binary_drift "$service")"
        state="${line#*|}"
        detail="${state#*|}"
        state="${state%%|*}"
        [[ "$state" == "stale" ]] || continue
        if ! $drift_found; then
            printf '\n' >&2
            _warn "Running-binary drift: an updated tool is installed but the live service still runs the old executable."
            drift_found=true
        fi
        _warn "  $service: $detail"
        _warn "  Restart just this service: acfs services restart $service"
    done

    if $drift_found; then
        _warn "A restart interrupts that service; Agent Mail stays up unless you restart it too."
        _warn "Pick a quiescent moment: in-flight agent work in that service is cut off."
        printf '\n' >&2
        return 1
    fi
    return 0
}

cmd_drift() {
    local robot=false
    local service="" line="" state=""
    local rc=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --robot|--porcelain) robot=true; shift ;;
            "") shift ;;
            *)
                _err "Unknown option for 'drift': '$1'"
                _info "Usage: acfs services drift [--robot]"
                return 1
                ;;
        esac
    done

    _initialize_bins
    _require_tmux

    if $robot; then
        for service in "${ACFS_SERVICE_NAMES[@]}"; do
            line="$(_service_binary_drift "$service")"
            printf '%s\n' "$line"
            state="${line#*|}"
            [[ "${state%%|*}" == "stale" ]] && rc=1
        done
        return $rc
    fi

    if _report_binary_drift; then
        _ok "Every running ACFS-managed service is executing its installed binary."
    else
        rc=1
    fi
    return $rc
}

# --- Commands ---

cmd_start() {
    _initialize_bins
    _require_tmux

    if _session_exists; then
        local repair_rc=0 status_rc=0
        _warn "Session '$ACFS_SVC_SESSION' already exists; repairing any service that is not running."
        cmd_repair || repair_rc=$?
        cmd_status || status_rc=$?
        (( status_rc != 0 )) && return "$status_rc"
        return "$repair_rc"
    fi

    # Pre-flight: every binary we are about to launch must exist and run
    # (issue #382). Endpoint syntax is validated here too.
    if ! _preflight_services; then
        _err "Cannot start services -- fix the problems above first."
        return 1
    fi

    # Fail fast on bad/duplicate/occupied HTTP ports before touching tmux.
    _validate_http_endpoints || return 1

    if $_DRY_RUN; then
        _info "[dry-run] Would reuse or start Agent Mail at $ACFS_AGENT_MAIL_HOST:$ACFS_AGENT_MAIL_PORT."
        _info "[dry-run] Would create tmux session '$ACFS_SVC_SESSION' for:"
        _info "  cm:   $(_service_cmd cm)"
        _info "  cass: $(_service_cmd cass)"
        return 0
    fi

    local agent_mail_in_tmux=false
    if _agent_mail_is_healthy; then
        _info "Reusing healthy Agent Mail at $ACFS_AGENT_MAIL_HOST:$ACFS_AGENT_MAIL_PORT."
    elif _native_agent_mail_unit_available; then
        _info "Starting native Agent Mail user service..."
        if ! "$_SYSTEMCTL_BIN" --user start agent-mail.service >/dev/null 2>&1 || \
           ! _wait_for_agent_mail 15; then
            _err "Agent Mail user service did not become ready."
            _err "Inspect it with: systemctl --user status agent-mail.service"
            return 1
        fi
    else
        agent_mail_in_tmux=true
    fi

    local -a tmux_services=("cm" "cass")
    if $agent_mail_in_tmux; then
        tmux_services=("agent-mail" "${tmux_services[@]}")
    fi

    _info "Starting ACFS services in tmux session '$ACFS_SVC_SESSION'..."

    # Create session with a single window named "services"
    if ! "$_TMUX_BIN" new-session -d -s "$ACFS_SVC_SESSION" -n "services"; then
        _err "Failed to create tmux session '$ACFS_SVC_SESSION'."
        return 1
    fi

    local first_pane_id
    first_pane_id="$("$_TMUX_BIN" list-panes -t "$ACFS_SVC_SESSION:services" -F '#{pane_id}' 2>/dev/null | while IFS= read -r pane; do printf '%s\n' "$pane"; break; done)"
    if [[ -z "$first_pane_id" ]] || ! _tag_and_start_pane "$first_pane_id" "${tmux_services[0]}"; then
        _err "Failed to launch ${tmux_services[0]} in tmux."
        return 1
    fi

    # Create additional panes for remaining services
    local i
    for ((i = 1; i < ${#tmux_services[@]}; i++)); do
        local new_pane_id
        new_pane_id="$("$_TMUX_BIN" split-window -t "$ACFS_SVC_SESSION:services" -v -P -F '#{pane_id}')" || {
            _err "Failed to create tmux pane for ${tmux_services[$i]}."
            return 1
        }
        if ! _tag_and_start_pane "$new_pane_id" "${tmux_services[$i]}"; then
            _err "Failed to launch ${tmux_services[$i]} in tmux."
            return 1
        fi
    done

    # Even out the pane layout
    "$_TMUX_BIN" select-layout -t "$ACFS_SVC_SESSION:services" even-vertical >/dev/null

    # Select the first pane
    "$_TMUX_BIN" select-pane -t "$first_pane_id"

    if ! _wait_for_agent_mail 15 || ! _wait_for_tmux_services 15; then
        _err "One or more services failed readiness checks; the tmux session was left running for diagnosis."
        cmd_status || true
        return 1
    fi

    _ok "All services are ready."
    _info "Attach with: tmux attach -t $ACFS_SVC_SESSION"
    _info "View logs:   acfs services logs [agent-mail|cm|cass]"
}

# Recreate or relaunch the pane for one service inside an existing session.
# Only ever touches a pane that is demonstrably not running the service: a
# pane whose process is alive is left strictly alone, because this session can
# be sharing a tmux server with long-lived agent panes (#383).
_repair_service_pane() {
    local service="$1"
    local pane_id="" pane_dead=""

    _preflight_service_binary "$service" || return 1

    pane_id="$(_pane_id_for_service "$service" 2>/dev/null || true)"

    if [[ -z "$pane_id" ]]; then
        # No tagged pane at all: add one to the services window, creating the
        # window if the session lost it. Untagged panes are never reused.
        if "$_TMUX_BIN" list-panes -t "$ACFS_SVC_SESSION:services" >/dev/null 2>&1; then
            pane_id="$("$_TMUX_BIN" split-window -t "$ACFS_SVC_SESSION:services" -v -P -F '#{pane_id}' 2>/dev/null || true)"
        else
            pane_id="$("$_TMUX_BIN" new-window -t "$ACFS_SVC_SESSION" -n "services" -P -F '#{pane_id}' 2>/dev/null || true)"
        fi
        if [[ -z "$pane_id" ]]; then
            _err "Failed to create a tmux pane for $service."
            return 1
        fi
    else
        pane_dead="$("$_TMUX_BIN" display-message -t "$pane_id" -p '#{pane_dead}' 2>/dev/null || true)"
        if [[ "$pane_dead" == "1" ]]; then
            # respawn-pane without -k refuses to touch a pane that is not dead,
            # which is exactly the guarantee we want here.
            if ! "$_TMUX_BIN" respawn-pane -t "$pane_id" >/dev/null 2>&1; then
                _err "Failed to respawn the dead $service pane ($pane_id)."
                return 1
            fi
            # Let the fresh shell reach a prompt before typing the command.
            sleep 1
        fi
    fi

    if ! _tag_and_start_pane "$pane_id" "$service"; then
        _err "Failed to relaunch $service in tmux."
        return 1
    fi
    _info "Relaunched $service in pane $pane_id."
    return 0
}

# Converge an existing service group toward ready: start Agent Mail if it is
# down, and relaunch only the services that are not running (#383). With no
# arguments every managed service is considered; names narrow it down.
cmd_repair() {
    local -a targets=()
    local -a repaired=()
    local service=""
    local rc=0

    (($#)) && targets=("$@")

    _initialize_bins
    _require_tmux

    ((${#targets[@]})) || targets=("${ACFS_SERVICE_NAMES[@]}")
    for service in "${targets[@]}"; do  # never empty after the default above
        if ! _service_desc "$service" >/dev/null 2>&1; then
            _err "Unknown service: '$service'"
            _info "Available services: ${ACFS_SERVICE_NAMES[*]}"
            return 1
        fi
    done

    if ! _session_exists; then
        _err "Session '$ACFS_SVC_SESSION' is not running. Start with: acfs services start"
        return 1
    fi

    if $_DRY_RUN; then
        _info "[dry-run] Would relaunch these services if they are not running: ${targets[*]}"
        return 0
    fi

    _validate_endpoint_config || return 1

    for service in "${targets[@]}"; do
        if [[ "$service" == "agent-mail" ]]; then
            _agent_mail_is_healthy && continue
            if _native_agent_mail_unit_available; then
                repaired+=("agent-mail")
                _info "Starting native Agent Mail user service..."
                if ! "$_SYSTEMCTL_BIN" --user start agent-mail.service >/dev/null 2>&1; then
                    _err "Agent Mail user service failed to start."
                    _err "Inspect it with: systemctl --user status agent-mail.service"
                    rc=1
                fi
                continue
            fi
            # No native unit: Agent Mail is one of our tmux panes.
        fi

        _pane_service_is_running "$service" && continue
        repaired+=("$service")
        _repair_service_pane "$service" || rc=1
    done

    if ((${#repaired[@]} == 0)); then
        _info "Every ACFS-managed service is already running; nothing to repair."
        return $rc
    fi

    "$_TMUX_BIN" select-layout -t "$ACFS_SVC_SESSION:services" even-vertical >/dev/null 2>&1 || true

    for service in "${repaired[@]}"; do
        if ! _wait_for_service_ready "$service" 15; then
            _err "$service did not pass its readiness check after being relaunched; it was left running for diagnosis."
            rc=1
        fi
    done
    return $rc
}

cmd_stop() {
    _initialize_bins
    _require_tmux

    if $_DRY_RUN; then
        _info "[dry-run] Would stop the native Agent Mail service when active."
        _info "[dry-run] Would stop tmux session '$ACFS_SVC_SESSION' when present."
        return 0
    fi

    local stopped_any=false
    local rc=0
    _info "Stopping ACFS services..."

    if _native_agent_mail_is_active; then
        stopped_any=true
        if ! "$_SYSTEMCTL_BIN" --user stop agent-mail.service >/dev/null 2>&1; then
            _err "Failed to stop native Agent Mail service."
            rc=1
        fi
    fi

    if _session_exists; then
        stopped_any=true
        local pane_id
        while IFS= read -r pane_id; do
            [[ -n "$pane_id" ]] || continue
            "$_TMUX_BIN" send-keys -t "$pane_id" C-c 2>/dev/null || true
        done < <(_get_pane_ids)
        sleep 2
        if ! "$_TMUX_BIN" kill-session -t "$ACFS_SVC_SESSION" 2>/dev/null; then
            _err "Failed to stop tmux session '$ACFS_SVC_SESSION'."
            rc=1
        fi
    fi

    if ! $stopped_any; then
        _info "No ACFS-managed services were running."
    elif (( rc == 0 )); then
        _ok "All ACFS-managed services stopped."
    fi

    if _agent_mail_is_healthy; then
        _warn "Agent Mail is still healthy but is not owned by the ACFS native service or tmux session; it was left untouched."
    fi
    return $rc
}

cmd_status() {
    _initialize_bins
    _require_tmux

    local rc=0
    local owner="external"
    if _native_agent_mail_is_active; then
        owner="native"
    elif _session_exists && _pane_service_is_running agent-mail; then
        owner="tmux"
    fi

    local am_health_rc=0
    _agent_mail_is_healthy || am_health_rc=$?
    if (( am_health_rc == 0 )); then
        printf '  %-12s  %sready%s    %s  (%s)\n' "agent-mail" "$_C_GREEN" "$_C_RESET" \
            "$ACFS_AGENT_MAIL_HOST:$ACFS_AGENT_MAIL_PORT" "$owner"
    elif (( am_health_rc == 2 )); then
        printf '  %-12s  %salive, readiness slow%s  %s  (%s)\n' "agent-mail" "$_C_YELLOW" "$_C_RESET" \
            "$ACFS_AGENT_MAIL_HOST:$ACFS_AGENT_MAIL_PORT" "$owner"
        rc=1
    else
        printf '  %-12s  %snot ready%s  %s\n' "agent-mail" "$_C_RED" "$_C_RESET" \
            "$ACFS_AGENT_MAIL_HOST:$ACFS_AGENT_MAIL_PORT"
        rc=1
    fi

    if _session_exists && _pane_service_is_running cm && \
       _port_is_listening "$ACFS_CM_HOST" "$ACFS_CM_PORT"; then
        printf '  %-12s  %sready%s    %s  (tmux)\n' "cm" "$_C_GREEN" "$_C_RESET" \
            "$ACFS_CM_HOST:$ACFS_CM_PORT"
    else
        printf '  %-12s  %snot ready%s  %s\n' "cm" "$_C_RED" "$_C_RESET" \
            "$ACFS_CM_HOST:$ACFS_CM_PORT"
        rc=1
    fi

    if _session_exists && _pane_service_is_running cass; then
        printf '  %-12s  %srunning%s          (tmux)\n' "cass" "$_C_GREEN" "$_C_RESET"
    else
        printf '  %-12s  %snot running%s\n' "cass" "$_C_RED" "$_C_RESET"
        rc=1
    fi

    printf '\n'
    if _session_exists; then
        _info "Attach: tmux attach -t $ACFS_SVC_SESSION"
    fi
    _info "Logs:   acfs services logs [agent-mail|cm|cass]"
    if (( rc != 0 )); then
        # Lifecycle contract (#196, documented per #360): "not running" can be
        # intentional. Say exactly what owns what and what the fix is.
        printf '\n'
        _info "Lifecycle: only agent-mail persists across reboots (native user service)."
        _info "cm and cass run in the '$ACFS_SVC_SESSION' tmux session, which does not survive"
        _info "a reboot and does not restart crashed processes -- run 'acfs services start'"
        _info "to bring them back. Leaving cm/cass off is fine if you only use 'cm context'/'cm reflect'"
        _info "or are diagnosing indexing/resource problems."
    fi

    # A service can be perfectly "ready" and still be executing the binary an
    # update replaced days ago (#381). Say so; do not let readiness read green
    # while the shipped fix is not actually live.
    _report_binary_drift || true
    return $rc
}

# Stop one tmux-owned service without disturbing the rest of the session:
# interrupt the process, wait for it to leave, and leave the pane in place.
_stop_pane_service() {
    local service="$1"
    local pane_id=""
    local waited=0

    pane_id="$(_pane_id_for_service "$service" 2>/dev/null || true)"
    [[ -n "$pane_id" ]] || return 0

    "$_TMUX_BIN" send-keys -t "$pane_id" C-c 2>/dev/null || true
    while _pane_service_is_running "$service"; do
        (( waited >= 10 )) && { _err "$service did not stop after 10s; leaving it alone."; return 1; }
        sleep 1
        waited=$((waited + 1))
    done
    return 0
}

# Restart exactly one service. Agent Mail goes through its native unit when it
# owns the process; everything else is restarted in place in its tmux pane, so
# restarting cass never interrupts Agent Mail or CM.
_restart_one_service() {
    local service="$1"

    if [[ "$service" == "agent-mail" ]] && _native_agent_mail_is_active; then
        _info "Restarting native Agent Mail user service..."
        if ! "$_SYSTEMCTL_BIN" --user restart agent-mail.service >/dev/null 2>&1 || \
           ! _wait_for_agent_mail 15; then
            _err "Agent Mail user service did not become ready after restart."
            _err "Inspect it with: systemctl --user status agent-mail.service"
            return 1
        fi
        return 0
    fi

    if ! _session_exists; then
        _err "Session '$ACFS_SVC_SESSION' is not running. Start with: acfs services start"
        return 1
    fi

    if [[ "$service" == "agent-mail" ]] && [[ -z "$(_pane_id_for_service agent-mail 2>/dev/null || true)" ]]; then
        _err "Agent Mail is not owned by ACFS here (no native unit, no managed pane); refusing to restart it."
        _err "Whatever serves $ACFS_AGENT_MAIL_HOST:$ACFS_AGENT_MAIL_PORT was started outside ACFS -- restart it there."
        return 1
    fi

    _stop_pane_service "$service" || return 1
    _repair_service_pane "$service" || return 1
    if ! _wait_for_service_ready "$service" 15; then
        _err "$service did not pass its readiness check after the restart."
        return 1
    fi
    return 0
}

cmd_restart() {
    local -a targets=()
    local service=""
    local rc=0
    local stop_rc=0

    (($#)) && targets=("$@")

    _initialize_bins
    _require_tmux

    for service in "${targets[@]+"${targets[@]}"}"; do
        if ! _service_desc "$service" >/dev/null 2>&1; then
            _err "Unknown service: '$service'"
            _info "Available services: ${ACFS_SERVICE_NAMES[*]}"
            return 1
        fi
    done

    # A full restart tears down the tmux session, so an Agent Mail fallback
    # pane counts as "will be stopped" and its binary must preflight too.
    if ((${#targets[@]} == 0)) && ! _native_agent_mail_is_active && \
       _session_exists && _pane_service_is_running agent-mail; then
        _PREFLIGHT_AGENT_MAIL_WILL_STOP=true
    fi

    # Preflight BEFORE anything is stopped (issue #382): a restart that cannot
    # resolve or run the replacement binaries must leave healthy services up.
    if ! _preflight_services "${targets[@]+"${targets[@]}"}"; then
        _err "Preflight failed: no service was stopped and nothing changed."
        _err "Fix the problems above, then re-run: acfs services restart${targets[*]:+ ${targets[*]}}"
        return 1
    fi

    if ((${#targets[@]})); then
        if $_DRY_RUN; then
            _info "[dry-run] Would restart: ${targets[*]}"
            return 0
        fi
        _info "Restarting ACFS services: ${targets[*]}"
        for service in "${targets[@]+"${targets[@]}"}"; do
            _restart_one_service "$service" || rc=1
        done
        cmd_status || true
        return $rc
    fi

    _info "Restarting ACFS services..."
    cmd_stop || stop_rc=$?
    if (( stop_rc != 0 )); then
        _err "Stop reported errors; not starting on top of an unknown state."
        _err "Inspect with 'acfs services status', then run 'acfs services start'."
        return "$stop_rc"
    fi
    if ! cmd_start; then
        rc=$?
        _err "Services were stopped but did not come back up (start exit $rc)."
        _err "Recover with: acfs services start   (after fixing the errors above)"
        return "$rc"
    fi
}

cmd_logs() {
    local target="${1:-}"

    _initialize_bins
    _require_tmux

    # If no target specified, just attach to the session
    if [[ -z "$target" ]]; then
        if ! _session_exists; then
            _err "Session '$ACFS_SVC_SESSION' is not running. Start with: acfs services start"
            return 1
        fi
        if $_DRY_RUN; then
            _info "[dry-run] Would attach to tmux session '$ACFS_SVC_SESSION'"
            return 0
        fi
        exec "$_TMUX_BIN" attach -t "$ACFS_SVC_SESSION"
    fi

    case "$target" in
        agent-mail|cm|cass) ;;
        *)
        _err "Unknown service: '$target'"
        _info "Available services: ${ACFS_SERVICE_NAMES[*]}"
        return 1
        ;;
    esac

    local pane_id
    pane_id="$(_pane_id_for_service "$target" 2>/dev/null || true)"
    if [[ -z "$pane_id" ]]; then
        if [[ "$target" == "agent-mail" ]] && _native_agent_mail_unit_available; then
            if $_DRY_RUN; then
                _info "[dry-run] Would follow journalctl logs for agent-mail.service"
                return 0
            fi
            if [[ -z "$_JOURNALCTL_BIN" ]]; then
                _err "journalctl is unavailable; run: am service logs"
                return 1
            fi
            exec "$_JOURNALCTL_BIN" --user -u agent-mail.service -f
        fi
        _err "Pane for '$target' not found. Start with: acfs services start"
        return 1
    fi

    if $_DRY_RUN; then
        _info "[dry-run] Would attach to the $target pane in session '$ACFS_SVC_SESSION'"
        return 0
    fi

    exec "$_TMUX_BIN" select-pane -t "$pane_id" \; attach -t "$ACFS_SVC_SESSION"
}

# --- Usage ---

usage() {
    cat <<'EOF'
ACFS Services — Unified background daemon management

Usage: acfs services <command> [options]

Commands:
  start               Start all ACFS background services. If the session
                      already exists, relaunch only the services that are
                      not running; healthy panes are never touched.
  stop                Stop all services (graceful shutdown)
  status              Show which services are running
  restart [service…]  Restart everything, or only the named services.
                      Binaries are validated before anything is stopped.
  repair              Relaunch only the services that are not running
  drift [--robot]     Report managed services still executing a binary that
                      has since been replaced on disk
  logs [service]      Attach to tmux session (optionally select a pane)

Services managed:
  agent-mail      native service or am fallback               [default 127.0.0.1:8765]
  cm              cm serve (CASS Memory server)               [default 127.0.0.1:8766]
  cass            cass index --watch (CASS indexer, watch mode)

Agent Mail and CM both default to port 8765 upstream; ACFS assigns them
distinct ports so they don't collide. Override the defaults with:
  ACFS_AGENT_MAIL_HOST   (default 127.0.0.1)
  ACFS_AGENT_MAIL_PORT   (default 8765)
  ACFS_CM_HOST           (default 127.0.0.1)
  ACFS_CM_PORT           (default 8766)

Options:
  --dry-run       Show what would be done without doing it
  --help, -h      Show this help message

Examples:
  acfs services start              # Start all daemons (or repair a partial session)
  acfs services status             # Quick health check
  acfs services logs agent-mail    # View Agent Mail logs
  acfs services restart            # Restart everything
  acfs services restart cass       # Restart only CASS; Agent Mail stays up
  acfs services drift              # Are the live services on the installed binaries?
  acfs services stop               # Graceful shutdown

CM and CASS run in a dedicated tmux session named 'acfs-svc'. Agent Mail
reuses the native ACFS user service when it is installed and healthy; otherwise
it gets its own tmux pane. Start and status return nonzero unless every service
passes its runtime readiness check.
EOF
}

# --- Main ---

main() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    # Parse global flags
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) _DRY_RUN=true; shift ;;
            *)         args+=("$1"); shift ;;
        esac
    done

    # Also check if --dry-run was the first arg (before cmd)
    if [[ "$cmd" == "--dry-run" ]]; then
        _DRY_RUN=true
        cmd="${args[0]:-}"
        args=("${args[@]:1}")
    fi

    case "$cmd" in
        start)   cmd_start ;;
        stop)    cmd_stop ;;
        status)  cmd_status ;;
        restart) cmd_restart "${args[@]+"${args[@]}"}" ;;
        repair)  cmd_repair "${args[@]+"${args[@]}"}" ;;
        drift)   cmd_drift "${args[@]+"${args[@]}"}" ;;
        logs|log|attach)
            cmd_logs "${args[0]:-}" ;;
        help|-h|--help|"")
            usage ;;
        *)
            _err "Unknown command: '$cmd'"
            usage >&2
            return 1
            ;;
    esac
}

# Allow sourcing for testing without executing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] || [[ "${1:-}" == "--source-test" ]]; then
    if [[ "${1:-}" == "--source-test" ]]; then
        # Source-test mode: just validate syntax and function definitions
        shift
        if [[ $# -gt 0 ]]; then
            "$@"
        fi
    else
        main "$@"
    fi
fi
