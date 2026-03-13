#!/usr/bin/env bash
# ============================================================
# ACFS Changelog - Show Recent Changes
#
# Displays changelog entries filtered by date, formatted for terminal.
# Parses CHANGELOG.md in Keep a Changelog format.
#
# Usage:
#   acfs changelog              # Since last update
#   acfs changelog --all        # Full history
#   acfs changelog --since 7d   # Last 7 days
#   acfs changelog --since 2w   # Last 2 weeks
#   acfs changelog --json       # JSON output for scripting
#
# Design Philosophy:
#   - Speed: Parse CHANGELOG.md quickly using shell builtins
#   - Readable: Color-coded output with icons for change types
#   - Filterable: Support date-based filtering
#   - Scriptable: JSON output for automation
#
# Related beads:
#   - bd-2p56: acfs changelog: Show recent changes command
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_CHANGELOG_SH_LOADED:-}" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    exit 0
fi
_ACFS_CHANGELOG_SH_LOADED=1

set -euo pipefail

# ============================================================
# Configuration
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CHANGELOG_EXPLICIT_ACFS_HOME="${ACFS_HOME:-}"
_CHANGELOG_DEFAULT_ACFS_HOME="$HOME/.acfs"
ACFS_HOME="${_CHANGELOG_EXPLICIT_ACFS_HOME:-$_CHANGELOG_DEFAULT_ACFS_HOME}"
_CHANGELOG_EXPLICIT_ACFS_REPO="${ACFS_REPO:-}"
ACFS_REPO="${_CHANGELOG_EXPLICIT_ACFS_REPO:-$ACFS_HOME}"
_CHANGELOG_SYSTEM_STATE_FILE="${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}"
_CHANGELOG_RESOLVED_ACFS_HOME=""
CHANGELOG_FILE="${ACFS_REPO}/CHANGELOG.md"

# Find CHANGELOG.md - check multiple locations
find_changelog() {
    local locations=(
        "${CHANGELOG_FILE}"
        "${ACFS_HOME}/CHANGELOG.md"
        "/data/projects/agentic_coding_flywheel_setup/CHANGELOG.md"
        "$HOME/.acfs/CHANGELOG.md"
    )

    for loc in "${locations[@]}"; do
        if [[ -f "$loc" ]]; then
            echo "$loc"
            return 0
        fi
    done

    return 1
}

# ============================================================
# Color Constants - respect NO_COLOR standard (https://no-color.org/)
# NO_COLOR with any value disables colors. Related: bd-39ye
# ============================================================
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_GREEN='\033[0;32m'
    C_CYAN='\033[0;36m'
    C_YELLOW='\033[0;33m'
    C_RED='\033[0;31m'
    C_MAGENTA='\033[0;35m'
    C_GRAY='\033[0;90m'
else
    C_RESET=''
    C_BOLD=''
    C_DIM=''
    C_GREEN=''
    C_CYAN=''
    C_YELLOW=''
    C_RED=''
    C_MAGENTA=''
    C_GRAY=''
fi

# ============================================================
# Helper Functions
# ============================================================

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

changelog_home_for_user() {
    local user="$1"
    local passwd_entry=""

    [[ -n "$user" ]] || return 1

    if command -v getent &>/dev/null; then
        passwd_entry=$(getent passwd "$user" 2>/dev/null || true)
        if [[ -n "$passwd_entry" ]]; then
            printf '%s\n' "$(printf '%s\n' "$passwd_entry" | cut -d: -f6)"
            return 0
        fi
    fi

    if [[ "$user" == "root" ]]; then
        echo "/root"
        return 0
    fi

    if [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "/home/$user"
        return 0
    fi

    return 1
}

changelog_read_target_user_from_state() {
    local state_file="$1"
    local target_user=""

    [[ -f "$state_file" ]] || return 1

    if command -v jq &>/dev/null; then
        target_user=$(jq -r '.target_user // empty' "$state_file" 2>/dev/null || true)
    else
        target_user=$(sed -n 's/.*"target_user"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$state_file" 2>/dev/null | head -n 1)
    fi

    [[ -n "$target_user" ]] && [[ "$target_user" != "null" ]] || return 1
    printf '%s\n' "$target_user"
}

changelog_script_acfs_home() {
    local candidate=""
    candidate=$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd) || return 1
    [[ "$(basename "$candidate")" == ".acfs" ]] || return 1
    printf '%s\n' "$candidate"
}

resolve_changelog_acfs_home() {
    if [[ -n "$_CHANGELOG_RESOLVED_ACFS_HOME" ]]; then
        printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
        return 0
    fi

    local candidate=""
    local target_home=""
    local target_user=""

    if [[ -n "$_CHANGELOG_EXPLICIT_ACFS_HOME" ]]; then
        _CHANGELOG_RESOLVED_ACFS_HOME="$_CHANGELOG_EXPLICIT_ACFS_HOME"
        printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
        return 0
    fi

    candidate=$(changelog_script_acfs_home 2>/dev/null || true)
    if [[ -n "$candidate" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -f "$candidate/CHANGELOG.md" ]]; then
        _CHANGELOG_RESOLVED_ACFS_HOME="$candidate"
        printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -f "$ACFS_HOME/state.json" || -f "$ACFS_HOME/VERSION" || -f "$ACFS_HOME/CHANGELOG.md" ]]; then
        _CHANGELOG_RESOLVED_ACFS_HOME="$ACFS_HOME"
        printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -n "${SUDO_USER:-}" ]]; then
        target_home=$(changelog_home_for_user "$SUDO_USER" 2>/dev/null || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -f "$candidate/CHANGELOG.md" ]]; then
            _CHANGELOG_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    target_user=$(changelog_read_target_user_from_state "$_CHANGELOG_SYSTEM_STATE_FILE" 2>/dev/null || true)
    if [[ -n "$target_user" ]]; then
        target_home=$(changelog_home_for_user "$target_user" 2>/dev/null || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -f "$candidate/CHANGELOG.md" ]]; then
            _CHANGELOG_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    _CHANGELOG_RESOLVED_ACFS_HOME="$ACFS_HOME"
    printf '%s\n' "$_CHANGELOG_RESOLVED_ACFS_HOME"
}

resolve_changelog_state_file() {
    local candidate="${ACFS_HOME}/state.json"

    if [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    if [[ -f "$_CHANGELOG_SYSTEM_STATE_FILE" ]]; then
        printf '%s\n' "$_CHANGELOG_SYSTEM_STATE_FILE"
        return 0
    fi

    printf '%s\n' "$candidate"
}

refresh_changelog_paths() {
    ACFS_HOME="$(resolve_changelog_acfs_home)"
    if [[ -n "$_CHANGELOG_EXPLICIT_ACFS_REPO" ]]; then
        ACFS_REPO="$_CHANGELOG_EXPLICIT_ACFS_REPO"
    else
        ACFS_REPO="$ACFS_HOME"
    fi
    CHANGELOG_FILE="${ACFS_REPO}/CHANGELOG.md"
}

read_state_timestamp() {
    local state_file="$1"
    local ts=""
    local key=""

    [[ -f "$state_file" ]] || return 1

    if command -v jq &>/dev/null; then
        ts=$(jq -r '
            .last_updated //
            .last_completed_phase_ts //
            .updated_at //
            .last_update //
            .started_at //
            .install_date //
            empty
        ' "$state_file" 2>/dev/null || true)
    fi

    if [[ -z "$ts" || "$ts" == "null" ]]; then
        for key in last_updated last_completed_phase_ts updated_at last_update started_at install_date; do
            ts=$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
                "$state_file" 2>/dev/null | head -n 1)
            if [[ -n "$ts" ]]; then
                break
            fi
        done
    fi

    [[ -n "$ts" ]] || return 1
    printf '%s\n' "$ts"
}

# Get last update timestamp from state.json
get_last_update_date() {
    local state_file=""
    state_file="$(resolve_changelog_state_file)"
    local ts=""

    if ts=$(read_state_timestamp "$state_file" 2>/dev/null || true); then
        if [[ -n "$ts" ]]; then
            date -d "$ts" '+%Y-%m-%d' 2>/dev/null || echo ""
            return 0
        fi
    fi

    # Fallback: 30 days ago
    date -d "30 days ago" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d'
}

# Parse duration string (e.g., "7d", "2w", "1m") to days
parse_duration() {
    local duration="$1"
    if [[ ! "$duration" =~ ^[0-9]+([dDwWmM])?$ ]]; then
        return 1
    fi

    local num="${duration%[dwmDWM]}"
    local unit="${duration: -1}"

    case "$unit" in
        d|D) echo "$num" ;;
        w|W) echo "$((num * 7))" ;;
        m|M) echo "$((num * 30))" ;;
        *) echo "$duration" ;;  # Assume days if no unit
    esac
}

# Format change type icon and color
format_change_type() {
    local type="$1"
    case "$type" in
        Added|added)
            echo -e "${C_GREEN}+"
            ;;
        Changed|changed)
            echo -e "${C_YELLOW}~"
            ;;
        Deprecated|deprecated)
            echo -e "${C_MAGENTA}!"
            ;;
        Removed|removed)
            echo -e "${C_RED}-"
            ;;
        Fixed|fixed)
            echo -e "${C_CYAN}*"
            ;;
        Security|security)
            echo -e "${C_RED}!"
            ;;
        Migration|migration)
            echo -e "${C_YELLOW}>"
            ;;
        *)
            echo -e "${C_GRAY}*"
            ;;
    esac
}

# Get ACFS version from VERSION file
get_acfs_version() {
    local version_file="${ACFS_HOME}/VERSION"
    if [[ -f "$version_file" ]]; then
        cat "$version_file"
    else
        echo "unknown"
    fi
}

refresh_changelog_paths

# ============================================================
# Changelog Parsing
# ============================================================

# Parse CHANGELOG.md and output structured data
# Output format: VERSION|DATE|TYPE|ENTRY
parse_changelog() {
    local changelog_path="$1"
    local current_version=""
    local current_date=""
    local current_type=""
    local in_entry=false
    local entry_text=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Version header: ## [X.Y.Z] - YYYY-MM-DD or ## [Unreleased]
        if [[ "$line" =~ ^##[[:space:]]*\[([^\]]+)\]([[:space:]]*-[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}))? ]]; then
            # Output previous entry if exists
            if [[ -n "$entry_text" ]]; then
                echo "${current_version}|${current_date}|${current_type}|${entry_text}"
                entry_text=""
            fi

            current_version="${BASH_REMATCH[1]}"
            current_date="${BASH_REMATCH[3]:-$(date '+%Y-%m-%d')}"
            current_type=""
            in_entry=false
            continue
        fi

        # Change type header: ### Added, ### Changed, etc.
        if [[ "$line" =~ ^###[[:space:]]*(.+)$ ]]; then
            # Output previous entry if exists
            if [[ -n "$entry_text" ]]; then
                echo "${current_version}|${current_date}|${current_type}|${entry_text}"
                entry_text=""
            fi

            current_type="${BASH_REMATCH[1]}"
            in_entry=false
            continue
        fi

        # Entry line: starts with - or *
        if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+(.+)$ ]]; then
            # Output previous entry if exists
            if [[ -n "$entry_text" ]]; then
                echo "${current_version}|${current_date}|${current_type}|${entry_text}"
            fi

            entry_text="${BASH_REMATCH[1]}"
            in_entry=true
            continue
        fi

        # Continuation line (indented, part of previous entry)
        if [[ "$in_entry" == "true" ]] && [[ "$line" =~ ^[[:space:]]{2,}(.+)$ ]]; then
            entry_text="${entry_text} ${BASH_REMATCH[1]}"
            continue
        fi

        # Empty line ends current entry
        if [[ -z "$line" ]] && [[ -n "$entry_text" ]]; then
            echo "${current_version}|${current_date}|${current_type}|${entry_text}"
            entry_text=""
            in_entry=false
        fi
    done < "$changelog_path"

    # Output final entry if exists
    if [[ -n "$entry_text" ]]; then
        echo "${current_version}|${current_date}|${current_type}|${entry_text}"
    fi
}

# Filter entries by date
filter_by_date() {
    local since_date="$1"
    local since_epoch
    since_epoch=$(date -d "$since_date" '+%s' 2>/dev/null || echo 0)

    while IFS='|' read -r version date type entry; do
        [[ -z "$date" ]] && continue
        local entry_epoch
        entry_epoch=$(date -d "$date" '+%s' 2>/dev/null || echo 0)

        if [[ "$entry_epoch" -ge "$since_epoch" ]]; then
            echo "${version}|${date}|${type}|${entry}"
        fi
    done
}

# ============================================================
# Output Formatters
# ============================================================

# Format as terminal output with colors
format_terminal() {
    local last_version=""
    local last_date=""
    local last_type=""
    local count=0

    while IFS='|' read -r version date type entry; do
        [[ -z "$entry" ]] && continue

        # New version header
        if [[ "$version" != "$last_version" ]] || [[ "$date" != "$last_date" ]]; then
            if [[ "$count" -gt 0 ]]; then
                echo ""  # Space between versions
            fi
            echo -e "${C_BOLD}${C_CYAN}## ${version}${C_RESET}${C_GRAY} - ${date}${C_RESET}"
            last_version="$version"
            last_date="$date"
            last_type=""
        fi

        # New type header
        if [[ "$type" != "$last_type" ]] && [[ -n "$type" ]]; then
            echo -e "${C_DIM}### ${type}${C_RESET}"
            last_type="$type"
        fi

        # Entry with icon
        local icon
        icon=$(format_change_type "$type")
        echo -e "  ${icon} ${entry}${C_RESET}"

        ((++count))
    done

    if [[ "$count" -eq 0 ]]; then
        echo -e "${C_GREEN}You're up to date! No new changes since your last update.${C_RESET}"
    else
        echo ""
        echo -e "${C_DIM}${count} change(s) shown${C_RESET}"
    fi
}

# Format as JSON
format_json() {
    local first=true

    echo "{"
    echo '  "changes": ['

    while IFS='|' read -r version date type entry; do
        [[ -z "$entry" ]] && continue

        if [[ "$first" != "true" ]]; then
            echo ","
        fi
        first=false

        printf '    {"version": "%s", "date": "%s", "type": "%s", "entry": "%s"}' \
            "$(json_escape "$version")" \
            "$(json_escape "$date")" \
            "$(json_escape "$type")" \
            "$(json_escape "$entry")"
    done

    echo ""
    echo "  ],"
    printf '  "acfs_version": "%s",\n' "$(json_escape "$(get_acfs_version)")"
    printf '  "generated_at": "%s"\n' "$(json_escape "$(date -Iseconds)")"
    echo "}"
}

# ============================================================
# Main Function
# ============================================================

show_usage() {
    cat << 'EOF'
ACFS Changelog - Show recent project changes

Usage: acfs changelog [OPTIONS]

Options:
  --all              Show full changelog history
  --since <PERIOD>   Show changes since period (e.g., 7d, 2w, 1m)
  --json             Output in JSON format
  --help, -h         Show this help message

Examples:
  acfs changelog              # Since last update
  acfs changelog --all        # Full history
  acfs changelog --since 7d   # Last 7 days
  acfs changelog --since 2w   # Last 2 weeks
  acfs changelog --json       # JSON output

Legend:
  + Added      New features
  ~ Changed    Changed behavior
  * Fixed      Bug fixes
  - Removed    Removed features
  ! Security   Security updates
  > Migration  Migration guides
EOF
}

main() {
    local show_all=false
    local since_period=""
    local json_output=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all|-a)
                show_all=true
                shift
                ;;
            --since|-s)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --since requires a duration value (e.g., 7d, 2w, 1m)" >&2
                    exit 1
                fi
                since_period="$2"
                shift 2
                ;;
            --json|-j)
                json_output=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage >&2
                exit 1
                ;;
        esac
    done

    # Find changelog file
    local changelog_path
    if ! changelog_path=$(find_changelog); then
        echo "Error: CHANGELOG.md not found" >&2
        echo "Looked in:" >&2
        echo "  - ${CHANGELOG_FILE}" >&2
        echo "  - ${ACFS_HOME}/CHANGELOG.md" >&2
        exit 1
    fi

    # Determine since date
    local since_date
    if [[ "$show_all" == "true" ]]; then
        since_date="1970-01-01"
    elif [[ -n "$since_period" ]]; then
        local days
        if ! days=$(parse_duration "$since_period"); then
            echo "Error: invalid duration '$since_period' (expected 7d, 2w, 1m, or whole days)" >&2
            exit 1
        fi
        since_date=$(date -d "${days} days ago" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
    else
        since_date=$(get_last_update_date)
    fi

    # Header for terminal output
    if [[ "$json_output" != "true" ]]; then
        echo -e "${C_BOLD}ACFS Changelog${C_RESET}"
        if [[ "$show_all" == "true" ]]; then
            echo -e "${C_DIM}Showing all changes${C_RESET}"
        else
            echo -e "${C_DIM}Changes since: ${since_date}${C_RESET}"
        fi
        echo ""
    fi

    # Parse and format
    if [[ "$json_output" == "true" ]]; then
        parse_changelog "$changelog_path" | filter_by_date "$since_date" | format_json
    else
        parse_changelog "$changelog_path" | filter_by_date "$since_date" | format_terminal
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
