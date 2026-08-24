#!/usr/bin/env bash
# ============================================================
# ACFS Progress Bar Library
# Provides visual progress tracking during tool installation.
#
# Related: bead bd-21kh
# ============================================================

# NOTE: Do not enable strict mode here. This file is sourced by
# installers and must not leak set -euo pipefail.

# Global progress state
ACFS_PROGRESS_TOTAL=0
ACFS_PROGRESS_CURRENT=0
ACFS_PROGRESS_START_TIME=0
ACFS_PROGRESS_ENABLED=true
ACFS_PROGRESS_IS_TTY=false
ACFS_PROGRESS_LAST_LINE_LEN=0

_progress_is_nonnegative_integer() {
    local value="${1:-}"
    [[ "$value" =~ ^[0-9]+$ ]]
}

_progress_is_positive_integer() {
    local value="${1:-}"
    _progress_is_nonnegative_integer "$value" || return 1
    (( 10#$value > 0 ))
}

# Check if we should use color/formatting
_progress_check_tty() {
    # Disable progress bar if NO_COLOR is set or output is not a TTY
    if [[ -n "${NO_COLOR:-}" ]]; then
        ACFS_PROGRESS_ENABLED=true  # Still show text, just no colors
        ACFS_PROGRESS_IS_TTY=false
    elif [[ -t 2 ]]; then
        ACFS_PROGRESS_ENABLED=true
        ACFS_PROGRESS_IS_TTY=true
    else
        # Non-TTY (piped output) - use simple line-by-line
        ACFS_PROGRESS_ENABLED=true
        ACFS_PROGRESS_IS_TTY=false
    fi
}

# Initialize progress tracking
# Usage: progress_init <total_items>
progress_init() {
    local total="${1:-0}"

    _progress_check_tty

    if ! _progress_is_positive_integer "$total"; then
        ACFS_PROGRESS_TOTAL=0
        ACFS_PROGRESS_CURRENT=0
        ACFS_PROGRESS_START_TIME=0
        ACFS_PROGRESS_LAST_LINE_LEN=0
        ACFS_PROGRESS_ENABLED=false
        return
    fi

    ACFS_PROGRESS_TOTAL="$total"
    ACFS_PROGRESS_CURRENT=0
    ACFS_PROGRESS_START_TIME=$(date +%s)
    ACFS_PROGRESS_LAST_LINE_LEN=0
}

# Build ASCII progress bar
# Usage: _progress_bar <current> <total> <width>
_progress_bar() {
    local current="${1:-0}"
    local total="${2:-0}"
    local width="${3:-20}"

    if ! _progress_is_positive_integer "$width"; then
        width=20
    fi

    if ! _progress_is_positive_integer "$total" || ! _progress_is_nonnegative_integer "$current"; then
        printf '%*s' "$width" ""
        return
    fi

    local percent=$((10#$current * 100 / 10#$total))
    if [[ "$percent" -gt 100 ]]; then
        percent=100
    fi
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    local bar=""
    local i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    printf '%s' "$bar"
}

# Update progress display
# Usage: progress_update <item_name> [<item_description>]
progress_update() {
    local item_name="${1:-}"
    local item_desc="${2:-}"

    if [[ "$ACFS_PROGRESS_ENABLED" != "true" ]]; then
        return
    fi
    if ! _progress_is_positive_integer "${ACFS_PROGRESS_TOTAL:-0}"; then
        ACFS_PROGRESS_ENABLED=false
        return
    fi
    if ! _progress_is_nonnegative_integer "${ACFS_PROGRESS_CURRENT:-0}"; then
        ACFS_PROGRESS_CURRENT=0
    fi

    ((ACFS_PROGRESS_CURRENT++)) || true

    local current="$ACFS_PROGRESS_CURRENT"
    local total="$ACFS_PROGRESS_TOTAL"
    local percent=$((10#$current * 100 / 10#$total))
    if [[ "$percent" -gt 100 ]]; then
        percent=100
    fi

    # Truncate item name if too long
    local display_name="$item_name"
    if [[ ${#display_name} -gt 35 ]]; then
        display_name="${display_name:0:32}..."
    fi

    if [[ "$ACFS_PROGRESS_IS_TTY" == "true" ]]; then
        # Interactive TTY: in-place update
        local bar
        bar="$(_progress_bar "$current" "$total" 20)"

        # Build the progress line
        local line
        printf -v line "[%s] %d/%d (%d%%) %s" "$bar" "$current" "$total" "$percent" "$display_name"

        # Clear previous line and print new one
        # Use carriage return to overwrite, then clear to end of line
        printf '\r\033[K%s' "$line" >&2

        ACFS_PROGRESS_LAST_LINE_LEN=${#line}
    else
        # Non-TTY or NO_COLOR: simple line-by-line output
        printf '[%d/%d] Installing %s...\n' "$current" "$total" "$display_name" >&2
    fi
}

# Mark progress as complete (add newline for TTY mode)
progress_finish() {
    local total="${ACFS_PROGRESS_TOTAL:-0}"

    if [[ "$ACFS_PROGRESS_ENABLED" != "true" ]]; then
        return
    fi
    if ! _progress_is_nonnegative_integer "$total"; then
        total=0
    fi

    if [[ "$ACFS_PROGRESS_IS_TTY" == "true" ]] && [[ "$ACFS_PROGRESS_LAST_LINE_LEN" -gt 0 ]]; then
        # Print completion message and newline
        local bar
        bar="$(_progress_bar "$total" "$total" 20)"
        printf '\r\033[K[%s] %d/%d (100%%) Complete\n' "$bar" "$total" "$total" >&2
    fi

    # Reset state
    ACFS_PROGRESS_TOTAL=0
    ACFS_PROGRESS_CURRENT=0
    ACFS_PROGRESS_LAST_LINE_LEN=0
}

# Helper to count modules for a category/phase
# Usage: progress_count_modules <category> <phase>
# Returns count via stdout
progress_count_modules() {
    local category="$1"
    local phase="$2"
    local count=0
    local module key

    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        echo "0"
        return
    fi

    for module in "${ACFS_EFFECTIVE_PLAN[@]:-}"; do
        key="$module"
        if [[ "${ACFS_MODULE_CATEGORY[$key]:-}" == "$category" ]] && \
           [[ "${ACFS_MODULE_PHASE[$key]:-}" == "$phase" ]] && \
           [[ "${ACFS_MODULE_GENERATED[$key]:-}" == "1" ]]; then
            ((count++)) || true
        fi
    done

    echo "$count"
}

# ============================================================
# Local milestone progress
# ============================================================

local_progress_file_path() {
    if [[ -n "${ACFS_LOCAL_PROGRESS_FILE:-}" ]]; then
        printf '%s\n' "$ACFS_LOCAL_PROGRESS_FILE"
        return 0
    fi

    if [[ -n "${ACFS_HOME:-}" ]]; then
        printf '%s/local_progress.json\n' "${ACFS_HOME%/}"
        return 0
    fi

    if [[ -n "${HOME:-}" ]]; then
        printf '%s/.acfs/local_progress.json\n' "${HOME%/}"
        return 0
    fi

    return 1
}

local_progress_is_disabled() {
    local value=""

    value="${ACFS_LOCAL_PROGRESS:-}"
    case "${value,,}" in
        0|false|no|off|disabled|disable|opt-out|opt_out)
            return 0
            ;;
    esac

    for value in "${ACFS_LOCAL_PROGRESS_OPT_OUT:-}" "${ACFS_DISABLE_LOCAL_PROGRESS:-}" "${DO_NOT_TRACK:-}"; do
        case "${value,,}" in
            1|true|yes|on|enabled|enable)
                return 0
                ;;
        esac
    done

    return 1
}

local_progress_safe_token() {
    local value="${1:-unknown}"

    if [[ "$value" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]]; then
        printf '%s\n' "$value"
        return 0
    fi

    printf 'unknown\n'
}

local_progress_json_number_or_null() {
    local value="${1:-}"

    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%d\n' "$((10#$value))"
        return 0
    fi

    printf 'null\n'
}

local_progress_json_bool() {
    local value="${1:-false}"

    case "${value,,}" in
        1|true|yes|on)
            printf 'true\n'
            ;;
        *)
            printf 'false\n'
            ;;
    esac
}

local_progress_now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -Iseconds
}

local_progress_record_event() {
    local source="$1"
    local kind="$2"
    local status="$3"
    local details_json="${4:-}"
    local jq_bin=""
    local progress_file=""
    local progress_dir=""
    local tmp=""
    local lock_file=""
    local lock_fd=""
    local now=""
    local max_events="${ACFS_LOCAL_PROGRESS_MAX_EVENTS:-100}"

    [[ -n "$details_json" ]] || details_json="{}"
    local_progress_is_disabled && return 0

    jq_bin="$(command -v jq 2>/dev/null || true)"
    [[ -n "$jq_bin" ]] || return 0

    source="$(local_progress_safe_token "$source")"
    kind="$(local_progress_safe_token "$kind")"
    status="$(local_progress_safe_token "$status")"

    "$jq_bin" -e . >/dev/null 2>&1 <<< "$details_json" || details_json="{}"

    progress_file="$(local_progress_file_path 2>/dev/null || true)"
    [[ -n "$progress_file" ]] || return 0
    progress_dir="$(dirname "$progress_file")"
    mkdir -p "$progress_dir" 2>/dev/null || return 0

    if ! _progress_is_positive_integer "$max_events"; then
        max_events=100
    fi

    if [[ -f "$progress_file" ]] && ! "$jq_bin" . "$progress_file" >/dev/null 2>&1; then
        return 0
    fi

    lock_file="${progress_file}.lock"
    exec {lock_fd}>"$lock_file" 2>/dev/null || return 0
    flock -x -w 2 "$lock_fd" 2>/dev/null || {
        { exec {lock_fd}>&-; } 2>/dev/null || true
        return 0
    }

    tmp="$(mktemp "${progress_dir}/.local_progress.XXXXXX" 2>/dev/null)" || {
        { exec {lock_fd}>&-; } 2>/dev/null || true
        return 0
    }
    now="$(local_progress_now_iso)"

    if [[ -f "$progress_file" ]]; then
        "$jq_bin" \
            --arg now "$now" \
            --arg source "$source" \
            --arg kind "$kind" \
            --arg status "$status" \
            --argjson details "$details_json" \
            --argjson max_events "$max_events" \
            '
            def event_list: if (.events | type) == "array" then .events else [] end;
            (if type == "object" then . else {} end)
            | .schema_version = 1
            | .created_at = (.created_at // $now)
            | .updated_at = $now
            | .events = (
                (event_list + [{
                    timestamp: $now,
                    source: $source,
                    kind: $kind,
                    status: $status,
                    details: $details
                }])
                | if length > $max_events then .[(length - $max_events):] else . end
              )
            ' "$progress_file" > "$tmp" 2>/dev/null || {
            { exec {lock_fd}>&-; } 2>/dev/null || true
            return 0
        }
    else
        "$jq_bin" -n \
            --arg now "$now" \
            --arg source "$source" \
            --arg kind "$kind" \
            --arg status "$status" \
            --argjson details "$details_json" \
            '{
                schema_version: 1,
                created_at: $now,
                updated_at: $now,
                events: [{
                    timestamp: $now,
                    source: $source,
                    kind: $kind,
                    status: $status,
                    details: $details
                }]
            }' > "$tmp" 2>/dev/null || {
            { exec {lock_fd}>&-; } 2>/dev/null || true
            return 0
        }
    fi

    mv -- "$tmp" "$progress_file" 2>/dev/null || {
        { exec {lock_fd}>&-; } 2>/dev/null || true
        return 0
    }

    { exec {lock_fd}>&-; } 2>/dev/null || true
    return 0
}

local_progress_record_installer_phase() {
    local phase_id
    local status
    local kind
    local details_json

    phase_id="$(local_progress_safe_token "${1:-unknown}")"
    status="$(local_progress_safe_token "${2:-unknown}")"

    case "$status" in
        started) kind="phase_started" ;;
        completed) kind="phase_completed" ;;
        failed) kind="phase_failed" ;;
        *) kind="phase_event" ;;
    esac

    printf -v details_json '{"phase_id":"%s"}' "$phase_id"
    local_progress_record_event "installer" "$kind" "$status" "$details_json"
}

local_progress_record_doctor_invoked() {
    local deep_mode
    local fix_mode
    local dry_run_mode
    local json_mode
    local details_json

    deep_mode="$(local_progress_json_bool "${1:-false}")"
    fix_mode="$(local_progress_json_bool "${2:-false}")"
    dry_run_mode="$(local_progress_json_bool "${3:-false}")"
    json_mode="$(local_progress_json_bool "${4:-false}")"
    printf -v details_json '{"deep_mode":%s,"fix_mode":%s,"dry_run_mode":%s,"json_mode":%s}' \
        "$deep_mode" "$fix_mode" "$dry_run_mode" "$json_mode"

    local_progress_record_event "doctor" "doctor_invoked" "invoked" "$details_json"
}

local_progress_record_onboard_lesson() {
    local status
    local kind
    local lesson_index
    local lesson_number
    local details_json

    status="$(local_progress_safe_token "${1:-unknown}")"
    lesson_index="$(local_progress_json_number_or_null "${2:-}")"
    lesson_number="$(local_progress_json_number_or_null "${3:-}")"

    case "$status" in
        started) kind="lesson_started" ;;
        completed) kind="lesson_completed" ;;
        *) kind="lesson_event" ;;
    esac

    printf -v details_json '{"lesson_index":%s,"lesson_number":%s}' "$lesson_index" "$lesson_number"
    local_progress_record_event "onboard" "$kind" "$status" "$details_json"
}

local_progress_record_onboard_event() {
    local kind
    local status
    local completed_count
    local total_lessons
    local details_json

    kind="$(local_progress_safe_token "${1:-event}")"
    status="$(local_progress_safe_token "${2:-observed}")"
    completed_count="$(local_progress_json_number_or_null "${3:-}")"
    total_lessons="$(local_progress_json_number_or_null "${4:-}")"

    printf -v details_json '{"completed_count":%s,"total_lessons":%s}' "$completed_count" "$total_lessons"
    local_progress_record_event "onboard" "$kind" "$status" "$details_json"
}
