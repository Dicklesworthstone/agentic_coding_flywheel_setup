#!/usr/bin/env bash
# ============================================================
# ACFS Info Library
#
# Provides lightning-fast system and installation status display.
# Reads from state files only - NO verification checks (that's doctor's job).
#
# Usage:
#   acfs info            # Terminal output (default)
#   acfs info --json     # JSON output for scripting
#   acfs info --html     # Self-contained HTML page
#   acfs info --minimal  # Just essentials (IP, key commands)
#
# Design Philosophy:
#   - Speed: Must complete in <1 second
#   - Read-only: Never verify/test anything (doctor does that)
#   - Offline: No network calls required
#   - Fallback: Graceful degradation if data missing
#
# Related beads:
#   - agentic_coding_flywheel_setup-bags: FEATURE: acfs info Quick Reference Command
#   - agentic_coding_flywheel_setup-cxz3: TASK: Design acfs info output format
#   - agentic_coding_flywheel_setup-3dkg: TASK: Implement info.sh core data gathering
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_INFO_SH_LOADED:-}" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    exit 0
fi
_ACFS_INFO_SH_LOADED=1

# ACFS home directory
_INFO_DEFAULT_ACFS_HOME="$HOME/.acfs"
ACFS_HOME="${ACFS_HOME:-$_INFO_DEFAULT_ACFS_HOME}"
_INFO_SYSTEM_STATE_FILE="${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}"
_INFO_RESOLVED_ACFS_HOME=""

# Source output formatting library (for TOON support)
_INFO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_INFO_SCRIPT_DIR}/output.sh" ]]; then
    # shellcheck source=output.sh
    source "${_INFO_SCRIPT_DIR}/output.sh"
fi

# Global format options (set by argument parsing)
_INFO_OUTPUT_FORMAT=""
_INFO_SHOW_STATS=false

# ============================================================
# Color Constants (for terminal output)
# Respects NO_COLOR standard: https://no-color.org/
# Related: bd-39ye
# ============================================================
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_GREEN='\033[0;32m'
    C_CYAN='\033[0;36m'
    C_GRAY='\033[0;90m'
else
    C_RESET=''
    C_BOLD=''
    C_DIM=''
    C_GREEN=''
    C_CYAN=''
    C_GRAY=''
fi

# ============================================================
# Data Gathering Functions
# ============================================================
# Each function must:
#   - Complete in <100ms
#   - Never make network calls
#   - Return fallback value on error

# Get file modified time (unix epoch seconds)
info_get_file_mtime() {
    local path="$1"
    local mtime=""
    mtime="$(stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null || echo "")"
    [[ "$mtime" =~ ^[0-9]+$ ]] || return 1
    echo "$mtime"
}

info_home_for_user() {
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

info_read_target_user_from_state() {
    local state_file="${1:-$_INFO_SYSTEM_STATE_FILE}"
    local target_user=""

    [[ -f "$state_file" ]] || return 1

    if command -v jq &>/dev/null; then
        target_user=$(jq -r '.target_user // empty' "$state_file" 2>/dev/null || true)
    else
        target_user=$(sed -n 's/.*"target_user"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$state_file" 2>/dev/null | head -n 1)
    fi

    [[ -n "$target_user" ]] && [[ "$target_user" != "null" ]] || return 1
    echo "$target_user"
}

info_get_data_home() {
    if [[ -n "$_INFO_RESOLVED_ACFS_HOME" ]]; then
        echo "$_INFO_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ "$ACFS_HOME" != "$_INFO_DEFAULT_ACFS_HOME" ]]; then
        _INFO_RESOLVED_ACFS_HOME="$ACFS_HOME"
        echo "$_INFO_RESOLVED_ACFS_HOME"
        return 0
    fi

    local candidate=""
    local target_home=""
    local target_user=""

    if [[ -n "${SUDO_USER:-}" ]]; then
        target_home=$(info_home_for_user "$SUDO_USER" || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && [[ -e "$candidate/state.json" || -e "$candidate/onboard_progress.json" || -d "$candidate/onboard" ]]; then
            _INFO_RESOLVED_ACFS_HOME="$candidate"
            echo "$_INFO_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    target_user=$(info_read_target_user_from_state || true)
    if [[ -n "$target_user" ]]; then
        target_home=$(info_home_for_user "$target_user" || true)
        candidate="${target_home}/.acfs"
        if [[ -n "$target_home" ]] && [[ -e "$candidate/state.json" || -e "$candidate/onboard_progress.json" || -d "$candidate/onboard" ]]; then
            _INFO_RESOLVED_ACFS_HOME="$candidate"
            echo "$_INFO_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    _INFO_RESOLVED_ACFS_HOME="$ACFS_HOME"
    echo "$_INFO_RESOLVED_ACFS_HOME"
}

info_get_install_state_file() {
    local data_home
    data_home=$(info_get_data_home)

    if [[ -f "$data_home/state.json" ]]; then
        echo "$data_home/state.json"
        return 0
    fi

    if [[ -f "$_INFO_SYSTEM_STATE_FILE" ]]; then
        echo "$_INFO_SYSTEM_STATE_FILE"
        return 0
    fi

    echo "$data_home/state.json"
}

# Get system hostname
info_get_hostname() {
    cat /etc/hostname 2>/dev/null || hostname 2>/dev/null || echo "unknown"
}

# Get primary IP address (cached or live)
info_get_ip() {
    # Try cached value first
    local data_home
    data_home=$(info_get_data_home)
    local cache_file="${data_home}/cache/ip_address"
    local now
    now="$(date +%s 2>/dev/null || echo "")"

    if [[ -f "$cache_file" ]] && [[ "$now" =~ ^[0-9]+$ ]]; then
        local cache_mtime
        if cache_mtime="$(info_get_file_mtime "$cache_file")" && [[ $cache_mtime -gt $((now - 3600)) ]]; then
            local cached_ip=""
            cached_ip="$(head -1 "$cache_file" 2>/dev/null | tr -d '[:space:]')"
            if [[ -n "$cached_ip" ]] && [[ "$cached_ip" != "unknown" ]]; then
                echo "$cached_ip"
                return 0
            fi
        fi
    fi

    # Get live value
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "$ip" ]]; then
        ip=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}')
    fi
    if [[ -z "$ip" ]]; then
        ip="unknown"
    fi

    # Cache successful lookups, but do not pin transient failures for an hour.
    if [[ "$ip" != "unknown" ]]; then
        mkdir -p "${data_home}/cache" 2>/dev/null
        echo "$ip" > "$cache_file" 2>/dev/null
    fi

    echo "$ip"
}

# Get human-readable uptime
info_get_uptime() {
    uptime -p 2>/dev/null | sed 's/^up //' || echo "unknown"
}

# Get OS version info
info_get_os_version() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        echo "${VERSION_ID:-unknown}"
    else
        echo "unknown"
    fi
}

# Get OS codename
info_get_os_codename() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        echo "${VERSION_CODENAME:-unknown}"
    else
        echo "unknown"
    fi
}

# Get installation state from state.json
info_get_install_state() {
    local state_file
    state_file="$(info_get_install_state_file)"
    [[ -f "$state_file" ]] || { echo '{}'; return 0; }

    if command -v jq &>/dev/null; then
        jq -c '.' "$state_file" 2>/dev/null || cat "$state_file" 2>/dev/null || echo '{}'
        return 0
    fi

    cat "$state_file" 2>/dev/null || echo '{}'
}

# Get completed phases count
info_get_completed_phases() {
    local state
    state=$(info_get_install_state)
    if command -v jq &>/dev/null; then
        echo "$state" | jq -r '.completed_phases | length // 0'
    else
        echo "0"
    fi
}

# Get total phases count
info_get_total_phases() {
    echo "9"  # Fixed in ACFS
}

# Get skipped tools
info_get_skipped_tools_json() {
    local state_file
    state_file="$(info_get_install_state_file)"
    [[ -f "$state_file" ]] || { echo '[]'; return 0; }

    if command -v jq &>/dev/null; then
        jq -c '.skipped_tools // []' "$state_file" 2>/dev/null || echo '[]'
        return 0
    fi

    if command -v python3 &>/dev/null; then
        python3 - "$state_file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
    skipped = data.get("skipped_tools", [])
    if isinstance(skipped, dict):
        skipped = list(skipped.keys())
    elif not isinstance(skipped, list):
        skipped = []
    print(json.dumps([str(item) for item in skipped if item is not None]))
except Exception:
    print("[]")
PY
        return 0
    fi

    local raw
    raw=$(sed -n 's/.*"skipped_tools"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$state_file" 2>/dev/null | head -n1)
    if [[ -z "$raw" ]]; then
        echo '[]'
    else
        printf '[%s]\n' "$raw"
    fi
}

info_get_skipped_tools() {
    local skipped_tools_json
    skipped_tools_json="$(info_get_skipped_tools_json)"

    if command -v jq &>/dev/null; then
        echo "$skipped_tools_json" | jq -r 'join(", ")'
        return 0
    fi

    if command -v python3 &>/dev/null; then
        python3 - "$skipped_tools_json" <<'PY'
import json
import sys

try:
    skipped = json.loads(sys.argv[1])
    if isinstance(skipped, dict):
        skipped = list(skipped.keys())
    elif not isinstance(skipped, list):
        skipped = []
    print(", ".join(str(item) for item in skipped if item is not None))
except Exception:
    print("")
PY
        return 0
    fi

    printf '%s\n' "$skipped_tools_json" | sed -e 's/^\[//' -e 's/\]$//' -e 's/"//g' -e 's/, */, /g'
}

# Get installation date
info_get_install_date() {
    local state
    state=$(info_get_install_state)
    if command -v jq &>/dev/null; then
        local date_str
        date_str=$(echo "$state" | jq -r '.started_at // empty')
        if [[ -n "$date_str" ]]; then
            # Try to format nicely, fall back to raw
            date -d "$date_str" "+%Y-%m-%d" 2>/dev/null || echo "${date_str%%T*}"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# Get onboard progress
info_get_onboard_lessons_dir() {
    local data_home
    data_home=$(info_get_data_home)
    echo "${ACFS_LESSONS_DIR:-${data_home}/onboard/lessons}"
}

info_get_onboard_progress_file() {
    local data_home
    data_home=$(info_get_data_home)
    echo "${ACFS_PROGRESS_FILE:-${data_home}/onboard_progress.json}"
}

info_get_lesson_file_by_index() {
    local index="${1:-}"
    local lessons_dir
    lessons_dir=$(info_get_onboard_lessons_dir)

    if [[ ! "$index" =~ ^[0-9]+$ ]] || [[ ! -d "$lessons_dir" ]]; then
        return 1
    fi

    find "$lessons_dir" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null \
        | LC_ALL=C sort \
        | sed -n "$((index + 1))p"
}

info_get_onboard_progress() {
    local progress_file
    progress_file=$(info_get_onboard_progress_file)
    local total
    total=$(info_get_lessons_total)
    if [[ -f "$progress_file" ]]; then
        cat "$progress_file"
    else
        printf '{"completed": [], "total": %s}\n' "$total"
    fi
}

info_get_onboard_progress_compact() {
    local progress_file
    progress_file=$(info_get_onboard_progress_file)

    [[ -f "$progress_file" ]] || return 1
    tr -d '[:space:]' < "$progress_file" 2>/dev/null
}

info_get_onboard_completed_csv() {
    local compact
    compact="$(info_get_onboard_progress_compact || true)"
    printf '%s\n' "$compact" | sed -n 's/.*"completed":\[\([^]]*\)\].*/\1/p' | head -1
}

# Get onboard lessons completed count
info_get_lessons_completed() {
    local progress
    progress=$(info_get_onboard_progress)
    if command -v jq &>/dev/null; then
        echo "$progress" | jq -r '(.completed // []) | length'
    else
        local completed_raw
        completed_raw="$(info_get_onboard_completed_csv)"
        if [[ -z "$completed_raw" ]]; then
            echo "0"
        else
            echo "$completed_raw" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | wc -l | awk '{print $1}'
        fi
    fi
}

# Get total lessons
info_get_lessons_total() {
    local lessons_dir
    lessons_dir=$(info_get_onboard_lessons_dir)

    if [[ ! -d "$lessons_dir" ]]; then
        echo "0"
        return 0
    fi

    find "$lessons_dir" -maxdepth 1 -type f -name '*.md' -print 2>/dev/null \
        | LC_ALL=C sort \
        | wc -l \
        | awk '{print $1}'
}

# Map an onboard lesson index to its discovered title.
info_get_lesson_title() {
    local lesson_path
    local title

    lesson_path=$(info_get_lesson_file_by_index "${1:-}") || {
        echo "unknown"
        return 0
    }

    title=$(grep -m1 '^# ' "$lesson_path" 2>/dev/null | sed 's/^# //')
    if [[ -n "$title" ]]; then
        echo "$title"
    else
        basename "${lesson_path%.md}"
    fi
}

# Get next lesson
info_get_next_lesson() {
    local progress
    local total
    progress=$(info_get_onboard_progress)
    total=$(info_get_lessons_total)

    if [[ ! "$total" =~ ^[0-9]+$ ]] || [[ "$total" -le 0 ]]; then
        echo "No lessons available"
        return 0
    fi

    if command -v jq &>/dev/null; then
        local completed_count
        completed_count=$(echo "$progress" | jq -r '(.completed // []) | length' 2>/dev/null || echo "0")

        if [[ "$completed_count" -ge "$total" ]]; then
            echo "All complete!"
            return 0
        fi

        local next_idx
        next_idx=$(echo "$progress" | jq -r --argjson total "$total" '(.completed // []) as $c | ([range(0;$total) as $i | select(($c | index($i)) == null) | $i] | first // 0)' 2>/dev/null || echo "0")
        [[ "$next_idx" =~ ^[0-9]+$ ]] || next_idx=0

        local title
        title=$(info_get_lesson_title "$next_idx")
        echo "Lesson $((next_idx + 1)) - $title"
    else
        local completed_count
        completed_count=$(info_get_lessons_completed)

        if [[ "$completed_count" =~ ^[0-9]+$ ]] && [[ "$completed_count" -ge "$total" ]]; then
            echo "All complete!"
            return 0
        fi

        local completed_csv
        completed_csv="$(info_get_onboard_completed_csv | tr -d ' ')"

        local next_idx=0
        local idx
        for ((idx = 0; idx < total; idx++)); do
            if [[ ",${completed_csv}," != *",$idx,"* ]]; then
                next_idx="$idx"
                break
            fi
        done

        local title
        title=$(info_get_lesson_title "$next_idx")
        echo "Lesson $((next_idx + 1)) - $title"
    fi
}

# ============================================================
# Quick Commands Data
# ============================================================
# Top 8 most useful commands for quick reference

info_get_quick_commands() {
    cat <<'EOF'
cc|Launch Claude Code
cod|Launch Codex CLI
gmi|Launch Gemini CLI
ntm new X|Create tmux session
ntm attach X|Resume session
lazygit|Visual git interface
rg "term"|Search code
z folder|Jump to folder
EOF
}

# ============================================================
# Installed Tools Detection
# ============================================================

info_get_installed_tools_summary() {
    local shell_ok lang_ok agents_ok stack_ok

    # Shell tools
    shell_ok="○"
    if command -v zsh &>/dev/null && [[ -d "$HOME/.oh-my-zsh" ]]; then
        shell_ok="✓"
    fi

    # Languages
    lang_ok="○"
    local lang_count=0
    command -v bun &>/dev/null && lang_count=$((lang_count + 1))
    command -v uv &>/dev/null && lang_count=$((lang_count + 1))
    command -v rustc &>/dev/null && lang_count=$((lang_count + 1))
    command -v go &>/dev/null && lang_count=$((lang_count + 1))
    [[ $lang_count -ge 3 ]] && lang_ok="✓"

    # Agents
    agents_ok="○"
    local agent_count=0
    command -v claude &>/dev/null && agent_count=$((agent_count + 1))
    command -v codex &>/dev/null && agent_count=$((agent_count + 1))
    command -v gemini &>/dev/null && agent_count=$((agent_count + 1))
    [[ $agent_count -ge 2 ]] && agents_ok="✓"

    # Stack tools
    stack_ok="○"
    command -v ntm &>/dev/null && stack_ok="✓"

    echo "shell:$shell_ok|lang:$lang_ok|agents:$agents_ok|stack:$stack_ok"
}

info_render_onboard_bar() {
    local completed="${1:-0}"
    local total="${2:-0}"
    local width="${3:-24}"
    local filled=0
    local empty="$width"

    [[ "$completed" =~ ^[0-9]+$ ]] || completed=0
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    [[ "$width" =~ ^[0-9]+$ ]] || width=24

    if (( total > 0 )); then
        (( completed < 0 )) && completed=0
        (( completed > total )) && completed="$total"
        filled=$((completed * width / total))
        if (( completed > 0 && filled == 0 )); then
            filled=1
        fi
        (( filled > width )) && filled="$width"
        empty=$((width - filled))
    fi

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    printf '%s' "$bar"
}

# ============================================================
# Terminal Output Renderer
# ============================================================

info_render_terminal() {
    local hostname ip uptime os_version os_codename
    hostname=$(info_get_hostname)
    ip=$(info_get_ip)
    uptime=$(info_get_uptime)
    os_version=$(info_get_os_version)
    os_codename=$(info_get_os_codename)

    local install_date skipped_tools
    install_date=$(info_get_install_date)
    skipped_tools=$(info_get_skipped_tools)

    local lessons_completed lessons_total next_lesson
    lessons_completed=$(info_get_lessons_completed)
    lessons_total=$(info_get_lessons_total)
    next_lesson=$(info_get_next_lesson)

    local tools_summary
    tools_summary=$(info_get_installed_tools_summary)

    # Header
    echo -e "${C_CYAN}╭─────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}  ${C_BOLD}ACFS Environment Info${C_RESET}                                      ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}╰─────────────────────────────────────────────────────────────╯${C_RESET}"
    echo ""

    # System section
    echo -e "${C_BOLD}System${C_RESET}"
    printf "  %-12s ${C_GREEN}%s${C_RESET}\n" "Hostname:" "$hostname"
    printf "  %-12s ${C_GREEN}%s${C_RESET}\n" "IP Address:" "$ip"
    printf "  %-12s %s\n" "Uptime:" "$uptime"
    printf "  %-12s Ubuntu %s (%s)\n" "OS:" "$os_version" "$os_codename"
    echo ""

    # Installed Tools section
    echo -e "${C_BOLD}Installed Tools${C_RESET}"

    # Parse tools summary
    local shell_status lang_status agents_status stack_status
    IFS='|' read -r shell_status lang_status agents_status stack_status <<< "$tools_summary"

    local shell_icon="${shell_status#*:}"
    local lang_icon="${lang_status#*:}"
    local agents_icon="${agents_status#*:}"
    local stack_icon="${stack_status#*:}"

    # Color the icons
    [[ "$shell_icon" == "✓" ]] && shell_icon="${C_GREEN}✓${C_RESET}" || shell_icon="${C_GRAY}○${C_RESET}"
    [[ "$lang_icon" == "✓" ]] && lang_icon="${C_GREEN}✓${C_RESET}" || lang_icon="${C_GRAY}○${C_RESET}"
    [[ "$agents_icon" == "✓" ]] && agents_icon="${C_GREEN}✓${C_RESET}" || agents_icon="${C_GRAY}○${C_RESET}"
    [[ "$stack_icon" == "✓" ]] && stack_icon="${C_GREEN}✓${C_RESET}" || stack_icon="${C_GRAY}○${C_RESET}"

    echo -e "  $shell_icon ${C_DIM}Shell:${C_RESET}     zsh + oh-my-zsh + powerlevel10k"
    echo -e "  $lang_icon ${C_DIM}Languages:${C_RESET} bun, uv, rust, go"
    echo -e "  $agents_icon ${C_DIM}Agents:${C_RESET}    claude, codex, gemini"
    echo -e "  $stack_icon ${C_DIM}Stack:${C_RESET}     ntm, bv, lazygit"

    if [[ -n "$skipped_tools" ]]; then
        echo -e "  ${C_GRAY}○ Skipped:   $skipped_tools${C_RESET}"
    fi
    echo ""

    # Quick Commands section
    echo -e "${C_BOLD}Quick Commands${C_RESET}"
    while IFS='|' read -r cmd desc; do
        printf "  ${C_CYAN}%-14s${C_RESET} %s\n" "$cmd" "$desc"
    done < <(info_get_quick_commands)
    echo ""

    # Onboard Progress section
    echo -e "${C_BOLD}Onboard Progress${C_RESET}"
    if [[ "$lessons_total" =~ ^[0-9]+$ ]] && (( lessons_total == 0 )); then
        echo -e "  No lessons available"
        echo -e "  ${C_DIM}Re-run the installer or set ACFS_LESSONS_DIR to a directory with onboarding lessons.${C_RESET}"
    else
        local percent=0
        local display_completed="$lessons_completed"
        if [[ "$lessons_completed" =~ ^[0-9]+$ ]] && [[ "$lessons_total" =~ ^[0-9]+$ ]] && (( lessons_total > 0 )); then
            if (( lessons_completed > lessons_total )); then
                display_completed="$lessons_total"
            fi
            percent=$((display_completed * 100 / lessons_total))
        fi
        local bar=""
        bar=$(info_render_onboard_bar "$display_completed" "$lessons_total" 24)

        echo -e "  ${C_GREEN}$bar${C_RESET} ${display_completed}/${lessons_total} lessons (${percent}%)"
        if [[ "$lessons_completed" -lt "$lessons_total" ]]; then
            echo -e "  ${C_DIM}Next:${C_RESET} $next_lesson"
        fi
    fi
    echo ""

    # Footer
    echo -e "${C_DIM}Run 'acfs doctor' for health verification${C_RESET}"
    if [[ "$lessons_total" =~ ^[0-9]+$ ]] && (( lessons_total > 0 )); then
        echo -e "${C_DIM}Run 'onboard' to continue learning${C_RESET}"
    fi
}

# ============================================================
# Minimal Output Renderer
# ============================================================

info_render_minimal() {
    local ip hostname
    ip=$(info_get_ip)
    hostname=$(info_get_hostname)

    echo "ACFS @ $hostname ($ip)"
    echo ""
    echo "Quick commands: cc (Claude), cod (Codex), ntm (sessions)"
    echo "Run 'acfs info' for full details"
}

# ============================================================
# JSON Output Renderer
# ============================================================

info_render_json() {
    local hostname ip uptime os_version os_codename
    hostname=$(info_get_hostname)
    ip=$(info_get_ip)
    uptime=$(info_get_uptime)
    os_version=$(info_get_os_version)
    os_codename=$(info_get_os_codename)

    local install_date
    install_date=$(info_get_install_date)
    local skipped_tools_json="[]"
    skipped_tools_json="$(info_get_skipped_tools_json)"

    local lessons_completed lessons_total next_lesson
    lessons_completed=$(info_get_lessons_completed)
    lessons_total=$(info_get_lessons_total)
    next_lesson=$(info_get_next_lesson)

    # Build JSON manually for compatibility (jq might not be available)
    # Ensure all string values are JSON-escaped so output is always valid JSON.
    _info_json_escape() {
        local s="$1"
        s="${s//\\/\\\\}"      # \ -> \\
        s="${s//\"/\\\"}"      # " -> \"
        s="${s//$'\n'/\\n}"    # newline -> \n
        s="${s//$'\r'/\\r}"    # carriage return -> \r
        s="${s//$'\t'/\\t}"    # tab -> \t
        printf '%s' "$s"
    }

    [[ "$lessons_completed" =~ ^[0-9]+$ ]] || lessons_completed=0
    [[ "$lessons_total" =~ ^[0-9]+$ ]] || lessons_total=0

    local hostname_json ip_json uptime_json os_version_json os_codename_json
    hostname_json="$(_info_json_escape "$hostname")"
    ip_json="$(_info_json_escape "$ip")"
    uptime_json="$(_info_json_escape "$uptime")"
    os_version_json="$(_info_json_escape "$os_version")"
    os_codename_json="$(_info_json_escape "$os_codename")"

    local install_date_json next_lesson_json
    install_date_json="$(_info_json_escape "$install_date")"
    next_lesson_json="$(_info_json_escape "$next_lesson")"

    local json_output
    json_output=$(cat <<EOF
{
  "system": {
    "hostname": "$hostname_json",
    "ip": "$ip_json",
    "uptime": "$uptime_json",
    "os": {
      "version": "$os_version_json",
      "codename": "$os_codename_json"
    }
  },
  "installation": {
    "date": "$install_date_json",
    "skipped_tools": $skipped_tools_json
  },
  "onboard": {
    "lessons_completed": $lessons_completed,
    "total_lessons": $lessons_total,
    "next_lesson": "$next_lesson_json"
  },
  "quick_commands": [
    {"cmd": "cc", "desc": "Launch Claude Code"},
    {"cmd": "cod", "desc": "Launch Codex CLI"},
    {"cmd": "gmi", "desc": "Launch Gemini CLI"},
    {"cmd": "ntm new X", "desc": "Create tmux session"},
    {"cmd": "ntm attach X", "desc": "Resume session"},
    {"cmd": "lazygit", "desc": "Visual git interface"},
    {"cmd": "rg term", "desc": "Search code"},
    {"cmd": "z folder", "desc": "Jump to folder"}
  ]
}
EOF
)

    # Use output formatting library if available
    if type -t acfs_format_output &>/dev/null; then
        local resolved_format
        resolved_format=$(acfs_resolve_format "$_INFO_OUTPUT_FORMAT")
        acfs_format_output "$json_output" "$resolved_format" "$_INFO_SHOW_STATS"
    else
        # Fallback: direct JSON output
        printf '%s\n' "$json_output"
    fi
}

# ============================================================
# HTML Output Renderer
# ============================================================

info_render_html() {
    local hostname ip uptime os_version os_codename
    hostname=$(info_get_hostname)
    ip=$(info_get_ip)
    uptime=$(info_get_uptime)
    os_version=$(info_get_os_version)
    os_codename=$(info_get_os_codename)

    # Escape values for safe HTML rendering (prevent broken markup if hostname/etc contain
    # special characters). This output may be served via `acfs dashboard serve`.
    _info_html_escape() {
        local s="$1"
        s="${s//&/&amp;}"
        s="${s//</&lt;}"
        s="${s//>/&gt;}"
        s="${s//\"/&quot;}"
        s="${s//\'/&#39;}"
        printf '%s' "$s"
    }

    local hostname_html ip_html uptime_html os_version_html os_codename_html
    hostname_html="$(_info_html_escape "$hostname")"
    ip_html="$(_info_html_escape "$ip")"
    uptime_html="$(_info_html_escape "$uptime")"
    os_version_html="$(_info_html_escape "$os_version")"
    os_codename_html="$(_info_html_escape "$os_codename")"

    local lessons_completed lessons_total
    lessons_completed=$(info_get_lessons_completed)
    lessons_total=$(info_get_lessons_total)
    local percent=0
    local display_completed="$lessons_completed"
    if [[ "$lessons_completed" =~ ^[0-9]+$ ]] && [[ "$lessons_total" =~ ^[0-9]+$ ]] && (( lessons_total > 0 )); then
        if (( lessons_completed > lessons_total )); then
            display_completed="$lessons_total"
        fi
        percent=$((display_completed * 100 / lessons_total))
    fi

    local onboard_card
    if [[ "$lessons_total" =~ ^[0-9]+$ ]] && (( lessons_total == 0 )); then
        onboard_card=$(cat <<'EOF'
        <div class="card">
            <h2>Onboard Progress</h2>
            <p class="label">No lessons available.</p>
            <p class="label">Re-run the installer or set ACFS_LESSONS_DIR to a directory with onboarding lessons.</p>
        </div>
EOF
)
    else
        onboard_card=$(cat <<EOF
        <div class="card">
            <h2>Onboard Progress</h2>
            <div class="progress-bar">
                <div class="progress-fill">${display_completed}/${lessons_total}</div>
            </div>
        </div>
EOF
)
    fi

    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ACFS Dashboard - $hostname_html</title>
    <style>
        :root {
            --bg: #1e1e2e;
            --surface: #313244;
            --text: #cdd6f4;
            --subtext: #a6adc8;
            --green: #a6e3a1;
            --cyan: #89dceb;
            --yellow: #f9e2af;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg);
            color: var(--text);
            padding: 2rem;
            line-height: 1.6;
        }
        .container { max-width: 800px; margin: 0 auto; }
        h1 { color: var(--cyan); margin-bottom: 1.5rem; }
        h2 { color: var(--text); font-size: 1.1rem; margin: 1.5rem 0 0.75rem; }
        .card {
            background: var(--surface);
            border-radius: 12px;
            padding: 1.5rem;
            margin-bottom: 1rem;
        }
        .grid { display: grid; grid-template-columns: 120px 1fr; gap: 0.5rem; }
        .label { color: var(--subtext); }
        .value { color: var(--green); }
        .cmd { font-family: monospace; color: var(--cyan); }
        .progress-bar {
            background: var(--bg);
            border-radius: 8px;
            height: 24px;
            overflow: hidden;
            margin: 0.5rem 0;
        }
        .progress-fill {
            background: linear-gradient(90deg, var(--green), var(--cyan));
            height: 100%;
            width: ${percent}%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 0.8rem;
            font-weight: bold;
        }
        .footer { margin-top: 2rem; color: var(--subtext); font-size: 0.9rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>ACFS Dashboard</h1>

        <div class="card">
            <h2>System</h2>
            <div class="grid">
                <span class="label">Hostname</span><span class="value">$hostname_html</span>
                <span class="label">IP Address</span><span class="value">$ip_html</span>
                <span class="label">Uptime</span><span>$uptime_html</span>
                <span class="label">OS</span><span>Ubuntu $os_version_html ($os_codename_html)</span>
            </div>
        </div>

        <div class="card">
            <h2>Quick Commands</h2>
            <div class="grid">
                <span class="cmd">cc</span><span>Launch Claude Code</span>
                <span class="cmd">cod</span><span>Launch Codex CLI</span>
                <span class="cmd">ntm new X</span><span>Create tmux session</span>
                <span class="cmd">lazygit</span><span>Visual git interface</span>
            </div>
        </div>

$onboard_card

        <div class="footer">
            Generated: $(date -Iseconds)<br>
            Run <code>acfs doctor</code> for health verification
        </div>
    </div>
</body>
</html>
EOF
}

# ============================================================
# Main Entry Point
# ============================================================

info_main() {
    local output_mode="terminal"
    _INFO_OUTPUT_FORMAT=""
    _INFO_SHOW_STATS=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json|-j)
                output_mode="json"
                ;;
            --format|-f)
                shift
                if [[ -z "${1:-}" || "$1" == -* ]]; then
                    echo "Error: --format requires a value (json or toon)" >&2
                    return 1
                fi
                _INFO_OUTPUT_FORMAT="$1"
                if [[ "$_INFO_OUTPUT_FORMAT" != "json" && "$_INFO_OUTPUT_FORMAT" != "toon" ]]; then
                    echo "Error: invalid format '$_INFO_OUTPUT_FORMAT' (expected json or toon)" >&2
                    return 1
                fi
                output_mode="json"  # --format implies structured output
                ;;
            --format=*)
                _INFO_OUTPUT_FORMAT="${1#*=}"
                if [[ -z "$_INFO_OUTPUT_FORMAT" ]]; then
                    echo "Error: --format requires a value (json or toon)" >&2
                    return 1
                fi
                if [[ "$_INFO_OUTPUT_FORMAT" != "json" && "$_INFO_OUTPUT_FORMAT" != "toon" ]]; then
                    echo "Error: invalid format '$_INFO_OUTPUT_FORMAT' (expected json or toon)" >&2
                    return 1
                fi
                output_mode="json"
                ;;
            --toon|-t)
                _INFO_OUTPUT_FORMAT="toon"
                output_mode="json"
                ;;
            --stats)
                _INFO_SHOW_STATS=true
                ;;
            --html|-H)
                output_mode="html"
                ;;
            --minimal|-m)
                output_mode="minimal"
                ;;
            --help|-h)
                echo "Usage: acfs info [OPTIONS]"
                echo ""
                echo "Display ACFS environment information."
                echo ""
                echo "Options:"
                echo "  --json, -j         Output as JSON"
                echo "  --format <fmt>     Output format: json or toon (env: ACFS_OUTPUT_FORMAT, TOON_DEFAULT_FORMAT)"
                echo "  --toon, -t         Shorthand for --format toon"
                echo "  --stats            Show token savings statistics (JSON vs TOON bytes)"
                echo "  --html, -H         Output as self-contained HTML"
                echo "  --minimal, -m      Show only essentials"
                echo "  --help, -h         Show this help"
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Run 'acfs info --help' for usage" >&2
                return 1
                ;;
        esac
        shift
    done

    # Render based on output mode
    case "$output_mode" in
        json)
            info_render_json
            ;;
        html)
            info_render_html
            ;;
        minimal)
            info_render_minimal
            ;;
        terminal)
            info_render_terminal
            ;;
    esac
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    info_main "$@"
fi
