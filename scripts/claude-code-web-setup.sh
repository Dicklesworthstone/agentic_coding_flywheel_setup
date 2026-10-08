#!/usr/bin/env bash
# claude-code-web-setup.sh - ACFS for Claude Code on the web (cloud environments)
#
# A lightweight, alternate ACFS install path for the disposable VMs behind
# Claude Code cloud sessions (claude.ai/code). install.sh provisions a
# long-lived VPS: a target user, shell theming, an optional Ubuntu upgrade,
# systemd services. None of that fits a cloud session VM, which runs as root,
# already ships Rust/Go/Bun/uv, and is snapshotted after its setup script
# runs. This script installs only the agent-facing flywheel CLIs, through the
# same upstream installers that install.sh uses, verified against the same
# checksums.yaml ledger.
#
# Use it as the environment's "Setup script" (environment settings dialog):
#
#   #!/bin/bash
#   curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/scripts/claude-code-web-setup.sh | bash
#
# or paste this whole file into the field. Network access "Full" is
# recommended. The default "Trusted" level also works with reduced coverage:
# jsm and jfp download from jeffreys-skills.md and jeffreysprompts.com, which
# Trusted blocks, so they are skipped and reported as such.
#
# Contract with the cloud environment
# (https://code.claude.com/docs/en/cloud-environments#setup-scripts):
#   - Always exits 0. A non-zero exit stops the session from starting, so a
#     tool that fails to install is reported, never fatal.
#   - Installers run in parallel under a per-installer timeout so the whole
#     run stays under the ~5 minute limit for the environment to be cached.
#   - Leaves nothing running: background processes do not survive the
#     snapshot, so Agent Mail is registered as a stdio MCP server that Claude
#     Code spawns itself instead of an HTTP daemon.
#   - Writes a managed block into ~/.claude/CLAUDE.md, which cloud sessions
#     load as user instructions, listing what was installed and how to use it.
#
# Environment overrides (all optional):
#   ACFS_CLOUD_TOOLS     space-separated subset of tools to install
#                        (default: br bv am ubs cass cm ms jsm jfp)
#   ACFS_CLOUD_TIMEOUT   per-installer timeout in seconds (default: 240)
#   ACFS_CLOUD_REINSTALL 1 = reinstall tools that are already on PATH
#   ACFS_REF             ACFS git ref that supplies checksums.yaml (default: main)

ACFS_REF="${ACFS_REF:-main}"
ACFS_RAW="https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF}"
ACFS_CLOUD_SCRIPT_URL="${ACFS_RAW}/scripts/claude-code-web-setup.sh"
ACFS_CLOUD_DEFAULT_TOOLS="br bv am ubs cass cm ms jsm jfp"
ACFS_CLOUD_STATE_DIR="${HOME}/.acfs/cloud"
ACFS_CLOUD_BIN_DIR="${HOME}/.local/bin"
ACFS_CLOUD_GUIDE="${HOME}/.claude/CLAUDE.md"
ACFS_CLOUD_GUIDE_BEGIN="<!-- BEGIN ACFS CLOUD TOOLS (managed by claude-code-web-setup.sh) -->"
ACFS_CLOUD_GUIDE_END="<!-- END ACFS CLOUD TOOLS -->"
# Any github.com page for a repo this session has not attached answers 403
# with this text when the cloud GitHub proxy scopes access to attached repos.
ACFS_CLOUD_GITHUB_SCOPE_MARKER="is not enabled for this session"

# Columns: tool | checksums.yaml key ("-" = vendor installer outside the
# ledger) | binary | where the binary comes from (github = GitHub release
# assets, vendor = the vendor's own site) | installer arguments
ACFS_CLOUD_TOOL_TABLE="
br|br|br|github|--skip-skills
bv|bv|bv|github|
am|mcp_agent_mail|am|github|--yes --no-service
ubs|ubs|ubs|github|--easy-mode --skip-hooks
cass|cass|cass|github|--easy-mode --verify
cm|cm|cm|github|--easy-mode --verify
ms|ms|ms|github|--easy-mode
jsm|-|jsm|vendor|
jfp|jfp|jfp|vendor|
"
ACFS_CLOUD_JSM_URL="https://jeffreys-skills.md/install.sh"

cloud_step() { printf '\033[34m[acfs-cloud] %s\033[0m\n' "$*" >&2; }
cloud_detail() { printf '\033[90m    %s\033[0m\n' "$*" >&2; }
cloud_ok() { printf '\033[32m    %s\033[0m\n' "$*" >&2; }
cloud_warn() { printf '\033[33m    %s\033[0m\n' "$*" >&2; }

cloud_tool_field() {
    # $1 = tool, $2 = field number (1-based) in ACFS_CLOUD_TOOL_TABLE
    printf '%s\n' "$ACFS_CLOUD_TOOL_TABLE" | awk -F'|' -v tool="$1" -v field="$2" '$1 == tool { print $field; exit }'
}

cloud_ledger_entry() {
    # Prints "url sha256" for a checksums.yaml installer key.
    awk -v key="  $1:" '
        $0 == key { found = 1; next }
        found && /^    url:/ { url = $2 }
        found && /^    sha256:/ { sha = $2 }
        found && !/^    / { exit }
        END {
            gsub(/"/, "", url)
            gsub(/"/, "", sha)
            if (url != "" && sha != "") print url, sha
        }
    ' "$ACFS_CLOUD_WORK/checksums.yaml"
}

cloud_download() {
    # $1 = url, $2 = destination file
    curl -fsSL --proto '=https' --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 120 \
        -o "$2" "$1"
}

cloud_host_blocked() {
    # True when the egress proxy refuses the CONNECT for this URL's host,
    # which is how a host outside the environment's network access level
    # shows up. curl -f reports that as a plain HTTP 403, so ask for the
    # proxy's CONNECT code separately (an allowed host answers 200).
    local code
    code="$(curl -sS -o /dev/null --max-time 20 -w '%{http_connect}' "$1" 2>/dev/null)"
    [[ "$code" == "403" || "$code" == "407" ]]
}

cloud_record() {
    # $1 = tool, $2 = ok|fail, $3 = detail
    printf '%s|%s\n' "$2" "$3" > "$ACFS_CLOUD_WORK/status/$1"
}

cloud_find_binary() {
    # Resolve a binary across the directories upstream installers write to.
    PATH="$ACFS_CLOUD_BIN_DIR:/usr/local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/go/bin:$PATH" \
        command -v "$1" 2>/dev/null
}

cloud_link_onto_path() {
    # Cloud sessions put ~/.local/bin, /usr/local/bin, ~/.cargo/bin and
    # ~/.bun/bin on PATH, but not ~/go/bin or installer-private directories.
    local bin="$1" path dir
    path="$(cloud_find_binary "$bin")" || return 1
    dir="$(dirname "$path")"
    case "$dir" in
        "$ACFS_CLOUD_BIN_DIR" | /usr/local/bin | /usr/bin | "$HOME/.cargo/bin" | "$HOME/.bun/bin") ;;
        *) ln -sf "$path" "$ACFS_CLOUD_BIN_DIR/$bin" ;;
    esac
}

cloud_version() {
    local bin="$1" path out
    path="$(cloud_find_binary "$bin")" || return 1
    out="$(timeout 15 "$path" --version </dev/null 2>/dev/null | head -n 1)"
    printf '%s\n' "${out:-installed}"
}

cloud_install_tool() {
    # Runs in a background job: download, verify, run, and record one installer.
    local tool="$1" key bin args url host sha actual installer log rc
    local -a installer_args=() installer_env=()
    key="$(cloud_tool_field "$tool" 2)"
    bin="$(cloud_tool_field "$tool" 3)"
    args="$(cloud_tool_field "$tool" 5)"
    log="$ACFS_CLOUD_STATE_DIR/logs/$tool.log"
    installer="$ACFS_CLOUD_WORK/installers/$tool.sh"

    if [[ "$key" == "-" ]]; then
        # jsm ships from its own site and is not in the ACFS ledger; this is
        # the vendor's documented one-liner, cache-busted the same way.
        url="${ACFS_CLOUD_JSM_URL}?$(date +%s)"
        sha=""
    else
        if [[ ! -s "$ACFS_CLOUD_WORK/checksums.yaml" ]]; then
            cloud_record "$tool" fail "checksums.yaml unavailable; refusing to run an unverified installer"
            return 0
        fi
        read -r url sha < <(cloud_ledger_entry "$key")
        if [[ -z "${url:-}" || -z "${sha:-}" ]]; then
            cloud_record "$tool" fail "no '$key' entry in checksums.yaml"
            return 0
        fi
    fi

    if ! cloud_download "$url" "$installer" 2>"$log"; then
        host="${url#https://}"
        host="${host%%/*}"
        if cloud_host_blocked "$url"; then
            cloud_record "$tool" fail "$host is blocked by this environment's network access level (set it to Full)"
        else
            cloud_record "$tool" fail "could not download ${url%%\?*} (see $log)"
        fi
        return 0
    fi

    if [[ -n "$sha" ]]; then
        actual="$(sha256sum "$installer" | awk '{ print $1 }')"
        if [[ "$actual" != "$sha" ]]; then
            cloud_record "$tool" fail "installer checksum mismatch (ledger ${sha:0:12}, got ${actual:0:12}); not run"
            return 0
        fi
    fi

    [[ -n "$args" ]] && read -r -a installer_args <<< "$args"
    if [[ "$tool" == "am" ]]; then
        # MCP client wiring happens below as a stdio server; the installer's
        # own setup targets the HTTP daemon this VM cannot keep running.
        installer_env=(AM_INSTALL_SKIP_MCP_SETUP=1 AM_INSTALL_SKIP_REMOTE_HTTP_READINESS=1)
    fi

    env "${installer_env[@]}" timeout --kill-after=15 "$ACFS_CLOUD_TIMEOUT" \
        bash "$installer" "${installer_args[@]}" </dev/null >>"$log" 2>&1
    rc=$?

    if cloud_find_binary "$bin" >/dev/null; then
        cloud_link_onto_path "$bin"
        cloud_record "$tool" ok "$(cloud_version "$bin")"
    elif [[ $rc -eq 124 || $rc -eq 137 ]]; then
        cloud_record "$tool" fail "installer timed out after ${ACFS_CLOUD_TIMEOUT}s (see $log)"
    elif grep -q "$ACFS_CLOUD_GITHUB_SCOPE_MARKER" "$log" 2>/dev/null; then
        cloud_record "$tool" fail "GitHub proxy blocked release downloads (see $log)"
    else
        cloud_record "$tool" fail "installer exited $rc without installing $bin (see $log)"
    fi
    return 0
}

cloud_build_bv_from_source() {
    # bv fallback that avoids github.com release downloads: an anonymous
    # shallow clone (public git reads are not repo-scoped) plus a Go build.
    # bv needs a newer Go than the image ships; GOTOOLCHAIN fetches it from
    # the Go module proxy.
    local log="$ACFS_CLOUD_STATE_DIR/logs/bv-source.log" src="$ACFS_CLOUD_WORK/bv-src"
    command -v go >/dev/null 2>&1 || return 1
    git clone --quiet --depth 1 https://github.com/Dicklesworthstone/beads_viewer "$src" >"$log" 2>&1 || return 1
    (
        cd "$src" &&
            GOTOOLCHAIN="${GOTOOLCHAIN:-auto}" CGO_ENABLED=0 timeout "$ACFS_CLOUD_TIMEOUT" \
                go build -trimpath -o "$ACFS_CLOUD_BIN_DIR/bv" ./cmd/bv
    ) >>"$log" 2>&1
}

cloud_register_agent_mail() {
    # Register Agent Mail with Claude Code as a stdio MCP server so each
    # session spawns it on demand; nothing has to survive the VM snapshot.
    local server claude_bin
    server="$(cloud_find_binary mcp-agent-mail)" || return 1
    claude_bin="$(command -v claude 2>/dev/null)" || return 1
    timeout 30 "$claude_bin" mcp remove --scope user mcp-agent-mail </dev/null >/dev/null 2>&1 || true
    timeout 30 "$claude_bin" mcp add --scope user mcp-agent-mail -- "$server" </dev/null >/dev/null 2>&1
}

cloud_tool_guide_line() {
    case "$1" in
        br) printf '%s\n' '- `br` (beads_rust): issue tracker in `.beads/`. `br ready --json`, `br show <id>`, `br update <id> --status in_progress`, `br close <id> --reason "..."`, then `br sync --flush-only` and commit `.beads/`.' ;;
        bv) printf '%s\n' '- `bv` (beads_viewer): graph-aware triage over beads. Use ONLY `--robot-*` flags (bare `bv` opens a blocking TUI): `bv --robot-triage`, `bv --robot-next`, `bv --robot-plan`.' ;;
        am) printf '%s\n' '- `am` / `mcp-agent-mail` (Agent Mail): agent messaging and file reservations. Registered as the stdio MCP server `mcp-agent-mail`; if its tools are not loaded, use the CLI (`am --help`, `am robot status --project "$PWD" --agent <Name>`) or run `claude mcp add --scope project mcp-agent-mail -- mcp-agent-mail` in the repo.' ;;
        ubs) printf '%s\n' '- `ubs` (Ultimate Bug Scanner): run `ubs <changed files>` before every commit; exit 0 means clean.' ;;
        cass) printf '%s\n' '- `cass` (session search): `cass search "query" --robot --limit 5`. Always pass `--robot` or `--json`; bare `cass` opens a TUI.' ;;
        cm) printf '%s\n' '- `cm` (CASS Memory): `cm context "<task>" --json` before starting work to pull relevant procedural memory.' ;;
        ms) printf '%s\n' '- `ms` (meta_skill): local skill search and management; see `ms --help`.' ;;
        jsm) printf '%s\n' '- `jsm` (jeffreys-skills.md): skill manager; `jsm list`, `jsm install <skill>`, `jsm --help`.' ;;
        jfp) printf '%s\n' '- `jfp` (JeffreysPrompts): prompt library CLI; `jfp --help`. Skill installs go through `jsm`.' ;;
    esac
}

cloud_write_guide() {
    local tool status detail block tmp
    local -a installed=() missing=()
    # Cover every known tool, not just this run's selection, so a partial
    # re-run does not drop tools installed earlier from the guide.
    for tool in $ACFS_CLOUD_DEFAULT_TOOLS; do
        if [[ -f "$ACFS_CLOUD_WORK/status/$tool" ]]; then
            IFS='|' read -r status detail < "$ACFS_CLOUD_WORK/status/$tool"
        elif cloud_find_binary "$(cloud_tool_field "$tool" 3)" >/dev/null; then
            status="ok"
        else
            continue
        fi
        if [[ "$status" == "ok" ]]; then
            installed+=("$(cloud_tool_guide_line "$tool")")
        else
            missing+=("- \`$tool\`: $detail")
        fi
    done

    block="$ACFS_CLOUD_GUIDE_BEGIN"$'\n'
    block+="# Agent Flywheel tools (ACFS cloud setup)"$'\n\n'
    block+="This VM was provisioned by the ACFS Claude Code on the web setup script"$'\n'
    block+="(https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup). These CLIs are on PATH:"$'\n\n'
    if [[ ${#installed[@]} -gt 0 ]]; then
        block+="$(printf '%s\n' "${installed[@]}")"$'\n'
    else
        block+="- (none installed)"$'\n'
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        block+=$'\n'"Not installed at setup time:"$'\n\n'
        block+="$(printf '%s\n' "${missing[@]}")"$'\n'
    fi
    block+=$'\n'"Setup log: \`~/.acfs/cloud/setup.log\` (per-tool logs in \`~/.acfs/cloud/logs/\`)."
    block+=" Re-run: \`curl -fsSL $ACFS_CLOUD_SCRIPT_URL | bash\`."$'\n'
    block+="$ACFS_CLOUD_GUIDE_END"

    mkdir -p "$(dirname "$ACFS_CLOUD_GUIDE")"
    tmp="$ACFS_CLOUD_WORK/CLAUDE.md"
    if [[ -f "$ACFS_CLOUD_GUIDE" ]]; then
        # Keep everything outside the managed block (e.g. other setup lines),
        # minus trailing blank lines so re-runs do not accumulate them.
        awk -v begin="$ACFS_CLOUD_GUIDE_BEGIN" -v end="$ACFS_CLOUD_GUIDE_END" '
            $0 == begin { skip = 1; next }
            $0 == end { skip = 0; next }
            skip { next }
            /^[[:space:]]*$/ { blank++; next }
            { while (blank > 0) { print ""; blank-- } print }
        ' "$ACFS_CLOUD_GUIDE" > "$tmp"
        [[ -s "$tmp" ]] && printf '\n' >> "$tmp"
    else
        : > "$tmp"
    fi
    printf '%s\n' "$block" >> "$tmp"
    cat "$tmp" > "$ACFS_CLOUD_GUIDE"
}

cloud_main() {
    set -uo pipefail
    local started tool bin status detail probe_body probe_code
    local -a pids=()
    started=$(date +%s)
    ACFS_CLOUD_TOOLS="${ACFS_CLOUD_TOOLS:-$ACFS_CLOUD_DEFAULT_TOOLS}"
    ACFS_CLOUD_TIMEOUT="${ACFS_CLOUD_TIMEOUT:-240}"
    ACFS_CLOUD_WORK="$(mktemp -d "${TMPDIR:-/tmp}/acfs-cloud.XXXXXX")" || return 0
    mkdir -p "$ACFS_CLOUD_STATE_DIR/logs" "$ACFS_CLOUD_BIN_DIR" "$ACFS_CLOUD_WORK/status" "$ACFS_CLOUD_WORK/installers"
    export PATH="$ACFS_CLOUD_BIN_DIR:/usr/local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"

    cloud_step "ACFS cloud setup: $ACFS_CLOUD_TOOLS"
    cloud_detail "ACFS ref: $ACFS_REF, per-installer timeout: ${ACFS_CLOUD_TIMEOUT}s"

    if ! cloud_download "$ACFS_RAW/checksums.yaml" "$ACFS_CLOUD_WORK/checksums.yaml"; then
        cloud_warn "Could not fetch checksums.yaml; ledger-verified installers will be skipped"
        rm -f "$ACFS_CLOUD_WORK/checksums.yaml"
    fi

    # Probe whether github.com release downloads work for repos outside the
    # session's attached repositories (the cloud GitHub proxy may scope them).
    ACFS_CLOUD_GITHUB_SCOPED=0
    probe_body="$ACFS_CLOUD_WORK/github-probe"
    probe_code="$(curl -sS --max-time 20 -o "$probe_body" -w '%{http_code}' \
        https://github.com/Dicklesworthstone/beads_rust/releases/latest 2>/dev/null)"
    if [[ "$probe_code" == "403" ]] && grep -q "$ACFS_CLOUD_GITHUB_SCOPE_MARKER" "$probe_body" 2>/dev/null; then
        ACFS_CLOUD_GITHUB_SCOPED=1
        cloud_warn "github.com is scoped to this session's repositories; release-based installers will be skipped"
    fi

    for tool in $ACFS_CLOUD_TOOLS; do
        bin="$(cloud_tool_field "$tool" 3)"
        if [[ -z "$bin" ]]; then
            cloud_warn "Unknown tool '$tool' (known: $ACFS_CLOUD_DEFAULT_TOOLS)"
            continue
        fi
        if [[ "${ACFS_CLOUD_REINSTALL:-0}" != "1" ]] && cloud_find_binary "$bin" >/dev/null; then
            cloud_link_onto_path "$bin"
            cloud_record "$tool" ok "$(cloud_version "$bin") (already installed)"
            continue
        fi
        if [[ "$ACFS_CLOUD_GITHUB_SCOPED" == "1" && "$(cloud_tool_field "$tool" 4)" == "github" ]]; then
            cloud_record "$tool" fail "github.com release downloads are blocked by the session's GitHub proxy"
            continue
        fi
        cloud_detail "Installing $tool"
        cloud_install_tool "$tool" &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    if [[ " $ACFS_CLOUD_TOOLS " == *" bv "* ]] && ! cloud_find_binary bv >/dev/null; then
        cloud_detail "bv: building from source (git clone + go build)"
        if cloud_build_bv_from_source && cloud_find_binary bv >/dev/null; then
            cloud_record bv ok "$(cloud_version bv) (built from source)"
        else
            cloud_record bv fail "release install and source build both failed (see $ACFS_CLOUD_STATE_DIR/logs/bv*.log)"
        fi
    fi

    if [[ -f "$ACFS_CLOUD_WORK/status/am" ]] && IFS='|' read -r status detail < "$ACFS_CLOUD_WORK/status/am" && [[ "$status" == "ok" ]]; then
        if cloud_register_agent_mail; then
            cloud_detail "Registered Agent Mail as the stdio MCP server 'mcp-agent-mail'"
        else
            cloud_warn "Could not register Agent Mail with Claude Code (am CLI still works)"
        fi
    fi

    cloud_write_guide

    cloud_step "Summary ($(( $(date +%s) - started ))s)"
    for tool in $ACFS_CLOUD_TOOLS; do
        [[ -f "$ACFS_CLOUD_WORK/status/$tool" ]] || continue
        IFS='|' read -r status detail < "$ACFS_CLOUD_WORK/status/$tool"
        if [[ "$status" == "ok" ]]; then
            cloud_ok "$(printf '%-5s %s' "$tool" "$detail")"
        else
            cloud_warn "$(printf '%-5s %s' "$tool" "$detail")"
        fi
    done
    cloud_detail "Guide for Claude: $ACFS_CLOUD_GUIDE; logs: $ACFS_CLOUD_STATE_DIR/logs/"
    rm -rf "$ACFS_CLOUD_WORK"
    return 0
}

mkdir -p "${HOME}/.acfs/cloud" 2>/dev/null
# The subshell confines any unexpected error (including set -u) so the
# setup script still exits 0 and the session starts.
( cloud_main "$@" ) 2>&1 | tee "${HOME}/.acfs/cloud/setup.log" >&2
exit 0
