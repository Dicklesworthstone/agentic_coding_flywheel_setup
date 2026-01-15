#!/usr/bin/env bash
set -e

# Mock logging to avoid sourcing dependencies
log_detail() { echo "LOG: $1"; }
log_warn() { echo "WARN: $1"; }

# The function mirrors the logic in scripts/lib/cli_tools.sh
_fetch_github_version() {
    local repo="$1"
    local strip_v="${2:-false}"
    local tag=""

    echo "Testing strategy 1 (HEAD request)..."
    local location_header
    # Added -w '%{redirect_url}' to debug what curl actually sees vs what grep finds
    # But sticking to the exact code in cli_tools.sh for fidelity:
    if location_header=$(curl -sI --max-time 10 "https://github.com/$repo/releases/latest" | grep -i "^location:" | head -n 1); then
        echo "Raw header found: '$location_header'"
        # Use awk to grab the URL (second field) and strip carriage returns
        local url
        url=$(echo "$location_header" | awk '{print $2}' | tr -d '\r')
        tag="${url##*/}"
        echo "Parsed tag: '$tag'"
    else
        echo "Strategy 1 failed (no location header)"
    fi

    # Fallback to GitHub API if HEAD failed or returned no tag
    if [[ -z "$tag" || "$tag" == http* ]]; then
        echo "Strategy 1 yielded empty tag, falling back to API..."
        local json
        if json=$(curl -s --max-time 10 "https://api.github.com/repos/$repo/releases/latest"); then
            if command -v jq &>/dev/null; then
                tag=$(echo "$json" | jq -r '.tag_name // empty')
            elif command -v python3 &>/dev/null; then
                tag=$(echo "$json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('tag_name', ''))" 2>/dev/null)
            else
                tag=$(echo "$json" | grep -o '"tag_name": *"[^"]*"' | head -n1 | cut -d'"' -f4)
            fi
        fi
    fi

    if [[ -z "$tag" ]]; then
        echo "No tag resolved from either strategy"
        return 1
    fi

    # Simulate success
    if [[ "$strip_v" == "true" ]]; then
        echo "${tag#v}"
    else
        echo "$tag"
    fi
}

echo "--- Test 1: lazygit (expecting ~v0.44.1) ---"
_fetch_github_version "jesseduffield/lazygit" true
echo ""

echo "--- Test 2: fzf (expecting ~0.55.0) ---"
_fetch_github_version "junegunn/fzf" false
