#!/usr/bin/env bash
# release-doctor.sh - local pre-release readiness gate for ACFS maintainers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${ACFS_RELEASE_DOCTOR_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

FULL_MODE=false
JSON_MODE=false
QUIET=false
NETWORK_MODE="skip"
WEB_MODE="auto"

CHECK_IDS=()
CHECK_LABELS=()
CHECK_STATUSES=()
CHECK_DETAILS=()
CHECK_COMMANDS=()
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0

usage() {
    cat <<'EOF'
Usage: scripts/release-doctor.sh [--json] [--quiet] [--full] [--network=skip|check] [--web=auto|always|never]

Runs the ACFS maintainer release readiness gate:
  - branch policy and clean worktree check
  - ShellCheck over installer scripts
  - manifest/generated/checksum drift contract
  - optional verified-installer checksum candidate check
  - web type-check, lint, and production build when needed

Defaults keep network and web-heavy checks explicit:
  --network=skip  Skip upstream checksum candidate fetching.
  --web=auto      Run web checks only with --full or changed apps/web files.
EOF
}

json_escape() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

join_messages() {
    local IFS='; '
    printf '%s' "$*"
}

summarize_output() {
    local output="${1:-}"
    if [[ -z "$output" ]]; then
        printf 'command returned no output'
        return 0
    fi
    printf '%s\n' "$output" | sed -n '1,4p' | paste -sd ' ' -
}

record_check() {
    local id="$1"
    local label="$2"
    local status="$3"
    local detail="$4"
    local command="${5:-}"

    case "$status" in
        pass) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        fail) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        warn) WARN_COUNT=$((WARN_COUNT + 1)) ;;
        skip) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
        *)
            echo "release-doctor internal error: invalid status '$status' for $id" >&2
            exit 2
            ;;
    esac

    CHECK_IDS+=("$id")
    CHECK_LABELS+=("$label")
    CHECK_STATUSES+=("$status")
    CHECK_DETAILS+=("$detail")
    CHECK_COMMANDS+=("$command")
}

fake_status_var_name() {
    local id="$1"
    id="${id^^}"
    id="${id//-/_}"
    id="${id//./_}"
    printf 'ACFS_RELEASE_DOCTOR_FAKE_%s_STATUS' "$id"
}

fake_detail_var_name() {
    local id="$1"
    id="${id^^}"
    id="${id//-/_}"
    id="${id//./_}"
    printf 'ACFS_RELEASE_DOCTOR_FAKE_%s_DETAIL' "$id"
}

record_fake_check_if_requested() {
    local id="$1"
    local label="$2"
    local command="$3"
    local status_var detail_var status detail

    status_var="$(fake_status_var_name "$id")"
    status="${!status_var-}"
    [[ -n "$status" ]] || return 1

    detail_var="$(fake_detail_var_name "$id")"
    detail="${!detail_var:-fake $status result for $id}"
    record_check "$id" "$label" "$status" "$detail" "$command"
    return 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                JSON_MODE=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --full)
                FULL_MODE=true
                shift
                ;;
            --network=skip|--network=check)
                NETWORK_MODE="${1#--network=}"
                shift
                ;;
            --web=auto|--web=always|--web=never)
                WEB_MODE="${1#--web=}"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                usage >&2
                exit 2
                ;;
        esac
    done
}

git_value_or_override() {
    local override_name="$1"
    shift
    if [[ -v "$override_name" ]]; then
        printf '%s\n' "${!override_name}"
        return 0
    fi
    (cd "$REPO_ROOT" && "$@")
}

check_branch_policy() {
    local command="git rev-parse --abbrev-ref HEAD && git status --porcelain"
    if record_fake_check_if_requested "branch_policy" "Branch policy" "$command"; then
        return 0
    fi

    local branch status_output main_ref master_ref
    local failures=()
    local warnings=()

    branch="$(git_value_or_override ACFS_RELEASE_DOCTOR_GIT_BRANCH git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    status_output="$(git_value_or_override ACFS_RELEASE_DOCTOR_GIT_STATUS git status --porcelain 2>/dev/null || true)"
    main_ref="$(git_value_or_override ACFS_RELEASE_DOCTOR_ORIGIN_MAIN git rev-parse origin/main 2>/dev/null || true)"
    master_ref="$(git_value_or_override ACFS_RELEASE_DOCTOR_ORIGIN_MASTER git rev-parse origin/master 2>/dev/null || true)"

    if [[ "$branch" != "main" ]]; then
        failures+=("current branch is '$branch', expected main")
    fi
    if [[ -n "$status_output" ]]; then
        failures+=("worktree has uncommitted changes")
    fi
    if [[ -n "$main_ref" && -n "$master_ref" && "$main_ref" != "$master_ref" ]]; then
        warnings+=("origin/master differs from origin/main; mirror with: git push origin main:master")
    elif [[ -n "$main_ref" && -z "$master_ref" ]]; then
        warnings+=("origin/master was not found locally; verify the legacy mirror after push")
    fi

    if [[ ${#failures[@]} -gt 0 ]]; then
        record_check "branch_policy" "Branch policy" "fail" "$(join_messages "${failures[@]}")" "$command"
    elif [[ ${#warnings[@]} -gt 0 ]]; then
        record_check "branch_policy" "Branch policy" "warn" "$(join_messages "${warnings[@]}")" "$command"
    else
        record_check "branch_policy" "Branch policy" "pass" "on main, worktree clean, local branch refs aligned" "$command"
    fi
}

check_shellcheck() {
    local command="shellcheck install.sh scripts/**/*.sh"
    if record_fake_check_if_requested "shellcheck" "ShellCheck" "$command"; then
        return 0
    fi

    if ! command -v shellcheck >/dev/null 2>&1; then
        record_check "shellcheck" "ShellCheck" "fail" "shellcheck is not installed" "$command"
        return 0
    fi

    local shell_files=()
    local output status
    shopt -s globstar nullglob
    shell_files=("$REPO_ROOT/install.sh" "$REPO_ROOT"/scripts/**/*.sh)
    shopt -u globstar nullglob

    if [[ ${#shell_files[@]} -eq 0 ]]; then
        record_check "shellcheck" "ShellCheck" "fail" "no shell files found to lint" "$command"
        return 0
    fi

    set +e
    output="$(shellcheck "${shell_files[@]}" 2>&1)"
    status=$?
    set -e

    if [[ "$status" -eq 0 ]]; then
        record_check "shellcheck" "ShellCheck" "pass" "linted ${#shell_files[@]} installer scripts" "$command"
    else
        record_check "shellcheck" "ShellCheck" "fail" "$(summarize_output "$output")" "$command"
    fi
}

check_manifest_drift() {
    local command="scripts/check-manifest-drift.sh --json --quiet"
    if record_fake_check_if_requested "manifest_drift" "Manifest and generated drift" "$command"; then
        return 0
    fi

    local output status
    set +e
    output="$(cd "$REPO_ROOT" && bash scripts/check-manifest-drift.sh --json --quiet 2>&1)"
    status=$?
    set -e

    case "$status" in
        0)
            record_check "manifest_drift" "Manifest and generated drift" "pass" "manifest, generated artifacts, checksums, and semantic contract are clean" "$command"
            ;;
        1)
            record_check "manifest_drift" "Manifest and generated drift" "fail" "drift detected; run scripts/check-manifest-drift.sh --json for details" "$command"
            ;;
        *)
            record_check "manifest_drift" "Manifest and generated drift" "fail" "$(summarize_output "$output")" "$command"
            ;;
    esac
}

check_checksum_candidate() {
    local command="scripts/lib/security.sh --update-checksums"

    if [[ "$NETWORK_MODE" == "skip" ]]; then
        record_check "checksum_candidate" "Verified-installer checksum candidate" "skip" "network check skipped; run with --network=check before release if verified installers changed" "$command"
        return 0
    fi

    if record_fake_check_if_requested "checksum_candidate" "Verified-installer checksum candidate" "$command"; then
        return 0
    fi

    local candidate status current_body candidate_body
    set +e
    candidate="$(cd "$REPO_ROOT" && bash scripts/lib/security.sh --update-checksums 2>/dev/null)"
    status=$?
    set -e

    if [[ "$status" -ne 0 ]]; then
        record_check "checksum_candidate" "Verified-installer checksum candidate" "warn" "checksum updater failed; run scripts/lib/security.sh --update-checksums for details" "$command"
        return 0
    fi

    if cmp -s "$REPO_ROOT/checksums.yaml" <(printf '%s\n' "$candidate"); then
        record_check "checksum_candidate" "Verified-installer checksum candidate" "pass" "generated candidate matches checksums.yaml" "$command"
        return 0
    fi

    current_body="$(tail -n +2 "$REPO_ROOT/checksums.yaml")"
    candidate_body="$(printf '%s\n' "$candidate" | tail -n +2)"
    if [[ "$current_body" == "$candidate_body" ]]; then
        record_check "checksum_candidate" "Verified-installer checksum candidate" "pass" "only the generated timestamp header differs; leave checksums.yaml unchanged" "$command"
    else
        record_check "checksum_candidate" "Verified-installer checksum candidate" "fail" "checksum candidate differs; review diff before release" "$command"
    fi
}

changed_files() {
    if [[ -v ACFS_RELEASE_DOCTOR_CHANGED_FILES ]]; then
        printf '%s\n' "$ACFS_RELEASE_DOCTOR_CHANGED_FILES"
        return 0
    fi
    (cd "$REPO_ROOT" && git diff --name-only HEAD -- 2>/dev/null || true)
}

should_run_web_checks() {
    case "$WEB_MODE" in
        always) return 0 ;;
        never) return 1 ;;
    esac

    if [[ "$FULL_MODE" == "true" ]]; then
        return 0
    fi

    local changed
    changed="$(changed_files)"
    [[ "$changed" == apps/web/* || "$changed" == *$'\n'apps/web/* ]]
}

check_web() {
    local command="cd apps/web && bun run type-check && bun run lint && bun run build"

    if ! should_run_web_checks; then
        record_check "web_checks" "Website checks" "skip" "no apps/web changes detected; use --full or --web=always to force" "$command"
        return 0
    fi

    if record_fake_check_if_requested "web_checks" "Website checks" "$command"; then
        return 0
    fi

    if ! command -v bun >/dev/null 2>&1; then
        record_check "web_checks" "Website checks" "fail" "bun is not installed" "$command"
        return 0
    fi

    local output status
    set +e
    output="$(cd "$REPO_ROOT/apps/web" && { bun run type-check && bun run lint && bun run build; } 2>&1)"
    status=$?
    set -e

    if [[ "$status" -eq 0 ]]; then
        record_check "web_checks" "Website checks" "pass" "type-check, lint, and build passed" "$command"
    else
        record_check "web_checks" "Website checks" "fail" "$(summarize_output "$output")" "$command"
    fi
}

print_human_report() {
    local i status label detail
    if [[ "$QUIET" == "true" ]]; then
        return 0
    fi

    echo "ACFS release doctor"
    echo
    for i in "${!CHECK_IDS[@]}"; do
        status="${CHECK_STATUSES[$i]}"
        label="${CHECK_LABELS[$i]}"
        detail="${CHECK_DETAILS[$i]}"
        printf '[%s] %s - %s\n' "${status^^}" "$label" "$detail"
    done
    echo
    printf 'Summary: pass=%d warn=%d skip=%d fail=%d\n' "$PASS_COUNT" "$WARN_COUNT" "$SKIP_COUNT" "$FAIL_COUNT"
    if [[ "$FAIL_COUNT" -eq 0 ]]; then
        echo "Release readiness: ready with the warnings/skips shown above."
    else
        echo "Release readiness: blocked until failed checks are fixed."
    fi
}

print_json_report() {
    local ok="true"
    local first="true"
    local i
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        ok="false"
    fi

    printf '{\n'
    printf '  "ok": %s,\n' "$ok"
    printf '  "mode": {"full": %s, "network": "%s", "web": "%s"},\n' "$FULL_MODE" "$(json_escape "$NETWORK_MODE")" "$(json_escape "$WEB_MODE")"
    printf '  "summary": {"pass": %d, "warn": %d, "skip": %d, "fail": %d},\n' "$PASS_COUNT" "$WARN_COUNT" "$SKIP_COUNT" "$FAIL_COUNT"
    printf '  "checks": [\n'
    for i in "${!CHECK_IDS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first="false"
        else
            printf ',\n'
        fi
        printf '    {"id": "%s", "label": "%s", "status": "%s", "detail": "%s", "command": "%s"}' \
            "$(json_escape "${CHECK_IDS[$i]}")" \
            "$(json_escape "${CHECK_LABELS[$i]}")" \
            "$(json_escape "${CHECK_STATUSES[$i]}")" \
            "$(json_escape "${CHECK_DETAILS[$i]}")" \
            "$(json_escape "${CHECK_COMMANDS[$i]}")"
    done
    printf '\n  ]\n'
    printf '}\n'
}

main() {
    parse_args "$@"
    check_branch_policy
    check_shellcheck
    check_manifest_drift
    check_checksum_candidate
    check_web

    if [[ "$JSON_MODE" == "true" ]]; then
        print_json_report
    else
        print_human_report
    fi

    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
