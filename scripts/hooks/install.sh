#!/usr/bin/env bash
# Install ACFS git hooks
#
# Usage: ./scripts/hooks/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "Installing ACFS git hooks..."

# Install pre-commit hook
cp "$SCRIPT_DIR/pre-commit" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"
echo "✅ Installed pre-commit hook"

echo ""
echo "Hooks installed. They will:"
echo "  - Auto-regenerate scripts/generated/ when manifest changes"
echo ""
echo "To bypass: git commit --no-verify"
echo "CI still enforces drift checks."
