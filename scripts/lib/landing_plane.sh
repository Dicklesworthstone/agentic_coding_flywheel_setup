#!/usr/bin/env bash
# ============================================================
# ACFS Landing Plane - read-only closeout checklist
#
# Builds an auditable end-of-session checklist for Beads, Agent Mail,
# reservations, quality gates, exact-file staging, and handoff.
# ============================================================

set -euo pipefail

LANDING_JSON=false
LANDING_GATES_PASSED="${ACFS_LAND_GATES_PASSED:-false}"
LANDING_MAIL_SENT="${ACFS_LAND_MAIL_SENT:-unknown}"
LANDING_AGENT_NAME="${ACFS_LAND_AGENT_NAME:-${AGENT_NAME:-unknown-agent}}"
LANDING_PROJECT_KEY="${ACFS_LAND_PROJECT_KEY:-$(pwd)}"
LANDING_THREAD_ID="${ACFS_LAND_THREAD_ID:-}"
LANDING_COMMIT_MESSAGE="${ACFS_LAND_COMMIT_MESSAGE:-close out session work}"

LANDING_CHANGED_FILES=()
LANDING_SHELL_FILES=()
LANDING_ZSH_FILES=()
LANDING_WEB_FILES=()
LANDING_RUST_FILES=()
LANDING_BEADS_DB_DIRTY=false
LANDING_BEADS_JSONL_DIRTY=false
LANDING_BEADS_SYNC_STATUS="unknown"
LANDING_BEADS_IN_PROGRESS_IDS=()
LANDING_RESERVATION_PATHS=()
LANDING_NEXT_COMMANDS=()
LANDING_WARNINGS=()

LANDING_GATES_STATUS="pass"
LANDING_BEADS_STATUS="pass"
LANDING_MAIL_STATUS="warn"
LANDING_RESERVATIONS_STATUS="warn"
LANDING_STATUS="pass"
LANDING_RESERVATION_COUNT=0

declare -gA LANDING_CHANGED_SEEN=()
declare -gA LANDING_COMMAND_SEEN=()

landing_usage() {
    cat <<'EOF'
Usage: acfs landing-plane [OPTIONS]

Read-only closeout assistant for agent work sessions.

Options:
  --json              Emit machine-readable JSON
  --gates-passed      Mark quality gates as already completed
  --mail-sent         Mark Agent Mail handoff as already sent
  --agent-name NAME   Agent Mail identity for handoff/reservation guidance
  --project-key PATH  Agent Mail project key (default: current directory)
  --thread-id ID      Beads/Mail thread id for completion handoff
  --commit-message M  Commit message placeholder for the suggested commit
  --help, -h          Show this help

Environment for tests or nonstandard shells:
  ACFS_LAND_GIT_STATUS_FILE       File containing git status --porcelain=v1 output
  ACFS_LAND_IN_PROGRESS_JSON      br list --status in_progress --json payload or file path
  ACFS_LAND_RESERVATIONS_JSON     Active reservation payload or file path
  ACFS_LAND_GATES_PASSED=true     Same as --gates-passed
  ACFS_LAND_MAIL_SENT=true        Same as --mail-sent
EOF
}

landing_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                LANDING_JSON=true
                shift
                ;;
            --gates-passed)
                LANDING_GATES_PASSED=true
                shift
                ;;
            --mail-sent)
                LANDING_MAIL_SENT=true
                shift
                ;;
            --agent-name)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --agent-name requires a value" >&2
                    return 2
                fi
                LANDING_AGENT_NAME="$2"
                shift 2
                ;;
            --project-key)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --project-key requires a path" >&2
                    return 2
                fi
                LANDING_PROJECT_KEY="$2"
                shift 2
                ;;
            --thread-id)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --thread-id requires an id" >&2
                    return 2
                fi
                LANDING_THREAD_ID="$2"
                shift 2
                ;;
            --commit-message)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --commit-message requires a message" >&2
                    return 2
                fi
                LANDING_COMMIT_MESSAGE="$2"
                shift 2
                ;;
            --help|-h)
                landing_usage
                exit 0
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs landing-plane --help' for usage." >&2
                return 2
                ;;
        esac
    done
}

landing_binary_path() {
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

landing_bool_true() {
    case "${1:-}" in
        true|TRUE|True|1|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

landing_read_payload() {
    local value="${1:-}"

    if [[ -n "$value" && -f "$value" ]]; then
        cat "$value"
    else
        printf '%s\n' "$value"
    fi
}

landing_add_warning() {
    LANDING_WARNINGS+=("$1")
}

landing_add_command() {
    local command_text="$1"

    [[ -n "$command_text" ]] || return 0
    if [[ -z "${LANDING_COMMAND_SEEN[$command_text]+x}" ]]; then
        LANDING_NEXT_COMMANDS+=("$command_text")
        LANDING_COMMAND_SEEN[$command_text]=1
    fi
}

landing_quote_args() {
    local quoted=""
    local arg=""
    local piece=""

    for arg in "$@"; do
        printf -v piece '%q' "$arg"
        quoted+="${quoted:+ }$piece"
    done
    printf '%s\n' "$quoted"
}

landing_git_status_output() {
    local git_bin=""
    local output=""
    local exit_status=0

    if [[ -n "${ACFS_LAND_GIT_STATUS_FILE:-}" ]]; then
        cat "$ACFS_LAND_GIT_STATUS_FILE"
        return 0
    fi

    git_bin="$(landing_binary_path git 2>/dev/null || true)"
    if [[ -z "$git_bin" ]]; then
        landing_add_warning "git not found; changed-file detection is unavailable"
        return 0
    fi

    set +e
    output="$("$git_bin" status --porcelain=v1 2>/dev/null)"
    exit_status=$?
    set -e
    if [[ $exit_status -ne 0 ]]; then
        landing_add_warning "git status failed; run inside a git worktree for exact-file closeout"
        return 0
    fi

    printf '%s\n' "$output"
}

landing_add_changed_file() {
    local path="$1"

    [[ -n "$path" ]] || return 0
    if [[ -z "${LANDING_CHANGED_SEEN[$path]+x}" ]]; then
        LANDING_CHANGED_FILES+=("$path")
        LANDING_CHANGED_SEEN[$path]=1
    fi
}

landing_classify_changed_file() {
    local path="$1"

    case "$path" in
        .beads/beads.db) LANDING_BEADS_DB_DIRTY=true ;;
        .beads/issues.jsonl) LANDING_BEADS_JSONL_DIRTY=true ;;
    esac

    case "$path" in
        install.sh|*.sh|scripts/acfs-*)
            LANDING_SHELL_FILES+=("$path")
            ;;
    esac

    case "$path" in
        *.zsh|*.zshrc|acfs/zsh/*)
            LANDING_ZSH_FILES+=("$path")
            ;;
    esac

    case "$path" in
        apps/web/*)
            case "$path" in
                *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.md|*.mdx|apps/web/bun.lock)
                    LANDING_WEB_FILES+=("$path")
                    ;;
            esac
            ;;
    esac

    case "$path" in
        *.rs|Cargo.toml|Cargo.lock|*/Cargo.toml|*/Cargo.lock)
            LANDING_RUST_FILES+=("$path")
            ;;
    esac
}

landing_collect_changed_files() {
    local status_output=""
    local line=""
    local path=""

    status_output="$(landing_git_status_output)"
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        path="${line:3}"
        if [[ "$path" == *" -> "* ]]; then
            path="${path##* -> }"
        fi
        landing_add_changed_file "$path"
        landing_classify_changed_file "$path"
    done <<<"$status_output"

    if [[ "$LANDING_BEADS_DB_DIRTY" == true && "$LANDING_BEADS_JSONL_DIRTY" != true ]]; then
        LANDING_BEADS_SYNC_STATUS="needs_sync"
    elif [[ "$LANDING_BEADS_JSONL_DIRTY" == true ]]; then
        LANDING_BEADS_SYNC_STATUS="export_changed"
    else
        LANDING_BEADS_SYNC_STATUS="clean"
    fi
}

landing_collect_beads() {
    local jq_bin="$1"
    local br_bin=""
    local payload=""
    local id=""

    if [[ -n "${ACFS_LAND_IN_PROGRESS_JSON:-}" ]]; then
        payload="$(landing_read_payload "$ACFS_LAND_IN_PROGRESS_JSON")"
    else
        br_bin="$(landing_binary_path br 2>/dev/null || true)"
        if [[ -n "$br_bin" ]]; then
            payload="$("$br_bin" list --status in_progress --json 2>/dev/null || true)"
        else
            landing_add_warning "br not found; Beads in-progress detection is unavailable"
        fi
    fi

    if [[ -n "$payload" ]] && printf '%s' "$payload" | "$jq_bin" . >/dev/null 2>&1; then
        while IFS= read -r id; do
            [[ -n "$id" ]] || continue
            LANDING_BEADS_IN_PROGRESS_IDS+=("$id")
        done < <(printf '%s' "$payload" | "$jq_bin" -r '
            (if type == "array" then .
             else (.issues // .result // [])
             end)
            | .[]
            | .id? // empty
        ')
    elif [[ -n "$payload" ]]; then
        landing_add_warning "Beads in-progress payload was not valid JSON"
    fi

    if [[ -z "$LANDING_THREAD_ID" && ${#LANDING_BEADS_IN_PROGRESS_IDS[@]} -eq 1 ]]; then
        LANDING_THREAD_ID="${LANDING_BEADS_IN_PROGRESS_IDS[0]}"
    fi
}

landing_collect_reservations() {
    local jq_bin="$1"
    local am_bin=""
    local payload=""
    local path=""
    local exit_status=0

    if [[ -n "${ACFS_LAND_RESERVATIONS_JSON:-}" ]]; then
        payload="$(landing_read_payload "$ACFS_LAND_RESERVATIONS_JSON")"
    else
        am_bin="$(landing_binary_path am 2>/dev/null || true)"
        if [[ -n "$am_bin" && "$LANDING_AGENT_NAME" != "unknown-agent" ]]; then
            set +e
            payload="$("$am_bin" robot reservations --format json --project "$LANDING_PROJECT_KEY" --agent "$LANDING_AGENT_NAME" 2>/dev/null)"
            exit_status=$?
            set -e
            if [[ $exit_status -ne 0 ]]; then
                payload=""
            fi
        fi
    fi

    if [[ -z "$payload" ]]; then
        LANDING_RESERVATIONS_STATUS="warn"
        landing_add_warning "active reservation detection needs Agent Mail access or a reservation snapshot; release your own reservations before handoff"
        return 0
    fi

    if ! printf '%s' "$payload" | "$jq_bin" . >/dev/null 2>&1; then
        LANDING_RESERVATIONS_STATUS="warn"
        landing_add_warning "reservation payload was not valid JSON"
        return 0
    fi

    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        LANDING_RESERVATION_PATHS+=("$path")
    done < <(printf '%s' "$payload" | "$jq_bin" -r '
        def rows:
          if type == "array" then .
          elif (.my_reservations? | type) == "array" then .my_reservations
          elif (.active? | type) == "array" then .active
          elif (.reservations? | type) == "array" then .reservations
          elif (.all_active? | type) == "array" then .all_active
          elif (.granted? | type) == "array" then .granted
          else [] end;
        rows
        | map(select((.released_ts? // null) == null))
        | .[]
        | (.path_pattern // .path // .file // .id // "unknown")
    ')

    LANDING_RESERVATION_COUNT="${#LANDING_RESERVATION_PATHS[@]}"
    if [[ "$LANDING_RESERVATION_COUNT" -eq 0 ]]; then
        LANDING_RESERVATIONS_STATUS="pass"
    else
        LANDING_RESERVATIONS_STATUS="warn"
    fi
}

landing_set_statuses_and_commands() {
    local quoted=""
    local id=""

    if [[ ${#LANDING_CHANGED_FILES[@]} -gt 0 ]]; then
        if landing_bool_true "$LANDING_GATES_PASSED"; then
            LANDING_GATES_STATUS="pass"
        else
            LANDING_GATES_STATUS="warn"
            landing_add_warning "quality gates are not marked complete for the changed files"
        fi

        landing_add_command "git diff --check"
        landing_add_command "git diff --cached --check"

        quoted="$(landing_quote_args "${LANDING_CHANGED_FILES[@]}")"
        landing_add_command "ubs $quoted"
        landing_add_command "git add -- $quoted"
    else
        LANDING_GATES_STATUS="pass"
    fi

    if [[ ${#LANDING_SHELL_FILES[@]} -gt 0 ]]; then
        quoted="$(landing_quote_args "${LANDING_SHELL_FILES[@]}")"
        landing_add_command "shellcheck $quoted"
        landing_add_command "shellcheck install.sh scripts/**/*.sh"
    fi

    if [[ ${#LANDING_ZSH_FILES[@]} -gt 0 ]]; then
        quoted="$(landing_quote_args "${LANDING_ZSH_FILES[@]}")"
        landing_add_command "zsh -n $quoted"
    fi

    if [[ ${#LANDING_WEB_FILES[@]} -gt 0 ]]; then
        landing_add_command "cd apps/web && bun run type-check && bun run lint"
        landing_add_command "cd apps/web && bun run build"
    fi

    if [[ ${#LANDING_RUST_FILES[@]} -gt 0 ]]; then
        landing_add_command "rch exec -- cargo test"
    fi

    if [[ "$LANDING_BEADS_SYNC_STATUS" == "needs_sync" ]]; then
        LANDING_BEADS_STATUS="warn"
        landing_add_warning "Beads database changed but .beads/issues.jsonl is not exported"
    elif [[ "$LANDING_BEADS_SYNC_STATUS" == "unknown" ]]; then
        LANDING_BEADS_STATUS="warn"
    fi

    if [[ ${#LANDING_BEADS_IN_PROGRESS_IDS[@]} -gt 0 ]]; then
        LANDING_BEADS_STATUS="warn"
        for id in "${LANDING_BEADS_IN_PROGRESS_IDS[@]}"; do
            landing_add_command "br close $id --reason \"Completed\""
        done
    fi

    if [[ ${#LANDING_BEADS_IN_PROGRESS_IDS[@]} -gt 0 || "$LANDING_BEADS_SYNC_STATUS" != "clean" ]]; then
        landing_add_command "br sync --flush-only"
    fi

    if landing_bool_true "$LANDING_MAIL_SENT"; then
        LANDING_MAIL_STATUS="pass"
    else
        LANDING_MAIL_STATUS="warn"
        landing_add_warning "Agent Mail completion handoff is not marked sent"
    fi

    if [[ "$LANDING_MAIL_STATUS" != "pass" ]]; then
        landing_add_command "send_message(project_key=\"$LANDING_PROJECT_KEY\", sender_name=\"$LANDING_AGENT_NAME\", thread_id=\"${LANDING_THREAD_ID:-bd-issue-id}\", subject=\"[${LANDING_THREAD_ID:-bd-issue-id}] Completed: <summary>\", body_md=\"Summary, verification, remaining work\")"
    fi

    if [[ "$LANDING_RESERVATIONS_STATUS" != "pass" ]]; then
        landing_add_command "release_file_reservations(project_key=\"$LANDING_PROJECT_KEY\", agent_name=\"$LANDING_AGENT_NAME\")"
    fi

    if [[ ${#LANDING_CHANGED_FILES[@]} -gt 0 ]]; then
        landing_add_command "AGENT_NAME=$LANDING_AGENT_NAME git commit -m \"$LANDING_COMMIT_MESSAGE\""
        landing_add_command "AGENT_NAME=$LANDING_AGENT_NAME git push origin main"
    fi

    LANDING_STATUS="pass"
    if [[ "$LANDING_GATES_STATUS" != "pass" || "$LANDING_BEADS_STATUS" != "pass" || "$LANDING_MAIL_STATUS" != "pass" || "$LANDING_RESERVATIONS_STATUS" != "pass" ]]; then
        LANDING_STATUS="warn"
    fi
}

landing_json_array() {
    local jq_bin="$1"
    shift

    if [[ $# -eq 0 ]]; then
        printf '[]\n'
        return 0
    fi

    printf '%s\n' "$@" | "$jq_bin" -R . | "$jq_bin" -s .
}

landing_build_report() {
    local jq_bin="$1"
    local changed_json=""
    local shell_json=""
    local zsh_json=""
    local web_json=""
    local rust_json=""
    local in_progress_json=""
    local reservations_json=""
    local commands_json=""
    local warnings_json=""

    changed_json="$(landing_json_array "$jq_bin" "${LANDING_CHANGED_FILES[@]}")"
    shell_json="$(landing_json_array "$jq_bin" "${LANDING_SHELL_FILES[@]}")"
    zsh_json="$(landing_json_array "$jq_bin" "${LANDING_ZSH_FILES[@]}")"
    web_json="$(landing_json_array "$jq_bin" "${LANDING_WEB_FILES[@]}")"
    rust_json="$(landing_json_array "$jq_bin" "${LANDING_RUST_FILES[@]}")"
    in_progress_json="$(landing_json_array "$jq_bin" "${LANDING_BEADS_IN_PROGRESS_IDS[@]}")"
    reservations_json="$(landing_json_array "$jq_bin" "${LANDING_RESERVATION_PATHS[@]}")"
    commands_json="$(landing_json_array "$jq_bin" "${LANDING_NEXT_COMMANDS[@]}")"
    warnings_json="$(landing_json_array "$jq_bin" "${LANDING_WARNINGS[@]}")"

    "$jq_bin" -n \
        --arg status "$LANDING_STATUS" \
        --arg gates_status "$LANDING_GATES_STATUS" \
        --arg beads_status "$LANDING_BEADS_STATUS" \
        --arg beads_sync_status "$LANDING_BEADS_SYNC_STATUS" \
        --arg mail_status "$LANDING_MAIL_STATUS" \
        --arg reservations_status "$LANDING_RESERVATIONS_STATUS" \
        --arg agent_name "$LANDING_AGENT_NAME" \
        --arg project_key "$LANDING_PROJECT_KEY" \
        --arg thread_id "$LANDING_THREAD_ID" \
        --argjson changed_files "$changed_json" \
        --argjson shell_files "$shell_json" \
        --argjson zsh_files "$zsh_json" \
        --argjson web_files "$web_json" \
        --argjson rust_files "$rust_json" \
        --argjson in_progress_ids "$in_progress_json" \
        --argjson reservation_paths "$reservations_json" \
        --argjson next_commands "$commands_json" \
        --argjson warnings "$warnings_json" \
        '{
            schema_version: 1,
            status: $status,
            warnings: $warnings,
            changed_files: $changed_files,
            quality_gates: {
                status: $gates_status,
                shell_files: $shell_files,
                zsh_files: $zsh_files,
                web_files: $web_files,
                rust_files: $rust_files
            },
            beads: {
                status: $beads_status,
                sync_status: $beads_sync_status,
                in_progress_ids: $in_progress_ids
            },
            agent_mail: {
                status: $mail_status,
                agent_name: $agent_name,
                project_key: $project_key,
                thread_id: $thread_id
            },
            reservations: {
                status: $reservations_status,
                active_count: ($reservation_paths | length),
                paths: $reservation_paths
            },
            next_commands: $next_commands
        }'
}

landing_emit_human() {
    local report="$1"
    local jq_bin="$2"

    echo "ACFS Landing Plane"
    echo "Status: $("${jq_bin}" -r '.status' <<<"$report")"
    echo ""

    echo "Changed files:"
    if [[ "$("${jq_bin}" -r '.changed_files | length' <<<"$report")" == "0" ]]; then
        echo "  none"
    else
        "${jq_bin}" -r '.changed_files[] | "  " + .' <<<"$report"
    fi

    echo ""
    echo "Checks:"
    "${jq_bin}" -r '"  quality_gates: " + .quality_gates.status' <<<"$report"
    "${jq_bin}" -r '"  beads:        " + .beads.status + " (sync=" + .beads.sync_status + ")"' <<<"$report"
    "${jq_bin}" -r '"  agent_mail:   " + .agent_mail.status + " (thread=" + (.agent_mail.thread_id // "") + ")"' <<<"$report"
    "${jq_bin}" -r '"  reservations: " + .reservations.status + " (active=" + (.reservations.active_count | tostring) + ")"' <<<"$report"

    if [[ "$("${jq_bin}" -r '.warnings | length' <<<"$report")" != "0" ]]; then
        echo ""
        echo "Warnings:"
        "${jq_bin}" -r '.warnings[] | "  " + .' <<<"$report"
    fi

    if [[ "$("${jq_bin}" -r '.next_commands | length' <<<"$report")" != "0" ]]; then
        echo ""
        echo "Copyable closeout commands:"
        "${jq_bin}" -r '.next_commands[] | "  " + .' <<<"$report"
    fi

    echo ""
    echo "Handoff summary template:"
    echo "  Summary: <what changed>"
    echo "  Verification: <commands and results>"
    echo "  Remaining work: <none, or exact follow-up issue ids>"
}

landing_main() {
    landing_parse_args "$@"

    local jq_bin=""
    local report=""

    jq_bin="$(landing_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        echo "Error: jq is required for acfs landing-plane" >&2
        return 2
    fi

    landing_collect_changed_files
    landing_collect_beads "$jq_bin"
    landing_collect_reservations "$jq_bin"
    landing_set_statuses_and_commands
    report="$(landing_build_report "$jq_bin")"

    if [[ "$LANDING_JSON" == true ]]; then
        printf '%s\n' "$report"
    else
        landing_emit_human "$report" "$jq_bin"
    fi
}

landing_main "$@"
