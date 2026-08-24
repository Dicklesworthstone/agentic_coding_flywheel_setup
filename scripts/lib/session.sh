#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Session Export Library
# Defines schema and validation for agent session exports
# ============================================================
#
# Part of EPIC: Agent Session Sharing and Replay (0sb)
# See bead c61 for design decisions.
#
# ============================================================
# SESSION EXPORT SCHEMA (TypeScript Interface)
# ============================================================
#
# Schema lives inline per AGENTS.md guidance (no separate schema file).
# Version field allows future evolution.
#
# ```typescript
# interface SessionExport {
#     schema_version: 1;              // Always 1 for this version
#     exported_at: string;            // ISO8601 timestamp
#     session_id: string;             // Unique session identifier
#     agent: "claude-code" | "codex" | "gemini";
#     model: string;                  // e.g., "opus-4.5", "gpt-5.2-codex"
#     summary: string;                // Brief description of what happened
#     duration_minutes: number;       // Session length
#     stats: {
#         turns: number;              // Conversation turns
#         files_created: number;
#         files_modified: number;
#         commands_run: number;
#     };
#     outcomes: Array<{
#         type: "file_created" | "file_modified" | "command_run";
#         path?: string;              // For file operations
#         description: string;
#     }>;
#     key_prompts: string[];          // Notable prompts for learning
#     sanitized_transcript: Array<{
#         role: "user" | "assistant";
#         content: string;            // Post-sanitization
#         timestamp: string;          // ISO8601
#     }>;
# }
# ```
#
# DESIGN DECISIONS:
# - Schema versioned for evolution (schema_version: 1)
# - Fields designed for post-sanitization data (no raw secrets)
# - Focused on value: outcomes show what happened, key_prompts show how
# - Not a raw dump - curated for learning and replay
#
# ============================================================
# CASS (Coding Agent Session Search) API REFERENCE
# ============================================================
#
# CASS is the backend for session discovery and export. See bead eli for research.
#
# Version Info:
#   API Version: 1, Contract Version: 1, Crate: 0.2.0+
#
# Supported Connectors (agents):
#   claude_code, codex, gemini, cursor, amp, cline, aider, opencode, chatgpt, pi_agent
#
# Key Commands:
#   cass stats --json              # Session counts by agent/workspace
#   cass search "query" --json     # Full-text search with JSON output
#   cass export <path> --format json  # Export session to JSON array
#   cass status --json             # Health check with index freshness
#   cass capabilities --json       # Feature/connector discovery
#
# CASS Export JSON Structure (per message):
#   {
#     "agentId": "abc123",           // Short session identifier
#     "sessionId": "uuid",           // Full session UUID
#     "cwd": "/path/to/project",     // Working directory
#     "gitBranch": "main",           // Git branch (optional)
#     "timestamp": "ISO8601",        // Message timestamp
#     "type": "user|assistant",      // Message type
#     "uuid": "message-uuid",        // Message UUID
#     "parentUuid": "uuid|null",     // For threading
#     "message": {
#       "role": "user|assistant",
#       "content": "...",            // String or array of content blocks
#       "model": "claude-opus-4-5",  // For assistant messages
#       "usage": {...}               // Token usage stats
#     }
#   }
#
# Limitations (see bead eli):
#   - No direct "list sessions" CLI - use `cass search "*" --limit 100`
#   - CASS indexes JSONL files from agent data dirs, not a sessions table
#   - Export requires knowing the session file path
#   - Use stats/search to discover sessions, then export specific ones
#
# Session File Locations:
#   Claude Code: ~/.claude/projects/<project>/agent-*.jsonl
#   Codex: ~/.codex/sessions/<year>/<month>/<day>/*.jsonl
#   Gemini: ~/.gemini/tmp/<hash>/session.jsonl
#
# ============================================================

# Source logging if not already loaded
if [[ -z "${_ACFS_LOGGING_SH_LOADED:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=logging.sh
    source "${SCRIPT_DIR}/logging.sh" 2>/dev/null || true
fi

# ============================================================
# VALIDATION
# ============================================================

readonly ACFS_SESSION_ID_MAX_LENGTH=128

acfs_session_validate_id() {
    local session_id="${1:-}"
    local label="${2:-Session ID}"

    if [[ -z "$session_id" ]] || [[ ${#session_id} -gt $ACFS_SESSION_ID_MAX_LENGTH ]] ||
        [[ ! "$session_id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
        log_error "$label must be 1-${ACFS_SESSION_ID_MAX_LENGTH} characters using only letters, digits, '_' or '-'"
        return 1
    fi

    return 0
}

acfs_session_system_binary_path() {
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

acfs_session_jq() {
    local jq_bin=""

    jq_bin="$(acfs_session_system_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        log_error "jq is required for session operations but not installed"
        return 1
    fi

    "$jq_bin" "$@"
}

# Validate a session export JSON file against the schema
# Usage: validate_session_export "/path/to/export.json"
# Returns: 0 on success, 1 on validation failure
validate_session_export() {
    local file="$1"

    # Check file exists
    if [[ ! -f "$file" ]]; then
        log_error "Session export file not found: $file"
        return 1
    fi

    # Check it's valid JSON
    if ! acfs_session_jq -e . "$file" >/dev/null 2>&1; then
        log_error "Invalid JSON in session export: $file"
        return 1
    fi

    # Check required top-level fields exist and contain usable values
    if ! acfs_session_jq -e '
        (.schema_version != null)
        and (.session_id | type == "string" and test("\\S"))
        and (.agent | type == "string" and test("\\S"))
    ' "$file" >/dev/null 2>&1; then
        log_error "Invalid session export: missing required fields (schema_version, session_id, agent)"
        return 1
    fi

    local session_id
    session_id="$(acfs_session_jq -r '.session_id' "$file")" || {
        log_error "Invalid session export: unable to read session_id"
        return 1
    }
    if ! acfs_session_validate_id "$session_id" "Session export ID"; then
        return 1
    fi

    # Check schema version compatibility
    local version
    version=$(acfs_session_jq -r '.schema_version' "$file")
    if [[ "$version" != "1" ]]; then
        log_warn "Session schema version $version may not be fully compatible (expected: 1)"
    fi

    # Validate agent field is one of the known agents
    local agent
    agent=$(acfs_session_jq -r '.agent' "$file")
    case "$agent" in
        claude-code|codex|gemini)
            ;;
        *)
            log_warn "Unknown agent type: $agent (expected: claude-code, codex, or gemini)"
            ;;
    esac

    # Validate stats object exists and has expected fields
    if ! acfs_session_jq -e '.stats.turns != null' "$file" >/dev/null 2>&1; then
        log_warn "Session export missing stats.turns field"
    fi

    return 0
}

# Get schema version from a session export
# Usage: get_session_schema_version "/path/to/export.json"
# Returns: schema version number or "unknown"
get_session_schema_version() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "unknown"
        return 1
    fi

    acfs_session_jq -r '.schema_version // "unknown"' "$file" 2>/dev/null || echo "unknown"
}

# Get session summary from an export
# Usage: get_session_summary "/path/to/export.json"
get_session_summary() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    acfs_session_jq -r '.summary // ""' "$file" 2>/dev/null || echo ""
}

# Get session agent from an export
# Usage: get_session_agent "/path/to/export.json"
get_session_agent() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    acfs_session_jq -r '.agent // ""' "$file" 2>/dev/null || echo ""
}

# Check if jq is available (required for session operations)
# Usage: check_session_deps
check_session_deps() {
    if ! acfs_session_system_binary_path jq >/dev/null 2>&1; then
        log_error "jq is required for session operations but not installed"
        return 1
    fi
    return 0
}

# ============================================================
# SANITIZATION
# ============================================================
#
# Sanitization patterns for removing secrets from session exports.
# See bead 1xq for design decisions.
#
# ACFS_SANITIZE_OPTIONAL=1 enables optional patterns (IPs, emails)

# Core redaction patterns - always applied
# These patterns detect secrets that MUST be redacted
readonly REDACT_PATTERNS=(
    # OpenAI API keys (sk-..., sk-proj-...)
    'sk-[a-zA-Z0-9_-]{20,}'

    # Anthropic API keys (sk-ant-...)
    'sk-ant-[a-zA-Z0-9_-]{20,}'

    # Google API keys (AIza...)
    'AIza[a-zA-Z0-9_-]{35}'

    # GitHub Fine-grained PATs
    'github_pat_[a-zA-Z0-9_]{50,}'

    # GitHub Personal Access Tokens
    'ghp_[a-zA-Z0-9]{36}'

    # GitHub OAuth tokens
    'gho_[a-zA-Z0-9]{36}'

    # GitHub App tokens
    'ghs_[a-zA-Z0-9]{36}'

    # GitHub Refresh tokens
    'ghr_[a-zA-Z0-9]{36}'

    # Slack Bot tokens
    'xoxb-[a-zA-Z0-9-]+'

    # Slack User tokens
    'xoxp-[a-zA-Z0-9-]+'

    # AWS Access Keys
    'AKIA[A-Z0-9]{16}'

    # HuggingFace Tokens
    'hf_[a-zA-Z0-9]{34}'

    # Stripe Secret Keys (live and test)
    '[rs]k_(live|test)_[a-zA-Z0-9]{24,}'
)

# Optional redaction patterns - applied when ACFS_SANITIZE_OPTIONAL=1
# These may have higher false positive rates
readonly OPTIONAL_REDACT_PATTERNS=(
    # IPv4 addresses
    '[0-9]{1,3}(\.[0-9]{1,3}){3}'

    # Email addresses
    '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
)

readonly ACFS_PRIVATE_KEY_PEM_PATTERN='-----BEGIN ([A-Z0-9][A-Z0-9 -]* )?PRIVATE KEY( BLOCK)?-----'

acfs_session_redact_private_key_blocks() {
    local awk_bin=""

    awk_bin="$(acfs_session_system_binary_path awk 2>/dev/null || true)"
    if [[ -z "$awk_bin" ]]; then
        log_error "awk is required for private-key redaction but not installed"
        return 1
    fi

    "$awk_bin" '
        BEGIN {
            in_private_key = 0
            begin_pattern = "-----BEGIN ([A-Z0-9][A-Z0-9 -]* )?PRIVATE KEY( BLOCK)?-----"
            end_pattern = "-----END ([A-Z0-9][A-Z0-9 -]* )?PRIVATE KEY( BLOCK)?-----"
        }
        {
            upper_line = toupper($0)
            if (in_private_key) {
                if (upper_line ~ end_pattern) {
                    in_private_key = 0
                }
                next
            }
            if (upper_line ~ begin_pattern) {
                print "[PRIVATE_KEY_REDACTED]"
                if (upper_line !~ end_pattern) {
                    in_private_key = 1
                }
                next
            }
            print
        }
    '
}

acfs_session_assert_no_private_key_material() {
    local file="${1:-}"
    local grep_bin=""
    local grep_status=0

    if [[ ! -f "$file" ]] || [[ -L "$file" ]]; then
        log_error "Cannot verify private-key redaction for unsafe file: $file"
        return 1
    fi

    grep_bin="$(acfs_session_system_binary_path grep 2>/dev/null || true)"
    if [[ -z "$grep_bin" ]]; then
        log_error "grep is required to verify private-key redaction but not installed"
        return 1
    fi

    LC_ALL=C "$grep_bin" -Eiq -- "$ACFS_PRIVATE_KEY_PEM_PATTERN" "$file" 2>/dev/null || grep_status=$?
    case "$grep_status" in
        0)
            log_error "Private-key material remains after session sanitization; refusing output"
            return 1
            ;;
        1)
            return 0
            ;;
        *)
            log_error "Failed to verify session output for private-key material"
            return 1
            ;;
    esac
}

# Sanitize content by applying redaction patterns
# Usage: sanitize_content [file|content] (or reads from stdin)
# Returns: sanitized content via stdout
sanitize_content() {
    local sed_flags="g"
    local sed_bin=""
    local pipeline_status=0

    sed_bin="$(acfs_session_system_binary_path sed 2>/dev/null || true)"
    if [[ -z "$sed_bin" ]]; then
        log_error "sed is required for session sanitization but not installed"
        return 1
    fi

    # BSD sed doesn't support case-insensitive replacement flags. Prefer gI when available.
    if printf 'test' | "$sed_bin" -E 's/test/TEST/gI' >/dev/null 2>&1; then
        sed_flags="gI"
    fi

    local sed_script=""
    for pattern in "${REDACT_PATTERNS[@]}"; do
        sed_script+="s/${pattern}/[REDACTED]/${sed_flags}; "
    done

    # Redact common key/value secrets while preserving surrounding structure.
    local kv_pattern="([\"']?)(password|secret|api_key|apikey|auth_token|access_token)([\"']?)([[:space:]]*[:=][[:space:]]*)([\"']?)[^][[:space:]\"'}),;[]{8,}([\"']?)"
    sed_script+="s/${kv_pattern}/\\1\\2\\3\\4\\5[REDACTED]\\6/${sed_flags}; "

    # Apply optional patterns if enabled
    if [[ "${ACFS_SANITIZE_OPTIONAL:-0}" == "1" ]]; then
        for pattern in "${OPTIONAL_REDACT_PATTERNS[@]}"; do
            sed_script+="s/${pattern}/[REDACTED]/${sed_flags}; "
        done
    fi

    if [[ $# -gt 0 ]]; then
        if [[ -f "$1" ]]; then
            (
                set -o pipefail
                acfs_session_redact_private_key_blocks < "$1" | "$sed_bin" -E "$sed_script"
            ) || pipeline_status=$?
        else
            (
                set -o pipefail
                printf '%s' "$1" | acfs_session_redact_private_key_blocks | "$sed_bin" -E "$sed_script"
            ) || pipeline_status=$?
        fi
    else
        (
            set -o pipefail
            acfs_session_redact_private_key_blocks | "$sed_bin" -E "$sed_script"
        ) || pipeline_status=$?
    fi

    return "$pipeline_status"
}

acfs_session_remove_temp_files() {
    local path
    for path in "$@"; do
        if [[ -n "$path" ]]; then
            rm -f -- "$path" 2>/dev/null || true
        fi
    done
}

# Sanitize a session export JSON file in place
# Usage: sanitize_session_export "/path/to/export.json"
# Returns: 0 on success, 1 on failure
sanitize_session_export() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "Session export file not found: $file"
        return 1
    fi

    # Validate it's valid JSON first
    if ! acfs_session_jq -e . "$file" >/dev/null 2>&1; then
        log_error "Invalid JSON in session export: $file"
        return 1
    fi

    # Create temp file for atomic write (same directory to guarantee atomic rename).
    local tmpfile
    local file_dir="${file%/*}"
    if [[ -z "$file_dir" ]]; then
        file_dir="/"
    elif [[ "$file_dir" == "$file" ]]; then
        file_dir="."
    fi

    tmpfile=$(mktemp "${file_dir}/acfs_session_sanitize.XXXXXX" 2>/dev/null) || {
        log_error "Failed to create temp file for sanitization in: $file_dir"
        return 1
    }

    # Sanitize all string values in the JSON.
    # This processes transcript content, summary, key_prompts, etc.
    #
    # Keep this as heredocs to avoid shell quoting issues with jq regex patterns.
    local jq_filter_base
    read -r -d '' jq_filter_base <<'JQ_BASE' || true
def is_secret_key:
    test("(?i)password|secret|api_key|apikey|auth_token|access_token|private_key|secret_key");

def redact_private_keys:
    gsub("(?is)-----BEGIN ([A-Z0-9][A-Z0-9 -]* )?PRIVATE KEY( BLOCK)?-----.*?-----END ([A-Z0-9][A-Z0-9 -]* )?PRIVATE KEY( BLOCK)?-----"; "[PRIVATE_KEY_REDACTED]") |
    gsub("(?is)-----BEGIN ([A-Z0-9][A-Z0-9 -]* )?PRIVATE KEY( BLOCK)?-----.*$"; "[PRIVATE_KEY_REDACTED]");

def sanitize_value:
    if type == "string" then
        redact_private_keys |
        gsub("sk-[a-zA-Z0-9_-]{20,}"; "[REDACTED]") |
        gsub("sk-ant-[a-zA-Z0-9_-]{20,}"; "[REDACTED]") |
        gsub("AIza[a-zA-Z0-9_-]{35}"; "[REDACTED]") |
        gsub("github_pat_[a-zA-Z0-9_]{50,}"; "[REDACTED]") |
        gsub("ghp_[a-zA-Z0-9]{36}"; "[REDACTED]") |
        gsub("gho_[a-zA-Z0-9]{36}"; "[REDACTED]") |
        gsub("ghs_[a-zA-Z0-9]{36}"; "[REDACTED]") |
        gsub("ghr_[a-zA-Z0-9]{36}"; "[REDACTED]") |
        gsub("xoxb-[a-zA-Z0-9-]+"; "[REDACTED]") |
        gsub("xoxp-[a-zA-Z0-9-]+"; "[REDACTED]") |
        gsub("AKIA[A-Z0-9]{16}"; "[REDACTED]") |
        gsub("hf_[a-zA-Z0-9]{34}"; "[REDACTED]") |
        gsub("[rs]k_(live|test)_[a-zA-Z0-9]{24,}"; "[REDACTED]") |
        # Fallback for inline key=value pairs in strings.
        # Since jq gsub doesn't support backreferences in the replacement string,
        # we use a capture-and-replace approach or just redact the whole match.
        # Redacting the whole match is safer for security.
        gsub("(?i)(password|secret|api_key|apikey|auth_token|access_token)[\"\\s:=]+[\"']?[^\\s\"'\\}\\]\\),;\\[]{8,}[\"']?"; "[SECRET_REDACTED]")
JQ_BASE

    local jq_filter_optional=""
    if [[ "${ACFS_SANITIZE_OPTIONAL:-0}" == "1" ]]; then
        read -r -d '' jq_filter_optional <<'JQ_OPTIONAL' || true
        |
        gsub("\\b[0-9]{1,3}(\\.[0-9]{1,3}){3}\\b"; "[REDACTED]") |
        gsub("\\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}\\b"; "[REDACTED]")
JQ_OPTIONAL
    fi

    local jq_filter_tail
    read -r -d '' jq_filter_tail <<'JQ_TAIL' || true
    elif type == "array" then
        map(sanitize_value)
    elif type == "object" then
        with_entries(
            if (.key | is_secret_key) then
                .value = "[REDACTED]"
            else
                .value |= sanitize_value
            end
        )
    else
        .
    end;
sanitize_value
JQ_TAIL

    local jq_filter="${jq_filter_base}${jq_filter_optional}${jq_filter_tail}"

    if ! acfs_session_jq "$jq_filter" "$file" > "$tmpfile"; then
        acfs_session_remove_temp_files "$tmpfile"
        log_error "Failed to sanitize session export"
        return 1
    fi

    if ! acfs_session_assert_no_private_key_material "$tmpfile"; then
        acfs_session_remove_temp_files "$tmpfile"
        return 1
    fi

    # Atomic replace
    if ! mv -- "$tmpfile" "$file"; then
        acfs_session_remove_temp_files "$tmpfile"
        log_error "Failed to write sanitized session export"
        return 1
    fi
    return 0
}

# Check if content contains potential secrets (pre-sanitization check)
# Usage: contains_secrets "content string"
# Returns: 0 if secrets detected, 1 if clean
contains_secrets() {
    local content="$1"

    if printf '%s' "$content" | grep -qiE -- "$ACFS_PRIVATE_KEY_PEM_PATTERN" 2>/dev/null; then
        return 0
    fi

    # Match common key/value secrets (preserve case-insensitive detection).
    if printf '%s' "$content" | grep -qiE '(password|secret|api_key|apikey|auth_token|access_token)[\"[:space:]:=]+[\"'\''"]?[^[:space:]\"'\''"]{8,}[\"'\''"]?' 2>/dev/null; then
        return 0
    fi

    for pattern in "${REDACT_PATTERNS[@]}"; do
        if printf '%s' "$content" | grep -qE "$pattern" 2>/dev/null; then
            return 0
        fi
    done

    return 1
}

# ============================================================
# SESSION LISTING (via CASS)
# ============================================================

# Check if CASS is installed
# Usage: check_cass_installed
# Returns: 0 if installed, 1 otherwise
check_cass_installed() {
    if ! command -v cass >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# List recent sessions via CASS search
# Usage: list_sessions [--json] [--days N] [--agent AGENT] [--limit N]
# Returns: Session list to stdout
list_sessions() {
    local output_json=false
    local days=30
    local agent=""
    local limit=20

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                output_json=true
                shift
                ;;
            --days)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--days requires a numeric value"
                    return 1
                fi
                if [[ ! "$2" =~ ^[0-9]+$ ]] || [[ "$2" == "0" ]]; then
                    log_error "--days requires a positive integer"
                    return 1
                fi
                days="$2"
                shift 2
                ;;
            --agent)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--agent requires a value"
                    return 1
                fi
                agent="$2"
                shift 2
                ;;
            --limit)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--limit requires a numeric value"
                    return 1
                fi
                if [[ ! "$2" =~ ^[0-9]+$ ]] || [[ "$2" == "0" ]]; then
                    log_error "--limit requires a positive integer"
                    return 1
                fi
                limit="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Check CASS is installed
    if ! check_cass_installed; then
        if [[ "$output_json" == "true" ]]; then
            echo '{"error": "CASS not installed", "install": "See https://github.com/Dicklesworthstone/coding_agent_session_search"}'
        else
            log_error "CASS (Coding Agent Session Search) is not installed"
            log_info "Install from: https://github.com/Dicklesworthstone/coding_agent_session_search"
        fi
        return 1
    fi

    # Build CASS search command
    local cass_args=("search" "*" "--limit" "$limit" "--days" "$days")

    if [[ -n "$agent" ]]; then
        cass_args+=("--agent" "$agent")
    fi

    if [[ "$output_json" == "true" ]]; then
        # JSON output: aggregate by session with stats
        cass "${cass_args[@]}" --json --aggregate agent,workspace 2>/dev/null | jq '
            {
                sessions: (.aggregations // []) | map({
                    agent: .agent,
                    workspace: .workspace,
                    count: .count
                }),
                total: .count,
                query_info: {
                    limit: .limit,
                    offset: .offset
                }
            }
        ' 2>/dev/null || echo '{"error": "Failed to query CASS"}'
    else
        # Human-readable output
        echo ""
        echo "Recent Sessions (last ${days} days):"
        echo ""

        # Get stats by agent
        local stats
        stats=$(cass stats --json 2>/dev/null)

        if [[ -n "$stats" ]]; then
            echo "$stats" | jq -r '
                "  By Agent:",
                (.by_agent[] | "    \(.agent): \(.count) sessions"),
                "",
                "  Top Workspaces:",
                (.top_workspaces[:5][] | "    \(.workspace): \(.count) sessions")
            ' 2>/dev/null

            echo ""
            echo "  Date Range: $(echo "$stats" | jq -r '.date_range.oldest[:10]') to $(echo "$stats" | jq -r '.date_range.newest[:10]')"
            echo "  Total Conversations: $(echo "$stats" | jq -r '.conversations')"
            echo "  Total Messages: $(echo "$stats" | jq -r '.messages')"
        fi

        echo ""
        echo "Use: cass search \"<query>\" to find specific sessions"
        echo "Use: cass export <session-path> --format json to export"
    fi
}

# Get session details for a specific workspace
# Usage: get_workspace_sessions <workspace_path> [--limit N]
get_workspace_sessions() {
    local workspace="$1"
    local limit="${2:-10}"

    if ! check_cass_installed; then
        log_error "CASS not installed"
        return 1
    fi

    cass search "*" --workspace "$workspace" --limit "$limit" --json 2>/dev/null
}

# ============================================================
# SESSION EXPORT
# ============================================================

# Export a session file with sanitization
# Usage: export_session <session_path> [--format json|markdown] [--no-sanitize] [--output FILE]
# Returns: Exported content to stdout (or file if --output specified)
export_session() {
    local session_path=""
    local format="json"
    local sanitize=true
    local output_file=""
    local status=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--format requires a value (json or markdown)"
                    return 1
                fi
                format="$2"
                shift 2
                ;;
            --no-sanitize)
                sanitize=false
                shift
                ;;
            --output|-o)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--output requires a file path"
                    return 1
                fi
                output_file="$2"
                shift 2
                ;;
            -*)
                log_warn "Unknown option: $1"
                shift
                ;;
            *)
                session_path="$1"
                shift
                ;;
        esac
    done

    # Validate session path
    if [[ -z "$session_path" ]]; then
        log_error "Session path required"
        log_info "Usage: export_session <session_path> [--format json|markdown]"
        log_info "Find sessions with: cass search \"<query>\" or list_sessions"
        return 1
    fi

    if [[ ! -f "$session_path" ]]; then
        log_error "Session file not found: $session_path"
        return 1
    fi

    case "$format" in
        json|markdown) ;;
        *)
            log_error "Unsupported export format: $format (expected json or markdown)"
            return 1
            ;;
    esac

    # Check CASS is installed
    if ! check_cass_installed; then
        log_error "CASS not installed"
        return 1
    fi

    # Use a temp file for the export to handle large sessions efficiently
    local tmp_export
    tmp_export=$(mktemp "${TMPDIR:-/tmp}/acfs_session_export.XXXXXX" 2>/dev/null) || {
        log_error "Failed to create temp file for session export"
        return 1
    }
    local tmp_sanitized="${tmp_export}.sanitized"

    # Export via CASS to temp file
    if ! cass export "$session_path" --format "$format" > "$tmp_export" 2>/dev/null; then
        log_error "Failed to export session: $session_path"
        status=1
    elif [[ ! -s "$tmp_export" ]]; then
        log_error "Exported session is empty: $session_path"
        status=1
    elif [[ "$sanitize" == "true" ]]; then
        if [[ "$format" == "json" ]]; then
            # In-place JSON sanitization
            if ! sanitize_session_export "$tmp_export"; then
                log_error "Sanitization failed; refusing to output unsanitized export"
                status=1
            fi
        else
            # Text-based sanitization (stream through sed to new temp file)
            if sanitize_content "$tmp_export" > "$tmp_sanitized"; then
                if ! mv -- "$tmp_sanitized" "$tmp_export"; then
                    acfs_session_remove_temp_files "$tmp_sanitized"
                    log_error "Sanitization failed; refusing to output unsanitized export"
                    status=1
                fi
            else
                acfs_session_remove_temp_files "$tmp_sanitized"
                log_error "Sanitization failed; refusing to output unsanitized export"
                status=1
            fi
        fi
    fi

    # Private keys are never exportable, even when the caller explicitly disables
    # the broader token sanitizer. This postcondition catches redactor drift and
    # prevents --no-sanitize from becoming a private-key exfiltration switch.
    if [[ "$status" -eq 0 ]] && ! acfs_session_assert_no_private_key_material "$tmp_export"; then
        status=1
    fi

    if [[ "$status" -eq 0 && -n "$output_file" ]]; then
        # Move or copy to destination
        # Try mv first (atomic if same fs), fall back to cat (streaming)
        if ! mv -- "$tmp_export" "$output_file" 2>/dev/null; then
            if ! cat "$tmp_export" > "$output_file"; then
                log_error "Failed to write exported session to: $output_file"
                status=1
            fi
        fi
        if [[ "$status" -eq 0 ]]; then
            log_success "Exported to: $output_file"
        fi
    elif [[ "$status" -eq 0 ]]; then
        if ! cat "$tmp_export"; then
            log_error "Failed to stream exported session output"
            status=1
        fi
    fi

    acfs_session_remove_temp_files "$tmp_export" "$tmp_sanitized"
    return "$status"
}

# Find and export the most recent session in a workspace
# Usage: export_recent_session [workspace] [--format json|markdown]
export_recent_session() {
    local workspace="${1:-$(pwd)}"
    local format="${2:-json}"

    if ! check_cass_installed; then
        log_error "CASS not installed"
        return 1
    fi

    # Find the most recent session file in the workspace
    local recent_session
    recent_session=$(cass search "*" --workspace "$workspace" --limit 1 --json 2>/dev/null | jq -r '.hits[0].source_path // empty')

    if [[ -z "$recent_session" ]]; then
        log_error "No sessions found for workspace: $workspace"
        return 1
    fi

    export_session "$recent_session" --format "$format"
}

# Convert CASS export JSON to our schema format
# Usage: convert_to_acfs_schema <cass.json | raw_json>
# Returns: ACFS-schema JSON to stdout
convert_to_acfs_schema() {
    local input="${1:-}"
    local agent_hint="${2:-}"
    if [[ -z "$input" ]]; then
        return 1
    fi

    # Normalize agent hint (best-effort). CASS exports don't reliably include
    # an "agent type" field, so callers can pass a hint (e.g., inferred from path).
    case "$agent_hint" in
        claude-code|codex|gemini) ;;
        "") agent_hint="" ;;
        *) agent_hint="unknown" ;;
    esac

    local filter
    filter="$(
        cat <<'JQ'
        def is_claude_export:
          any(.[]?; (.type == "user" or .type == "assistant") and (.sessionId? | type) == "string");

        def is_codex_export:
          any(.[]?; .type == "event_msg" and ((.payload.type? // "") == "user_message" or (.payload.type? // "") == "agent_message"));

        def content_to_text:
          if type == "string" then .
          elif type == "array" then
            (
              [
                .[]? |
                if type == "string" then .
                elif type == "object" then
                  # Only include user-visible text blocks; exclude "thinking" / tool blocks.
                  if ((.type? // "") == "text" or (.type? // "") == "input_text" or (.type? // "") == "output_text" or (.type? // "") == "") and (.text? | type) == "string" then .text
                  else "" end
                else "" end
              ] | join("")
            )
          else "" end;

        def messages:
          if is_claude_export then
            [
              .[] |
              select(.type == "user" or .type == "assistant") |
	              {
	                role: (.message.role // .type // "unknown"),
	                content: (.message.content | content_to_text),
	                timestamp: (.timestamp // ""),
	                sessionId: (.sessionId? // ""),
	                model: (.message.model? // "")
	              }
	            ]
          elif is_codex_export then
            [
              .[] |
              select(.type == "event_msg") |
              select((.payload.type? // "") == "user_message" or (.payload.type? // "") == "agent_message") |
              {
                role: (if (.payload.type? // "") == "user_message" then "user" else "assistant" end),
                content: (.payload.message? // "" | tostring),
                timestamp: (.timestamp // "")
              }
            ]
          else
            []
          end;

        {
            schema_version: 1,
            exported_at: (now | todateiso8601),
            session_id: (
              if is_claude_export then
                messages as $msgs |
                ([$msgs[] | .sessionId? | select(type == "string" and length > 0)] | .[0] // "unknown")
              elif is_codex_export then
                ([.[] | select(.type == "session_meta") | .payload.id? | select(type == "string" and length > 0)] | .[0] // "unknown")
              else
                "unknown"
              end
            ),
            agent: (if ($agent_hint | length) > 0 then $agent_hint else "unknown" end),
            model: (
              if is_claude_export then
                (
	                  [
	                    messages[] |
	                    select(.role == "assistant") |
	                    (.model? // "") |
	                    select(type == "string" and length > 0)
	                  ] | .[0] // "unknown"
	                )
              elif is_codex_export then
                ([.[] | select(.type == "turn_context") | .payload.model? | select(type == "string" and length > 0)] | .[0] // "unknown")
              else
                "unknown"
              end
            ),
            summary: "Exported session",
            duration_minutes: 0,
            stats: {
                turns: (messages | length),
                files_created: 0,
                files_modified: 0,
                commands_run: 0
            },
            outcomes: [],
            key_prompts: [],
            sanitized_transcript: [
                messages[] |
                {
                    role: (.role // "unknown"),
                    content: (.content // ""),
                    timestamp: (.timestamp // "")
                }
                | select(.content | type == "string")
                | select((.content | length) > 0)
            ]
        }
JQ
    )"

    # Prefer raw JSON when the argument clearly looks like JSON.
    if [[ "$input" == "{"* || "$input" == "["* ]]; then
        jq --arg agent_hint "$agent_hint" "$filter" 2>/dev/null <<<"$input"
        return $?
    fi

    # Prefer a readable path (regular file or FIFO like /dev/fd/*).
    if [[ -r "$input" ]]; then
        jq --arg agent_hint "$agent_hint" "$filter" "$input" 2>/dev/null
        return $?
    fi

    # Fall back to treating the input as raw JSON.
    jq --arg agent_hint "$agent_hint" "$filter" 2>/dev/null <<<"$input"
}

# ============================================================
# NATIVE SESSION CONVERSION (X -> Y)
# ============================================================
#
# Converts one provider's native session file into another provider's
# native storage format and location.
#
# Supported providers: claude-code, codex, gemini

session_generate_uuid() {
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        tr '[:upper:]' '[:lower:]' < /proc/sys/kernel/random/uuid
        return 0
    fi
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
        return 0
    fi
    # Best-effort fallback: generate enough entropy in one pass.
    local seed
    seed=$( (date +%s%N; head -c 32 /dev/urandom | sha256sum) | sha256sum | cut -d' ' -f1)
    printf '%s-%s-%s-%s-%s\n' \
        "${seed:0:8}" \
        "${seed:8:4}" \
        "${seed:12:4}" \
        "${seed:16:4}" \
        "${seed:20:12}"
}

session_now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

acfs_session_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    case "$path_value" in
        *$'\n'*|*$'\r'*|*$'\t'*) return 1 ;;
        */../*|*/..|*/./*|*/.) return 1 ;;
    esac
    printf '%s\n' "$path_value"
}

acfs_session_child_path() {
    local root="${1:-}"
    local leaf="${2:-}"

    root="$(acfs_session_sanitize_abs_nonroot_path "$root" 2>/dev/null || true)"
    if [[ -z "$root" ]] || [[ -z "$leaf" ]] || [[ "$leaf" == "." ]] || [[ "$leaf" == ".." ]] ||
        [[ "$leaf" == */* ]] || [[ "$leaf" == *$'\n'* ]] || [[ "$leaf" == *$'\r'* ]]; then
        log_error "Refusing unsafe session storage path"
        return 1
    fi

    printf '%s/%s\n' "$root" "$leaf"
}

acfs_session_assert_direct_child_path() {
    local root="${1:-}"
    local path="${2:-}"

    root="$(acfs_session_sanitize_abs_nonroot_path "$root" 2>/dev/null || true)"
    if [[ -z "$root" ]] || [[ -z "$path" ]] || [[ "${path%/*}" != "$root" ]]; then
        log_error "Session path escapes its intended storage directory: $path"
        return 1
    fi

    return 0
}

acfs_session_require_new_destination() {
    local root="${1:-}"
    local path="${2:-}"

    acfs_session_assert_direct_child_path "$root" "$path" || return 1
    if [[ -e "$path" ]] || [[ -L "$path" ]]; then
        log_error "Refusing to overwrite existing session destination: $path"
        return 1
    fi

    return 0
}

acfs_session_create_new_file() {
    local root="${1:-}"
    local path="${2:-}"

    acfs_session_require_new_destination "$root" "$path" || return 1
    if ! (set -o noclobber; : > "$path") 2>/dev/null; then
        log_error "Failed to create new session destination without overwriting: $path"
        return 1
    fi
    if [[ ! -f "$path" ]] || [[ -L "$path" ]]; then
        log_error "Created session destination is not a safe regular file: $path"
        return 1
    fi

    return 0
}

acfs_session_publish_new_file() {
    local staged_path="${1:-}"
    local root="${2:-}"
    local destination="${3:-}"
    local mv_bin=""

    if [[ ! -f "$staged_path" ]] || [[ -L "$staged_path" ]]; then
        log_error "Refusing to publish unsafe staged session file: $staged_path"
        return 1
    fi
    acfs_session_require_new_destination "$root" "$destination" || return 1

    mv_bin="$(acfs_session_system_binary_path mv 2>/dev/null || true)"
    if [[ -z "$mv_bin" ]]; then
        log_error "mv is required to publish imported sessions but not installed"
        return 1
    fi

    # -n makes a destination race non-destructive. Some mv implementations return
    # success when they skip an existing destination, so the staged-file check is
    # the authoritative proof that publication actually occurred.
    if ! "$mv_bin" -n -- "$staged_path" "$destination" 2>/dev/null || [[ -e "$staged_path" ]]; then
        log_error "Refusing to overwrite existing session destination: $destination"
        return 1
    fi
    if [[ ! -f "$destination" ]] || [[ -L "$destination" ]]; then
        log_error "Published session destination is not a safe regular file: $destination"
        return 1
    fi

    return 0
}

acfs_session_home_base() {
    local base_home=""

    base_home="$(acfs_session_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"
    if [[ -z "$base_home" ]]; then
        base_home="$(acfs_session_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    fi
    [[ -n "$base_home" ]] || return 1

    printf '%s\n' "$base_home"
}

acfs_session_provider_home_dir() {
    local env_name="$1"
    local default_leaf="$2"
    local explicit_home="${!env_name-}"
    local home_dir=""

    if [[ -n "$explicit_home" ]]; then
        home_dir="$(acfs_session_sanitize_abs_nonroot_path "$explicit_home" 2>/dev/null || true)"
        if [[ -z "$home_dir" ]]; then
            log_error "Invalid $env_name: $explicit_home"
            return 1
        fi
        printf '%s\n' "$home_dir"
        return 0
    fi

    local base_home=""
    base_home="$(acfs_session_home_base 2>/dev/null || true)"
    if [[ -z "$base_home" ]]; then
        log_error "Unable to resolve $env_name; set $env_name, TARGET_HOME, or HOME"
        return 1
    fi

    printf '%s/%s\n' "$base_home" "$default_leaf"
}

acfs_session_default_sessions_dir() {
    local base_home=""

    base_home="$(acfs_session_home_base 2>/dev/null || true)"
    [[ -n "$base_home" ]] || return 1

    printf '%s/.acfs/sessions\n' "$base_home"
}

acfs_session_storage_dir() {
    local sessions_dir=""

    if [[ -n "${ACFS_SESSIONS_DIR:-}" ]]; then
        sessions_dir="$(acfs_session_sanitize_abs_nonroot_path "$ACFS_SESSIONS_DIR" 2>/dev/null || true)"
        if [[ -z "$sessions_dir" ]]; then
            log_error "Invalid ACFS_SESSIONS_DIR: $ACFS_SESSIONS_DIR"
            return 1
        fi
    else
        sessions_dir="$(acfs_session_default_sessions_dir 2>/dev/null || true)"
        if [[ -z "$sessions_dir" ]]; then
            log_error "Unable to resolve session storage directory; set HOME, TARGET_HOME, or ACFS_SESSIONS_DIR"
            return 1
        fi
    fi

    ACFS_SESSIONS_DIR="$sessions_dir"
    printf '%s\n' "$ACFS_SESSIONS_DIR"
}

session_project_dir_key_claude() {
    local workspace="${1:-/tmp}"
    printf '%s' "$workspace" | sed -E 's/[^[:alnum:]]/-/g'
}

session_project_hash_gemini() {
    local workspace="${1:-/tmp}"
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$workspace" | sha256sum | awk '{print $1}'
        return 0
    fi
    if command -v shasum >/dev/null 2>&1; then
        printf '%s' "$workspace" | shasum -a 256 | awk '{print $1}'
        return 0
    fi
    log_error "No SHA256 tool found (need sha256sum or shasum)"
    return 1
}

session_project_dir_key_gemini() {
    local workspace="${1:-/tmp}"
    local home_dir=""
    home_dir="$(acfs_session_provider_home_dir GEMINI_HOME ".gemini")" || return 1
    local tmp_root="$home_dir/tmp"

    # Prefer an existing native project directory keyed by .project_root.
    if [[ -d "$tmp_root" ]]; then
        local d project_root dir_name first_match=""
        while IFS= read -r -d '' d; do
            [[ -f "$d/.project_root" ]] || continue
            project_root="$(tr -d '\r\n' < "$d/.project_root" 2>/dev/null || true)"
            if [[ "$project_root" == "$workspace" ]]; then
                dir_name="$(basename "$d")"
                [[ -z "$first_match" ]] && first_match="$dir_name"
                # Prefer native project-key directories (non hash-like names).
                if [[ ! "$dir_name" =~ ^[0-9a-f]{64}$ ]]; then
                    printf '%s\n' "$dir_name"
                    return 0
                fi
            fi
        done < <(find "$tmp_root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
        if [[ -n "$first_match" ]]; then
            printf '%s\n' "$first_match"
            return 0
        fi
    fi

    # Fallback for first-time conversion into a workspace with no existing Gemini dir.
    local key
    key="$(basename "$workspace" 2>/dev/null || true)"
    if [[ -z "$key" || "$key" == "/" || "$key" == "." ]]; then
        key="$(printf '%s' "$workspace" | sed -E 's#^/##; s#/+#-#g')"
    fi
    key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^[:alnum:]]+/-/g; s/^-+//; s/-+$//')"
    [[ -z "$key" ]] && key="default-project"
    printf '%s\n' "$key"
}

parse_native_claude_to_canonical() {
    local input_file="$1"
    local workspace_hint="$2"
    jq -s --arg workspace_hint "$workspace_hint" '
        def flatten_content:
            if . == null then ""
            elif type == "string" then .
            elif type == "array" then
                ([ .[]? |
                    if . == null then ""
                    elif type == "string" then .
                    elif type == "object" then
                        (.text? // .content? // .output? // "")
                    else "" end
                 ] | join(""))
            elif type == "object" then (.text? // .content? // .output? // "")
            else "" end;

        {
            workspace: (([ .[] | .cwd? | select(type == "string" and length > 0) ] | .[0]) // ($workspace_hint // "/tmp")),
            source_session_id: (([ .[] | .sessionId? | select(type == "string" and length > 0) ] | .[0]) // "unknown"),
            messages: [
                .[] |
                select(.type == "user" or .type == "assistant") |
                {
                    role: (if .type == "assistant" then "assistant" else "user" end),
                    content: ((.message.content? // .content?) | flatten_content),
                    timestamp: (.timestamp? // "")
                } |
                select(.content | type == "string") |
                select((.content | length) > 0)
            ]
        }
    ' "$input_file"
}

parse_native_codex_to_canonical() {
    local input_file="$1"
    local workspace_hint="$2"
    jq -s --arg workspace_hint "$workspace_hint" '
        def flatten_content:
            if . == null then ""
            elif type == "string" then .
            elif type == "array" then
                ([ .[]? |
                    if . == null then ""
                    elif type == "string" then .
                    elif type == "object" then (.text? // .content? // .message? // "")
                    else "" end
                 ] | join(""))
            elif type == "object" then (.text? // .content? // .message? // "")
            else "" end;

        {
            workspace: (([ .[] | select(.type == "session_meta") | .payload.cwd? | select(type == "string" and length > 0) ] | .[0]) // ($workspace_hint // "/tmp")),
            source_session_id: (([ .[] | select(.type == "session_meta") | .payload.id? | select(type == "string" and length > 0) ] | .[0]) // "unknown"),
            messages: [
                .[] |
                if (.type == "event_msg" and ((.payload.type? // "") == "user_message")) then
                    {
                        role: "user",
                        content: ((.payload.message? // "") | tostring),
                        timestamp: (.timestamp? // "")
                    }
                elif (.type == "event_msg" and ((.payload.type? // "") == "agent_reasoning")) then
                    {
                        role: "assistant",
                        content: ((.payload.text? // "") | tostring),
                        timestamp: (.timestamp? // "")
                    }
                elif (.type == "response_item") then
                    {
                        role: (if ((.payload.role? // "assistant") | ascii_downcase) == "user" then "user" else "assistant" end),
                        content: ((.payload.content? // "") | flatten_content),
                        timestamp: (.timestamp? // "")
                    }
                else empty end |
                select(.content | type == "string") |
                select((.content | length) > 0)
            ]
        }
    ' "$input_file"
}

parse_native_gemini_to_canonical() {
    local input_file="$1"
    local workspace_hint="$2"
    jq --arg workspace_hint "$workspace_hint" '
        def flatten_content:
            if . == null then ""
            elif type == "string" then .
            elif type == "array" then
                ([ .[]? |
                    if . == null then ""
                    elif type == "string" then .
                    elif type == "object" then (.text? // .content? // "")
                    else "" end
                 ] | join(""))
            elif type == "object" then (.text? // .content? // "")
            else "" end;

        {
            workspace: ($workspace_hint // "/tmp"),
            source_session_id: (.sessionId // "unknown"),
            project_hash: (.projectHash // ""),
            messages: [
                (.messages // [])[] |
                {
                    role: (if ((.type // "") | ascii_downcase) == "user" then "user" else "assistant" end),
                    content: (.content | flatten_content),
                    timestamp: (.timestamp // "")
                } |
                select(.content | type == "string") |
                select((.content | length) > 0)
            ]
        }
    ' "$input_file"
}

parse_native_to_canonical() {
    local input_file="$1"
    local source_agent="$2"
    local workspace_hint="$3"

    case "$source_agent" in
        claude-code)
            parse_native_claude_to_canonical "$input_file" "$workspace_hint"
            ;;
        codex)
            parse_native_codex_to_canonical "$input_file" "$workspace_hint"
            ;;
        gemini)
            parse_native_gemini_to_canonical "$input_file" "$workspace_hint"
            ;;
        *)
            log_error "Unsupported source agent: $source_agent"
            return 1
            ;;
    esac
}

write_native_claude_from_canonical() {
    local canonical_file="$1"
    local workspace="$2"
    local target_session_id="$3"
    local dry_run="$4"

    acfs_session_validate_id "$target_session_id" "Target session ID" || return 1

    local home_dir=""
    home_dir="$(acfs_session_provider_home_dir CLAUDE_HOME ".claude")" || return 1
    local dir_key
    dir_key="$(session_project_dir_key_claude "$workspace")" || return 1
    local target_dir="$home_dir/projects/$dir_key"
    local target_path=""
    target_path="$(acfs_session_child_path "$target_dir" "${target_session_id}.jsonl")" || return 1
    acfs_session_require_new_destination "$target_dir" "$target_path" || return 1

    if [[ "$dry_run" != "true" ]]; then
        if ! mkdir -p "$target_dir"; then
            log_error "Failed to create Claude session directory: $target_dir"
            return 1
        fi
        acfs_session_create_new_file "$target_dir" "$target_path" || return 1

        local parent_uuid=""
        local msg_count=0
        local first_prompt=""
        local created_ts
        created_ts="$(session_now_iso)"
        local msg
        while IFS= read -r msg; do
            [[ -z "$msg" ]] && continue
            local role content msg_ts entry_uuid
            role="$(jq -r '.role // "user"' <<<"$msg")"
            content="$(jq -r '.content // ""' <<<"$msg")"
            msg_ts="$(jq -r '.timestamp // ""' <<<"$msg")"
            [[ -z "$msg_ts" ]] && msg_ts="$created_ts"
            entry_uuid="$(session_generate_uuid)"

            if [[ -z "$first_prompt" && "$role" == "user" ]]; then
                first_prompt="$content"
            fi

            jq -cn \
                --arg parent "$parent_uuid" \
                --arg cwd "$workspace" \
                --arg sid "$target_session_id" \
                --arg role "$role" \
                --arg content "$content" \
                --arg uuid "$entry_uuid" \
                --arg ts "$msg_ts" '
                {
                    parentUuid: (if $parent == "" then null else $parent end),
                    isSidechain: false,
                    userType: "external",
                    cwd: $cwd,
                    sessionId: $sid,
                    version: "2.1.32",
                    gitBranch: "main",
                    type: (if $role == "assistant" then "assistant" else "user" end),
                    message: (
                        if $role == "assistant" then
                            { role: "assistant", content: [{type: "text", text: $content}] }
                        else
                            { role: "user", content: $content }
                        end
                    ),
                    uuid: $uuid,
                    timestamp: $ts
                }
            ' >> "$target_path"

            parent_uuid="$entry_uuid"
            msg_count=$((msg_count + 1))
        done < <(jq -c '.messages[]' "$canonical_file")

        # Update/seed sessions-index so converted session appears alongside native sessions.
        local index_file="$home_dir/projects/$dir_key/sessions-index.json"
        local index_tmp
        local index_existed=false
        index_tmp=$(mktemp "${target_dir}/.sessions-index.XXXXXX.tmp") || return 1
        if [[ -L "$index_file" ]] || { [[ -e "$index_file" ]] && [[ ! -f "$index_file" ]]; }; then
            acfs_session_remove_temp_files "$index_tmp"
            log_error "Refusing unsafe Claude sessions-index: $index_file"
            return 1
        fi
        if [[ -f "$index_file" ]]; then
            index_existed=true
        fi

        local file_mtime_ms
        file_mtime_ms=$(( $(date +%s) * 1000 ))

        local -a index_jq_args=(
            --arg sid "$target_session_id"
            --arg full "$target_path"
            --arg first_prompt "$first_prompt"
            --arg created "$created_ts"
            --arg modified "$created_ts"
            --arg project "$workspace"
            --arg summary "Converted session"
            --argjson mtime "$file_mtime_ms"
            --argjson count "$msg_count"
        )
        local index_filter='
            .version = (if (.version | type) == "number" then .version else 1 end) |
            .entries = (
                (.entries // [])
                | map(select(.sessionId != $sid))
                + [{
                    sessionId: $sid,
                    fullPath: $full,
                    fileMtime: $mtime,
                    firstPrompt: $first_prompt,
                    summary: $summary,
                    messageCount: $count,
                    created: $created,
                    modified: $modified,
                    gitBranch: "main",
                    projectPath: $project,
                    isSidechain: false
                }]
            )
        '

        if [[ "$index_existed" == "true" ]]; then
            if ! jq "${index_jq_args[@]}" "$index_filter" "$index_file" > "$index_tmp"; then
                acfs_session_remove_temp_files "$index_tmp"
                log_error "Failed to update Claude sessions-index: $index_file"
                return 1
            fi
        elif ! printf '{"version":1,"entries":[]}\n' | jq "${index_jq_args[@]}" "$index_filter" > "$index_tmp"; then
            acfs_session_remove_temp_files "$index_tmp"
            log_error "Failed to create Claude sessions-index: $index_file"
            return 1
        fi

        if [[ "$index_existed" == "true" ]]; then
            if ! mv -- "$index_tmp" "$index_file"; then
                acfs_session_remove_temp_files "$index_tmp"
                log_error "Failed to write Claude sessions-index: $index_file"
                return 1
            fi
        elif ! acfs_session_publish_new_file "$index_tmp" "$target_dir" "$index_file"; then
            acfs_session_remove_temp_files "$index_tmp"
            log_error "Failed to publish Claude sessions-index: $index_file"
            return 1
        fi
    fi

    printf '%s\n' "$target_path"
}

write_native_codex_from_canonical() {
    local canonical_file="$1"
    local workspace="$2"
    local target_session_id="$3"
    local dry_run="$4"

    acfs_session_validate_id "$target_session_id" "Target session ID" || return 1

    local home_dir=""
    home_dir="$(acfs_session_provider_home_dir CODEX_HOME ".codex")" || return 1
    local now_slug date_path now_iso
    now_slug="$(date -u +%Y-%m-%dT%H-%M-%S)"
    date_path="$(date -u +%Y/%m/%d)"
    now_iso="$(session_now_iso)"

    local target_dir="$home_dir/sessions/$date_path"
    local target_path=""
    target_path="$(acfs_session_child_path "$target_dir" "rollout-${now_slug}-${target_session_id}.jsonl")" || return 1
    acfs_session_require_new_destination "$target_dir" "$target_path" || return 1

    if [[ "$dry_run" != "true" ]]; then
        if ! mkdir -p "$target_dir"; then
            log_error "Failed to create Codex session directory: $target_dir"
            return 1
        fi
        acfs_session_create_new_file "$target_dir" "$target_path" || return 1

        jq -cn \
            --arg sid "$target_session_id" \
            --arg cwd "$workspace" \
            --arg ts "$now_iso" '
            {
                timestamp: $ts,
                type: "session_meta",
                payload: {
                    id: $sid,
                    timestamp: $ts,
                    cwd: $cwd,
                    originator: "acfs_session_bridge",
                    cli_version: "unknown",
                    source: "cli",
                    model_provider: "openai"
                }
            }
        ' >> "$target_path"

        local msg
        while IFS= read -r msg; do
            [[ -z "$msg" ]] && continue
            local role content msg_ts
            role="$(jq -r '.role // "assistant"' <<<"$msg")"
            content="$(jq -r '.content // ""' <<<"$msg")"
            msg_ts="$(jq -r '.timestamp // ""' <<<"$msg")"
            [[ -z "$msg_ts" ]] && msg_ts="$now_iso"

            if [[ "$role" == "user" ]]; then
                jq -cn \
                    --arg ts "$msg_ts" \
                    --arg content "$content" '
                    {
                        timestamp: $ts,
                        type: "event_msg",
                        payload: {
                            type: "user_message",
                            message: $content,
                            images: [],
                            local_images: [],
                            text_elements: []
                        }
                    }
                ' >> "$target_path"
            else
                jq -cn \
                    --arg ts "$msg_ts" \
                    --arg content "$content" '
                    {
                        timestamp: $ts,
                        type: "response_item",
                        payload: {
                            type: "message",
                            role: "assistant",
                            content: [
                                {
                                    type: "output_text",
                                    text: $content
                                }
                            ]
                        }
                    }
                ' >> "$target_path"
            fi
        done < <(jq -c '.messages[]' "$canonical_file")
    fi

    printf '%s\n' "$target_path"
}

write_native_gemini_from_canonical() {
    local canonical_file="$1"
    local workspace="$2"
    local target_session_id="$3"
    local dry_run="$4"

    acfs_session_validate_id "$target_session_id" "Target session ID" || return 1

    local home_dir=""
    home_dir="$(acfs_session_provider_home_dir GEMINI_HOME ".gemini")" || return 1
    local hash
    hash="$(jq -r '.project_hash // ""' "$canonical_file" 2>/dev/null || true)"
    if [[ -z "$hash" || "$hash" == "null" ]]; then
        hash="$(session_project_hash_gemini "$workspace")" || return 1
    fi

    local now_iso file_stub
    now_iso="$(session_now_iso)"
    file_stub="$(date -u +%Y-%m-%dT%H-%M)-${target_session_id}"

    local dir_key
    dir_key="$(session_project_dir_key_gemini "$workspace")" || return 1
    local root_dir="$home_dir/tmp/$dir_key"
    local chats_dir="$root_dir/chats"
    local target_path=""
    target_path="$(acfs_session_child_path "$chats_dir" "session-${file_stub}.json")" || return 1
    local logs_path="$root_dir/logs.json"
    local project_root_file="$root_dir/.project_root"
    acfs_session_require_new_destination "$chats_dir" "$target_path" || return 1

    if [[ "$dry_run" != "true" ]]; then
        if ! mkdir -p "$chats_dir"; then
            log_error "Failed to create Gemini session directory: $chats_dir"
            return 1
        fi
        if [[ -L "$project_root_file" ]] || { [[ -e "$project_root_file" ]] && [[ ! -f "$project_root_file" ]]; }; then
            log_error "Refusing unsafe Gemini project-root file: $project_root_file"
            return 1
        fi
        if [[ -f "$project_root_file" ]]; then
            local existing_project_root=""
            existing_project_root="$(tr -d '\r\n' < "$project_root_file" 2>/dev/null || true)"
            if [[ "$existing_project_root" != "$workspace" ]]; then
                log_error "Refusing to overwrite Gemini project-root metadata: $project_root_file"
                return 1
            fi
        else
            acfs_session_create_new_file "$root_dir" "$project_root_file" || return 1
            if ! printf '%s\n' "$workspace" >> "$project_root_file"; then
                log_error "Failed to write Gemini project-root metadata: $project_root_file"
                return 1
            fi
        fi

        acfs_session_create_new_file "$chats_dir" "$target_path" || return 1

        local msg_tmp logs_tmp=""
        msg_tmp=$(mktemp "${TMPDIR:-/tmp}/acfs_gemini_msgs.XXXXXX") || return 1

        local first_ts=""
        local last_ts="$now_iso"
        local msg
        while IFS= read -r msg; do
            [[ -z "$msg" ]] && continue
            local role content msg_ts entry_id
            role="$(jq -r '.role // "assistant"' <<<"$msg")"
            content="$(jq -r '.content // ""' <<<"$msg")"
            msg_ts="$(jq -r '.timestamp // ""' <<<"$msg")"
            [[ -z "$msg_ts" ]] && msg_ts="$now_iso"
            [[ -z "$first_ts" ]] && first_ts="$msg_ts"
            last_ts="$msg_ts"
            entry_id="$(session_generate_uuid)"

            jq -cn \
                --arg id "$entry_id" \
                --arg ts "$msg_ts" \
                --arg role "$role" \
                --arg content "$content" '
                {
                    id: $id,
                    timestamp: $ts,
                    type: (if $role == "user" then "user" else "gemini" end),
                    content: [{text: $content}]
                }
            ' >> "$msg_tmp"
        done < <(jq -c '.messages[]' "$canonical_file")

        [[ -z "$first_ts" ]] && first_ts="$now_iso"

        local messages_json
        if ! messages_json="$(jq -s '.' "$msg_tmp")"; then
            acfs_session_remove_temp_files "$msg_tmp" "$logs_tmp"
            log_error "Failed to assemble Gemini message payload"
            return 1
        fi

        if ! jq -cn \
            --arg sid "$target_session_id" \
            --arg hash "$hash" \
            --arg start "$first_ts" \
            --arg updated "$last_ts" \
            --argjson messages "$messages_json" '
            {
                sessionId: $sid,
                projectHash: $hash,
                startTime: $start,
                lastUpdated: $updated,
                messages: $messages,
                summary: ""
            }
        ' >> "$target_path"; then
            acfs_session_remove_temp_files "$msg_tmp" "$logs_tmp"
            log_error "Failed to write Gemini chat file: $target_path"
            return 1
        fi

        # Keep logs.json in sync with user prompts for native discoverability.
        local user_log_entries
        user_log_entries="$(jq -c --arg sid "$target_session_id" '
            [ .messages
              | map(select(.role == "user"))
              | to_entries[]
              | {
                    sessionId: $sid,
                    messageId: .key,
                    type: "user",
                    message: .value.content,
                    timestamp: (if (.value.timestamp | length) > 0 then .value.timestamp else (now | todateiso8601) end)
                }
            ]
        ' "$canonical_file")"

        if [[ -L "$logs_path" ]] || { [[ -e "$logs_path" ]] && [[ ! -f "$logs_path" ]]; }; then
            acfs_session_remove_temp_files "$msg_tmp"
            log_error "Refusing unsafe Gemini logs file: $logs_path"
            return 1
        fi

        logs_tmp=$(mktemp "${root_dir}/.logs.XXXXXX.tmp") || {
            acfs_session_remove_temp_files "$msg_tmp"
            return 1
        }
        if [[ -f "$logs_path" ]]; then
            if ! jq --argjson add "$user_log_entries" '. + $add' "$logs_path" > "$logs_tmp"; then
                acfs_session_remove_temp_files "$msg_tmp" "$logs_tmp"
                log_error "Refusing to replace malformed Gemini logs file: $logs_path"
                return 1
            fi
            if ! mv -- "$logs_tmp" "$logs_path"; then
                acfs_session_remove_temp_files "$msg_tmp" "$logs_tmp"
                log_error "Failed to update Gemini logs file: $logs_path"
                return 1
            fi
        else
            if ! printf '%s\n' "$user_log_entries" > "$logs_tmp"; then
                acfs_session_remove_temp_files "$msg_tmp" "$logs_tmp"
                log_error "Failed to stage Gemini logs file: $logs_path"
                return 1
            fi
            if ! acfs_session_publish_new_file "$logs_tmp" "$root_dir" "$logs_path"; then
                acfs_session_remove_temp_files "$msg_tmp" "$logs_tmp"
                log_error "Failed to publish Gemini logs file: $logs_path"
                return 1
            fi
        fi

        acfs_session_remove_temp_files "$msg_tmp" "$logs_tmp"
    fi

    printf '%s\n' "$target_path"
}

write_native_from_canonical() {
    local canonical_file="$1"
    local target_agent="$2"
    local workspace="$3"
    local target_session_id="$4"
    local dry_run="$5"

    acfs_session_validate_id "$target_session_id" "Target session ID" || return 1

    case "$target_agent" in
        claude-code)
            write_native_claude_from_canonical "$canonical_file" "$workspace" "$target_session_id" "$dry_run"
            ;;
        codex)
            write_native_codex_from_canonical "$canonical_file" "$workspace" "$target_session_id" "$dry_run"
            ;;
        gemini)
            write_native_gemini_from_canonical "$canonical_file" "$workspace" "$target_session_id" "$dry_run"
            ;;
        *)
            log_error "Unsupported target agent: $target_agent"
            return 1
            ;;
    esac
}

infer_native_agent_from_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Gemini JSON object shape.
    if jq -e 'type == "object" and .sessionId and .messages' "$file" >/dev/null 2>&1; then
        echo "gemini"
        return 0
    fi

    # JSONL shapes for Claude/Codex.
    local first_line
    first_line="$(head -n 1 "$file" 2>/dev/null || true)"
    if [[ -z "$first_line" ]]; then
        return 1
    fi

    if jq -e '.type == "session_meta" and (.payload.id != null)' >/dev/null 2>&1 <<<"$first_line"; then
        echo "codex"
        return 0
    fi
    if jq -e '(.sessionId != null) and (.message != null)' >/dev/null 2>&1 <<<"$first_line"; then
        echo "claude-code"
        return 0
    fi
    return 1
}

# Convert a native provider session file into another provider-native session.
# Usage:
#   convert_session_native <input_file> --from <agent> --to <agent> [--workspace PATH] [--session-id ID] [--dry-run] [--json]
convert_session_native() {
    local input_file=""
    local from_agent=""
    local to_agent=""
    local workspace_hint=""
    local target_session_id=""
    local dry_run=false
    local output_json=true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--from requires a source agent"
                    return 1
                fi
                from_agent="${2:-}"
                shift 2
                ;;
            --to)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--to requires a target agent"
                    return 1
                fi
                to_agent="${2:-}"
                shift 2
                ;;
            --workspace)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--workspace requires a path"
                    return 1
                fi
                workspace_hint="${2:-}"
                shift 2
                ;;
            --session-id)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--session-id requires a value"
                    return 1
                fi
                target_session_id="${2:-}"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --json)
                output_json=true
                shift
                ;;
            --no-json)
                output_json=false
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$input_file" ]]; then
                    input_file="$1"
                else
                    log_error "Unexpected positional argument: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$input_file" ]]; then
        log_error "Input file required"
        log_info "Usage: convert_session_native <input_file> --from <agent> --to <agent>"
        return 1
    fi
    if [[ ! -f "$input_file" ]]; then
        log_error "Input file not found: $input_file"
        return 1
    fi

    if [[ -z "$from_agent" ]]; then
        from_agent="$(infer_native_agent_from_file "$input_file" || true)"
        if [[ -z "$from_agent" ]]; then
            log_error "Unable to infer source agent; pass --from"
            return 1
        fi
    fi
    if [[ -z "$to_agent" ]]; then
        log_error "Target agent required (--to)"
        return 1
    fi

    if [[ -z "$target_session_id" ]]; then
        target_session_id="$(session_generate_uuid)"
    fi

    local canonical_tmp
    canonical_tmp=$(mktemp "${TMPDIR:-/tmp}/acfs_native_canonical.XXXXXX") || {
        log_error "Failed to create temp file for canonical conversion"
        return 1
    }

    if ! parse_native_to_canonical "$input_file" "$from_agent" "$workspace_hint" > "$canonical_tmp"; then
        acfs_session_remove_temp_files "$canonical_tmp"
        log_error "Failed to parse source session into canonical format"
        return 1
    fi

    local workspace
    workspace="$(jq -r '.workspace // ""' "$canonical_tmp")"
    if [[ -z "$workspace" || "$workspace" == "null" ]]; then
        workspace="${workspace_hint:-$(pwd)}"
    fi

    local msg_count
    msg_count="$(jq -r '.messages | length' "$canonical_tmp")"
    if [[ "${msg_count:-0}" -le 0 ]]; then
        acfs_session_remove_temp_files "$canonical_tmp"
        log_error "Source session has no conversational messages to convert"
        return 1
    fi

    local source_session_id
    source_session_id="$(jq -r '.source_session_id // "unknown"' "$canonical_tmp")"

    local written_path
    if ! written_path="$(write_native_from_canonical "$canonical_tmp" "$to_agent" "$workspace" "$target_session_id" "$dry_run")"; then
        acfs_session_remove_temp_files "$canonical_tmp"
        log_error "Failed to write target-native session"
        return 1
    fi

    local output_status=0
    if [[ "$output_json" == "true" ]]; then
        if ! jq -cn \
            --arg source_agent "$from_agent" \
            --arg target_agent "$to_agent" \
            --arg source_session_id "$source_session_id" \
            --arg target_session_id "$target_session_id" \
            --arg input_file "$input_file" \
            --arg written_path "$written_path" \
            --arg workspace "$workspace" \
            --argjson message_count "$msg_count" \
            --arg dry_run "$dry_run" '
            {
                source_agent: $source_agent,
                target_agent: $target_agent,
                source_session_id: $source_session_id,
                target_session_id: $target_session_id,
                input_file: $input_file,
                written_path: $written_path,
                workspace: $workspace,
                message_count: $message_count,
                dry_run: ($dry_run == "true"),
                resume_command: (
                    if $target_agent == "claude-code" then ("claude -r " + $target_session_id)
                    elif $target_agent == "codex" then ("codex exec resume " + $target_session_id)
                    elif $target_agent == "gemini" then ("gemini --resume " + $target_session_id)
                    else ""
                    end
                )
            }
        '; then
            output_status=1
        fi
    else
        echo "Source: $from_agent ($source_session_id)"
        echo "Target: $to_agent ($target_session_id)"
        echo "Written: $written_path"
    fi

    acfs_session_remove_temp_files "$canonical_tmp"
    return "$output_status"
}

# ============================================================
# SESSION IMPORT
# ============================================================

# Default session storage directory
if [[ -z "${ACFS_SESSIONS_DIR:-}" ]]; then
    ACFS_SESSIONS_DIR="$(acfs_session_default_sessions_dir 2>/dev/null || true)"
fi

# Infer agent type from a CASS export JSON file.
# CASS exports include per-message models (for assistant turns), which is a
# better signal than the user-chosen export filename/path.
infer_agent_from_cass_export() {
    local export_file="${1:-}"

    local originator=""
    originator="$(jq -r '([.[] | select(.type == "session_meta") | .payload.originator? | select(type == "string" and length > 0)] | .[0] // "")' "$export_file" 2>/dev/null)" || originator=""

    case "${originator,,}" in
        *claude*|*anthropic*) echo "claude-code"; return 0 ;;
        *gemini*) echo "gemini"; return 0 ;;
        *codex*|*openai*) echo "codex"; return 0 ;;
    esac

    local model=""
    model="$(jq -r '([.[] | select(.type == "assistant") | .message.model? | select(type == "string" and length > 0)] | .[0] // "")' "$export_file" 2>/dev/null)" || model=""
    if [[ -z "$model" ]]; then
        model="$(jq -r '([.[] | select(.type == "turn_context") | .payload.model? | select(type == "string" and length > 0)] | .[0] // "")' "$export_file" 2>/dev/null)" || model=""
    fi

    case "${model,,}" in
        *claude*|*anthropic*) echo "claude-code" ;;
        *gemini*) echo "gemini" ;;
        *gpt*|*openai*|*codex*) echo "codex" ;;
        *)
            # Last-resort heuristic: some users export files into paths that still include
            # the agent data directory (e.g., ~/.claude/...).
            case "$export_file" in
                *"/.claude/"*) echo "claude-code" ;;
                *"/.codex/"*) echo "codex" ;;
                *"/.gemini/"*) echo "gemini" ;;
                *) echo "unknown" ;;
            esac
            ;;
    esac
}

# Generate a unique session ID
generate_session_id() {
    if command -v xxd >/dev/null 2>&1; then
        head -c 4 /dev/urandom | xxd -p
        return 0
    fi
    if command -v od >/dev/null 2>&1; then
        head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n'
        return 0
    fi
    date +%s%N | sha256sum | head -c 8
}

# Import a session file for local viewing/reference
# Usage: import_session <file> [--dry-run]
import_session() {
    local file=""
    local dry_run=false
    local sessions_dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            -*) log_warn "Unknown option: $1"; shift ;;
            *) file="$1"; shift ;;
        esac
    done

    if [[ -z "$file" ]]; then
        log_error "Session file required"
        log_info "Usage: import_session <file.json> [--dry-run]"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    if ! jq -e . "$file" >/dev/null 2>&1; then
        log_error "Invalid JSON: $file"
        return 1
    fi

    # Detect format
    local is_cass=false is_acfs=false
    if jq -e 'type == "array"' "$file" >/dev/null 2>&1; then
        # CASS exports can begin with snapshot/event records before conversation messages.
        # Detect by scanning entries rather than assuming .[0] is a message record.
        jq -e 'any(.[]?; (.type == "user" or .type == "assistant") and (.sessionId? | type) == "string")' "$file" >/dev/null 2>&1 && is_cass=true
        jq -e 'any(.[]?; .type == "event_msg" and ((.payload.type? // "") == "user_message" or (.payload.type? // "") == "agent_message"))' "$file" >/dev/null 2>&1 && is_cass=true
    fi
    jq -e 'type == "object" and .schema_version' "$file" >/dev/null 2>&1 && is_acfs=true

    # Extract metadata
    local session_id agent turn_count first_ts last_ts
    if [[ "$is_cass" == "true" ]]; then
        session_id=$(jq -r '
            if any(.[]?; .type == "user" or .type == "assistant") then
                ([.[] | select(.type == "user" or .type == "assistant") | .sessionId] | map(select(type == "string" and length > 0)) | .[0]) // "unknown"
            else
                ([.[] | select(.type == "session_meta") | .payload.id?] | map(select(type == "string" and length > 0)) | .[0]) // "unknown")
            end
        ' "$file")
        agent="$(infer_agent_from_cass_export "$file")"
        turn_count=$(jq '
            if any(.[]?; .type == "user" or .type == "assistant") then
                ([.[] | select(.type == "user" or .type == "assistant")] | length)
            else
                ([.[] | select(.type == "event_msg" and ((.payload.type? // "") == "user_message" or (.payload.type? // "") == "agent_message"))] | length)
            end
        ' "$file")
        first_ts=$(jq -r '
            if any(.[]?; .type == "user" or .type == "assistant") then
                ([.[] | select(.type == "user" or .type == "assistant") | .timestamp] | map(select(type == "string")) | .[0]) // ""
            else
                ([.[] | select(.type == "event_msg" and ((.payload.type? // "") == "user_message" or (.payload.type? // "") == "agent_message")) | .timestamp] | map(select(type == "string")) | .[0]) // ""
            end
        ' "$file")
        last_ts=$(jq -r '
            if any(.[]?; .type == "user" or .type == "assistant") then
                ([.[] | select(.type == "user" or .type == "assistant") | .timestamp] | map(select(type == "string")) | .[-1]) // ""
            else
                ([.[] | select(.type == "event_msg" and ((.payload.type? // "") == "user_message" or (.payload.type? // "") == "agent_message")) | .timestamp] | map(select(type == "string")) | .[-1]) // ""
            end
        ' "$file")
    elif [[ "$is_acfs" == "true" ]]; then
        if ! validate_session_export "$file"; then
            return 1
        fi
        session_id=$(jq -r '.session_id // "unknown"' "$file")
        agent=$(jq -r '.agent // "unknown"' "$file")
        turn_count=$(jq '.stats.turns // 0' "$file")
        first_ts=$(jq -r '.exported_at // ""' "$file")
        last_ts="$first_ts"
        local ver; ver=$(jq -r '.schema_version' "$file")
        [[ "$ver" != "1" ]] && log_warn "Schema version $ver may not be compatible"
    else
        log_error "Unrecognized session format"; return 1
    fi

    echo ""
    echo "Session Summary:"
    echo "  Session ID: $session_id"
    echo "  Agent: $agent"
    echo "  Messages: $turn_count"
    echo "  Time: ${first_ts%T*} to ${last_ts%T*}"

    if [[ "$dry_run" == "true" ]]; then
        echo ""; echo "(Dry run - nothing imported)"; return 0
    fi

    sessions_dir="$(acfs_session_storage_dir)" || return 1
    if ! mkdir -p "$sessions_dir"; then
        log_error "Failed to create session storage directory: $sessions_dir"
        return 1
    fi
    local local_id; local_id=$(generate_session_id)
    local dest="$sessions_dir/${local_id}.json"

    if [[ "$is_cass" == "true" ]]; then
        local tmp_dest
        tmp_dest=$(mktemp "${sessions_dir}/.${local_id}.XXXXXX.tmp" 2>/dev/null) || {
            log_error "Failed to create temp file for import in: $sessions_dir"
            return 1
        }

        if ! convert_to_acfs_schema "$file" "$agent" > "$tmp_dest"; then
            acfs_session_remove_temp_files "$tmp_dest"
            log_error "Failed to convert CASS export to ACFS schema"
            return 1
        fi

        # Always sanitize imported output before persisting.
        if ! sanitize_session_export "$tmp_dest"; then
            acfs_session_remove_temp_files "$tmp_dest"
            log_error "Sanitization failed; refusing to import unsanitized session"
            return 1
        fi

        if ! mv -- "$tmp_dest" "$dest"; then
            acfs_session_remove_temp_files "$tmp_dest"
            log_error "Failed to write imported session: $dest"
            return 1
        fi
    else
        local tmp_dest
        tmp_dest=$(mktemp "${sessions_dir}/.${local_id}.XXXXXX.tmp" 2>/dev/null) || {
            log_error "Failed to create temp file for import in: $sessions_dir"
            return 1
        }

        if ! cp -- "$file" "$tmp_dest"; then
            acfs_session_remove_temp_files "$tmp_dest"
            log_error "Failed to copy session export into staging file"
            return 1
        fi

        # Always sanitize imported output before persisting.
        if ! sanitize_session_export "$tmp_dest"; then
            acfs_session_remove_temp_files "$tmp_dest"
            log_error "Sanitization failed; refusing to import unsanitized session"
            return 1
        fi

        if ! mv -- "$tmp_dest" "$dest"; then
            acfs_session_remove_temp_files "$tmp_dest"
            log_error "Failed to write imported session: $dest"
            return 1
        fi
    fi

    echo ""
    echo "Imported as: $local_id"
    echo "View with: show_session $local_id"
}

# Show an imported session
# Usage: show_session <id> [--format json|markdown|summary]
show_session() {
    local session_id="" format="summary"
    local sessions_dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--format requires a value (json, markdown, or summary)"
                    return 1
                fi
                format="$2"
                shift 2
                ;;
            -*) shift ;;
            *) session_id="$1"; shift ;;
        esac
    done

    if [[ -z "$session_id" ]]; then
        log_error "Session ID required"
        return 1
    fi

    sessions_dir="$(acfs_session_storage_dir)" || return 1

    local file="$sessions_dir/${session_id}.json"
    if [[ ! -f "$file" ]]; then
        log_error "Session not found: $session_id"
        return 1
    fi

    case "$format" in
        json) jq '.' "$file" ;;
        markdown)
            jq -r '
                "# Session: \(.session_id)\n",
                "**Agent:** \(.agent)  ",
                "**Turns:** \(.stats.turns // 0)\n",
                "## Transcript\n",
                (.sanitized_transcript[:20][] |
                    "### \(.role) (\(.timestamp[:19]))\n\n\(.content)\n"
                )
            ' "$file" 2>/dev/null
            ;;
        *)
            jq -r '
                "Session: \(.session_id)",
                "Agent: \(.agent)  Model: \(.model // "unknown")",
                "Turns: \(.stats.turns // 0)\n",
                "First exchanges:",
                (.sanitized_transcript[:4][] |
                    "  [\(.role)]: \(.content[:80] | gsub("\n"; " "))..."
                )
            ' "$file" 2>/dev/null
            ;;
    esac
}

# List imported sessions
list_imported_sessions() {
    local sessions_dir=""
    sessions_dir="$(acfs_session_storage_dir 2>/dev/null || true)"

    if [[ -z "$sessions_dir" ]] || [[ ! -d "$sessions_dir" ]]; then
        echo "No imported sessions. Import with: import_session <file.json>"
        return 0
    fi

    echo ""
    echo "Imported Sessions:"
    printf "  %-10s %-12s %-20s\n" "ID" "AGENT" "SESSION_ID"
    echo "  $(printf '%.0s-' {1..50})"

    for f in "$sessions_dir"/*.json; do
        [[ -f "$f" ]] || continue
        local id; id=$(basename "$f" .json)
        jq -r '"  \("'"$id"'")   \(.agent[:12])   \(.session_id)"' "$f" 2>/dev/null
    done
}
