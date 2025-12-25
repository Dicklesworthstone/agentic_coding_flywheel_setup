#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Ensure logging functions available
ACFS_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    log_step() { echo "[*] $*"; }
    log_section() { echo ""; echo "=== $* ==="; }
    log_success() { echo "[OK] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "    $*"; }
fi

# Source install helpers (run_as_*_shell, selection helpers)
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh"
fi

# Source contract validation
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh"
fi

# Optional security verification for upstream installer scripts.
# Scripts that need it should call: acfs_security_init
ACFS_SECURITY_READY=false
acfs_security_init() {
    if [[ "${ACFS_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    local security_lib="$ACFS_GENERATED_SCRIPT_DIR/../lib/security.sh"
    if [[ ! -f "$security_lib" ]]; then
        log_error "Security library not found: $security_lib"
        return 1
    fi

    # Use ACFS_CHECKSUMS_YAML if set by install.sh bootstrap (overrides security.sh default)
    if [[ -n "${ACFS_CHECKSUMS_YAML:-}" ]]; then
        export CHECKSUMS_FILE="${ACFS_CHECKSUMS_YAML}"
    fi

    # shellcheck source=../lib/security.sh
    # shellcheck disable=SC1091  # runtime relative source
    source "$security_lib"
    load_checksums || { log_error "Failed to load checksums.yaml"; return 1; }
    ACFS_SECURITY_READY=true
    return 0
}

# Doctor checks generated from manifest
# Format: ID<TAB>DESCRIPTION<TAB>CHECK_COMMAND<TAB>REQUIRED/OPTIONAL
# Using tab delimiter to avoid conflicts with | in shell commands
# Commands are encoded (\n, \t, \\) and decoded via printf before execution

declare -a MANIFEST_CHECKS=(
    "base.system.1	Base packages + sane defaults	curl --version	required"
    "base.system.2	Base packages + sane defaults	git --version	required"
    "base.system.3	Base packages + sane defaults	jq --version	required"
    "base.system.4	Base packages + sane defaults	gpg --version	required"
    "users.ubuntu.1	Ensure ubuntu user + passwordless sudo + ssh keys	id ubuntu	required"
    "users.ubuntu.2	Ensure ubuntu user + passwordless sudo + ssh keys	sudo -n true	required"
    "base.filesystem.1	Create workspace and ACFS directories	test -d /data/projects	required"
    "base.filesystem.2	Create workspace and ACFS directories	test -d \"\${TARGET_HOME:-/home/ubuntu}/.acfs\"	required"
    "shell.zsh	Zsh shell package	zsh --version	required"
    "shell.omz.1	Oh My Zsh + Powerlevel10k + plugins + ACFS config	test -d ~/.oh-my-zsh	required"
    "shell.omz.2	Oh My Zsh + Powerlevel10k + plugins + ACFS config	test -f ~/.acfs/zsh/acfs.zshrc	required"
    "shell.omz.3	Oh My Zsh + Powerlevel10k + plugins + ACFS config	test -f ~/.p10k.zsh	required"
    "cli.modern.1	Modern CLI tools referenced by the zshrc intent	rg --version	required"
    "cli.modern.2	Modern CLI tools referenced by the zshrc intent	tmux -V	required"
    "cli.modern.3	Modern CLI tools referenced by the zshrc intent	fzf --version	required"
    "cli.modern.4	Modern CLI tools referenced by the zshrc intent	gh --version	required"
    "cli.modern.5	Modern CLI tools referenced by the zshrc intent	git-lfs version	required"
    "cli.modern.6	Modern CLI tools referenced by the zshrc intent	rsync --version	required"
    "cli.modern.7	Modern CLI tools referenced by the zshrc intent	strace --version	required"
    "cli.modern.8	Modern CLI tools referenced by the zshrc intent	command -v lsof	required"
    "cli.modern.9	Modern CLI tools referenced by the zshrc intent	command -v dig	required"
    "cli.modern.10	Modern CLI tools referenced by the zshrc intent	command -v nc	required"
    "cli.modern.11	Modern CLI tools referenced by the zshrc intent	command -v lsd || command -v eza	optional"
    "network.tailscale.1	Zero-config mesh VPN for secure remote VPS access	tailscale version	required"
    "network.tailscale.2	Zero-config mesh VPN for secure remote VPS access	systemctl is-enabled tailscaled	required"
    "lang.bun	Bun runtime for JS tooling and global CLIs	~/.bun/bin/bun --version	required"
    "lang.uv	uv Python tooling (fast venvs)	~/.local/bin/uv --version	required"
    "lang.rust.1	Rust nightly + cargo	~/.cargo/bin/cargo --version	required"
    "lang.rust.2	Rust nightly + cargo	~/.cargo/bin/rustup show | grep -q nightly	required"
    "lang.go	Go toolchain	go version	required"
    "lang.nvm	nvm + latest Node.js	export NVM_DIR=\"\$HOME/.nvm\"\\n[ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"\\nnode --version	required"
    "tools.atuin	Atuin shell history (Ctrl-R superpowers)	~/.atuin/bin/atuin --version	required"
    "tools.zoxide	Zoxide (better cd)	command -v zoxide	required"
    "tools.ast_grep	ast-grep (used by UBS for syntax-aware scanning)	sg --version	required"
    "agents.claude	Claude Code	claude --version || claude --help	required"
    "agents.codex	OpenAI Codex CLI	~/.local/bin/codex --version || ~/.local/bin/codex --help	required"
    "agents.gemini	Google Gemini CLI	~/.local/bin/gemini --version || ~/.local/bin/gemini --help	required"
    "tools.vault	HashiCorp Vault CLI	vault --version	required"
    "db.postgres18.1	PostgreSQL 18	psql --version	required"
    "db.postgres18.2	PostgreSQL 18	systemctl status postgresql --no-pager	optional"
    "cloud.wrangler	Cloudflare Wrangler CLI	wrangler --version	required"
    "cloud.supabase	Supabase CLI	supabase --version	required"
    "cloud.convex	Convex CLI	convex --version	required"
    "cloud.vercel	Vercel CLI	vercel --version	required"
    "stack.ntm	Named tmux manager (agent cockpit)	ntm --help	required"
    "stack.mcp_agent_mail	Like gmail for coding agents; MCP HTTP server + token; installs beads tools	command -v am	required"
    "stack.ultimate_bug_scanner.1	UBS bug scanning (easy-mode)	ubs --help	required"
    "stack.ultimate_bug_scanner.2	UBS bug scanning (easy-mode)	ubs doctor	optional"
    "stack.beads_viewer	bv TUI for Beads tasks	bv --help || bv --version	required"
    "stack.cass	Unified search across agent session history	cass --help || cass --version	required"
    "stack.cm.1	Procedural memory for agents (cass-memory)	cm --version	required"
    "stack.cm.2	Procedural memory for agents (cass-memory)	cm doctor --json	optional"
    "stack.caam	Instant auth switching for agent CLIs	caam status || caam --help	required"
    "stack.slb	Two-person rule for dangerous commands (optional guardrails)	export PATH=\"\$HOME/go/bin:\$PATH\" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1	required"
    "acfs.workspace.1	Agent workspace with tmux session and project folder	test -d /data/projects/my_first_project	required"
    "acfs.workspace.2	Agent workspace with tmux session and project folder	grep -q \"alias agents=\" ~/.zshrc.local || grep -q \"alias agents=\" ~/.zshrc	required"
    "acfs.onboard	Onboarding TUI tutorial	onboard --help || command -v onboard	required"
    "acfs.doctor	ACFS doctor command for health checks	acfs doctor --help || command -v acfs	required"
)

# Run all manifest checks
run_manifest_checks() {
    local passed=0
    local failed=0
    local skipped=0

    for check in "${MANIFEST_CHECKS[@]}"; do
        # Use tab as delimiter (safe - won't appear in commands)
        IFS=$'\t' read -r id desc cmd optional <<< "$check"
        cmd="$(printf '%b' "$cmd")"
        
        if bash -o pipefail -c "$cmd" &>/dev/null; then
            echo -e "\033[0;32m[ok]\033[0m $id - $desc"
            ((passed += 1))
        elif [[ "$optional" == "optional" ]]; then
            echo -e "\033[0;33m[skip]\033[0m $id - $desc"
            ((skipped += 1))
        else
            echo -e "\033[0;31m[fail]\033[0m $id - $desc"
            ((failed += 1))
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
