#!/usr/bin/env bash
# Exercise the real setup entrypoint against controlled HTTP responses.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/test_claude_code_web_setup.py"
