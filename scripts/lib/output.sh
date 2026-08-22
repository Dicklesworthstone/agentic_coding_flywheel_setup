#!/usr/bin/env bash
# ============================================================
# ACFS Output Formatting Library
#
# Provides TOON and JSON output formatting support.
# Uses tru binary (toon_rust) for TOON encoding.
#
# Usage:
#   source "${SCRIPT_DIR}/output.sh"
#
#   # Resolve output format from CLI and environment
#   format=$(acfs_resolve_format "$cli_format")
#
#   # Format and emit JSON data
#   acfs_format_output "$json_data" "$format" "$show_stats"
#
# Environment Variables:
#   ACFS_OUTPUT_FORMAT   - Default format (json|toon)
#   TOON_DEFAULT_FORMAT  - Global TOON default (fallback)
#
# Related beads:
#   - bd-a7o: Integrate TOON into acfs
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_OUTPUT_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_ACFS_OUTPUT_SH_LOADED=1

# ============================================================
# TOON Availability Check
# ============================================================

# Check if the toon binary (installed by toon_rust, installer key tru) is available
_acfs_tru_available() {
    command -v toon &>/dev/null
}

# ============================================================
# Format Resolution
# ============================================================

# Resolve output format from CLI argument and environment variables
# Precedence: CLI > ACFS_OUTPUT_FORMAT > TOON_DEFAULT_FORMAT > default (json)
#
# Usage: format=$(acfs_resolve_format "$cli_format")
# Arguments:
#   $1 - CLI format argument (optional, may be empty)
# Returns: "json" or "toon"
acfs_resolve_format() {
    local cli_format="${1:-}"
    local fmt=""

    # CLI argument takes precedence
    if [[ -n "$cli_format" ]]; then
        fmt="${cli_format,,}"  # lowercase
    elif [[ -n "${ACFS_OUTPUT_FORMAT:-}" ]]; then
        fmt="${ACFS_OUTPUT_FORMAT,,}"
    elif [[ -n "${TOON_DEFAULT_FORMAT:-}" ]]; then
        fmt="${TOON_DEFAULT_FORMAT,,}"
    else
        fmt="json"
    fi

    # Validate and normalize (fmt is already lowercase)
    case "$fmt" in
        toon)
            echo "toon"
            ;;
        *)
            echo "json"
            ;;
    esac
}

# ============================================================
# Output Formatting
# ============================================================

# Format and emit JSON data in the specified format
#
# Usage: acfs_format_output "$json_data" "$format" "$show_stats"
# Arguments:
#   $1 - JSON data string
#   $2 - Output format ("json" or "toon")
#   $3 - Show stats flag ("true" or "false", optional)
# Output: Formatted data to stdout, stats to stderr
acfs_format_output() {
    local json_data="$1"
    local format="${2:-json}"
    local show_stats="${3:-false}"

    case "$format" in
        toon|TOON)
            if _acfs_tru_available; then
                local toon_data
                toon_data=$(printf '%s' "$json_data" | toon --encode 2>/dev/null)

                # If encoding failed (empty output), fall back to JSON
                if [[ -z "$toon_data" ]]; then
                    echo "[acfs] Warning: toon encoding failed, falling back to JSON" >&2
                    printf '%s\n' "$json_data"
                    return 0
                fi

                if [[ "$show_stats" == "true" ]]; then
                    local json_bytes toon_bytes savings
                    json_bytes=$(printf '%s' "$json_data" | wc -c)
                    toon_bytes=$(printf '%s' "$toon_data" | wc -c)
                    if [[ $json_bytes -gt 0 ]]; then
                        savings=$(( 100 - (toon_bytes * 100 / json_bytes) ))
                    else
                        savings=0
                    fi
                    printf '[acfs-toon] JSON: %d bytes, TOON: %d bytes (%d%% savings)\n' \
                        "$json_bytes" "$toon_bytes" "$savings" >&2
                fi

                printf '%s\n' "$toon_data"
            else
                echo "[acfs] Warning: toon (toon_rust) not found, falling back to JSON" >&2
                if [[ "$show_stats" == "true" ]]; then
                    local json_bytes
                    json_bytes=$(printf '%s' "$json_data" | wc -c)
                    printf '[acfs-toon] JSON: %d bytes (TOON unavailable)\n' "$json_bytes" >&2
                fi
                printf '%s\n' "$json_data"
            fi
            ;;
        *)
            # JSON output - show potential TOON savings if stats requested
            if [[ "$show_stats" == "true" ]]; then
                local json_bytes
                json_bytes=$(printf '%s' "$json_data" | wc -c)

                if _acfs_tru_available; then
                    local toon_data toon_bytes savings
                    toon_data=$(printf '%s' "$json_data" | toon --encode 2>/dev/null)
                    if [[ -n "$toon_data" ]]; then
                        toon_bytes=$(printf '%s' "$toon_data" | wc -c)
                        if [[ $json_bytes -gt 0 ]]; then
                            savings=$(( 100 - (toon_bytes * 100 / json_bytes) ))
                        else
                            savings=0
                        fi
                        printf '[acfs-toon] JSON: %d bytes, TOON would be: %d bytes (%d%% potential savings)\n' \
                            "$json_bytes" "$toon_bytes" "$savings" >&2
                    else
                        printf '[acfs-toon] JSON: %d bytes (TOON unavailable for comparison)\n' "$json_bytes" >&2
                    fi
                else
                    printf '[acfs-toon] JSON: %d bytes (TOON unavailable for comparison)\n' "$json_bytes" >&2
                fi
            fi
            printf '%s\n' "$json_data"
            ;;
    esac
}

# ============================================================
# Verification
# ============================================================

# Verify TOON round-trip preserves data integrity
#
# Usage: acfs_verify_roundtrip "$json_data"
# Returns: 0 if round-trip matches, 1 otherwise
acfs_verify_roundtrip() {
    local original="$1"

    if ! _acfs_tru_available; then
        echo "[acfs] Error: toon (toon_rust) not available for round-trip verification" >&2
        return 1
    fi

    local encoded decoded
    encoded=$(printf '%s' "$original" | toon --encode 2>/dev/null) || return 1
    decoded=$(printf '%s' "$encoded" | toon --decode 2>/dev/null) || return 1

    # Normalize JSON for comparison (if jq is available)
    if command -v jq &>/dev/null; then
        local orig_norm dec_norm
        orig_norm=$(printf '%s' "$original" | jq -S . 2>/dev/null)
        dec_norm=$(printf '%s' "$decoded" | jq -S . 2>/dev/null)
        [[ "$orig_norm" == "$dec_norm" ]]
    else
        # Fallback: simple string comparison
        [[ "$original" == "$decoded" ]]
    fi
}
