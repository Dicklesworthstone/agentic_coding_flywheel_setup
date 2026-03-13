#!/usr/bin/env bash
# ============================================================
# ACFS Dashboard - Static HTML Generation & Serving
#
# Generates a local HTML dashboard using `acfs info --html`
# and optionally serves it via a temporary HTTP server.
#
# Usage:
#   acfs dashboard generate [--force]
#   acfs dashboard serve [--port PORT]
# ============================================================

set -euo pipefail

ACFS_HOME="${ACFS_HOME:-$HOME/.acfs}"

dashboard_usage() {
    echo "Usage: acfs dashboard <command>"
    echo ""
    echo "Commands:"
    echo "  generate [--force]   Generate ~/.acfs/dashboard/index.html"
    echo "  serve [--port PORT] [--host HOST] [--public]  Start a temporary HTTP server for the dashboard"
    echo "  help                 Show this help"
}

find_info_script() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Prefer the repo-local helper when running from a checkout so dashboard
    # generation follows the code under test, not a stale installed copy.
    if [[ -f "$script_dir/info.sh" ]]; then
        echo "$script_dir/info.sh"
        return 0
    fi

    if [[ -f "$ACFS_HOME/scripts/lib/info.sh" ]]; then
        echo "$ACFS_HOME/scripts/lib/info.sh"
        return 0
    fi

    return 1
}

validate_port() {
    local port="${1:-}"
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    (( port >= 1 && port <= 65535 ))
}

dashboard_generate() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                ;;
            --help|-h)
                dashboard_usage
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
        shift
    done

    local dashboard_dir="${ACFS_HOME}/dashboard"
    local html_file="${dashboard_dir}/index.html"
    local timestamp_file="${dashboard_dir}/.last_generated"

    mkdir -p "$dashboard_dir"

    if [[ "$force" != "true" && -f "$html_file" ]]; then
        local last_gen now age
        last_gen="$(cat "$timestamp_file" 2>/dev/null || echo 0)"
        if [[ ! "$last_gen" =~ ^[0-9]+$ ]]; then
            last_gen=0
        fi
        now="$(date +%s)"
        age=$((now - last_gen))

        if [[ $age -ge 0 && $age -lt 3600 ]]; then
            echo "Dashboard is recent ($((age / 60)) minutes old). Use --force to regenerate."
            echo "Dashboard path: $html_file"
            return 0
        fi
    fi

    local info_script
    if ! info_script="$(find_info_script)"; then
        echo "Error: info.sh not found" >&2
        echo "Re-run the ACFS installer to get the latest scripts." >&2
        return 1
    fi

    echo "Generating dashboard..."
    local tmp_file=""
    tmp_file=$(mktemp "${dashboard_dir}/index.html.tmp.XXXXXX") || {
        echo "Error: could not create temporary dashboard file" >&2
        return 1
    }

    cleanup_tmp_file() {
        if [[ -n "$tmp_file" && -e "$tmp_file" ]]; then
            rm -f "$tmp_file"
        fi
    }

    trap cleanup_tmp_file RETURN

    if ! bash "$info_script" --html > "$tmp_file"; then
        echo "Error: dashboard generation failed" >&2
        return 1
    fi

    mv "$tmp_file" "$html_file"
    tmp_file=""
    trap - RETURN
    date +%s > "$timestamp_file"

    echo "Dashboard generated: $html_file"
    echo "Open with: open \"$html_file\" (macOS) or xdg-open \"$html_file\" (Linux)"
}

dashboard_serve() {
    local port=8080
    local host="127.0.0.1"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --port)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --port requires a port number" >&2
                    return 1
                fi
                if ! validate_port "$2"; then
                    echo "Error: port must be an integer between 1 and 65535" >&2
                    return 1
                fi
                port="$2"
                shift
                ;;
            --host)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --host requires a host/address (e.g. 127.0.0.1 or 0.0.0.0)" >&2
                    return 1
                fi
                host="$2"
                shift
                ;;
            --public)
                host="0.0.0.0"
                ;;
            --help|-h)
                echo "Usage: acfs dashboard serve [--port PORT] [--host HOST] [--public]"
                echo ""
                echo "Starts a temporary HTTP server to view the dashboard."
                echo "Default port: 8080"
                echo "Default host: 127.0.0.1 (local only)"
                echo ""
                echo "Notes:"
                echo "  - Local-only is safer on VPS (prevents accidental internet exposure)."
                echo "  - Use --public to bind 0.0.0.0 (all interfaces)."
                return 0
                ;;
            *)
                # Allow port as positional argument
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    if ! validate_port "$1"; then
                        echo "Error: port must be an integer between 1 and 65535" >&2
                        return 1
                    fi
                    port="$1"
                else
                    echo "Unknown option: $1" >&2
                    return 1
                fi
                ;;
        esac
        shift
    done

    if ! validate_port "$port"; then
        echo "Error: port must be an integer between 1 and 65535" >&2
        return 1
    fi

    local dashboard_dir="${ACFS_HOME}/dashboard"
    local html_file="${dashboard_dir}/index.html"

    # Auto-generate dashboard if missing
    if [[ ! -f "$html_file" ]]; then
        echo "Dashboard not found. Generating..."
        dashboard_generate --force
    fi

    # Get IP for display
    local ip
    if command -v hostname &>/dev/null; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}') || ip="<your-server-ip>"
    else
        ip="<your-server-ip>"
    fi
    # Fallback if hostname -I returned empty
    [[ -z "$ip" ]] && ip="<your-server-ip>"

    # Prefer the invoking user for SSH tunnel instructions (handles `sudo acfs ...`).
    # Avoid hard-coding "ubuntu" so TARGET_USER installs aren't confusing.
    local ssh_user=""
    if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        ssh_user="$SUDO_USER"
    else
        ssh_user="$(whoami 2>/dev/null || echo "ubuntu")"
    fi

    # Check if port is in use
    if command -v lsof &>/dev/null && lsof -i :"$port" &>/dev/null; then
        echo "Warning: Port $port appears to be in use." >&2
        echo "Try a different port: acfs dashboard serve --port 8081" >&2
        return 1
    fi

    # Show banner
    if [[ "$host" == "127.0.0.1" || "$host" == "localhost" ]]; then
        cat <<EOF

╭─────────────────────────────────────────────────────────────╮
│  📊 ACFS Dashboard Server                                   │
├─────────────────────────────────────────────────────────────┤
│  Local URL:   http://localhost:${port} (server-side only)      │
│                                                             │
│  Press Ctrl+C to stop                                       │
│                                                             │
│  ⚠️  This is a temporary server.                            │
│  It stops when you close this terminal.                     │
│                                                             │
│  To view from your laptop (recommended):                     │
│    ssh -L ${port}:localhost:${port} ${ssh_user}@${ip}                │
│    then open: http://localhost:${port}                         │
╰─────────────────────────────────────────────────────────────╯

EOF
    else
        cat <<EOF

╭─────────────────────────────────────────────────────────────╮
│  📊 ACFS Dashboard Server                                   │
├─────────────────────────────────────────────────────────────┤
│  Local URL:   http://localhost:${port}                         │
│  Network URL: http://${ip}:${port}
│                                                             │
│  Press Ctrl+C to stop                                       │
│                                                             │
│  ⚠️  This is a temporary server.                            │
│  It stops when you close this terminal.                     │
╰─────────────────────────────────────────────────────────────╯

EOF
    fi

    # Start server
    cd "$dashboard_dir" || {
        echo "Error: Cannot cd to $dashboard_dir" >&2
        return 1
    }

    if command -v python3 &>/dev/null; then
        python3 -m http.server --bind "$host" "$port"
    elif command -v python &>/dev/null; then
        python -m http.server --bind "$host" "$port"
    else
        echo "Error: Python not found. Cannot start HTTP server." >&2
        echo "Install Python or open the dashboard directly: $html_file" >&2
        return 1
    fi
}

dashboard_main() {
    local cmd="${1:-help}"
    shift 1 2>/dev/null || true

    case "$cmd" in
        generate)
            dashboard_generate "$@"
            ;;
        serve)
            dashboard_serve "$@"
            ;;
        help|-h|--help)
            dashboard_usage
            ;;
        *)
            echo "Unknown command: $cmd" >&2
            dashboard_usage >&2
            return 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    dashboard_main "$@"
fi
