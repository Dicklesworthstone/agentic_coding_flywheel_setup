#!/usr/bin/env bash
# ============================================================
# ACFS Services — Unified background daemon management
# Manages Agent Mail, CM serve, and CASS indexer via tmux
#
# Usage:
#   acfs services start       Start all services in a tmux session
#   acfs services stop        Stop the tmux session (kills all)
#   acfs services status      Show which services are running
#   acfs services restart     Stop then start
#   acfs services logs [svc]  Attach to a service pane for logs
#
# Services (in pane order):
#   agent-mail: am serve-http --no-tui
#   cm:         cm serve
#   cass:       cass index --watch
#
# The tmux session is named "acfs-svc" to avoid conflicts.
# Pane numbering adapts to the user's tmux pane-base-index.
# ============================================================

set -euo pipefail

# --- Constants ---
readonly ACFS_SVC_SESSION="acfs-svc"
readonly ACFS_SVC_VERSION="1.0.0"

# Service definitions: name|command|description
# Order matters: index 0 = first pane, 1 = second pane, etc.
readonly -a ACFS_SERVICES=(
    "agent-mail|am serve-http --no-tui|Agent Mail HTTP server"
    "cm|cm serve|CASS Memory server"
    "cass|cass index --watch|CASS indexer (watch mode)"
)

# --- State ---
_DRY_RUN=false

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

_svc_name()  { echo "${1%%|*}"; }
_svc_cmd()   { local rest="${1#*|}"; echo "${rest%%|*}"; }
_svc_desc()  { echo "${1##*|}"; }

_info()  { printf '%s[acfs-services]%s %s\n' "$_C_CYAN" "$_C_RESET" "$*"; }
_ok()    { printf '%s[acfs-services]%s %s%s%s\n' "$_C_CYAN" "$_C_RESET" "$_C_GREEN" "$*" "$_C_RESET"; }
_warn()  { printf '%s[acfs-services]%s %s%s%s\n' "$_C_CYAN" "$_C_RESET" "$_C_YELLOW" "$*" "$_C_RESET" >&2; }
_err()   { printf '%s[acfs-services]%s %s%s%s\n' "$_C_CYAN" "$_C_RESET" "$_C_RED" "$*" "$_C_RESET" >&2; }

_session_exists() {
    tmux has-session -t "$ACFS_SVC_SESSION" 2>/dev/null
}

_require_tmux() {
    if ! command -v tmux &>/dev/null; then
        _err "tmux is not installed. Install with: sudo apt install tmux"
        return 1
    fi
}

# Get an ordered array of pane_ids for the session.
# This adapts to any pane-base-index setting.
_get_pane_ids() {
    tmux list-panes -t "$ACFS_SVC_SESSION:services" -F '#{pane_id}' 2>/dev/null
}

# Get the Nth pane_id (0-indexed logical position).
_nth_pane_id() {
    local n="$1"
    _get_pane_ids | sed -n "$((n + 1))p"
}

# Get the PID of the shell running in a pane (by pane_id, e.g. %0).
_pane_pid_by_id() {
    local pane_id="$1"
    tmux display-message -t "$pane_id" -p '#{pane_pid}' 2>/dev/null
}

# --- Commands ---

cmd_start() {
    _require_tmux

    if _session_exists; then
        _warn "Session '$ACFS_SVC_SESSION' already exists. Services are running."
        _info "Use 'acfs services status' to check, or 'acfs services restart' to restart."
        return 0
    fi

    # Pre-flight: check all binaries exist
    local missing=0
    for svc in "${ACFS_SERVICES[@]}"; do
        local cmd_str
        cmd_str="$(_svc_cmd "$svc")"
        local bin="${cmd_str%% *}"
        if ! command -v "$bin" &>/dev/null; then
            _err "Missing binary: $bin (needed for $(_svc_name "$svc"))"
            missing=1
        fi
    done
    if (( missing )); then
        _err "Cannot start services -- install missing binaries first."
        return 1
    fi

    if $_DRY_RUN; then
        _info "[dry-run] Would create tmux session '$ACFS_SVC_SESSION' with ${#ACFS_SERVICES[@]} panes:"
        for i in "${!ACFS_SERVICES[@]}"; do
            local svc="${ACFS_SERVICES[$i]}"
            _info "  Pane $i ($(_svc_name "$svc")): $(_svc_cmd "$svc")"
        done
        return 0
    fi

    _info "Starting ACFS services in tmux session '$ACFS_SVC_SESSION'..."

    # Create session with a single window named "services"
    tmux new-session -d -s "$ACFS_SVC_SESSION" -n "services"

    # The first pane already exists. Send service 0's command.
    local first_pane_id
    first_pane_id="$(_nth_pane_id 0)"
    tmux send-keys -t "$first_pane_id" "$(_svc_cmd "${ACFS_SERVICES[0]}")" Enter

    # Create additional panes for remaining services
    local i
    for i in $(seq 1 $(( ${#ACFS_SERVICES[@]} - 1 ))); do
        local svc="${ACFS_SERVICES[$i]}"
        # split-window -P -F prints the new pane's ID so we can target it explicitly.
        # Without -t on send-keys, tmux may target the wrong session if another is active.
        local new_pane_id
        new_pane_id="$(tmux split-window -t "$ACFS_SVC_SESSION:services" -v -P -F '#{pane_id}')"
        tmux send-keys -t "$new_pane_id" "$(_svc_cmd "$svc")" Enter
    done

    # Even out the pane layout
    tmux select-layout -t "$ACFS_SVC_SESSION:services" even-vertical

    # Select the first pane
    first_pane_id="$(_nth_pane_id 0)"
    tmux select-pane -t "$first_pane_id"

    _ok "All services started."
    printf '\n'
    for i in "${!ACFS_SERVICES[@]}"; do
        local svc="${ACFS_SERVICES[$i]}"
        printf '  %sPANE %d%s  %-12s  %s\n' "$_C_BOLD" "$i" "$_C_RESET" "$(_svc_name "$svc")" "$(_svc_desc "$svc")"
    done
    printf '\n'
    _info "Attach with: tmux attach -t $ACFS_SVC_SESSION"
    _info "View logs:   acfs services logs [agent-mail|cm|cass]"
}

cmd_stop() {
    _require_tmux

    if ! _session_exists; then
        _info "Session '$ACFS_SVC_SESSION' is not running. Nothing to stop."
        return 0
    fi

    if $_DRY_RUN; then
        _info "[dry-run] Would stop tmux session '$ACFS_SVC_SESSION'"
        return 0
    fi

    _info "Stopping ACFS services..."

    # Graceful shutdown: send C-c to each pane to interrupt the running service
    local pane_id
    while IFS= read -r pane_id; do
        [[ -n "$pane_id" ]] || continue
        tmux send-keys -t "$pane_id" C-c 2>/dev/null || true
    done < <(_get_pane_ids)

    # Brief wait for graceful shutdown
    local waited=0
    while (( waited < 3 )); do
        sleep 1
        waited=$((waited + 1))
        # Check if all child processes have exited
        local any_alive=false
        while IFS= read -r pane_id; do
            [[ -n "$pane_id" ]] || continue
            local pid
            pid="$(_pane_pid_by_id "$pane_id")"
            if [[ -n "$pid" ]]; then
                local child_pid
                child_pid="$(pgrep -P "$pid" 2>/dev/null | head -1 || true)"
                if [[ -n "$child_pid" ]]; then
                    any_alive=true
                    break
                fi
            fi
        done < <(_get_pane_ids)
        if ! $any_alive; then
            break
        fi
    done

    # Kill the session
    if _session_exists; then
        tmux kill-session -t "$ACFS_SVC_SESSION" 2>/dev/null || true
    fi

    _ok "All services stopped."
}

cmd_status() {
    _require_tmux

    if ! _session_exists; then
        printf '%sSESSION%s  %s%s%s  (not running)\n' \
            "$_C_BOLD" "$_C_RESET" "$_C_RED" "$ACFS_SVC_SESSION" "$_C_RESET"
        return 1
    fi

    printf '%sSESSION%s  %s%s%s  (running)\n\n' \
        "$_C_BOLD" "$_C_RESET" "$_C_GREEN" "$ACFS_SVC_SESSION" "$_C_RESET"

    local i=0
    for svc in "${ACFS_SERVICES[@]}"; do
        local name desc pane_id pid
        name="$(_svc_name "$svc")"
        desc="$(_svc_desc "$svc")"
        pane_id="$(_nth_pane_id "$i")"

        if [[ -z "$pane_id" ]]; then
            printf '  %sPANE %d%s  %-12s  %s%s%s\n' \
                "$_C_BOLD" "$i" "$_C_RESET" "$name" "$_C_RED" "missing" "$_C_RESET"
            i=$((i + 1))
            continue
        fi

        pid="$(_pane_pid_by_id "$pane_id")"

        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            local child_pid cmd_running
            child_pid="$(pgrep -P "$pid" 2>/dev/null | head -1 || true)"
            if [[ -n "$child_pid" ]]; then
                cmd_running="$(ps -p "$child_pid" -o args= 2>/dev/null || echo "unknown")"
                printf '  %sPANE %d%s  %-12s  %s%s%s  %s\n' \
                    "$_C_BOLD" "$i" "$_C_RESET" "$name" "$_C_GREEN" "running" "$_C_RESET" "$_C_DIM$cmd_running$_C_RESET"
            else
                printf '  %sPANE %d%s  %-12s  %s%s%s  %s\n' \
                    "$_C_BOLD" "$i" "$_C_RESET" "$name" "$_C_YELLOW" "idle" "$_C_RESET" "(shell running, service exited)"
            fi
        else
            printf '  %sPANE %d%s  %-12s  %s%s%s\n' \
                "$_C_BOLD" "$i" "$_C_RESET" "$name" "$_C_RED" "dead" "$_C_RESET"
        fi

        i=$((i + 1))
    done

    printf '\n'
    _info "Attach: tmux attach -t $ACFS_SVC_SESSION"
    _info "Logs:   acfs services logs [agent-mail|cm|cass]"
}

cmd_restart() {
    _info "Restarting ACFS services..."
    cmd_stop
    cmd_start
}

cmd_logs() {
    local target="${1:-}"

    _require_tmux

    if ! _session_exists; then
        _err "Session '$ACFS_SVC_SESSION' is not running. Start with: acfs services start"
        return 1
    fi

    # If no target specified, just attach to the session
    if [[ -z "$target" ]]; then
        if $_DRY_RUN; then
            _info "[dry-run] Would attach to tmux session '$ACFS_SVC_SESSION'"
            return 0
        fi
        exec tmux attach -t "$ACFS_SVC_SESSION"
    fi

    # Find the logical index for the requested service
    local svc_index=-1
    local i=0
    for svc in "${ACFS_SERVICES[@]}"; do
        if [[ "$(_svc_name "$svc")" == "$target" ]]; then
            svc_index=$i
            break
        fi
        i=$((i + 1))
    done

    if (( svc_index < 0 )); then
        _err "Unknown service: '$target'"
        local names=()
        for svc in "${ACFS_SERVICES[@]}"; do
            names+=("$(_svc_name "$svc")")
        done
        _info "Available services: ${names[*]}"
        return 1
    fi

    local pane_id
    pane_id="$(_nth_pane_id "$svc_index")"
    if [[ -z "$pane_id" ]]; then
        _err "Pane for '$target' not found. The session may have fewer panes than expected."
        return 1
    fi

    if $_DRY_RUN; then
        _info "[dry-run] Would attach to pane $svc_index ($target) in session '$ACFS_SVC_SESSION'"
        return 0
    fi

    exec tmux select-pane -t "$pane_id" \; attach -t "$ACFS_SVC_SESSION"
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
  agent-mail      am serve-http (Agent Mail HTTP/MCP server)
  cm              cm serve (CASS Memory server)
  cass            cass index --watch (CASS indexer, watch mode)

Options:
  --dry-run       Show what would be done without doing it
  --help, -h      Show this help message

Examples:
  acfs services start              # Start all daemons
  acfs services status             # Quick health check
  acfs services logs agent-mail    # View Agent Mail logs
  acfs services restart            # Restart everything
  acfs services stop               # Graceful shutdown

The services run in a dedicated tmux session named 'acfs-svc'.
Each service gets its own pane for independent log viewing.
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
