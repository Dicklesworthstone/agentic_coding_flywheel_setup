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
#     model: string;                  // e.g., "opus-4.5", "gpt-4o"
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
#   API Version: 1, Contract Version: 1, Crate: 0.1.35+
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
if [[ -z "${ACFS_LOG_LOADED:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=logging.sh
    source "${SCRIPT_DIR}/logging.sh" 2>/dev/null || true
fi

# ============================================================
# VALIDATION
# ============================================================

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
    if ! jq -e . "$file" >/dev/null 2>&1; then
        log_error "Invalid JSON in session export: $file"
        return 1
    fi

    # Check required top-level fields exist
    if ! jq -e '.schema_version and .session_id and .agent' "$file" >/dev/null 2>&1; then
        log_error "Invalid session export: missing required fields (schema_version, session_id, agent)"
        return 1
    fi

    # Check schema version compatibility
    local version
    version=$(jq -r '.schema_version' "$file")
    if [[ "$version" != "1" ]]; then
        log_warn "Session schema version $version may not be fully compatible (expected: 1)"
    fi

    # Validate agent field is one of the known agents
    local agent
    agent=$(jq -r '.agent' "$file")
    case "$agent" in
        claude-code|codex|gemini)
            ;;
        *)
            log_warn "Unknown agent type: $agent (expected: claude-code, codex, or gemini)"
            ;;
    esac

    # Validate stats object exists and has expected fields
    if ! jq -e '.stats.turns != null' "$file" >/dev/null 2>&1; then
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

    jq -r '.schema_version // "unknown"' "$file" 2>/dev/null || echo "unknown"
}

# Get session summary from an export
# Usage: get_session_summary "/path/to/export.json"
get_session_summary() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    jq -r '.summary // ""' "$file" 2>/dev/null || echo ""
}

# Get session agent from an export
# Usage: get_session_agent "/path/to/export.json"
get_session_agent() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    jq -r '.agent // ""' "$file" 2>/dev/null || echo ""
}

# Check if jq is available (required for session operations)
# Usage: check_session_deps
check_session_deps() {
    if ! command -v jq >/dev/null 2>&1; then
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

    # Generic password/secret patterns (key=value or key: value)
    # Using [[:space:]] for portability instead of \s
    'password["[:space:]:=]+[^[:space:]"'\'']{8,}'
    'secret["[:space:]:=]+[^[:space:]"'\'']{8,}'
    'api_key["[:space:]:=]+[^[:space:]"'\'']{8,}'
    'apikey["[:space:]:=]+[^[:space:]"'\'']{8,}'
    'auth_token["[:space:]:=]+[^[:space:]"'\'']{8,}'
    'access_token["[:space:]:=]+[^[:space:]"'\'']{8,}'
)

# Optional redaction patterns - applied when ACFS_SANITIZE_OPTIONAL=1
# These may have higher false positive rates
readonly OPTIONAL_REDACT_PATTERNS=(
    # IPv4 addresses
    '\b[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b'

    # Email addresses
    '\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b'
)

# Sanitize content by applying redaction patterns
# Usage: sanitize_content "content string"
# Returns: sanitized content via stdout
sanitize_content() {
    local content="$1"
    local result="$content"

    # Apply core redaction patterns
    for pattern in "${REDACT_PATTERNS[@]}"; do
        # Use sed with extended regex for pattern replacement
        result=$(echo "$result" | sed -E "s/${pattern}/[REDACTED]/gi" 2>/dev/null || echo "$result")
    done

    # Apply optional patterns if enabled
    if [[ "${ACFS_SANITIZE_OPTIONAL:-0}" == "1" ]]; then
        for pattern in "${OPTIONAL_REDACT_PATTERNS[@]}"; do
            result=$(echo "$result" | sed -E "s/${pattern}/[REDACTED]/gi" 2>/dev/null || echo "$result")
        done
    fi

    echo "$result"
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
    if ! jq -e . "$file" >/dev/null 2>&1; then
        log_error "Invalid JSON in session export: $file"
        return 1
    fi

    # Create temp file for atomic write
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/acfs_session_sanitize.XXXXXX" 2>/dev/null) || tmpfile="/tmp/acfs_session_sanitize.$$"

    # Sanitize all string values in the JSON
    # This processes the transcript content, summary, key_prompts, etc.
    # Using heredoc to avoid shell quoting issues with jq regex patterns
    local jq_filter
    read -r -d '' jq_filter <<'JQ_EOF'
def sanitize_string:
    if type == "string" then
        gsub("sk-[a-zA-Z0-9]{20,}"; "[REDACTED]") |
        gsub("sk-ant-[a-zA-Z0-9_-]{20,}"; "[REDACTED]") |
        gsub("AIza[a-zA-Z0-9_-]{35}"; "[REDACTED]") |
        gsub("ghp_[a-zA-Z0-9]{36}"; "[REDACTED]") |
        gsub("gho_[a-zA-Z0-9]{36}"; "[REDACTED]") |
        gsub("ghs_[a-zA-Z0-9]{36}"; "[REDACTED]") |
        gsub("ghr_[a-zA-Z0-9]{36}"; "[REDACTED]") |
        gsub("xoxb-[a-zA-Z0-9-]+"; "[REDACTED]") |
        gsub("xoxp-[a-zA-Z0-9-]+"; "[REDACTED]") |
        gsub("AKIA[A-Z0-9]{16}"; "[REDACTED]") |
        gsub("(?i)password[\"\\s:=]+[^\\s\"']{8,}"; "[REDACTED]") |
        gsub("(?i)secret[\"\\s:=]+[^\\s\"']{8,}"; "[REDACTED]") |
        gsub("(?i)api_key[\"\\s:=]+[^\\s\"']{8,}"; "[REDACTED]") |
        gsub("(?i)apikey[\"\\s:=]+[^\\s\"']{8,}"; "[REDACTED]") |
        gsub("(?i)auth_token[\"\\s:=]+[^\\s\"']{8,}"; "[REDACTED]") |
        gsub("(?i)access_token[\"\\s:=]+[^\\s\"']{8,}"; "[REDACTED]")
    elif type == "array" then
        map(sanitize_string)
    elif type == "object" then
        with_entries(.value |= sanitize_string)
    else
        .
    end;
sanitize_string
JQ_EOF

    if ! jq "$jq_filter" "$file" > "$tmpfile"; then
        rm -f "$tmpfile"
        log_error "Failed to sanitize session export"
        return 1
    fi

    # Atomic replace
    mv "$tmpfile" "$file"
    return 0
}

# Check if content contains potential secrets (pre-sanitization check)
# Usage: contains_secrets "content string"
# Returns: 0 if secrets detected, 1 if clean
contains_secrets() {
    local content="$1"

    for pattern in "${REDACT_PATTERNS[@]}"; do
        if echo "$content" | grep -qE "$pattern" 2>/dev/null; then
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
                days="$2"
                shift 2
                ;;
            --agent)
                agent="$2"
                shift 2
                ;;
            --limit)
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

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                format="$2"
                shift 2
                ;;
            --no-sanitize)
                sanitize=false
                shift
                ;;
            --output|-o)
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

    # Check CASS is installed
    if ! check_cass_installed; then
        log_error "CASS not installed"
        return 1
    fi

    # Export via CASS
    local exported
    exported=$(cass export "$session_path" --format "$format" 2>/dev/null)

    if [[ -z "$exported" ]]; then
        log_error "Failed to export session: $session_path"
        return 1
    fi

    # Apply sanitization if requested (and format is json)
    if [[ "$sanitize" == "true" && "$format" == "json" ]]; then
        # Create temp file for sanitization
        local tmpfile
        tmpfile=$(mktemp "${TMPDIR:-/tmp}/acfs_session_export.XXXXXX" 2>/dev/null) || tmpfile="/tmp/acfs_session_export.$$"
        printf '%s' "$exported" > "$tmpfile"

        # Apply sanitization
        if sanitize_session_export "$tmpfile"; then
            exported=$(cat "$tmpfile")
        else
            log_warn "Sanitization failed, returning unsanitized export"
        fi
        rm -f "$tmpfile"
    elif [[ "$sanitize" == "true" && "$format" != "json" ]]; then
        # For non-JSON formats, apply text sanitization
        exported=$(sanitize_content "$exported")
    fi

    # Output
    if [[ -n "$output_file" ]]; then
        printf '%s' "$exported" > "$output_file"
        log_success "Exported to: $output_file"
    else
        echo "$exported"
    fi
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
# Usage: convert_to_acfs_schema <cass_json>
# Returns: ACFS-schema JSON to stdout
convert_to_acfs_schema() {
    local cass_json="$1"

    echo "$cass_json" | jq '
        {
            schema_version: 1,
            exported_at: (now | todate),
            session_id: (.[0].sessionId // "unknown"),
            agent: (.[0].agentId // "unknown"),
            model: (.[0].message.model // "unknown"),
            summary: "Exported session",
            duration_minutes: 0,
            stats: {
                turns: (length // 0),
                files_created: 0,
                files_modified: 0,
                commands_run: 0
            },
            outcomes: [],
            key_prompts: [],
            sanitized_transcript: [
                .[] | {
                    role: .message.role,
                    content: (if .message.content | type == "string" then .message.content else (.message.content[0].text // "") end),
                    timestamp: .timestamp
                }
            ]
        }
    ' 2>/dev/null
}

# ============================================================
# SESSION IMPORT
# ============================================================

# Default session storage directory
ACFS_SESSIONS_DIR="${ACFS_SESSIONS_DIR:-${HOME}/.acfs/sessions}"

# Generate a unique session ID
generate_session_id() {
    head -c 4 /dev/urandom | xxd -p
}

# Import a session file for local viewing/reference
# Usage: import_session <file> [--dry-run]
import_session() {
    local file=""
    local dry_run=false

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
    jq -e '.[0].sessionId' "$file" >/dev/null 2>&1 && is_cass=true
    jq -e '.schema_version' "$file" >/dev/null 2>&1 && is_acfs=true

    # Extract metadata
    local session_id agent turn_count first_ts last_ts
    if [[ "$is_cass" == "true" ]]; then
        session_id=$(jq -r '.[0].sessionId // "unknown"' "$file")
        agent=$(jq -r '.[0].agentId // "unknown"' "$file")
        turn_count=$(jq 'length' "$file")
        first_ts=$(jq -r '.[0].timestamp // ""' "$file")
        last_ts=$(jq -r '.[-1].timestamp // ""' "$file")
    elif [[ "$is_acfs" == "true" ]]; then
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

    mkdir -p "$ACFS_SESSIONS_DIR"
    local local_id; local_id=$(generate_session_id)
    local dest="$ACFS_SESSIONS_DIR/${local_id}.json"

    if [[ "$is_cass" == "true" ]]; then
        convert_to_acfs_schema "$(cat "$file")" > "$dest"
    else
        cp "$file" "$dest"
    fi

    echo ""
    echo "Imported as: $local_id"
    echo "View with: show_session $local_id"
}

# Show an imported session
# Usage: show_session <id> [--format json|markdown|summary]
show_session() {
    local session_id="" format="summary"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2 ;;
            -*) shift ;;
            *) session_id="$1"; shift ;;
        esac
    done

    if [[ -z "$session_id" ]]; then
        log_error "Session ID required"
        return 1
    fi

    local file="$ACFS_SESSIONS_DIR/${session_id}.json"
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
    if [[ ! -d "$ACFS_SESSIONS_DIR" ]]; then
        echo "No imported sessions. Import with: import_session <file.json>"
        return 0
    fi

    echo ""
    echo "Imported Sessions:"
    printf "  %-10s %-12s %-20s\n" "ID" "AGENT" "SESSION_ID"
    echo "  $(printf '%.0s-' {1..50})"

    for f in "$ACFS_SESSIONS_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        local id; id=$(basename "$f" .json)
        jq -r '"  \("'"$id"'")   \(.agent[:12])   \(.session_id)"' "$f" 2>/dev/null
    done
}
