#!/usr/bin/env bash
# ============================================================
# ACFS Credential Preflight - read-only local secret exposure check
#
# Scans bounded ACFS-owned files plus documented shell/env surfaces before
# agent launch or support-bundle sharing. It reports categories and counts,
# never raw secret values or snippets, and never mutates user files.
# ============================================================

set -euo pipefail

CRED_PREFLIGHT_SYSTEM_PATH="/usr/bin:/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/sbin"
PATH="$CRED_PREFLIGHT_SYSTEM_PATH"
export PATH

CRED_PREFLIGHT_JSON=false
CRED_PREFLIGHT_ROOT=""
CRED_PREFLIGHT_HOME="${HOME:-}"
CRED_PREFLIGHT_ACFS_HOME="${ACFS_HOME:-}"
CRED_PREFLIGHT_MAX_BYTES="${ACFS_CREDENTIAL_PREFLIGHT_MAX_BYTES:-1048576}"
CRED_PREFLIGHT_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
CRED_PREFLIGHT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRED_PREFLIGHT_REPO_ROOT="$(cd "$CRED_PREFLIGHT_SCRIPT_DIR/../.." 2>/dev/null && pwd || true)"
CRED_PREFLIGHT_SCAN_FILES=()
CRED_PREFLIGHT_SCAN_SOURCES=()
CRED_PREFLIGHT_EXCLUDES=()
CRED_PREFLIGHT_FINDINGS=()
CRED_PREFLIGHT_SKIPPED=()
CRED_PREFLIGHT_FILES_SCANNED=0
CRED_PREFLIGHT_JQ_BIN=""

credential_preflight_usage() {
    cat <<'EOF'
Usage: acfs credential-preflight [OPTIONS]

Read-only scan for credential exposure in bounded ACFS, shell config, and shell
history surfaces. Output reports categories and counts only; it never prints raw
secret values or snippets.

Options:
  --json              Emit machine-readable JSON
  --human             Emit human-readable output (default)
  --home DIR          Target user home (default: current HOME)
  --acfs-home DIR     ACFS home (default: $ACFS_HOME or HOME/.acfs)
  --root DIR          Repository root used for relative path display
  --file FILE         Scan one file; repeat to scan several files
  --exclude PATH      Skip a file or directory; repeat for multiple paths
  --max-bytes N       Skip files larger than N bytes (default: 1048576)
  --help, -h          Show this help
EOF
}

credential_preflight_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                CRED_PREFLIGHT_JSON=true
                shift
                ;;
            --human|--markdown)
                CRED_PREFLIGHT_JSON=false
                shift
                ;;
            --home)
                [[ -n "${2:-}" && "$2" != -* ]] || { echo "Error: --home requires a directory" >&2; return 2; }
                CRED_PREFLIGHT_HOME="$2"
                shift 2
                ;;
            --acfs-home)
                [[ -n "${2:-}" && "$2" != -* ]] || { echo "Error: --acfs-home requires a directory" >&2; return 2; }
                CRED_PREFLIGHT_ACFS_HOME="$2"
                shift 2
                ;;
            --root)
                [[ -n "${2:-}" && "$2" != -* ]] || { echo "Error: --root requires a directory" >&2; return 2; }
                CRED_PREFLIGHT_ROOT="$2"
                shift 2
                ;;
            --file)
                [[ -n "${2:-}" && "$2" != -* ]] || { echo "Error: --file requires a path" >&2; return 2; }
                CRED_PREFLIGHT_SCAN_FILES+=("$2")
                CRED_PREFLIGHT_SCAN_SOURCES+=("explicit")
                shift 2
                ;;
            --exclude)
                [[ -n "${2:-}" && "$2" != -* ]] || { echo "Error: --exclude requires a path" >&2; return 2; }
                CRED_PREFLIGHT_EXCLUDES+=("$2")
                shift 2
                ;;
            --max-bytes)
                [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]] || { echo "Error: --max-bytes requires an integer" >&2; return 2; }
                CRED_PREFLIGHT_MAX_BYTES="$2"
                shift 2
                ;;
            --help|-h)
                credential_preflight_usage
                return 100
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs credential-preflight --help' for usage." >&2
                return 2
                ;;
        esac
    done
}

credential_preflight_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..|*/*|*[!A-Za-z0-9._+-]*) return 1 ;;
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

credential_preflight_require_jq() {
    CRED_PREFLIGHT_JQ_BIN="$(credential_preflight_binary_path jq 2>/dev/null || true)"
    if [[ -z "$CRED_PREFLIGHT_JQ_BIN" ]]; then
        echo "Error: jq is required for acfs credential-preflight" >&2
        return 2
    fi
}

credential_preflight_jq() {
    local jq_bin="$CRED_PREFLIGHT_JQ_BIN"

    if [[ -z "$jq_bin" || ! -x "$jq_bin" ]]; then
        jq_bin="$(credential_preflight_binary_path jq 2>/dev/null || true)"
        [[ -n "$jq_bin" ]] || return 2
        CRED_PREFLIGHT_JQ_BIN="$jq_bin"
    fi

    "$jq_bin" "$@"
}

credential_preflight_abs_path() {
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

credential_preflight_root() {
    if [[ -n "$CRED_PREFLIGHT_ROOT" ]]; then
        credential_preflight_abs_path "$CRED_PREFLIGHT_ROOT"
    elif [[ -n "$CRED_PREFLIGHT_REPO_ROOT" && -d "$CRED_PREFLIGHT_REPO_ROOT" ]]; then
        printf '%s\n' "$CRED_PREFLIGHT_REPO_ROOT"
    else
        pwd -P
    fi
}

credential_preflight_display_path() {
    local root="$1"
    local path="$2"
    local abs_path=""
    local home_abs=""
    local acfs_abs=""

    abs_path="$(credential_preflight_abs_path "$path" 2>/dev/null || printf '%s\n' "$path")"
    home_abs="$(credential_preflight_abs_path "$CRED_PREFLIGHT_HOME" 2>/dev/null || true)"
    acfs_abs="$(credential_preflight_abs_path "$CRED_PREFLIGHT_ACFS_HOME" 2>/dev/null || true)"

    if [[ "$abs_path" == "$root/"* ]]; then
        printf '%s\n' "${abs_path#"$root/"}"
    elif [[ -n "$acfs_abs" && "$abs_path" == "$acfs_abs/"* ]]; then
        printf '$ACFS_HOME/%s\n' "${abs_path#"$acfs_abs/"}"
    elif [[ -n "$home_abs" && "$abs_path" == "$home_abs/"* ]]; then
        printf '$HOME/%s\n' "${abs_path#"$home_abs/"}"
    else
        basename "$path"
    fi
}

credential_preflight_source_for_path() {
    local path="$1"
    local base=""

    base="$(basename "$path")"
    case "$base" in
        .bash_history|.zsh_history) printf 'shell_history\n' ;;
        .bashrc|.zshrc|.profile|.bash_profile|.zprofile|.zshenv|.env|.env.local) printf 'shell_env\n' ;;
        state.json|onboard_progress.json|acfs.manifest.yaml) printf 'acfs_state\n' ;;
        install-*.log|install_summary_*.json|performance_budget*.json) printf 'acfs_log\n' ;;
        *) printf 'explicit\n' ;;
    esac
}

credential_preflight_add_scan_file() {
    local path="$1"
    local source="${2:-}"
    local existing=""

    [[ -n "$path" ]] || return 0
    [[ -f "$path" || -e "$path" ]] || return 0
    for existing in "${CRED_PREFLIGHT_SCAN_FILES[@]:-}"; do
        [[ "$existing" == "$path" ]] && return 0
    done

    [[ -n "$source" ]] || source="$(credential_preflight_source_for_path "$path")"
    CRED_PREFLIGHT_SCAN_FILES+=("$path")
    CRED_PREFLIGHT_SCAN_SOURCES+=("$source")
}

credential_preflight_collect_default_files() {
    local home_dir="$1"
    local acfs_home="$2"
    local path=""

    for path in \
        "$home_dir/.zshrc" \
        "$home_dir/.zshenv" \
        "$home_dir/.zprofile" \
        "$home_dir/.bashrc" \
        "$home_dir/.bash_profile" \
        "$home_dir/.profile" \
        "$home_dir/.env" \
        "$home_dir/.env.local" \
        "$home_dir/.zsh_history" \
        "$home_dir/.bash_history"
    do
        credential_preflight_add_scan_file "$path"
    done

    if [[ -n "$acfs_home" ]]; then
        for path in \
            "$acfs_home/state.json" \
            "$acfs_home/onboard_progress.json" \
            "$acfs_home/acfs.manifest.yaml"
        do
            credential_preflight_add_scan_file "$path"
        done

        if [[ -d "$acfs_home/logs" ]]; then
            while IFS= read -r path; do
                credential_preflight_add_scan_file "$path" "acfs_log"
            done < <(find "$acfs_home/logs" -maxdepth 1 -type f \( -name 'install-*.log' -o -name 'install_summary_*.json' -o -name 'performance_budget*.json' \) 2>/dev/null | LC_ALL=C sort | head -20)
        fi
    fi
}

credential_preflight_is_excluded() {
    local path="$1"
    local abs_path=""
    local exclude=""
    local abs_exclude=""

    abs_path="$(credential_preflight_abs_path "$path" 2>/dev/null || printf '%s\n' "$path")"
    for exclude in "${CRED_PREFLIGHT_EXCLUDES[@]:-}"; do
        abs_exclude="$(credential_preflight_abs_path "$exclude" 2>/dev/null || printf '%s\n' "$exclude")"
        [[ "$abs_path" == "$abs_exclude" || "$abs_path" == "$abs_exclude/"* ]] && return 0
    done
    return 1
}

credential_preflight_json_array_from_objects() {
    if [[ $# -eq 0 ]]; then
        printf '[]\n'
    else
        printf '%s\n' "$@" | credential_preflight_jq -s .
    fi
}

credential_preflight_add_skipped() {
    local root="$1"
    local path="$2"
    local source="$3"
    local reason="$4"
    local object=""

    object="$(credential_preflight_jq -n \
        --arg file "$(credential_preflight_display_path "$root" "$path")" \
        --arg source "$source" \
        --arg reason "$reason" \
        '{file: $file, source: $source, reason: $reason}')"
    CRED_PREFLIGHT_SKIPPED+=("$object")
}

credential_preflight_remediation() {
    local category="$1"

    case "$category" in
        private_key) printf 'Move private keys out of shareable logs/configs and rotate the key if it was exposed.\n' ;;
        credential_url) printf 'Move credentials into a secret manager or local env file excluded from sharing.\n' ;;
        aws_key|github_token|github_pat|vault_token|slack_token|bearer_token|jwt|api_key) printf 'Rotate the token and move it to the intended provider secret store or shell profile outside shared artifacts.\n' ;;
        password|generic_secret) printf 'Replace the literal value with a secret reference and rotate it if it has been shared.\n' ;;
        *) printf 'Remove the sensitive value from shareable files and rotate if exposed.\n' ;;
    esac
}

credential_preflight_add_finding() {
    local root="$1"
    local path="$2"
    local source="$3"
    local line_number="$4"
    local category="$5"
    local evidence="$6"
    local object=""

    object="$(credential_preflight_jq -n \
        --arg category "$category" \
        --arg severity "warning" \
        --arg file "$(credential_preflight_display_path "$root" "$path")" \
        --arg source "$source" \
        --argjson line "$line_number" \
        --arg evidence "$evidence" \
        --arg remediation "$(credential_preflight_remediation "$category")" \
        '{
          category: $category,
          severity: $severity,
          file: $file,
          source: $source,
          line: $line,
          evidence: $evidence,
          remediation: $remediation
        }')"
    CRED_PREFLIGHT_FINDINGS+=("$object")
}

credential_preflight_value_is_placeholder() {
    local value="${1:-}"
    local lower=""

    lower="${value,,}"
    [[ -z "$lower" ]] && return 0
    [[ "$lower" =~ ^[0-9]+$ ]] && return 0
    [[ "$lower" == *"<redacted"* ||
       "$lower" == *"redacted"* ||
       "$lower" == *"example"* ||
       "$lower" == *"placeholder"* ||
       "$lower" == *"changeme"* ||
       "$lower" == *"change-me"* ||
       "$lower" == *"replace-me"* ||
       "$lower" == *"your-token"* ||
       "$lower" == *"your_token"* ||
       "$lower" == *"your-api-key"* ||
       "$lower" == *"your_api_key"* ||
       "$lower" == *"dummy"* ||
       "$lower" == *"notasecret"* ||
       "$lower" == *"test-token"* ||
       "$lower" == *"test_token"* ]]
}

credential_preflight_key_is_secret_like() {
    local key="${1:-}"
    local lower=""

    lower="${key,,}"
    case "$lower" in
        *api_key*|*api-key*|\
        *api_secret*|*api-secret*|\
        *secret_key*|*secret-key*|\
        *access_key*|*access-key*|\
        *access_token*|*access-token*|\
        *refresh_token*|*refresh-token*|\
        *auth_token*|*auth-token*|\
        *client_secret*|*client-secret*|\
        *private_key*|*private-key*|\
        *password*|*passwd*|*secret*|*token*)
            return 0
            ;;
    esac

    return 1
}

credential_preflight_value_has_specific_pattern() {
    local value="${1:-}"
    local lower=""

    lower="${value,,}"
    [[ "$lower" =~ sk-[a-z0-9_-]{20,} ]] && return 0
    [[ "$lower" =~ akia[a-z0-9]{16} ]] && return 0
    [[ "$lower" =~ gh[pousr]_[a-z0-9_]{20,} ]] && return 0
    [[ "$lower" =~ github_pat_[a-z0-9_]{22,} ]] && return 0
    [[ "$lower" =~ hvs\.[a-z0-9]{20,} ]] && return 0
    [[ "$lower" =~ xox[bpsar]-[a-z0-9-]{10,} ]] && return 0
    [[ "$lower" =~ eyj[a-z0-9_-]{10,}\.[a-z0-9_-]{10,}\.[a-z0-9_-]{10,} ]] && return 0
    [[ "$lower" =~ [a-z][a-z0-9+.-]*://[^/@[:space:]]+:[^/@[:space:]]+@ ]] && return 0

    return 1
}

credential_preflight_scan_line() {
    local root="$1"
    local path="$2"
    local source="$3"
    local line_number="$4"
    local line="$5"
    local lower=""
    local rest=""
    local match=""
    local key=""
    local value=""

    lower="${line,,}"

    if [[ "$line" =~ -----BEGIN[[:space:]][^-]*PRIVATE[[:space:]]KEY[^-]*----- ]]; then
        credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "private_key" "private key block marker"
    fi
    if [[ "$line" =~ sk-[A-Za-z0-9_-]{20,} ]]; then
        credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "api_key" "sk-style API key pattern"
    fi
    if [[ "$line" =~ AKIA[A-Z0-9]{16} ]]; then
        credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "aws_key" "AWS access key pattern"
    fi
    if [[ "$line" =~ gh[pousr]_[A-Za-z0-9_]{20,} ]]; then
        credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "github_token" "GitHub token pattern"
    fi
    if [[ "$line" =~ github_pat_[A-Za-z0-9_]{22,} ]]; then
        credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "github_pat" "GitHub fine-grained PAT pattern"
    fi
    if [[ "$line" =~ hvs\.[A-Za-z0-9]{20,} ]]; then
        credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "vault_token" "Vault token pattern"
    fi
    if [[ "$line" =~ xox[bpsar]-[A-Za-z0-9-]{10,} ]]; then
        credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "slack_token" "Slack token pattern"
    fi
    if [[ "$line" =~ Bearer[[:space:]][A-Za-z0-9._/-]{20,} ]]; then
        credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "bearer_token" "Bearer token pattern"
    fi
    if [[ "$line" =~ eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,} ]]; then
        credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "jwt" "JWT pattern"
    fi
    if [[ "$line" =~ [A-Za-z][A-Za-z0-9+.-]*://[^/@[:space:]]+:[^/@[:space:]]+@ ]]; then
        credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "credential_url" "URL with embedded credentials"
    fi

    rest="$lower"
    while [[ "$rest" =~ \"([a-z][a-z0-9_-]*)\"[[:space:]]*:[[:space:]]*\"([^\"]{4,})\" ]]; do
        match="${BASH_REMATCH[0]}"
        key="${BASH_REMATCH[1]:-}"
        value="${BASH_REMATCH[2]:-}"
        if credential_preflight_key_is_secret_like "$key" &&
            ! credential_preflight_value_is_placeholder "$value" &&
            ! credential_preflight_value_has_specific_pattern "$value"; then
            if [[ "$key" == *"password"* || "$key" == *"passwd"* ]]; then
                credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "password" "secret-like JSON key"
            else
                credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "generic_secret" "secret-like JSON key"
            fi
        fi
        rest="${rest#*"$match"}"
    done

    rest="$lower"
    while [[ "$rest" =~ (^|[^a-z0-9_-])([a-z][a-z0-9_-]*)[[:space:]]*[:=][[:space:]]*[\"\']?([^\"\'\<\>\ 	]{4,}) ]]; do
        match="${BASH_REMATCH[0]}"
        key="${BASH_REMATCH[2]:-}"
        value="${BASH_REMATCH[3]:-}"
        if credential_preflight_key_is_secret_like "$key" &&
            ! credential_preflight_value_is_placeholder "$value" &&
            ! credential_preflight_value_has_specific_pattern "$value"; then
            case "$key" in
                *password*|*passwd*) credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "password" "secret-like assignment key" ;;
                *) credential_preflight_add_finding "$root" "$path" "$source" "$line_number" "generic_secret" "secret-like assignment key" ;;
            esac
        fi
        rest="${rest#*"$match"}"
    done
}

credential_preflight_file_is_binary() {
    local path="$1"
    head -c 1024 "$path" 2>/dev/null | od -An -tx1 2>/dev/null | grep -q ' 00'
}

credential_preflight_scan_file() {
    local root="$1"
    local path="$2"
    local source="$3"
    local size_bytes=0
    local line=""
    local line_number=0

    if credential_preflight_is_excluded "$path"; then
        credential_preflight_add_skipped "$root" "$path" "$source" "excluded_by_option"
        return 0
    fi
    if [[ ! -f "$path" ]]; then
        credential_preflight_add_skipped "$root" "$path" "$source" "not_regular_file"
        return 0
    fi
    if [[ ! -r "$path" ]]; then
        credential_preflight_add_skipped "$root" "$path" "$source" "unreadable"
        return 0
    fi

    size_bytes="$(wc -c < "$path" 2>/dev/null | tr -d '[:space:]' || printf '0')"
    if [[ "$size_bytes" =~ ^[0-9]+$ ]] && (( size_bytes > CRED_PREFLIGHT_MAX_BYTES )); then
        credential_preflight_add_skipped "$root" "$path" "$source" "too_large"
        return 0
    fi
    if credential_preflight_file_is_binary "$path"; then
        credential_preflight_add_skipped "$root" "$path" "$source" "binary"
        return 0
    fi

    CRED_PREFLIGHT_FILES_SCANNED=$((CRED_PREFLIGHT_FILES_SCANNED + 1))
    # shellcheck disable=SC2094 # Scanner is read-only; helper functions only append in-memory JSON objects.
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        credential_preflight_scan_line "$root" "$path" "$source" "$line_number" "$line"
    done < "$path"
}

credential_preflight_render_json() {
    local status="pass"
    local findings_json="[]"
    local skipped_json="[]"
    local categories_json="[]"

    findings_json="$(credential_preflight_json_array_from_objects "${CRED_PREFLIGHT_FINDINGS[@]}")"
    skipped_json="$(credential_preflight_json_array_from_objects "${CRED_PREFLIGHT_SKIPPED[@]}")"
    categories_json="$(credential_preflight_jq -n --argjson findings "$findings_json" '
      $findings
      | group_by(.category)
      | map({category: .[0].category, count: length})
    ')"

    if [[ ${#CRED_PREFLIGHT_FINDINGS[@]} -gt 0 ]]; then
        status="warn"
    fi

    credential_preflight_jq -n \
        --arg generated_at "$CRED_PREFLIGHT_GENERATED_AT" \
        --arg status "$status" \
        --argjson files_scanned "$CRED_PREFLIGHT_FILES_SCANNED" \
        --argjson findings_count "${#CRED_PREFLIGHT_FINDINGS[@]}" \
        --argjson skipped_count "${#CRED_PREFLIGHT_SKIPPED[@]}" \
        --argjson categories "$categories_json" \
        --argjson findings "$findings_json" \
        --argjson skipped "$skipped_json" \
        '{
          schema_version: 1,
          generated_at: $generated_at,
          status: $status,
          safety: {
            read_only: true,
            raw_secret_values_printed: false,
            raw_snippets_printed: false,
            user_files_mutated: false
          },
          summary: {
            files_scanned: $files_scanned,
            findings: $findings_count,
            skipped: $skipped_count,
            categories: $categories
          },
          findings: $findings,
          skipped_files: $skipped
        }'
}

credential_preflight_render_human() {
    local object=""

    if [[ ${#CRED_PREFLIGHT_FINDINGS[@]} -eq 0 ]]; then
        printf 'PASS: credential preflight found no credential patterns in %d file(s).\n' "$CRED_PREFLIGHT_FILES_SCANNED"
        if [[ ${#CRED_PREFLIGHT_SKIPPED[@]} -gt 0 ]]; then
            printf 'Skipped %d file(s); use --json for reasons.\n' "${#CRED_PREFLIGHT_SKIPPED[@]}"
        fi
        return 0
    fi

    printf 'WARN: credential preflight found %d potential exposure(s) in %d scanned file(s).\n' \
        "${#CRED_PREFLIGHT_FINDINGS[@]}" \
        "$CRED_PREFLIGHT_FILES_SCANNED"
    for object in "${CRED_PREFLIGHT_FINDINGS[@]}"; do
        credential_preflight_jq -r '"\(.file):\(.line): \(.category) - \(.evidence)\n  Remediation: \(.remediation)"' <<<"$object"
    done
    if [[ ${#CRED_PREFLIGHT_SKIPPED[@]} -gt 0 ]]; then
        printf 'Skipped %d file(s); use --json for reasons.\n' "${#CRED_PREFLIGHT_SKIPPED[@]}"
    fi
}

credential_preflight_main() {
    local parse_status=0
    local root=""
    local home_abs=""
    local acfs_abs=""
    local idx=0

    credential_preflight_parse_args "$@" || parse_status=$?
    if [[ $parse_status -eq 100 ]]; then
        return 0
    elif [[ $parse_status -ne 0 ]]; then
        return "$parse_status"
    fi

    credential_preflight_require_jq
    root="$(credential_preflight_root)"
    home_abs="$(credential_preflight_abs_path "$CRED_PREFLIGHT_HOME" 2>/dev/null || true)"
    if [[ -n "$home_abs" ]]; then
        CRED_PREFLIGHT_HOME="$home_abs"
    fi
    if [[ -z "$CRED_PREFLIGHT_ACFS_HOME" && -n "$CRED_PREFLIGHT_HOME" ]]; then
        CRED_PREFLIGHT_ACFS_HOME="$CRED_PREFLIGHT_HOME/.acfs"
    fi
    acfs_abs="$(credential_preflight_abs_path "$CRED_PREFLIGHT_ACFS_HOME" 2>/dev/null || true)"
    if [[ -n "$acfs_abs" ]]; then
        CRED_PREFLIGHT_ACFS_HOME="$acfs_abs"
    fi

    if [[ ${#CRED_PREFLIGHT_SCAN_FILES[@]} -eq 0 ]]; then
        credential_preflight_collect_default_files "$CRED_PREFLIGHT_HOME" "$CRED_PREFLIGHT_ACFS_HOME"
    fi

    for ((idx = 0; idx < ${#CRED_PREFLIGHT_SCAN_FILES[@]}; idx++)); do
        credential_preflight_scan_file "$root" "${CRED_PREFLIGHT_SCAN_FILES[$idx]}" "${CRED_PREFLIGHT_SCAN_SOURCES[$idx]}"
    done

    if [[ "$CRED_PREFLIGHT_JSON" == true ]]; then
        credential_preflight_render_json
    else
        credential_preflight_render_human
    fi

    [[ ${#CRED_PREFLIGHT_FINDINGS[@]} -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    credential_preflight_main "$@"
fi
