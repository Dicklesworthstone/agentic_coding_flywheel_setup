#!/usr/bin/env bash
# ============================================================
# ACFS Policy Lint - read-only guidance/template policy checks
#
# Detects drift in AGENTS.md, templates, onboarding lessons, and docs that
# teach future agents unsafe or repo-inconsistent behavior.
# ============================================================

set -euo pipefail

POLICY_LINT_JSON=false
POLICY_LINT_ROOT=""
POLICY_LINT_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
POLICY_LINT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_LINT_REPO_ROOT="$(cd "$POLICY_LINT_SCRIPT_DIR/../.." 2>/dev/null && pwd || true)"
POLICY_LINT_FILES=()
POLICY_LINT_SCANNED_FILES=()
POLICY_LINT_VIOLATIONS=()
POLICY_LINT_FILES_SCANNED=0

policy_lint_usage() {
    cat <<'EOF'
Usage: acfs policy-lint [OPTIONS]

Read-only lint for ACFS guidance, templates, and startup context. It reports
policy drift but never edits files.

Options:
  --json          Emit machine-readable JSON
  --human         Emit human-readable output (default)
  --root DIR      Repository/root directory to scan
  --file FILE     Scan one file; repeat to scan several files
  --help, -h      Show this help

Inline allow comments:
  acfs-policy-lint: allow <policy-id>
  acfs-policy-lint: allow
EOF
}

policy_lint_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                POLICY_LINT_JSON=true
                shift
                ;;
            --human|--markdown)
                POLICY_LINT_JSON=false
                shift
                ;;
            --root)
                [[ -n "${2:-}" && "$2" != -* ]] || { echo "Error: --root requires a directory" >&2; return 2; }
                POLICY_LINT_ROOT="$2"
                shift 2
                ;;
            --file)
                [[ -n "${2:-}" && "$2" != -* ]] || { echo "Error: --file requires a path" >&2; return 2; }
                POLICY_LINT_FILES+=("$2")
                shift 2
                ;;
            --help|-h)
                policy_lint_usage
                return 100
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs policy-lint --help' for usage." >&2
                return 2
                ;;
        esac
    done
}

policy_lint_binary_path() {
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

policy_lint_require_jq() {
    if ! policy_lint_binary_path jq >/dev/null 2>&1; then
        echo "Error: jq is required for acfs policy-lint" >&2
        return 2
    fi
}

policy_lint_abs_path() {
    local path="$1"
    local dir=""
    local base=""

    if [[ -d "$path" ]]; then
        (cd "$path" 2>/dev/null && pwd -P) || return 1
        return 0
    fi

    dir="$(dirname "$path")"
    base="$(basename "$path")"
    (cd "$dir" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$base") || return 1
}

policy_lint_root() {
    if [[ -n "$POLICY_LINT_ROOT" ]]; then
        policy_lint_abs_path "$POLICY_LINT_ROOT"
    elif [[ -n "$POLICY_LINT_REPO_ROOT" && -d "$POLICY_LINT_REPO_ROOT" ]]; then
        printf '%s\n' "$POLICY_LINT_REPO_ROOT"
    else
        pwd -P
    fi
}

policy_lint_rel_path() {
    local root="$1"
    local path="$2"
    local abs_path=""

    abs_path="$(policy_lint_abs_path "$path" 2>/dev/null || printf '%s\n' "$path")"
    if [[ "$abs_path" == "$root/"* ]]; then
        printf '%s\n' "${abs_path#"$root/"}"
    else
        printf '%s\n' "$path"
    fi
}

policy_lint_add_file_if_present() {
    local path="$1"
    [[ -f "$path" ]] || return 0
    POLICY_LINT_FILES+=("$path")
}

policy_lint_collect_default_files() {
    local root="$1"
    local dir=""
    local path=""

    policy_lint_add_file_if_present "$root/AGENTS.md"
    policy_lint_add_file_if_present "$root/acfs/AGENTS.md"
    policy_lint_add_file_if_present "$root/README.md"
    policy_lint_add_file_if_present "$root/apps/web/README.md"
    policy_lint_add_file_if_present "$root/tests/README.md"

    for dir in "$root/docs" "$root/acfs/onboard/lessons" "$root/acfs/templates" "$root/scripts/templates"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r path; do
            [[ -f "$path" ]] || continue
            POLICY_LINT_FILES+=("$path")
        done < <(find "$dir" -type f \( -name '*.md' -o -name '*.txt' -o -name '*.service' -o -name '*.timer' \) | LC_ALL=C sort)
    done
}

policy_lint_lower() {
    local text="${1:-}"
    printf '%s\n' "${text,,}"
}

policy_lint_trim() {
    local text="${1:-}"
    text="${text#"${text%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    printf '%s\n' "$text"
}

policy_lint_has_allow_directive() {
    local policy_id="$1"
    local line="$2"
    local lower=""

    lower="$(policy_lint_lower "$line")"
    [[ "$lower" == *"acfs-policy-lint: allow"* ]] || return 1
    [[ "$lower" == *"acfs-policy-lint: allow $policy_id"* || "$lower" == *"acfs-policy-lint: allow"* ]]
}

policy_lint_context_is_negative() {
    local text="$1"
    local lower=""

    lower="$(policy_lint_lower "$text")"
    [[ "$lower" == *"forbidden"* ||
       "$lower" == *"never"* ||
       "$lower" == *"do not"* ||
       "$lower" == *"don't"* ||
       "$lower" == *"not allowed"* ||
       "$lower" == *"avoid"* ||
       "$lower" == *"blocks"* ||
       "$lower" == *"blocked"* ||
       "$lower" == *"reject"* ||
       "$lower" == *"dangerous"* ||
       "$lower" == *"opens tui"* ||
       "$lower" == *"wipe"* ||
       "$lower" == *"deletes"* ||
       "$lower" == *"must not"* ||
       "$lower" == *"must never"* ||
       "$lower" == *"without express permission"* ||
       "$lower" == *"no destructive"* ]]
}

policy_lint_add_violation() {
    local policy_id="$1"
    local severity="$2"
    local file="$3"
    local line_number="$4"
    local message="$5"
    local fix="$6"
    local snippet="$7"
    local object=""

    if [[ ${#snippet} -gt 180 ]]; then
        snippet="${snippet:0:177}..."
    fi

    object="$(jq -n \
        --arg policy_id "$policy_id" \
        --arg severity "$severity" \
        --arg file "$file" \
        --argjson line "$line_number" \
        --arg message "$message" \
        --arg fix "$fix" \
        --arg snippet "$snippet" \
        '{
          policy_id: $policy_id,
          severity: $severity,
          file: $file,
          line: $line,
          message: $message,
          fix: $fix,
          snippet: $snippet
        }')"
    POLICY_LINT_VIOLATIONS+=("$object")
}

policy_lint_check_branch_line() {
    local rel_path="$1"
    local line_number="$2"
    local line="$3"
    local lower=""

    lower="$(policy_lint_lower "$line")"
    [[ "$lower" == *"master"* ]] || return 0
    policy_lint_has_allow_directive "branch.main_not_master" "$line" && return 0

    if [[ "$lower" == *"legacy url compatibility"* ||
          "$lower" == *"main:master"* ||
          "$lower" == *"stay synchronized"* ||
          "$lower" == *"synchronized with main"* ||
          "$lower" == *"never reference"* ||
          "$lower" == *"not master"* ||
          "$lower" == *"only use main"* ||
          "$lower" == *"update it to main"* ]]; then
        return 0
    fi

    if [[ "$lower" =~ default[[:space:]]+branch[^[:alnum:]]+is[[:space:]]+\`?master ||
          "$lower" =~ (base|target|default)[[:space:]]+branch.*master ||
          "$lower" =~ git[[:space:]]+(checkout|switch|pull|merge|rebase)[[:space:]].*master ||
          "$lower" =~ git[[:space:]]+push[[:space:]]+origin[[:space:]]+master([[:space:]]|$) ||
          "$lower" =~ /(tree|blob|raw)/master(/|$) ]]; then
        policy_lint_add_violation \
            "branch.main_not_master" \
            "error" \
            "$rel_path" \
            "$line_number" \
            "Guidance points agents at master instead of main." \
            "Use main for work examples; reserve main:master only for the explicit mirror command." \
            "$line"
    fi
}

policy_lint_check_destructive_line() {
    local rel_path="$1"
    local line_number="$2"
    local line="$3"
    local context="$4"
    local lower=""

    lower="$(policy_lint_lower "$line")"

    [[ "$lower" == *"rm -rf"* ||
       "$lower" == *"git reset --hard"* ||
       "$lower" == *"git clean -fd"* ||
       "$lower" == *"git clean -xdf"* ||
       "$lower" == *"git checkout --"* ]] || return 0
    policy_lint_has_allow_directive "filesystem.no_destructive_cleanup" "$line" && return 0
    [[ "$lower" == *"dcg test"* ]] && return 0

    policy_lint_context_is_negative "$context" && return 0

    policy_lint_add_violation \
        "filesystem.no_destructive_cleanup" \
        "error" \
        "$rel_path" \
        "$line_number" \
        "Guidance includes destructive cleanup or rollback commands without an explicit prohibition context." \
        "Replace with non-destructive inspection/stash guidance or add a narrow policy-lint allow comment for quoted forbidden examples." \
        "$line"
}

policy_lint_check_toolchain_line() {
    local rel_path="$1"
    local line_number="$2"
    local line="$3"
    local context="$4"
    local lower=""

    lower="$(policy_lint_lower "$line")"
    [[ "$lower" == *"npm"* || "$lower" == *"yarn"* || "$lower" == *"pnpm"* ]] || return 0

    if [[ "$lower" =~ (^|[^a-z0-9_-])(npm|yarn|pnpm)[[:space:]]+(install|i|run|test|build|exec|ci|add)($|[^a-z0-9_-]) ||
          "$lower" =~ (^|[^a-z0-9_-])(yarn|pnpm)[[:space:]]*$ ]]; then
        policy_lint_has_allow_directive "toolchain.bun_only" "$line" && return 0
        if [[ "$lower" == *"bun install -g"* ||
              "$lower" == *"never use"* ||
              "$lower" == *"do not use"* ||
              "$lower" == *"don't use"* ||
              "$lower" == *"not use"* ||
              "$lower" == *"instead of"* ||
              "$lower" == *"unresponsive"* ||
              "$lower" == *"process priorities"* ||
              "$lower" == *"alias for bun"* ||
              "$context" == *"never use npm"* ]]; then
            return 0
        fi

        policy_lint_add_violation \
            "toolchain.bun_only" \
            "error" \
            "$rel_path" \
            "$line_number" \
            "Guidance uses npm, yarn, or pnpm for JS/TS workflows." \
            "Use bun commands and keep bun.lock as the only JS lockfile." \
            "$line"
    fi
}

policy_lint_check_bv_line() {
    local rel_path="$1"
    local line_number="$2"
    local line="$3"
    local context="$4"
    local trimmed=""

    [[ "$line" == *"bv"* || "$line" == *"BV"* ]] || return 0
    trimmed="$(policy_lint_trim "$line")"
    trimmed="${trimmed#\$ }"
    trimmed="${trimmed#> }"
    trimmed="${trimmed%\`}"
    trimmed="${trimmed#\`}"
    trimmed="${trimmed%%#*}"
    trimmed="$(policy_lint_trim "$trimmed")"

    [[ "$trimmed" == "bv" ]] || return 0
    policy_lint_has_allow_directive "beads.robot_bv_only" "$line" && return 0
    policy_lint_context_is_negative "$context" && return 0

    policy_lint_add_violation \
        "beads.robot_bv_only" \
        "error" \
        "$rel_path" \
        "$line_number" \
        "Guidance shows bare bv, which opens the interactive TUI." \
        "Use bv --robot-triage, bv --robot-next, or br --json commands in agent-facing examples." \
        "$line"
}

policy_lint_check_cargo_line() {
    local rel_path="$1"
    local line_number="$2"
    local line="$3"
    local context="$4"
    local lower=""

    lower="$(policy_lint_lower "$line")"
    [[ "$lower" == *"cargo"* ]] || return 0
    [[ "$lower" =~ (^|[^a-z0-9_-])cargo[[:space:]]+(build|test|check|clippy)([[:space:]]|$) ]] || return 0
    policy_lint_has_allow_directive "builds.rch_for_cpu_heavy" "$line" && return 0
    [[ "$(policy_lint_trim "$line")" == \#* ]] && return 0
    [[ "$lower" == *"rch exec -- cargo"* ]] && return 0
    [[ "$lower" =~ (^|[^a-z0-9_-])rch[[:space:]]+cargo ]] && return 0
    [[ "$lower" =~ (^|[^a-z0-9_-])rch[[:space:]].*cargo ]] && return 0
    [[ "$lower" == *"cargo fmt"* ]] && return 0

    if [[ "$lower" == *"avoid"* ||
          "$lower" == *"do not"* ||
          "$lower" == *"don't"* ||
          "$lower" == *"not recommend"* ||
          "$lower" == *"did not wait"* ||
          "$lower" == *"no local"* ||
          "$lower" == *"without rch"* ||
          "$lower" == *"worker-side"* ||
          "$context" == *"remote compilation"* ]]; then
        return 0
    fi

    policy_lint_add_violation \
        "builds.rch_for_cpu_heavy" \
        "error" \
        "$rel_path" \
        "$line_number" \
        "Guidance shows a CPU-heavy cargo command without rch." \
        "Use rch exec -- cargo ... for build, test, check, and clippy examples." \
        "$line"
}

policy_lint_file_needs_reservation_guidance() {
    local rel_path="$1"
    local mentions_agent="$2"
    local mentions_before_editing="$3"

    case "$rel_path" in
        AGENTS.md|*/AGENTS.md|*agent*template*|*startup*packet*|*swarm*packet*)
            return 0
            ;;
    esac

    [[ "$mentions_agent" == true && "$mentions_before_editing" == true ]]
}

policy_lint_check_reservation_guidance() {
    local rel_path="$1"
    local mentions_agent_mail="$2"
    local mentions_reservation="$3"
    local mentions_agent="$4"
    local mentions_before_editing="$5"
    local allow_reservation="$6"

    policy_lint_file_needs_reservation_guidance "$rel_path" "$mentions_agent" "$mentions_before_editing" || return 0

    if [[ "$mentions_agent_mail" == true && "$mentions_reservation" == true ]]; then
        return 0
    fi

    [[ "$allow_reservation" == true ]] && return 0

    policy_lint_add_violation \
        "coordination.agent_mail_reservation" \
        "error" \
        "$rel_path" \
        1 \
        "Agent-facing guidance is missing Agent Mail file-reservation instructions." \
        "Tell agents to reserve edit surfaces with Agent Mail before changing files." \
        "file-level policy check"
}

policy_lint_scan_file() {
    local root="$1"
    local path="$2"
    local rel_path=""
    local hit=""
    local line=""
    local prev1=""
    local prev2=""
    local context=""
    local line_number=0
    local index=0
    local -a file_lines=()
    local mentions_agent=false
    local mentions_before_editing=false
    local mentions_agent_mail=false
    local mentions_reservation=false
    local allow_reservation=false

    [[ -r "$path" && -f "$path" ]] || return 0
    rel_path="$(policy_lint_rel_path "$root" "$path")"
    POLICY_LINT_SCANNED_FILES+=("$rel_path")
    POLICY_LINT_FILES_SCANNED=$((POLICY_LINT_FILES_SCANNED + 1))

    mapfile -t file_lines < "$path"

    grep -Eiq 'agent' "$path" && mentions_agent=true
    grep -Eiq 'before editing' "$path" && mentions_before_editing=true
    grep -Eiq 'agent mail' "$path" && mentions_agent_mail=true
    grep -Eiq 'reservation|reserve files|file_reservation_paths' "$path" && mentions_reservation=true
    grep -Eiq 'acfs-policy-lint: allow( coordination\.agent_mail_reservation)?' "$path" && allow_reservation=true

    while IFS= read -r hit; do
        line_number="${hit%%:*}"
        line="${hit#*:}"
        policy_lint_check_branch_line "$rel_path" "$line_number" "$line"
    done < <(grep -nEi 'master|/(tree|blob|raw)/master' "$path" || true)

    while IFS= read -r hit; do
        line_number="${hit%%:*}"
        line="${hit#*:}"
        index=$((line_number - 1))
        prev1=""
        prev2=""
        (( index > 0 )) && prev1="${file_lines[$((index - 1))]}"
        (( index > 1 )) && prev2="${file_lines[$((index - 2))]}"
        context="$prev2"$'\n'"$prev1"$'\n'"$line"
        policy_lint_check_destructive_line "$rel_path" "$line_number" "$line" "$context"
    done < <(grep -nEi 'rm -rf|git reset --hard|git clean -(fd|xdf)|git checkout --' "$path" || true)

    while IFS= read -r hit; do
        line_number="${hit%%:*}"
        line="${hit#*:}"
        index=$((line_number - 1))
        prev1=""
        prev2=""
        (( index > 0 )) && prev1="${file_lines[$((index - 1))]}"
        (( index > 1 )) && prev2="${file_lines[$((index - 2))]}"
        context="$prev2"$'\n'"$prev1"$'\n'"$line"
        policy_lint_check_toolchain_line "$rel_path" "$line_number" "$line" "$context"
    done < <(grep -nEi 'npm|yarn|pnpm' "$path" || true)

    while IFS= read -r hit; do
        line_number="${hit%%:*}"
        line="${hit#*:}"
        index=$((line_number - 1))
        prev1=""
        prev2=""
        (( index > 0 )) && prev1="${file_lines[$((index - 1))]}"
        (( index > 1 )) && prev2="${file_lines[$((index - 2))]}"
        context="$prev2"$'\n'"$prev1"$'\n'"$line"
        policy_lint_check_bv_line "$rel_path" "$line_number" "$line" "$context"
    done < <(grep -nEi '(^|[[:space:]`$>])bv([[:space:]`#]|$)' "$path" || true)

    while IFS= read -r hit; do
        line_number="${hit%%:*}"
        line="${hit#*:}"
        index=$((line_number - 1))
        prev1=""
        prev2=""
        (( index > 0 )) && prev1="${file_lines[$((index - 1))]}"
        (( index > 1 )) && prev2="${file_lines[$((index - 2))]}"
        context="$prev2"$'\n'"$prev1"$'\n'"$line"
        policy_lint_check_cargo_line "$rel_path" "$line_number" "$line" "$context"
    done < <(grep -nEi 'cargo[[:space:]]+(build|test|check|clippy)' "$path" || true)

    policy_lint_check_reservation_guidance \
        "$rel_path" \
        "$mentions_agent_mail" \
        "$mentions_reservation" \
        "$mentions_agent" \
        "$mentions_before_editing" \
        "$allow_reservation"
}

policy_lint_json_array_from_lines() {
    if [[ $# -eq 0 ]]; then
        printf '[]\n'
    else
        printf '%s\n' "$@" | jq -R . | jq -s .
    fi
}

policy_lint_json_array_from_objects() {
    if [[ $# -eq 0 ]]; then
        printf '[]\n'
    else
        printf '%s\n' "$@" | jq -s .
    fi
}

policy_lint_render_json() {
    local status="pass"
    local violations_json="[]"
    local files_json="[]"

    if [[ ${#POLICY_LINT_VIOLATIONS[@]} -gt 0 ]]; then
        status="fail"
        violations_json="$(policy_lint_json_array_from_objects "${POLICY_LINT_VIOLATIONS[@]}")"
    fi
    files_json="$(policy_lint_json_array_from_lines "${POLICY_LINT_SCANNED_FILES[@]}")"

    jq -n \
        --arg generated_at "$POLICY_LINT_GENERATED_AT" \
        --arg status "$status" \
        --argjson files_scanned "$POLICY_LINT_FILES_SCANNED" \
        --argjson violations_count "${#POLICY_LINT_VIOLATIONS[@]}" \
        --argjson scanned_files "$files_json" \
        --argjson violations "$violations_json" \
        '{
          schema_version: 1,
          generated_at: $generated_at,
          status: $status,
          summary: {
            files_scanned: $files_scanned,
            violations: $violations_count
          },
          scanned_files: $scanned_files,
          violations: $violations
        }'
}

policy_lint_render_human() {
    local object=""

    if [[ ${#POLICY_LINT_VIOLATIONS[@]} -eq 0 ]]; then
        printf 'PASS: ACFS policy lint found no violations in %d file(s).\n' "$POLICY_LINT_FILES_SCANNED"
        return 0
    fi

    printf 'FAIL: ACFS policy lint found %d violation(s) in %d file(s).\n' \
        "${#POLICY_LINT_VIOLATIONS[@]}" \
        "$POLICY_LINT_FILES_SCANNED"
    for object in "${POLICY_LINT_VIOLATIONS[@]}"; do
        jq -r '"\(.file):\(.line): \(.policy_id) - \(.message)\n  Fix: \(.fix)"' <<<"$object"
    done
}

policy_lint_main() {
    local parse_status=0
    local root=""
    local path=""

    policy_lint_parse_args "$@" || parse_status=$?
    if [[ $parse_status -eq 100 ]]; then
        return 0
    elif [[ $parse_status -ne 0 ]]; then
        return "$parse_status"
    fi

    policy_lint_require_jq
    root="$(policy_lint_root)"

    if [[ ${#POLICY_LINT_FILES[@]} -eq 0 ]]; then
        policy_lint_collect_default_files "$root"
    fi

    for path in "${POLICY_LINT_FILES[@]}"; do
        policy_lint_scan_file "$root" "$path"
    done

    if [[ "$POLICY_LINT_JSON" == true ]]; then
        policy_lint_render_json
    else
        policy_lint_render_human
    fi

    [[ ${#POLICY_LINT_VIOLATIONS[@]} -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    policy_lint_main "$@"
fi
