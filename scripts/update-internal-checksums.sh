#!/usr/bin/env bash
# ============================================================
# ACFS Internal Checksum Updater
#
# Regenerates scripts/generated/internal_checksums.sh by
# computing fresh SHA-256 hashes for each tracked internal
# script.  Run this after editing any of those files to keep
# the integrity check in sync.
#
# Usage:
#   ./scripts/update-internal-checksums.sh          # update in-place
#   ./scripts/update-internal-checksums.sh --check  # exit 1 if stale
#
# Note: `bun run generate` (from packages/manifest) also
# regenerates this file alongside all other generated artefacts.
# Use that command when the full set of generated files needs
# refreshing.  Use this script for a quick, bun-free update of
# just the internal checksums.
# ============================================================
set -euo pipefail

# ── paths ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_FILE="${PROJECT_ROOT}/scripts/generated/internal_checksums.sh"

# ── list of files to checksum (must mirror generate.ts) ────
INTERNAL_SCRIPTS=(
  "scripts/lib/security.sh"
  "scripts/lib/agents.sh"
  "scripts/lib/update.sh"
  "scripts/lib/doctor.sh"
  "scripts/lib/install_helpers.sh"
  "scripts/lib/logging.sh"
  "scripts/lib/state.sh"
  "scripts/lib/session.sh"
  "scripts/lib/os_detect.sh"
  "scripts/lib/errors.sh"
  "scripts/lib/user.sh"
  "scripts/lib/tools.sh"
  "scripts/lib/export-config.sh"
  "scripts/acfs-global"
  "scripts/acfs-update"
)

# ── parse args ──────────────────────────────────────────────
CHECK_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# ── build the new file content ──────────────────────────────
build_content() {
  local count=${#INTERNAL_SCRIPTS[@]}

  cat <<'HEADER'
#!/usr/bin/env bash
# shellcheck disable=SC2034
# ============================================================
# AUTO-GENERATED internal script checksums - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================
# SHA256 checksums for critical internal scripts (bd-3tpl).
# Used by check-manifest-drift.sh to detect unauthorized changes.

HEADER

  echo "declare -gA ACFS_INTERNAL_CHECKSUMS=("

  local fail=0
  for rel_path in "${INTERNAL_SCRIPTS[@]}"; do
    local abs_path="${PROJECT_ROOT}/${rel_path}"
    if [[ -f "$abs_path" ]]; then
      local hash
      hash=$(sha256sum "$abs_path" | cut -d' ' -f1)
      printf '  [%s]="%s"\n' "$rel_path" "$hash"
    else
      printf '  # MISSING: %s\n' "$rel_path" >&2
      fail=1
    fi
  done

  echo ")"
  echo ""
  echo "ACFS_INTERNAL_CHECKSUMS_COUNT=${count}"
  # This variable is evaluated when internal_checksums.sh is sourced at
  # install-time and records when the checksums were last regenerated.
  # shellcheck disable=SC2016
  echo 'ACFS_INTERNAL_CHECKSUMS_GENERATED="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"'

  return $fail
}

# ── --check mode: compare without writing ──────────────────
if [[ "$CHECK_ONLY" == true ]]; then
  new_content=$(build_content)
  existing_content=$(cat "$OUTPUT_FILE" 2>/dev/null || true)

  # Strip the generated timestamp line before comparing so a
  # difference in generation time doesn't cause a false mismatch.
  strip_ts() { grep -v '^ACFS_INTERNAL_CHECKSUMS_GENERATED=' || true; }

  if diff <(echo "$new_content" | strip_ts) <(echo "$existing_content" | strip_ts) > /dev/null 2>&1; then
    echo "✓ internal_checksums.sh is up to date"
    exit 0
  else
    echo "✗ internal_checksums.sh is stale — run ./scripts/update-internal-checksums.sh to fix" >&2
    exit 1
  fi
fi

# ── normal mode: write the updated file ────────────────────
new_content=$(build_content)
printf '%s\n' "$new_content" > "$OUTPUT_FILE"
echo "✓ Updated ${OUTPUT_FILE}"
