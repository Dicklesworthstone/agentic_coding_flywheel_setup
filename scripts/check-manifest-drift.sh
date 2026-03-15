#!/usr/bin/env bash
# check-manifest-drift.sh - Detect and auto-fix ACFS manifest/script/config drift
#
# This script verifies that scripts/generated/manifest_index.sh has the correct
# SHA256 hash for acfs.manifest.yaml, that internal library scripts match
# their recorded checksums in scripts/generated/internal_checksums.sh, that the
# full set of generated artifacts still matches `bun run generate:diff`, and
# that checked-in MCP Agent Mail client configs still point at the canonical
# HTTP URL. If drift is detected, it can regenerate all generated scripts,
# commit, and push.
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
# Detect MCP base path: Rust am uses /mcp/, Python mcp_agent_mail uses /api/
if command -v am &>/dev/null && am --version 2>/dev/null | grep -q '^am '; then
    EXPECTED_AGENT_MAIL_MCP_URL="http://127.0.0.1:8765/mcp/"
else
    EXPECTED_AGENT_MAIL_MCP_URL="http://127.0.0.1:8765/api/"
fi
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

if $JSON_MODE && ! command -v jq &>/dev/null; then
    log_error "jq is required for --json output"
    exit 3
fi

parse_internal_checksums_file() {
    local file="$1"
    require_readable_file "$file" "Internal checksums file" || return 1

    INTERNAL_CHECKSUM_PATHS=()
    INTERNAL_CHECKSUM_VALUES=()
    INTERNAL_CHECKSUMS_EXPECTED_COUNT=0

    INTERNAL_CHECKSUMS_EXPECTED_COUNT=$(
        grep -E '^ACFS_INTERNAL_CHECKSUMS_COUNT=' "$file" | head -n 1 | cut -d'=' -f2 | tr -d '"[:space:]\r' || true
    )

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*\[([^]]+)\]=\"([0-9A-Fa-f]{64})\"[[:space:]]*$ ]]; then
            INTERNAL_CHECKSUM_PATHS+=("${BASH_REMATCH[1]}")
            INTERNAL_CHECKSUM_VALUES+=("${BASH_REMATCH[2],,}")
        fi
    done < "$file"
}

extract_repo_mcp_config_url() {
    local rel_path="$1"
    local abs_path="$2"

    command -v jq &>/dev/null || return 1

    case "$rel_path" in
        .claude/settings.local.json|cline.mcp.json|cursor.mcp.json|windsurf.mcp.json)
            jq -r '.mcpServers["mcp-agent-mail"].url // empty' "$abs_path" 2>/dev/null || true
            ;;
        gemini.mcp.json)
            jq -r '.mcpServers["mcp-agent-mail"].httpUrl // .mcpServers["mcp-agent-mail"].url // empty' "$abs_path" 2>/dev/null || true
            ;;
        opencode.json)
            jq -r '.mcp["mcp-agent-mail"].url // empty' "$abs_path" 2>/dev/null || true
            ;;
        *)
            return 1
            ;;
    esac
}

GENERATED_ARTIFACT_STATUS="skipped"
GENERATED_ARTIFACT_DRIFT_FILES=()
GENERATED_ARTIFACT_DRIFT_COUNT=0

check_generated_artifact_drift() {
    local record_drift="${1:-true}"
    local diff_output=""
    local diff_status=0
    local line=""

    GENERATED_ARTIFACT_STATUS="skipped"
    GENERATED_ARTIFACT_DRIFT_FILES=()
    GENERATED_ARTIFACT_DRIFT_COUNT=0

    if ! command -v bun &>/dev/null; then
        log "Warning: bun not found; skipping generate:diff validation"
        return 0
    fi

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
                if [[ "$line" =~ ^\[(DIFF|NEW)\][[:space:]]+(.+)$ ]]; then
                    GENERATED_ARTIFACT_DRIFT_FILES+=("${BASH_REMATCH[2]}")
                fi
            done <<< "$diff_output"
            GENERATED_ARTIFACT_DRIFT_COUNT=${#GENERATED_ARTIFACT_DRIFT_FILES[@]}
            if [[ "$GENERATED_ARTIFACT_DRIFT_COUNT" -eq 0 ]]; then
                GENERATED_ARTIFACT_DRIFT_FILES+=("manifest-derived outputs differ")
                GENERATED_ARTIFACT_DRIFT_COUNT=1
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

check_repo_mcp_config_drift() {
    local record_drift="${1:-true}"
    REPO_MCP_CONFIGS_CHECKED=0
    REPO_MCP_CONFIG_DRIFT_COUNT=0
    REPO_MCP_CONFIG_DRIFT_FILES=()

    local rel_path abs_path configured_url
    for rel_path in "${REPO_MCP_CONFIG_FILES[@]}"; do
        abs_path="$REPO_ROOT/$rel_path"

        if [[ ! -f "$abs_path" ]]; then
            continue
        fi

        REPO_MCP_CONFIGS_CHECKED=$((REPO_MCP_CONFIGS_CHECKED + 1))
        configured_url="$(extract_repo_mcp_config_url "$rel_path" "$abs_path" || true)"
        if [[ -n "$configured_url" ]]; then
            if [[ "$configured_url" == "$EXPECTED_AGENT_MAIL_MCP_URL" ]]; then
                continue
            fi
            REPO_MCP_CONFIG_DRIFT_COUNT=$((REPO_MCP_CONFIG_DRIFT_COUNT + 1))
            REPO_MCP_CONFIG_DRIFT_FILES+=("$rel_path")
            if [[ "$record_drift" == "true" ]]; then
                DRIFT_DETECTED=true
                DRIFT_REASONS+=("Repo MCP config drift: $rel_path uses $configured_url (expected $EXPECTED_AGENT_MAIL_MCP_URL)")
            fi
            continue
        fi

        if ! grep -Fq "$EXPECTED_AGENT_MAIL_MCP_URL" "$abs_path"; then
            REPO_MCP_CONFIG_DRIFT_COUNT=$((REPO_MCP_CONFIG_DRIFT_COUNT + 1))
            REPO_MCP_CONFIG_DRIFT_FILES+=("$rel_path")
            if [[ "$record_drift" == "true" ]]; then
                DRIFT_DETECTED=true
                DRIFT_REASONS+=("Repo MCP config drift: $rel_path should contain $EXPECTED_AGENT_MAIL_MCP_URL")
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

if [[ -f "$INTERNAL_CHECKSUMS_FILE" ]]; then
    if ! parse_internal_checksums_file "$INTERNAL_CHECKSUMS_FILE"; then
        exit 3
    fi

    if [[ ${#INTERNAL_CHECKSUM_PATHS[@]} -gt 0 ]]; then
        for i in "${!INTERNAL_CHECKSUM_PATHS[@]}"; do
            rel_path="${INTERNAL_CHECKSUM_PATHS[$i]}"
            expected="${INTERNAL_CHECKSUM_VALUES[$i]}"
            abs_path="$REPO_ROOT/$rel_path"
            if [[ -f "$abs_path" ]]; then
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
        if [[ "$INTERNAL_CHECKSUMS_EXPECTED_COUNT" =~ ^[0-9]+$ ]] && [[ "$INTERNAL_CHECKSUMS_EXPECTED_COUNT" -gt 0 ]]; then
            INTERNAL_DRIFT_COUNT=$INTERNAL_CHECKSUMS_EXPECTED_COUNT
            DRIFT_DETECTED=true
            DRIFT_REASONS+=("Internal checksum index malformed: parsed 0 of expected $INTERNAL_CHECKSUMS_EXPECTED_COUNT entries")
        else
            log "Warning: No internal checksum entries parsed from $INTERNAL_CHECKSUMS_FILE"
        fi
    fi
else
    log "Internal checksums file not found (pre-migration), skipping"
fi

check_repo_mcp_config_drift
log "Repo MCP configs: $REPO_MCP_CONFIGS_CHECKED checked, $REPO_MCP_CONFIG_DRIFT_COUNT drifted"
if ! check_generated_artifact_drift; then
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
    jq -nc \
        --argjson drift "$DRIFT_DETECTED" \
        --arg actual "$ACTUAL_SHA256" \
        --arg recorded "$RECORDED_SHA256" \
        --arg expected_mcp_url "$EXPECTED_AGENT_MAIL_MCP_URL" \
        --arg generated_status "$GENERATED_ARTIFACT_STATUS" \
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

# Auto-fix: regenerate, commit, push
log "Auto-fixing manifest drift..."

# Check prerequisites for fix
if ! command -v bun &>/dev/null; then
    log_error "bun not found - cannot regenerate"
    exit 2
fi

# Regenerate
cd "$REPO_ROOT/packages/manifest"
if ! bun run generate >&2; then
    log_error "bun run generate failed"
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

# Verify internal checksums fix (if file was regenerated)
if [[ -f "$INTERNAL_CHECKSUMS_FILE" ]] && [[ "$INTERNAL_DRIFT_COUNT" -gt 0 ]]; then
    log "Verifying internal script checksums after regeneration..."
    if ! parse_internal_checksums_file "$INTERNAL_CHECKSUMS_FILE"; then
        exit 2
    fi
    post_fix_drift=0
    for i in "${!INTERNAL_CHECKSUM_PATHS[@]}"; do
        rel_path="${INTERNAL_CHECKSUM_PATHS[$i]}"
        expected="${INTERNAL_CHECKSUM_VALUES[$i]}"
        abs_path="$REPO_ROOT/$rel_path"
        if [[ -f "$abs_path" ]]; then
            if ! actual="$(sha256_file "$abs_path" "Internal script $rel_path")"; then
                exit 2
            fi
            if [[ "$actual" != "$expected" ]]; then
                post_fix_drift=$((post_fix_drift + 1))
                log_error "Still drifted after fix: $rel_path"
            fi
        fi
    done
    if [[ "$post_fix_drift" -gt 0 ]]; then
        log_error "Internal checksum drift persists after regeneration ($post_fix_drift files)"
        exit 2
    fi
    log "Internal script checksums verified clean after regeneration"
fi

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

# Commit and push
cd "$REPO_ROOT"

git add scripts/generated/
if [[ -d "$REPO_ROOT/apps/web/lib/generated" ]]; then
    git add apps/web/lib/generated/
fi

if git diff --cached --quiet; then
    log "No generated artifact changes after regeneration (already up to date)"
    exit 0
fi

git commit -m "$(cat <<'COMMIT_MSG'
fix(manifest): auto-fix generated artifact checksum drift

Detected by check-manifest-drift.sh.
Regenerated installer and web generated artifacts via `bun run generate`
to sync ACFS_MANIFEST_SHA256 and internal checksums with source files.
COMMIT_MSG
)"

# Pull latest main first to avoid non-fast-forward push failures
if ! git pull --rebase origin main; then
    log_error "Pull --rebase failed; fix committed locally but not pushed"
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
