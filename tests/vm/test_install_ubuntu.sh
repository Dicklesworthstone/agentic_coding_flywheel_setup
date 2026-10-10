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
#     with the C (credentials) flag, so setuid sudo works inside the container
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
  --bootstrap-e2e      Instead of the full install, run the curl|bash bootstrap and
                       resume-after-failure E2E scripts, each in a fresh container.
  --help               Show help.

Examples:
  ./tests/vm/test_install_ubuntu.sh
  ./tests/vm/test_install_ubuntu.sh --all
  ./tests/vm/test_install_ubuntu.sh --ubuntu 26.04
  ./tests/vm/test_install_ubuntu.sh --mode safe
  ./tests/vm/test_install_ubuntu.sh --interrupt-resume
  ./tests/vm/test_install_ubuntu.sh --platform linux/arm64
  ./tests/vm/test_install_ubuntu.sh --bootstrap-e2e
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
BOOTSTRAP_E2E=false
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
    --bootstrap-e2e)
      BOOTSTRAP_E2E=true
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

# A binfmt handler without the C (credentials) flag runs setuid binaries
# unprivileged, so sudo inside an emulated container cannot elevate. The
# 2026-10-09 arm64 run on ts1 (flags POF) spent hours installing, then failed
# SLB, MDWB, SRPS and the passwordless-sudo smoke check on exactly that.
host_platform=""
case "$(uname -m)" in
  x86_64|amd64) host_platform="linux/amd64" ;;
  aarch64|arm64) host_platform="linux/arm64" ;;
esac
if [[ "$PLATFORM" != "$host_platform" && -d /proc/sys/fs/binfmt_misc ]]; then
  binfmt_handler="qemu-x86_64"
  [[ "$PLATFORM" == "linux/arm64" ]] && binfmt_handler="qemu-aarch64"
  binfmt_flags="$(sed -n 's/^flags: //p' "/proc/sys/fs/binfmt_misc/$binfmt_handler" 2>/dev/null || true)"
  if [[ "$binfmt_flags" != *C* ]]; then
    echo "ERROR: $PLATFORM emulation needs /proc/sys/fs/binfmt_misc/$binfmt_handler registered with the C (credentials) flag (found flags: '${binfmt_flags:-none}')." >&2
    echo "       Without it sudo cannot elevate inside the container, so the install cannot pass." >&2
    exit 1
  fi
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

# The real user path is curl|bash, and resume is how users recover from a
# dropped session. Before this flag only the (unused) Actions workflow ran
# these two scripts. Each gets a fresh container and a writable copy of the
# tree, so nothing root-owned lands in the host checkout.
run_bootstrap_e2e() {
  local ubuntu_version="$1"
  local image="ubuntu:${ubuntu_version}"
  local test_script=""

  docker pull --platform "$PLATFORM" "$image" >/dev/null
  for test_script in tests/e2e/test_curlbash_bootstrap.sh tests/e2e/test_resume_after_failure.sh; do
    echo "" >&2
    echo "[ACFS Test] Ubuntu ${ubuntu_version}: ${test_script} (platform=${PLATFORM})" >&2
    docker run --rm --platform "$PLATFORM" \
      -e DEBIAN_FRONTEND=noninteractive \
      -v "${REPO_ROOT}:/src:ro" \
      "$image" bash -c '
        set -euo pipefail
        apt-get update -qq >/dev/null
        apt-get install -y -qq sudo curl git ca-certificates jq unzip tar xz-utils gnupg python3 >/dev/null
        echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-acfs-e2e
        chmod 440 /etc/sudoers.d/90-acfs-e2e
        mkdir -p /repo
        tar -C /src --exclude=.git --exclude=node_modules -cf - . | tar -C /repo -xf -
        cd /repo
        bash "$1"
      ' _ "$test_script"
  done
}

for ubuntu_version in "${ubuntus[@]}"; do
  if [[ -z "$ubuntu_version" ]]; then
    echo "ERROR: --ubuntu requires a version (e.g. 24.04)" >&2
    exit 1
  fi
  if [[ "$BOOTSTRAP_E2E" == "true" ]]; then
    run_bootstrap_e2e "$ubuntu_version"
  else
    run_one "$ubuntu_version"
  fi
done

echo "" >&2
echo "✅ All requested Ubuntu installer tests passed." >&2
