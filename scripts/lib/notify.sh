#!/usr/bin/env bash
# ============================================================
# ACFS Installer - ntfy.sh Notification Library
#
# Provides lightweight push notifications via ntfy.sh for
# installation events, agent completions, and system alerts.
# Zero-config: silent no-op when disabled or unconfigured.
#
# Related: GitHub issue #131, bead bd-2igt6
#
# Configuration (env vars override config.yaml values):
#   ACFS_NTFY_TOPIC    - required, the ntfy topic
#   ACFS_NTFY_SERVER   - optional, defaults to https://ntfy.sh
#   ACFS_NTFY_PRIORITY - optional, default priority (min/low/default/high/urgent)
#   ACFS_NTFY_ENABLED  - optional, defaults to "true" if topic is set
#
# Config file: ~/.config/acfs/config.yaml
# Keys: ntfy_enabled, ntfy_topic, ntfy_server, ntfy_priority
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_NOTIFY_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_NOTIFY_SH_LOADED=1

# ============================================================
# Configuration
# ============================================================

# Default ntfy server
ACFS_NTFY_SERVER_DEFAULT="https://ntfy.sh"

# Rate-limit state directory (per-user)
_ACFS_NOTIFY_STATE_DIR="${HOME}/.cache/acfs/notify"

# Minimum seconds between notifications with the same debounce key.
# Override with ACFS_NTFY_DEBOUNCE_SECONDS (default: 30).
_ACFS_NOTIFY_DEBOUNCE_SECONDS="${ACFS_NTFY_DEBOUNCE_SECONDS:-30}"

# ============================================================
# Config Reader
# ============================================================

# Read a single key from ACFS config.yaml
# Usage: _acfs_notify_config_read <key>
# Returns: value on stdout, or empty string
_acfs_notify_config_read() {
    local key="$1"
    local config_file="${HOME}/.config/acfs/config.yaml"

    # Also check target user's config if running as root
    if [[ "$(id -u)" -eq 0 ]] && [[ -n "${TARGET_HOME:-}" ]]; then
        config_file="${TARGET_HOME}/.config/acfs/config.yaml"
    fi

    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    # Simple YAML parsing: key: "value" or key: 'value' or key: value
    local val
    val=$(grep -E "^\s*${key}\s*:" "$config_file" 2>/dev/null | head -1 | \
          sed -E "s/^\s*${key}\s*:\s*//; s/^[\"']//; s/[\"']\s*$//" | \
          sed 's/^[[:space:]]*//; s/[[:space:]]*$//') || true

    printf '%s' "$val"
}

# ============================================================
# Rate Limiting / Debounce
# ============================================================

# Check whether a notification with the given debounce key was sent
# recently (within _ACFS_NOTIFY_DEBOUNCE_SECONDS).  Returns 0 if
# sending is allowed, 1 if the notification should be suppressed.
# When allowed, records the current timestamp.
#
# Usage: _acfs_notify_debounce_allowed <key>
_acfs_notify_debounce_allowed() {
    local key="$1"

    # Debounce disabled (0 or negative)
    if [[ "$_ACFS_NOTIFY_DEBOUNCE_SECONDS" -le 0 ]] 2>/dev/null; then
        return 0
    fi

    mkdir -p "$_ACFS_NOTIFY_STATE_DIR" 2>/dev/null || return 0

    # Sanitise the key so it is safe for a filename
    local safe_key
    safe_key=$(printf '%s' "$key" | tr -cd 'A-Za-z0-9_-')
    local stamp_file="${_ACFS_NOTIFY_STATE_DIR}/${safe_key}.ts"

    local now last_ts
    now=$(date +%s 2>/dev/null) || return 0

    if [[ -f "$stamp_file" ]]; then
        last_ts=$(cat "$stamp_file" 2>/dev/null) || last_ts=0
        if [[ "$last_ts" =~ ^[0-9]+$ ]]; then
            local elapsed=$((now - last_ts))
            if [[ $elapsed -lt $_ACFS_NOTIFY_DEBOUNCE_SECONDS ]]; then
                # Too soon -- suppress
                return 1
            fi
        fi
    fi

    # Record timestamp and allow
    printf '%s' "$now" > "$stamp_file" 2>/dev/null || true
    return 0
}

# ============================================================
# Core Notification Function
# ============================================================

# Send a notification via ntfy.sh (non-blocking, best-effort)
#
# Usage: acfs_notify <title> [body] [priority] [tags]
#   title:    Short notification title (required)
#   body:     Longer description (optional, default: "")
#   priority: ntfy priority 1-5 or name (optional)
#             1=min, 2=low, 3=default, 4=high, 5=urgent
#             Falls back to ACFS_NTFY_PRIORITY env / config, then "default".
#   tags:     Comma-separated ntfy tags/emoji shortcodes (optional)
#             Falls back to "computer,acfs".
#
# Environment overrides:
#   ACFS_NTFY_ENABLED=true|false  Override config
#   ACFS_NTFY_TOPIC=<topic>       Override config
#   ACFS_NTFY_SERVER=<url>        Override config
#   ACFS_NTFY_PRIORITY=<prio>     Override default priority
#
# Returns: 0 always (never fails, never blocks)
acfs_notify() {
    local title="${1:-}"
    local body="${2:-}"
    local priority="${3:-}"
    local tags="${4:-computer,acfs}"

    # Must have a title
    if [[ -z "$title" ]]; then
        return 0
    fi

    # Check if enabled (env override > config file)
    local enabled="${ACFS_NTFY_ENABLED:-}"
    if [[ -z "$enabled" ]]; then
        enabled=$(_acfs_notify_config_read "ntfy_enabled")
    fi

    # Not enabled or explicitly disabled -> silent no-op
    if [[ "$enabled" != "true" ]]; then
        return 0
    fi

    # Read topic (env override > config file)
    local topic="${ACFS_NTFY_TOPIC:-}"
    if [[ -z "$topic" ]]; then
        topic=$(_acfs_notify_config_read "ntfy_topic")
    fi

    # No topic configured -> silent no-op
    if [[ -z "$topic" ]]; then
        return 0
    fi

    # Read server (env override > config file > default)
    local server="${ACFS_NTFY_SERVER:-}"
    if [[ -z "$server" ]]; then
        server=$(_acfs_notify_config_read "ntfy_server")
    fi
    if [[ -z "$server" ]]; then
        server="$ACFS_NTFY_SERVER_DEFAULT"
    fi

    # Resolve priority (arg > env > config > "default")
    if [[ -z "$priority" ]]; then
        priority="${ACFS_NTFY_PRIORITY:-}"
    fi
    if [[ -z "$priority" ]]; then
        priority=$(_acfs_notify_config_read "ntfy_priority")
    fi
    if [[ -z "$priority" ]]; then
        priority="default"
    fi

    # Require curl
    if ! command -v curl &>/dev/null; then
        return 0
    fi

    # Send notification in background (non-blocking, fire-and-forget)
    (
        curl -s -o /dev/null \
            --max-time 10 \
            -H "Title: ${title}" \
            -H "Priority: ${priority}" \
            -H "Tags: ${tags}" \
            -d "${body:-$title}" \
            "${server}/${topic}" 2>/dev/null || true
    ) &
    disown 2>/dev/null || true

    return 0
}

# Send a notification with rate limiting (debounce).
# Same arguments as acfs_notify, plus a leading debounce key.
#
# Usage: acfs_notify_debounced <debounce_key> <title> [body] [priority] [tags]
#
# If a notification with the same debounce_key was sent within the
# last ACFS_NTFY_DEBOUNCE_SECONDS (default 30), the call is a no-op.
acfs_notify_debounced() {
    local debounce_key="${1:-}"
    shift 1 2>/dev/null || true

    if [[ -z "$debounce_key" ]]; then
        acfs_notify "$@"
        return 0
    fi

    if _acfs_notify_debounce_allowed "$debounce_key"; then
        acfs_notify "$@"
    fi

    return 0
}

# ============================================================
# Convenience Wrappers - Installation
# ============================================================

# Notify install success
# Usage: acfs_notify_install_success [duration_human]
acfs_notify_install_success() {
    local duration="${1:-}"
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    local body="Host: ${hostname}"
    if [[ -n "$duration" ]]; then
        body="${body} | Duration: ${duration}"
    fi
    acfs_notify "ACFS Install Complete" "$body" "default" "white_check_mark,acfs"
}

# Notify install failure
# Usage: acfs_notify_install_failure [error_msg]
acfs_notify_install_failure() {
    local error="${1:-Unknown error}"
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    acfs_notify "ACFS Install Failed" "Host: ${hostname} | Error: ${error}" "high" "x,acfs"
}

# ============================================================
# Convenience Wrappers - Agent Task Lifecycle
# ============================================================

# Notify that an agent task completed successfully.
# Usage: acfs_notify_task_complete <task_description> [agent_name] [extra_detail]
acfs_notify_task_complete() {
    local task="${1:-Task}"
    local agent="${2:-}"
    local detail="${3:-}"
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")

    local body="Host: ${hostname}"
    if [[ -n "$agent" ]]; then
        body="${body} | Agent: ${agent}"
    fi
    if [[ -n "$detail" ]]; then
        body="${body} | ${detail}"
    fi

    acfs_notify_debounced "task-complete-${task}" \
        "Task Complete: ${task}" "$body" "default" "white_check_mark,robot,acfs"
}

# Notify that an agent task failed.
# Usage: acfs_notify_task_failed <task_description> [error_msg] [agent_name]
acfs_notify_task_failed() {
    local task="${1:-Task}"
    local error="${2:-Unknown error}"
    local agent="${3:-}"
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")

    local body="Host: ${hostname} | Error: ${error}"
    if [[ -n "$agent" ]]; then
        body="${body} | Agent: ${agent}"
    fi

    acfs_notify_debounced "task-failed-${task}" \
        "Task Failed: ${task}" "$body" "high" "x,robot,acfs"
}

# Notify that human attention is needed (e.g., approval, decision, stuck state).
# Usage: acfs_notify_human_needed <reason> [context] [agent_name]
acfs_notify_human_needed() {
    local reason="${1:-Attention needed}"
    local context="${2:-}"
    local agent="${3:-}"
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")

    local body="Host: ${hostname}"
    if [[ -n "$agent" ]]; then
        body="${body} | Agent: ${agent}"
    fi
    if [[ -n "$context" ]]; then
        body="${body} | ${context}"
    fi

    acfs_notify_debounced "human-needed" \
        "Human Needed: ${reason}" "$body" "urgent" "warning,sos,acfs"
}

# ============================================================
# Convenience Wrappers - System Events
# ============================================================

# Notify nightly update success
# Usage: acfs_notify_update_success [detail]
acfs_notify_update_success() {
    local detail="${1:-}"
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    local body="Host: ${hostname}"
    if [[ -n "$detail" ]]; then
        body="${body} | ${detail}"
    fi
    acfs_notify "ACFS Update Complete" "$body" "low" "arrows_counterclockwise,acfs"
}

# Notify nightly update failure
# Usage: acfs_notify_update_failure [error_msg]
acfs_notify_update_failure() {
    local error="${1:-Unknown error}"
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    acfs_notify "ACFS Update Failed" "Host: ${hostname} | Error: ${error}" "high" "warning,acfs"
}

# Notify a critical error during any ACFS operation.
# Usage: acfs_notify_error <title> [detail]
acfs_notify_error() {
    local title="${1:-ACFS Error}"
    local detail="${2:-}"
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    local body="Host: ${hostname}"
    if [[ -n "$detail" ]]; then
        body="${body} | ${detail}"
    fi
    acfs_notify_debounced "error-${title}" \
        "$title" "$body" "high" "rotating_light,acfs"
}
