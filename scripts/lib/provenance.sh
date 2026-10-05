#!/usr/bin/env bash
# ============================================================
# ACFS Tool Provenance - local installed-tool ledger
#
# Read-only JSON ledger for support bundles and swarm diagnostics.
# No network calls are made; unknown provenance is reported explicitly.
# ============================================================

set -euo pipefail

PROVENANCE_JSON=false
PROVENANCE_GENERATED_AT="$(date -Iseconds 2>/dev/null || date)"
PROVENANCE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVENANCE_REPO_ROOT="$(cd "$PROVENANCE_SCRIPT_DIR/../.." 2>/dev/null && pwd || true)"
PROVENANCE_CHECKSUMS_FILE="${ACFS_PROVENANCE_CHECKSUMS_FILE:-}"
PROVENANCE_TOOLS_FILE="${ACFS_PROVENANCE_TOOLS_FILE:-}"
PROVENANCE_TIMEOUT="${ACFS_PROVENANCE_TIMEOUT:-5}"
PROVENANCE_OBJECTS=()
PROVENANCE_WARNINGS=()

provenance_usage() {
    cat <<'EOF'
Usage: acfs provenance [OPTIONS]

Emit a local installed-tool provenance ledger. The command is read-only,
offline, and redacts user-specific paths.

Options:
  --json       Emit machine-readable JSON
  --help, -h   Show this help

Environment:
  ACFS_PROVENANCE_TOOLS_FILE      Pipe-delimited tool spec override for tests
  ACFS_PROVENANCE_CHECKSUMS_FILE  checksums.yaml path for installer references
  ACFS_PROVENANCE_TIMEOUT         Per-tool version timeout seconds (default: 5)
EOF
}

provenance_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                PROVENANCE_JSON=true
                shift
                ;;
            --help|-h)
                provenance_usage
                exit 0
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs provenance --help' for usage." >&2
                return 2
                ;;
        esac
    done
}

provenance_binary_path() {
    local name="${1:-}"
    local path_value=""
    local base_home=""
    local dir=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..|*/*) return 1 ;;
    esac

    path_value="$(command -v "$name" 2>/dev/null || true)"
    if [[ -n "$path_value" && -x "$path_value" ]]; then
        printf '%s\n' "$path_value"
        return 0
    fi

    # `acfs provenance` and `acfs support-bundle` run helpers with a minimal
    # system PATH, so PATH alone reported every per-user tool missing. Look in
    # the target user's standard ACFS bin dirs, as status.sh does. Never as
    # root: this ledger executes `--version`, and root must not run
    # target-user binaries.
    [[ "${EUID:-0}" -ne 0 ]] || return 1
    base_home="${TARGET_HOME:-${HOME:-}}"
    base_home="${base_home%/}"
    [[ "$base_home" == /* && "$base_home" != "/" ]] || return 1
    for dir in "${ACFS_BIN_DIR:-}" "$base_home/.local/bin" "$base_home/.acfs/bin" \
        "$base_home/.bun/bin" "$base_home/.cargo/bin" "$base_home/go/bin" \
        "$base_home/.atuin/bin" "$base_home/bin"; do
        [[ "$dir" == /* ]] || continue
        if [[ -f "$dir/$name" && -x "$dir/$name" ]]; then
            printf '%s\n' "$dir/$name"
            return 0
        fi
    done
    return 1
}

provenance_find_checksums_file() {
    local candidate=""

    if [[ -n "$PROVENANCE_CHECKSUMS_FILE" && -f "$PROVENANCE_CHECKSUMS_FILE" ]]; then
        printf '%s\n' "$PROVENANCE_CHECKSUMS_FILE"
        return 0
    fi

    for candidate in \
        "${ACFS_HOME:-}/checksums.yaml" \
        "$PROVENANCE_REPO_ROOT/checksums.yaml" \
        "$HOME/.acfs/checksums.yaml"
    do
        [[ -n "$candidate" && -f "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

provenance_default_tools() {
    cat <<'EOF'
br|br|--version|verified_installer|https://github.com/Dicklesworthstone/beads_rust|br|
bv|bv|--version|verified_installer|https://github.com/Dicklesworthstone/beads_viewer|bv|
ntm|ntm|--version|verified_installer|https://github.com/Dicklesworthstone/ntm|ntm|
rch|rch|--version|verified_installer|https://github.com/Dicklesworthstone/remote_compilation_helper|rch|
agent_mail|am|--version|verified_installer|https://github.com/Dicklesworthstone/mcp_agent_mail_rust|mcp_agent_mail|
ubs|ubs|--version|verified_installer|https://github.com/Dicklesworthstone/ultimate_bug_scanner|ubs|
cass|cass|--version|verified_installer|https://github.com/Dicklesworthstone/coding_agent_session_search|cass|
cm|cm|--version|verified_installer|https://github.com/Dicklesworthstone/cass_memory_system|cm|
caam|caam|--version|verified_installer|https://github.com/Dicklesworthstone/coding_agent_account_manager|caam|
dcg|dcg|--version|verified_installer|https://github.com/Dicklesworthstone/destructive_command_guard|dcg|
slb|slb|--version|verified_installer|https://github.com/Dicklesworthstone/simultaneous_launch_button|slb|
ru|ru|--version|verified_installer|https://github.com/Dicklesworthstone/repo_updater|ru|
bun|bun|--version|verified_installer|https://bun.sh/install|bun|
rust|cargo|--version|verified_installer|https://sh.rustup.rs|rust|
go|go|version|apt|Ubuntu golang-go package||
claude|claude|--version|verified_installer|https://claude.ai/install.sh|claude|
codex|codex|--version|bun_global|@openai/codex||
gemini|gemini|--version|bun_global|@google/gemini-cli||
EOF
}

provenance_tool_specs() {
    if [[ -n "$PROVENANCE_TOOLS_FILE" && -f "$PROVENANCE_TOOLS_FILE" ]]; then
        cat "$PROVENANCE_TOOLS_FILE"
    else
        provenance_default_tools
    fi
}

provenance_checksum_field() {
    local checksum_file="$1"
    local checksum_key="$2"
    local field="$3"

    [[ -n "$checksum_file" && -f "$checksum_file" ]] || return 1
    [[ -n "$checksum_key" && -n "$field" ]] || return 1

    awk -v key="$checksum_key" -v field="$field" '
        $0 ~ "^  " key ":" {
            in_key = 1
            next
        }
        in_key && $0 ~ /^  [A-Za-z0-9_.-]+:/ {
            exit
        }
        in_key {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line ~ "^" field ":") {
                sub("^[^:]+:[[:space:]]*", "", line)
                gsub(/^"/, "", line)
                gsub(/"$/, "", line)
                print line
                exit
            }
        }
    ' "$checksum_file"
}

provenance_redact_text() {
    local text="${1:-}"
    local home_candidate=""

    for home_candidate in "${HOME:-}" "${TARGET_HOME:-}" "${ACFS_HOME:-}"; do
        [[ -n "$home_candidate" && "$home_candidate" == /* && "$home_candidate" != "/" ]] || continue
        text="${text//$home_candidate/\$HOME}"
    done

    text="$(printf '%s\n' "$text" | sed -E \
        -e 's/sk-[a-zA-Z0-9_-]{20,}/<REDACTED:api_key>/g' \
        -e 's/gh[pousr]_[a-zA-Z0-9_]{20,}/<REDACTED:github_token>/g' \
        -e 's/Bearer [a-zA-Z0-9._\/-]{10,}/Bearer <REDACTED:bearer>/g' \
        -e 's/(password|PASSWORD|token|TOKEN|secret|SECRET)([=:])[A-Za-z0-9._\/:+-]{8,}/\1\2<REDACTED:generic_secret>/g')"
    printf '%s\n' "$text"
}

provenance_resolve_path() {
    local command_name="$1"
    local command_path=""
    local readlink_bin=""

    command_path="$(provenance_binary_path "$command_name" 2>/dev/null || true)"
    [[ -n "$command_path" ]] || return 1

    readlink_bin="$(provenance_binary_path readlink 2>/dev/null || true)"
    if [[ -n "$readlink_bin" ]]; then
        "$readlink_bin" -f "$command_path" 2>/dev/null || printf '%s\n' "$command_path"
    else
        printf '%s\n' "$command_path"
    fi
}

provenance_hash_file() {
    local path="$1"
    local sha_bin=""

    [[ -f "$path" && -r "$path" ]] || return 1
    sha_bin="$(provenance_binary_path sha256sum 2>/dev/null || true)"
    [[ -n "$sha_bin" ]] || return 1
    "$sha_bin" "$path" 2>/dev/null | awk '{print $1}'
}

provenance_version_output() {
    local path="$1"
    local args_raw="$2"
    local timeout_bin=""
    local output=""
    local exit_status=0
    local -a args=()

    read -r -a args <<<"$args_raw"
    timeout_bin="$(provenance_binary_path timeout 2>/dev/null || true)"

    set +e
    if [[ -n "$timeout_bin" ]]; then
        output="$("$timeout_bin" "$PROVENANCE_TIMEOUT" "$path" "${args[@]}" 2>/dev/null | head -1)"
    else
        output="$("$path" "${args[@]}" 2>/dev/null | head -1)"
    fi
    exit_status=$?
    set -e

    if [[ $exit_status -ne 0 || -z "$output" ]]; then
        printf 'unknown\n'
    else
        provenance_redact_text "$output"
    fi
}

provenance_status_for_tool() {
    local resolved_path="$1"
    local binary_sha="$2"
    local expected_binary_sha="$3"

    if [[ -z "$resolved_path" ]]; then
        printf 'missing\n'
    elif [[ -n "$expected_binary_sha" && -n "$binary_sha" && "$binary_sha" != "$expected_binary_sha" ]]; then
        printf 'mismatched\n'
    elif [[ -n "$expected_binary_sha" && -n "$binary_sha" && "$binary_sha" == "$expected_binary_sha" ]]; then
        printf 'verified\n'
    else
        printf 'unknown_provenance\n'
    fi
}

provenance_collect_tool() {
    local jq_bin="$1"
    local checksum_file="$2"
    local spec_line="$3"
    local name="" command_name="" version_args="" install_method="" expected_source="" checksum_key="" expected_binary_sha=""
    local resolved_path="" redacted_path="" installed_version="missing" binary_sha="" installer_url="" installer_sha=""
    local verification_status="" path_redacted=false

    IFS='|' read -r name command_name version_args install_method expected_source checksum_key expected_binary_sha <<<"$spec_line"
    [[ -n "$name" && -n "$command_name" ]] || return 0
    [[ -n "$version_args" ]] || version_args="--version"
    [[ -n "$install_method" ]] || install_method="unknown"

    resolved_path="$(provenance_resolve_path "$command_name" 2>/dev/null || true)"
    if [[ -n "$resolved_path" ]]; then
        redacted_path="$(provenance_redact_text "$resolved_path")"
        [[ "$redacted_path" != "$resolved_path" ]] && path_redacted=true
        binary_sha="$(provenance_hash_file "$resolved_path" 2>/dev/null || true)"
        installed_version="$(provenance_version_output "$resolved_path" "$version_args")"
    fi

    if [[ -n "$checksum_key" && -n "$checksum_file" ]]; then
        installer_url="$(provenance_checksum_field "$checksum_file" "$checksum_key" "url" 2>/dev/null || true)"
        installer_sha="$(provenance_checksum_field "$checksum_file" "$checksum_key" "sha256" 2>/dev/null || true)"
    fi

    verification_status="$(provenance_status_for_tool "$resolved_path" "$binary_sha" "$expected_binary_sha")"
    "$jq_bin" -n \
        --arg name "$name" \
        --arg command "$command_name" \
        --arg install_method "$install_method" \
        --arg expected_source "$expected_source" \
        --arg checksum_key "$checksum_key" \
        --arg installer_url "$installer_url" \
        --arg installer_sha256 "$installer_sha" \
        --arg resolved_path "$redacted_path" \
        --arg installed_version "$installed_version" \
        --arg binary_sha256 "$binary_sha" \
        --arg expected_binary_sha256 "$expected_binary_sha" \
        --arg verification_status "$verification_status" \
        --arg last_verification_at "$PROVENANCE_GENERATED_AT" \
        --argjson path_redacted "$path_redacted" \
        '{
            name: $name,
            command: $command,
            install_method: $install_method,
            expected_source: $expected_source,
            installer_reference: {
                checksum_key: (if $checksum_key == "" then null else $checksum_key end),
                url: (if $installer_url == "" then null else $installer_url end),
                sha256: (if $installer_sha256 == "" then null else $installer_sha256 end)
            },
            resolved_path: (if $resolved_path == "" then null else $resolved_path end),
            path_redacted: $path_redacted,
            installed_version: $installed_version,
            binary_sha256: (if $binary_sha256 == "" then null else $binary_sha256 end),
            expected_binary_sha256: (if $expected_binary_sha256 == "" then null else $expected_binary_sha256 end),
            last_verification_at: $last_verification_at,
            verification_status: $verification_status
        }'
}

provenance_build_report() {
    local jq_bin="$1"
    local checksum_file=""
    local spec_line=""
    local object=""

    checksum_file="$(provenance_find_checksums_file 2>/dev/null || true)"
    if [[ -z "$checksum_file" ]]; then
        PROVENANCE_WARNINGS+=("checksums.yaml not found; installer references are limited")
    fi

    while IFS= read -r spec_line; do
        [[ -n "$spec_line" ]] || continue
        [[ "$spec_line" != \#* ]] || continue
        object="$(provenance_collect_tool "$jq_bin" "$checksum_file" "$spec_line")"
        [[ -n "$object" ]] && PROVENANCE_OBJECTS+=("$object")
    done < <(provenance_tool_specs)

    local warnings_json="[]"
    if [[ ${#PROVENANCE_WARNINGS[@]} -gt 0 ]]; then
        warnings_json="$(printf '%s\n' "${PROVENANCE_WARNINGS[@]}" | "$jq_bin" -R . | "$jq_bin" -s .)"
    fi

    printf '%s\n' "${PROVENANCE_OBJECTS[@]}" | "$jq_bin" -s \
        --arg generated_at "$PROVENANCE_GENERATED_AT" \
        --argjson warnings "$warnings_json" \
        '{
            schema_version: 1,
            generated_at: $generated_at,
            status: (if any(.[]; .verification_status == "mismatched" or .verification_status == "missing") then "warn" else "pass" end),
            warnings: $warnings,
            summary: {
                total: length,
                present: ([.[] | select(.verification_status != "missing")] | length),
                missing: ([.[] | select(.verification_status == "missing")] | length),
                verified: ([.[] | select(.verification_status == "verified")] | length),
                mismatched: ([.[] | select(.verification_status == "mismatched")] | length),
                unknown_provenance: ([.[] | select(.verification_status == "unknown_provenance")] | length)
            },
            tools: .
        }'
}

provenance_emit_human() {
    local report="$1"
    local jq_bin="$2"

    echo "ACFS Tool Provenance"
    echo "Status: $("${jq_bin}" -r '.status' <<<"$report")"
    "${jq_bin}" -r '.summary | "Tools: \(.total) total, \(.present) present, \(.missing) missing, \(.mismatched) mismatched, \(.unknown_provenance) unknown provenance"' <<<"$report"
    echo ""
    "${jq_bin}" -r '.tools[] | "  \(.verification_status): \(.name) -> \(.resolved_path // "missing") (\(.installed_version))"' <<<"$report"
}

provenance_main() {
    provenance_parse_args "$@"

    local jq_bin=""
    local report=""

    jq_bin="$(provenance_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        echo "Error: jq is required for acfs provenance" >&2
        return 2
    fi

    report="$(provenance_build_report "$jq_bin")"
    if [[ "$PROVENANCE_JSON" == true ]]; then
        printf '%s\n' "$report"
    else
        provenance_emit_human "$report" "$jq_bin"
    fi
}

provenance_main "$@"
