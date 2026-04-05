#!/usr/bin/env bash
#
# onboard - ACFS Interactive Onboarding TUI
#
# Teaches users the ACFS workflow through interactive lessons.
# Uses gum for TUI elements with fallback to basic bash menus.
#
# Usage:
#   onboard                 # Launch interactive menu
#   onboard N               # Jump to lesson number N from the lesson filenames
#   onboard status|list|--status|--list   # Show completion status
#   onboard reset|--reset                  # Reset progress
#   onboard help|--help                    # Show help
#   onboard version|--version              # Show version
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

ACFS_HOME="${ACFS_HOME:-$HOME/.acfs}"
LESSONS_DIR="${ACFS_LESSONS_DIR:-$ACFS_HOME/onboard/lessons}"
PROGRESS_FILE="${ACFS_PROGRESS_FILE:-$ACFS_HOME/onboard_progress.json}"
PROGRESS_LOCK_FILE="${PROGRESS_FILE}.lock"
VERSION="0.1.0"
MENU_SEPARATOR="─────────────────────────────────"

# ─────────────────────────────────────────────────────────────────────────────
# Signal Handling — clean exit on Ctrl+C / SIGTERM
# ─────────────────────────────────────────────────────────────────────────────
_onboard_cleanup() {
    printf '\033[?25h' 2>/dev/null   # Restore cursor visibility
    stty echo 2>/dev/null || true    # Re-enable echo if gum disabled it
    printf '\n' 2>/dev/null || true  # Clean newline so shell prompt isn't mangled
    exit 130                         # Standard SIGINT exit code
}
trap _onboard_cleanup INT TERM HUP

# Source gum_ui library if available for consistent theming
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for candidate in \
    "$SCRIPT_DIR/../scripts/lib/gum_ui.sh" \
    "$SCRIPT_DIR/../../scripts/lib/gum_ui.sh" \
    "$HOME/.acfs/scripts/lib/gum_ui.sh"; do
    if [[ -f "$candidate" ]]; then
        # shellcheck disable=SC1090,SC1091
        source "$candidate"
        break
    fi
done

# Dynamic lesson discovery
# Finds all *.md files in LESSONS_DIR, sorted by filename
# Extracts titles from the first "# Title" line in each file
declare -a LESSON_TITLES=()
declare -a LESSON_FILES=()
declare -a LESSON_NUMBERS=()
declare -gA LESSON_INDEX_BY_NUMBER=()

extract_lesson_number() {
    local basename=$1

    if [[ "$basename" =~ ^([0-9]+)(_|$) ]]; then
        printf '%d\n' "$((10#${BASH_REMATCH[1]}))"
        return 0
    fi

    return 1
}

get_lesson_number() {
    local idx=$1

    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 0 && idx < ${#LESSON_NUMBERS[@]} )); then
        printf '%s\n' "${LESSON_NUMBERS[$idx]}"
        return 0
    fi

    return 1
}

get_lesson_index_by_number() {
    local lesson_number=$1

    if [[ -n "${LESSON_INDEX_BY_NUMBER[$lesson_number]+x}" ]]; then
        printf '%s\n' "${LESSON_INDEX_BY_NUMBER[$lesson_number]}"
        return 0
    fi

    return 1
}

discover_lessons() {
    LESSON_TITLES=()
    LESSON_FILES=()
    LESSON_NUMBERS=()
    LESSON_INDEX_BY_NUMBER=()

    if [[ ! -d "$LESSONS_DIR" ]]; then
        return
    fi

    # Find all markdown files, sorted by name (handles NN_ prefix ordering)
    # Using plain sort -z for portability (works on macOS/BSD)
    # Lesson files named 00_xxx, 01_xxx sort correctly with alphanumeric sort
    while IFS= read -r -d '' file; do
        local basename
        local lesson_number
        local lesson_index
        basename=$(basename "$file")
        LESSON_FILES+=("$basename")

        lesson_number="$(extract_lesson_number "$basename" || true)"
        if [[ -z "$lesson_number" ]]; then
            lesson_number="$(( ${#LESSON_FILES[@]} ))"
        fi
        LESSON_NUMBERS+=("$lesson_number")
        lesson_index=$(( ${#LESSON_FILES[@]} - 1 ))
        LESSON_INDEX_BY_NUMBER["$lesson_number"]="$lesson_index"

        # Extract title from first "# " line
        local title
        title=$({ grep -m1 "^# " "$file" 2>/dev/null || true; } | sed 's/^# //' | head -n 1)
        # Fallback to filename if no title found
        if [[ -z "$title" ]]; then
            title="${basename%.md}"
        fi
        LESSON_TITLES+=("$title")
    done < <(find "$LESSONS_DIR" -maxdepth 1 -name "*.md" -print0 2>/dev/null | sort -z)
}

# Run discovery at startup
discover_lessons

# Lesson summaries - key learning points for celebration screen (pipe-separated)
declare -gA LESSON_SUMMARIES=(
    [0]="Understanding the ACFS philosophy|How AI agents fit into development|Your path to productivity"
    [1]="Navigating with pwd, ls, cd|Creating files and directories|Understanding file paths"
    [2]="SSH key-based authentication|Keeping sessions alive|Remote work best practices"
    [3]="Creating and managing sessions|Window and pane navigation|Session persistence"
    [4]="Claude Code (cc) workflow|Codex CLI (cod) basics|Gemini CLI (gmi) overview"
    [5]="NTM dashboard navigation|Understanding system status|Quick actions and controls"
    [6]="Using the prompt palette|Common prompts and shortcuts|Customizing your workflow"
    [7]="The agentic development loop|Continuous improvement|Measuring productivity"
    [8]="Keeping tools updated|Staying current with AI agents|Community resources"
    [9]="Multi-repo sync with ru sync|AI-driven commits via agent-sweep|Parallel workflow automation"
    [10]="DCG command safety|Protection packs|Allow-once workflow"
    [21]="Single-branch model for agent swarms|File reservations replace branches|Preventing conflicts with Agent Mail"
)

# Number of lessons (derived from array length for maintainability)
NUM_LESSONS=${#LESSON_TITLES[@]}

# Service definitions for authentication flow
declare -a AUTH_SERVICES=(
    "tailscale"
    "claude"
    "codex"
    "gemini"
    "github"
    "vercel"
    "supabase"
    "cloudflare"
)

declare -gA AUTH_SERVICE_NAMES=(
    [tailscale]="Tailscale"
    [claude]="Claude Code"
    [codex]="Codex CLI"
    [gemini]="Gemini CLI"
    [github]="GitHub"
    [vercel]="Vercel"
    [supabase]="Supabase"
    [cloudflare]="Cloudflare"
)

declare -gA AUTH_SERVICE_DESCRIPTIONS=(
    [tailscale]="Secure VPS access via private network"
    [claude]="Anthropic's AI coding agent"
    [codex]="OpenAI's AI coding agent"
    [gemini]="Google's AI coding agent"
    [github]="Code hosting and version control"
    [vercel]="Frontend deployment platform"
    [supabase]="Database and auth backend"
    [cloudflare]="CDN and edge computing"
)

declare -gA AUTH_SERVICE_COMMANDS=(
    [tailscale]="sudo tailscale up"
    [claude]="claude"
    [codex]="codex login --device-auth"
    [gemini]="export GEMINI_API_KEY=\"your-gemini-api-key\""
    [github]="gh auth login"
    [vercel]="vercel login"
    [supabase]="supabase login --token YOUR_SUPABASE_ACCESS_TOKEN"
    [cloudflare]="export CLOUDFLARE_API_TOKEN=\"your-token-here\""
)

auth_service_guidance() {
    local service=$1

    case "$service" in
        codex)
            cat <<'EOF'
Use device auth on a headless VPS. If your account does not offer device auth yet,
use the SSH tunnel fallback from the website wizard so the localhost callback works.
EOF
            ;;
        gemini)
            cat <<'EOF'
For a headless VPS, prefer environment-based auth. Add GEMINI_API_KEY to your
shell config or ~/.gemini/.env, then run `gemini`. If you use Vertex AI instead,
set GOOGLE_GENAI_USE_VERTEXAI=true plus the required Google Cloud variables.
EOF
            ;;
        vercel)
            cat <<'EOF'
Vercel CLI now supports a headless-safe device login flow, so `vercel login`
works directly on a VPS. If you need non-interactive auth for automation, export
VERCEL_TOKEN in your shell config instead.
EOF
            ;;
        supabase)
            cat <<'EOF'
Create a Supabase access token in your browser first, then pass it with --token
or export SUPABASE_ACCESS_TOKEN in your shell config for later commands.
EOF
            ;;
        cloudflare)
            cat <<'EOF'
Use API tokens on a headless VPS instead of wrangler login. Add
CLOUDFLARE_API_TOKEN to your shell config, and set CLOUDFLARE_ACCOUNT_ID too if
the commands you plan to run require it.
EOF
            ;;
        *)
            cat <<'EOF'
This will open a browser or print an auth URL/code flow.
Follow the prompts to complete authentication.
EOF
            ;;
    esac
}

# Colors (works in most terminals) - fallback if gum_ui not loaded
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Catppuccin Mocha color scheme (if not already set by gum_ui)
ACFS_PRIMARY="${ACFS_PRIMARY:-#89b4fa}"
ACFS_SECONDARY="${ACFS_SECONDARY:-#74c7ec}"
ACFS_SUCCESS="${ACFS_SUCCESS:-#a6e3a1}"
ACFS_WARNING="${ACFS_WARNING:-#f9e2af}"
ACFS_ERROR="${ACFS_ERROR:-#f38ba8}"
ACFS_MUTED="${ACFS_MUTED:-#6c7086}"
ACFS_ACCENT="${ACFS_ACCENT:-#cba6f7}"
ACFS_PINK="${ACFS_PINK:-#f5c2e7}"
ACFS_TEAL="${ACFS_TEAL:-#94e2d5}"

# ─────────────────────────────────────────────────────────────────────────────
# Utility Functions
# ─────────────────────────────────────────────────────────────────────────────

# Check if gum is available
has_gum() {
    command -v gum &>/dev/null
}

has_interactive_tty() {
    [[ -t 0 && -t 1 ]]
}

has_gum_ui() {
    has_gum && has_interactive_tty
}

# Check if glow is available (for markdown rendering)
has_glow() {
    command -v glow &>/dev/null
}

has_nonblank_value() {
    local value="${1-}"
    [[ -n "${value//[[:space:]]/}" ]]
}

normalize_config_value() {
    local value="${1-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ ${#value} -ge 2 ]]; then
        local first_char="${value:0:1}"
        local last_char="${value: -1}"
        if [[ ( "$first_char" == '"' && "$last_char" == '"' ) || ( "$first_char" == "'" && "$last_char" == "'" ) ]]; then
            value="${value:1:${#value}-2}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
        fi
    fi

    printf '%s\n' "$value"
}

is_placeholder_secret() {
    local normalized
    normalized="$(normalize_config_value "${1-}")"
    normalized="${normalized,,}"

    case "$normalized" in
        your-token-here|your-token|your_api_key|your-api-key|your_vercel_token|your_supabase_access_token|your_cloudflare_api_token|your_gemini_api_key|your_google_api_key|your_project_id|your_project_location|replace-me|change-me|changeme|"<token>"|"<api-key>"|"<secret>")
            return 0
            ;;
    esac

    return 1
}

has_usable_secret() {
    local normalized
    normalized="$(normalize_config_value "${1-}")"
    has_nonblank_value "$normalized" && ! is_placeholder_secret "$normalized"
}

file_has_nonblank_content() {
    local file=$1
    [[ -f "$file" ]] || return 1
    grep -q '[^[:space:]]' "$file" 2>/dev/null
}

read_configured_var_from_file() {
    local var_name=$1
    local file_path=$2
    [[ -f "$file_path" ]] || return 1

    local line=""
    local regex="^[[:space:]]*(export[[:space:]]+)?${var_name}[[:space:]]*=(.*)$"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ $regex ]]; then
            local value="${BASH_REMATCH[2]}"
            local first_char="${value:0:1}"
            if [[ "$first_char" != '"' && "$first_char" != "'" ]]; then
                value="${value%%#*}"
            fi
            value="$(normalize_config_value "$value")"
            if has_nonblank_value "$value"; then
                printf '%s\n' "$value"
                return 0
            fi
        fi
    done < "$file_path"

    return 1
}

get_configured_value() {
    local var_name=$1
    shift
    local env_value="${!var_name-}"
    if has_nonblank_value "$env_value" && ! is_placeholder_secret "$env_value"; then
        normalize_config_value "$env_value"
        return 0
    fi

    local file_path=""
    local configured_value=""
    for file_path in "$@"; do
        configured_value="$(read_configured_var_from_file "$var_name" "$file_path" || true)"
        if has_nonblank_value "$configured_value" && ! is_placeholder_secret "$configured_value"; then
            printf '%s\n' "$configured_value"
            return 0
        fi
    done

    return 1
}

get_configured_secret() {
    local var_name=$1
    shift
    local env_value="${!var_name-}"
    if has_usable_secret "$env_value"; then
        normalize_config_value "$env_value"
        return 0
    fi

    local file_path=""
    local configured_value=""
    for file_path in "$@"; do
        configured_value="$(read_configured_var_from_file "$var_name" "$file_path" || true)"
        if has_usable_secret "$configured_value"; then
            printf '%s\n' "$configured_value"
            return 0
        fi
    done

    return 1
}

configured_truthy_value() {
    local var_name=$1
    shift
    local configured_value=""
    configured_value="$(get_configured_value "$var_name" "$@" || true)"
    case "${configured_value,,}" in
        1|true|yes|on)
            return 0
            ;;
    esac
    return 1
}

compact_progress_json() {
    [[ -f "$PROGRESS_FILE" ]] || return 1
    tr -d '[:space:]' < "$PROGRESS_FILE" 2>/dev/null
}

progress_file_is_valid() {
    [[ -f "$PROGRESS_FILE" ]] || return 1

    if command -v jq &>/dev/null; then
        jq -e '
            (.completed? | type == "array") and
            ((.current? | type == "number") or (.current? == null))
        ' "$PROGRESS_FILE" >/dev/null 2>&1
        return $?
    fi

    local compact
    compact="$(compact_progress_json || true)"
    [[ -n "$compact" ]] || return 1
    [[ "$compact" == *'"completed":['* ]] || return 1
    [[ "$compact" =~ \"current\":[0-9]+ ]] || return 1

    return 0
}

write_default_progress_file() {
    local started_at="$1"
    local last_accessed="$2"
    local progress_dir
    local tmp

    progress_dir="$(dirname "$PROGRESS_FILE")"
    mkdir -p "$progress_dir" 2>/dev/null || true

    tmp=$(mktemp "${progress_dir}/.acfs_onboard.XXXXXX" 2>/dev/null) || {
        echo -e "${RED}Error: could not initialize progress (mktemp failed).${NC}" >&2
        return 1
    }

    if cat > "$tmp" <<EOF
{
  "completed": [],
  "current": 0,
  "started_at": "$started_at",
  "last_accessed": "$last_accessed"
}
EOF
    then
        mv -- "$tmp" "$PROGRESS_FILE" 2>/dev/null || {
            rm -f -- "$tmp" 2>/dev/null || true
            echo -e "${RED}Error: could not initialize progress (mv failed).${NC}" >&2
            return 1
        }
    else
        rm -f -- "$tmp" 2>/dev/null || true
        echo -e "${RED}Error: could not initialize progress.${NC}" >&2
        return 1
    fi

    return 0
}

get_progress_started_at() {
    local compact
    local started_at

    compact="$(compact_progress_json || true)"
    if [[ -n "$compact" ]]; then
        started_at=$(printf '%s' "$compact" | sed -n 's/.*"started_at":"\([^"]*\)".*/\1/p')
        if [[ -n "$started_at" ]]; then
            printf '%s\n' "$started_at"
            return 0
        fi
    fi

    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

build_completed_csv() {
    local new_lesson="${1-}"
    local existing_csv
    local entry
    local i
    local -a ordered=()
    declare -A seen=()

    existing_csv=$(get_completed | tr -d '[:space:]')
    if [[ -n "$existing_csv" ]]; then
        IFS=',' read -r -a ordered <<< "$existing_csv"
        for entry in "${ordered[@]}"; do
            [[ "$entry" =~ ^[0-9]+$ ]] || continue
            seen["$entry"]=1
        done
    fi

    if [[ -n "$new_lesson" ]] && [[ "$new_lesson" =~ ^[0-9]+$ ]]; then
        seen["$new_lesson"]=1
    fi

    ordered=()
    for (( i = 0; i < NUM_LESSONS; i++ )); do
        if [[ -n "${seen[$i]+x}" ]]; then
            ordered+=("$i")
        fi
    done

    (
        IFS=','
        printf '%s' "${ordered[*]}"
    )
}

get_next_incomplete_from_csv() {
    local completed_csv
    completed_csv=$(printf '%s' "$1" | tr -d '[:space:]')

    if (( NUM_LESSONS == 0 )); then
        echo "0"
        return 0
    fi

    local i
    for (( i = 0; i < NUM_LESSONS; i++ )); do
        if [[ ",$completed_csv," != *",$i,"* ]]; then
            echo "$i"
            return 0
        fi
    done

    echo "$((NUM_LESSONS - 1))"
}

write_progress_without_jq() {
    local completed_csv=$1
    local current_lesson=$2
    local progress_dir
    local tmp
    local now
    local started_at

    progress_dir="$(dirname "$PROGRESS_FILE")"
    mkdir -p "$progress_dir" 2>/dev/null || true

    tmp=$(mktemp "${progress_dir}/.acfs_onboard.XXXXXX" 2>/dev/null) || {
        echo -e "${RED}Error: could not save progress (mktemp failed).${NC}" >&2
        return 1
    }

    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    started_at="$(get_progress_started_at)"

    if printf '{"completed":[%s],"current":%s,"started_at":"%s","last_accessed":"%s"}\n' \
        "$completed_csv" "$current_lesson" "$started_at" "$now" > "$tmp"; then
        mv -- "$tmp" "$PROGRESS_FILE" 2>/dev/null || {
            rm -f -- "$tmp" 2>/dev/null || true
            echo -e "${RED}Error: could not save progress (mv failed).${NC}" >&2
            return 1
        }
    else
        rm -f -- "$tmp" 2>/dev/null || true
        echo -e "${RED}Error: could not save progress.${NC}" >&2
        return 1
    fi

    return 0
}

# Initialize progress file if it doesn't exist
init_progress() {
    local dir
    local lock_fd
    local now
    dir=$(dirname "$PROGRESS_FILE")
    mkdir -p "$dir"

    exec {lock_fd}>"$PROGRESS_LOCK_FILE"
    if ! flock -x -w 5 "$lock_fd" 2>/dev/null; then
        echo -e "${RED}Error: could not acquire progress lock.${NC}" >&2
        exec {lock_fd}>&- 2>/dev/null || true
        return 1
    fi

    if ! progress_file_is_valid; then
        if [[ -f "$PROGRESS_FILE" ]]; then
            local backup
            backup="${PROGRESS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
            if mv "$PROGRESS_FILE" "$backup" 2>/dev/null; then
                echo -e "${YELLOW}Warning: repaired malformed progress file (backup: $backup).${NC}" >&2
            else
                echo -e "${RED}Error: could not back up malformed progress file.${NC}" >&2
                exec {lock_fd}>&- 2>/dev/null || true
                return 1
            fi
        fi

        now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        if ! write_default_progress_file "$now" "$now"; then
            exec {lock_fd}>&- 2>/dev/null || true
            return 1
        fi
    fi

    exec {lock_fd}>&- 2>/dev/null || true
}

# Get list of completed lessons
get_completed() {
    if [[ -f "$PROGRESS_FILE" ]]; then
        # Parse JSON with jq if available, otherwise use sed (POSIX-compatible)
        if command -v jq &>/dev/null; then
            jq -r '.completed | @csv' "$PROGRESS_FILE" 2>/dev/null | tr -d '"' || echo ""
        else
            # Handle both pretty-printed jq output and compact JSON.
            local compact
            compact="$(compact_progress_json || true)"
            printf '%s\n' "$compact" | sed -n 's/.*"completed":\[\([^]]*\)\].*/\1/p'
        fi
    else
        echo ""
    fi
}

# Check if a lesson is completed
is_completed() {
    local lesson=$1
    local completed
    completed=$(get_completed | tr -d ' ')
    [[ "$completed" =~ (^|,)$lesson(,|$) ]]
}

# Get current lesson
get_current() {
    if [[ -f "$PROGRESS_FILE" ]] && command -v jq &>/dev/null; then
        jq -r '.current // 0' "$PROGRESS_FILE" 2>/dev/null || echo "0"
    else
        # Handle both pretty-printed jq output and compact JSON.
        local result
        local compact
        compact="$(compact_progress_json || true)"
        result=$(printf '%s\n' "$compact" | sed -n 's/.*"current":\([0-9]*\).*/\1/p' | head -1)
        echo "${result:-0}"
    fi
}

# Get the next recommended lesson index (first incomplete, 0 to NUM_LESSONS-1).
get_next_incomplete() {
    if (( NUM_LESSONS == 0 )); then
        echo "0"
        return 0
    fi

    local i
    # Use C-style for loop since brace expansion {0..N} is evaluated at parse time
    for (( i = 0; i < NUM_LESSONS; i++ )); do
        if ! is_completed "$i"; then
            echo "$i"
            return 0
        fi
    done
    # All lessons complete - return the last lesson index
    echo "$((NUM_LESSONS - 1))"
}

all_lessons_complete() {
    if (( NUM_LESSONS == 0 )); then
        return 1
    fi

    local i
    for (( i = 0; i < NUM_LESSONS; i++ )); do
        if ! is_completed "$i"; then
            return 1
        fi
    done

    return 0
}

# Mark a lesson as completed
# Uses file locking to prevent race conditions with concurrent calls.
mark_completed() {
    local lesson=$1

    if command -v jq &>/dev/null; then
        local tmp
        local progress_dir
        local lock_fd
        progress_dir="$(dirname "$PROGRESS_FILE")"
        mkdir -p "$progress_dir" 2>/dev/null || true

        # Acquire exclusive lock (wait up to 5 seconds)
        exec {lock_fd}>"$PROGRESS_LOCK_FILE"
        if ! flock -x -w 5 "$lock_fd" 2>/dev/null; then
            echo -e "${RED}Error: could not acquire progress lock.${NC}" >&2
            exec {lock_fd}>&- 2>/dev/null || true
            return 1
        fi

        tmp=$(mktemp "${progress_dir}/.acfs_onboard.XXXXXX" 2>/dev/null) || {
            echo -e "${RED}Error: could not save progress (mktemp failed).${NC}" >&2
            exec {lock_fd}>&- 2>/dev/null || true
            return 1
        }

        if jq --argjson lesson "$lesson" --argjson num_lessons "$NUM_LESSONS" '
            .completed = (.completed + [$lesson] | unique | sort) |
            . as $o |
            .current = (
                [range(0;$num_lessons) as $i | select(($o.completed | index($i)) == null) | $i] | first // (if $num_lessons > 0 then ($num_lessons - 1) else 0 end)
            ) |
            .last_accessed = (now | todateiso8601)
        ' "$PROGRESS_FILE" > "$tmp"; then
            mv -- "$tmp" "$PROGRESS_FILE" 2>/dev/null || {
                rm -f -- "$tmp" 2>/dev/null || true
                echo -e "${RED}Error: could not save progress (mv failed).${NC}" >&2
                exec {lock_fd}>&- 2>/dev/null || true
                return 1
            }
        else
            rm -f -- "$tmp" 2>/dev/null || true
            echo -e "${RED}Error: could not save progress.${NC}" >&2
            exec {lock_fd}>&- 2>/dev/null || true
            return 1
        fi

        # Release lock
        exec {lock_fd}>&- 2>/dev/null || true
        return 0
    fi

    local progress_dir
    local lock_fd
    local completed_csv
    local next_current
    progress_dir="$(dirname "$PROGRESS_FILE")"
    mkdir -p "$progress_dir" 2>/dev/null || true

    exec {lock_fd}>"$PROGRESS_LOCK_FILE"
    if ! flock -x -w 5 "$lock_fd" 2>/dev/null; then
        echo -e "${RED}Error: could not acquire progress lock.${NC}" >&2
        exec {lock_fd}>&- 2>/dev/null || true
        return 1
    fi

    completed_csv="$(build_completed_csv "$lesson")"
    next_current="$(get_next_incomplete_from_csv "$completed_csv")"
    if ! write_progress_without_jq "$completed_csv" "$next_current"; then
        exec {lock_fd}>&- 2>/dev/null || true
        return 1
    fi

    exec {lock_fd}>&- 2>/dev/null || true
    return 0
}

# Update current lesson without marking complete
# Uses file locking to prevent race conditions with concurrent calls.
set_current() {
    local lesson=$1

    if command -v jq &>/dev/null; then
        local tmp
        local progress_dir
        local lock_fd
        progress_dir="$(dirname "$PROGRESS_FILE")"
        mkdir -p "$progress_dir" 2>/dev/null || true

        # Acquire exclusive lock (wait up to 5 seconds)
        exec {lock_fd}>"$PROGRESS_LOCK_FILE"
        if ! flock -x -w 5 "$lock_fd" 2>/dev/null; then
            echo -e "${RED}Error: could not acquire progress lock.${NC}" >&2
            exec {lock_fd}>&- 2>/dev/null || true
            return 1
        fi

        tmp=$(mktemp "${progress_dir}/.acfs_onboard.XXXXXX" 2>/dev/null) || {
            echo -e "${RED}Error: could not update progress (mktemp failed).${NC}" >&2
            exec {lock_fd}>&- 2>/dev/null || true
            return 1
        }

        if jq --argjson lesson "$lesson" '
            .current = $lesson |
            .last_accessed = (now | todateiso8601)
        ' "$PROGRESS_FILE" > "$tmp"; then
            mv -- "$tmp" "$PROGRESS_FILE" 2>/dev/null || {
                rm -f -- "$tmp" 2>/dev/null || true
                echo -e "${RED}Error: could not update progress (mv failed).${NC}" >&2
                exec {lock_fd}>&- 2>/dev/null || true
                return 1
            }
        else
            rm -f -- "$tmp" 2>/dev/null || true
            echo -e "${RED}Error: could not update progress.${NC}" >&2
            exec {lock_fd}>&- 2>/dev/null || true
            return 1
        fi

        # Release lock
        exec {lock_fd}>&- 2>/dev/null || true
        return 0
    fi

    local progress_dir
    local lock_fd
    local completed_csv
    progress_dir="$(dirname "$PROGRESS_FILE")"
    mkdir -p "$progress_dir" 2>/dev/null || true

    exec {lock_fd}>"$PROGRESS_LOCK_FILE"
    if ! flock -x -w 5 "$lock_fd" 2>/dev/null; then
        echo -e "${RED}Error: could not acquire progress lock.${NC}" >&2
        exec {lock_fd}>&- 2>/dev/null || true
        return 1
    fi

    completed_csv="$(build_completed_csv)"
    if ! write_progress_without_jq "$completed_csv" "$lesson"; then
        exec {lock_fd}>&- 2>/dev/null || true
        return 1
    fi

    exec {lock_fd}>&- 2>/dev/null || true
    return 0
}

# Reset progress
# Uses file locking to prevent race conditions with concurrent calls.
reset_progress() {
    local progress_dir
    local lock_fd
    progress_dir="$(dirname "$PROGRESS_FILE")"
    mkdir -p "$progress_dir" 2>/dev/null || true

    # Acquire exclusive lock (wait up to 5 seconds)
    exec {lock_fd}>"$PROGRESS_LOCK_FILE"
    if ! flock -x -w 5 "$lock_fd" 2>/dev/null; then
        echo -e "${RED}Error: could not acquire progress lock.${NC}" >&2
        exec {lock_fd}>&- 2>/dev/null || true
        return 1
    fi

    if [[ -f "$PROGRESS_FILE" ]]; then
        local backup
        backup="${PROGRESS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        if mv "$PROGRESS_FILE" "$backup" 2>/dev/null; then
            echo -e "${DIM}Backed up previous progress to: $backup${NC}"
        else
            echo -e "${YELLOW}Warning: could not back up progress file; continuing.${NC}"
        fi
    fi
    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local tmp
    tmp=$(mktemp "${progress_dir}/.acfs_onboard.XXXXXX" 2>/dev/null) || {
        echo -e "${RED}Error: could not reset progress (mktemp failed).${NC}" >&2
        exec {lock_fd}>&- 2>/dev/null || true
        return 1
    }
    if cat > "$tmp" <<EOF
{
  "completed": [],
  "current": 0,
  "started_at": "$now",
  "last_accessed": "$now"
}
EOF
    then
        mv -- "$tmp" "$PROGRESS_FILE" 2>/dev/null || {
            rm -f -- "$tmp" 2>/dev/null || true
            echo -e "${RED}Error: could not reset progress (mv failed).${NC}" >&2
            exec {lock_fd}>&- 2>/dev/null || true
            return 1
        }
    else
        rm -f -- "$tmp" 2>/dev/null || true
        echo -e "${RED}Error: could not reset progress (write failed).${NC}" >&2
        exec {lock_fd}>&- 2>/dev/null || true
        return 1
    fi

    # Release lock
    exec {lock_fd}>&- 2>/dev/null || true
    echo -e "${GREEN}Progress reset!${NC}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Authentication Check Functions
# ─────────────────────────────────────────────────────────────────────────────

# Check if a service is authenticated
# Returns: 0 = authenticated, 1 = not authenticated, 2 = not installed
check_auth_status() {
    local service=$1
    local shell_config_files=(
        "$HOME/.zshrc.local"
        "$HOME/.zshrc"
        "$HOME/.bashrc"
        "$HOME/.profile"
    )

    case "$service" in
        tailscale)
            if ! command -v tailscale &>/dev/null; then
                return 2
            fi
            local status="unknown"
            if command -v jq &>/dev/null; then
                status=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "unknown"' 2>/dev/null || echo "unknown")
            else
                if tailscale status --json 2>/dev/null | grep -q '"BackendState"[[:space:]]*:[[:space:]]*"[[:space:]]*Running"'; then
                    status="Running"
                fi
            fi
            [[ "$status" == "Running" ]] && return 0 || return 1
            ;;
        claude)
            if ! command -v claude &>/dev/null; then
                return 2
            fi
            # Claude Code stores OAuth credentials in ~/.claude/.credentials.json.
            local creds_file="$HOME/.claude/.credentials.json"
            [[ -s "$creds_file" ]] || return 1

            if command -v jq &>/dev/null; then
                local claude_token=""
                claude_token="$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null || true)"
                has_nonblank_value "$claude_token" && return 0 || return 1
            fi

            grep -Eq '"accessToken"[[:space:]]*:[[:space:]]*"[[:space:]]*[^[:space:]"][^"]*"' "$creds_file" && return 0 || return 1
            ;;
        codex)
            if ! command -v codex &>/dev/null; then
                return 2
            fi
            # Codex stores auth in ~/.codex/auth.json (or $CODEX_HOME/auth.json).
            # File existence alone isn't enough; check for an access token field.
            local codex_home="${CODEX_HOME:-$HOME/.codex}"
            local auth_file="$codex_home/auth.json"
            [[ -s "$auth_file" ]] || return 1

            if command -v jq &>/dev/null; then
                local token=""
                token="$(jq -r '.tokens.access_token // .access_token // .accessToken // .OPENAI_API_KEY // empty' "$auth_file" 2>/dev/null || true)"
                has_nonblank_value "$token" && return 0 || return 1
            fi

            # Basic grep fallback if jq is unavailable.
            grep -Eq '"(access(_token|Token)|OPENAI_API_KEY)"[[:space:]]*:[[:space:]]*"[[:space:]]*[^[:space:]"][^"]*"' "$auth_file" && return 0 || return 1
            ;;
        gemini)
            if ! command -v gemini &>/dev/null; then
                return 2
            fi
            local gemini_home="${GEMINI_CLI_HOME:-$HOME}"
            local gemini_config_files=(
                "$gemini_home/.gemini/.env"
                "${shell_config_files[@]}"
            )
            if get_configured_secret "GEMINI_API_KEY" "${gemini_config_files[@]}" >/dev/null; then
                return 0
            fi
            if configured_truthy_value "GOOGLE_GENAI_USE_VERTEXAI" "${gemini_config_files[@]}"; then
                if get_configured_secret "GOOGLE_API_KEY" "${gemini_config_files[@]}" >/dev/null; then
                    return 0
                fi

                local vertex_project=""
                local vertex_location=""
                local service_account_path=""
                vertex_project="$(get_configured_value "GOOGLE_CLOUD_PROJECT" "${gemini_config_files[@]}" || get_configured_value "GOOGLE_CLOUD_PROJECT_ID" "${gemini_config_files[@]}" || true)"
                vertex_location="$(get_configured_value "GOOGLE_CLOUD_LOCATION" "${gemini_config_files[@]}" || true)"
                service_account_path="$(get_configured_value "GOOGLE_APPLICATION_CREDENTIALS" "${gemini_config_files[@]}" || true)"

                if has_nonblank_value "$vertex_project" && has_nonblank_value "$vertex_location"; then
                    if has_nonblank_value "$service_account_path" && [[ -f "$service_account_path" ]]; then
                        return 0
                    fi
                    if command -v gcloud &>/dev/null && timeout 5 gcloud auth application-default print-access-token >/dev/null 2>&1; then
                        return 0
                    fi
                fi
            fi

            # Gemini CLI also stores browser-login state under ~/.gemini/.
            local google_accounts_file="$gemini_home/.gemini/google_accounts.json"
            local oauth_creds_file="$gemini_home/.gemini/oauth_creds.json"

            if command -v jq &>/dev/null; then
                local gemini_active=""
                local gemini_access_token=""
                local gemini_refresh_token=""

                if [[ -f "$google_accounts_file" ]]; then
                    gemini_active="$(jq -r '.active // empty' "$google_accounts_file" 2>/dev/null || true)"
                fi
                if [[ -f "$oauth_creds_file" ]]; then
                    gemini_access_token="$(jq -r '.access_token // empty' "$oauth_creds_file" 2>/dev/null || true)"
                    gemini_refresh_token="$(jq -r '.refresh_token // empty' "$oauth_creds_file" 2>/dev/null || true)"
                fi

                if has_nonblank_value "$gemini_active" || has_nonblank_value "$gemini_access_token" || has_nonblank_value "$gemini_refresh_token"; then
                    return 0
                fi
            else
                if [[ -f "$google_accounts_file" ]] && grep -Eq '"active"[[:space:]]*:[[:space:]]*"[[:space:]]*[^[:space:]"][^"]*"' "$google_accounts_file"; then
                    return 0
                fi
                if [[ -f "$oauth_creds_file" ]] && grep -Eq '"(access_token|refresh_token)"[[:space:]]*:[[:space:]]*"[[:space:]]*[^[:space:]"][^"]*"' "$oauth_creds_file"; then
                    return 0
                fi
            fi
            return 1
            ;;
        github)
            if ! command -v gh &>/dev/null; then
                return 2
            fi
            gh auth status -h github.com &>/dev/null && return 0 || return 1
            ;;
        vercel)
            if ! command -v vercel &>/dev/null; then
                return 2
            fi
            if get_configured_secret "VERCEL_TOKEN" "${shell_config_files[@]}" >/dev/null; then
                return 0
            fi
            local vercel_output=""
            vercel_output="$(vercel whoami 2>/dev/null || true)"
            if [[ -n "$vercel_output" ]] && [[ "${vercel_output,,}" != *"not logged"* ]]; then
                return 0
            fi

            local auth_file=""
            for auth_file in "$HOME/.config/vercel/auth.json" "$HOME/.vercel/auth.json"; do
                [[ -s "$auth_file" ]] || continue
                if command -v jq &>/dev/null; then
                    local vercel_token=""
                    local vercel_email=""
                    vercel_email="$(jq -r '.user.email // empty' "$auth_file" 2>/dev/null || true)"
                    vercel_token="$(jq -r '.token // empty' "$auth_file" 2>/dev/null || true)"
                    if has_nonblank_value "$vercel_email" || has_nonblank_value "$vercel_token"; then
                        return 0
                    fi
                elif grep -Eq '"(token|email)"[[:space:]]*:[[:space:]]*"[[:space:]]*[^[:space:]"][^"]*"' "$auth_file"; then
                    return 0
                fi
            done
            return 1
            ;;
        supabase)
            if ! command -v supabase &>/dev/null; then
                return 2
            fi
            if get_configured_secret "SUPABASE_ACCESS_TOKEN" "${shell_config_files[@]}" >/dev/null; then
                return 0
            fi
            if file_has_nonblank_content "$HOME/.supabase/access-token" || file_has_nonblank_content "$HOME/.config/supabase/access-token"; then
                return 0
            fi
            return 1
            ;;
        cloudflare)
            if ! command -v wrangler &>/dev/null; then
                return 2
            fi
            if get_configured_secret "CLOUDFLARE_API_TOKEN" "${shell_config_files[@]}" >/dev/null; then
                return 0
            fi
            # Prefer the CLI check when available (more reliable than config file presence).
            if wrangler whoami &>/dev/null; then
                return 0
            fi
            return 1
            ;;
        *)
            return 2
            ;;
    esac
}

# Fetch auth status without tripping `set -e`
# Echoes: 0 (authed), 1 (needs auth), 2 (not installed)
get_auth_status_code() {
    local service=$1
    local status
    # Capture exit code safely under set -e
    check_auth_status "$service" && status=0 || status=$?
    echo "$status"
}

# Get auth status display for a service
get_auth_status_display() {
    local service=$1
    local status
    status=$(get_auth_status_code "$service")

    case $status in
        0) echo -e "${GREEN}✓${NC}" ;;
        1) echo -e "${YELLOW}○${NC}" ;;
        2) echo -e "${DIM}—${NC}" ;;
    esac
}

# Show authentication flow
show_auth_flow() {
    while true; do
        clear 2>/dev/null || true

        if has_gum; then
            gum style \
                --border rounded \
                --border-foreground "$ACFS_ACCENT" \
                --padding "1 4" \
                --margin "1" \
                "$(gum style --foreground "$ACFS_PINK" --bold '🔐 Service Authentication')" \
                "$(gum style --foreground "$ACFS_MUTED" --italic "Connect your services for the full experience")"
        else
            echo ""
            echo -e "${BOLD}${MAGENTA}╭─────────────────────────────────────────╮${NC}"
            echo -e "${BOLD}${MAGENTA}│     🔐 Service Authentication          │${NC}"
            echo -e "${BOLD}${MAGENTA}│  Connect your services                  │${NC}"
            echo -e "${BOLD}${MAGENTA}╰─────────────────────────────────────────╯${NC}"
            echo ""
        fi

        echo ""
        echo -e "${BOLD}Service Status:${NC}"
        echo ""

        local authed=0
        local total=0

        for service in "${AUTH_SERVICES[@]}"; do
            local name="${AUTH_SERVICE_NAMES[$service]}"
            local desc="${AUTH_SERVICE_DESCRIPTIONS[$service]}"
            local status_icon
            status_icon=$(get_auth_status_display "$service")

            local status
            status=$(get_auth_status_code "$service")

            if [[ $status -ne 2 ]]; then
                ((total += 1))
                [[ $status -eq 0 ]] && ((authed += 1))
            fi

            printf "  %s  %-15s %s\n" "$status_icon" "$name" "${DIM}$desc${NC}"
        done

        echo ""
        echo -e "${DIM}Legend: ${GREEN}✓${NC} authenticated  ${YELLOW}○${NC} needs auth  ${DIM}—${NC} not installed${NC}"
        echo ""

        if [[ $total -gt 0 ]]; then
            echo -e "${CYAN}Progress: $authed/$total services authenticated${NC}"
        fi

        echo ""
        echo -e "${DIM}─────────────────────────────────────────${NC}"

        # Show menu options
        if has_gum; then
            local -a items=()
            for service in "${AUTH_SERVICES[@]}"; do
                local status
                status=$(get_auth_status_code "$service")
                if [[ $status -eq 1 ]]; then
                    items+=("🔑 Authenticate ${AUTH_SERVICE_NAMES[$service]}")
                fi
            done
            items+=("$MENU_SEPARATOR")
            items+=("📋 [m] Back to menu")
            items+=("🔄 [r] Refresh status")

            local choice
            choice=$(printf '%s\n' "${items[@]}" | gum choose \
                --cursor.foreground "$ACFS_ACCENT" \
                --selected.foreground "$ACFS_SUCCESS" 2>/dev/null) || true

            # Empty choice (Esc or Ctrl+C) -> back to menu
            if [[ -z "$choice" ]]; then
                return 0
            fi

            case "$choice" in
                *"[m]"*) return 0 ;;
                *"[r]"*) continue ;;
                *"Authenticate"*)
                    # Extract service name from choice
                    for service in "${AUTH_SERVICES[@]}"; do
                        if [[ "$choice" == *"${AUTH_SERVICE_NAMES[$service]}"* ]]; then
                            show_auth_service "$service"
                            # Loop continues to refresh
                            break
                        fi
                    done
                    ;;
            esac
        else
            echo "Options:"
            echo "  [number] Authenticate a listed service"
            echo "  [m]   Back to menu"
            echo "  [r]   Refresh status"
            echo ""

            local -a auth_menu_services=()
            for service in "${AUTH_SERVICES[@]}"; do
                local status
                status=$(get_auth_status_code "$service")
                if [[ $status -eq 1 ]]; then
                    auth_menu_services+=("$service")
                    echo "  [${#auth_menu_services[@]}] ${AUTH_SERVICE_NAMES[$service]}"
                fi
            done

            if [[ ${#auth_menu_services[@]} -eq 0 ]]; then
                echo "  No installed services currently need authentication."
            fi

            read -rp "$(echo -e "${CYAN}Choose:${NC} ")" choice

            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                local idx=$((10#$choice - 1))
                if [[ $idx -ge 0 ]] && [[ $idx -lt ${#auth_menu_services[@]} ]]; then
                    show_auth_service "${auth_menu_services[$idx]}"
                    # Loop continues to refresh
                fi
                continue
            fi

            case "$choice" in
                m|M) return 0 ;;
                r|R) continue ;;
            esac
        fi
    done
}

# Show auth instructions for a specific service
show_auth_service() {
    local service=$1
    local name="${AUTH_SERVICE_NAMES[$service]}"
    local cmd="${AUTH_SERVICE_COMMANDS[$service]}"

    clear 2>/dev/null || true

    if has_gum; then
        gum style \
            --border rounded \
            --border-foreground "$ACFS_PRIMARY" \
            --padding "1 2" \
            "$(gum style --foreground "$ACFS_ACCENT" "🔑 Authenticate $name")"

        echo ""
        echo "To authenticate $name, run this command:"
        echo ""
        gum style --foreground "$ACFS_TEAL" --bold "  $cmd"
        echo ""
        auth_service_guidance "$service"
        echo ""

        gum confirm --affirmative "I've authenticated" --negative "Skip for now" || true
    else
        echo ""
        echo -e "${BOLD}${CYAN}Authenticate $name${NC}"
        echo ""
        echo "Run this command:"
        echo ""
        echo -e "  ${GREEN}$cmd${NC}"
        echo ""
        auth_service_guidance "$service"
        echo ""
        read -rp "Press Enter when done (or 's' to skip)... " _
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Display Functions
# ─────────────────────────────────────────────────────────────────────────────

# Calculate progress statistics
# Returns: completed_count|total|percent|est_minutes_remaining
calc_progress_stats() {
    local completed_count=0
    local i
    for (( i = 0; i < NUM_LESSONS; i++ )); do
        if is_completed "$i"; then
            ((completed_count += 1))
        fi
    done
    local total="$NUM_LESSONS"
    if (( total == 0 )); then
        echo "0|0|0|0"
        return 0
    fi
    local percent=$((completed_count * 100 / total))
    local remaining=$((total - completed_count))
    local est_minutes=$((remaining * 5))  # ~5 min per lesson average
    echo "${completed_count}|${total}|${percent}|${est_minutes}"
}

# Render progress bar (20 chars wide)
render_progress_bar() {
    local percent=$1
    local width=20
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done
    echo "$bar"
}

show_no_lessons_notice() {
    local message="No lesson markdown files were found in ${LESSONS_DIR}."
    local hint="Re-run the installer or set ACFS_LESSONS_DIR to a directory with onboarding lessons."

    echo ""
    if has_gum; then
        gum style \
            --border rounded \
            --border-foreground "$ACFS_WARNING" \
            --padding "1 2" \
            --margin "0 0 1 0" \
            "$(gum style --foreground "$ACFS_WARNING" --bold '⚠️  No lessons available')" \
            "$(gum style --foreground "$ACFS_MUTED" "$message")" \
            "$(gum style --foreground "$ACFS_MUTED" "$hint")"
    else
        echo -e "${YELLOW}${BOLD}No lessons available.${NC}"
        echo -e "${DIM}${message}${NC}"
        echo -e "${DIM}${hint}${NC}"
    fi
}

# Print header with progress bar
print_header() {
    clear 2>/dev/null || true

    # Get progress stats
    local stats completed total percent est_minutes
    stats=$(calc_progress_stats)
    IFS='|' read -r completed total percent est_minutes <<< "$stats"
    local bar
    bar=$(render_progress_bar "$percent")

    if has_gum; then
        # Build time remaining text
        local time_text=""
        if [[ "$total" -eq 0 ]]; then
            time_text="No lessons found in ${LESSONS_DIR}"
        elif [[ "$completed" -lt "$total" ]]; then
            if [[ "$est_minutes" -ge 60 ]]; then
                time_text="Est. remaining: ~$((est_minutes / 60))h $((est_minutes % 60))m"
            elif [[ "$est_minutes" -gt 0 ]]; then
                time_text="Est. remaining: ~${est_minutes} minutes"
            fi
        else
            time_text="🎉 All lessons complete!"
        fi

        gum style \
            --border rounded \
            --border-foreground "$ACFS_ACCENT" \
            --padding "1 4" \
            --margin "1" \
            "$(gum style --foreground "$ACFS_PINK" --bold '📚 ACFS Onboarding')" \
            "$(gum style --foreground "$ACFS_PRIMARY" "$bar") $(gum style --foreground "$ACFS_SUCCESS" --bold "$completed/$total") $(gum style --foreground "$ACFS_MUTED" "($percent%)")" \
            "$(gum style --foreground "$ACFS_MUTED" --italic "$time_text")"
    else
        # Plain text fallback
        local time_text=""
        if [[ "$total" -eq 0 ]]; then
            time_text="No lessons found in ${LESSONS_DIR}"
        elif [[ "$completed" -lt "$total" ]]; then
            if [[ "$est_minutes" -ge 60 ]]; then
                time_text="Est. remaining: ~$((est_minutes / 60))h $((est_minutes % 60))m"
            elif [[ "$est_minutes" -gt 0 ]]; then
                time_text="Est. remaining: ~${est_minutes} minutes"
            fi
        else
            time_text="All lessons complete!"
        fi

        echo ""
        echo -e "${BOLD}${MAGENTA}╭─────────────────────────────────────────────────────╮${NC}"
        echo -e "${BOLD}${MAGENTA}│${NC}  ${BOLD}📚 ACFS Onboarding${NC}                                   ${BOLD}${MAGENTA}│${NC}"
        echo -e "${BOLD}${MAGENTA}│${NC}  ${CYAN}${bar}${NC} ${GREEN}${completed}/${total}${NC} (${percent}%)            ${BOLD}${MAGENTA}│${NC}"
        echo -e "${BOLD}${MAGENTA}│${NC}  ${DIM}${time_text}${NC}$(printf '%*s' $((27 - ${#time_text})) '')${BOLD}${MAGENTA}│${NC}"
        echo -e "${BOLD}${MAGENTA}╰─────────────────────────────────────────────────────╯${NC}"
        echo ""
    fi
}

# Format lesson title with status
format_lesson() {
    local idx=$1
    local title="${LESSON_TITLES[$idx]}"
    local status=""
    local current
    current=$(get_current)

    if is_completed "$idx"; then
        status="${GREEN}✓${NC}"
    elif [[ "$idx" == "$current" ]]; then
        status="${YELLOW}●${NC}"
    else
        status="${DIM}○${NC}"
    fi

    local lesson_number
    lesson_number="$(get_lesson_number "$idx" || printf '%d' "$((idx + 1))")"

    printf "%s [%s] %s" "$status" "$lesson_number" "$title"
}

# Show lesson menu with gum
show_menu_gum() {
    local current i
    current=$(get_current)

    # Build menu items with styled status indicators
    local -a items=()
    for (( i = 0; i < NUM_LESSONS; i++ )); do
        local status=""
        if is_completed "$i"; then
            status="✓"
        elif [[ "$i" == "$current" ]]; then
            status="●"
        else
            status="○"
        fi
        local lesson_number
        lesson_number="$(get_lesson_number "$i" || printf '%d' "$((i + 1))")"
        items+=("${status} [${lesson_number}] ${LESSON_TITLES[$i]}")
    done
    if (( NUM_LESSONS > 0 )); then
            items+=("$MENU_SEPARATOR")
    fi
    items+=("🔐 [a] Authenticate Services")
    items+=("↺ [r] Restart from beginning")
    items+=("📊 [s] Show status")
    # Show certificate option only when all lessons complete
    if all_lessons_complete; then
        items+=("🏆 [t] View Certificate")
    fi
    items+=("👋 [q] Quit")

    # Show menu with gum using Catppuccin colors
    local choice=""
    choice=$(printf '%s\n' "${items[@]}" | gum choose \
        --cursor.foreground "$ACFS_ACCENT" \
        --selected.foreground "$ACFS_SUCCESS" \
        --header.foreground "$ACFS_PRIMARY" \
        --header "Select a lesson:" 2>/dev/null) || true

    # Parse choice (handles single and double digit lesson numbers)
    # Empty choice (Esc or gum failure) is treated as "invalid" to redraw menu
    if [[ -z "$choice" ]]; then
        echo "invalid"
    elif [[ "$choice" =~ \[([0-9]+)\] ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$choice" == "$MENU_SEPARATOR" ]]; then
        echo "invalid"
    elif [[ "$choice" =~ \[a\] ]]; then
        echo "a"
    elif [[ "$choice" =~ \[r\] ]]; then
        echo "r"
    elif [[ "$choice" =~ \[s\] ]]; then
        echo "s"
    elif [[ "$choice" =~ \[t\] ]]; then
        echo "t"
    else
        echo "q"
    fi
}

# Show lesson menu with basic bash
show_menu_basic() {
    local i
    if (( NUM_LESSONS == 0 )); then
        show_no_lessons_notice
    fi

    echo -e "${BOLD}Choose a lesson:${NC}"
    echo ""

    for (( i = 0; i < NUM_LESSONS; i++ )); do
        echo -e "  $(format_lesson "$i")"
    done

    echo ""
    echo -e "  ${DIM}[a] Authenticate Services${NC}"
    echo -e "  ${DIM}[r] Restart from beginning${NC}"
    echo -e "  ${DIM}[s] Show status${NC}"
    # Show certificate option only when all lessons complete
    if all_lessons_complete; then
        echo -e "  ${GREEN}[t] View Certificate${NC}"
    fi
    echo -e "  ${DIM}[q] Quit${NC}"
    echo ""

    local prompt_opts="a, r, s, q"
    if (( NUM_LESSONS > 0 )); then
        prompt_opts="lesson number, a, r, s, q"
    fi
    if all_lessons_complete; then
        if (( NUM_LESSONS > 0 )); then
            prompt_opts="lesson number, a, r, s, t, q"
        else
            prompt_opts="a, r, s, t, q"
        fi
    fi
    read -rp "$(echo -e "${CYAN}Choose [$prompt_opts]:${NC} ")" choice

    # Validate numeric choices against actual lesson count
    # Use 10# to force decimal interpretation (avoids octal error for '08', '09')
    if [[ "$choice" =~ ^[0-9]+$ ]] && get_lesson_index_by_number "$((10#$choice))" >/dev/null 2>&1; then
        echo "$((10#$choice))"
    else
        case "$choice" in
            a|A) echo "a" ;;
            r|R) echo "r" ;;
            s|S) echo "s" ;;
            t|T) echo "t" ;;
            q|Q|"") echo "q" ;;
            *) echo "invalid" ;;
        esac
    fi
}

# Render markdown content
render_markdown() {
    local file=$1

    if has_glow; then
        # Prevent glow's built-in pager from blocking on long lessons
        PAGER="cat" glow -s dark "$file"
    elif has_gum; then
        gum format -t markdown < "$file"
    elif command -v bat &>/dev/null; then
        bat --paging=never --style=plain --language=markdown "$file"
    else
        # Basic markdown rendering with sed
        sed \
            -e "s/^# \(.*\)$/$(printf '\033[1;35m')\\1$(printf '\033[0m')/" \
            -e "s/^## \(.*\)$/$(printf '\033[1;36m')\\1$(printf '\033[0m')/" \
            -e "s/^### \(.*\)$/$(printf '\033[1;33m')\\1$(printf '\033[0m')/" \
            -e "s/\*\*\([^*]*\)\*\*/$(printf '\033[1m')\\1$(printf '\033[0m')/g" \
            -e "s/\`\([^\`]*\)\`/$(printf '\033[36m')\\1$(printf '\033[0m')/g" \
            -e "s/^---$/$(printf '\033[90m')────────────────────────────────────────$(printf '\033[0m')/" \
            -e "s/^- /  • /" \
            "$file"
    fi
}

# Show celebration screen after completing a lesson
show_celebration() {
    local idx=$1
    local title="${LESSON_TITLES[$idx]}"
    local stats completed_count total
    local next_idx=""
    local lesson_number=""
    lesson_number="$(get_lesson_number "$idx" || printf '%d' "$((idx + 1))")"
    local summaries="${LESSON_SUMMARIES[$lesson_number]:-}"
    stats=$(calc_progress_stats)
    IFS='|' read -r completed_count total _ _ <<< "$stats"
    if [[ -z "$summaries" ]]; then
        if all_lessons_complete; then
            summaries="Key concepts from ${title}|You have completed the full onboarding curriculum"
        else
            next_idx=$(get_current)
            if [[ ! "$next_idx" =~ ^[0-9]+$ ]] || (( next_idx < 0 || next_idx >= NUM_LESSONS )); then
                next_idx=$(get_next_incomplete)
            fi
            if [[ "$next_idx" =~ ^[0-9]+$ ]] && (( next_idx >= 0 && next_idx < NUM_LESSONS )); then
                local next_lesson_number
                next_lesson_number="$(get_lesson_number "$next_idx" || printf '%d' "$((next_idx + 1))")"
                summaries="Key concepts from ${title}|Next recommended lesson: onboard ${next_lesson_number}"
            else
                summaries="Key concepts from ${title}|Continue anytime with onboard status"
            fi
        fi
    fi

    clear 2>/dev/null || true

    if has_gum; then
        # Build summary bullets
        local summary_text=""
        if [[ -n "$summaries" ]]; then
            IFS='|' read -ra items <<< "$summaries"
            for item in "${items[@]}"; do
                summary_text+="$(gum style --foreground "$ACFS_TEAL" "  ✦ $item")"$'\n'
            done
        fi

        gum style \
            --border double \
            --border-foreground "$ACFS_SUCCESS" \
            --padding "2 4" \
            --margin "2" \
            --align center \
            "$(gum style --foreground "$ACFS_SUCCESS" --bold '🎉 Lesson Complete!')" \
            "" \
            "$(gum style --foreground "$ACFS_PINK" --bold "Lesson ${lesson_number}: $title")" \
            "" \
            "$(gum style --foreground "$ACFS_MUTED" 'You learned:')" \
            "$summary_text" \
            "" \
            "$(gum style --foreground "$ACFS_ACCENT" "Progress: ${completed_count}/${total} lessons")"

        sleep 2
    else
        echo ""
        echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}${BOLD}║            🎉 Lesson Complete!                     ║${NC}"
        echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${MAGENTA}${BOLD}Lesson ${lesson_number}: $title${NC}"
        echo ""
        echo -e "${DIM}You learned:${NC}"

        if [[ -n "$summaries" ]]; then
            IFS='|' read -ra items <<< "$summaries"
            for item in "${items[@]}"; do
                echo -e "  ${CYAN}✦${NC} $item"
            done
        fi

        echo ""
        echo -e "${CYAN}Progress: ${completed_count}/${total} lessons${NC}"
        echo ""
        sleep 2
    fi
}

# Show completion certificate when all lessons are done
show_completion_certificate() {
    local completed_at
    completed_at=$(date '+%Y-%m-%d %H:%M')

    clear 2>/dev/null || true

    if has_gum; then
        gum style \
            --border double \
            --border-foreground "$ACFS_SUCCESS" \
            --padding "2 6" \
            --margin "2" \
            --align center \
            "$(gum style --foreground "$ACFS_ACCENT" --bold '╔═══════════════════════════════════════╗')" \
            "$(gum style --foreground "$ACFS_ACCENT" --bold '║     CERTIFICATE OF COMPLETION         ║')" \
            "$(gum style --foreground "$ACFS_ACCENT" --bold '╚═══════════════════════════════════════╝')" \
            "" \
            "$(gum style --foreground "$ACFS_SUCCESS" --bold '🏆 ACFS Onboarding Complete! 🏆')" \
            "" \
            "$(gum style --foreground "$ACFS_PINK" "You have successfully completed all $NUM_LESSONS lessons")" \
            "$(gum style --foreground "$ACFS_PINK" "of the Agentic Coding Flywheel Setup tutorial.")" \
            "" \
            "$(gum style --foreground "$ACFS_TEAL" "Curriculum Highlights:")" \
            "$(gum style --foreground "$ACFS_MUTED" "  • Linux, SSH, tmux, and shell workflow")" \
            "$(gum style --foreground "$ACFS_MUTED" "  • AI agents, prompts, and local skills")" \
            "$(gum style --foreground "$ACFS_MUTED" "  • Coordination, safety, triage, and memory systems")" \
            "$(gum style --foreground "$ACFS_MUTED" "  • Search, debugging, maintenance, and release tooling")" \
            "" \
            "$(gum style --foreground "$ACFS_PRIMARY" "Completed: $completed_at")" \
            "" \
            "$(gum style --foreground "$ACFS_SUCCESS" --bold '🚀 You are ready to fly! 🚀')"

        echo ""
        gum confirm --affirmative "Continue" --negative "" || true
    else
        echo ""
        echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}${BOLD}║              CERTIFICATE OF COMPLETION                     ║${NC}"
        echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}${BOLD}         🏆 ACFS Onboarding Complete! 🏆${NC}"
        echo ""
        echo -e "  You have successfully completed all $NUM_LESSONS lessons"
        echo -e "  of the Agentic Coding Flywheel Setup tutorial."
        echo ""
        echo -e "${CYAN}${BOLD}  Curriculum Highlights:${NC}"
        echo -e "    • Linux, SSH, tmux, and shell workflow"
        echo -e "    • AI agents, prompts, and local skills"
        echo -e "    • Coordination, safety, triage, and memory systems"
        echo -e "    • Search, debugging, maintenance, and release tooling"
        echo ""
        echo -e "${DIM}  Completed: $completed_at${NC}"
        echo ""
        echo -e "${GREEN}${BOLD}         🚀 You are ready to fly! 🚀${NC}"
        echo ""
        read -rp "Press Enter to continue..."
    fi
}

# Show a lesson
show_lesson() {
    local idx=$1
    local file="${LESSONS_DIR}/${LESSON_FILES[$idx]}"
    local lesson_number=""
    lesson_number="$(get_lesson_number "$idx" || printf '%d' "$((idx + 1))")"

    if [[ ! -f "$file" ]]; then
        if has_gum; then
            gum style --foreground "$ACFS_ERROR" "Error: Lesson file not found: $file"
        else
            echo -e "${RED}Error: Lesson file not found: $file${NC}"
        fi
        echo "Please ensure ACFS is properly installed."
        return 1
    fi

    clear 2>/dev/null || true

    # Header with step indicator
    if has_gum; then
        # Build progress dots
        local dots=""
        for ((i = 0; i < NUM_LESSONS; i++)); do
            if is_completed "$i"; then
                dots+="$(gum style --foreground "$ACFS_SUCCESS" "●") "
            elif [[ $i -eq $idx ]]; then
                dots+="$(gum style --foreground "$ACFS_PRIMARY" --bold "●") "
            else
                dots+="$(gum style --foreground "$ACFS_MUTED" "○") "
            fi
        done

        gum style \
            --border rounded \
            --border-foreground "$ACFS_PRIMARY" \
            --padding "1 2" \
            --margin "0 0 1 0" \
            "$(gum style --foreground "$ACFS_ACCENT" "Lesson ${lesson_number} ($((idx + 1))/$NUM_LESSONS)")
$dots
$(gum style --foreground "$ACFS_PINK" --bold "${LESSON_TITLES[$idx]}")"
    else
        echo -e "${BOLD}${MAGENTA}Lesson ${lesson_number}: ${LESSON_TITLES[$idx]}${NC}"
        echo -e "${DIM}─────────────────────────────────────────${NC}"
        echo ""
    fi

    # Content
    render_markdown "$file"

    echo ""

    # Navigation with gum
    local last_idx=$((NUM_LESSONS - 1))
    if has_gum_ui; then
        gum style --foreground "$ACFS_MUTED" "─────────────────────────────────────────"

        # Build navigation options
        local -a nav_items=()
        nav_items+=("📋 [m] Menu")
        [[ $idx -gt 0 ]] && nav_items+=("⬅️  [p] Previous")
        [[ $idx -lt $last_idx ]] && nav_items+=("➡️  [n] Next")
        nav_items+=("✅ [c] Mark complete")
        nav_items+=("👋 [q] Quit")

        local action=""
        action=$(printf '%s\n' "${nav_items[@]}" | gum choose \
            --cursor.foreground "$ACFS_ACCENT" \
            --selected.foreground "$ACFS_SUCCESS" 2>/dev/null) || true

        # Handle empty action (Esc pressed or gum failed) -> return to menu
        if [[ -z "$action" ]]; then
            return 0
        fi

        case "$action" in
            *"[m]"*) return 0 ;;
            *"[p]"*)
                if [[ $idx -gt 0 ]]; then
                    if ! set_current $((idx - 1)); then
                        return 0
                    fi
                    show_lesson $((idx - 1))
                    return $?
                fi
                ;;
            *"[n]"*)
                if [[ $idx -lt $last_idx ]]; then
                    if ! set_current $((idx + 1)); then
                        return 0
                    fi
                    show_lesson $((idx + 1))
                    return $?
                fi
                ;;
            *"[c]"*)
                local next_idx
                if ! mark_completed "$idx"; then
                    return 0
                fi
                show_celebration "$idx"
                if all_lessons_complete; then
                    show_completion_certificate
                    return 0
                fi
                next_idx=$(get_current)
                if [[ ! "$next_idx" =~ ^[0-9]+$ ]] || (( next_idx < 0 || next_idx >= NUM_LESSONS )); then
                    next_idx=$(get_next_incomplete)
                fi
                if [[ "$next_idx" =~ ^[0-9]+$ ]] && (( next_idx != idx )); then
                    show_lesson "$next_idx"
                    return $?
                fi
                return 0
                ;;
            *"[q]"*) exit 0 ;;
            *) return 0 ;;  # Unknown action -> back to menu
        esac
    else
        if ! has_interactive_tty; then
            return 0
        fi

        echo -e "${DIM}─────────────────────────────────────────${NC}"

        # Navigation
        local nav_options="[m] Menu"
        if [[ $idx -gt 0 ]]; then
            nav_options+="  [p] Previous"
        fi
        if [[ $idx -lt $last_idx ]]; then
            nav_options+="  [n] Next"
        fi
        nav_options+="  [c] Mark complete  [q] Quit"

        echo -e "${DIM}$nav_options${NC}"
        echo ""

        while true; do
            read -rp "$(echo -e "${CYAN}Action:${NC} ")" action
            case "$action" in
                m|M) return 0 ;;
                p|P)
                    if [[ $idx -gt 0 ]]; then
                        if ! set_current $((idx - 1)); then
                            return 0
                        fi
                        show_lesson $((idx - 1))
                        return $?
                    fi
                    ;;
                n|N)
                    if [[ $idx -lt $last_idx ]]; then
                        if ! set_current $((idx + 1)); then
                            return 0
                        fi
                        show_lesson $((idx + 1))
                        return $?
                    fi
                    ;;
                c|C)
                    local next_idx
                    if ! mark_completed "$idx"; then
                        return 0
                    fi
                    show_celebration "$idx"
                    if all_lessons_complete; then
                        show_completion_certificate
                        return 0
                    fi
                    next_idx=$(get_current)
                    if [[ ! "$next_idx" =~ ^[0-9]+$ ]] || (( next_idx < 0 || next_idx >= NUM_LESSONS )); then
                        next_idx=$(get_next_incomplete)
                    fi
                    if [[ "$next_idx" =~ ^[0-9]+$ ]] && (( next_idx != idx )); then
                        show_lesson "$next_idx"
                        return $?
                    fi
                    return 0
                    ;;
                q|Q) exit 0 ;;
                "") ;;
                *) echo -e "${YELLOW}Invalid option. Use m/p/n/c/q${NC}" ;;
            esac
        done
    fi
}

# Show completion status
show_status() {
    print_header

    local completed_count=0 i
    for (( i = 0; i < NUM_LESSONS; i++ )); do
        if is_completed "$i"; then
            ((completed_count += 1))
        fi
    done

    if (( NUM_LESSONS == 0 )); then
        show_no_lessons_notice
        echo ""
        if has_gum && has_interactive_tty; then
            gum confirm --affirmative "Continue" --negative "" "Return to menu?" || true
        elif has_interactive_tty; then
            read -rp "Press Enter to continue..."
        fi
        return 0
    fi

    if has_gum; then
        # Styled progress display with gum
        local percent=$((completed_count * 100 / NUM_LESSONS))
        local filled=$((percent / 2))
        local empty=$((50 - filled))

        local bar=""
        for ((i = 0; i < filled; i++)); do bar+="█"; done
        for ((i = 0; i < empty; i++)); do bar+="░"; done

        gum style \
            --border rounded \
            --border-foreground "$ACFS_ACCENT" \
            --padding "1 2" \
            --margin "0 0 1 0" \
            "$(gum style --foreground "$ACFS_PINK" --bold "📊 Progress: $completed_count/$NUM_LESSONS lessons")

$(gum style --foreground "$ACFS_PRIMARY" "$bar") $(gum style --foreground "$ACFS_SUCCESS" --bold "$percent%")"

        # Lesson list with styled status
        echo ""
        for (( i = 0; i < NUM_LESSONS; i++ )); do
            local status_icon
            local status_color
            if is_completed "$i"; then
                status_icon="✓"
                status_color="$ACFS_SUCCESS"
            elif [[ "$i" == "$(get_current)" ]]; then
                status_icon="●"
                status_color="$ACFS_PRIMARY"
            else
                status_icon="○"
                status_color="$ACFS_MUTED"
            fi
            local lesson_number
            lesson_number="$(get_lesson_number "$i" || printf '%d' "$((i + 1))")"
            echo "  $(gum style --foreground "$status_color" "$status_icon") $(gum style --foreground "$ACFS_TEAL" "[${lesson_number}]") ${LESSON_TITLES[$i]}"
        done

        echo ""

        if all_lessons_complete; then
            gum style \
                --foreground "$ACFS_SUCCESS" \
                --bold \
                "🎉 All lessons complete! You're ready to fly!"
        else
            local next_idx
            next_idx=$(get_next_incomplete)
            local next_lesson_number
            next_lesson_number="$(get_lesson_number "$next_idx" || printf '%d' "$((next_idx + 1))")"
            echo "$(gum style --foreground "$ACFS_MUTED" "Next up:") $(gum style --foreground "$ACFS_PRIMARY" "Lesson ${next_lesson_number} - ${LESSON_TITLES[$next_idx]}")"
        fi

        echo ""
        if has_interactive_tty; then
            gum confirm --affirmative "Continue" --negative "" "Ready to continue?" || true
        fi
    else
        echo -e "${BOLD}Progress: $completed_count/$NUM_LESSONS lessons completed${NC}"
        echo ""

        # Progress bar (width based on lesson count)
        local filled=$((completed_count * 45 / NUM_LESSONS))
        local empty=$((45 - filled))
        local i
        printf '%s' "${GREEN}"
        for ((i = 0; i < filled; i++)); do printf '█'; done
        printf '%s' "${DIM}"
        for ((i = 0; i < empty; i++)); do printf '░'; done
        printf '%s' "${NC}"
        echo " $((completed_count * 100 / NUM_LESSONS))%"
        echo ""

        for (( i = 0; i < NUM_LESSONS; i++ )); do
            echo -e "  $(format_lesson "$i")"
        done

        echo ""

        if all_lessons_complete; then
            echo -e "${GREEN}${BOLD}All lessons complete! You're ready to fly!${NC}"
        else
            local next_idx
            next_idx=$(get_next_incomplete)
            local next_lesson_number
            next_lesson_number="$(get_lesson_number "$next_idx" || printf '%d' "$((next_idx + 1))")"
            echo -e "${CYAN}Next up: Lesson ${next_lesson_number} - ${LESSON_TITLES[$next_idx]}${NC}"
        fi

        echo ""
        if has_interactive_tty; then
            read -rp "Press Enter to continue..."
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main_menu() {
    if ! has_interactive_tty; then
        echo "Interactive menu requires a TTY. Run 'onboard <lesson-number>', 'onboard status', or 'onboard --help'." >&2
        return 1
    fi

    while true; do
        print_header

        local choice
        if has_gum_ui; then
            choice=$(show_menu_gum)
        else
            choice=$(show_menu_basic)
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            # Support dynamically discovered lesson counts instead of assuming
            # the menu will never exceed two digits.
            local idx=""
            idx="$(get_lesson_index_by_number "$((10#$choice))" || true)"
            if [[ -n "$idx" ]]; then
                if ! set_current "$idx"; then
                    continue
                fi
                show_lesson "$idx"
            else
                echo -e "${YELLOW}Invalid lesson number. Please try again.${NC}"
                sleep 1
            fi
            continue
        fi

        case "$choice" in
            a)
                show_auth_flow
                ;;
            r)
                if has_gum; then
                    if gum confirm "Reset all progress?"; then
                        reset_progress || continue
                    fi
                else
                    read -rp "Reset all progress? [y/N] " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        reset_progress || continue
                    fi
                fi
                ;;
            s)
                show_status
                ;;
            t)
                show_completion_certificate
                ;;
            q)
                echo -e "${GREEN}Happy coding!${NC}"
                exit 0
                ;;
            invalid)
                echo -e "${YELLOW}Invalid choice. Please try again.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Handle command line arguments
arg="${1:-}"

if [[ "$arg" =~ ^[0-9]+$ ]]; then
    idx="$(get_lesson_index_by_number "$((10#$arg))" || true)"
    if [[ -n "$idx" ]]; then
        init_progress
        if ! set_current "$idx"; then
            exit 1
        fi
        show_lesson "$idx"
        exit 0
    fi

    if (( NUM_LESSONS == 0 )); then
        echo "No lessons are available in $LESSONS_DIR"
    else
        echo "Lesson $arg was not found. Run 'onboard status' to see the available lesson numbers."
    fi
    exit 1
fi

case "$arg" in
    --cheatsheet|cheatsheet)
        shift || true
        cheatsheet_script=""
        for candidate in \
            "$HOME/.acfs/scripts/lib/cheatsheet.sh" \
            "$SCRIPT_DIR/../../scripts/lib/cheatsheet.sh" \
            "$SCRIPT_DIR/../scripts/lib/cheatsheet.sh"; do
            if [[ -f "$candidate" ]]; then
                cheatsheet_script="$candidate"
                break
            fi
        done

        if [[ -z "${cheatsheet_script:-}" ]]; then
            echo "Error: cheatsheet.sh not found" >&2
            echo "Re-run the ACFS installer or update to get the latest scripts." >&2
            exit 1
        fi

        exec bash "$cheatsheet_script" "$@"
        ;;
    reset|--reset)
        init_progress
        reset_progress
        ;;
    status|list|--status|--list)
        init_progress
        show_status
        ;;
    version|--version|-v)
        echo "onboard v$VERSION"
        ;;
    help|--help|-h)
        cat <<EOF
ACFS Onboarding Tutorial

Usage:
  onboard           Launch interactive menu
  onboard N         Jump to lesson number N from the lesson filenames
  onboard status    Show completion status
  onboard list      Alias for 'status'
  onboard --status  Alias for 'status'
  onboard --list    Alias for 'status'
  onboard reset     Reset all progress
  onboard --reset   Alias for 'reset'
  onboard help      Alias for '--help'
  onboard --cheatsheet [query]  Show ACFS command cheatsheet
  onboard version   Show version
  onboard --help    Show this help

Lessons:
$(if (( NUM_LESSONS == 0 )); then
    printf '  No lessons discovered in %s\n' "$LESSONS_DIR"
else
    for (( i = 0; i < NUM_LESSONS; i++ )); do
        printf '  %s - %s\n' "$(get_lesson_number "$i" || printf '%d' "$((i + 1))")" "${LESSON_TITLES[$i]}"
    done
fi)

Environment:
  ACFS_LESSONS_DIR   Path to lesson files (default: $LESSONS_DIR)
  ACFS_PROGRESS_FILE Path to progress file (default: $PROGRESS_FILE)
EOF
        ;;
    "")
        init_progress
        main_menu
        ;;
    *)
        echo "Unknown command: $arg"
        echo "Run 'onboard --help' for usage."
        exit 1
        ;;
 esac
