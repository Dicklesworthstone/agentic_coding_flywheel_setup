#!/usr/bin/env bash
# ============================================================
# ACFS Nightly Update - Pre-flight wrapper
#
# Called by systemd timer at 4am. Checks system health before
# running acfs-update to avoid updating under adverse conditions.
#
# Pre-flight checks:
#   1. Load average - skip if system is overloaded
#   2. Disk space   - skip if critically low (<2GB)
#   3. Low-risk cleanup if disk is tight (<5GB)
#   4. Run acfs-update --yes --quiet
#
# Logs to: ~/.acfs/logs/updates/nightly-YYYY-MM-DD-HHMMSS.log
# ============================================================

set -euo pipefail

# Resolve home directory (systemd %h may not set HOME reliably)
HOME="${HOME:-$(getent passwd "$(id -un)" | cut -d: -f6)}"
export HOME

TIMESTAMP="$(date '+%Y-%m-%d-%H%M%S')"
LOG_DIR="$HOME/.acfs/logs/updates"
LOG_FILE="$LOG_DIR/nightly-${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"

# Redirect all output to log file AND journal (stdout/stderr already go to journal via systemd)
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== ACFS Nightly Update starting ==="
log "Date: $(date)"
log "Host: $(hostname)"

# ── Source notification library (best-effort, non-fatal) ─────
_ACFS_NOTIFY_LIB=""
for _candidate in \
    "$HOME/.acfs/scripts/lib/notify.sh" \
    "/data/projects/agentic_coding_flywheel_setup/scripts/lib/notify.sh"; do
    if [[ -f "$_candidate" ]]; then
        _ACFS_NOTIFY_LIB="$_candidate"
        break
    fi
done
if [[ -n "$_ACFS_NOTIFY_LIB" ]]; then
    # shellcheck source=scripts/lib/notify.sh
    source "$_ACFS_NOTIFY_LIB" 2>/dev/null || true
fi

# ── Pre-flight 1: Load average check ──────────────────────
NPROC="$(nproc)"
LOAD_5MIN="$(awk '{print $2}' /proc/loadavg)"

# Compare as integers (bash can't do float comparison natively)
LOAD_INT="${LOAD_5MIN%%.*}"
if [[ "$LOAD_INT" -ge "$NPROC" ]]; then
    log "SKIP: 5-min load average ($LOAD_5MIN) >= nproc ($NPROC). System overloaded."
    exit 0
fi
log "OK: Load average $LOAD_5MIN < $NPROC cores"

# ── Pre-flight 2: Disk space check ────────────────────────
# Get available space on root filesystem in GB
ROOT_AVAIL_KB="$(df --output=avail / | tail -1 | tr -d ' ')"
ROOT_AVAIL_GB="$((ROOT_AVAIL_KB / 1048576))"

if [[ "$ROOT_AVAIL_GB" -lt 2 ]]; then
    log "SKIP: Root filesystem has only ${ROOT_AVAIL_GB}GB free (need >= 2GB). Critically low."
    exit 0
fi
log "OK: Root filesystem has ${ROOT_AVAIL_GB}GB free"

# ── Pre-flight 3: Low-risk cleanup if tight on space ──────
if [[ "$ROOT_AVAIL_GB" -lt 5 ]]; then
    log "WARN: Disk below 5GB free (${ROOT_AVAIL_GB}GB). Running safe cleanup..."
    FREED=0

    # Clean old /tmp build artifacts (>7 days)
    # Note: || true after du pipeline guards against set -eo pipefail
    # killing the script if a file disappears between find and du (race).
    for pattern in "cargo-install*" "rustc*" "npm-*" "bun-*"; do
        while IFS= read -r -d '' dir; do
            sz="$(du -sk "$dir" 2>/dev/null | cut -f1 || true)"
            sz="${sz:-0}"
            rm -rf "$dir" 2>/dev/null && FREED=$((FREED + sz)) && log "  Cleaned: $dir (${sz}KB)"
        done < <(find /tmp -maxdepth 1 -name "$pattern" -mtime +7 -print0 2>/dev/null || true)
    done

    # Clean old nightly logs (>30 days)
    while IFS= read -r -d '' f; do
        sz="$(du -sk "$f" 2>/dev/null | cut -f1 || true)"
        sz="${sz:-0}"
        rm -f "$f" 2>/dev/null && FREED=$((FREED + sz)) && log "  Cleaned: $f (${sz}KB)"
    done < <(find "$LOG_DIR" -name "nightly-*.log" -mtime +30 -print0 2>/dev/null || true)

    # Cargo registry cache if > 500MB
    CARGO_REGISTRY="$HOME/.cargo/registry/cache"
    if [[ -d "$CARGO_REGISTRY" ]]; then
        REG_SIZE_KB="$(du -sk "$CARGO_REGISTRY" 2>/dev/null | cut -f1 || true)"
        REG_SIZE_KB="${REG_SIZE_KB:-0}"
        if [[ "$REG_SIZE_KB" -gt 512000 ]]; then
            rm -rf "$CARGO_REGISTRY" 2>/dev/null || true
            FREED=$((FREED + REG_SIZE_KB))
            log "  Cleaned: cargo registry cache (${REG_SIZE_KB}KB)"
        fi
    fi

    # Bun install cache if > 500MB
    BUN_CACHE="$HOME/.bun/install/cache"
    if [[ -d "$BUN_CACHE" ]]; then
        BUN_SIZE_KB="$(du -sk "$BUN_CACHE" 2>/dev/null | cut -f1 || true)"
        BUN_SIZE_KB="${BUN_SIZE_KB:-0}"
        if [[ "$BUN_SIZE_KB" -gt 512000 ]]; then
            rm -rf "$BUN_CACHE" 2>/dev/null || true
            FREED=$((FREED + BUN_SIZE_KB))
            log "  Cleaned: bun install cache (${BUN_SIZE_KB}KB)"
        fi
    fi

    log "Cleanup freed ~$((FREED / 1024))MB"
fi

# ── Run acfs-update ───────────────────────────────────────
ACFS_UPDATE=""
for candidate in \
    "$HOME/.local/bin/acfs-update" \
    "$HOME/.acfs/scripts/lib/update.sh" \
    "/data/projects/agentic_coding_flywheel_setup/scripts/acfs-update"; do
    if [[ -x "$candidate" ]]; then
        ACFS_UPDATE="$candidate"
        break
    fi
done

if [[ -z "$ACFS_UPDATE" ]]; then
    log "ERROR: acfs-update not found in any expected location"
    exit 1
fi

log "Running: $ACFS_UPDATE --yes --quiet"
log "---"

# Run update; capture exit code but don't fail the whole script
set +e
"$ACFS_UPDATE" --yes --quiet
UPDATE_RC=$?
set -e

log "---"
if [[ "$UPDATE_RC" -eq 0 ]]; then
    log "=== Nightly update completed successfully ==="
    if type -t acfs_notify_update_success &>/dev/null; then
        acfs_notify_update_success 2>/dev/null || true
    fi
else
    log "=== Nightly update finished with exit code $UPDATE_RC ==="
    if type -t acfs_notify_update_failure &>/dev/null; then
        acfs_notify_update_failure "exit code $UPDATE_RC" 2>/dev/null || true
    fi
fi

exit "$UPDATE_RC"
