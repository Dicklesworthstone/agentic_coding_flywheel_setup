#!/usr/bin/env bash
# ============================================================
# ACFS Installer - Webhook Notification Library
#
# Provides webhook notification for installation completion,
# useful for fleet management, monitoring, and personal alerts.
#
# Related bead: bd-2zqr
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_WEBHOOK_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_WEBHOOK_SH_LOADED=1

# ============================================================
# Configuration Sources (priority order)
# ============================================================
# 1. CLI flag: --webhook <url>
# 2. Environment variable: ACFS_WEBHOOK_URL
# 3. Config file: ~/.config/acfs/config.yaml (webhook_url key)

# Global webhook URL - set by parse_webhook_args or read_webhook_config
ACFS_WEBHOOK_URL="${ACFS_WEBHOOK_URL:-}"

webhook_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

webhook_system_binary_path() {
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

webhook_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(webhook_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(webhook_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

webhook_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(webhook_system_binary_path getent 2>/dev/null || true)"
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

webhook_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(webhook_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

webhook_resolve_current_home() {
    local current_user=""
    local home_candidate=""
    local passwd_entry=""
    local passwd_home=""

    home_candidate="$(webhook_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    current_user="$(webhook_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(webhook_getent_passwd_entry "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(webhook_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

webhook_runtime_home() {
    local current_user=""
    local explicit_target_home=""
    local passwd_entry=""
    local passwd_home=""
    local target_user="${TARGET_USER:-}"

    explicit_target_home="$(webhook_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"

    if [[ -n "$target_user" ]]; then
        [[ "$target_user" =~ ^[a-z_][a-z0-9._-]*$ ]] || return 1

        if [[ "$target_user" == "root" ]]; then
            printf '/root\n'
            return 0
        fi

        passwd_entry="$(webhook_getent_passwd_entry "$target_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(webhook_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi

        current_user="$(webhook_resolve_current_user 2>/dev/null || true)"
        if [[ -z "$current_user" ]] || [[ "$current_user" != "$target_user" ]]; then
            return 1
        fi
    fi

    if [[ -n "$explicit_target_home" ]]; then
        printf '%s\n' "$explicit_target_home"
        return 0
    fi

    webhook_resolve_current_home
}

_ACFS_WEBHOOK_RUNTIME_HOME="$(webhook_runtime_home 2>/dev/null || true)"

webhook_is_hex16_group() {
    [[ "${1:-}" =~ ^[0-9A-Fa-f]{1,4}$ ]]
}

webhook_is_ipv6_literal() {
    local ip="${1:-}"
    local group=""
    local group_count=0
    local left=""
    local right=""
    local -a groups=()

    [[ "$ip" == *:* ]] || return 1
    [[ "$ip" != *:::* ]] || return 1
    # A lone edge colon is invalid; IFS read otherwise drops an empty tail.
    [[ "$ip" != :* || "$ip" == ::* ]] || return 1
    [[ "$ip" != *: || "$ip" == *:: ]] || return 1

    if [[ "$ip" == *::* ]]; then
        [[ "$ip" != *::*::* ]] || return 1

        left="${ip%%::*}"
        right="${ip#*::}"

        if [[ -n "$left" ]]; then
            IFS=: read -r -a groups <<< "$left"
            for group in "${groups[@]}"; do
                webhook_is_hex16_group "$group" || return 1
                group_count=$((group_count + 1))
            done
        fi

        if [[ -n "$right" ]]; then
            IFS=: read -r -a groups <<< "$right"
            for group in "${groups[@]}"; do
                webhook_is_hex16_group "$group" || return 1
                group_count=$((group_count + 1))
            done
        fi

        (( group_count <= 7 ))
        return
    fi

    IFS=: read -r -a groups <<< "$ip"
    [[ ${#groups[@]} -eq 8 ]] || return 1
    for group in "${groups[@]}"; do
        webhook_is_hex16_group "$group" || return 1
    done
}

webhook_public_ip() {
    local curl_bin=""
    local ip=""

    curl_bin="$(webhook_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        printf 'unknown\n'
        return 0
    fi

    ip=$("$curl_bin" -fsS --max-time 2 https://ifconfig.me/ip 2>/dev/null || true)
    ip="${ip//$'\r'/}"
    ip="${ip//$'\n'/}"
    ip="${ip//[[:space:]]/}"

    case "$ip" in
        *[!0-9A-Fa-f:.]*|""|*.*.*.*.*|*:*.*)
            printf 'unknown\n'
            return 0
            ;;
    esac

    if [[ "$ip" == *.* ]]; then
        local octets=()
        local octet
        IFS=. read -r -a octets <<< "$ip"
        if [[ ${#octets[@]} -ne 4 ]]; then
            printf 'unknown\n'
            return 0
        fi
        for octet in "${octets[@]}"; do
            if [[ ! "$octet" =~ ^[0-9]{1,3}$ ]] || (( 10#$octet > 255 )); then
                printf 'unknown\n'
                return 0
            fi
        done
    elif ! webhook_is_ipv6_literal "$ip"; then
        printf 'unknown\n'
        return 0
    fi

    printf '%s\n' "$ip"
}

# ============================================================
# Webhook URL Validation
# ============================================================

# Validate webhook URL - HTTPS only for security
# Usage: webhook_validate_url <url>
# Returns: 0 if valid, 1 if invalid
webhook_validate_url() {
    local url="$1"

    # Empty URL is valid (means no webhook)
    if [[ -z "$url" ]]; then
        return 0
    fi

    # Must start with https://
    if [[ ! "$url" =~ ^https:// ]]; then
        log_warn "Webhook URL rejected: HTTPS required"
        return 1
    fi

    # Basic URL structure check
    if [[ ! "$url" =~ ^https://[^/]+(/|$) ]]; then
        log_warn "Webhook URL rejected: Invalid URL format"
        return 1
    fi

    return 0
}

# ============================================================
# Configuration Reading
# ============================================================

# Read webhook URL from config file if not already set
# Config file: ~/.config/acfs/config.yaml
# Format: webhook_url: "https://..."
webhook_read_config() {
    # Skip if already set via env or CLI
    if [[ -n "${ACFS_WEBHOOK_URL:-}" ]]; then
        return 0
    fi

    local config_home="${_ACFS_WEBHOOK_RUNTIME_HOME:-}"
    local config_file=""

    if [[ -z "$config_home" ]]; then
        return 0
    fi
    config_file="${config_home}/.config/acfs/config.yaml"

    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    # Simple YAML parsing for webhook_url key
    # Handles: webhook_url: "https://..." or webhook_url: 'https://...' or webhook_url: https://...
    local url
    url=$(grep -E '^\s*webhook_url\s*:' "$config_file" 2>/dev/null | head -1 | \
          sed -E 's/^\s*webhook_url\s*:\s*//; s/^["'"'"']//; s/["'"'"']$//' | \
          tr -d '[:space:]') || true

    if [[ -n "$url" ]]; then
        if webhook_validate_url "$url"; then
            ACFS_WEBHOOK_URL="$url"
            log_detail "Webhook URL loaded from config file"
        fi
    fi
}

# ============================================================
# Payload Formatting
# ============================================================

# Detect webhook platform and format appropriately
# Usage: webhook_format_payload <status> <json_summary_file>
# Returns: JSON payload on stdout
webhook_format_payload() {
    local status="$1"
    local summary_file="$2"
    local url="${ACFS_WEBHOOK_URL:-}"
    local jq_bin=""

    # Read summary data
    local hostname ip duration_seconds tools_installed acfs_version timestamp
    hostname=$(hostname 2>/dev/null || echo "unknown")
    ip=$(webhook_public_ip)
    jq_bin="$(webhook_system_binary_path jq 2>/dev/null || true)"
    [[ -n "$jq_bin" ]] || return 1

    if [[ -f "$summary_file" ]]; then
        duration_seconds=$("$jq_bin" -r '.total_seconds // 0' "$summary_file" 2>/dev/null) || duration_seconds=0
        tools_installed=$("$jq_bin" -r '.phases | length // 0' "$summary_file" 2>/dev/null) || tools_installed=0
        acfs_version=$("$jq_bin" -r '.environment.acfs_version // "unknown"' "$summary_file" 2>/dev/null) || acfs_version="unknown"
        timestamp=$("$jq_bin" -r '.timestamp // empty' "$summary_file" 2>/dev/null) || timestamp=""
        [[ -n "$timestamp" ]] || timestamp=$(date -Iseconds)
    else
        duration_seconds=0
        tools_installed=0
        acfs_version="${ACFS_VERSION:-unknown}"
        timestamp=$(date -Iseconds)
    fi

    # Detect platform and format appropriately
    if [[ "$url" == *"hooks.slack.com"* ]]; then
        # Slack webhook format
        _webhook_format_slack "$jq_bin" "$status" "$hostname" "$ip" "$duration_seconds" "$tools_installed" "$acfs_version" "$timestamp"
    elif [[ "$url" == *"discord.com/api/webhooks"* ]]; then
        # Discord webhook format
        _webhook_format_discord "$jq_bin" "$status" "$hostname" "$ip" "$duration_seconds" "$tools_installed" "$acfs_version" "$timestamp"
    else
        # Generic JSON format
        _webhook_format_generic "$jq_bin" "$status" "$hostname" "$ip" "$duration_seconds" "$tools_installed" "$acfs_version" "$timestamp"
    fi
}

# Generic JSON payload
_webhook_format_generic() {
    local jq_bin="$1" status="$2" hostname="$3" ip="$4" duration="$5" tools="$6" version="$7" timestamp="$8"

    "$jq_bin" -n \
        --arg event "install_${status}" \
        --arg timestamp "$timestamp" \
        --arg hostname "$hostname" \
        --arg ip "$ip" \
        --argjson duration_seconds "$duration" \
        --argjson tools_installed "$tools" \
        --argjson tools_failed 0 \
        --arg version "$version" \
        '{
            event: $event,
            timestamp: $timestamp,
            hostname: $hostname,
            ip: $ip,
            duration_seconds: $duration_seconds,
            tools_installed: $tools_installed,
            tools_failed: $tools_failed,
            version: $version,
            errors: []
        }'
}

# Slack webhook format
_webhook_format_slack() {
    local jq_bin="$1" status="$2" hostname="$3" ip="$4" duration="$5" tools="$6" version="$7" timestamp="$8"

    local emoji color text
    if [[ "$status" == "success" ]]; then
        emoji=":white_check_mark:"
        color="good"
        text="ACFS installation completed successfully!"
    else
        emoji=":x:"
        color="danger"
        text="ACFS installation failed"
    fi

    local duration_human
    if [[ "$duration" -ge 60 ]]; then
        duration_human="$((duration / 60))m $((duration % 60))s"
    else
        duration_human="${duration}s"
    fi

    "$jq_bin" -n \
        --arg text "$emoji $text" \
        --arg color "$color" \
        --arg hostname "$hostname" \
        --arg ip "$ip" \
        --arg duration "$duration_human" \
        --arg tools "$tools" \
        --arg version "$version" \
        '{
            attachments: [{
                color: $color,
                text: $text,
                fields: [
                    {title: "Host", value: $hostname, short: true},
                    {title: "IP", value: $ip, short: true},
                    {title: "Duration", value: $duration, short: true},
                    {title: "Phases", value: $tools, short: true},
                    {title: "Version", value: $version, short: true}
                ],
                footer: "ACFS Installer"
            }]
        }'
}

# Discord webhook format
_webhook_format_discord() {
    local jq_bin="$1" status="$2" hostname="$3" ip="$4" duration="$5" tools="$6" version="$7" timestamp="$8"

    local emoji color title
    if [[ "$status" == "success" ]]; then
        emoji=":white_check_mark:"
        color=5763719  # Green
        title="ACFS Installation Complete"
    else
        emoji=":x:"
        color=15548997  # Red
        title="ACFS Installation Failed"
    fi

    local duration_human
    if [[ "$duration" -ge 60 ]]; then
        duration_human="$((duration / 60))m $((duration % 60))s"
    else
        duration_human="${duration}s"
    fi

    "$jq_bin" -n \
        --arg title "$title" \
        --argjson color "$color" \
        --arg hostname "$hostname" \
        --arg ip "$ip" \
        --arg duration "$duration_human" \
        --arg tools "$tools" \
        --arg version "$version" \
        --arg timestamp "$timestamp" \
        '{
            embeds: [{
                title: $title,
                color: $color,
                fields: [
                    {name: "Host", value: $hostname, inline: true},
                    {name: "IP", value: $ip, inline: true},
                    {name: "Duration", value: $duration, inline: true},
                    {name: "Phases", value: $tools, inline: true},
                    {name: "Version", value: $version, inline: true}
                ],
                footer: {text: "ACFS Installer"},
                timestamp: $timestamp
            }]
        }'
}

# ============================================================
# Webhook Sending
# ============================================================

# Send webhook notification (non-blocking, best-effort)
# Usage: webhook_send <status> [summary_file]
# Returns: 0 always (non-blocking, don't fail install)
webhook_send() {
    local status="${1:-success}"
    local summary_file="${2:-${ACFS_SUMMARY_FILE:-}}"
    local url="${ACFS_WEBHOOK_URL:-}"
    local curl_bin=""
    local jq_bin=""

    # No webhook configured - silently skip
    if [[ -z "$url" ]]; then
        return 0
    fi

    # Validate URL
    if ! webhook_validate_url "$url"; then
        return 0
    fi

    # Require curl from a trusted system path. Webhook hooks may run from
    # polluted interactive shells, so do not inherit a caller-provided curl.
    curl_bin="$(webhook_system_binary_path curl 2>/dev/null || true)"
    if [[ -z "$curl_bin" ]]; then
        log_warn "Webhook skipped: curl not available"
        return 0
    fi

    # Require jq for payload formatting from the same trusted resolver.
    jq_bin="$(webhook_system_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        log_warn "Webhook skipped: jq not available"
        return 0
    fi

    log_detail "Sending webhook notification..."

    # Format payload
    local payload
    payload=$(webhook_format_payload "$status" "$summary_file") || {
        log_warn "Webhook skipped: failed to format payload"
        return 0
    }

    # Send webhook (non-blocking with 5s timeout)
    # Runs in background to not block install completion
    (
        local http_code
        http_code=$("$curl_bin" -s -o /dev/null -w '%{http_code}' \
            --max-time 5 \
            -X POST \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$url" 2>/dev/null) || http_code="000"

        if [[ "$http_code" =~ ^2 ]]; then
            # Success - log only if debug mode
            [[ "${ACFS_DEBUG:-}" == "true" ]] && echo "Webhook sent (HTTP $http_code)" >&2
        else
            # Failure - log warning but don't fail
            echo "Webhook failed (HTTP $http_code)" >&2
        fi
    ) &

    # Don't wait for background process
    disown 2>/dev/null || true

    return 0
}

# ============================================================
# Convenience Function
# ============================================================

# Initialize and send webhook (call this from install.sh)
# Usage: webhook_notify <status> [summary_file]
webhook_notify() {
    # Read config if not already set
    webhook_read_config

    # Send notification
    webhook_send "$@"
}
