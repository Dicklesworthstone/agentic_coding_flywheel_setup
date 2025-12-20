#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Ensure logging functions available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$SCRIPT_DIR/../lib/logging.sh"
fi

# Doctor checks generated from manifest
# Format: ID|DESCRIPTION|CHECK_COMMAND

declare -a MANIFEST_CHECKS=(
    "base.system.1|Base packages + sane defaults|curl --version|required"
    "base.system.2|Base packages + sane defaults|git --version|required"
    "base.system.3|Base packages + sane defaults|jq --version|required"
    "users.ubuntu.1|Ensure ubuntu user + passwordless sudo + ssh keys|id ubuntu|required"
    "users.ubuntu.2|Ensure ubuntu user + passwordless sudo + ssh keys|sudo -n true|required"
    "shell.zsh.1|Zsh + Oh My Zsh + Powerlevel10k + plugins + canonical ACFS zshrc|zsh --version|required"
    "shell.zsh.2|Zsh + Oh My Zsh + Powerlevel10k + plugins + canonical ACFS zshrc|test -f ~/.acfs/zsh/acfs.zshrc|required"
    "cli.modern.1|Modern CLI tools referenced by the zshrc intent|rg --version|required"
    "cli.modern.2|Modern CLI tools referenced by the zshrc intent|tmux -V|required"
    "cli.modern.3|Modern CLI tools referenced by the zshrc intent|fzf --version|required"
    "cli.modern.4|Modern CLI tools referenced by the zshrc intent|command -v lsd || command -v eza|optional"
    "lang.bun|Bun runtime for JS tooling and global CLIs|~/.bun/bin/bun --version|required"
    "lang.uv|uv Python tooling (fast venvs)|~/.local/bin/uv --version|required"
    "lang.rust|Rust + cargo|~/.cargo/bin/cargo --version|required"
    "lang.go|Go toolchain|go version|required"
    "tools.atuin|Atuin shell history (Ctrl-R superpowers)|~/.atuin/bin/atuin --version|required"
    "tools.zoxide|Zoxide (better cd)|command -v zoxide|required"
    "tools.ast_grep|ast-grep (used by UBS for syntax-aware scanning)|sg --version|required"
    "tools.vault|HashiCorp Vault CLI|vault --version|required"
    "db.postgres18.1|PostgreSQL 18|psql --version|required"
    "db.postgres18.2|PostgreSQL 18|systemctl status postgresql --no-pager|optional"
    "cloud.wrangler|Cloudflare Wrangler CLI|wrangler --version|required"
    "cloud.supabase|Supabase CLI|supabase --version|required"
    "cloud.vercel|Vercel CLI|vercel --version|required"
    "agents.claude|Claude Code|claude --version || claude --help|required"
    "agents.codex|OpenAI Codex CLI|codex --version || codex --help|required"
    "agents.gemini|Google Gemini CLI|gemini --version || gemini --help|required"
    "stack.ntm|Named tmux manager (agent cockpit)|ntm --help|required"
    "stack.mcp_agent_mail.1|Like gmail for coding agents; MCP HTTP server + token; installs beads tools|command -v am|required"
    "stack.mcp_agent_mail.2|Like gmail for coding agents; MCP HTTP server + token; installs beads tools|curl -fsS http://127.0.0.1:8765/health|optional"
    "stack.ultimate_bug_scanner.1|UBS bug scanning (easy-mode)|ubs --help|required"
    "stack.ultimate_bug_scanner.2|UBS bug scanning (easy-mode)|ubs doctor|optional"
    "stack.beads_viewer|bv TUI for Beads tasks|bv --help || bv --version|required"
    "stack.cass|Unified search across agent session history|cass --help || cass --version|required"
    "stack.cm.1|Procedural memory for agents (cass-memory)|cm --version|required"
    "stack.cm.2|Procedural memory for agents (cass-memory)|cm doctor --json|optional"
    "stack.caam|Instant auth switching for agent CLIs|caam status || caam --help|required"
    "stack.slb|Two-person rule for dangerous commands (optional guardrails)|slb --help|required"
    "acfs.onboard|Onboarding TUI tutorial|onboard --help || command -v onboard|required"
    "acfs.doctor|ACFS doctor command for health checks|acfs doctor --help || command -v acfs|required"
)

# Run all manifest checks
run_manifest_checks() {
    local passed=0
    local failed=0
    local skipped=0

    for check in "${MANIFEST_CHECKS[@]}"; do
        IFS="|" read -r id desc cmd optional <<< "$check"
        
        if eval "$cmd" &>/dev/null; then
            echo -e "\033[0;32m[ok]\033[0m $id - $desc"
            ((passed++))
        elif [[ "$optional" == "optional" ]]; then
            echo -e "\033[0;33m[skip]\033[0m $id - $desc"
            ((skipped++))
        else
            echo -e "\033[0;31m[fail]\033[0m $id - $desc"
            ((failed++))
        fi
    done

    echo ""
    echo "Passed: $passed, Failed: $failed, Skipped: $skipped"
    [[ $failed -eq 0 ]]
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_manifest_checks
fi
