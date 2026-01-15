#!/usr/bin/env bash
# ============================================================
# ACFS Installer - Ubuntu Integration Test (Docker)
#
# Runs the full installer inside a fresh Ubuntu container image, then runs
# `acfs doctor` as the `ubuntu` user.
#
# Usage:
#   ./tests/vm/test_install_ubuntu.sh              # defaults to 24.04
#   ./tests/vm/test_install_ubuntu.sh --all        # run 24.04 + 25.04
#   ./tests/vm/test_install_ubuntu.sh --ubuntu 25.04
#   ./tests/vm/test_install_ubuntu.sh --mode safe
#
# Requirements:
#   - docker (or compatible runtime that supports `docker run`)
# ============================================================

set -euo pipefail

usage() {
  cat <<'EOF'
tests/vm/test_install_ubuntu.sh - ACFS installer integration test (Docker)

Usage:
  ./tests/vm/test_install_ubuntu.sh [options]

Options:
  --ubuntu <version>   Ubuntu tag (e.g. 24.04, 25.04). Repeatable.
  --all                Run on 24.04 and 25.04.
  --mode <mode>        Install mode: vibe or safe (default: vibe).
  --help               Show help.

Examples:
  ./tests/vm/test_install_ubuntu.sh
  ./tests/vm/test_install_ubuntu.sh --all
  ./tests/vm/test_install_ubuntu.sh --ubuntu 25.04
  ./tests/vm/test_install_ubuntu.sh --mode safe
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
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ubuntu)
      ubuntus+=("${2:-}")
      shift 2
      ;;
    --all)
      ubuntus=("24.04" "25.04")
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

run_one() {
  local ubuntu_version="$1"
  local image="ubuntu:${ubuntu_version}"

  echo "" >&2
  echo "============================================================" >&2
  echo "[ACFS Test] Ubuntu ${ubuntu_version} (mode=${MODE})" >&2
  echo "============================================================" >&2

  docker pull "$image" >/dev/null

  docker run --rm -t \
    -e DEBIAN_FRONTEND=noninteractive \
    -e ACFS_TEST_MODE="$MODE" \
    -v "${REPO_ROOT}:/repo:ro" \
    "$image" bash -lc '
      set -euo pipefail

      apt-get update
      apt-get install -y sudo curl git ca-certificates jq unzip tar xz-utils gnupg

      bash /repo/tests/vm/bootstrap_offline_checks.sh
      bash /repo/tests/vm/selection_checks.sh

      cd /repo
      bash install.sh --yes --mode "${ACFS_TEST_MODE}"

      su - ubuntu -c "zsh -ic '\''acfs doctor'\''"
      su - ubuntu -c "zsh -ic '\''test -f ~/.acfs/VERSION'\''"
      su - ubuntu -c "zsh -ic '\''onboard --help >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''ntm --help >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''gh --version >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''jq --version >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''sg --version >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''git-lfs version >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''rsync --version >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''strace --version >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''command -v lsof >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''command -v dig >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''command -v nc >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''codex --version >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''gemini --version >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''claude --version >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''dcg --version >/dev/null'\''"
      su - ubuntu -c "zsh -ic '\''set -o pipefail; dcg doctor --format json 2>/dev/null | jq -e \".hook_registered == true\" >/dev/null || dcg doctor 2>/dev/null | grep -qi \"hook wiring.*OK\"'\''"
      su - ubuntu -c "zsh -ic '\''dcg test \"git reset --hard\" | grep -Eqi \"deny|block\"'\''"
      su - ubuntu -c "zsh -ic '\''dcg test \"git status\" | grep -Eqi \"allow\"'\''"
      su - ubuntu -c "bash -lc '\''/repo/tests/vm/resume_checks.sh'\''"
    '
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
