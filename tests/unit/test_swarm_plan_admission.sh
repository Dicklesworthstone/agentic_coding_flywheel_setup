#!/usr/bin/env bash
# Shell-suite entry point for real CLI admission and snapshot regression tests.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v jq >/dev/null
exec python3 -m unittest discover -s "$REPO_ROOT/tests/unit" -p 'test_swarm_plan_*.py' -v
