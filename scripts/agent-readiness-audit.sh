#!/usr/bin/env bash
# agent-readiness-audit.sh - local ACFS agent CLI and CAAM account readiness audit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${ACFS_AGENT_READINESS_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Installed as ~/.acfs/scripts/ beside ~/.acfs/packages/manifest/src, so the
# same layout works from a checkout and from `acfs agent-readiness`.
BUN_BIN="$(command -v bun 2>/dev/null || true)"
if [[ -z "$BUN_BIN" && -x "${HOME:-}/.bun/bin/bun" ]]; then
    BUN_BIN="$HOME/.bun/bin/bun"
fi
if [[ -z "$BUN_BIN" ]]; then
    echo "agent-readiness-audit requires bun" >&2
    exit 127
fi

cd "$REPO_ROOT/packages/manifest"
# Keep the existing audit read-only by default. Rehearsal has a separate explicit
# selection/consent parser; --run alone never enables it on the ordinary audit.
if [[ "${1:-}" == "--rehearse" ]]; then
    shift
    exec "$BUN_BIN" run src/agent-profile-rehearsal.ts "$@"
fi
exec "$BUN_BIN" run src/agent-readiness-audit.ts "$@"
