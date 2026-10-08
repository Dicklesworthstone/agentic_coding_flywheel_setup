#!/usr/bin/env bash
# claude-code-web-setup.sh - ACFS for Claude Code on the web (cloud environments)
#
# A lightweight, alternate ACFS install path for the disposable VMs behind
# Claude Code cloud sessions (claude.ai/code). install.sh provisions a
# long-lived VPS: a target user, shell theming, an optional Ubuntu upgrade,
# systemd services. None of that fits a cloud session VM, which runs as root,
# already ships Rust/Go/Bun/uv, and is snapshotted after its setup script
# runs. This script installs only prebuilt, hash-pinned flywheel bundles from
# the public mirror. It never runs upstream installers or builds from source.
#
# Use it as the environment's "Setup script" (environment settings dialog):
#
#   #!/bin/bash
#   curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/scripts/claude-code-web-setup.sh | bash
#
# or paste this whole file into the field. Network access must be "Full"
# (or Custom allowing raw.githubusercontent.com and downloads.agent-flywheel.com).
# Locked-down networks retain existing tools and report unavailable downloads.
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
#                        (default: br bv am ubs cass cm ms ast-grep jsm jfp)
#   ACFS_CLOUD_TIMEOUT   whole tool job timeout in seconds (default: 180, max: 180)
#   ACFS_CLOUD_REINSTALL 1 = reinstall tools that are already on PATH
#   ACFS_REF             ACFS git ref that supplies cloud-mirror.json (default: main)

ACFS_REF="${ACFS_REF:-main}"
ACFS_RAW="https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF}"
ACFS_CLOUD_SCRIPT_URL="${ACFS_RAW}/scripts/claude-code-web-setup.sh"
ACFS_CLOUD_DEFAULT_TOOLS="br bv am ubs cass cm ms ast-grep jsm jfp"
ACFS_CLOUD_STATE_DIR="${HOME}/.acfs/cloud"
ACFS_CLOUD_BIN_DIR="${HOME}/.local/bin"
ACFS_CLOUD_GUIDE="${HOME}/.claude/CLAUDE.md"
ACFS_CLOUD_GUIDE_BEGIN="<!-- BEGIN ACFS CLOUD TOOLS (managed by claude-code-web-setup.sh) -->"
ACFS_CLOUD_GUIDE_END="<!-- END ACFS CLOUD TOOLS -->"
# Columns: tool | manifest key | primary binary. All bundles are public.
ACFS_CLOUD_TOOL_TABLE="
br|br|br
bv|bv|bv
am|am|am
ubs|ubs|ubs
cass|cass|cass
cm|cm|cm
ms|ms|ms
ast-grep|ast-grep|ast-grep
jsm|jsm|jsm
jfp|jfp|jfp
"

cloud_step() { printf '\033[34m[acfs-cloud] %s\033[0m\n' "$*" >&2; }
cloud_detail() { printf '\033[90m    %s\033[0m\n' "$*" >&2; }
cloud_ok() { printf '\033[32m    %s\033[0m\n' "$*" >&2; }
cloud_warn() { printf '\033[33m    %s\033[0m\n' "$*" >&2; }

cloud_tool_field() {
    # $1 = tool, $2 = field number (1-based) in ACFS_CLOUD_TOOL_TABLE
    printf '%s\n' "$ACFS_CLOUD_TOOL_TABLE" | awk -F'|' -v tool="$1" -v field="$2" '$1 == tool { print $field; exit }'
}

cloud_download() {
    # $1 = url, $2 = destination file
    curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 5 --max-time 20 \
        -o "$2" "$1"
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
    out="$(timeout 5 "$path" --version </dev/null 2>&1)" || return 1
    [[ -n "$out" ]] || return 1
    printf '%s\n' "${out%%$'\n'*}"
}

cloud_install_tool() {
    local tool="$1" rc bin version log="$ACFS_CLOUD_STATE_DIR/logs/$1.log"
    bin="$(cloud_tool_field "$tool" 3)"
    if [[ "${ACFS_CLOUD_REINSTALL:-0}" != "1" ]] && version="$(cloud_version "$bin")" && { [[ "$tool" != am ]] || cloud_version mcp-agent-mail >/dev/null; }; then
        cloud_link_onto_path "$bin"
        cloud_record "$tool" ok "$version (already installed)"
        return 0
    fi
    timeout --kill-after=2 "$ACFS_CLOUD_TIMEOUT" python3 - "$tool" "$ACFS_CLOUD_WORK" "$HOME/.local" >"$log" 2>&1 <<'PY'
import hashlib, io, json, pathlib, re, shutil, subprocess, sys, tarfile, zipfile
tool, work, prefix = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
try:
    manifest = json.loads((work / 'cloud-mirror.json').read_text())
    if manifest['schema'] != 1 or manifest['platform'] != 'linux-x86_64':
        raise ValueError('unsupported mirror schema/platform')
    entry = manifest['tools'][tool]
    base, relative = manifest['base_url'], entry['file']
    if not re.fullmatch(r'https://[A-Za-z0-9.-]+(?::[0-9]+)?(?:/[A-Za-z0-9_.-]+)*', base):
        raise ValueError('invalid HTTPS mirror URL')
    if not re.fullmatch(r'[A-Za-z0-9_./-]+', relative) or relative.startswith('/') or '..' in relative.split('/'):
        raise ValueError('invalid bundle path')
    if not re.fullmatch(r'[a-f0-9]{64}', entry['sha256']):
        raise ValueError('invalid bundle checksum')
    expected_bins = ['am', 'mcp-agent-mail'] if tool == 'am' else [tool]
    if entry['bins'] != expected_bins:
        raise ValueError('unexpected bundle binaries')
    archive = work / (tool + '.tar.gz')
    def download(url, target):
        if not url.startswith('https://'):
            raise ValueError('HTTPS required')
        result = subprocess.run(['curl', '-fsSL', '--proto', '=https', '--proto-redir', '=https',
                                 '--connect-timeout', '5', '--max-time', '60', '-w', '%{http_connect}',
                                 '-o', str(target), url], stdout=subprocess.PIPE, text=True, check=False)
        if result.returncode and result.stdout.strip() in ('403', '407'):
            host = url.split('/')[2]
            print(host + ' is blocked by this environment\'s network access level (set Full or allow it in Custom)', flush=True)
        return result.returncode == 0
    fallback = False
    expected_sha = entry['sha256']
    if not download(base.rstrip('/') + '/' + relative, archive):
        print('Mirror unreachable: use Full or Custom allowing downloads.agent-flywheel.com. Trying pinned public release.', flush=True)
        source = entry.get('source', {})
        if not re.fullmatch(r'[a-f0-9]{64}', source.get('sha256', '')):
            raise ValueError('no pinned public release fallback')
        if not download(source['url'], archive):
            raise ValueError('mirror and public release blocked/unavailable; select Full network access')
        expected_sha, fallback = source['sha256'], True
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected_sha:
        raise ValueError('bundle checksum mismatch; not extracted')
    if fallback:
        # Normalize only the expected executables from a verified upstream asset.
        # Never extract upstream links, absolute paths or other archive payloads.
        data = archive.read_bytes()
        name = source['asset']
        contents = []
        if name.endswith('.zip'):
            with zipfile.ZipFile(io.BytesIO(data)) as z:
                contents = [(m.filename, z.read(m)) for m in z.infolist() if not m.is_dir() and pathlib.PurePosixPath(m.filename).name in expected_bins]
        elif name.endswith(('.tar.gz', '.tar.xz')):
            with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as t:
                contents = [(m.name, t.extractfile(m).read()) for m in t if m.isfile() and m.size < 512*1024*1024 and pathlib.PurePosixPath(m.name).name in expected_bins]
        elif len(expected_bins) == 1:
            contents = [(expected_bins[0], data)]
        normalized = work / (tool + '-normalized.tar.gz')
        with tarfile.open(normalized, 'w:gz') as t:
            for binary in expected_bins:
                matches = [value for path, value in contents if pathlib.PurePosixPath(path).name == binary]
                if len(matches) != 1:
                    raise ValueError('upstream archive missing/duplicating ' + binary)
                member = tarfile.TarInfo('bin/' + binary)
                member.size = len(matches[0])
                t.addfile(member, io.BytesIO(matches[0]))
        archive = normalized
    stage = work / (tool + '-stage')
    stage.mkdir()
    with tarfile.open(archive, 'r:gz') as tar:
        members = tar.getmembers()
        seen = set()
        total = 0
        for member in members:
            path = pathlib.PurePosixPath(member.name)
            allowed = member.name in ['bin/' + b for b in expected_bins] or (tool == 'ubs' and member.name.startswith('share/ubs/modules/'))
            if not allowed or path.is_absolute() or '..' in path.parts or not member.isfile() or member.name in seen:
                raise ValueError('unsafe archive member: ' + member.name)
            seen.add(member.name)
            total += member.size
            if total > 1024 * 1024 * 1024:
                raise ValueError('bundle expands beyond 1 GiB')
        if not all('bin/' + b in seen for b in expected_bins):
            raise ValueError('bundle missing expected binaries')
        for member in members:
            dest = stage / member.name
            dest.parent.mkdir(parents=True, exist_ok=True)
            with dest.open('xb') as out:
                shutil.copyfileobj(tar.extractfile(member), out)
            dest.chmod(0o755 if member.name.startswith('bin/') or member.name.endswith('.sh') else 0o644)
    for binary in expected_bins:
        result = subprocess.run([str(stage / 'bin' / binary), '--version'], capture_output=True, text=True, timeout=5, check=True)
        version = (result.stdout + result.stderr).strip()
        if not version:
            raise ValueError(binary + ' returned no version')
        print(version.splitlines()[0], flush=True)
    # Validate every destination before copying. Never follow pre-existing links.
    for name in seen:
        target = prefix / name
        if any(p.is_symlink() for p in [target, *target.parents]):
            raise ValueError('symlink in destination: ' + str(target))
        if target.exists() and not target.is_file():
            raise ValueError('non-file destination: ' + str(target))
    for name in sorted(seen):
        target = prefix / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(stage / name, target)
    if fallback and tool == 'ubs':
        print('UBS public-release fallback: modules download on first scan; mirror bundles include them.', flush=True)
except subprocess.CalledProcessError as error:
    if error.returncode == -4:
        print('prebuilt release uses CPU instructions unavailable on this VM (SIGILL)', file=sys.stderr)
    else:
        print(str(error), file=sys.stderr)
    sys.exit(1)
except Exception as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
PY
    rc=$?
    if [[ $rc -eq 0 ]]; then
        cloud_record "$tool" ok "$(cloud_version "$bin") (verified prebuilt)"
    elif [[ $rc -eq 124 || $rc -eq 137 ]]; then
        cloud_record "$tool" fail "download/install timed out after ${ACFS_CLOUD_TIMEOUT}s (see $log)"
    else
        cloud_record "$tool" fail "$(tail -n 1 "$log"); see $log; no source build attempted"
    fi
    return 0
}

cloud_register_agent_mail() {
    # Register Agent Mail with Claude Code as a stdio MCP server so each
    # session spawns it on demand; nothing has to survive the VM snapshot.
    local server claude_bin
    server="$(cloud_find_binary mcp-agent-mail)" || return 1
    claude_bin="$(command -v claude 2>/dev/null)" || return 1
    # Keep any existing registration rather than removing user configuration.
    if timeout 5 "$claude_bin" mcp get mcp-agent-mail >"$ACFS_CLOUD_STATE_DIR/logs/mcp.log" 2>&1; then
        ACFS_CLOUD_MCP_DETAIL="Existing Agent Mail MCP registration retained; see logs/mcp.log"
        return 0
    fi
    ACFS_CLOUD_MCP_DETAIL="Registered Agent Mail as the stdio MCP server 'mcp-agent-mail'"
    timeout 10 "$claude_bin" mcp add --scope user mcp-agent-mail -- "$server" </dev/null >>"$ACFS_CLOUD_STATE_DIR/logs/mcp.log" 2>&1
}

cloud_tool_guide_line() {
    case "$1" in
        br) printf '%s\n' '- `br` (beads_rust): issue tracker in `.beads/`. `br ready --json`, `br show <id>`, `br update <id> --status in_progress`, `br close <id> --reason "..."`, then `br sync --flush-only` and commit `.beads/`.' ;;
        bv) printf '%s\n' '- `bv` (beads_viewer): graph-aware triage over beads. Use ONLY `--robot-*` flags (bare `bv` opens a blocking TUI): `bv --robot-triage`, `bv --robot-next`, `bv --robot-plan`.' ;;
        am) printf '%s\n' '- `am` / `mcp-agent-mail` (Agent Mail): agent messaging and file reservations. MCP registration status is in `~/.acfs/cloud/setup.log`; use `am --help` for CLI access.' ;;
        ast-grep) printf '%s\n' '- `ast-grep`: structural code search used by UBS. Use this name because Linux may have an unrelated `sg` command.' ;;
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
        elif cloud_version "$(cloud_tool_field "$tool" 3)" >/dev/null; then
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
    local started tool bin status detail pid selected=" "
    local -a pids=()
    started=$(date +%s)
    ACFS_CLOUD_TOOLS="${ACFS_CLOUD_TOOLS:-$ACFS_CLOUD_DEFAULT_TOOLS}"
    ACFS_CLOUD_TIMEOUT="${ACFS_CLOUD_TIMEOUT:-180}"
    if [[ ! "$ACFS_CLOUD_TIMEOUT" =~ ^[0-9]+$ ]] || (( ACFS_CLOUD_TIMEOUT < 1 || ACFS_CLOUD_TIMEOUT > 180 )); then
        cloud_warn "ACFS_CLOUD_TIMEOUT must be an integer from 1 to 180"
        return 0
    fi
    if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
        cloud_warn "Cloud bundles support Linux x86_64 only"
        return 0
    fi
    for bin in python3 curl timeout; do
        command -v "$bin" >/dev/null || { cloud_warn "Required command missing: $bin"; return 0; }
    done
    ACFS_CLOUD_WORK="$(mktemp -d "${TMPDIR:-/tmp}/acfs-cloud.XXXXXX")" || return 0
    mkdir -p "$ACFS_CLOUD_STATE_DIR/logs" "$ACFS_CLOUD_BIN_DIR" "$ACFS_CLOUD_WORK/status"
    export PATH="$ACFS_CLOUD_BIN_DIR:/usr/local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"

    cloud_step "ACFS cloud setup: $ACFS_CLOUD_TOOLS"
    cloud_detail "ACFS ref: $ACFS_REF, whole tool job timeout: ${ACFS_CLOUD_TIMEOUT}s"

    if ! cloud_download "$ACFS_RAW/cloud-mirror.json" "$ACFS_CLOUD_WORK/cloud-mirror.json"; then
        cloud_warn "Could not fetch cloud-mirror.json; new installs require Full network access or a Custom allowlist"
        # Discard partial content without ever interpreting it as a manifest.
        printf '{}' > "$ACFS_CLOUD_WORK/cloud-mirror.json"
    fi

    for tool in $ACFS_CLOUD_TOOLS; do
        bin="$(cloud_tool_field "$tool" 3)"
        if [[ -z "$bin" ]]; then
            cloud_warn "Unknown tool '$tool' (known: $ACFS_CLOUD_DEFAULT_TOOLS)"
            continue
        fi
        [[ "$selected" == *" $tool "* ]] && continue
        selected+="$tool "
        cloud_detail "Installing $tool"
        cloud_install_tool "$tool" &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    if [[ -f "$ACFS_CLOUD_WORK/status/am" ]] && IFS='|' read -r status detail < "$ACFS_CLOUD_WORK/status/am" && [[ "$status" == "ok" ]]; then
        if cloud_register_agent_mail; then
            cloud_detail "$ACFS_CLOUD_MCP_DETAIL"
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
    cloud_detail "Retained staging: $ACFS_CLOUD_WORK"
    return 0
}

mkdir -p "${HOME}/.acfs/cloud" 2>/dev/null
# The subshell confines any unexpected error (including set -u) so the
# setup script still exits 0 and the session starts.
( cloud_main "$@" ) 2>&1 | tee "${HOME}/.acfs/cloud/setup.log" >&2
exit 0
