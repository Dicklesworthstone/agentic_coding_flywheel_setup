#!/usr/bin/env bash
# ============================================================
# ACFS Swarm Packet - per-agent startup packet generator
#
# Builds a bounded, read-only prompt packet for one Beads issue. The packet
# packages current repo instructions, Beads metadata, bounded CASS/CM context,
# and Agent Mail/RCH/UBS workflow commands for NTM prompt injection.
# ============================================================

set -euo pipefail

SWARM_PACKET_FORMAT="markdown"
SWARM_PACKET_BEAD_ID=""
SWARM_PACKET_BEAD_FILE=""
SWARM_PACKET_REPO_ROOT="${PWD}"
SWARM_PACKET_AGENT_NAME="${AGENT_NAME:-agent}"
SWARM_PACKET_ROLE="implementation"
SWARM_PACKET_MAX_CHARS=9000
SWARM_PACKET_CM_FILE=""
SWARM_PACKET_CASS_FILE=""
SWARM_PACKET_AGENTS_FILE=""
SWARM_PACKET_README_FILE=""
SWARM_PACKET_NO_LIVE_CONTEXT=false
SWARM_PACKET_WARNINGS=()

swarm_packet_usage() {
    cat <<'EOF'
Usage: acfs swarm packet --bead ID [OPTIONS]

Options:
  --json                Emit machine-readable JSON
  --markdown            Emit Markdown packet (default)
  --bead ID             Beads issue ID, for example bd-1234
  --bead-id ID          Alias for --bead
  --bead-file FILE      Read Beads JSON from a fixture or saved br show output
  --repo PATH           Repository root (default: current directory)
  --agent-name NAME     Agent identity or launch slot label
  --role NAME           Agent role hint (default: implementation)
  --max-chars N         Maximum Markdown packet size (default: 9000)
  --agents-file FILE    AGENTS.md path override
  --readme-file FILE    README.md path override
  --cm-file FILE        Bounded CM context fixture
  --cass-file FILE      Bounded CASS search fixture
  --no-live-context     Do not run cm or cass when fixture files are absent
  --help, -h            Show this help

The generator is read-only. It does not update Beads, send Agent Mail, reserve
files, start agents, run builds, or edit generated files.
EOF
}

swarm_packet_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                SWARM_PACKET_FORMAT="json"
                shift
                ;;
            --markdown)
                SWARM_PACKET_FORMAT="markdown"
                shift
                ;;
            --bead|--bead-id)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: $1 requires a Beads issue ID" >&2
                    return 2
                fi
                SWARM_PACKET_BEAD_ID="$2"
                shift 2
                ;;
            --bead-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --bead-file requires a path" >&2
                    return 2
                fi
                SWARM_PACKET_BEAD_FILE="$2"
                shift 2
                ;;
            --repo)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --repo requires a path" >&2
                    return 2
                fi
                SWARM_PACKET_REPO_ROOT="$2"
                shift 2
                ;;
            --agent-name)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --agent-name requires a value" >&2
                    return 2
                fi
                SWARM_PACKET_AGENT_NAME="$2"
                shift 2
                ;;
            --role)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --role requires a value" >&2
                    return 2
                fi
                SWARM_PACKET_ROLE="$2"
                shift 2
                ;;
            --max-chars)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --max-chars requires a positive integer" >&2
                    return 2
                fi
                SWARM_PACKET_MAX_CHARS="$2"
                shift 2
                ;;
            --agents-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --agents-file requires a path" >&2
                    return 2
                fi
                SWARM_PACKET_AGENTS_FILE="$2"
                shift 2
                ;;
            --readme-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --readme-file requires a path" >&2
                    return 2
                fi
                SWARM_PACKET_README_FILE="$2"
                shift 2
                ;;
            --cm-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --cm-file requires a path" >&2
                    return 2
                fi
                SWARM_PACKET_CM_FILE="$2"
                shift 2
                ;;
            --cass-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --cass-file requires a path" >&2
                    return 2
                fi
                SWARM_PACKET_CASS_FILE="$2"
                shift 2
                ;;
            --no-live-context)
                SWARM_PACKET_NO_LIVE_CONTEXT=true
                shift
                ;;
            --help|-h)
                swarm_packet_usage
                return 100
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs swarm packet --help' for usage." >&2
                return 2
                ;;
        esac
    done

    if [[ -z "$SWARM_PACKET_BEAD_ID" && -z "$SWARM_PACKET_BEAD_FILE" ]]; then
        echo "Error: --bead or --bead-file is required" >&2
        return 2
    fi

    if [[ ! "$SWARM_PACKET_MAX_CHARS" =~ ^[0-9]+$ ]] || (( SWARM_PACKET_MAX_CHARS < 2000 )); then
        echo "Error: --max-chars requires an integer >= 2000" >&2
        return 2
    fi

    if [[ ! -d "$SWARM_PACKET_REPO_ROOT" ]]; then
        echo "Error: repository root not found: $SWARM_PACKET_REPO_ROOT" >&2
        return 2
    fi

    SWARM_PACKET_REPO_ROOT="$(cd "$SWARM_PACKET_REPO_ROOT" && pwd)"
    if [[ -z "$SWARM_PACKET_AGENTS_FILE" ]]; then
        SWARM_PACKET_AGENTS_FILE="$SWARM_PACKET_REPO_ROOT/AGENTS.md"
    fi
    if [[ -z "$SWARM_PACKET_README_FILE" ]]; then
        SWARM_PACKET_README_FILE="$SWARM_PACKET_REPO_ROOT/README.md"
    fi
}

swarm_packet_binary_path() {
    local name="${1:-}"
    local path_value=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..|*/*) return 1 ;;
    esac

    path_value="$(command -v "$name" 2>/dev/null || true)"
    [[ -n "$path_value" && -x "$path_value" ]] || return 1
    printf '%s\n' "$path_value"
}

swarm_packet_read_file_excerpt() {
    local path_value="$1"
    local label="$2"
    local max_bytes="$3"
    local byte_count=""
    local excerpt=""

    if [[ ! -f "$path_value" ]]; then
        SWARM_PACKET_WARNINGS+=("$label not found: $path_value")
        return 0
    fi

    byte_count="$(wc -c < "$path_value" | tr -d '[:space:]')"
    excerpt="$(LC_ALL=C head -c "$max_bytes" "$path_value")"
    if [[ "$byte_count" =~ ^[0-9]+$ ]] && (( byte_count > max_bytes )); then
        excerpt+=$'\n[truncated for packet size]'
    fi
    printf '%s' "$excerpt"
}

swarm_packet_limit_text() {
    local text="$1"
    local max_bytes="$2"

    if (( ${#text} > max_bytes )); then
        printf '%s\n[truncated for packet size]' "${text:0:max_bytes}"
    else
        printf '%s' "$text"
    fi
}

swarm_packet_sanitize_context_text() {
    local text="$1"

    # Two concerns, one pass:
    #  1. Neutralize dangerous command examples so a packet can never teach
    #     an agent a forbidden command verbatim.
    #  2. Redact secret-shaped values. cass/cm excerpts replay agent session
    #     history, which can contain tokens or passwords that were echoed in
    #     past sessions; a work packet is handed to other agents and must
    #     not carry live credentials. Token shapes mirror the sensitive-value
    #     scan in swarm_inventory.sh.
    printf '%s' "$text" | sed -E \
        -e 's/rm[[:space:]]+-rf/[unsafe cleanup command redacted]/g' \
        -e 's/git[[:space:]]+reset[[:space:]]+--hard/[destructive git command redacted]/g' \
        -e 's/git[[:space:]]+clean[[:space:]]+-fd/[destructive git cleanup command redacted]/g' \
        -e 's/^([[:space:]]*)bv([[:space:]]*)$/\1bv --robot-next\2/g' \
        -e 's/^([[:space:]]*)bd[[:space:]]+/\1br /g' \
        -e 's/^([[:space:]]*)cargo[[:space:]]+(test|build|clippy)/\1rch exec -- cargo \2/g' \
        -e 's/(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}/[github token redacted]/g' \
        -e 's/github_pat_[A-Za-z0-9_]{20,}/[github token redacted]/g' \
        -e 's/tskey-[A-Za-z0-9-]{10,}/[tailscale key redacted]/g' \
        -e 's/sk-[A-Za-z0-9_-]{20,}/[api key redacted]/g' \
        -e 's/hvs\.[A-Za-z0-9_-]{20,}/[vault token redacted]/g' \
        -e 's/xox[bpsar]-[A-Za-z0-9-]{10,}/[slack token redacted]/g' \
        -e 's/AKIA[0-9A-Z]{16}/[aws key id redacted]/g' \
        -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----/[private key redacted]/g' \
        -e 's/([Aa]uthorization:[[:space:]]*)(Bearer|Basic)[[:space:]]+[A-Za-z0-9._~+\/=-]+/\1[credential redacted]/g' \
        -e 's/(([A-Z0-9_]*(PASSWORD|SECRET|TOKEN|API_?KEY|ACCESS_KEY|PRIVATE_KEY)[A-Z0-9_]*)[[:space:]]*[=:][[:space:]]*)[^[:space:]"'"'"']+/\1[redacted]/g' \
        -e 's/("(password|passwd|secret|token|api_key|apikey|access_key|private_key)"[[:space:]]*:[[:space:]]*")[^"]*(")/\1[redacted]\3/g'
}

swarm_packet_collect_tool_context() {
    local tool_name="$1"
    local fixture_file="$2"
    local query="$3"
    local max_bytes="$4"
    local output=""
    local status=0
    local timeout_bin=""

    if [[ -n "$fixture_file" ]]; then
        swarm_packet_read_file_excerpt "$fixture_file" "$tool_name context fixture" "$max_bytes"
        return 0
    fi

    if [[ "$SWARM_PACKET_NO_LIVE_CONTEXT" == true ]]; then
        SWARM_PACKET_WARNINGS+=("$tool_name context unavailable: no fixture file supplied and live context disabled")
        return 0
    fi

    if ! swarm_packet_binary_path "$tool_name" >/dev/null 2>&1; then
        SWARM_PACKET_WARNINGS+=("$tool_name context unavailable: command not found")
        return 0
    fi

    timeout_bin="$(swarm_packet_binary_path timeout 2>/dev/null || true)"
    set +e
    if [[ "$tool_name" == "cm" ]]; then
        if [[ -n "$timeout_bin" ]]; then
            output="$("$timeout_bin" 12s cm context "$query" --workspace "$SWARM_PACKET_REPO_ROOT" --limit 5 --history 3 --json 2>&1)"
        else
            output="$(cm context "$query" --workspace "$SWARM_PACKET_REPO_ROOT" --limit 5 --history 3 --json 2>&1)"
        fi
    else
        if [[ -n "$timeout_bin" ]]; then
            output="$("$timeout_bin" 12s cass search "$query" --workspace "$SWARM_PACKET_REPO_ROOT" --limit 5 --fields summary --json --max-tokens 1200 2>&1)"
        else
            output="$(cass search "$query" --workspace "$SWARM_PACKET_REPO_ROOT" --limit 5 --fields summary --json --max-tokens 1200 2>&1)"
        fi
    fi
    status=$?
    set -e

    if [[ $status -ne 0 ]]; then
        SWARM_PACKET_WARNINGS+=("$tool_name context unavailable: command exited $status")
        return 0
    fi

    swarm_packet_limit_text "$output" "$max_bytes"
}

swarm_packet_collect_bead_json() {
    local raw_json=""

    if [[ -n "$SWARM_PACKET_BEAD_FILE" ]]; then
        if [[ ! -f "$SWARM_PACKET_BEAD_FILE" ]]; then
            echo "Error: bead file not found: $SWARM_PACKET_BEAD_FILE" >&2
            return 2
        fi
        raw_json="$(cat "$SWARM_PACKET_BEAD_FILE")"
    else
        if ! swarm_packet_binary_path br >/dev/null 2>&1; then
            echo "Error: br is required when --bead-file is not supplied" >&2
            return 2
        fi
        raw_json="$(cd "$SWARM_PACKET_REPO_ROOT" && br show "$SWARM_PACKET_BEAD_ID" --json)"
    fi

    if ! jq -e . >/dev/null 2>&1 <<<"$raw_json"; then
        echo "Error: Beads JSON is malformed" >&2
        return 2
    fi

    jq -c 'if type == "array" then .[0] else . end' <<<"$raw_json"
}

swarm_packet_indent_text() {
    sed 's/^/    /'
}

swarm_packet_json_array_from_args() {
    local jq_bin="$1"
    shift

    if [[ $# -eq 0 ]]; then
        printf '[]'
        return 0
    fi

    printf '%s\n' "$@" | "$jq_bin" -R . | "$jq_bin" -s .
}

swarm_packet_build_markdown() {
    local bead_id="$1"
    local bead_title="$2"
    local bead_status="$3"
    local bead_priority="$4"
    local bead_labels="$5"
    local agents_excerpt="$6"
    local readme_excerpt="$7"
    local cm_context="$8"
    local cass_context="$9"
    local warnings_block="${10}"
    local agents_block=""
    local readme_block=""
    local cm_block=""
    local cass_block=""

    agents_block="$(printf '%s\n' "$agents_excerpt" | swarm_packet_indent_text)"
    readme_block="$(printf '%s\n' "$readme_excerpt" | swarm_packet_indent_text)"
    cm_block="$(printf '%s\n' "$cm_context" | swarm_packet_indent_text)"
    cass_block="$(printf '%s\n' "$cass_context" | swarm_packet_indent_text)"

    cat <<EOF
# ACFS Swarm Startup Packet

Agent: $SWARM_PACKET_AGENT_NAME
Role: $SWARM_PACKET_ROLE
Repository: $SWARM_PACKET_REPO_ROOT
Bead: $bead_id
Title: $bead_title
Status: $bead_status
Priority: $bead_priority
Labels: $bead_labels

## Source Priority

1. Current AGENTS.md, README.md, and live code in this repository.
2. Current Beads output for $bead_id.
3. Agent Mail reservations and inbox state.
4. Bounded CM and CASS context below, used only as hints because it may drift.

## Start Checks

Run these before editing:

    bv --robot-next
    bv --robot-triage
    br ready --json
    br show $bead_id --json

Confirm $bead_id is still ready or intentionally assigned to you. If live Beads or repo instructions disagree with this packet, follow the live repo.

## Agent Mail

Use MCP Agent Mail before editing:

    fetch_inbox(project_key="$SWARM_PACKET_REPO_ROOT", agent_name="$SWARM_PACKET_AGENT_NAME", include_bodies=true)
    acknowledge_message(project_key="$SWARM_PACKET_REPO_ROOT", agent_name="$SWARM_PACKET_AGENT_NAME", message_id=<id>)
    file_reservation_paths(project_key="$SWARM_PACKET_REPO_ROOT", agent_name="$SWARM_PACKET_AGENT_NAME", paths=[<exact files>], exclusive=true, reason="$bead_id")
    send_message(project_key="$SWARM_PACKET_REPO_ROOT", sender_name="$SWARM_PACKET_AGENT_NAME", to=[<recipient>], thread_id="$bead_id", subject="[$bead_id] Start: $bead_title", body_md=<short plan>)

Reserve only the files you will edit. If reservations conflict, narrow the path set or pick another ready Bead.

## Work Rules

- Keep the slice narrow and tied to $bead_id.
- Do not manually edit generated files under scripts/generated.
- Do not delete files or run destructive cleanup.
- Use only robot BV modes in automated sessions.
- Use RCH for CPU-heavy Rust gates:

    rch exec -- cargo test
    rch exec -- cargo clippy

- Run focused gates first, then widen to the repo-required gates for touched surfaces.
- Run UBS on changed files before committing:

    ubs \$(git diff --name-only --cached)

## Closeout

After implementation and verification:

    br close $bead_id --reason "Completed"
    br sync --flush-only
    git push origin main
    git push origin main:master

Then release Agent Mail reservations and send a completion message in thread $bead_id with commit, gates, and any follow-up Beads.

## Drift Checks

- Re-read AGENTS.md and README.md sections that affect the touched files.
- Re-run br show $bead_id --json before closing.
- Check git status before staging so peer work is not included.
- Treat CM and CASS context as stale unless current files confirm it.

## Current Repo Instructions Excerpt

$agents_block

## README Excerpt

$readme_block

## CM Context

$cm_block

## CASS Context

$cass_block

## Packet Warnings

$warnings_block
EOF
}

swarm_packet_build_report() {
    local jq_bin=""
    local bead_json=""
    local bead_id=""
    local bead_title=""
    local bead_status=""
    local bead_priority=""
    local bead_labels_json=""
    local bead_labels_text=""
    local query=""
    local agents_excerpt=""
    local readme_excerpt=""
    local cm_context=""
    local cass_context=""
    local warnings_json=""
    local warnings_block=""
    local packet_markdown=""
    local output_truncated=false
    local truncate_limit=0
    local status_value="pass"
    local cm_warning_count_before=0
    local cass_warning_count_before=0

    jq_bin="$(swarm_packet_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        echo "Error: jq is required for swarm packet generation" >&2
        return 2
    fi

    bead_json="$(swarm_packet_collect_bead_json)"
    bead_id="$("$jq_bin" -r --arg fallback "$SWARM_PACKET_BEAD_ID" '.id // $fallback' <<<"$bead_json")"
    bead_title="$("$jq_bin" -r '.title // "Untitled Bead"' <<<"$bead_json")"
    bead_status="$("$jq_bin" -r '.status // "unknown"' <<<"$bead_json")"
    bead_priority="$("$jq_bin" -r '(.priority // "unknown") | tostring' <<<"$bead_json")"
    bead_labels_json="$("$jq_bin" -c '.labels // []' <<<"$bead_json")"
    bead_labels_text="$("$jq_bin" -r '(.labels // []) | if length == 0 then "none" else join(", ") end' <<<"$bead_json")"

    if [[ -z "$bead_id" || "$bead_id" == "null" ]]; then
        echo "Error: Beads JSON did not include an issue id" >&2
        return 2
    fi
    SWARM_PACKET_BEAD_ID="$bead_id"

    query="$bead_id $bead_title in $SWARM_PACKET_REPO_ROOT"
    if [[ ! -f "$SWARM_PACKET_AGENTS_FILE" ]]; then
        SWARM_PACKET_WARNINGS+=("AGENTS.md not found: $SWARM_PACKET_AGENTS_FILE")
    fi
    if [[ ! -f "$SWARM_PACKET_README_FILE" ]]; then
        SWARM_PACKET_WARNINGS+=("README.md not found: $SWARM_PACKET_README_FILE")
    fi

    agents_excerpt="$(swarm_packet_read_file_excerpt "$SWARM_PACKET_AGENTS_FILE" "AGENTS.md" 1800)"
    readme_excerpt="$(swarm_packet_read_file_excerpt "$SWARM_PACKET_README_FILE" "README.md" 1600)"
    agents_excerpt="$(swarm_packet_sanitize_context_text "$agents_excerpt")"
    readme_excerpt="$(swarm_packet_sanitize_context_text "$readme_excerpt")"

    cm_warning_count_before=${#SWARM_PACKET_WARNINGS[@]}
    if [[ -n "$SWARM_PACKET_CM_FILE" && ! -f "$SWARM_PACKET_CM_FILE" ]]; then
        SWARM_PACKET_WARNINGS+=("cm context unavailable: fixture not found: $SWARM_PACKET_CM_FILE")
    elif [[ -z "$SWARM_PACKET_CM_FILE" && "$SWARM_PACKET_NO_LIVE_CONTEXT" == true ]]; then
        SWARM_PACKET_WARNINGS+=("cm context unavailable: no fixture file supplied and live context disabled")
    elif [[ -z "$SWARM_PACKET_CM_FILE" ]] && ! swarm_packet_binary_path cm >/dev/null 2>&1; then
        SWARM_PACKET_WARNINGS+=("cm context unavailable: command not found")
    fi
    cm_context="$(swarm_packet_collect_tool_context cm "$SWARM_PACKET_CM_FILE" "$query" 1800)"
    cm_context="$(swarm_packet_sanitize_context_text "$cm_context")"
    if [[ -z "$cm_context" ]]; then
        if (( ${#SWARM_PACKET_WARNINGS[@]} == cm_warning_count_before )); then
            SWARM_PACKET_WARNINGS+=("cm context unavailable: command returned no output")
        fi
        cm_context="No CM context available. Continue from current repo files and Beads."
    fi

    cass_warning_count_before=${#SWARM_PACKET_WARNINGS[@]}
    if [[ -n "$SWARM_PACKET_CASS_FILE" && ! -f "$SWARM_PACKET_CASS_FILE" ]]; then
        SWARM_PACKET_WARNINGS+=("cass context unavailable: fixture not found: $SWARM_PACKET_CASS_FILE")
    elif [[ -z "$SWARM_PACKET_CASS_FILE" && "$SWARM_PACKET_NO_LIVE_CONTEXT" == true ]]; then
        SWARM_PACKET_WARNINGS+=("cass context unavailable: no fixture file supplied and live context disabled")
    elif [[ -z "$SWARM_PACKET_CASS_FILE" ]] && ! swarm_packet_binary_path cass >/dev/null 2>&1; then
        SWARM_PACKET_WARNINGS+=("cass context unavailable: command not found")
    fi
    cass_context="$(swarm_packet_collect_tool_context cass "$SWARM_PACKET_CASS_FILE" "$query" 1800)"
    cass_context="$(swarm_packet_sanitize_context_text "$cass_context")"

    if [[ -z "$cass_context" ]]; then
        if (( ${#SWARM_PACKET_WARNINGS[@]} == cass_warning_count_before )); then
            SWARM_PACKET_WARNINGS+=("cass context unavailable: command returned no output")
        fi
        cass_context="No CASS context available. Continue from current repo files and Beads."
    fi

    warnings_json="$(swarm_packet_json_array_from_args "$jq_bin" "${SWARM_PACKET_WARNINGS[@]}")"
    if [[ "$("$jq_bin" -r 'length' <<<"$warnings_json")" != "0" ]]; then
        status_value="warn"
        warnings_block="$("$jq_bin" -r '.[] | "- " + .' <<<"$warnings_json")"
    else
        warnings_block="- none"
    fi

    packet_markdown="$(swarm_packet_build_markdown \
        "$bead_id" \
        "$bead_title" \
        "$bead_status" \
        "$bead_priority" \
        "$bead_labels_text" \
        "$agents_excerpt" \
        "$readme_excerpt" \
        "$cm_context" \
        "$cass_context" \
        "$warnings_block")"

    if (( ${#packet_markdown} > SWARM_PACKET_MAX_CHARS )); then
        output_truncated=true
        truncate_limit=$((SWARM_PACKET_MAX_CHARS - 90))
        if (( truncate_limit < 1500 )); then
            truncate_limit="$SWARM_PACKET_MAX_CHARS"
        fi
        packet_markdown="$(printf '%s' "$packet_markdown" | LC_ALL=C head -c "$truncate_limit")"$'\n\n[truncated: rerun with a larger --max-chars for more context]'
    fi

    "$jq_bin" -n \
        --arg generated_at "$(date -Iseconds)" \
        --arg status "$status_value" \
        --arg agent_name "$SWARM_PACKET_AGENT_NAME" \
        --arg role "$SWARM_PACKET_ROLE" \
        --arg repo_root "$SWARM_PACKET_REPO_ROOT" \
        --arg agents_file "$SWARM_PACKET_AGENTS_FILE" \
        --arg readme_file "$SWARM_PACKET_README_FILE" \
        --argjson bead "$bead_json" \
        --arg bead_id "$bead_id" \
        --arg bead_title "$bead_title" \
        --arg bead_status "$bead_status" \
        --arg bead_priority "$bead_priority" \
        --argjson bead_labels "$bead_labels_json" \
        --arg agents_excerpt "$agents_excerpt" \
        --arg readme_excerpt "$readme_excerpt" \
        --arg cm_context "$cm_context" \
        --arg cass_context "$cass_context" \
        --argjson warnings "$warnings_json" \
        --arg packet_markdown "$packet_markdown" \
        --argjson max_chars "$SWARM_PACKET_MAX_CHARS" \
        --arg output_truncated "$output_truncated" \
        '{
          schema_version: 1,
          generated_at: $generated_at,
          status: $status,
          agent: {name: $agent_name, role: $role},
          repository: {path: $repo_root, agents_file: $agents_file, readme_file: $readme_file},
          bead: {
            id: $bead_id,
            title: $bead_title,
            status: $bead_status,
            priority: $bead_priority,
            labels: $bead_labels,
            source: $bead
          },
          source_priority: [
            "Current AGENTS.md, README.md, and live code in this repository",
            "Current Beads output for the selected issue",
            "Agent Mail reservations and inbox state",
            "Bounded CM and CASS context as drift-prone hints"
          ],
          context: {
            agents_excerpt: $agents_excerpt,
            readme_excerpt: $readme_excerpt,
            cm: {
              status: (if ($cm_context | startswith("No CM context available.")) then "missing" else "available" end),
              text: $cm_context
            },
            cass: {
              status: (if ($cass_context | startswith("No CASS context available.")) then "missing" else "available" end),
              text: $cass_context
            }
          },
          commands: {
            start_checks: ["bv --robot-next", "bv --robot-triage", "br ready --json", ("br show " + $bead_id + " --json")],
            agent_mail: [
              "fetch_inbox(project_key=\"" + $repo_root + "\", agent_name=\"" + $agent_name + "\", include_bodies=true)",
              "acknowledge_message(project_key=\"" + $repo_root + "\", agent_name=\"" + $agent_name + "\", message_id=<id>)",
              "file_reservation_paths(project_key=\"" + $repo_root + "\", agent_name=\"" + $agent_name + "\", paths=[<exact files>], exclusive=true, reason=\"" + $bead_id + "\")",
              "send_message(project_key=\"" + $repo_root + "\", sender_name=\"" + $agent_name + "\", to=[<recipient>], thread_id=\"" + $bead_id + "\", subject=\"[" + $bead_id + "] Start: " + $bead_title + "\", body_md=<short plan>)"
            ],
            gates: ["rch exec -- cargo test", "rch exec -- cargo clippy", "ubs $(git diff --name-only --cached)"],
            closeout: ["br close " + $bead_id + " --reason \"Completed\"", "br sync --flush-only", "git push origin main", "git push origin main:master"]
          },
          drift_checks: [
            "Re-read AGENTS.md and README.md sections that affect the touched files",
            "Re-run br show " + $bead_id + " --json before closing",
            "Check git status before staging so peer work is not included",
            "Treat CM and CASS context as stale unless current files confirm it"
          ],
          safety: {
            read_only: true,
            launches_agents: false,
            mutates_beads: false,
            sends_agent_mail: false,
            reserves_files: false,
            runs_builds: false,
            edits_generated_files: false
          },
          warnings: $warnings,
          output: {
            format: "markdown",
            max_chars: $max_chars,
            char_count: ($packet_markdown | length),
            truncated: ($output_truncated == "true")
          },
          packet_markdown: $packet_markdown
        }'
}

swarm_packet_main() {
    local parse_status=0
    local report=""
    local jq_bin=""

    set +e
    swarm_packet_parse_args "$@"
    parse_status=$?
    set -e

    if [[ $parse_status -eq 100 ]]; then
        return 0
    elif [[ $parse_status -ne 0 ]]; then
        return "$parse_status"
    fi

    report="$(swarm_packet_build_report)"
    if [[ "$SWARM_PACKET_FORMAT" == "json" ]]; then
        printf '%s\n' "$report"
        return 0
    fi

    jq_bin="$(swarm_packet_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        echo "Error: jq is required for Markdown packet extraction" >&2
        return 2
    fi
    "$jq_bin" -r '.packet_markdown' <<<"$report"
}

swarm_packet_main "$@"
