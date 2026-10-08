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
# or paste this whole file into the field. Network access "Full" is recommended
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
#   ACFS_CLOUD_AGENT     claude (default) or codex; selects the instruction guide
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
ACFS_CLOUD_AGENT="${ACFS_CLOUD_AGENT:-claude}"
ACFS_CLOUD_GUIDE="${HOME}/.claude/CLAUDE.md"
if [[ "$ACFS_CLOUD_AGENT" == codex ]]; then
    ACFS_CLOUD_GUIDE="${CODEX_HOME:-${HOME}/.codex}/AGENTS.md"
fi
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

# Exported job functions are invoked in the timeout-controlled child Bash.
# shellcheck disable=SC2329
cloud_link_onto_path() {
    # Cloud sessions put ~/.local/bin, /usr/local/bin, ~/.cargo/bin and
    # ~/.bun/bin on PATH, but not ~/go/bin or installer-private directories.
    local bin="$1" path dir
    path="$(cloud_find_binary "$bin")" || return 1
    dir="$(dirname "$path")"
    case "$dir" in
        "$ACFS_CLOUD_BIN_DIR" | /usr/local/bin | /usr/bin | "$HOME/.cargo/bin" | "$HOME/.bun/bin") ;;
        *) ln -s "$path" "$ACFS_CLOUD_BIN_DIR/$bin" ;;
    esac
}

cloud_version() {
    local bin="$1" path out
    path="$(cloud_find_binary "$bin")" || return 1
    out="$(timeout --kill-after=1 5 "$path" --version </dev/null 2>&1)" || return 1
    [[ -n "$out" ]] || return 1
    printf '%s\n' "${out%%$'\n'*}"
}

# shellcheck disable=SC2329
cloud_install_tool_job() {
    local tool="$1" rc bin version log="$ACFS_CLOUD_STATE_DIR/logs/$1.log"
    bin="$(cloud_tool_field "$tool" 3)"
    if [[ "${ACFS_CLOUD_REINSTALL:-0}" != "1" ]] && version="$(cloud_version "$bin")" && { [[ "$tool" != am ]] || cloud_version mcp-agent-mail >/dev/null; }; then
        if ! cloud_link_onto_path "$bin" || { [[ "$tool" == am ]] && ! cloud_link_onto_path mcp-agent-mail; }; then
            cloud_record "$tool" fail "existing binary could not be linked onto PATH"
            return 0
        fi
        cloud_record "$tool" ok "$version (already installed)"
        return 0
    fi
    python3 - "$tool" "$ACFS_CLOUD_WORK" "$HOME/.local" >"$log" 2>&1 <<'PY'
import hashlib, io, json, pathlib, re, shutil, subprocess, sys, tarfile, zipfile
tool, work, prefix = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
blocked_hosts = []
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
            diagnostic = host + ' is blocked by this environment\'s network access level (set Full or allow it in Custom)'
            blocked_hosts.append(diagnostic)
            print(diagnostic, flush=True)
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
    print('; '.join([*blocked_hosts, str(error)]), file=sys.stderr)
    sys.exit(1)
PY
    rc=$?
    if [[ $rc -eq 0 ]]; then
        if version="$(cloud_version "$bin")" && { [[ "$tool" != am ]] || cloud_version mcp-agent-mail >/dev/null; }; then
            cloud_record "$tool" ok "$version (verified prebuilt)"
        else
            cloud_record "$tool" fail "installed binary verification failed; see $log"
        fi
    else
        cloud_record "$tool" fail "$(tail -n 1 "$log"); see $log; no source build attempted"
    fi
    return 0
}

cloud_install_tool() {
    # Bound the entire job, including existing/final binary probes, not only
    # downloads. GNU timeout also signals the job's subprocess group.
    local tool="$1" rc log="$ACFS_CLOUD_STATE_DIR/logs/$1.log"
    : > "$log"
    timeout --kill-after=2 "$ACFS_CLOUD_TIMEOUT" bash -c 'set -uo pipefail; cloud_install_tool_job "$1"' _ "$tool"
    rc=$?
    if [[ $rc -eq 124 || $rc -eq 137 ]]; then
        cloud_record "$tool" fail "download/install timed out after ${ACFS_CLOUD_TIMEOUT}s (see $log)"
    elif [[ $rc -ne 0 || ! -f "$ACFS_CLOUD_WORK/status/$tool" ]]; then
        cloud_record "$tool" fail "tool job failed (exit $rc); see $log; no source build attempted"
    fi
}

cloud_register_agent_mail() {
    # Register Agent Mail with Claude Code as a stdio MCP server so each
    # session spawns it on demand; nothing has to survive the VM snapshot.
    local server claude_bin legacy
    server="$(cloud_find_binary am)" || return 1
    claude_bin="$(command -v claude 2>/dev/null)" || return 1
    legacy="$(cloud_find_binary mcp-agent-mail)" || return 1
    : > "$ACFS_CLOUD_STATE_DIR/logs/mcp.log"
    # Migrate only the exact user-scope entry emitted by earlier ACFS setup.
    # That release defaults to HTTP, so launching it without args as stdio
    # never connected. Preserve every other field/entry and retain a backup.
    if ! python3 - "$HOME/.claude.json" "$legacy" "$server" "$ACFS_CLOUD_WORK" >>"$ACFS_CLOUD_STATE_DIR/logs/mcp.log" 2>&1 <<'PY'
import json, os, pathlib, stat, sys
path, legacy, server, work = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4])
if path.is_file():
    original = path.read_bytes()
    config = json.loads(original)
    entry = config.get('mcpServers', {}).get('mcp-agent-mail', {})
    if entry.get('command') == legacy and entry.get('args', []) == [] and entry.get('type', 'stdio') == 'stdio':
        if path.is_symlink():
            raise ValueError('Legacy registration is in a symlinked config; retained unchanged')
        (work / 'claude.json.before-stdio-fix').write_bytes(original)
        (work / 'claude.json.before-stdio-fix').chmod(0o600)
        entry['command'], entry['args'] = server, ['serve-stdio']
        updated = path.with_name(path.name + '.acfs-' + work.name + '.tmp')
        with updated.open('x') as output:
            output.write(json.dumps(config, indent=2) + '\n')
        updated.chmod(stat.S_IMODE(path.stat().st_mode))
        if path.read_bytes() != original:
            raise ValueError('Config changed concurrently; registration retained, candidate saved')
        os.replace(updated, path)
        print('Migrated legacy ACFS registration to am serve-stdio; backup retained in ' + str(work))
PY
    then
        cloud_warn "Could not migrate legacy Agent Mail registration; inspect logs/mcp.log"
        return 1
    fi
    # Keep any existing registration rather than removing user configuration.
    if timeout --kill-after=1 5 "$claude_bin" mcp get mcp-agent-mail </dev/null >>"$ACFS_CLOUD_STATE_DIR/logs/mcp.log" 2>&1; then
        ACFS_CLOUD_MCP_DETAIL="Existing Agent Mail MCP registration retained; see logs/mcp.log"
        return 0
    fi
    ACFS_CLOUD_MCP_DETAIL="Registered Agent Mail as the stdio MCP server 'mcp-agent-mail'"
    timeout --kill-after=1 10 "$claude_bin" mcp add --scope user mcp-agent-mail -- "$server" serve-stdio </dev/null >>"$ACFS_CLOUD_STATE_DIR/logs/mcp.log" 2>&1
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
        elif cloud_version "$(cloud_tool_field "$tool" 3)" >/dev/null && { [[ "$tool" != am ]] || cloud_version mcp-agent-mail >/dev/null; }; then
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
    block+="This VM was provisioned by the ACFS cloud setup script for $ACFS_CLOUD_AGENT"$'\n'
    block+="(https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup)."$'\n'
    block+='In each task shell, run `export PATH="$HOME/.local/bin:$PATH"` before using these CLIs:'$'\n\n'
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
    block+=" Re-run: \`curl -fsSL $ACFS_CLOUD_SCRIPT_URL | ACFS_CLOUD_AGENT=$ACFS_CLOUD_AGENT bash\`."$'\n'
    if [[ "$ACFS_CLOUD_AGENT" == codex ]]; then
        block+=$'\nAgent Mail is installed as a CLI. Hosted Codex MCP registration is not configured by this script.\n'
    fi
    block+="$ACFS_CLOUD_GUIDE_END"

    mkdir -p "$(dirname "$ACFS_CLOUD_GUIDE")"
    tmp="$ACFS_CLOUD_WORK/CLAUDE.md"
    printf '%s\n' "$block" > "$ACFS_CLOUD_WORK/tool-guide.md"
    if [[ -f "$ACFS_CLOUD_GUIDE" ]]; then
        # An interrupted/manual edit can leave an unmatched marker. Refuse
        # to interpret the rest of the user's instructions as managed content.
        if ! awk -v begin="$ACFS_CLOUD_GUIDE_BEGIN" -v end="$ACFS_CLOUD_GUIDE_END" '
            $0 == begin { if (inside) { bad = 1; exit } inside = 1 }
            $0 == end { if (!inside) { bad = 1; exit } inside = 0 }
            END { exit (bad || inside) }
        ' "$ACFS_CLOUD_GUIDE"; then
            cloud_warn "Unbalanced ACFS guide markers; existing instructions preserved. New guide: $ACFS_CLOUD_WORK/tool-guide.md"
            return 1
        fi
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
    case "$ACFS_CLOUD_AGENT" in
        claude|codex) ;;
        *) cloud_warn "ACFS_CLOUD_AGENT must be claude or codex"; return 0 ;;
    esac
    ACFS_CLOUD_TOOLS="${ACFS_CLOUD_TOOLS:-$ACFS_CLOUD_DEFAULT_TOOLS}"
    ACFS_CLOUD_TIMEOUT="${ACFS_CLOUD_TIMEOUT:-180}"
    if [[ ! "$ACFS_CLOUD_TIMEOUT" =~ ^([1-9]|[1-9][0-9]|1[0-7][0-9]|180)$ ]]; then
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
    export ACFS_CLOUD_WORK ACFS_CLOUD_STATE_DIR ACFS_CLOUD_BIN_DIR ACFS_CLOUD_TIMEOUT ACFS_CLOUD_TOOL_TABLE
    export -f cloud_install_tool_job cloud_version cloud_find_binary cloud_tool_field cloud_link_onto_path cloud_record

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

    if [[ "$ACFS_CLOUD_AGENT" == claude && -f "$ACFS_CLOUD_WORK/status/am" ]] && IFS='|' read -r status detail < "$ACFS_CLOUD_WORK/status/am" && [[ "$status" == "ok" ]]; then
        if cloud_register_agent_mail; then
            cloud_detail "$ACFS_CLOUD_MCP_DETAIL"
        else
            cloud_warn "Could not register Agent Mail with Claude Code (am CLI still works)"
        fi
    fi

    cloud_write_guide
    if [[ "$ACFS_CLOUD_AGENT" == codex && -s "$(dirname "$ACFS_CLOUD_GUIDE")/AGENTS.override.md" ]]; then
        cloud_warn "Existing AGENTS.override.md takes precedence. Add a reference to $ACFS_CLOUD_GUIDE in your Start skill."
    fi

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
    cloud_detail "Guide for $ACFS_CLOUD_AGENT: $ACFS_CLOUD_GUIDE; logs: $ACFS_CLOUD_STATE_DIR/logs/"
    cloud_detail "Retained staging: $ACFS_CLOUD_WORK"
    return 0
}

mkdir -p "${HOME}/.acfs/cloud" 2>/dev/null
# The subshell confines any unexpected error (including set -u) so the
# setup script still exits 0 and the session starts.
( cloud_main "$@" ) 2>&1 | tee "${HOME}/.acfs/cloud/setup.log" >&2
exit 0
