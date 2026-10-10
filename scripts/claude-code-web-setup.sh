#!/usr/bin/env bash
# claude-code-web-setup.sh - prebuilt ACFS tools for cloud agent environments
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
#   curl -q -fsSL --proto '=https' --proto-redir '=https' -A 'OpenAI File Downloader, XaiImageApiFetch/1.0' -H 'Accept-Encoding: identity' https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/scripts/claude-code-web-setup.sh | bash
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
#   ACFS_CLOUD_AGENT     claude (default), codex or generic; selects the guide
#   ACFS_CLOUD_ROOT      writable absolute data root (default: $HOME); in Codex
#                        mode a custom root also holds the explicitly loaded guide
#   ACFS_CLOUD_SKILL_DIR optional absolute repository skill directory for Codex
#   ACFS_CLOUD_TOOLS     space-separated subset of tools to install
#                        (default: br bv am ubs cass cm ms ast-grep jsm jfp)
#   ACFS_CLOUD_TIMEOUT   whole tool job timeout in seconds (default: 180, max: 180)
#   ACFS_CLOUD_REINSTALL 1 = reinstall tools that are already on PATH
#   ACFS_REF             ACFS git ref that supplies cloud-mirror.json (default: main)

ACFS_REF="${ACFS_REF:-main}"
ACFS_RAW="https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF}"
ACFS_CLOUD_SCRIPT_URL="${ACFS_RAW}/scripts/claude-code-web-setup.sh"
ACFS_CLOUD_DEFAULT_TOOLS="br bv am ubs cass cm ms ast-grep jsm jfp"
ACFS_CLOUD_ROOT="${ACFS_CLOUD_ROOT:-$HOME}"
ACFS_CLOUD_SKILL_DIR="${ACFS_CLOUD_SKILL_DIR:-}"
ACFS_CLOUD_STATE_DIR="${ACFS_CLOUD_ROOT}/.acfs/cloud"
ACFS_CLOUD_BIN_DIR="${ACFS_CLOUD_ROOT}/.local/bin"
ACFS_CLOUD_AGENT="${ACFS_CLOUD_AGENT:-claude}"
ACFS_CLOUD_GUIDE="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/CLAUDE.md"
if [[ "$ACFS_CLOUD_AGENT" == codex ]]; then
    ACFS_CLOUD_GUIDE="${CODEX_HOME:-${HOME}/.codex}/AGENTS.md"
    if [[ "$ACFS_CLOUD_ROOT" != "$HOME" ]]; then
        # Hosted CODEX_HOME may be a read-only runtime mount. Keep its config
        # intact; the Start skill explicitly loads this environment-local guide.
        ACFS_CLOUD_GUIDE="$ACFS_CLOUD_ROOT/.codex/AGENTS.md"
    fi
elif [[ "$ACFS_CLOUD_AGENT" == generic ]]; then
    # Other harnesses load this guide explicitly; never change their config
    # or assume they discover another provider's instruction directory.
    ACFS_CLOUD_GUIDE="$ACFS_CLOUD_STATE_DIR/AGENTS.md"
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
    curl -q -fsSL -A 'OpenAI File Downloader, XaiImageApiFetch/1.0' -H 'Accept-Encoding: identity' \
        --proto '=https' --proto-redir '=https' --connect-timeout 5 --max-time 20 \
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
    python3 - "$tool" "$ACFS_CLOUD_WORK" "$ACFS_CLOUD_ROOT/.local" >"$log" 2>&1 <<'PY'
import hashlib, io, json, os, pathlib, re, shutil, stat, subprocess, sys, tarfile, zipfile
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
        result = subprocess.run(['curl', '-q', '-fsSL', '-A', 'OpenAI File Downloader, XaiImageApiFetch/1.0',
                                 '-H', 'Accept-Encoding: identity', '--proto', '=https', '--proto-redir', '=https',
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
        source = entry.get('fallback', entry.get('source', {}))
        if source.get('format', 'upstream') not in ('upstream', 'acfs-overlay'):
            raise ValueError('unsupported public fallback format')
        if not re.fullmatch(r'[a-f0-9]{64}', source.get('sha256', '')):
            raise ValueError('no pinned public release fallback')
        if source.get('format') == 'acfs-overlay' and source['sha256'] != entry['sha256']:
            raise ValueError('public overlay checksum must match mirror bundle')
        if not download(source['url'], archive):
            raise ValueError('mirror and public release blocked/unavailable; select Full network access')
        expected_sha, fallback = source['sha256'], True
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected_sha:
        raise ValueError('bundle checksum mismatch; not extracted')
    if fallback and source.get('format', 'upstream') == 'upstream':
        # Normalize only the expected executables from a verified upstream asset.
        # Never extract upstream links, absolute paths or other archive payloads.
        data = archive.read_bytes()
        name = source['asset']
        contents = []
        def upstream_binary(path, size, read):
            if size < 0 or size > 512 * 1024 * 1024:
                raise ValueError('upstream binary expands beyond 512 MiB: ' + path)
            # Bound the selected bodies before allocating or normalizing them.
            if sum(len(value) for _, value in contents) + size > 1024 * 1024 * 1024:
                raise ValueError('upstream binary payloads expand beyond 1 GiB')
            payload = read()
            if len(payload) != size:
                raise ValueError('upstream binary size mismatch: ' + path)
            contents.append((path, payload))
        if name.endswith('.zip'):
            with zipfile.ZipFile(io.BytesIO(data)) as z:
                for m in z.infolist():
                    if not m.is_dir() and pathlib.PurePosixPath(m.filename).name in expected_bins:
                        if stat.S_IFMT(m.external_attr >> 16) not in (0, stat.S_IFREG):
                            raise ValueError('upstream binary is not a regular file: ' + m.filename)
                        upstream_binary(m.filename, m.file_size, lambda m=m: z.read(m))
        elif name.endswith(('.tar.gz', '.tar.xz')):
            with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as t:
                for m in t:
                    if m.isfile() and pathlib.PurePosixPath(m.name).name in expected_bins:
                        upstream_binary(m.name, m.size, lambda m=m: t.extractfile(m).read())
        elif len(expected_bins) == 1:
            upstream_binary(expected_bins[0], len(data), lambda: data)
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
    replacements = []
    for name in sorted(seen):
        target = prefix / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if any(p.is_symlink() for p in [target, *target.parents]):
            raise ValueError('symlink in destination: ' + str(target))
        # Copy beside the destination before replacing it. A timeout, full disk
        # or interrupted copy must not truncate an already working executable.
        candidate = target.with_name('.' + target.name + '.acfs-' + work.name + '.tmp')
        with candidate.open('xb'):
            pass
        shutil.copy2(stage / name, candidate)
        replacements.append((candidate, target))
    for candidate, target in replacements:
        if any(p.is_symlink() for p in [target, *target.parents]):
            raise ValueError('symlink in destination: ' + str(target))
        os.replace(candidate, target)
    if fallback and tool == 'ubs':
        if source.get('format', 'upstream') == 'acfs-overlay':
            print('UBS complete public fallback: bundled modules/helpers are ready for offline scans.', flush=True)
        else:
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
    local server claude_bin legacy config="$HOME/.claude.json"
    server="$(cloud_find_binary am)" || return 1
    claude_bin="$(command -v claude 2>/dev/null)" || return 1
    legacy="$(cloud_find_binary mcp-agent-mail)" || return 1
    [[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && config="$CLAUDE_CONFIG_DIR/.claude.json"
    # `claude mcp get` can print a custom registration's environment values.
    # Restrict this diagnostic file before any command writes to it.
    (umask 077; : > "$ACFS_CLOUD_STATE_DIR/logs/mcp.log") || return 1
    chmod 600 "$ACFS_CLOUD_STATE_DIR/logs/mcp.log" || return 1
    # Migrate only the exact user-scope entry emitted by earlier ACFS setup.
    # That release defaults to HTTP, so launching it without args as stdio
    # never connected. Preserve every other field/entry and retain a backup.
    if ! python3 - "$config" "$legacy" "$server" "$ACFS_CLOUD_WORK" >>"$ACFS_CLOUD_STATE_DIR/logs/mcp.log" 2>&1 <<'PY'
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
        # The config can contain credentials: restrict its temporary candidate
        # at creation, before writing any bytes, regardless of the caller's umask.
        with os.fdopen(os.open(updated, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
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
    # Keep custom registrations; repair only the legacy ACFS command above.
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
        am) printf '%s\n' "- \`am\` / \`mcp-agent-mail\` (Agent Mail): agent messaging and file reservations. MCP registration status is in \`$ACFS_CLOUD_STATE_DIR/setup.log\`; use \`am --help\` for CLI access." ;;
        ast-grep) printf '%s\n' '- `ast-grep`: structural code search used by UBS. Use this name because Linux may have an unrelated `sg` command.' ;;
        ubs) printf '%s\n' '- `ubs` (Ultimate Bug Scanner): run `ubs <changed files>` before every commit. Default exit 0 can include warnings; read the report. Use `ubs <changed files> --ci --fail-on-warning` when warnings must fail the check.' ;;
        cass) printf '%s\n' '- `cass` (session search): `cass search "query" --robot --limit 5`. Always pass `--robot` or `--json`; bare `cass` opens a TUI.' ;;
        cm) printf '%s\n' '- `cm` (CASS Memory): `cm context "<task>" --json` before starting work to pull relevant procedural memory.' ;;
        ms) printf '%s\n' '- `ms` (meta_skill): local skill search and management; see `ms --help`.' ;;
        jsm) printf '%s\n' '- `jsm` (jeffreys-skills.md): skill manager; `jsm list`, `jsm install <skill>`, `jsm --help`.' ;;
        jfp) printf '%s\n' '- `jfp` (JeffreysPrompts): prompt library CLI; `jfp --help`. Skill installs go through `jsm`.' ;;
    esac
}

cloud_write_guide() {
    local tool status detail block
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
    block+="In each task shell, run \`export PATH=$(printf '%q' "$ACFS_CLOUD_BIN_DIR"):\$PATH\` before using these CLIs:"$'\n\n'
    if [[ "$ACFS_CLOUD_ROOT" != "$HOME" ]]; then
        block+="For JFP's prompt cache in this writable data root, run \`export JFP_HOME=\${JFP_HOME:-$(printf '%q' "$ACFS_CLOUD_ROOT")}\`. This preserves an existing JFP_HOME. If XDG_CONFIG_HOME is set, JFP uses it instead; that directory must also be writable."$'\n\n'
    fi
    if [[ ${#installed[@]} -gt 0 ]]; then
        block+="$(printf '%s\n' "${installed[@]}")"$'\n'
    else
        block+="- (none installed)"$'\n'
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        block+=$'\n'"Not installed at setup time:"$'\n\n'
        block+="$(printf '%s\n' "${missing[@]}")"$'\n'
    fi
    block+=$'\n'"Setup log: \`$ACFS_CLOUD_STATE_DIR/setup.log\` (per-tool logs in \`$ACFS_CLOUD_STATE_DIR/logs/\`)."
    block+=" Re-run: \`curl -q -fsSL --proto '=https' --proto-redir '=https' -A 'OpenAI File Downloader, XaiImageApiFetch/1.0' -H 'Accept-Encoding: identity' $ACFS_CLOUD_SCRIPT_URL | ACFS_REF=$(printf '%q' "$ACFS_REF") ACFS_CLOUD_SKILL_DIR=$(printf '%q' "$ACFS_CLOUD_SKILL_DIR") ACFS_CLOUD_ROOT=$(printf '%q' "$ACFS_CLOUD_ROOT") ACFS_CLOUD_AGENT=$ACFS_CLOUD_AGENT bash\`."$'\n'
    if [[ "$ACFS_CLOUD_AGENT" == codex ]]; then
        block+=$'\nAgent Mail is installed as a CLI. Hosted Codex MCP registration is not configured by this script.\n'
    elif [[ "$ACFS_CLOUD_AGENT" == generic ]]; then
        block+=$'\nLoad this guide explicitly in your agent instructions. Agent Mail is a CLI; provider MCP registration is not configured.\n'
    fi
    block+="$ACFS_CLOUD_GUIDE_END"

    printf '%s\n' "$block" > "$ACFS_CLOUD_WORK/tool-guide.md"
    if ! python3 - "$ACFS_CLOUD_GUIDE" "$ACFS_CLOUD_WORK" "$ACFS_CLOUD_GUIDE_BEGIN" "$ACFS_CLOUD_GUIDE_END" <<'PY'
# ACFS atomic tool guide: never truncate the live instructions or follow links.
import os, pathlib, stat, sys
path, work = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
begin, end = sys.argv[3:]
try:
    def reject_links():
        if any(parent.is_symlink() for parent in [path, *path.parents]):
            raise ValueError('Symlink in instruction path; existing instructions preserved')
    reject_links()
    snapshot = path.stat() if path.exists() else None
    if snapshot and not stat.S_ISREG(snapshot.st_mode):
        raise ValueError('Instruction destination is not a regular file')
    original = path.read_bytes() if snapshot else b''
    if snapshot:
        with os.fdopen(os.open(work / 'instructions-before-update', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as backup:
            backup.write(original)
    kept, inside = [], False
    for line in original.decode('utf-8').splitlines(keepends=True):
        marker = line.rstrip('\r\n')
        if marker == begin:
            if inside:
                raise ValueError('Unbalanced ACFS guide markers')
            inside = True
        elif marker == end:
            if not inside:
                raise ValueError('Unbalanced ACFS guide markers')
            inside = False
        elif not inside:
            kept.append(line)
    if inside:
        raise ValueError('Unbalanced ACFS guide markers')
    while kept and not kept[-1].strip():
        kept.pop()
    preserved = ''.join(kept)
    if preserved and not preserved.endswith('\n'):
        preserved += '\n'
    content = (preserved + ('\n' if preserved else '')).encode() + (work / 'tool-guide.md').read_bytes()
    path.parent.mkdir(parents=True, exist_ok=True)
    reject_links()
    candidate = path.with_name('.' + path.name + '.acfs-' + work.name + '.tmp')
    with os.fdopen(os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as output:
        output.write(content)
        output.flush()
        os.fsync(output.fileno())
    if snapshot:
        owner = candidate.stat()
        if (owner.st_uid, owner.st_gid) != (snapshot.st_uid, snapshot.st_gid):
            os.chown(candidate, snapshot.st_uid, snapshot.st_gid)
        candidate.chmod(stat.S_IMODE(snapshot.st_mode))
        reject_links()
        current = path.stat()
        fields = ('st_dev', 'st_ino', 'st_mtime_ns', 'st_ctime_ns', 'st_size', 'st_mode', 'st_uid', 'st_gid')
        if any(getattr(current, field) != getattr(snapshot, field) for field in fields) or path.read_bytes() != original:
            raise ValueError('Instructions changed while preparing the guide; candidate retained at ' + str(candidate))
        os.replace(candidate, path)
    else:
        # Exclusive creation cannot replace instructions that appeared meanwhile.
        # Retain the private candidate, like the rest of this run's staging.
        os.link(candidate, path)
except Exception as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
PY
    then
        cloud_warn "Could not publish the tool guide; existing instructions preserved. New guide: $ACFS_CLOUD_WORK/tool-guide.md"
        return 1
    fi
}

cloud_write_codex_skill() {
    [[ "$ACFS_CLOUD_AGENT" == codex && -n "$ACFS_CLOUD_SKILL_DIR" ]] || return 0
    # A saved environment Start skill was absent from a fresh hosted task's
    # catalog. Write the documented repository skill format; hosted catalog
    # loading is not guaranteed, so the guide remains usable by explicit path.
    # Never replace an existing skill, even one with the same name.
    if ! python3 - "$ACFS_CLOUD_SKILL_DIR" "$ACFS_CLOUD_GUIDE" "$ACFS_CLOUD_BIN_DIR" "$ACFS_CLOUD_STATE_DIR" <<'PY'
import pathlib, shlex, sys
directory, guide, bins, state = sys.argv[1:]
if not pathlib.Path(guide).is_file():
    raise ValueError('Tool guide is missing; repository skill was not created')
content = '''---
name: acfs-cloud-tools
description: Use when starting coding work in this cloud repository, choosing tasks, or using Beads, Beads Viewer, Agent Mail, UBS, CASS, memory or skills. Load the installed flywheel tool guide and configure PATH; do not reinstall tools.
---

# ACFS cloud tools

Read the generated tool guide at {guide} and setup results at {log}.
In every task shell, run `export PATH={bins}:"$PATH"` before using the CLIs.
Check `br --version`, `bv --version`, `ubs --version` and `jsm --version`.
Follow the guide's robot/JSON commands and use the repository's existing Beads tracker.
When the home directory is read-only, use the guide's JFP_HOME export for the prompt cache.
Do not run the full VPS installer or build tools from source.
Agent Mail is available as a CLI; this skill does not configure hosted MCP.
'''.format(guide=shlex.quote(guide), log=shlex.quote(str(pathlib.Path(state) / 'setup.log')), bins=shlex.quote(bins))
path = pathlib.Path(directory) / 'SKILL.md'
def reject_links():
    if any(parent.is_symlink() for parent in [path, *path.parents]):
        raise ValueError('Symlink in repository skill path; existing files preserved: ' + str(path))
reject_links()
path.parent.mkdir(parents=True, exist_ok=True)
reject_links()
try:
    with path.open('x', encoding='utf-8') as output:
        output.write(content)
except FileExistsError:
    if path.is_symlink() or not path.is_file() or path.read_text() != content:
        raise ValueError('Existing repository skill retained unchanged: ' + str(path))
print('Repository skill for Codex: ' + str(path))
PY
    then
        cloud_warn "Could not create the Codex repository skill; use the generated guide explicitly"
        return 1
    fi
}

cloud_main() {
    set -uo pipefail
    local started tool bin status detail pid selected=" "
    local -a pids=()
    started=$(date +%s)
    case "$ACFS_CLOUD_AGENT" in
        claude|codex|generic) ;;
        *) cloud_warn "ACFS_CLOUD_AGENT must be claude or codex or generic"; return 0 ;;
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
    if ! mkdir -p "$ACFS_CLOUD_STATE_DIR/logs" "$ACFS_CLOUD_BIN_DIR" "$ACFS_CLOUD_WORK/status"; then
        cloud_warn "Cannot write the install directories; choose a writable ACFS_CLOUD_ROOT"
        return 0
    fi
    export PATH="$ACFS_CLOUD_BIN_DIR:/usr/local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
    export ACFS_CLOUD_WORK ACFS_CLOUD_ROOT ACFS_CLOUD_STATE_DIR ACFS_CLOUD_BIN_DIR ACFS_CLOUD_TIMEOUT ACFS_CLOUD_TOOL_TABLE
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

    if cloud_write_guide; then
        cloud_write_codex_skill
    else
        cloud_warn "Guide publication failed; no new repository skill was created"
    fi
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

if [[ "$ACFS_CLOUD_ROOT" != /* || "$ACFS_CLOUD_ROOT" == / ]]; then
    cloud_warn "ACFS_CLOUD_ROOT must be an absolute directory other than /"
    exit 0
fi
if [[ "$ACFS_CLOUD_AGENT" == codex && -n "$ACFS_CLOUD_SKILL_DIR" && ( "$ACFS_CLOUD_SKILL_DIR" != /* || "$ACFS_CLOUD_SKILL_DIR" == / ) ]]; then
    cloud_warn "ACFS_CLOUD_SKILL_DIR must be an absolute directory other than /"
    exit 0
fi
if ! command -v python3 >/dev/null; then
    cloud_warn "Required command missing: python3"
    exit 0
fi
# Validate log destinations before tee or a job truncates an existing file.
# The same guard covers setup.log, every tool log and private MCP diagnostics.
if ! python3 - "$ACFS_CLOUD_STATE_DIR" "$ACFS_CLOUD_DEFAULT_TOOLS" <<'PY'
import pathlib, sys
state = pathlib.Path(sys.argv[1])
paths = [state / 'setup.log', *(state / 'logs' / (tool + '.log') for tool in [*sys.argv[2].split(), 'mcp'])]
for path in paths:
    if any(parent.is_symlink() for parent in [path, *path.parents]) or (path.exists() and not path.is_file()):
        print('Unsafe cloud log destination; existing files preserved: ' + str(path), file=sys.stderr)
        sys.exit(1)
PY
then
    exit 0
fi
if ! mkdir -p "$ACFS_CLOUD_STATE_DIR"; then
    cloud_warn "Cannot write $ACFS_CLOUD_STATE_DIR; choose a writable ACFS_CLOUD_ROOT"
    exit 0
fi
# The subshell confines any unexpected error (including set -u) so the
# setup script still exits 0 and the session starts.
( cloud_main "$@" ) 2>&1 | tee "$ACFS_CLOUD_STATE_DIR/setup.log" >&2
exit 0
