#!/usr/bin/env bash
# ============================================================
# ACFS Checksum Monitor (local) — replaces the GitHub Actions
# checksum-monitor workflow with a host-local systemd timer.
#
# Faithfully reproduces .github/workflows/checksum-monitor.yml:
#   1. Sync a dedicated clone to origin/main (ff-only; never resets).
#   2. Detect generated-artifact drift (check-manifest-drift.sh --json)
#      and auto-repair it (--fix regenerates, commits, and pushes).
#   3. Verify every upstream installer against checksums.yaml
#      (security.sh --verify --json).
#   4. FAIL CLOSED: any fetch error or skipped entry aborts the run
#      with no update — partial/placeholder checksums are never written.
#   5. On genuine mismatches: regenerate checksums.yaml via the
#      canonical updater, commit (same message format as the workflow),
#      pull --rebase, push main, and mirror main -> master.
#   6. External (non-Dicklesworthstone) changes additionally open or
#      extend a GitHub issue labeled security,checksum-update so a
#      human reviews them — same dedupe rule as the workflow.
#
# Deployment (maintainer host, e.g. ts1):
#   git clone https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup ~/acfs-monitor
#   cp ~/acfs-monitor/scripts/templates/acfs-checksum-monitor.{service,timer} \
#      ~/.config/systemd/user/
#   systemctl --user daemon-reload
#   systemctl --user enable --now acfs-checksum-monitor.timer
#   loginctl enable-linger "$USER"   # so the timer runs without a login session
#
# Requirements on the host: git (push access via gh credential helper),
# gh (authenticated), bun, jq, curl, flock.
#
# Environment overrides:
#   ACFS_MONITOR_REPO   clone to operate on   (default: ~/acfs-monitor)
#   ACFS_MONITOR_STATE  state/log directory   (default: ~/.local/state/acfs-monitor)
# ============================================================

set -euo pipefail

MONITOR_REPO="${ACFS_MONITOR_REPO:-$HOME/acfs-monitor}"
STATE_DIR="${ACFS_MONITOR_STATE:-$HOME/.local/state/acfs-monitor}"
LOG_DIR="$STATE_DIR/logs"
LOCK_FILE="$STATE_DIR/monitor.lock"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="$LOG_DIR/run-$RUN_TS.log"

mkdir -p "$LOG_DIR"

log() {
    printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$LOG_FILE" >&2
}

# Consecutive fail-closed runs are tracked so a persistently broken monitor
# (expired gh auth, dead network, wedged clone) alerts a human instead of
# silently leaving checksums unmonitored. Alerting is strictly best-effort:
# it must never mask the fail-closed exit or itself abort the trap path.
FAIL_STREAK_FILE="$STATE_DIR/fail_closed_streak"

_alert_fail_closed_streak() {
    local streak="$1" reason="$2"
    # Alert when the streak first crosses 3, then re-alert every 24 runs
    # (~6h at the 15-minute timer cadence) while it persists.
    if (( streak != 3 )) && { (( streak < 3 )) || (( streak % 24 != 0 )); }; then
        return 0
    fi
    local alert_msg="ACFS checksum monitor has failed closed $streak times in a row on $(hostname 2>/dev/null || echo unknown-host). Latest reason: $reason. Checksum drift is NOT being monitored until this is fixed. See $LOG_DIR."
    # Optional push notification
    if [[ -n "${ACFS_NTFY_TOPIC:-}" ]]; then
        curl -fsS -m 10 -A "OpenAI File Downloader, XaiImageApiFetch/1.0" \
            -d "$alert_msg" "https://ntfy.sh/${ACFS_NTFY_TOPIC}" \
            >>"$LOG_FILE" 2>&1 || true
    fi
    # GitHub issue (deduped by label + search, same pattern as the
    # external-change review issue below)
    local repo_slug="Dicklesworthstone/agentic_coding_flywheel_setup"
    local existing=""
    existing="$(gh issue list --repo "$repo_slug" --state open \
        --label monitoring \
        --search "Checksum monitor failing closed" \
        --json number -q '.[0].number' 2>>"$LOG_FILE" || true)"
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        gh issue comment "$existing" --repo "$repo_slug" \
            --body "$alert_msg" >>"$LOG_FILE" 2>&1 \
            && log "commented on existing monitoring issue #$existing" || true
    else
        gh issue create --repo "$repo_slug" \
            --title "🚨 Checksum monitor failing closed - checksums unmonitored" \
            --label monitoring \
            --body "$alert_msg" >>"$LOG_FILE" 2>&1 \
            && log "created monitoring alert issue" || true
    fi
}

fail_closed() {
    log "FAIL-CLOSED: $*"
    local streak=0
    streak="$(command cat "$FAIL_STREAK_FILE" 2>/dev/null || echo 0)"
    [[ "$streak" =~ ^[0-9]+$ ]] || streak=0
    streak=$((streak + 1))
    printf '%s\n' "$streak" > "$FAIL_STREAK_FILE" 2>/dev/null || true
    _alert_fail_closed_streak "$streak" "$*" || true
    log "summary: result=fail_closed streak=$streak repo=$MONITOR_REPO"
    exit 1
}

# ---- single-instance lock (timer overlap is a silent no-op) ----
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    # Another run is active; skipping is the correct behavior for a
    # 15-minute timer, so exit success without noise.
    exit 0
fi

# ---- log rotation: keep two weeks of runs ----
find "$LOG_DIR" -name 'run-*.log' -type f -mtime +14 -delete 2>/dev/null || true

log "ACFS checksum monitor starting (repo: $MONITOR_REPO)"

for dep in git gh jq curl bun flock; do
    command -v "$dep" >/dev/null 2>&1 || fail_closed "missing dependency: $dep"
done

[[ -d "$MONITOR_REPO/.git" ]] || fail_closed "monitor clone not found at $MONITOR_REPO"
cd "$MONITOR_REPO"

# ---- 1. sync clone to origin/main (never destructive) ----
git fetch origin main --quiet || fail_closed "git fetch failed"
git checkout main --quiet 2>/dev/null || fail_closed "cannot checkout main"
if ! git merge --ff-only origin/main --quiet 2>>"$LOG_FILE"; then
    fail_closed "clone has diverged from origin/main (refusing non-ff merge; inspect $MONITOR_REPO manually)"
fi
log "clone synced to $(git rev-parse --short HEAD)"

# Commit identity for any automated commits from this host.
git config user.name  "acfs-checksum-monitor ($(hostname -s))"
git config user.email "jeff141421@gmail.com"

# ---- generator dependencies (idempotent, quiet) ----
( cd packages/manifest && bun install --silent >>"$LOG_FILE" 2>&1 ) \
    || fail_closed "bun install failed in packages/manifest"

# ---- 2. generated-artifact drift check ----
drift_json="$STATE_DIR/drift-$RUN_TS.json"
set +e
bash scripts/check-manifest-drift.sh --json >"$drift_json" 2>>"$LOG_FILE"
drift_exit=$?
set -e
if [[ "$drift_exit" -gt 1 ]]; then
    fail_closed "drift checker failed (exit $drift_exit)"
fi
jq empty "$drift_json" 2>/dev/null || fail_closed "drift checker returned invalid JSON"

drift_detected="$(jq -r '.drift_detected' "$drift_json")"
drift_fixed=false
if [[ "$drift_detected" == "true" ]]; then
    log "generated artifact drift detected:"
    jq -r '.reasons[] | "  - \(.)"' "$drift_json" | tee -a "$LOG_FILE" >&2
    # --fix regenerates, commits, and pushes on its own (same as the workflow).
    bash scripts/check-manifest-drift.sh --fix >>"$LOG_FILE" 2>&1 \
        || fail_closed "drift --fix failed (see $LOG_FILE)"
    drift_fixed=true
    log "drift auto-fixed and pushed"
else
    log "no generated-artifact drift"
fi

# ---- 3. verify upstream checksums ----
verify_json="$STATE_DIR/verify-$RUN_TS.json"
set +e
bash scripts/lib/security.sh --verify --json >"$verify_json" 2>>"$LOG_FILE"
set -e
jq empty "$verify_json" 2>/dev/null || fail_closed "checksum verification returned invalid JSON"

mismatches="$(jq '.mismatches | length' "$verify_json")"
errors="$(jq '.errors | length' "$verify_json")"
skipped="$(jq '.skipped | length' "$verify_json")"

# ---- 4. fail closed on any error/skip ----
if [[ "$errors" -gt 0 || "$skipped" -gt 0 ]]; then
    jq -r '.errors[]?  | "  error: \(.name) -> \(.error)"'    "$verify_json" | tee -a "$LOG_FILE" >&2
    jq -r '.skipped[]? | "  skipped: \(.name) -> \(.reason)"' "$verify_json" | tee -a "$LOG_FILE" >&2
    fail_closed "verification returned $errors error(s) / $skipped skip(s); refusing to auto-update checksums.yaml"
fi

trusted_changed=""
external_changed=""
if [[ "$mismatches" -gt 0 ]]; then
    while IFS= read -r name; do
        url="$(jq -r --arg n "$name" '.mismatches[] | select(.name==$n) | .url // empty' "$verify_json")"
        if [[ "$url" == *"Dicklesworthstone"* ]]; then
            trusted_changed="${trusted_changed}${name},"
        else
            external_changed="${external_changed}${name},"
        fi
    done < <(jq -r '.mismatches[].name' "$verify_json")
fi
trusted_changed="${trusted_changed%,}"
external_changed="${external_changed%,}"

committed=false
if [[ "$mismatches" -gt 0 ]]; then
    changed_tools="$(jq -r '.mismatches[].name' "$verify_json" | paste -sd, -)"
    log "changed tools: $changed_tools (trusted: ${trusted_changed:-none}; external: ${external_changed:-none})"

    # ---- 5. regenerate checksums via the canonical updater ----
    candidate="$STATE_DIR/checksums-$RUN_TS.yaml"
    bash scripts/lib/security.sh --update-checksums >"$candidate" 2>>"$LOG_FILE" \
        || fail_closed "--update-checksums failed"
    # Belt-and-suspenders beyond the workflow: never accept an empty or
    # shrunken candidate (a network blip must not truncate the manifest).
    old_count="$(grep -c 'sha256:' checksums.yaml || true)"
    new_count="$(grep -c 'sha256:' "$candidate" || true)"
    if [[ ! -s "$candidate" || "$new_count" -lt "$old_count" ]]; then
        fail_closed "candidate checksums.yaml invalid (entries: $new_count vs $old_count)"
    fi
    cp "$candidate" checksums.yaml

    # Regenerate in the same run: manifest-modules.ts embeds
    # checksumsYamlSha256, so skipping this leaves a guaranteed drift for
    # the next run to clean up (the Actions workflow had that two-step lag).
    ( cd packages/manifest && bun run generate >>"$LOG_FILE" 2>&1 ) \
        || fail_closed "regeneration after checksum update failed"

    # Tracked files plus brand-new generator outputs only; other stray
    # untracked files in the generated dirs must never ride along in an
    # automated commit. Without the new-file pass, a first-time generated
    # script (new manifest category) would stay untracked and the drift
    # check would wedge the monitor on every run.
    git add checksums.yaml 2>/dev/null || true
    git add -u scripts/generated/ apps/web/lib/generated/ 2>/dev/null || true
    while IFS= read -r new_generated; do
        case "$new_generated" in
            scripts/generated/*.sh|apps/web/lib/generated/*.ts) git add -- "$new_generated" 2>/dev/null || true ;;
        esac
    done < <(git ls-files --others --exclude-standard -- scripts/generated apps/web/lib/generated 2>/dev/null)
    if git diff --cached --quiet; then
        log "no staged changes after regeneration (already current)"
    else
        subject="chore(security): auto-update checksums for ${changed_tools}"
        if [[ "$drift_fixed" == "true" ]]; then
            subject="chore(security): auto-update checksums + generated drift fixes"
        fi
        git commit --quiet \
            -m "$subject" \
            -m "Updated checksums for upstream installer scripts that have changed." \
            -m "" \
            -m "Changed tools: ${changed_tools}" \
            -m "Trusted: ${trusted_changed:-none}" \
            -m "External: ${external_changed:-none}" \
            -m "Drift fixed: ${drift_fixed}" \
            -m "" \
            -m "Generated by checksum-monitor-local on $(hostname -s)"
        if ! git pull --rebase --quiet origin main; then
            git rebase --abort 2>/dev/null || true
            # Leaving the local commit in place wedged the monitor for good:
            # the next run's `merge --ff-only origin/main` then fails forever
            # ("diverged") with only a log line. This clone is dedicated and
            # every monitor commit is regenerable, so drop the local commit
            # and let the next run redo it on top of the new origin/main.
            if git checkout --quiet --detach && git branch -f main origin/main && git checkout --quiet main; then
                log "rebase conflict; discarded the local monitor commit and re-synced to origin/main — next run will retry"
            else
                log "rebase conflict and re-sync failed; inspect $MONITOR_REPO manually"
            fi
        else
            git push --quiet origin HEAD:main \
                && git push --quiet origin main:master \
                && committed=true
            log "checksum update pushed (main + master)"
        fi
    fi
else
    log "all checksums match upstream"
fi

# ---- 6. issue for external changes (security visibility) ----
if [[ -n "$external_changed" && "$committed" == "true" ]]; then
    repo_slug="Dicklesworthstone/agentic_coding_flywheel_setup"
    body_file="$STATE_DIR/issue-body-$RUN_TS.md"
    {
        echo "## External Installer Checksums Updated"
        echo
        echo "The following **external** (non-Dicklesworthstone) installer scripts have changed:"
        echo
        tr ',' '\n' <<<"$external_changed" | sed 's/^/- `/; s/$/`/'
        echo
        echo "### Action Required"
        echo "These checksums were automatically updated. Please verify the upstream changes are legitimate:"
        echo
        tr ',' '\n' <<<"$external_changed" | sed 's/^/- [ ] Review /; s/$/ changes/'
        echo
        echo "### Why this matters"
        echo "External installers (ohmyzsh, rustup, bun, etc.) could be compromised. While auto-updating keeps users unblocked, a quick review ensures we're not distributing malicious code."
        echo
        echo "---"
        echo "Auto-generated by checksum-monitor-local on $(hostname -s)"
    } >"$body_file"

    existing="$(gh issue list --repo "$repo_slug" --state open \
        --label security --label checksum-update \
        --search "External installer checksums" \
        --json number -q '.[0].number' 2>>"$LOG_FILE" || true)"
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        gh issue comment "$existing" --repo "$repo_slug" \
            --body "### Additional changes detected

$(command cat "$body_file")" >>"$LOG_FILE" 2>&1 \
            && log "commented on existing issue #$existing"
    else
        gh issue create --repo "$repo_slug" \
            --title "🔐 External installer checksums updated - review recommended" \
            --label security --label checksum-update \
            --body-file "$body_file" >>"$LOG_FILE" 2>&1 \
            && log "created external-change review issue"
    fi
fi

# Healthy run: clear the consecutive fail-closed streak
printf '0\n' > "$FAIL_STREAK_FILE" 2>/dev/null || true

log "summary: result=ok drift_detected=$drift_detected drift_fixed=$drift_fixed mismatches=$mismatches errors=$errors skipped=$skipped trusted=${trusted_changed:-none} external=${external_changed:-none} committed=$committed"
