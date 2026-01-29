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
if [[ -z "${_ACFS_LOGGING_SH_LOADED:-}" ]]; then
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

# Sanitize content by applying redaction patterns
# Usage: sanitize_content "content string"
# Returns: sanitized content via stdout
sanitize_content() {
    local content="$1"
    local result="$content"
    local sed_flags="g"

    # BSD sed doesn't support case-insensitive replacement flags. Prefer gI when available.
    if printf 'test' | sed -E 's/test/TEST/gI' >/dev/null 2>&1; then
        sed_flags="gI"
    fi

    # Apply core redaction patterns
    for pattern in "${REDACT_PATTERNS[@]}"; do
        # Use sed with extended regex for pattern replacement
        local next_result
        if next_result=$(printf '%s' "$result" | sed -E "s/${pattern}/[REDACTED]/${sed_flags}" 2>/dev/null); then
            result="$next_result"
        else
            log_error "Sanitization failed for pattern: $pattern"
            return 1
        fi
    done

    # Redact common key/value secrets while preserving surrounding structure.
    #
    # Examples:
    #   password="secret"         -> password="[REDACTED]"
    #   {"password": "secret"}    -> {"password": "[REDACTED]"}
    #
    # We intentionally do this as a separate pass because we need capture groups
    # in the replacement to keep the key/delimiter/quotes.
    local kv_pattern
    # Stop before common trailing delimiters so we don't swallow surrounding syntax like `}`, `,`, `;`, etc.
    #
    # Note: To include a literal `]` in a bracket expression portably, it must appear first.
    # Also exclude `[` so we don't partially match already-redacted values like "[REDACTED]".
    kv_pattern="([\"']?)(password|secret|api_key|apikey|auth_token|access_token)([\"']?)([[:space:]]*[:=][[:space:]]*)([\"']?)[^][[:space:]\"'}),;[]{8,}([\"']?)"
    local next_kv_result
    if next_kv_result=$(printf '%s' "$result" | sed -E "s/${kv_pattern}/\\1\\2\\3\\4\\5[REDACTED]\\6/${sed_flags}" 2>/dev/null); then
        result="$next_kv_result"
    else
        log_error "Sanitization failed for key/value secrets"
        return 1
    fi

    # Apply optional patterns if enabled
    if [[ "${ACFS_SANITIZE_OPTIONAL:-0}" == "1" ]]; then
        for pattern in "${OPTIONAL_REDACT_PATTERNS[@]}"; do
            local next_result
            if next_result=$(printf '%s' "$result" | sed -E "s/${pattern}/[REDACTED]/${sed_flags}" 2>/dev/null); then
                result="$next_result"
            else
                log_error "Sanitization failed for optional pattern: $pattern"
                return 1
            fi
        done
    fi

    printf '%s\n' "$result"
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
    # Note: don't use bash parameter substitution with patterns starting with "#"
    # (e.g. "##OPTIONAL##"), because `${var/#pattern/...}` is special-cased.
    local jq_filter_base
    read -r -d '' jq_filter_base <<'JQ_BASE' || true
def sanitize_string:
    if type == "string" then
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
        gsub("(?i)password[\"\\s:=]+[\"']?[^\\s\"'\\}\\]\\),;\\[]{8,}[\"']?"; "password=[REDACTED]") |
        gsub("(?i)secret[\"\\s:=]+[\"']?[^\\s\"'\\}\\]\\),;\\[]{8,}[\"']?"; "secret=[REDACTED]") |
        gsub("(?i)api_key[\"\\s:=]+[\"']?[^\\s\"'\\}\\]\\),;\\[]{8,}[\"']?"; "api_key=[REDACTED]") |
        gsub("(?i)apikey[\"\\s:=]+[\"']?[^\\s\"'\\}\\]\\),;\\[]{8,}[\"']?"; "apikey=[REDACTED]") |
        gsub("(?i)auth_token[\"\\s:=]+[\"']?[^\\s\"'\\}\\]\\),;\\[]{8,}[\"']?"; "auth_token=[REDACTED]") |
        gsub("(?i)access_token[\"\\s:=]+[\"']?[^\\s\"'\\}\\]\\),;\\[]{8,}[\"']?"; "access_token=[REDACTED]")
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
        map(sanitize_string)
    elif type == "object" then
        with_entries(.value |= sanitize_string)
    else
        .
    end;
sanitize_string
JQ_TAIL

    local jq_filter="${jq_filter_base}${jq_filter_optional}${jq_filter_tail}"

    if ! jq "$jq_filter" "$file" > "$tmpfile"; then
        rm -f -- "$tmpfile" 2>/dev/null || true
        log_error "Failed to sanitize session export"
        return 1
    fi

    # Atomic replace
    if ! mv -- "$tmpfile" "$file"; then
        rm -f -- "$tmpfile" 2>/dev/null || true
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

    # Ensure cleanup on return
    trap 'rm -f -- "$tmp_export"' RETURN

    # Export via CASS to temp file
    if ! cass export "$session_path" --format "$format" > "$tmp_export" 2>/dev/null; then
        log_error "Failed to export session: $session_path"
        return 1
    fi

    # Verify export is not empty
    if [[ ! -s "$tmp_export" ]]; then
        log_error "Exported session is empty: $session_path"
        return 1
    fi

    # Apply sanitization if requested
    if [[ "$sanitize" == "true" ]]; then
        if [[ "$format" == "json" ]]; then
            # In-place JSON sanitization
            if ! sanitize_session_export "$tmp_export"; then
                log_error "Sanitization failed; refusing to output unsanitized export"
                return 1
            fi
        else
            # Text-based sanitization (stream through sed to new temp file)
            local tmp_sanitized
            tmp_sanitized="${tmp_export}.sanitized"
            if sanitize_content "$(cat "$tmp_export")" > "$tmp_sanitized"; then
                mv -- "$tmp_sanitized" "$tmp_export"
            else
                rm -f -- "$tmp_sanitized"
                log_error "Sanitization failed; refusing to output unsanitized export"
                return 1
            fi
        fi
    fi

    # Output
    if [[ -n "$output_file" ]]; then
        # Move or copy to destination
        # Try mv first (atomic if same fs), fall back to cat (streaming)
        if ! mv -- "$tmp_export" "$output_file" 2>/dev/null; then
            cat "$tmp_export" > "$output_file"
        fi
        log_success "Exported to: $output_file"
        # Since we moved/copied, clear the trap cleanup if we moved it successfully?
        # Actually, if we moved it, the temp file is gone. If we cat, it remains.
        # The trap will run rm -f which ignores missing files.
    else
        cat "$tmp_export"
        # Add newline if needed? cat output preserves original.
        # Usually good to ensure newline at end of output for CLI niceness if missing.
        # But for JSON/Markdown exact output is preferred.
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
# SESSION IMPORT
# ============================================================

# Default session storage directory
ACFS_SESSIONS_DIR="${ACFS_SESSIONS_DIR:-${HOME}/.acfs/sessions}"

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
                ([.[] | select(.type == "session_meta") | .payload.id?] | map(select(type == "string" and length > 0)) | .[0]) // "unknown"
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
        local tmp_dest
        tmp_dest=$(mktemp "${ACFS_SESSIONS_DIR}/.${local_id}.XXXXXX.tmp" 2>/dev/null) || {
            log_error "Failed to create temp file for import in: $ACFS_SESSIONS_DIR"
            return 1
        }

        if ! convert_to_acfs_schema "$file" "$agent" > "$tmp_dest"; then
            rm -f -- "$tmp_dest" 2>/dev/null || true
            log_error "Failed to convert CASS export to ACFS schema"
            return 1
        fi

        # Always sanitize imported output before persisting.
        if ! sanitize_session_export "$tmp_dest"; then
            rm -f -- "$tmp_dest" 2>/dev/null || true
            log_error "Sanitization failed; refusing to import unsanitized session"
            return 1
        fi

        if ! mv -- "$tmp_dest" "$dest"; then
            rm -f -- "$tmp_dest" 2>/dev/null || true
            log_error "Failed to write imported session: $dest"
            return 1
        fi
    else
        local tmp_dest
        tmp_dest=$(mktemp "${ACFS_SESSIONS_DIR}/.${local_id}.XXXXXX.tmp" 2>/dev/null) || {
            log_error "Failed to create temp file for import in: $ACFS_SESSIONS_DIR"
            return 1
        }

        if ! cp -- "$file" "$tmp_dest"; then
            rm -f -- "$tmp_dest" 2>/dev/null || true
            log_error "Failed to copy session export into staging file"
            return 1
        fi

        # Always sanitize imported output before persisting.
        if ! sanitize_session_export "$tmp_dest"; then
            rm -f -- "$tmp_dest" 2>/dev/null || true
            log_error "Sanitization failed; refusing to import unsanitized session"
            return 1
        fi

        if ! mv -- "$tmp_dest" "$dest"; then
            rm -f -- "$tmp_dest" 2>/dev/null || true
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
