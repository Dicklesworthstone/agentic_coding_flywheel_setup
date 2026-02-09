#!/usr/bin/env bash
# check-manifest-drift.sh - Detect and auto-fix ACFS manifest/script SHA256 drift
#
# This script verifies that scripts/generated/manifest_index.sh has the correct
# SHA256 hash for acfs.manifest.yaml, AND that internal library scripts match
# their recorded checksums in scripts/generated/internal_checksums.sh.
# If drift is detected, it can regenerate all generated scripts, commit, and push.
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
ACTUAL_SHA256=$(sha256sum "$MANIFEST" | awk '{print $1}')

# Extract recorded hash from generated index
RECORDED_SHA256=$(grep -oP 'ACFS_MANIFEST_SHA256="\K[a-f0-9]+' "$INDEX" | head -1)

if [[ -z "$RECORDED_SHA256" ]]; then
    log_error "Could not extract ACFS_MANIFEST_SHA256 from $INDEX"
    exit 3
fi

# Count SHA256 lines (detect duplicate)
SHA_LINE_COUNT=$(grep -c 'ACFS_MANIFEST_SHA256=' "$INDEX" || true)

# Count modules in manifest vs generated index
MANIFEST_MODULE_COUNT=$(grep -c '^\s*- id:' "$MANIFEST" || true)
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

# ============================================================
# Internal script checksum verification (bd-3tpl)
# ============================================================
INTERNAL_CHECKSUMS_FILE="$REPO_ROOT/scripts/generated/internal_checksums.sh"
INTERNAL_DRIFT_COUNT=0
INTERNAL_DRIFT_FILES=()
INTERNAL_CHECKED=0

if [[ -f "$INTERNAL_CHECKSUMS_FILE" ]]; then
    # Source the checksums file to get ACFS_INTERNAL_CHECKSUMS associative array
    # shellcheck source=generated/internal_checksums.sh
    source "$INTERNAL_CHECKSUMS_FILE"

    if declare -p ACFS_INTERNAL_CHECKSUMS &>/dev/null; then
        for rel_path in "${!ACFS_INTERNAL_CHECKSUMS[@]}"; do
            expected="${ACFS_INTERNAL_CHECKSUMS[$rel_path]}"
            abs_path="$REPO_ROOT/$rel_path"
            if [[ -f "$abs_path" ]]; then
                actual=$(sha256sum "$abs_path" | awk '{print $1}')
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
        log "Warning: ACFS_INTERNAL_CHECKSUMS not defined in $INTERNAL_CHECKSUMS_FILE"
    fi
else
    log "Internal checksums file not found (pre-migration), skipping"
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
    jq -nc \
        --argjson drift "$DRIFT_DETECTED" \
        --arg actual "$ACTUAL_SHA256" \
        --arg recorded "$RECORDED_SHA256" \
        --argjson sha_lines "$SHA_LINE_COUNT" \
        --argjson manifest_modules "$MANIFEST_MODULE_COUNT" \
        --argjson index_modules "$INDEX_MODULE_COUNT" \
        --argjson internal_checked "$INTERNAL_CHECKED" \
        --argjson internal_drifted "$INTERNAL_DRIFT_COUNT" \
        --argjson internal_drift_files "$internal_drift_json" \
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
            reasons: $reasons
        }'
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
if ! bun run generate 2>&1; then
    log_error "bun run generate failed"
    exit 2
fi

# Verify manifest fix
NEW_RECORDED=$(grep -oP 'ACFS_MANIFEST_SHA256="\K[a-f0-9]+' "$INDEX" | head -1)
ACTUAL_NOW=$(sha256sum "$MANIFEST" | awk '{print $1}')

if [[ "$NEW_RECORDED" != "$ACTUAL_NOW" ]]; then
    log_error "Regeneration did not fix manifest mismatch! recorded=$NEW_RECORDED actual=$ACTUAL_NOW"
    exit 2
fi

log "Manifest SHA256 now matches: $ACTUAL_NOW"

# Verify internal checksums fix (if file was regenerated)
if [[ -f "$INTERNAL_CHECKSUMS_FILE" ]] && [[ "$INTERNAL_DRIFT_COUNT" -gt 0 ]]; then
    log "Verifying internal script checksums after regeneration..."
    unset ACFS_INTERNAL_CHECKSUMS
    source "$INTERNAL_CHECKSUMS_FILE"
    post_fix_drift=0
    for rel_path in "${!ACFS_INTERNAL_CHECKSUMS[@]}"; do
        expected="${ACFS_INTERNAL_CHECKSUMS[$rel_path]}"
        abs_path="$REPO_ROOT/$rel_path"
        if [[ -f "$abs_path" ]]; then
            actual=$(sha256sum "$abs_path" | awk '{print $1}')
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

# Commit and push
cd "$REPO_ROOT"

if git diff --quiet scripts/generated/; then
    log "No changes in generated scripts after regeneration (already up to date)"
    exit 0
fi

git add scripts/generated/
git commit -m "$(cat <<'COMMIT_MSG'
fix(manifest): auto-fix SHA256 drift in generated scripts

Detected by check-manifest-drift.sh (scheduled systemd timer).
Regenerated all scripts via `bun run generate` to sync with current
acfs.manifest.yaml hash.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
COMMIT_MSG
)"

# Push (main:master for compat)
if git push origin main:master 2>&1; then
    log "Fix committed and pushed successfully."
else
    log_error "Push failed - fix committed locally but not pushed"
    exit 2
fi

exit 0
