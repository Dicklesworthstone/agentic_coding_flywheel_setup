#!/usr/bin/env bash
# ============================================================
# ACFS Bootstrap - Offline Simulation Test
#
# Validates the curl|bash bootstrap path from an explicitly selected local
# archive. The archive path is authoritative and bootstrap does not resolve or
# download a repository ref before consuming it.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log() {
  echo "[bootstrap-offline] $*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd tar
require_cmd bash
require_cmd grep
require_cmd cp
require_cmd mktemp

# This test exercises install.sh's archive bootstrap which uses GNU tar flags
# like --wildcards/--strip-components/--wildcards-match-slash.
# On macOS (BSD tar), these flags are not available; skip locally.
# Capture first: under pipefail, `tar --help | grep -q` fails whenever grep exits
# early and tar takes SIGPIPE, which silently skipped this whole check.
tar_help="$(tar --help 2>/dev/null || true)"
if [[ "$tar_help" != *--wildcards* ]]; then
  log "Skipping offline bootstrap checks: GNU tar required (missing --wildcards)"
  exit 0
fi

create_archive() {
  local archive_path="$1"
  log "Creating archive: $archive_path"
  # Portable archive creation (GNU tar and BSD tar compatible):
  # create a staging dir with an explicit top-level folder, then tar it.
  local stage_dir
  stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-offline-stage.XXXXXX")"

  mkdir -p "$stage_dir/acfs-offline/packages"

  # Mirror the real release tarball, which the bootstrap filters to */scripts/**:
  # every file in scripts/generated/internal_checksums.sh (templates, completions,
  # services-setup.sh, ...) must be present or the integrity contract refuses it.
  # A hand-picked subset silently drifted each time the ledger grew.
  cp -R "$REPO_ROOT/scripts" "$stage_dir/acfs-offline/scripts"
  cp -R "$REPO_ROOT/packages/onboard" "$stage_dir/acfs-offline/packages/onboard"
  # `acfs agent-readiness` sources are the only extracted packages/manifest files.
  mkdir -p "$stage_dir/acfs-offline/packages/manifest/src"
  cp "$REPO_ROOT"/packages/manifest/src/{agent-readiness-audit,agent-profile-rehearsal,binary-architecture}.ts \
    "$stage_dir/acfs-offline/packages/manifest/src/"

  cp -R "$REPO_ROOT/acfs" "$stage_dir/acfs-offline/acfs"
  # Bootstrap extracts and requires */install.sh alongside the runtime (fe0d314b).
  cp "$REPO_ROOT/install.sh" "$stage_dir/acfs-offline/install.sh"
  cp "$REPO_ROOT/checksums.yaml" "$stage_dir/acfs-offline/checksums.yaml"
  cp "$REPO_ROOT/acfs.manifest.yaml" "$stage_dir/acfs-offline/acfs.manifest.yaml"
  cp "$REPO_ROOT/VERSION" "$stage_dir/acfs-offline/VERSION"

  tar -czf "$archive_path" -C "$stage_dir" acfs-offline
}

create_bad_archive() {
  local good_archive="$1"
  local bad_archive="$2"
  local bad_dir
  bad_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-offline-bad.XXXXXX")"

  log "Creating bad archive: $bad_archive"
  tar -xzf "$good_archive" -C "$bad_dir"
  printf '\n# bootstrap mismatch\n' >> "$bad_dir/acfs-offline/acfs.manifest.yaml"
  tar -czf "$bad_archive" -C "$bad_dir" acfs-offline
}

run_bootstrap() {
  local archive_path="$1"
  local label="$2"
  local expect_failure="${3:-false}"

  log "$label: running bootstrap (archive=$archive_path)"
  if [[ "$expect_failure" == "true" ]]; then
    set +e
    local output
    output="$(ACFS_TEST_MODE=1 ACFS_TEST_ARCHIVE=/should-be-ignored bash -lc "cat '$REPO_ROOT/install.sh' | bash -s -- --bootstrap-archive '$archive_path' --list-modules" 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
      echo "$output" >&2
      echo "ERROR: expected bootstrap failure for $label" >&2
      exit 1
    fi

    # The tampered manifest must be refused by name. The internal-checksum ledger
    # (which covers acfs.manifest.yaml) now runs before the manifest-index check,
    # so either refusal is the manifest being rejected, not some unrelated error.
    grep -qE "INTEGRITY: acfs\.manifest\.yaml checksum mismatch|Bootstrap mismatch: manifest and manifest index disagree" <<<"$output" || {
      echo "$output" >&2
      echo "ERROR: expected bootstrap mismatch message for $label" >&2
      exit 1
    }

    log "$label: bootstrap failure detected as expected"
    return 0
  fi

  set +e
  local output
  output="$(ACFS_TEST_MODE=1 ACFS_TEST_ARCHIVE=/should-be-ignored bash -lc "cat '$REPO_ROOT/install.sh' | bash -s -- --bootstrap-archive '$archive_path' --list-modules" 2>&1)"
  local status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    echo "$output" >&2
    echo "ERROR: bootstrap command failed for $label (exit $status)" >&2
    exit 1
  fi

  echo "$output" | grep -q "Bootstrap archive ready" || {
    echo "$output" >&2
    echo "ERROR: bootstrap archive not reported ready for $label" >&2
    exit 1
  }

  echo "$output" | grep -q "Available ACFS Modules" || {
    echo "$output" >&2
    echo "ERROR: list-modules output missing for $label" >&2
    exit 1
  }

  log "$label: bootstrap success"
}

main() {
  local good_archive
  local bad_archive

  # mktemp portability: BSD mktemp requires Xs at the end of the template
  good_archive="$(mktemp "${TMPDIR:-/tmp}/acfs-offline-archive.XXXXXX")"
  bad_archive="$(mktemp "${TMPDIR:-/tmp}/acfs-offline-archive-bad.XXXXXX")"

  create_archive "$good_archive"
  run_bootstrap "$good_archive" "happy-path"

  create_bad_archive "$good_archive" "$bad_archive"
  run_bootstrap "$bad_archive" "mismatch-path" "true"

  log "offline bootstrap checks complete"
}

main "$@"
