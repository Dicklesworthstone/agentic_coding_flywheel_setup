#!/usr/bin/env bash
# ============================================================
# ACFS Services — Unified background daemon management
# Manages Agent Mail, CM serve, and the CASS indexer. Agent Mail reuses the
# ACFS native user service when available; tmux is the portable fallback and
# owns the CM/CASS processes.
#
# Usage:
#   acfs services start       Start all services
#   acfs services stop        Stop all services
#   acfs services status      Show which services are running
#   acfs services restart     Stop then start
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

_user_binary_path() {
    local name="${1:-}"
    local resolved=""

    [[ "$name" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
    resolved="$(type -P "$name" 2>/dev/null || true)"
    [[ -n "$resolved" && "$resolved" == /* && -x "$resolved" && ! -d "$resolved" ]] || return 1
    printf '%s\n' "$resolved"
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

# Validate the resolved HTTP endpoints before we create the tmux session.
# Fails fast (non-zero) with an actionable message on bad/duplicate/occupied
# ports so we never leave a dead pane behind a "started" report.
_validate_http_endpoints() {
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

# --- Commands ---

cmd_start() {
    _initialize_bins
    _require_tmux

    if _session_exists; then
        _warn "Session '$ACFS_SVC_SESSION' already exists; checking actual service health."
        cmd_status
        return $?
    fi

    # Pre-flight: check all binaries exist
    local missing=0
    if ! _agent_mail_is_healthy && ! _native_agent_mail_unit_available; then
        [[ -n "$_AM_BIN" ]] || { _err "Missing binary: am (needed for the Agent Mail fallback)"; missing=1; }
    fi
    [[ -n "$_CM_BIN" ]] || { _err "Missing binary: cm (needed for cm)"; missing=1; }
    [[ -n "$_CASS_BIN" ]] || { _err "Missing binary: cass (needed for cass)"; missing=1; }
    [[ -n "$_CURL_BIN" ]] || { _err "Missing system binary: curl (needed for health checks)"; missing=1; }
    if (( missing )); then
        _err "Cannot start services -- install missing binaries first."
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
    return $rc
}

cmd_restart() {
    _info "Restarting ACFS services..."
    cmd_stop
    cmd_start
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
  start           Start all ACFS background services
  stop            Stop all services (graceful shutdown)
  status          Show which services are running
  restart         Stop then start all services
  logs [service]  Attach to tmux session (optionally select a pane)

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
  acfs services start              # Start all daemons
  acfs services status             # Quick health check
  acfs services logs agent-mail    # View Agent Mail logs
  acfs services restart            # Restart everything
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
        restart) cmd_restart ;;
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
