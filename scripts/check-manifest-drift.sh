#!/usr/bin/env bash
# check-manifest-drift.sh - Detect and auto-fix ACFS manifest/script/config drift
#
# This script verifies that scripts/generated/manifest_index.sh has the correct
# SHA256 hash for acfs.manifest.yaml, that internal library scripts match
# their recorded checksums in scripts/generated/internal_checksums.sh, that the
# full set of generated artifacts still matches `bun run generate:diff`, that
# manifest-derived website, onboarding, doctor, README, and checksum surfaces
# satisfy the semantic drift contract, and that checked-in MCP Agent Mail
# client configs still point at the canonical HTTP URL. If drift is detected,
# it can regenerate all generated scripts, commit, and push.
#
# Usage:
#   ./scripts/check-manifest-drift.sh [--fix] [--json] [--quiet]
#
# Options:
#   --fix    Auto-regenerate, commit, and push if drift detected (default: check only)
#   --json   Output results as JSON
#   --quiet  Suppress non-error output
#
# Exit codes:
#   0  No drift (or drift was auto-fixed with --fix)
#   1  Drift detected (check-only mode)
#   2  Auto-fix failed
#   3  Missing prerequisites

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Repo MCP configs are committed artifacts, so the expected URL must be
# deterministic and cannot depend on whichever Agent Mail CLI is installed on
# the machine running this drift check.
EXPECTED_AGENT_MAIL_MCP_URL="http://127.0.0.1:8765/mcp/"
REPO_MCP_CONFIG_FILES=(
    ".claude/settings.local.json"
    "cline.mcp.json"
    "cursor.mcp.json"
    "gemini.mcp.json"
    "opencode.json"
    "windsurf.mcp.json"
)

# Defaults
FIX_MODE=false
JSON_MODE=false
QUIET=false

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix)    FIX_MODE=true; shift ;;
        --json)   JSON_MODE=true; shift ;;
        --quiet)  QUIET=true; shift ;;
        --help|-h)
            head -20 "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 3 ;;
    esac
done

log() { $QUIET || echo "[manifest-drift] $*" >&2; }
log_error() { echo "[manifest-drift] ERROR: $*" >&2; }

require_readable_file() {
    local file="$1"
    local description="$2"

    if [[ ! -f "$file" ]]; then
        log_error "$description not found: $file"
        return 1
    fi
    if [[ ! -r "$file" ]]; then
        log_error "$description not readable: $file"
        return 1
    fi
}

sha256_file() {
    local file="$1"
    local description="$2"
    local output

    require_readable_file "$file" "$description" || return 1
    if ! output="$(sha256sum "$file" 2>/dev/null)"; then
        log_error "Failed to compute SHA256 for $description: $file"
        return 1
    fi

    printf '%s\n' "${output%% *}"
}

extract_assignment_value() {
    local file="$1"
    local key="$2"
    local description="$3"
    local value

    require_readable_file "$file" "$description" || return 1
    if ! value="$(awk -F= -v key="$key" '$1 == key { gsub(/["[:space:]\r]/, "", $2); print $2; exit }' "$file")"; then
        log_error "Failed to read $key from $description: $file"
        return 1
    fi

    printf '%s\n' "$value"
}

INTERNAL_CHECKSUM_PATHS=()
INTERNAL_CHECKSUM_VALUES=()
INTERNAL_CHECKSUMS_EXPECTED_COUNT=0
INTERNAL_CHECKSUM_REQUIRED_PATHS=(
    install.sh
    checksums.yaml
    scripts/preflight.sh
    scripts/lib/security.sh
    scripts/lib/github_api.sh
    scripts/lib/contract.sh
    scripts/lib/agents.sh
    scripts/lib/update.sh
    scripts/lib/doctor.sh
    scripts/lib/acfs-services.sh
    scripts/lib/doctor_fix.sh
    scripts/lib/offline_artifact_pack.sh
    scripts/lib/autofix.sh
    scripts/lib/autofix_existing.sh
    scripts/lib/autofix_unattended.sh
    scripts/lib/autofix_version_managers.sh
    scripts/lib/ubuntu_upgrade.sh
    scripts/lib/upgrade_resume.sh
    scripts/lib/install_helpers.sh
    scripts/lib/logging.sh
    scripts/lib/output.sh
    scripts/lib/gum_ui.sh
    scripts/lib/progress.sh
    scripts/lib/state.sh
    scripts/lib/report.sh
    scripts/lib/error_tracking.sh
    scripts/lib/session.sh
    scripts/lib/os_detect.sh
    scripts/lib/errors.sh
    scripts/lib/user.sh
    scripts/lib/tools.sh
    scripts/lib/tailscale.sh
    scripts/lib/webhook.sh
    scripts/lib/notify.sh
    scripts/lib/stack.sh
    scripts/lib/export-config.sh
    scripts/acfs-global
    scripts/acfs-update
    scripts/lib/nightly_update.sh
    scripts/templates/acfs-upgrade-resume.service
    scripts/templates/acfs-nightly-update.service
    scripts/templates/acfs-nightly-update.timer
    packages/onboard/onboard.sh
    scripts/generated/manifest_index.sh
    scripts/generated/doctor_checks.sh
    scripts/generated/install_all.sh
    scripts/generated/install_base.sh
    scripts/generated/install_users.sh
    scripts/generated/install_filesystem.sh
    scripts/generated/install_shell.sh
    scripts/generated/install_cli.sh
    scripts/generated/install_network.sh
    scripts/generated/install_lang.sh
    scripts/generated/install_tools.sh
    scripts/generated/install_db.sh
    scripts/generated/install_cloud.sh
    scripts/generated/install_agents.sh
    scripts/generated/install_stack.sh
    scripts/generated/install_acfs.sh
)

# Closed publication set. Auto-fix may stage and commit only these exact files;
# matching extensions or directory-wide pathspecs are not an authority boundary.
GENERATED_OUTPUT_PATHS=(
    scripts/generated/doctor_checks.sh
    scripts/generated/install_acfs.sh
    scripts/generated/install_agents.sh
    scripts/generated/install_all.sh
    scripts/generated/install_base.sh
    scripts/generated/install_cli.sh
    scripts/generated/install_cloud.sh
    scripts/generated/install_db.sh
    scripts/generated/install_filesystem.sh
    scripts/generated/install_lang.sh
    scripts/generated/install_network.sh
    scripts/generated/install_shell.sh
    scripts/generated/install_stack.sh
    scripts/generated/install_tools.sh
    scripts/generated/install_users.sh
    scripts/generated/internal_checksums.sh
    scripts/generated/manifest_index.sh
    apps/web/lib/generated/manifest-commands.ts
    apps/web/lib/generated/manifest-lessons-index.ts
    apps/web/lib/generated/manifest-modules.ts
    apps/web/lib/generated/manifest-tldr.ts
    apps/web/lib/generated/manifest-tools.ts
    apps/web/lib/generated/manifest-web-index.ts
)

if ! command -v jq &>/dev/null; then
    log_error "jq is required for structured manifest/config validation"
    exit 3
fi
if ! command -v bun &>/dev/null; then
    log_error "bun is required; generated-artifact and semantic drift checks cannot be skipped"
    exit 3
fi

parse_internal_checksums_file() {
    local file="$1"
    require_readable_file "$file" "Internal checksums file" || return 1

    INTERNAL_CHECKSUM_PATHS=()
    INTERNAL_CHECKSUM_VALUES=()
    INTERNAL_CHECKSUMS_EXPECTED_COUNT=0

    if [[ -L "$file" ]]; then
        log_error "Internal checksums file must not be a symlink: $file"
        return 1
    fi

    local ledger_size=""
    ledger_size="$(stat -c '%s' -- "$file" 2>/dev/null || true)"
    if [[ ! "$ledger_size" =~ ^[0-9]+$ ]]; then
        ledger_size="$(stat -f '%z' "$file" 2>/dev/null || true)"
    fi
    if [[ ! "$ledger_size" =~ ^[0-9]+$ ]] || (( ledger_size == 0 || ledger_size > 65536 )); then
        log_error "Internal checksum ledger exceeds its 64 KiB byte bound"
        return 1
    fi
    local -a ledger_lines=()
    if ! mapfile -t ledger_lines < "$file"; then
        log_error "Internal checksum ledger could not be read"
        return 1
    fi

    local line=""
    local line_count=0
    local schema_seen=0
    local count_seen=0
    local array_open=false
    local array_seen=false
    local -A seen_paths=()
    local parse_state="expect_schema"
    for line in "${ledger_lines[@]}"; do
        ((line_count += 1))
        if (( line_count > 128 )) || ((${#line} > 4096)); then
            log_error "Internal checksum ledger exceeds its bounded data grammar"
            return 1
        fi
        case "$line" in
            ''|'#'*) continue ;;
            'ACFS_INTERNAL_CHECKSUMS_SCHEMA=1')
                [[ "$parse_state" == "expect_schema" ]] || return 1
                ((schema_seen += 1))
                parse_state="expect_array"
                continue
                ;;
            'declare -gA ACFS_INTERNAL_CHECKSUMS=(')
                [[ "$parse_state" == "expect_array" ]] || return 1
                [[ "$array_seen" == "false" && "$array_open" == "false" ]] || return 1
                array_seen=true
                array_open=true
                parse_state="in_array"
                continue
                ;;
            ')')
                [[ "$parse_state" == "in_array" && "$array_open" == "true" ]] || return 1
                array_open=false
                parse_state="expect_count"
                continue
                ;;
        esac
        if [[ "$line" =~ ^[[:space:]]*\[([A-Za-z0-9_./-]+)\]=\"([0-9a-f]{64})\"$ ]]; then
            [[ "$parse_state" == "in_array" && "$array_open" == "true" ]] || return 1
            local rel_path="${BASH_REMATCH[1]}"
            case "$rel_path" in /*|*..*) return 1 ;; esac
            [[ -z "${seen_paths[$rel_path]+present}" ]] || return 1
            seen_paths["$rel_path"]=1
            INTERNAL_CHECKSUM_PATHS+=("$rel_path")
            INTERNAL_CHECKSUM_VALUES+=("${BASH_REMATCH[2]}")
            continue
        fi
        if [[ "$line" =~ ^ACFS_INTERNAL_CHECKSUMS_COUNT=([0-9]+)$ ]]; then
            [[ "$parse_state" == "expect_count" ]] || return 1
            ((count_seen += 1))
            INTERNAL_CHECKSUMS_EXPECTED_COUNT="${BASH_REMATCH[1]}"
            parse_state="done"
            continue
        fi
        log_error "Internal checksum ledger contains unsupported data"
        return 1
    done

    if (( schema_seen != 1 || count_seen != 1 )) \
        || [[ "$array_seen" != "true" || "$array_open" == "true" || "$parse_state" != "done" ]] \
        || [[ "$INTERNAL_CHECKSUMS_EXPECTED_COUNT" != "${#INTERNAL_CHECKSUM_PATHS[@]}" ]]; then
        log_error "Internal checksum ledger structure/count is invalid"
        return 1
    fi

    if [[ ${#INTERNAL_CHECKSUM_PATHS[@]} -ne ${#INTERNAL_CHECKSUM_REQUIRED_PATHS[@]} ]]; then
        log_error "Internal checksum ledger membership count is not canonical"
        return 1
    fi
    local -A parsed_paths=()
    local parsed_path=""
    for parsed_path in "${INTERNAL_CHECKSUM_PATHS[@]}"; do
        parsed_paths["$parsed_path"]=1
    done
    local required_path=""
    for required_path in "${INTERNAL_CHECKSUM_REQUIRED_PATHS[@]}"; do
        if [[ -z "${parsed_paths[$required_path]+present}" ]]; then
            log_error "Internal checksum ledger is missing canonical path: $required_path"
            return 1
        fi
    done
}

extract_repo_mcp_config_url() {
    local rel_path="$1"
    local abs_path="$2"

    command -v jq &>/dev/null || return 1

    case "$rel_path" in
        .claude/settings.local.json|cline.mcp.json|cursor.mcp.json|windsurf.mcp.json)
            jq -er '.mcpServers["mcp-agent-mail"].url // empty' "$abs_path" 2>/dev/null
            ;;
        gemini.mcp.json)
            jq -er '.mcpServers["mcp-agent-mail"].httpUrl // .mcpServers["mcp-agent-mail"].url // empty' "$abs_path" 2>/dev/null
            ;;
        opencode.json)
            jq -er '.mcp["mcp-agent-mail"].url // empty' "$abs_path" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

GENERATED_ARTIFACT_STATUS="skipped"
GENERATED_ARTIFACT_DRIFT_FILES=()
GENERATED_ARTIFACT_DRIFT_COUNT=0
GENERATED_ARTIFACT_STALE_FILES=()
GENERATED_ARTIFACT_STALE_COUNT=0
MANIFEST_CONTRACT_STATUS="skipped"
MANIFEST_CONTRACT_DRIFT_FILES=()
MANIFEST_CONTRACT_MISMATCH_CODES=()
MANIFEST_CONTRACT_DRIFT_COUNT=0
MANIFEST_CONTRACT_CHECKED=0

check_generated_artifact_drift() {
    local record_drift="${1:-true}"
    local diff_output=""
    local diff_status=0
    local line=""

    GENERATED_ARTIFACT_STATUS="skipped"
    GENERATED_ARTIFACT_DRIFT_FILES=()
    GENERATED_ARTIFACT_DRIFT_COUNT=0
    GENERATED_ARTIFACT_STALE_FILES=()
    GENERATED_ARTIFACT_STALE_COUNT=0

    set +e
    diff_output="$(
        cd "$REPO_ROOT/packages/manifest" &&
        bun run generate:diff 2>&1
    )"
    diff_status=$?
    set -e

    case "$diff_status" in
        0)
            GENERATED_ARTIFACT_STATUS="clean"
            log "Generated artifacts: generate:diff reports clean"
            return 0
            ;;
        1)
            GENERATED_ARTIFACT_STATUS="drift"
            while IFS= read -r line; do
                if [[ "$line" =~ ^\[(DIFF|NEW|STALE)\][[:space:]]+(.+)$ ]]; then
                    GENERATED_ARTIFACT_DRIFT_FILES+=("${BASH_REMATCH[2]}")
                    if [[ "${BASH_REMATCH[1]}" == "STALE" ]]; then
                        GENERATED_ARTIFACT_STALE_FILES+=("${BASH_REMATCH[2]}")
                    fi
                fi
            done <<< "$diff_output"
            GENERATED_ARTIFACT_DRIFT_COUNT=${#GENERATED_ARTIFACT_DRIFT_FILES[@]}
            GENERATED_ARTIFACT_STALE_COUNT=${#GENERATED_ARTIFACT_STALE_FILES[@]}
            if [[ "$GENERATED_ARTIFACT_DRIFT_COUNT" -eq 0 ]]; then
                GENERATED_ARTIFACT_STATUS="error"
                log_error "generate:diff failed before reporting any generated-file differences"
                if [[ -n "$diff_output" ]]; then
                    log_error "$diff_output"
                fi
                return 1
            fi
            if [[ "$record_drift" == "true" ]]; then
                DRIFT_DETECTED=true
                DRIFT_REASONS+=(
                    "Generated artifact drift: ${GENERATED_ARTIFACT_DRIFT_FILES[*]}"
                )
            fi
            log "Generated artifacts: $GENERATED_ARTIFACT_DRIFT_COUNT drifted"
            return 0
            ;;
        *)
            GENERATED_ARTIFACT_STATUS="error"
            log_error "generate:diff failed unexpectedly"
            if [[ -n "$diff_output" ]]; then
                log_error "$diff_output"
            fi
            return 1
            ;;
    esac
}

check_manifest_contract_drift() {
    local record_drift="${1:-true}"
    local contract_output=""
    local contract_status=0
    local contract_summary=""

    MANIFEST_CONTRACT_STATUS="skipped"
    MANIFEST_CONTRACT_DRIFT_FILES=()
    MANIFEST_CONTRACT_MISMATCH_CODES=()
    MANIFEST_CONTRACT_DRIFT_COUNT=0
    MANIFEST_CONTRACT_CHECKED=0

    set +e
    contract_output="$(
        cd "$REPO_ROOT/packages/manifest" &&
        bun run src/drift-contract.ts --json --root "$REPO_ROOT" 2>&1
    )"
    contract_status=$?
    set -e

    case "$contract_status" in
        0)
            MANIFEST_CONTRACT_STATUS="clean"
            if command -v jq &>/dev/null; then
                MANIFEST_CONTRACT_CHECKED="$(jq -r '.summary.checked // 0' <<< "$contract_output" 2>/dev/null || printf '0\n')"
            fi
            log "Manifest drift contract: clean (${MANIFEST_CONTRACT_CHECKED} checks)"
            return 0
            ;;
        1)
            MANIFEST_CONTRACT_STATUS="drift"
            if command -v jq &>/dev/null && jq -e . >/dev/null 2>&1 <<< "$contract_output"; then
                MANIFEST_CONTRACT_DRIFT_COUNT="$(jq -r '.mismatches | length' <<< "$contract_output")"
                MANIFEST_CONTRACT_CHECKED="$(jq -r '.summary.checked // 0' <<< "$contract_output")"
                mapfile -t MANIFEST_CONTRACT_DRIFT_FILES < <(
                    jq -r '.mismatches[].file // empty' <<< "$contract_output" | sort -u | sed '/^$/d'
                )
                mapfile -t MANIFEST_CONTRACT_MISMATCH_CODES < <(
                    jq -r '.mismatches[].code // empty' <<< "$contract_output" | sort -u | sed '/^$/d'
                )
            else
                MANIFEST_CONTRACT_DRIFT_COUNT=1
                MANIFEST_CONTRACT_DRIFT_FILES=("manifest contract")
                MANIFEST_CONTRACT_MISMATCH_CODES=("MANIFEST_CONTRACT_DRIFT")
            fi

            if [[ "$record_drift" == "true" ]]; then
                DRIFT_DETECTED=true
                contract_summary="${MANIFEST_CONTRACT_MISMATCH_CODES[*]}"
                if [[ -z "$contract_summary" ]]; then
                    contract_summary="see packages/manifest/src/drift-contract.ts"
                fi
                DRIFT_REASONS+=("Manifest contract drift: $contract_summary")
            fi
            log "Manifest drift contract: $MANIFEST_CONTRACT_DRIFT_COUNT drifted"
            return 0
            ;;
        *)
            MANIFEST_CONTRACT_STATUS="error"
            log_error "manifest drift contract failed unexpectedly"
            if [[ -n "$contract_output" ]]; then
                log_error "$contract_output"
            fi
            return 1
            ;;
    esac
}

check_repo_mcp_config_drift() {
    local record_drift="${1:-true}"
    REPO_MCP_CONFIGS_CHECKED=0
    REPO_MCP_CONFIG_DRIFT_COUNT=0
    REPO_MCP_CONFIG_DRIFT_FILES=()

    local rel_path abs_path configured_url
    for rel_path in "${REPO_MCP_CONFIG_FILES[@]}"; do
        abs_path="$REPO_ROOT/$rel_path"

        if [[ ! -f "$abs_path" || -L "$abs_path" ]]; then
            REPO_MCP_CONFIG_DRIFT_COUNT=$((REPO_MCP_CONFIG_DRIFT_COUNT + 1))
            REPO_MCP_CONFIG_DRIFT_FILES+=("$rel_path")
            if [[ "$record_drift" == "true" ]]; then
                DRIFT_DETECTED=true
                DRIFT_REASONS+=("Repo MCP config missing or unsafe: $rel_path")
            fi
            continue
        fi

        REPO_MCP_CONFIGS_CHECKED=$((REPO_MCP_CONFIGS_CHECKED + 1))
        if ! configured_url="$(extract_repo_mcp_config_url "$rel_path" "$abs_path")"; then
            REPO_MCP_CONFIG_DRIFT_COUNT=$((REPO_MCP_CONFIG_DRIFT_COUNT + 1))
            REPO_MCP_CONFIG_DRIFT_FILES+=("$rel_path")
            if [[ "$record_drift" == "true" ]]; then
                DRIFT_DETECTED=true
                DRIFT_REASONS+=("Repo MCP config malformed or unreadable: $rel_path")
            fi
            continue
        fi
        if [[ "$configured_url" != "$EXPECTED_AGENT_MAIL_MCP_URL" ]]; then
            REPO_MCP_CONFIG_DRIFT_COUNT=$((REPO_MCP_CONFIG_DRIFT_COUNT + 1))
            REPO_MCP_CONFIG_DRIFT_FILES+=("$rel_path")
            if [[ "$record_drift" == "true" ]]; then
                DRIFT_DETECTED=true
                DRIFT_REASONS+=("Repo MCP config drift: $rel_path uses ${configured_url:-<missing>} (expected $EXPECTED_AGENT_MAIL_MCP_URL)")
            fi
        fi
    done
}

# Verify prerequisites
MANIFEST="$REPO_ROOT/acfs.manifest.yaml"
INDEX="$REPO_ROOT/scripts/generated/manifest_index.sh"

if [[ ! -f "$MANIFEST" ]]; then
    log_error "Manifest not found: $MANIFEST"
    exit 3
fi
if [[ ! -f "$INDEX" ]]; then
    log_error "Generated index not found: $INDEX"
    exit 3
fi

# Compute actual hash
if ! ACTUAL_SHA256="$(sha256_file "$MANIFEST" "Manifest")"; then
    exit 3
fi

# Extract recorded hash from generated index
if ! RECORDED_SHA256="$(extract_assignment_value "$INDEX" "ACFS_MANIFEST_SHA256" "Generated manifest index")"; then
    exit 3
fi

if [[ -z "$RECORDED_SHA256" ]]; then
    log_error "Could not extract ACFS_MANIFEST_SHA256 from $INDEX"
    exit 3
fi

# Count SHA256 lines (detect duplicate)
SHA_LINE_COUNT=$(grep -c 'ACFS_MANIFEST_SHA256=' "$INDEX" || true)

# Count modules in manifest vs generated index
MANIFEST_MODULE_COUNT=$(grep -c '^[[:space:]]*- id:' "$MANIFEST" || true)
INDEX_MODULE_COUNT=$(awk '/^ACFS_MODULES_IN_ORDER=/,/^\)/' "$INDEX" | grep -c '"' || true)

DRIFT_DETECTED=false
DRIFT_REASONS=()

if [[ "$ACTUAL_SHA256" != "$RECORDED_SHA256" ]]; then
    DRIFT_DETECTED=true
    DRIFT_REASONS+=("SHA256 mismatch: actual=$ACTUAL_SHA256 recorded=$RECORDED_SHA256")
fi

if [[ "$SHA_LINE_COUNT" -gt 1 ]]; then
    DRIFT_DETECTED=true
    DRIFT_REASONS+=("Duplicate ACFS_MANIFEST_SHA256 lines: $SHA_LINE_COUNT found")
fi

if [[ "$MANIFEST_MODULE_COUNT" -ne "$INDEX_MODULE_COUNT" ]]; then
    DRIFT_DETECTED=true
    DRIFT_REASONS+=("Module count mismatch: manifest=$MANIFEST_MODULE_COUNT index=$INDEX_MODULE_COUNT")
fi

# ============================================================
# Internal script checksum verification (bd-3tpl)
# ============================================================
INTERNAL_CHECKSUMS_FILE="$REPO_ROOT/scripts/generated/internal_checksums.sh"
INTERNAL_DRIFT_COUNT=0
INTERNAL_DRIFT_FILES=()
INTERNAL_CHECKED=0
REPO_MCP_CONFIGS_CHECKED=0
REPO_MCP_CONFIG_DRIFT_COUNT=0
REPO_MCP_CONFIG_DRIFT_FILES=()

if [[ -L "$INTERNAL_CHECKSUMS_FILE" ]]; then
    log_error "Internal checksums file must not be a symlink: $INTERNAL_CHECKSUMS_FILE"
    exit 3
elif [[ -f "$INTERNAL_CHECKSUMS_FILE" ]]; then
    if ! parse_internal_checksums_file "$INTERNAL_CHECKSUMS_FILE"; then
        exit 3
    fi

    if [[ "$INTERNAL_CHECKSUMS_EXPECTED_COUNT" =~ ^[0-9]+$ ]] && [[ ${#INTERNAL_CHECKSUM_PATHS[@]} -ne "$INTERNAL_CHECKSUMS_EXPECTED_COUNT" ]]; then
        INTERNAL_DRIFT_COUNT=$((INTERNAL_DRIFT_COUNT + 1))
        INTERNAL_DRIFT_FILES+=("internal checksum index (parsed ${#INTERNAL_CHECKSUM_PATHS[@]} of expected $INTERNAL_CHECKSUMS_EXPECTED_COUNT)")
        DRIFT_DETECTED=true
        DRIFT_REASONS+=("Internal checksum index malformed: parsed ${#INTERNAL_CHECKSUM_PATHS[@]} of expected $INTERNAL_CHECKSUMS_EXPECTED_COUNT entries")
    fi

    if [[ ${#INTERNAL_CHECKSUM_PATHS[@]} -gt 0 ]]; then
        for i in "${!INTERNAL_CHECKSUM_PATHS[@]}"; do
            rel_path="${INTERNAL_CHECKSUM_PATHS[$i]}"
            expected="${INTERNAL_CHECKSUM_VALUES[$i]}"
            abs_path="$REPO_ROOT/$rel_path"
            if [[ -f "$abs_path" && ! -L "$abs_path" ]]; then
                if ! actual="$(sha256_file "$abs_path" "Internal script $rel_path")"; then
                    exit 3
                fi
                INTERNAL_CHECKED=$((INTERNAL_CHECKED + 1))
                if [[ "$actual" != "$expected" ]]; then
                    INTERNAL_DRIFT_COUNT=$((INTERNAL_DRIFT_COUNT + 1))
                    INTERNAL_DRIFT_FILES+=("$rel_path")
                    DRIFT_DETECTED=true
                    DRIFT_REASONS+=("Internal script checksum mismatch: $rel_path")
                fi
            else
                INTERNAL_DRIFT_COUNT=$((INTERNAL_DRIFT_COUNT + 1))
                INTERNAL_DRIFT_FILES+=("$rel_path (MISSING)")
                DRIFT_DETECTED=true
                DRIFT_REASONS+=("Internal script missing: $rel_path")
            fi
        done
        log "Internal checksums: $INTERNAL_CHECKED checked, $INTERNAL_DRIFT_COUNT drifted"
    else
        if ! [[ "$INTERNAL_CHECKSUMS_EXPECTED_COUNT" =~ ^[0-9]+$ ]] || [[ "$INTERNAL_CHECKSUMS_EXPECTED_COUNT" -eq 0 ]]; then
            log "Warning: No internal checksum entries parsed from $INTERNAL_CHECKSUMS_FILE"
        fi
    fi
else
    INTERNAL_DRIFT_COUNT=$((INTERNAL_DRIFT_COUNT + 1))
    INTERNAL_DRIFT_FILES+=("scripts/generated/internal_checksums.sh (MISSING)")
    DRIFT_DETECTED=true
    DRIFT_REASONS+=("Mandatory internal checksum ledger is missing")
    log "Internal checksums file is missing"
fi

check_repo_mcp_config_drift
log "Repo MCP configs: $REPO_MCP_CONFIGS_CHECKED checked, $REPO_MCP_CONFIG_DRIFT_COUNT drifted"
if ! check_generated_artifact_drift; then
    exit 3
fi
if ! check_manifest_contract_drift; then
    exit 3
fi

# Output results
if $JSON_MODE; then
    reasons_json="[]"
    if [[ ${#DRIFT_REASONS[@]} -gt 0 ]]; then
        reasons_json=$(printf '%s\n' "${DRIFT_REASONS[@]}" | jq -R . | jq -s .)
    fi
    internal_drift_json="[]"
    if [[ ${#INTERNAL_DRIFT_FILES[@]} -gt 0 ]]; then
        internal_drift_json=$(printf '%s\n' "${INTERNAL_DRIFT_FILES[@]}" | jq -R . | jq -s .)
    fi
    repo_mcp_drift_json="[]"
    if [[ ${#REPO_MCP_CONFIG_DRIFT_FILES[@]} -gt 0 ]]; then
        repo_mcp_drift_json=$(printf '%s\n' "${REPO_MCP_CONFIG_DRIFT_FILES[@]}" | jq -R . | jq -s .)
    fi
    generated_artifact_drift_json="[]"
    if [[ ${#GENERATED_ARTIFACT_DRIFT_FILES[@]} -gt 0 ]]; then
        generated_artifact_drift_json=$(printf '%s\n' "${GENERATED_ARTIFACT_DRIFT_FILES[@]}" | jq -R . | jq -s .)
    fi
    manifest_contract_drift_json="[]"
    if [[ ${#MANIFEST_CONTRACT_DRIFT_FILES[@]} -gt 0 ]]; then
        manifest_contract_drift_json=$(printf '%s\n' "${MANIFEST_CONTRACT_DRIFT_FILES[@]}" | jq -R . | jq -s .)
    fi
    manifest_contract_code_json="[]"
    if [[ ${#MANIFEST_CONTRACT_MISMATCH_CODES[@]} -gt 0 ]]; then
        manifest_contract_code_json=$(printf '%s\n' "${MANIFEST_CONTRACT_MISMATCH_CODES[@]}" | jq -R . | jq -s .)
    fi
    jq -nc \
        --argjson drift "$DRIFT_DETECTED" \
        --arg actual "$ACTUAL_SHA256" \
        --arg recorded "$RECORDED_SHA256" \
        --arg expected_mcp_url "$EXPECTED_AGENT_MAIL_MCP_URL" \
        --arg generated_status "$GENERATED_ARTIFACT_STATUS" \
        --arg manifest_contract_status "$MANIFEST_CONTRACT_STATUS" \
        --argjson sha_lines "$SHA_LINE_COUNT" \
        --argjson manifest_modules "$MANIFEST_MODULE_COUNT" \
        --argjson index_modules "$INDEX_MODULE_COUNT" \
        --argjson internal_checked "$INTERNAL_CHECKED" \
        --argjson internal_drifted "$INTERNAL_DRIFT_COUNT" \
        --argjson internal_drift_files "$internal_drift_json" \
        --argjson repo_mcp_checked "$REPO_MCP_CONFIGS_CHECKED" \
        --argjson repo_mcp_drifted "$REPO_MCP_CONFIG_DRIFT_COUNT" \
        --argjson repo_mcp_drift_files "$repo_mcp_drift_json" \
        --argjson generated_artifact_drifted "$GENERATED_ARTIFACT_DRIFT_COUNT" \
        --argjson generated_artifact_drift_files "$generated_artifact_drift_json" \
        --argjson manifest_contract_checked "$MANIFEST_CONTRACT_CHECKED" \
        --argjson manifest_contract_drifted "$MANIFEST_CONTRACT_DRIFT_COUNT" \
        --argjson manifest_contract_drift_files "$manifest_contract_drift_json" \
        --argjson manifest_contract_codes "$manifest_contract_code_json" \
        --argjson reasons "$reasons_json" \
        '{
            drift_detected: $drift,
            manifest: {
                actual_sha256: $actual,
                recorded_sha256: $recorded,
                sha256_line_count: $sha_lines,
                manifest_modules: $manifest_modules,
                index_modules: $index_modules
            },
            internal_scripts: {
                checked: $internal_checked,
                drifted: $internal_drifted,
                drift_files: $internal_drift_files
            },
            repo_mcp_configs: {
                expected_url: $expected_mcp_url,
                checked: $repo_mcp_checked,
                drifted: $repo_mcp_drifted,
                drift_files: $repo_mcp_drift_files
            },
            generated_artifacts: {
                status: $generated_status,
                drifted: $generated_artifact_drifted,
                drift_files: $generated_artifact_drift_files
            },
            manifest_contract: {
                status: $manifest_contract_status,
                checked: $manifest_contract_checked,
                drifted: $manifest_contract_drifted,
                drift_files: $manifest_contract_drift_files,
                mismatch_codes: $manifest_contract_codes
            },
            reasons: $reasons
        }'
    if ! $FIX_MODE; then
        if $DRIFT_DETECTED; then
            exit 1
        else
            exit 0
        fi
    fi
fi

if ! $DRIFT_DETECTED; then
    log "No drift detected. SHA256=$ACTUAL_SHA256 (${INDEX_MODULE_COUNT} modules)"
    exit 0
fi

# Drift detected
for reason in "${DRIFT_REASONS[@]}"; do
    log_error "$reason"
done

if ! $FIX_MODE; then
    log "Drift detected but --fix not specified. Run with --fix to auto-repair."
    exit 1
fi

if [[ "$GENERATED_ARTIFACT_STALE_COUNT" -gt 0 ]]; then
    log_error "Refusing --fix while stale generated files require removal: ${GENERATED_ARTIFACT_STALE_FILES[*]}"
    log_error "Regeneration cannot remove files, and ACFS requires explicit written approval before deletion."
    exit 2
fi

# Auto-fix: regenerate, commit, push
log "Auto-fixing manifest drift..."

generation_dirty_sources() {
    local status_output=""
    cd "$REPO_ROOT" || return 1
    if ! status_output="$(git status --porcelain -- \
        install.sh \
        VERSION \
        scripts/preflight.sh \
        scripts/lib \
        scripts/acfs-global \
        scripts/acfs-update \
        scripts/templates \
        acfs.manifest.yaml \
        checksums.yaml \
        README.md \
        acfs/onboard/lessons \
        packages/onboard/onboard.sh \
        packages/manifest 2>/dev/null)"; then
        return 1
    fi
    while IFS= read -r status_line; do
        [[ "$status_line" == '?? '* ]] && continue
        [[ -n "$status_line" ]] && printf '%s\n' "$status_line"
    done <<< "$status_output"
}

# Synchronize before deriving any artifact. Rebasing after verification could
# change a checksummed source and then push a stale ledger.
cd "$REPO_ROOT"
current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ "$current_branch" != "main" ]]; then
    log_error "--fix only runs on main (current: ${current_branch:-detached})"
    exit 2
fi
if ! git diff --cached --quiet; then
    log_error "Refusing --fix with pre-existing staged changes; generated publication requires an isolated index"
    exit 2
fi

# Refuse to fix if any tracked source file (anything contributing to
# ACFS_INTERNAL_CHECKSUMS, verified-installer checksum validation, or the
# generated installer scripts) has uncommitted changes. Otherwise
# `bun run generate` would validate or hash dirty working-tree contents and
# we'd push generated artifacts that don't match what's actually committed,
# which is the failure mode that broke Pinned Ref Smoke and the offline
# bootstrap installer tests on c55a89eb.
if ! DIRTY_SOURCES="$(generation_dirty_sources)"; then
    log_error "Unable to inspect tracked generation sources"
    exit 2
fi
if [[ -n "$DIRTY_SOURCES" ]]; then
    log_error "Refusing to auto-fix: tracked source files have uncommitted changes."
    log_error "Otherwise generated checksums would capture working-tree state and"
    log_error "diverge from what's actually committed/pushed. Commit (or stash)"
    log_error "these first, then re-run with --fix:"
    while IFS= read -r _line; do
        [[ -z "$_line" ]] || log_error "  $_line"
    done <<< "$DIRTY_SOURCES"
    exit 2
fi
if ! git pull --rebase origin main; then
    log_error "Pull --rebase failed before regeneration; no generated files were changed"
    exit 2
fi
if ! DIRTY_SOURCES="$(generation_dirty_sources)"; then
    log_error "Unable to inspect tracked generation sources after synchronization"
    exit 2
fi
if [[ -n "$DIRTY_SOURCES" ]]; then
    log_error "Tracked generation sources changed while synchronizing; refusing to generate"
    exit 2
fi
FIX_BASE_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
if [[ ! "$FIX_BASE_HEAD" =~ ^[0-9a-f]{40}$ ]]; then
    log_error "Unable to pin HEAD after synchronization"
    exit 2
fi

# Regenerate
cd "$REPO_ROOT/packages/manifest"
if ! bun run generate >&2; then
    log_error "bun run generate failed"
    exit 2
fi

if ! DIRTY_SOURCES="$(generation_dirty_sources)"; then
    log_error "Unable to inspect tracked generation sources after generation"
    exit 2
fi
if [[ -n "$DIRTY_SOURCES" ]]; then
    log_error "Tracked generation sources changed during generation; refusing to commit artifacts"
    while IFS= read -r _line; do
        [[ -z "$_line" ]] || log_error "  $_line"
    done <<< "$DIRTY_SOURCES"
    exit 2
fi

# Verify manifest fix
if ! NEW_RECORDED="$(extract_assignment_value "$INDEX" "ACFS_MANIFEST_SHA256" "Generated manifest index")"; then
    exit 2
fi
if ! ACTUAL_NOW="$(sha256_file "$MANIFEST" "Manifest")"; then
    exit 2
fi

if [[ -z "$NEW_RECORDED" ]]; then
    log_error "Could not extract ACFS_MANIFEST_SHA256 from $INDEX after regeneration"
    exit 2
fi

if [[ "$NEW_RECORDED" != "$ACTUAL_NOW" ]]; then
    log_error "Regeneration did not fix manifest mismatch! recorded=$NEW_RECORDED actual=$ACTUAL_NOW"
    exit 2
fi

log "Manifest SHA256 now matches: $ACTUAL_NOW"

# Always prove the complete closed-world checksum contract after generation;
# the pre-fix drift count cannot establish what the generator just wrote.
if [[ ! -f "$INTERNAL_CHECKSUMS_FILE" || -L "$INTERNAL_CHECKSUMS_FILE" ]]; then
    log_error "Generated internal checksum ledger is missing or unsafe"
    exit 2
fi
log "Verifying internal script checksums after regeneration..."
if ! parse_internal_checksums_file "$INTERNAL_CHECKSUMS_FILE"; then
    exit 2
fi
post_fix_drift=0
for i in "${!INTERNAL_CHECKSUM_PATHS[@]}"; do
    rel_path="${INTERNAL_CHECKSUM_PATHS[$i]}"
    expected="${INTERNAL_CHECKSUM_VALUES[$i]}"
    abs_path="$REPO_ROOT/$rel_path"
    if [[ ! -f "$abs_path" || -L "$abs_path" ]]; then
        post_fix_drift=$((post_fix_drift + 1))
        log_error "Missing or unsafe after fix: $rel_path"
        continue
    fi
    if ! actual="$(sha256_file "$abs_path" "Internal script $rel_path")"; then
        exit 2
    fi
    if [[ "$actual" != "$expected" ]]; then
        post_fix_drift=$((post_fix_drift + 1))
        log_error "Still drifted after fix: $rel_path"
    fi
done
if [[ "$post_fix_drift" -gt 0 ]]; then
    log_error "Internal checksum drift persists after regeneration ($post_fix_drift files)"
    exit 2
fi
log "Internal script checksums verified clean after regeneration"

check_repo_mcp_config_drift false
if [[ "$REPO_MCP_CONFIG_DRIFT_COUNT" -gt 0 ]]; then
    log_error "Repo MCP config drift still requires manual repair: ${REPO_MCP_CONFIG_DRIFT_FILES[*]}"
    exit 2
fi
if ! check_generated_artifact_drift false; then
    exit 2
fi
if [[ "$GENERATED_ARTIFACT_DRIFT_COUNT" -gt 0 ]]; then
    log_error "Generated artifact drift persists after regeneration: ${GENERATED_ARTIFACT_DRIFT_FILES[*]}"
    exit 2
fi
if ! check_manifest_contract_drift false; then
    exit 2
fi
if [[ "$MANIFEST_CONTRACT_DRIFT_COUNT" -gt 0 ]]; then
    log_error "Manifest contract drift requires manual repair: ${MANIFEST_CONTRACT_MISMATCH_CODES[*]}"
    exit 2
fi

# Commit and push
cd "$REPO_ROOT"

# Stage only the closed publication set, after proving every member is a real
# file. This cannot stage deletions, nested surprises, or extension-matching
# scratch files left by another process.
for generated_path in "${GENERATED_OUTPUT_PATHS[@]}"; do
    if [[ ! -f "$REPO_ROOT/$generated_path" || -L "$REPO_ROOT/$generated_path" ]]; then
        log_error "Generated publication member is missing or unsafe: $generated_path"
        exit 2
    fi
done
git add -- "${GENERATED_OUTPUT_PATHS[@]}"

if git diff --cached --quiet -- "${GENERATED_OUTPUT_PATHS[@]}"; then
    log "No generated artifact changes after regeneration (already up to date)"
    exit 0
fi

declare -A allowed_generated_paths=()
for generated_path in "${GENERATED_OUTPUT_PATHS[@]}"; do
    allowed_generated_paths["$generated_path"]=1
done
while IFS= read -r staged_path; do
    [[ -n "$staged_path" ]] || continue
    if [[ -z "${allowed_generated_paths[$staged_path]+present}" ]]; then
        log_error "Unexpected staged path entered generated publication: $staged_path"
        exit 2
    fi
done < <(git diff --cached --name-only)
if [[ -n "$(git diff --cached --name-only --diff-filter=D -- "${GENERATED_OUTPUT_PATHS[@]}")" ]]; then
    log_error "Refusing to commit a generated-file deletion"
    exit 2
fi

if ! DIRTY_SOURCES="$(generation_dirty_sources)"; then
    log_error "Unable to inspect tracked generation sources before commit"
    exit 2
fi
if [[ -n "$DIRTY_SOURCES" ]]; then
    log_error "Tracked generation sources changed before commit; leaving generated files staged for inspection"
    exit 2
fi

if [[ "$(git rev-parse HEAD 2>/dev/null || true)" != "$FIX_BASE_HEAD" ]]; then
    log_error "HEAD changed during generated publication; refusing to commit"
    exit 2
fi
if ! check_generated_artifact_drift false \
    || [[ "$GENERATED_ARTIFACT_DRIFT_COUNT" -gt 0 ]]; then
    log_error "Generated output changed between verification and staging"
    exit 2
fi
if ! git diff --quiet -- "${GENERATED_OUTPUT_PATHS[@]}"; then
    log_error "Generated worktree bytes changed after staging"
    exit 2
fi
STAGED_GENERATED_FINGERPRINT="$(git ls-files -s -- "${GENERATED_OUTPUT_PATHS[@]}" | sha256sum | awk '{print $1}')"
if [[ ! "$STAGED_GENERATED_FINGERPRINT" =~ ^[0-9a-f]{64}$ ]]; then
    log_error "Unable to fingerprint staged generated objects"
    exit 2
fi
if [[ "$(git rev-parse HEAD 2>/dev/null || true)" != "$FIX_BASE_HEAD" ]] \
    || [[ "$(git ls-files -s -- "${GENERATED_OUTPUT_PATHS[@]}" | sha256sum | awk '{print $1}')" != "$STAGED_GENERATED_FINGERPRINT" ]]; then
    log_error "HEAD or staged generated objects changed immediately before commit"
    exit 2
fi

git commit -m "$(cat <<'COMMIT_MSG'
fix(manifest): auto-fix generated artifact checksum drift

Detected by check-manifest-drift.sh.
Regenerated installer and web generated artifacts via `bun run generate`
to sync ACFS_MANIFEST_SHA256 and internal checksums with source files.
COMMIT_MSG
)"

while IFS= read -r committed_path; do
    [[ -n "$committed_path" ]] || continue
    if [[ -z "${allowed_generated_paths[$committed_path]+present}" ]]; then
        log_error "Generated commit contains an unexpected path: $committed_path"
        exit 2
    fi
done < <(git diff-tree --no-commit-id --name-only -r HEAD)
if ! check_generated_artifact_drift false \
    || [[ "$GENERATED_ARTIFACT_DRIFT_COUNT" -gt 0 ]]; then
    log_error "Generated artifacts are not clean after commit; refusing to push"
    exit 2
fi

# Push to main first, then mirror to master for legacy compatibility
if ! git push origin HEAD:main; then
    log_error "Push to main failed; fix committed locally but not pushed"
    exit 2
fi
if ! git push origin main:master; then
    log_error "Push to master mirror failed after pushing main"
    exit 2
fi

log "Fix committed and pushed successfully."

exit 0
