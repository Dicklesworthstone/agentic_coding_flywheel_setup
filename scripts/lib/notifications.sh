#!/usr/bin/env bash
# ============================================================
# ACFS CLI - Notification Management Subcommand
#
# Manages ntfy.sh push notifications for ACFS events.
# Usage: acfs notifications <enable|disable|test|status|topic|set-server>
#
# Config stored at: ~/.config/acfs/config.yaml
# Related bead: bd-2igt6
# ============================================================

set -euo pipefail

# ============================================================
# Constants
# ============================================================
ACFS_CONFIG_DIR="${HOME}/.config/acfs"
ACFS_CONFIG_FILE="${ACFS_CONFIG_DIR}/config.yaml"
ACFS_NTFY_SERVER_DEFAULT="https://ntfy.sh"

# ============================================================
# Helpers
# ============================================================

# Read a key from config.yaml (simple YAML parser)
_notif_config_read() {
    local key="$1"
    if [[ ! -f "$ACFS_CONFIG_FILE" ]]; then
        return 0
    fi
    local val
    val=$(grep -E "^\s*${key}\s*:" "$ACFS_CONFIG_FILE" 2>/dev/null | head -1 | \
          sed -E "s/^\s*${key}\s*:\s*//; s/^[\"']//; s/[\"']\s*$//" | \
          sed 's/^[[:space:]]*//; s/[[:space:]]*$//') || true
    printf '%s' "$val"
}

# Write a key to config.yaml (upsert)
_notif_config_write() {
    local key="$1"
    local value="$2"

    # Ensure config dir exists
    mkdir -p "$ACFS_CONFIG_DIR"

    if [[ ! -f "$ACFS_CONFIG_FILE" ]]; then
        # Create new config file
        printf '%s: %s\n' "$key" "$value" > "$ACFS_CONFIG_FILE"
        return 0
    fi

    # Check if key already exists
    if grep -qE "^\s*${key}\s*:" "$ACFS_CONFIG_FILE" 2>/dev/null; then
        # Update existing key in-place
        sed -i -E "s|^\s*${key}\s*:.*|${key}: ${value}|" "$ACFS_CONFIG_FILE"
    else
        # Append new key
        printf '%s: %s\n' "$key" "$value" >> "$ACFS_CONFIG_FILE"
    fi
}

# Generate a random topic string: acfs-HOSTNAME-RANDOM8
_notif_generate_topic() {
    local hostname
    hostname=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "host")
    # Sanitize hostname: lowercase, alphanumeric + hyphens only
    hostname=$(printf '%s' "$hostname" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
    # Generate 8 random hex chars
    local random_part
    if [[ -r /dev/urandom ]]; then
        random_part=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
    else
        random_part=$(printf '%04x%04x' $((RANDOM % 65536)) $((RANDOM % 65536)))
    fi
    printf 'acfs-%s-%s' "$hostname" "$random_part"
}

# ============================================================
# Subcommands
# ============================================================

cmd_enable() {
    local topic
    topic=$(_notif_config_read "ntfy_topic")

    # Generate new topic if none exists
    if [[ -z "$topic" ]]; then
        topic=$(_notif_generate_topic)
    fi

    local server
    server=$(_notif_config_read "ntfy_server")
    if [[ -z "$server" ]]; then
        server="$ACFS_NTFY_SERVER_DEFAULT"
    fi

    # Write config
    _notif_config_write "ntfy_enabled" "true"
    _notif_config_write "ntfy_topic" "$topic"
    _notif_config_write "ntfy_server" "$server"

    echo "Notifications enabled!"
    echo ""
    echo "Subscribe on your phone or browser:"
    echo "  ${server}/${topic}"
    echo ""
    echo "Mobile apps:"
    echo "  Android: https://play.google.com/store/apps/details?id=io.heckel.ntfy"
    echo "  iOS:     https://apps.apple.com/us/app/ntfy/id1625396347"
    echo ""
    echo "Or open the URL above in any browser."
    echo ""
    echo "Test it with: acfs notifications test"
}

cmd_disable() {
    _notif_config_write "ntfy_enabled" "false"
    echo "Notifications disabled."
}

cmd_test() {
    local enabled
    enabled=$(_notif_config_read "ntfy_enabled")
    if [[ "$enabled" != "true" ]]; then
        echo "Notifications are not enabled. Run 'acfs notifications enable' first."
        return 1
    fi

    local topic server
    topic=$(_notif_config_read "ntfy_topic")
    server=$(_notif_config_read "ntfy_server")
    server="${server:-$ACFS_NTFY_SERVER_DEFAULT}"

    if [[ -z "$topic" ]]; then
        echo "Error: No topic configured. Run 'acfs notifications enable' first."
        return 1
    fi

    echo "Sending test notification to ${server}/${topic} ..."

    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' \
        --max-time 10 \
        -H "Title: ACFS Test Notification" \
        -H "Priority: default" \
        -H "Tags: white_check_mark,acfs" \
        -d "If you see this, ACFS notifications are working! ($(hostname 2>/dev/null || echo 'unknown'))" \
        "${server}/${topic}" 2>/dev/null) || http_code="000"

    if [[ "$http_code" =~ ^2 ]]; then
        echo "Test notification sent successfully (HTTP ${http_code})."
        echo "Check your subscribed device."
    else
        echo "Failed to send test notification (HTTP ${http_code})."
        echo "Check your network connection and server URL."
        return 1
    fi
}

cmd_status() {
    local enabled topic server priority

    if [[ ! -f "$ACFS_CONFIG_FILE" ]]; then
        echo "Notifications: not configured"
        echo "Config file:   ${ACFS_CONFIG_FILE} (not found)"
        echo ""
        echo "Run 'acfs notifications enable' to set up."
        return 0
    fi

    enabled=$(_notif_config_read "ntfy_enabled")
    topic=$(_notif_config_read "ntfy_topic")
    server=$(_notif_config_read "ntfy_server")
    server="${server:-$ACFS_NTFY_SERVER_DEFAULT}"
    priority=$(_notif_config_read "ntfy_priority")
    priority="${priority:-default}"

    echo "Notifications: ${enabled:-not set}"
    echo "Topic:         ${topic:-not set}"
    echo "Server:        ${server}"
    echo "Priority:      ${priority}"
    echo "Config file:   ${ACFS_CONFIG_FILE}"

    if [[ "$enabled" == "true" ]] && [[ -n "$topic" ]]; then
        echo ""
        echo "Subscribe URL: ${server}/${topic}"
    fi
}

cmd_topic() {
    local enabled topic server

    enabled=$(_notif_config_read "ntfy_enabled")
    topic=$(_notif_config_read "ntfy_topic")
    server=$(_notif_config_read "ntfy_server")
    server="${server:-$ACFS_NTFY_SERVER_DEFAULT}"

    if [[ -z "$topic" ]]; then
        echo "No topic configured. Run 'acfs notifications enable' first."
        return 1
    fi

    echo "${server}/${topic}"
}

cmd_set_server() {
    local new_server="${1:-}"

    if [[ -z "$new_server" ]]; then
        echo "Usage: acfs notifications set-server <url>"
        echo "Example: acfs notifications set-server https://ntfy.example.com"
        return 1
    fi

    # Basic URL validation
    if [[ ! "$new_server" =~ ^https?:// ]]; then
        echo "Error: Server URL must start with http:// or https://"
        return 1
    fi

    # Strip trailing slash
    new_server="${new_server%/}"

    _notif_config_write "ntfy_server" "$new_server"
    echo "ntfy server set to: ${new_server}"

    local topic
    topic=$(_notif_config_read "ntfy_topic")
    if [[ -n "$topic" ]]; then
        echo "Subscribe URL: ${new_server}/${topic}"
    fi
}

cmd_set_priority() {
    local new_priority="${1:-}"

    if [[ -z "$new_priority" ]]; then
        echo "Usage: acfs notifications set-priority <priority>"
        echo "Options: min, low, default, high, urgent (or 1-5)"
        return 1
    fi

    # Validate priority
    case "$new_priority" in
        min|low|default|high|urgent|1|2|3|4|5)
            ;;
        *)
            echo "Error: Invalid priority '$new_priority'"
            echo "Options: min, low, default, high, urgent (or 1-5)"
            return 1
            ;;
    esac

    _notif_config_write "ntfy_priority" "$new_priority"
    echo "Default notification priority set to: ${new_priority}"
}

cmd_set_topic() {
    local new_topic="${1:-}"

    if [[ -z "$new_topic" ]]; then
        echo "Usage: acfs notifications set-topic <topic>"
        echo "Example: acfs notifications set-topic acfs-myserver-secret123"
        return 1
    fi

    _notif_config_write "ntfy_topic" "$new_topic"
    echo "ntfy topic set to: ${new_topic}"

    local server
    server=$(_notif_config_read "ntfy_server")
    server="${server:-$ACFS_NTFY_SERVER_DEFAULT}"
    echo "Subscribe URL: ${server}/${new_topic}"
}

cmd_send() {
    local title="${1:-}"
    local body="${2:-}"
    local priority="${3:-}"

    if [[ -z "$title" ]]; then
        echo "Usage: acfs notifications send <title> [body] [priority]"
        echo ""
        echo "Send an ad-hoc notification via ntfy.sh."
        echo ""
        echo "Examples:"
        echo "  acfs notifications send 'Build done' 'All tests passed'"
        echo "  acfs notifications send 'Deploy failed' 'See logs' high"
        return 1
    fi

    local enabled
    enabled=$(_notif_config_read "ntfy_enabled")
    if [[ "$enabled" != "true" ]]; then
        echo "Notifications are not enabled. Run 'acfs notifications enable' first."
        return 1
    fi

    local topic server
    topic=$(_notif_config_read "ntfy_topic")
    server=$(_notif_config_read "ntfy_server")
    server="${server:-$ACFS_NTFY_SERVER_DEFAULT}"

    if [[ -z "$topic" ]]; then
        echo "Error: No topic configured. Run 'acfs notifications enable' first."
        return 1
    fi

    # Resolve priority (arg > config > default)
    if [[ -z "$priority" ]]; then
        priority=$(_notif_config_read "ntfy_priority")
    fi
    priority="${priority:-default}"

    echo "Sending notification to ${server}/${topic} ..."

    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' \
        --max-time 10 \
        -H "Title: ${title}" \
        -H "Priority: ${priority}" \
        -H "Tags: computer,acfs" \
        -d "${body:-$title}" \
        "${server}/${topic}" 2>/dev/null) || http_code="000"

    if [[ "$http_code" =~ ^2 ]]; then
        echo "Notification sent (HTTP ${http_code})."
    else
        echo "Failed to send notification (HTTP ${http_code})."
        return 1
    fi
}

# ============================================================
# Usage / Help
# ============================================================

show_help() {
    echo "ACFS Notifications - Push notifications via ntfy.sh"
    echo ""
    echo "Usage: acfs notifications <command>"
    echo ""
    echo "Setup:"
    echo "  enable              Enable notifications (generates random topic)"
    echo "  disable             Disable notifications"
    echo "  status              Show current notification config"
    echo ""
    echo "Configuration:"
    echo "  set-server URL      Use a custom ntfy server"
    echo "  set-topic TOPIC     Set a custom topic name"
    echo "  set-priority PRIO   Set default priority (min/low/default/high/urgent)"
    echo "  topic               Print the subscribe URL"
    echo ""
    echo "Actions:"
    echo "  test                Send a test notification"
    echo "  send TITLE [BODY] [PRIORITY]   Send a custom notification"
    echo ""
    echo "Config: ${ACFS_CONFIG_FILE}"
    echo ""
    echo "How it works:"
    echo "  1. Run 'acfs notifications enable'"
    echo "  2. Subscribe to the topic URL on your phone (ntfy app) or browser"
    echo "  3. ACFS sends notifications for:"
    echo "     - Install success/failure"
    echo "     - Agent task completion/failure"
    echo "     - Human attention needed (urgent)"
    echo "     - Nightly update results"
    echo ""
    echo "Scripting (source scripts/lib/notify.sh):"
    echo "  acfs_notify <title> [body] [priority] [tags]"
    echo "  acfs_notify_task_complete <task> [agent] [detail]"
    echo "  acfs_notify_task_failed <task> [error] [agent]"
    echo "  acfs_notify_human_needed <reason> [context] [agent]"
    echo "  acfs_notify_debounced <key> <title> [body] [priority] [tags]"
    echo ""
    echo "Environment overrides:"
    echo "  ACFS_NTFY_ENABLED=true|false"
    echo "  ACFS_NTFY_TOPIC=<topic>"
    echo "  ACFS_NTFY_SERVER=<url>"
    echo "  ACFS_NTFY_PRIORITY=<priority>"
    echo "  ACFS_NTFY_DEBOUNCE_SECONDS=<seconds>  (default: 30)"
}

# ============================================================
# Dispatcher
# ============================================================

main() {
    local subcmd="${1:-help}"
    shift 1 2>/dev/null || true

    case "$subcmd" in
        enable)
            cmd_enable "$@"
            ;;
        disable)
            cmd_disable "$@"
            ;;
        test)
            cmd_test "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        topic)
            cmd_topic "$@"
            ;;
        set-server)
            cmd_set_server "$@"
            ;;
        set-priority)
            cmd_set_priority "$@"
            ;;
        set-topic)
            cmd_set_topic "$@"
            ;;
        send)
            cmd_send "$@"
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            echo "Unknown command: $subcmd"
            echo "Run 'acfs notifications help' for available commands."
            return 1
            ;;
    esac
}

main "$@"
