#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Ensure logging functions available
ACFS_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# When running a generated installer directly (not sourced by install.sh),
# set sane defaults and derive ACFS paths from the script location so
# contract validation passes and local assets are discoverable.
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    # Match install.sh defaults
    if [[ -z "${TARGET_USER:-}" ]]; then
        if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
            _ACFS_DETECTED_USER="ubuntu"
        else
            _ACFS_DETECTED_USER="${SUDO_USER:-$(whoami)}"
        fi
        TARGET_USER="$_ACFS_DETECTED_USER"
    fi
    unset _ACFS_DETECTED_USER
    MODE="${MODE:-vibe}"

    if [[ -z "${TARGET_HOME:-}" ]]; then
        if [[ "${TARGET_USER}" == "root" ]]; then
            TARGET_HOME="/root"
        elif [[ "$(whoami 2>/dev/null || true)" == "${TARGET_USER}" ]]; then
            TARGET_HOME="${HOME}"
        else
            TARGET_HOME="/home/${TARGET_USER}"
        fi
    fi

    # Derive "bootstrap" paths from the repo layout (scripts/generated/.. -> repo root).
    if [[ -z "${ACFS_BOOTSTRAP_DIR:-}" ]]; then
        ACFS_BOOTSTRAP_DIR="$(cd "$ACFS_GENERATED_SCRIPT_DIR/../.." && pwd)"
    fi

    ACFS_LIB_DIR="${ACFS_LIB_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/lib}"
    ACFS_GENERATED_DIR="${ACFS_GENERATED_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/generated}"
    ACFS_ASSETS_DIR="${ACFS_ASSETS_DIR:-$ACFS_BOOTSTRAP_DIR/acfs}"
    ACFS_CHECKSUMS_YAML="${ACFS_CHECKSUMS_YAML:-$ACFS_BOOTSTRAP_DIR/checksums.yaml}"
    ACFS_MANIFEST_YAML="${ACFS_MANIFEST_YAML:-$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml}"

    export TARGET_USER TARGET_HOME MODE
    export ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML
fi
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    # Progress/status output should go to stderr so stdout stays clean for piping.
    log_step() { echo "[*] $*" >&2; }
    log_section() { echo "" >&2; echo "=== $* ===" >&2; }
    log_success() { echo "[OK] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "    $*" >&2; }
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
    if [[ "${ACFS_SECURITY_READY}" = "true" ]]; then
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
# Format: ID<TAB>DESCRIPTION<TAB>CHECK_COMMAND<TAB>REQUIRED/OPTIONAL<TAB>RUN_AS
# Using tab delimiter to avoid conflicts with | in shell commands
# Commands are encoded (\n, \t, \\) and decoded via printf before execution

declare -a MANIFEST_CHECKS=(
    "base.system.1	Base packages + sane defaults	curl --version	required	root"
    "base.system.2	Base packages + sane defaults	git --version	required	root"
    "base.system.3	Base packages + sane defaults	jq --version	required	root"
    "base.system.4	Base packages + sane defaults	gpg --version	required	root"
    "users.ubuntu.1	Ensure target user + passwordless sudo + ssh keys	id \"\${TARGET_USER:-ubuntu}\"	required	root"
    "users.ubuntu.2	Ensure target user + passwordless sudo + ssh keys	[[ \"\${MODE:-vibe}\" != \"vibe\" ]] || runuser -u \"\${TARGET_USER:-ubuntu}\" -- sudo -n true	required	root"
    "base.filesystem.1	Create workspace and ACFS directories	test -d /data/projects	required	root"
    "base.filesystem.2	Create workspace and ACFS directories	test -f /data/projects/AGENTS.md	required	root"
    "base.filesystem.3	Create workspace and ACFS directories	test -d \"\${TARGET_HOME:-/home/ubuntu}/.acfs\"	required	root"
    "shell.zsh	Zsh shell package	zsh --version	required	root"
    "shell.omz.1	Oh My Zsh + Powerlevel10k + plugins + ACFS config	test -d ~/.oh-my-zsh	required	target_user"
    "shell.omz.2	Oh My Zsh + Powerlevel10k + plugins + ACFS config	test -f ~/.acfs/zsh/acfs.zshrc	required	target_user"
    "shell.omz.3	Oh My Zsh + Powerlevel10k + plugins + ACFS config	test -f ~/.p10k.zsh	required	target_user"
    "cli.modern.1	Modern CLI tools referenced by the zshrc intent	rg --version	required	root"
    "cli.modern.2	Modern CLI tools referenced by the zshrc intent	tmux -V	required	root"
    "cli.modern.3	Modern CLI tools referenced by the zshrc intent	fzf --version	required	root"
    "cli.modern.4	Modern CLI tools referenced by the zshrc intent	gh --version	required	root"
    "cli.modern.5	Modern CLI tools referenced by the zshrc intent	git-lfs version	required	root"
    "cli.modern.6	Modern CLI tools referenced by the zshrc intent	rsync --version	required	root"
    "cli.modern.7	Modern CLI tools referenced by the zshrc intent	strace --version	required	root"
    "cli.modern.8	Modern CLI tools referenced by the zshrc intent	command -v lsof	required	root"
    "cli.modern.9	Modern CLI tools referenced by the zshrc intent	command -v dig	required	root"
    "cli.modern.10	Modern CLI tools referenced by the zshrc intent	command -v nc	required	root"
    "cli.modern.11	Modern CLI tools referenced by the zshrc intent	command -v lsd || command -v eza	optional	root"
    "tools.lazygit	Lazygit (apt or binary fallback)	lazygit --version	required	root"
    "tools.lazydocker	Lazydocker (binary install)	lazydocker --version	required	root"
    "network.tailscale.1	Zero-config mesh VPN for secure remote VPS access	tailscale version	required	root"
    "network.tailscale.2	Zero-config mesh VPN for secure remote VPS access	systemctl is-enabled tailscaled	required	root"
    "network.ssh_keepalive.1	Configure SSH server keepalive to prevent VPN/NAT disconnects	grep -E '^ClientAliveInterval[[:space:]]+60' /etc/ssh/sshd_config	optional	root"
    "network.ssh_keepalive.2	Configure SSH server keepalive to prevent VPN/NAT disconnects	grep -E '^ClientAliveCountMax[[:space:]]+3' /etc/ssh/sshd_config	optional	root"
    "lang.bun	Bun runtime for JS tooling and global CLIs	~/.bun/bin/bun --version	required	target_user"
    "lang.uv	uv Python tooling (fast venvs)	~/.local/bin/uv --version	required	target_user"
    "lang.rust.1	Rust nightly + cargo	~/.cargo/bin/cargo --version	required	target_user"
    "lang.rust.2	Rust nightly + cargo	~/.cargo/bin/rustup show | grep -q nightly	required	target_user"
    "lang.go	Go toolchain	go version	required	root"
    "lang.nvm	nvm + latest Node.js	export NVM_DIR=\"\$HOME/.nvm\"\\n[ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"\\nnode --version	required	target_user"
    "tools.atuin	Atuin shell history (Ctrl-R superpowers)	~/.atuin/bin/atuin --version	required	target_user"
    "tools.zoxide	Zoxide (better cd)	command -v zoxide	required	target_user"
    "tools.ast_grep	ast-grep (used by UBS for syntax-aware scanning)	sg --version	required	target_user"
    "agents.claude	Claude Code	~/.local/bin/claude --version || ~/.local/bin/claude --help	required	target_user"
    "agents.codex	OpenAI Codex CLI	~/.local/bin/codex --version || ~/.local/bin/codex --help	required	target_user"
    "agents.gemini	Google Gemini CLI	~/.local/bin/gemini --version || ~/.local/bin/gemini --help	required	target_user"
    "agents.opencode	OpenCode (multi-provider agent harness)	opencode --version || opencode --help	optional	target_user"
    "tools.vault	HashiCorp Vault CLI	vault --version	optional	root"
    "db.postgres18.1	PostgreSQL 18	psql --version	optional	root"
    "db.postgres18.2	PostgreSQL 18	systemctl status postgresql --no-pager	optional	root"
    "cloud.wrangler	Cloudflare Wrangler CLI	wrangler --version	optional	target_user"
    "cloud.supabase	Supabase CLI	supabase --version	optional	target_user"
    "cloud.vercel	Vercel CLI	vercel --version	optional	target_user"
    "stack.ntm	Named tmux manager (agent cockpit)	ntm --help	required	target_user"
    "stack.mcp_agent_mail.1	Like gmail for coding agents; MCP HTTP server + token; installs beads tools	command -v am	required	target_user"
    "stack.mcp_agent_mail.2	Like gmail for coding agents; MCP HTTP server + token; installs beads tools	runtime_dir=\"/run/user/\$(id -u)\"\\nif [[ -d \"\$runtime_dir\" ]]; then\\n  export XDG_RUNTIME_DIR=\"\$runtime_dir\"\\n  if [[ -S \"\$runtime_dir/bus\" ]]; then\\n    export DBUS_SESSION_BUS_ADDRESS=\"unix:path=\$runtime_dir/bus\"\\n  fi\\nfi\\nif command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then\\n  systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1 || exit 1\\nfi\\ncurl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null	required	target_user"
    "stack.meta_skill.1	Local-first knowledge management with hybrid semantic search (ms)	ms --version	required	target_user"
    "stack.meta_skill.2	Local-first knowledge management with hybrid semantic search (ms)	ms doctor --json	optional	target_user"
    "stack.automated_plan_reviser.1	Automated iterative spec refinement with extended AI reasoning (apr)	apr --help	optional	target_user"
    "stack.automated_plan_reviser.2	Automated iterative spec refinement with extended AI reasoning (apr)	apr --version	optional	target_user"
    "stack.jeffreysprompts.1	Curated battle-tested prompts for AI agents - browse and install as skills (jfp)	jfp --version	optional	target_user"
    "stack.jeffreysprompts.2	Curated battle-tested prompts for AI agents - browse and install as skills (jfp)	jfp doctor	optional	target_user"
    "stack.process_triage.1	Find and terminate stuck/zombie processes with intelligent scoring (pt)	pt --help	optional	target_user"
    "stack.process_triage.2	Find and terminate stuck/zombie processes with intelligent scoring (pt)	pt --version	optional	target_user"
    "stack.ultimate_bug_scanner.1	UBS bug scanning (easy-mode)	ubs --help	required	target_user"
    "stack.ultimate_bug_scanner.2	UBS bug scanning (easy-mode)	ubs doctor	optional	target_user"
    "stack.beads_rust.1	beads_rust (br) - Rust issue tracker with graph-aware dependencies	br --version	required	target_user"
    "stack.beads_rust.2	beads_rust (br) - Rust issue tracker with graph-aware dependencies	br list --json 2>/dev/null	optional	target_user"
    "stack.beads_viewer	bv TUI for Beads tasks	bv --help || bv --version	required	target_user"
    "stack.cass	Unified search across agent session history	cass --help || cass --version	required	target_user"
    "stack.cm.1	Procedural memory for agents (cass-memory)	cm --version	required	target_user"
    "stack.cm.2	Procedural memory for agents (cass-memory)	cm doctor --json	optional	target_user"
    "stack.caam	Instant auth switching for agent CLIs	caam status || caam --help	required	target_user"
    "stack.slb	Two-person rule for dangerous commands (optional guardrails)	export PATH=\"\$HOME/go/bin:\$PATH\" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1	optional	target_user"
    "stack.dcg.1	Destructive Command Guard - Claude Code hook blocking dangerous git/fs commands	dcg --version	required	target_user"
    "stack.dcg.2	Destructive Command Guard - Claude Code hook blocking dangerous git/fs commands	settings=\"\$HOME/.claude/settings.json\"\\nalt_settings=\"\$HOME/.config/claude/settings.json\"\\nif [[ -f \"\$settings\" ]]; then\\n  grep -q \"dcg\" \"\$settings\"\\nelif [[ -f \"\$alt_settings\" ]]; then\\n  grep -q \"dcg\" \"\$alt_settings\"\\nelse\\n  exit 1\\nfi	required	target_user"
    "stack.ru	Repo Updater - multi-repo sync + AI-driven commit automation	ru --version	required	target_user"
    "stack.brenner_bot	Brenner Bot - research session manager with hypothesis tracking	brenner --version || brenner --help	optional	target_user"
    "stack.rch	Remote Compilation Helper - transparent build offloading for AI coding agents	rch --version || rch --help	optional	target_user"
    "stack.wezterm_automata	WezTerm Automata (wa) - terminal automation and orchestration for AI agents	wa --version || wa --help	optional	target_user"
    "stack.srps.1	System Resource Protection Script - ananicy-cpp rules + TUI monitor for responsive dev workstations	sysmoni --version || sysmoni --help	optional	target_user"
    "stack.srps.2	System Resource Protection Script - ananicy-cpp rules + TUI monitor for responsive dev workstations	systemctl is-active ananicy-cpp	optional	target_user"
    "stack.frankensearch	Two-tier hybrid local search — lexical (BM25) + semantic retrieval with progressive delivery (fsfs)	fsfs version || fsfs --help	optional	target_user"
    "stack.storage_ballast_helper	Cross-platform disk-pressure defense for AI coding workloads (sbh)	sbh status || sbh --help	optional	target_user"
    "stack.cross_agent_session_resumer	Cross-provider AI coding session resumption — convert and resume sessions across providers (casr)	casr providers || casr --help	optional	target_user"
    "stack.doodlestein_self_releaser	Fallback release infrastructure — local builds via act when GitHub Actions is throttled (dsr)	dsr --version || dsr --help	optional	target_user"
    "stack.agent_settings_backup	Smart backup tool for AI coding agent configuration folders (asb)	asb version || asb help	optional	target_user"
    "stack.pcr	Post-compaction reminder hook for Claude Code that forces an AGENTS.md re-read	target_home=\"\${TARGET_HOME:-\$HOME}\"\\nhook_script=\"\$target_home/.local/bin/claude-post-compact-reminder\"\\nsettings=\"\$target_home/.claude/settings.json\"\\nalt_settings=\"\$target_home/.config/claude/settings.json\"\\n\\ntest -x \"\$hook_script\" || exit 1\\n\\nif [[ -f \"\$settings\" ]]; then\\n  grep -q \"claude-post-compact-reminder\" \"\$settings\"\\nelif [[ -f \"\$alt_settings\" ]]; then\\n  grep -q \"claude-post-compact-reminder\" \"\$alt_settings\"\\nelse\\n  exit 1\\nfi	optional	target_user"
    "utils.giil	Get Image from Internet Link - download cloud images for visual debugging	giil --help || giil --version	optional	target_user"
    "utils.csctf	Chat Shared Conversation to File - convert AI share links to Markdown/HTML	csctf --help || csctf --version	optional	target_user"
    "utils.xf	xf - Ultra-fast X/Twitter archive search with Tantivy	xf --help || xf --version	optional	target_user"
    "utils.toon_rust	toon_rust (tru) - Token-optimized notation format for LLM context efficiency	tru --help || tru --version	optional	target_user"
    "utils.rano	rano - Network observer for AI CLIs with request/response logging	rano --help || rano --version	optional	target_user"
    "utils.mdwb	markdown_web_browser (mdwb) - Convert websites to Markdown for LLM consumption	mdwb --help || mdwb --version	optional	target_user"
    "utils.s2p	source_to_prompt_tui (s2p) - Code to LLM prompt generator with TUI	s2p --help || s2p --version	optional	target_user"
    "utils.rust_proxy	rust_proxy - Transparent proxy routing for debugging network traffic	rust_proxy --help || rust_proxy --version	optional	target_user"
    "utils.aadc	aadc - ASCII diagram corrector for fixing malformed ASCII art	aadc --help || aadc --version	optional	target_user"
    "utils.caut	coding_agent_usage_tracker (caut) - LLM provider usage tracker	caut --help || caut --version	optional	target_user"
    "acfs.workspace.1	Agent workspace with tmux session and project folder	test -d /data/projects/my_first_project	required	target_user"
    "acfs.workspace.2	Agent workspace with tmux session and project folder	grep -q \"alias agents=\" ~/.zshrc.local || grep -q \"alias agents=\" ~/.zshrc	required	target_user"
    "acfs.onboard	Onboarding TUI tutorial	onboard --help || command -v onboard	required	target_user"
    "acfs.update	ACFS update command wrapper	command -v acfs-update	required	target_user"
    "acfs.nightly	Nightly auto-update timer (systemd)	systemctl --user is-enabled acfs-nightly-update.timer	optional	target_user"
    "acfs.doctor	ACFS doctor command for health checks	acfs doctor --help || command -v acfs	required	target_user"
)

# Execute a manifest check in the requested context without prompting.
run_manifest_check_command() {
    local run_as="$1"
    local cmd="$2"
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-}"
    local target_path=""

    if [[ -z "$target_home" ]]; then
        if [[ "$target_user" == "root" ]]; then
            target_home="/root"
        else
            target_home="/home/$target_user"
        fi
    fi

    target_path="$target_home/.local/bin:$target_home/.acfs/bin:$target_home/.bun/bin:$target_home/.cargo/bin:$target_home/.atuin/bin:$target_home/go/bin:${PATH:-/usr/local/bin:/usr/bin:/bin}"

    case "$run_as" in
        target_user)
            if [[ "$(id -un 2>/dev/null || true)" == "$target_user" ]]; then
                HOME="$target_home" PATH="$target_path" bash -o pipefail -c "$cmd"
                return $?
            fi
            if [[ $EUID -eq 0 ]] && command -v runuser >/dev/null 2>&1; then
                runuser -u "$target_user" -- env HOME="$target_home" PATH="$target_path" bash -o pipefail -c "$cmd"
                return $?
            fi
            if command -v sudo >/dev/null 2>&1; then
                sudo -n -u "$target_user" env HOME="$target_home" PATH="$target_path" bash -o pipefail -c "$cmd"
                return $?
            fi
            return 1
            ;;
        root)
            if [[ $EUID -eq 0 ]]; then
                bash -o pipefail -c "$cmd"
                return $?
            fi
            if command -v sudo >/dev/null 2>&1; then
                sudo -n env PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}" bash -o pipefail -c "$cmd"
                return $?
            fi
            return 1
            ;;
        current|*)
            bash -o pipefail -c "$cmd"
            ;;
    esac
}

# Run all manifest checks
run_manifest_checks() {
    local passed=0
    local failed=0
    local skipped=0

    for check in "${MANIFEST_CHECKS[@]}"; do
        # Use tab as delimiter (safe - won't appear in commands)
        IFS=$'\t' read -r id desc cmd optional run_as <<< "$check"
        cmd="$(printf '%b' "$cmd")"
        run_as="${run_as:-current}"
        
        if run_manifest_check_command "$run_as" "$cmd" &>/dev/null; then
            echo -e "${ACFS_GREEN-\033[0;32m}[ok]${ACFS_NC-\033[0m} $id - $desc"
            ((passed += 1))
        elif [[ "$optional" = "optional" ]]; then
            echo -e "${ACFS_YELLOW-\033[0;33m}[skip]${ACFS_NC-\033[0m} $id - $desc"
            ((skipped += 1))
        else
            echo -e "${ACFS_RED-\033[0;31m}[fail]${ACFS_NC-\033[0m} $id - $desc"
            ((failed += 1))
        fi
    done

    echo ""
    echo "Passed: $passed, Failed: $failed, Skipped: $skipped"
    [[ $failed -eq 0 ]]
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    run_manifest_checks
fi
