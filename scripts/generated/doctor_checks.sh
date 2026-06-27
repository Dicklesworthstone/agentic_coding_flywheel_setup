#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Resolve relative helper paths first.
ACFS_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure logging functions available
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

acfs_generated_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

acfs_generated_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(acfs_generated_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

acfs_generated_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(acfs_generated_system_binary_path getent 2>/dev/null || true)"
    if [[ -z "$user" ]]; then
        if [[ -n "$getent_bin" ]]; then
            while IFS= read -r passwd_line; do
                printf '%s\n' "$passwd_line"
                printed_any=true
            done < <("$getent_bin" passwd 2>/dev/null || true)
            if [[ "$printed_any" == true ]]; then
                return 0
            fi
        fi

        [[ -r /etc/passwd ]] || return 1
        while IFS= read -r passwd_line; do
            printf '%s\n' "$passwd_line"
        done < /etc/passwd
        return 0
    fi

    if [[ -n "$getent_bin" ]]; then
        passwd_entry="$("$getent_bin" passwd "$user" 2>/dev/null || true)"
    fi

    if [[ -z "$passwd_entry" ]] && [[ -r /etc/passwd ]]; then
        while IFS= read -r passwd_line; do
            [[ "${passwd_line%%:*}" == "$user" ]] || continue
            passwd_entry="$passwd_line"
            break
        done < /etc/passwd
    fi

    [[ -n "$passwd_entry" ]] || return 1
    printf '%s\n' "$passwd_entry"
}

acfs_generated_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    if [[ -n "$passwd_home" ]] && [[ "$passwd_home" == /* ]] && [[ "$passwd_home" != "/" ]]; then
        printf '%s\n' "${passwd_home%/}"
        return 0
    fi

    return 1
}

acfs_generated_target_user_exists() {
    local user="${1:-}"
    local id_bin=""

    [[ -n "$user" ]] || return 1
    id_bin="$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    [[ -n "$id_bin" ]] || return 1
    "$id_bin" "$user" >/dev/null 2>&1
}

acfs_generated_default_home_for_new_user() {
    local user="${1:-}"

    [[ -n "$user" ]] || return 1
    [[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    printf '/home/%s\n' "$user"
}

# When running a generated installer directly (not sourced by install.sh),
# set sane defaults and derive ACFS paths from the script location so
# contract validation passes and local assets are discoverable.
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    # Match install.sh defaults
    if [[ -z "${TARGET_USER:-}" ]]; then
        if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
            _ACFS_DETECTED_USER="ubuntu"
        else
            _ACFS_DETECTED_USER="${SUDO_USER:-}"
            if [[ -z "$_ACFS_DETECTED_USER" ]]; then
                _ACFS_DETECTED_USER="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
            fi
            if [[ -z "$_ACFS_DETECTED_USER" ]]; then
                log_error "Unable to resolve the current user for TARGET_USER"
                exit 1
            fi
        fi
        TARGET_USER="$_ACFS_DETECTED_USER"
    fi
    unset _ACFS_DETECTED_USER

    if declare -f _acfs_validate_target_user >/dev/null 2>&1; then
        _acfs_validate_target_user "${TARGET_USER}" "TARGET_USER" || exit 1
    elif [[ -z "${TARGET_USER:-}" ]] || [[ ! "${TARGET_USER}" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        log_error "Invalid TARGET_USER '${TARGET_USER:-<empty>}' (expected: lowercase user name like 'ubuntu')"
        exit 1
    fi

    MODE="${MODE:-vibe}"

    _ACFS_EXPLICIT_TARGET_HOME="${TARGET_HOME:-}"
    if [[ -n "$_ACFS_EXPLICIT_TARGET_HOME" ]]; then
        _ACFS_EXPLICIT_TARGET_HOME="${_ACFS_EXPLICIT_TARGET_HOME%/}"
    fi
    _ACFS_RESOLVED_TARGET_HOME=""
    if declare -f _acfs_resolve_target_home >/dev/null 2>&1; then
        _ACFS_RESOLVED_TARGET_HOME="$(_acfs_resolve_target_home "${TARGET_USER}" "$_ACFS_EXPLICIT_TARGET_HOME" || true)"
    else
        if [[ "${TARGET_USER}" == "root" ]]; then
            _ACFS_RESOLVED_TARGET_HOME="/root"
        else
            _acfs_passwd_entry="$(acfs_generated_getent_passwd_entry "${TARGET_USER}" 2>/dev/null || true)"
            if [[ -n "$_acfs_passwd_entry" ]]; then
                _ACFS_RESOLVED_TARGET_HOME="$(acfs_generated_passwd_home_from_entry "$_acfs_passwd_entry" 2>/dev/null || true)"
            else
                _acfs_current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
                _acfs_current_home="${HOME:-}"
                if [[ -n "$_acfs_current_home" ]]; then
                    _acfs_current_home="${_acfs_current_home%/}"
                fi
                if [[ "${_acfs_current_user:-}" == "${TARGET_USER}" ]] && [[ -n "$_acfs_current_home" ]] && [[ "$_acfs_current_home" == /* ]] && [[ "$_acfs_current_home" != "/" ]] && { [[ -z "$_ACFS_EXPLICIT_TARGET_HOME" ]] || [[ "$_acfs_current_home" == "$_ACFS_EXPLICIT_TARGET_HOME" ]]; }; then
                    _ACFS_RESOLVED_TARGET_HOME="$_acfs_current_home"
                fi
                unset _acfs_current_user _acfs_current_home
            fi
            unset _acfs_passwd_entry
        fi
    fi
    if [[ -z "$_ACFS_RESOLVED_TARGET_HOME" ]] && [[ $EUID -eq 0 ]] && ! acfs_generated_target_user_exists "${TARGET_USER}"; then
        if [[ -n "$_ACFS_EXPLICIT_TARGET_HOME" ]] && [[ "$_ACFS_EXPLICIT_TARGET_HOME" == /* ]] && [[ "$_ACFS_EXPLICIT_TARGET_HOME" != "/" ]]; then
            _ACFS_RESOLVED_TARGET_HOME="$_ACFS_EXPLICIT_TARGET_HOME"
        else
            _ACFS_RESOLVED_TARGET_HOME="$(acfs_generated_default_home_for_new_user "${TARGET_USER}" 2>/dev/null || true)"
        fi
    fi
    if [[ -n "$_ACFS_RESOLVED_TARGET_HOME" ]]; then
        TARGET_HOME="${_ACFS_RESOLVED_TARGET_HOME%/}"
    fi
    unset _ACFS_EXPLICIT_TARGET_HOME _ACFS_RESOLVED_TARGET_HOME

    if [[ -z "${TARGET_HOME:-}" ]] || [[ "${TARGET_HOME}" == "/" ]] || [[ "${TARGET_HOME}" != /* ]]; then
        log_error "Invalid TARGET_HOME for '${TARGET_USER}': ${TARGET_HOME:-<empty>} (must be an absolute path and cannot be '/')"
        exit 1
    fi

    # Derive "bootstrap" paths from the repo layout (scripts/generated/.. -> repo root).
    if [[ -z "${ACFS_BOOTSTRAP_DIR:-}" ]]; then
        ACFS_BOOTSTRAP_DIR="$(cd "$ACFS_GENERATED_SCRIPT_DIR/../.." && pwd)"
    fi

    ACFS_BIN_DIR="${ACFS_BIN_DIR:-$TARGET_HOME/.local/bin}"
    if [[ -z "${ACFS_BIN_DIR:-}" ]] || [[ "${ACFS_BIN_DIR}" == "/" ]] || [[ "${ACFS_BIN_DIR}" != /* ]]; then
        log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${ACFS_BIN_DIR:-<empty>})"
        exit 1
    fi
    ACFS_LIB_DIR="${ACFS_LIB_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/lib}"
    ACFS_GENERATED_DIR="${ACFS_GENERATED_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/generated}"
    ACFS_ASSETS_DIR="${ACFS_ASSETS_DIR:-$ACFS_BOOTSTRAP_DIR/acfs}"
    ACFS_CHECKSUMS_YAML="${ACFS_CHECKSUMS_YAML:-$ACFS_BOOTSTRAP_DIR/checksums.yaml}"
    ACFS_MANIFEST_YAML="${ACFS_MANIFEST_YAML:-$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml}"

    export TARGET_USER TARGET_HOME MODE ACFS_BIN_DIR
    export ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML

    # Defensive ownership repair (#306): when running as root, make sure the
    # target user owns their XDG bin dir before the user-space language
    # installers (uv/rust/bun) write into it. uv installs via an atomic
    # mktemp+rename inside ~/.local/bin, so a root-owned ~/.local/bin makes its
    # mktemp fail with "Permission denied (os error 13)" once the installer is
    # re-exec'd as the (non-root) target user. The ownership repair is
    # deliberately non-recursive: only the two directories themselves are
    # touched, never their contents.
    if [[ $EUID -eq 0 ]] && [[ -n "${TARGET_USER:-}" ]] && [[ "${TARGET_USER}" != "root" ]]; then
        # SECURITY: never chown through a symlink. If an untrusted target user
        # pre-staged ~/.local or ~/.local/bin as a symlink (e.g. -> /etc) before
        # the root install, a chown that follows it would transfer ownership of
        # the link target to them (local privilege escalation). chown -h /
        # nofollow is not portable, so refuse the repair entirely when either
        # path already exists as a symlink.
        if [[ -L "$TARGET_HOME/.local" ]] || [[ -L "$TARGET_HOME/.local/bin" ]]; then
            log_warn "Skipping ~/.local ownership repair: $TARGET_HOME/.local or .local/bin is a symlink (refusing to chown through it)"
        else
            _acfs_repair_mkdir="$(_acfs_system_binary_path mkdir 2>/dev/null || true)"
            _acfs_repair_chown="$(_acfs_system_binary_path chown 2>/dev/null || true)"
            if [[ -n "$_acfs_repair_mkdir" ]] && [[ -n "$_acfs_repair_chown" ]]; then
                if "$_acfs_repair_mkdir" -p "$TARGET_HOME/.local/bin" 2>/dev/null; then
                    "$_acfs_repair_chown" "${TARGET_USER}" "$TARGET_HOME/.local" "$TARGET_HOME/.local/bin" 2>/dev/null || true
                fi
            fi
            unset _acfs_repair_mkdir _acfs_repair_chown
        fi
    fi
fi

acfs_generated_ensure_selection() {
    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        local manifest_index="${ACFS_GENERATED_DIR:-$ACFS_GENERATED_SCRIPT_DIR}/manifest_index.sh"
        if [[ ! -f "$manifest_index" ]]; then
            log_error "Manifest index not found: $manifest_index"
            return 1
        fi
        source "$manifest_index"
        ACFS_MANIFEST_INDEX_LOADED=true
        export ACFS_MANIFEST_INDEX_LOADED
    fi

    if [[ "${ACFS_GENERATED_SELECTION_READY:-false}" != "true" ]]; then
        if ! declare -f acfs_resolve_selection >/dev/null 2>&1; then
            log_error "Install selection helper not loaded"
            return 1
        fi
        acfs_resolve_selection || return 1
        ACFS_GENERATED_SELECTION_READY=true
        export ACFS_GENERATED_SELECTION_READY
    fi

    return 0
}

acfs_generated_should_run_module() {
    local module_id="${1:-}"
    [[ -n "$module_id" ]] || return 1
    acfs_generated_ensure_selection || return 1
    should_run_module "$module_id"
}

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
    "base.filesystem.3	Create workspace and ACFS directories	# Resolve TARGET_HOME using generated helper functions. Doctor\\n# injects these helpers for manifest checks that reference\\n# acfs_generated_* functions, so this stays consistent with\\n# installer target-home resolution and avoids inherited HOME leaks.\\nexplicit_target_home=\"\${TARGET_HOME:-}\"\\nif [[ -n \"\$explicit_target_home\" ]]; then\\n  explicit_target_home=\"\${explicit_target_home%/}\"\\nfi\\ntarget_home=\"\"\\nif [[ \"\${TARGET_USER:-ubuntu}\" == \"root\" ]]; then\\n  target_home=\"/root\"\\nelse\\n  _acfs_passwd_entry=\"\$(acfs_generated_getent_passwd_entry \"\${TARGET_USER:-ubuntu}\" 2>/dev/null || true)\"\\n  if [[ -n \"\$_acfs_passwd_entry\" ]]; then\\n    target_home=\"\$(acfs_generated_passwd_home_from_entry \"\$_acfs_passwd_entry\" 2>/dev/null || true)\"\\n  else\\n    current_user=\"\$(acfs_generated_resolve_current_user 2>/dev/null || true)\"\\n    current_home=\"\${HOME:-}\"\\n    if [[ -n \"\$current_home\" ]]; then\\n      current_home=\"\${current_home%/}\"\\n    fi\\n    if [[ -n \"\$current_user\" ]] && [[ \"\$current_user\" == \"\${TARGET_USER:-ubuntu}\" ]] && [[ -n \"\$current_home\" ]] && [[ \"\$current_home\" == /* ]] && [[ \"\$current_home\" != \"/\" ]] && { [[ -z \"\$explicit_target_home\" ]] || [[ \"\$current_home\" == \"\$explicit_target_home\" ]]; }; then\\n      target_home=\"\$current_home\"\\n    fi\\n    unset current_user current_home\\n  fi\\n  unset _acfs_passwd_entry\\nfi\\nunset explicit_target_home\\nif [[ -z \"\$target_home\" ]] || [[ \"\$target_home\" == \"/\" ]] || [[ \"\$target_home\" != /* ]]; then\\n  echo \"ERROR: Unable to resolve TARGET_HOME for '\${TARGET_USER:-ubuntu}'; export TARGET_HOME explicitly (got: '\${target_home:-<empty>}')\" >&2\\n  exit 1\\nfi\\ntest -d \"\$target_home/.acfs\"	required	root"
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
    "lang.uv	uv Python tooling (fast venvs)	command -v uv >/dev/null 2>&1 && uv --version	required	target_user"
    "lang.rust.1	Rust nightly + cargo	~/.cargo/bin/cargo --version	required	target_user"
    "lang.rust.2	Rust nightly + cargo	~/.cargo/bin/rustup show | grep -q nightly	required	target_user"
    "lang.go	Go toolchain	go version	required	root"
    "lang.nvm	nvm + latest Node.js	export NVM_DIR=\"\$HOME/.nvm\"\\n[ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"\\nnode --version	required	target_user"
    "tools.atuin	Atuin CLI with guarded agent-safe shim	~/.atuin/bin/atuin --version	required	target_user"
    "tools.zoxide	Zoxide (better cd)	command -v zoxide	required	target_user"
    "tools.ast_grep	ast-grep (used by UBS for syntax-aware scanning)	sg --version	required	target_user"
    "agents.claude	Claude Code	target_bin=\"\${ACFS_BIN_DIR:-\$HOME/.local/bin}\"\\n\"\$target_bin/claude\" --version || \"\$target_bin/claude\" --help	required	target_user"
    "agents.codex	OpenAI Codex CLI	target_bin=\"\${ACFS_BIN_DIR:-\$HOME/.local/bin}\"\\n\"\$target_bin/codex\" --version || \"\$target_bin/codex\" --help	required	target_user"
    "agents.gemini	Legacy Google Gemini CLI (retired; not installed by default)	target_bin=\"\${ACFS_BIN_DIR:-\$HOME/.local/bin}\"\\n\"\$target_bin/gemini\" --version || \"\$target_bin/gemini\" --help	optional	target_user"
    "agents.antigravity	Antigravity CLI (agy) — Google, successor to the retired Gemini CLI	# acfs-summary: verify agy-locked launchers and pinned settings\\ntarget_bin=\"\${ACFS_BIN_DIR:-\$HOME/.local/bin}\"\\ntest -x \"\$target_bin/agy\"\\ntest -x \"\$target_bin/agy-locked\"\\ntest -x \"\$target_bin/gmi\"\\npython3 - <<'PY'\\nimport json\\nimport pathlib\\nimport sys\\n\\nsettings_path = pathlib.Path.home() / \".gemini\" / \"antigravity-cli\" / \"settings.json\"\\nhook_path = pathlib.Path.home() / \".gemini\" / \"config\" / \"hooks\" / \"dcg-antigravity-hook.py\"\\ntry:\\n    settings = json.loads(settings_path.read_text(encoding=\"utf-8\"))\\nexcept Exception as exc:\\n    print(f\"invalid or missing Antigravity settings: {settings_path}: {exc}\", file=sys.stderr)\\n    raise SystemExit(1)\\n\\nexpected = {\\n    \"model\": \"Gemini 3.1 Pro (High)\",\\n    \"toolPermission\": \"always-proceed\",\\n    \"artifactReviewPolicy\": \"always-proceed\",\\n    \"enableTelemetry\": False,\\n    \"enableTerminalSandbox\": False,\\n    \"allowNonWorkspaceAccess\": True,\\n    \"notifications\": False,\\n    \"showTips\": False,\\n    \"showFeedbackSurvey\": False,\\n    \"useG1Credits\": False,\\n    \"verbosity\": \"high\",\\n    \"runningLightSpeed\": \"medium\",\\n    \"colorScheme\": \"terminal\",\\n    \"editor\": \"auto\",\\n    \"altScreenMode\": \"never\",\\n}\\nfor key, value in expected.items():\\n    if settings.get(key) != value:\\n        print(f\"Antigravity setting {key} is {settings.get(key)!r}, expected {value!r}\", file=sys.stderr)\\n        raise SystemExit(1)\\nif not hook_path.is_file():\\n    print(f\"Antigravity dcg hook is missing: {hook_path}\", file=sys.stderr)\\n    raise SystemExit(1)\\nPY	required	target_user"
    "agents.opencode	OpenCode (multi-provider agent harness)	opencode --version || opencode --help	optional	target_user"
    "tools.vault	HashiCorp Vault CLI	vault --version	optional	root"
    "db.postgres18.1	PostgreSQL 18	psql --version	optional	root"
    "db.postgres18.2	PostgreSQL 18	systemctl status postgresql --no-pager	optional	root"
    "cloud.wrangler	Cloudflare Wrangler CLI	wrangler --version	optional	target_user"
    "cloud.supabase	Supabase CLI	supabase --version	optional	target_user"
    "cloud.vercel	Vercel CLI	vercel --version	optional	target_user"
    "stack.ntm	Named tmux manager (agent cockpit)	ntm --help	required	target_user"
    "stack.mcp_agent_mail.1	Like gmail for coding agents; MCP HTTP server + token; installs beads tools	command -v am	required	target_user"
    "stack.mcp_agent_mail.2	Like gmail for coding agents; MCP HTTP server + token; installs beads tools	agent_mail_service_curl() {\\n  local curl_bin=\"\"\\n  local candidate=\"\"\\n\\n  for candidate in /usr/bin/curl /bin/curl /usr/local/bin/curl /usr/local/sbin/curl /usr/sbin/curl /sbin/curl; do\\n    [[ -x \"\$candidate\" ]] || continue\\n    curl_bin=\"\$candidate\"\\n    break\\n  done\\n\\n  [[ -n \"\$curl_bin\" ]] || return 127\\n  \"\$curl_bin\" \"\$@\"\\n}\\n\\nagent_mail_readiness_ready() {\\n  local readiness_body=\"\"\\n  local readiness_url=\"\"\\n\\n  for readiness_url in \\\\\\n    http://127.0.0.1:8765/health/readiness \\\\\\n    http://127.0.0.1:8765/health\\n  do\\n    readiness_body=\"\$(agent_mail_service_curl -fsS --max-time 10 \"\$readiness_url\" 2>/dev/null)\" || continue\\n    if printf '%s\\\\n' \"\$readiness_body\" | grep -Eq '\"status\"[[:space:]]*:[[:space:]]*\"ready\"([[:space:]]*[,}])'; then\\n      return 0\\n    fi\\n  done\\n\\n  return 1\\n}\\n\\nruntime_dir=\"/run/user/\$(id -u)\"\\nif [[ -d \"\$runtime_dir\" ]]; then\\n  export XDG_RUNTIME_DIR=\"\$runtime_dir\"\\n  export DBUS_SESSION_BUS_ADDRESS=\"unix:path=\$runtime_dir/bus\"\\nfi\\nif command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then\\n  systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1 || exit 1\\nfi\\nagent_mail_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null\\nagent_mail_readiness_ready	required	target_user"
    "stack.meta_skill.1	Local-first knowledge management with hybrid semantic search (ms)	ms --version	required	target_user"
    "stack.meta_skill.2	Local-first knowledge management with hybrid semantic search (ms)	ms doctor	optional	target_user"
    "stack.automated_plan_reviser.1	Automated iterative spec refinement with extended AI reasoning (apr)	apr --help	optional	target_user"
    "stack.automated_plan_reviser.2	Automated iterative spec refinement with extended AI reasoning (apr)	apr --version	optional	target_user"
    "stack.jeffreysprompts.1	Curated battle-tested prompts for AI agents - browse and install as skills (jfp)	jfp --version	optional	target_user"
    "stack.jeffreysprompts.2	Curated battle-tested prompts for AI agents - browse and install as skills (jfp)	jfp doctor	optional	target_user"
    "stack.process_triage.1	Find and terminate stuck/zombie processes with intelligent scoring (pt)	pt --help	optional	target_user"
    "stack.process_triage.2	Find and terminate stuck/zombie processes with intelligent scoring (pt)	pt --version	optional	target_user"
    "stack.ultimate_bug_scanner.1	UBS bug scanning (easy-mode)	ubs --help	required	target_user"
    "stack.ultimate_bug_scanner.2	UBS bug scanning (easy-mode)	cd /tmp && ubs doctor	optional	target_user"
    "stack.beads_rust.1	beads_rust (br) - Rust issue tracker with graph-aware dependencies	br --version	required	target_user"
    "stack.beads_rust.2	beads_rust (br) - Rust issue tracker with graph-aware dependencies	br list --json 2>/dev/null	optional	target_user"
    "stack.beads_viewer	bv TUI for Beads tasks	bv --help || bv --version	required	target_user"
    "stack.cass	Unified search across agent session history	cass --help || cass --version	required	target_user"
    "stack.cm.1	Procedural memory for agents (cass-memory)	cm --version	required	target_user"
    "stack.cm.2	Procedural memory for agents (cass-memory)	cm doctor --json	optional	target_user"
    "stack.caam	Instant auth switching for agent CLIs	caam status || caam --help	required	target_user"
    "stack.slb	Two-person rule for dangerous commands (optional guardrails)	export PATH=\"\$HOME/go/bin:\$PATH\" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1	optional	target_user"
    "stack.dcg.1	Destructive Command Guard - Claude Code hook blocking dangerous git/fs commands	dcg --version	required	target_user"
    "stack.dcg.2	Destructive Command Guard - Claude Code hook blocking dangerous git/fs commands	claude_settings_has_command_hook() {\\n  local settings_file=\"\${1:-}\"\\n  local command_pattern=\"\${2:-}\"\\n  local jq_bin=\"\"\\n\\n  [[ -n \"\$settings_file\" && -n \"\$command_pattern\" ]] || return 1\\n  [[ -f \"\$settings_file\" ]] || return 1\\n  for jq_bin in /usr/bin/jq /bin/jq /usr/local/bin/jq /usr/local/sbin/jq /usr/sbin/jq /sbin/jq; do\\n    [[ -x \"\$jq_bin\" ]] && break\\n  done\\n  [[ -x \"\$jq_bin\" ]] || return 1\\n\\n  \"\$jq_bin\" -e --arg pattern \"\$command_pattern\" '\\n    def command_hook_matches:\\n      type == \"object\"\\n      and ((.type? // \"command\") == \"command\")\\n      and ((.command? // \"\") | strings | test(\$pattern));\\n    def event_entry_matches:\\n      if type == \"object\" and (.hooks? | type) == \"array\" then\\n        any(.hooks[]?; command_hook_matches)\\n      else\\n        command_hook_matches\\n      end;\\n    def hook_event_entries:\\n      if (.hooks? | type) == \"object\" then\\n        .hooks | to_entries[]? | .value | arrays | .[]?\\n      elif (.hooks? | type) == \"array\" then\\n        .hooks[]?\\n      else\\n        empty\\n      end;\\n    any(hook_event_entries; event_entry_matches)\\n  ' \"\$settings_file\" >/dev/null 2>&1\\n}\\n\\nsettings=\"\$HOME/.claude/settings.json\"\\nalt_settings=\"\$HOME/.config/claude/settings.json\"\\ndcg_command_pattern='(^|[[:space:]/])dcg([[:space:]]|\$)'\\n\\nclaude_settings_has_command_hook \"\$settings\" \"\$dcg_command_pattern\" ||\\n  claude_settings_has_command_hook \"\$alt_settings\" \"\$dcg_command_pattern\"	required	target_user"
    "stack.ru	Repo Updater - multi-repo sync + AI-driven commit automation	ru --version	required	target_user"
    "stack.brenner_bot	Brenner Bot - research session manager with hypothesis tracking	brenner --version || brenner --help	optional	target_user"
    "stack.rch	Remote Compilation Helper - transparent build offloading for AI coding agents	rch --version || rch --help	optional	target_user"
    "stack.wezterm_automata	WezTerm Automata (wa) - terminal automation and orchestration for AI agents	wa --version || wa --help	optional	target_user"
    "stack.srps.1	System Resource Protection Script - ananicy-cpp rules + TUI monitor for responsive dev workstations	command -v sysmoni	optional	target_user"
    "stack.srps.2	System Resource Protection Script - ananicy-cpp rules + TUI monitor for responsive dev workstations	systemctl is-active ananicy-cpp	optional	target_user"
    "stack.frankensearch	Two-tier hybrid local search — lexical (BM25) + semantic retrieval with progressive delivery (fsfs)	fsfs version || fsfs --help	optional	target_user"
    "stack.storage_ballast_helper	Cross-platform disk-pressure defense for AI coding workloads (sbh)	command -v sbh	optional	target_user"
    "stack.cross_agent_session_resumer	Cross-provider AI coding session resumption — convert and resume sessions across providers (casr)	casr providers || casr --help	optional	target_user"
    "stack.doodlestein_self_releaser	Fallback release infrastructure — local builds via act when GitHub Actions is throttled (dsr)	dsr --version || dsr --help	optional	target_user"
    "stack.agent_settings_backup	Smart backup tool for AI coding agent configuration folders (asb)	asb version || asb help	optional	target_user"
    "stack.pcr	Post-compaction reminder hook for Claude Code that forces an AGENTS.md re-read	claude_settings_has_command_hook() {\\n  local settings_file=\"\${1:-}\"\\n  local command_pattern=\"\${2:-}\"\\n  local jq_bin=\"\"\\n\\n  [[ -n \"\$settings_file\" && -n \"\$command_pattern\" ]] || return 1\\n  [[ -f \"\$settings_file\" ]] || return 1\\n  for jq_bin in /usr/bin/jq /bin/jq /usr/local/bin/jq /usr/local/sbin/jq /usr/sbin/jq /sbin/jq; do\\n    [[ -x \"\$jq_bin\" ]] && break\\n  done\\n  [[ -x \"\$jq_bin\" ]] || return 1\\n\\n  \"\$jq_bin\" -e --arg pattern \"\$command_pattern\" '\\n    def command_hook_matches:\\n      type == \"object\"\\n      and ((.type? // \"command\") == \"command\")\\n      and ((.command? // \"\") | strings | test(\$pattern));\\n    def event_entry_matches:\\n      if type == \"object\" and (.hooks? | type) == \"array\" then\\n        any(.hooks[]?; command_hook_matches)\\n      else\\n        command_hook_matches\\n      end;\\n    def hook_event_entries:\\n      if (.hooks? | type) == \"object\" then\\n        .hooks | to_entries[]? | .value | arrays | .[]?\\n      elif (.hooks? | type) == \"array\" then\\n        .hooks[]?\\n      else\\n        empty\\n      end;\\n    any(hook_event_entries; event_entry_matches)\\n  ' \"\$settings_file\" >/dev/null 2>&1\\n}\\n\\ntarget_home=\"\${TARGET_HOME:-\$HOME}\"\\nhook_script=\"\$target_home/.local/bin/claude-post-compact-reminder\"\\nsettings=\"\$target_home/.claude/settings.json\"\\nalt_settings=\"\$target_home/.config/claude/settings.json\"\\npcr_command_pattern='(^|[[:space:]/])claude-post-compact-reminder([[:space:]]|\$)'\\n\\ntest -x \"\$hook_script\" || exit 1\\n\\nclaude_settings_has_command_hook \"\$settings\" \"\$pcr_command_pattern\" ||\\n  claude_settings_has_command_hook \"\$alt_settings\" \"\$pcr_command_pattern\"	optional	target_user"
    "utils.giil	Get Image from Internet Link - download cloud images for visual debugging	giil --help || giil --version	optional	target_user"
    "utils.csctf	Chat Shared Conversation to File - convert AI share links to Markdown/HTML	csctf --help || csctf --version	optional	target_user"
    "utils.xf	xf - Ultra-fast X/Twitter archive search with Tantivy	xf --help || xf --version	optional	target_user"
    "utils.toon_rust	toon_rust (tru) - Token-optimized notation format for LLM context efficiency	tru --help || tru --version	optional	target_user"
    "utils.rano	rano - Network observer for AI CLIs with request/response logging	rano --help || rano --version	optional	target_user"
    "utils.mdwb	markdown_web_browser (mdwb) - Convert websites to Markdown for LLM consumption	mdwb --help || mdwb --version	optional	target_user"
    "utils.s2p	source_to_prompt_tui (s2p) - Code to LLM prompt generator with TUI	s2p --help	optional	target_user"
    "utils.rust_proxy	rust_proxy - Transparent proxy routing for debugging network traffic	rust_proxy --help || rust_proxy --version	optional	target_user"
    "utils.aadc	aadc - ASCII diagram corrector for fixing malformed ASCII art	aadc --help || aadc --version	optional	target_user"
    "utils.caut	coding_agent_usage_tracker (caut) - LLM provider usage tracker	caut --help || caut --version	optional	target_user"
    "acfs.workspace.1	Agent workspace with tmux session and project folder	test -d /data/projects/my_first_project	optional	target_user"
    "acfs.workspace.2	Agent workspace with tmux session and project folder	acfs_has_active_agents_alias() {\\n  local file=\"\${1:-}\"\\n  [[ -f \"\$file\" ]] || return 1\\n\\n  awk '\\n      /^[[:space:]]*#/ { next }\\n      /^[[:space:]]*alias[[:space:]]+agents=/ { found=1; exit }\\n      END { exit(found ? 0 : 1) }\\n  ' \"\$file\" 2>/dev/null\\n}\\n\\nacfs_has_active_agents_alias ~/.zshrc.local || acfs_has_active_agents_alias ~/.zshrc	optional	target_user"
    "acfs.onboard	Onboarding TUI tutorial	onboard --help || command -v onboard	required	target_user"
    "acfs.update	ACFS update command wrapper	acfs-update --help || command -v acfs-update	required	target_user"
    "acfs.nightly	Nightly auto-update timer (systemd)	systemctl --user is-enabled acfs-nightly-update.timer	optional	target_user"
    "acfs.doctor	ACFS doctor command for health checks	acfs doctor --help || command -v acfs	required	target_user"
)

# Execute a manifest check in the requested context without prompting.
run_manifest_check_command() {
    local run_as="$1"
    local cmd="$2"
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-}"
    local explicit_target_home=""
    local resolved_target_home=""
    local target_path=""
    local current_user=""
    local current_home=""
    local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

    explicit_target_home="$target_home"
    if [[ -n "$explicit_target_home" ]]; then
        explicit_target_home="${explicit_target_home%/}"
    fi

    if declare -f _acfs_validate_target_user >/dev/null 2>&1; then
        _acfs_validate_target_user "$target_user" "TARGET_USER" || return 1
    elif [[ -z "$target_user" ]] || [[ ! "$target_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        log_error "Invalid TARGET_USER '${target_user:-<empty>}' (expected: lowercase user name like 'ubuntu')"
        return 1
    fi

    if declare -f _acfs_resolve_target_home >/dev/null 2>&1; then
        resolved_target_home="$(_acfs_resolve_target_home "$target_user" "$explicit_target_home" || true)"
    elif [[ "$target_user" == "root" ]]; then
        resolved_target_home="/root"
    else
        local _acfs_passwd_entry=""
        _acfs_passwd_entry="$(acfs_generated_getent_passwd_entry "$target_user" 2>/dev/null || true)"
        if [[ -n "$_acfs_passwd_entry" ]]; then
            resolved_target_home="$(acfs_generated_passwd_home_from_entry "$_acfs_passwd_entry" 2>/dev/null || true)"
        else
            _acfs_current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
            current_home="${HOME:-}"
            if [[ -n "$current_home" ]]; then
                current_home="${current_home%/}"
            fi
            if [[ "${_acfs_current_user:-}" == "$target_user" ]] && [[ -n "$current_home" ]] && [[ "$current_home" == /* ]] && [[ "$current_home" != "/" ]] && { [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }; then
                resolved_target_home="$current_home"
            fi
            unset _acfs_current_user
        fi
        unset _acfs_passwd_entry
    fi
    if [[ -n "$resolved_target_home" ]]; then
        target_home="${resolved_target_home%/}"
    fi

    if [[ "$cmd" == *"acfs_generated_"* ]]; then
        local helper_prelude=""
        helper_prelude="$(declare -f acfs_generated_system_binary_path acfs_generated_resolve_current_user acfs_generated_getent_passwd_entry acfs_generated_passwd_home_from_entry 2>/dev/null || true)"
        if [[ -z "$helper_prelude" ]]; then
            log_error "Generated helper functions are unavailable for manifest check command"
            return 1
        fi
        cmd="${helper_prelude}"$'\n'"${cmd}"
    fi

    local env_bin=""
    local bash_bin=""
    env_bin="$(acfs_generated_system_binary_path env 2>/dev/null || true)"
    bash_bin="$(acfs_generated_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$env_bin" || -z "$bash_bin" ]]; then
        return 1
    fi

    case "$run_as" in
        target_user)
            if [[ -z "$target_home" ]] || [[ "$target_home" != /* ]] || [[ "$target_home" == "/" ]]; then
                log_error "Invalid TARGET_HOME for '$target_user': ${target_home:-<empty>} (must be an absolute path and cannot be '/')"
                return 1
            fi
            local target_bin="${ACFS_BIN_DIR:-$target_home/.local/bin}"
            if [[ -z "$target_bin" ]] || [[ "$target_bin" != /* ]] || [[ "$target_bin" == "/" ]]; then
                log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${target_bin:-<empty>})"
                return 1
            fi
            local dir=""
            local seen_path=":"
            local target_path_prefix=""
            local -a target_path_entries=()
            for dir in \
                "$target_bin" \
                "$target_home/.local/bin" \
                "$target_home/.acfs/bin" \
                "$target_home/.bun/bin" \
                "$target_home/.cargo/bin" \
                "$target_home/.atuin/bin" \
                "$target_home/go/bin" \
                "$target_home/google-cloud-sdk/bin" \
                "/usr/local/sbin" \
                "/usr/local/bin" \
                "/usr/sbin" \
                "/usr/bin" \
                "/sbin" \
                "/bin" \
                "/snap/bin"; do
                case "$seen_path" in
                    *":$dir:"*) ;;
                    *)
                        target_path_entries+=("$dir")
                        seen_path="${seen_path}${dir}:"
                        ;;
                esac
            done
            target_path_prefix=$(IFS=:; echo "${target_path_entries[*]}")
            target_path="$target_path_prefix${PATH:+:$PATH}"
            current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
            if [[ "${current_user:-}" == "$target_user" ]]; then
                "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"
                return $?
            fi
            local runuser_bin=""
            runuser_bin="$(acfs_generated_system_binary_path runuser 2>/dev/null || true)"
            if [[ $EUID -eq 0 && -n "$runuser_bin" ]]; then
                "$runuser_bin" -u "$target_user" -- "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"
                return $?
            fi
            local sudo_bin=""
            sudo_bin="$(acfs_generated_system_binary_path sudo 2>/dev/null || true)"
            if [[ -n "$sudo_bin" ]]; then
                "$sudo_bin" -n -u "$target_user" "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"
                return $?
            fi
            return 1
            ;;
        root)
            if [[ $EUID -eq 0 ]]; then
                if [[ -n "$target_home" ]] && [[ "$target_home" == /* ]] && [[ "$target_home" != "/" ]]; then
                    "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"
                else
                    "$env_bin" TARGET_USER="$target_user" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"
                fi
                return $?
            fi
            local sudo_bin=""
            sudo_bin="$(acfs_generated_system_binary_path sudo 2>/dev/null || true)"
            if [[ -n "$sudo_bin" ]]; then
                if [[ -n "$target_home" ]] && [[ "$target_home" == /* ]] && [[ "$target_home" != "/" ]]; then
                    "$sudo_bin" -n "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"
                else
                    "$sudo_bin" -n "$env_bin" TARGET_USER="$target_user" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"
                fi
                return $?
            fi
            return 1
            ;;
        current|*)
            if [[ -n "$target_home" ]] && [[ "$target_home" == /* ]] && [[ "$target_home" != "/" ]]; then
                "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" "$bash_bin" -o pipefail -c "$cmd"
            else
                "$env_bin" TARGET_USER="$target_user" "$bash_bin" -o pipefail -c "$cmd"
            fi
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
