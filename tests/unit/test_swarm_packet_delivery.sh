#!/usr/bin/env bash
# Run real packet-generation/delivery CLI fixtures; no model or live service calls.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 -m unittest discover -s "$REPO_ROOT/tests/unit" -p 'test_swarm_packet_delivery*.py' -v
