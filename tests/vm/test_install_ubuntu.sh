#!/usr/bin/env bash
# ============================================================
# ACFS Installer - Ubuntu Integration Test (Docker)
#
# Runs the full installer inside a fresh Ubuntu container image, then runs
# `acfs doctor` as the `ubuntu` user.
#
# Usage:
#   ./tests/vm/test_install_ubuntu.sh              # defaults to 24.04
#   ./tests/vm/test_install_ubuntu.sh --all        # run 22.04 + 24.04 + 26.04
#   ./tests/vm/test_install_ubuntu.sh --ubuntu 26.04
#   ./tests/vm/test_install_ubuntu.sh --mode safe
#   ./tests/vm/test_install_ubuntu.sh --interrupt-resume
#   ./tests/vm/test_install_ubuntu.sh --platform linux/arm64
#
# Requirements:
#   - docker (or compatible runtime that supports `docker run`)
#   - for a foreign --platform: binfmt/QEMU user emulation registered on the host
# ============================================================

set -euo pipefail

usage() {
  cat <<'EOF'
tests/vm/test_install_ubuntu.sh - ACFS installer integration test (Docker)

Usage:
  ./tests/vm/test_install_ubuntu.sh [options]

Options:
  --ubuntu <version>   Ubuntu tag (e.g. 22.04, 24.04, 26.04). Repeatable.
  --all                Run on the supported LTS releases: 22.04, 24.04, and 26.04.
  --mode <mode>        Install mode: vibe or safe (default: vibe).
  --strict             Enable strict installer mode (checksum mismatches fail).
  --interrupt-resume   Hang up the first install once cli_tools is checkpointed,
                       then require --resume to skip checkpointed phases and finish.
  --platform <p>       linux/amd64 or linux/arm64 (a foreign platform needs binfmt
                       emulation). Default: the host's native platform, pinned.
  --help               Show help.

Examples:
  ./tests/vm/test_install_ubuntu.sh
  ./tests/vm/test_install_ubuntu.sh --all
  ./tests/vm/test_install_ubuntu.sh --ubuntu 26.04
  ./tests/vm/test_install_ubuntu.sh --mode safe
  ./tests/vm/test_install_ubuntu.sh --interrupt-resume
  ./tests/vm/test_install_ubuntu.sh --platform linux/arm64
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found. Install Docker Desktop or docker engine." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

declare -a ubuntus=()
MODE="vibe"
STRICT=false
INTERRUPT_RESUME=false
PLATFORM=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ubuntu)
      ubuntus+=("${2:-}")
      shift 2
      ;;
    --all)
      ubuntus=("22.04" "24.04" "26.04")
      shift
      ;;
    --mode)
      MODE="${2:-}"
      case "$MODE" in
        vibe|safe) ;;
        *)
          echo "ERROR: --mode must be vibe or safe (got: '$MODE')" >&2
          exit 1
          ;;
      esac
      shift 2
      ;;
    --strict)
      STRICT=true
      shift
      ;;
    --interrupt-resume)
      INTERRUPT_RESUME=true
      shift
      ;;
    --platform)
      PLATFORM="${2:-}"
      if [[ ! "$PLATFORM" =~ ^linux/(amd64|arm64)$ ]]; then
        echo "ERROR: --platform must be linux/amd64 or linux/arm64 (got: '$PLATFORM')" >&2
        exit 1
      fi
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ${#ubuntus[@]} -eq 0 ]]; then
  ubuntus=("24.04")
fi

# Always pin the platform: a foreign-platform pull re-points the shared local
# ubuntu:<tag>, which would silently emulate a concurrent "native" run.
if [[ -z "$PLATFORM" ]]; then
  case "$(uname -m)" in
    x86_64|amd64) PLATFORM="linux/amd64" ;;
    aarch64|arm64) PLATFORM="linux/arm64" ;;
    *)
      echo "ERROR: unsupported host architecture $(uname -m); pass --platform" >&2
      exit 1
      ;;
  esac
fi

run_one() {
  local ubuntu_version="$1"
  local image="ubuntu:${ubuntu_version}"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local log_dir="${REPO_ROOT}/tests/logs/vm_test_${ubuntu_version}_${timestamp}"

  mkdir -p "$log_dir"

  echo "" >&2
  echo "============================================================" >&2
  local variant=""
  [[ "$INTERRUPT_RESUME" != "true" ]] || variant=", interrupt+resume"
  echo "[ACFS Test] Ubuntu ${ubuntu_version} (mode=${MODE}, platform=${PLATFORM}${variant})" >&2
  echo "Logs: ${log_dir}" >&2
  echo "============================================================" >&2

  docker pull --platform "$PLATFORM" "$image" >/dev/null

  docker run --rm --platform "$PLATFORM" \
    -e DEBIAN_FRONTEND=noninteractive \
    -e ACFS_TEST_MODE="$MODE" \
    -e ACFS_TEST_STRICT="$STRICT" \
    -e ACFS_TEST_INTERRUPT_RESUME="$INTERRUPT_RESUME" \
    -e ACFS_CHECKSUMS_REF="${ACFS_CHECKSUMS_REF:-}" \
    -e ACFS_REF="${ACFS_REF:-}" \
    -e ACFS_HOST_UID="$(id -u)" \
    -e ACFS_HOST_GID="$(id -g)" \
    -v "${REPO_ROOT}:/repo:rw" \
    "$image" bash /repo/tests/vm/test_runner.sh
}

for ubuntu_version in "${ubuntus[@]}"; do
  if [[ -z "$ubuntu_version" ]]; then
    echo "ERROR: --ubuntu requires a version (e.g. 24.04)" >&2
    exit 1
  fi
  run_one "$ubuntu_version"
done

echo "" >&2
echo "✅ All requested Ubuntu installer tests passed." >&2
