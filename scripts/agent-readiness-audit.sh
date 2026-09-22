#!/usr/bin/env bash
# agent-readiness-audit.sh - local ACFS agent CLI and CAAM account readiness audit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${ACFS_AGENT_READINESS_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if ! command -v bun >/dev/null 2>&1; then
    echo "agent-readiness-audit requires bun" >&2
    exit 127
fi

cd "$REPO_ROOT/packages/manifest"
# Keep the existing audit read-only by default. Rehearsal has a separate explicit
# selection/consent parser; --run alone never enables it on the ordinary audit.
if [[ "${1:-}" == "--rehearse" ]]; then
    shift
    exec bun run src/agent-profile-rehearsal.ts "$@"
fi
exec bun run src/agent-readiness-audit.ts "$@"
