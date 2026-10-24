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

_ACFS_NOTIFICATIONS_SOURCED=false
_ACFS_NOTIFICATIONS_HAD_ERREXIT=false
_ACFS_NOTIFICATIONS_HAD_NOUNSET=false
_ACFS_NOTIFICATIONS_HAD_PIPEFAIL=false

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    _ACFS_NOTIFICATIONS_SOURCED=true
    case "$-" in
        *e*) _ACFS_NOTIFICATIONS_HAD_ERREXIT=true ;;
    esac
    case "$-" in
        *u*) _ACFS_NOTIFICATIONS_HAD_NOUNSET=true ;;
    esac
    if [[ -o pipefail ]]; then
        _ACFS_NOTIFICATIONS_HAD_PIPEFAIL=true
    fi
fi

set -euo pipefail

# ============================================================
# Constants
# ============================================================
# Resolve notification config against the intended runtime user. When
# TARGET_USER is explicit, passwd/NSS owns the home directory and stale
# TARGET_HOME/HOME values must not redirect config writes.
notifications_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

notifications_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

notifications_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(notifications_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(notifications_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

notifications_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(notifications_system_binary_path getent 2>/dev/null || true)"
    if [[ -z "$user" ]]; then
        if [[ -n "$getent_bin" ]]; then
            while IFS= read -r passwd_line; do
                printf '%s\n' "$passwd_line"
                printed_any=true
            done < <("$getent_bin" passwd 2>/dev/null || true)
            if [[ "$printed_any" == true ]]; then
                return 0
            fi
        fi

        [[ -r /etc/passwd ]] || return 1
        while IFS= read -r passwd_line; do
            printf '%s\n' "$passwd_line"
        done < /etc/passwd
        return 0
    fi

    if [[ -n "$getent_bin" ]]; then
        passwd_entry="$("$getent_bin" passwd "$user" 2>/dev/null || true)"
    fi

    if [[ -z "$passwd_entry" ]] && [[ -r /etc/passwd ]]; then
        while IFS= read -r passwd_line; do
            [[ "${passwd_line%%:*}" == "$user" ]] || continue
            passwd_entry="$passwd_line"
            break
        done < /etc/passwd
    fi

    [[ -n "$passwd_entry" ]] || return 1
    printf '%s\n' "$passwd_entry"
}

notifications_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(notifications_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

notifications_resolve_current_home() {
    local current_user=""
    local home_candidate=""
    local passwd_entry=""
    local passwd_home=""

    home_candidate="$(notifications_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    current_user="$(notifications_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(notifications_getent_passwd_entry "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(notifications_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

notifications_runtime_home() {
    local current_user=""
    local explicit_target_home=""
    local passwd_entry=""
    local passwd_home=""
    local target_user="${TARGET_USER:-}"

    explicit_target_home="$(notifications_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"

    if [[ -n "$target_user" ]]; then
        [[ "$target_user" =~ ^[a-z_][a-z0-9._-]*$ ]] || return 1

        if [[ "$target_user" == "root" ]]; then
            printf '/root\n'
            return 0
        fi

        passwd_entry="$(notifications_getent_passwd_entry "$target_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(notifications_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi

        current_user="$(notifications_resolve_current_user 2>/dev/null || true)"
        if [[ -z "$current_user" ]] || [[ "$current_user" != "$target_user" ]]; then
            return 1
        fi
    fi

    if [[ -n "$explicit_target_home" ]]; then
        printf '%s\n' "$explicit_target_home"
        return 0
    fi

    notifications_resolve_current_home
}

_ACFS_NOTIFICATIONS_RUNTIME_HOME="$(notifications_runtime_home 2>/dev/null || true)"

if [[ -n "$_ACFS_NOTIFICATIONS_RUNTIME_HOME" ]]; then
    ACFS_CONFIG_DIR="${_ACFS_NOTIFICATIONS_RUNTIME_HOME}/.config/acfs"
else
    ACFS_CONFIG_DIR=""
fi
ACFS_CONFIG_FILE="${ACFS_CONFIG_DIR:+${ACFS_CONFIG_DIR}/config.yaml}"
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

    if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
        echo "Error: Invalid notification config key." >&2
        return 1
    fi

    if [[ "$value" =~ [[:cntrl:]] ]]; then
        echo "Error: Notification config values must not contain control characters." >&2
        return 1
    fi

    if [[ -z "$ACFS_CONFIG_DIR" || -z "$ACFS_CONFIG_FILE" ]]; then
        echo "Error: Unable to resolve ACFS notification config directory." >&2
        return 1
    fi

    # Ensure config dir exists
    if ! mkdir -p "$ACFS_CONFIG_DIR"; then
        echo "Error: Unable to create notification config directory: $ACFS_CONFIG_DIR" >&2
        return 1
    fi

    if [[ ! -f "$ACFS_CONFIG_FILE" ]]; then
        # Create new config file
        if ! printf '%s: %s\n' "$key" "$value" > "$ACFS_CONFIG_FILE"; then
            echo "Error: Unable to write notification config file: $ACFS_CONFIG_FILE" >&2
            return 1
        fi
        return 0
    fi

    # Check if key already exists
    if grep -qE "^\s*${key}\s*:" "$ACFS_CONFIG_FILE" 2>/dev/null; then
        # Update existing key in-place (avoid sed delimiter and backreference bugs)
        local temp_file
        if ! temp_file=$(mktemp "${TMPDIR:-/tmp}/acfs_config.XXXXXX" 2>/dev/null); then
            echo "Error: Unable to create temporary notification config file." >&2
            return 1
        fi
        if ! while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*: ]]; then
                printf '%s: %s\n' "$key" "$value"
            else
                printf '%s\n' "$line"
            fi
        done < "$ACFS_CONFIG_FILE" > "$temp_file"; then
            echo "Error: Unable to update notification config file: $ACFS_CONFIG_FILE" >&2
            return 1
        fi
        if ! mv "$temp_file" "$ACFS_CONFIG_FILE"; then
            echo "Error: Unable to replace notification config file: $ACFS_CONFIG_FILE" >&2
            return 1
        fi
    else
        # Append new key
        if ! printf '%s: %s\n' "$key" "$value" >> "$ACFS_CONFIG_FILE"; then
            echo "Error: Unable to append notification config file: $ACFS_CONFIG_FILE" >&2
            return 1
        fi
    fi
}

notifications_header_value() {
    local value="${1:-}"
    local fallback="${2:-}"

    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="$(printf '%s' "$value" | tr -d '\000-\010\013\014\016-\037\177')" || value=""

    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

notifications_priority_is_valid() {
    case "${1:-}" in
        min|low|default|high|urgent|1|2|3|4|5)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

notifications_topic_is_valid() {
    local topic="${1:-}"

    [[ -n "$topic" ]] || return 1
    [[ ${#topic} -le 128 ]] || return 1
    [[ "$topic" =~ ^[A-Za-z0-9._-]+$ ]]
}

notifications_server_is_valid() {
    local server="${1:-}"

    [[ -n "$server" ]] || return 1
    [[ ! "$server" =~ [[:cntrl:][:space:]] ]] || return 1
    [[ "$server" != *"?"* ]] || return 1
    [[ "$server" != *"#"* ]] || return 1
    [[ "$server" =~ ^https?://[^/]+(/[^[:space:]]*)?$ ]]
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

    if ! notifications_topic_is_valid "$topic"; then
        echo "Error: Configured ntfy topic contains unsupported characters."
        return 1
    fi
    if ! notifications_server_is_valid "$server"; then
        echo "Error: Configured ntfy server URL is invalid."
        return 1
    fi

    # Write config
    _notif_config_write "ntfy_topic" "$topic" || return 1
    _notif_config_write "ntfy_server" "$server" || return 1
    _notif_config_write "ntfy_enabled" "true" || return 1

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
    _notif_config_write "ntfy_enabled" "false" || return 1
    echo "Notifications disabled."
}

cmd_test() {
    local curl_bin=""
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
    if ! notifications_topic_is_valid "$topic"; then
        echo "Error: Configured ntfy topic contains unsupported characters."
        return 1
    fi
    if ! notifications_server_is_valid "$server"; then
        echo "Error: Configured ntfy server URL is invalid."
        return 1
    fi

    curl_bin="$(notifications_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        echo "Error: curl not available."
        return 1
    fi

    echo "Sending test notification to ${server}/${topic} ..."

    local http_code
    http_code=$("$curl_bin" -s -o /dev/null -w '%{http_code}' \
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

    if [[ -z "$ACFS_CONFIG_FILE" ]]; then
        echo "Notifications: unavailable"
        echo "Config file:   unable to resolve runtime home"
        return 1
    fi

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
    if ! notifications_topic_is_valid "$topic"; then
        echo "Error: Configured ntfy topic contains unsupported characters."
        return 1
    fi
    if ! notifications_server_is_valid "$server"; then
        echo "Error: Configured ntfy server URL is invalid."
        return 1
    fi

    echo "${server}/${topic}"
}

cmd_set_server() {
    local new_server="${1:-}"

    if [[ -z "$new_server" ]]; then
        notifications_subcommand_usage set-server
        return 1
    fi

    # Strip trailing slash
    new_server="${new_server%/}"

    if ! notifications_server_is_valid "$new_server"; then
        echo "Error: Server URL must be an http(s) base URL without whitespace, query, or fragment"
        return 1
    fi

    _notif_config_write "ntfy_server" "$new_server" || return 1
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
        notifications_subcommand_usage set-priority
        return 1
    fi

    if ! notifications_priority_is_valid "$new_priority"; then
        echo "Error: Invalid priority '$(notifications_header_value "$new_priority" "<empty>")'"
        echo "Options: min, low, default, high, urgent (or 1-5)"
        return 1
    fi

    _notif_config_write "ntfy_priority" "$new_priority" || return 1
    echo "Default notification priority set to: ${new_priority}"
}

cmd_set_topic() {
    local new_topic="${1:-}"

    if [[ -z "$new_topic" ]]; then
        notifications_subcommand_usage set-topic
        return 1
    fi

    if ! notifications_topic_is_valid "$new_topic"; then
        echo "Error: Topic must be 1-128 characters and contain only letters, numbers, dot, underscore, or hyphen"
        return 1
    fi

    _notif_config_write "ntfy_topic" "$new_topic" || return 1
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
    local curl_bin=""

    if [[ -z "$title" ]]; then
        notifications_subcommand_usage send
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
    if ! notifications_topic_is_valid "$topic"; then
        echo "Error: Configured ntfy topic contains unsupported characters."
        return 1
    fi
    if ! notifications_server_is_valid "$server"; then
        echo "Error: Configured ntfy server URL is invalid."
        return 1
    fi

    # Resolve priority (arg > config > default)
    if [[ -z "$priority" ]]; then
        priority=$(_notif_config_read "ntfy_priority")
    fi
    priority="${priority:-default}"
    title="$(notifications_header_value "$title" "")"

    if [[ -z "$title" ]]; then
        echo "Error: Notification title contains no printable characters."
        return 1
    fi

    if ! notifications_priority_is_valid "$priority"; then
        echo "Error: Invalid priority '$(notifications_header_value "$priority" "<empty>")'"
        echo "Options: min, low, default, high, urgent (or 1-5)"
        return 1
    fi

    curl_bin="$(notifications_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        echo "Error: curl not available."
        return 1
    fi

    echo "Sending notification to ${server}/${topic} ..."

    local http_code
    http_code=$("$curl_bin" -s -o /dev/null -w '%{http_code}' \
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
    echo "Run 'acfs notifications <command> --help' for command usage."
    echo ""
    echo "Config: ${ACFS_CONFIG_FILE:-<unresolved>}"
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

# Usage for one subcommand. Returns 1 for an unknown subcommand.
notifications_subcommand_usage() {
    case "${1:-}" in
        enable)
            echo "Usage: acfs notifications enable"
            echo ""
            echo "Turn on push notifications. The first run generates a random topic;"
            echo "the subscribe URL is printed afterwards."
            ;;
        disable)
            echo "Usage: acfs notifications disable"
            echo ""
            echo "Turn off push notifications. The topic and server are kept."
            ;;
        test)
            echo "Usage: acfs notifications test"
            echo ""
            echo "Send a test notification to the configured topic."
            ;;
        status)
            echo "Usage: acfs notifications status"
            echo ""
            echo "Show the current notification config."
            ;;
        topic)
            echo "Usage: acfs notifications topic"
            echo ""
            echo "Print the subscribe URL."
            ;;
        set-server)
            echo "Usage: acfs notifications set-server <url>"
            echo "Example: acfs notifications set-server https://ntfy.example.com"
            ;;
        set-topic)
            echo "Usage: acfs notifications set-topic <topic>"
            echo "Example: acfs notifications set-topic acfs-myserver-secret123"
            ;;
        set-priority)
            echo "Usage: acfs notifications set-priority <priority>"
            echo "Options: min, low, default, high, urgent (or 1-5)"
            ;;
        send)
            echo "Usage: acfs notifications send [--] <title> [body] [priority]"
            echo ""
            echo "Send an ad-hoc notification via ntfy.sh."
            echo "Put '--' before the title if the title or body starts with '-'."
            echo ""
            echo "Examples:"
            echo "  acfs notifications send 'Build done' 'All tests passed'"
            echo "  acfs notifications send 'Deploy failed' 'See logs' high"
            ;;
        *)
            return 1
            ;;
    esac
}

# Positional arguments of the subcommand being dispatched, set by
# notifications_parse_subcommand_args.
_NOTIF_ARGS=()

# Parse a subcommand's arguments before the subcommand can act (#484).
# Usage: notifications_parse_subcommand_args <subcommand> <max_positionals> [args...]
#
# -h/--help anywhere before a `--` prints the subcommand's usage and returns 2,
# so a help query never sends, enables, or writes anything. Any other argument
# starting with '-' before `--`, and any positional beyond <max_positionals>,
# is a usage error (returns 1) instead of being sent or saved as data.
# Everything after `--` is positional. Returns 0 with _NOTIF_ARGS filled on
# success.
notifications_parse_subcommand_args() {
    local subcmd="$1"
    local max_positionals="$2"
    shift 2

    local arg=""
    for arg in "$@"; do
        [[ "$arg" == "--" ]] && break
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            notifications_subcommand_usage "$subcmd"
            return 2
        fi
    done

    _NOTIF_ARGS=()
    local options_done=false
    for arg in "$@"; do
        if [[ "$options_done" != true ]]; then
            if [[ "$arg" == "--" ]]; then
                options_done=true
                continue
            fi
            if [[ "$arg" == -?* ]]; then
                echo "Error: Unknown option '$(notifications_header_value "$arg" "")' for 'acfs notifications ${subcmd}'." >&2
                if [[ "$max_positionals" -gt 0 ]]; then
                    echo "Put '--' before a value that starts with '-'." >&2
                fi
                notifications_subcommand_usage "$subcmd" >&2
                return 1
            fi
        fi
        _NOTIF_ARGS+=("$arg")
    done

    if [[ ${#_NOTIF_ARGS[@]} -gt "$max_positionals" ]]; then
        echo "Error: Too many arguments for 'acfs notifications ${subcmd}'." >&2
        notifications_subcommand_usage "$subcmd" >&2
        return 1
    fi

    return 0
}

# ============================================================
# Dispatcher
# ============================================================

main() {
    local subcmd="${1:-help}"
    shift 1 2>/dev/null || true

    local handler=""
    local max_positionals=0
    case "$subcmd" in
        enable)       handler=cmd_enable ;;
        disable)      handler=cmd_disable ;;
        test)         handler=cmd_test ;;
        status)       handler=cmd_status ;;
        topic)        handler=cmd_topic ;;
        set-server)   handler=cmd_set_server; max_positionals=1 ;;
        set-priority) handler=cmd_set_priority; max_positionals=1 ;;
        set-topic)    handler=cmd_set_topic; max_positionals=1 ;;
        send)         handler=cmd_send; max_positionals=3 ;;
        help|-h|--help)
            show_help
            return 0
            ;;
        *)
            echo "Unknown command: $subcmd"
            echo "Run 'acfs notifications help' for available commands."
            return 1
            ;;
    esac

    # The handlers act on their positional arguments directly, so every
    # argument is vetted here first: `send --help` must show usage, not send a
    # notification titled "--help".
    local parse_status=0
    notifications_parse_subcommand_args "$subcmd" "$max_positionals" "$@" || parse_status=$?
    case "$parse_status" in
        0) ;;
        2) return 0 ;;
        *) return 1 ;;
    esac

    "$handler" "${_NOTIF_ARGS[@]+"${_NOTIF_ARGS[@]}"}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
elif [[ "$_ACFS_NOTIFICATIONS_SOURCED" == true ]]; then
    if [[ "$_ACFS_NOTIFICATIONS_HAD_ERREXIT" != true ]]; then
        set +e
    fi
    if [[ "$_ACFS_NOTIFICATIONS_HAD_NOUNSET" != true ]]; then
        set +u
    fi
    if [[ "$_ACFS_NOTIFICATIONS_HAD_PIPEFAIL" != true ]]; then
        set +o pipefail
    fi
fi
