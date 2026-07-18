#!/usr/bin/env bash
# generate-root-agents-md.sh - Generate the ACFS flywheel agent guide
#
# Installed on target machines as `flywheel-update-agents-md`.
#
# Generates a comprehensive agent guide documenting installed flywheel
# tools, common workflows, and agent guidelines. The guide is written ONLY
# to an ACFS-owned canonical path:
#
#   ~/.acfs/docs/flywheel-agent-guide.md
#
# ACFS never automatically writes /AGENTS.md, /data/projects/AGENTS.md,
# ~/.codex/AGENTS.md, or any project's AGENTS.md. Deployment into a real
# agent-instruction surface is an explicit, optional, non-overwriting step
# (see `deploy` below), because those files can contain user-authored safety
# rules that must never be silently replaced.
#
# Tool detection always runs in the TARGET USER's context: when invoked via
# sudo, the target user is resolved from SUDO_USER (override: ACFS_TARGET_USER)
# and the user's tool directories (~/.local/bin, ~/go/bin, ...) are prepended
# to PATH so user-local installs are not falsely reported as missing.
#
# Usage:
#   flywheel-update-agents-md [--dry-run] [--output PATH]
#   flywheel-update-agents-md path
#   flywheel-update-agents-md deploy (--codex-global | --workspace | --root | --project DIR | --to PATH)
#
# Commands:
#   (default)      Generate/refresh the canonical guide under ~/.acfs/docs/
#   path           Print the canonical guide path
#   deploy TARGET  Copy the canonical guide to a real instruction surface.
#                  Creates the destination only when absent. On collision the
#                  destination is left untouched and a merge candidate is
#                  written next to it as <dest>.acfs-new.
#
# Options:
#   --output PATH  Write the generated guide to PATH instead of the canonical
#                  location (explicit destinations are honored as-is)
#   --dry-run      Print the generated guide to stdout instead of writing
#
# Deploy targets:
#   --codex-global   ~/.codex/AGENTS.md   (Codex global instruction scope)
#   --project DIR    DIR/AGENTS.md        (project-root instruction file)
#   --workspace      /data/projects/AGENTS.md (workspace-root convention)
#   --root           /AGENTS.md           (legacy; not auto-discovered by
#                                          agent harnesses; needs root perms)
#   --to PATH        arbitrary explicit destination
#
# Exit codes:
#   0  Success
#   1  Write failed
#   2  Usage error / missing prerequisites
#   3  Deploy collision (destination exists and differs; candidate written)

set -euo pipefail

# --- Target-user context resolution ---
# When run via sudo, root's restricted PATH hides user-local tools
# (~/.local/bin, ~/go/bin, ...). Resolve the real target user and prepend
# that user's tool directories so the tool inventory is accurate.
resolve_target_user() {
    local user="${ACFS_TARGET_USER:-${SUDO_USER:-}}"
    if [[ -z "$user" || "$user" == "root" ]]; then
        user="$(id -un)"
    fi
    echo "$user"
}

resolve_target_home() {
    local user="$1"
    local home="${ACFS_TARGET_HOME:-}"
    if [[ -n "$home" && "$home" == /* && "$home" != "/" ]]; then
        echo "${home%/}"
        return 0
    fi
    home="$(getent passwd "$user" 2>/dev/null | cut -d: -f6)" || home=""
    if [[ -z "$home" ]]; then
        if [[ "$user" == "$(id -un)" ]]; then
            home="${HOME:-}"
        fi
    fi
    if [[ -z "$home" || "$home" == "/" || "$home" != /* ]]; then
        echo "ERROR: Unable to resolve home directory for user '$user'" >&2
        return 2
    fi
    echo "${home%/}"
}

TARGET_USER="$(resolve_target_user)"
TARGET_HOME="$(resolve_target_home "$TARGET_USER")"

# Prepend the target user's tool directories (mirrors the installer's
# run_as_target PATH prefix) so `command -v` sees user-local installs even
# when this script runs as root.
PATH="$TARGET_HOME/.local/bin:$TARGET_HOME/.acfs/bin:$TARGET_HOME/.cargo/bin:$TARGET_HOME/.bun/bin:$TARGET_HOME/.atuin/bin:$TARGET_HOME/go/bin:$PATH"
export PATH

CANONICAL_DIR="$TARGET_HOME/.acfs/docs"
CANONICAL="$CANONICAL_DIR/flywheel-agent-guide.md"

# Fix ownership when running as root so the target user owns the output.
fix_ownership() {
    local path="$1"
    if [[ $EUID -eq 0 && "$TARGET_USER" != "root" ]]; then
        chown "$TARGET_USER:$TARGET_USER" "$path" 2>/dev/null || true
    fi
}

# --- Argument parsing ---
MODE="generate"
OUTPUT=""
DRY_RUN=false
DEPLOY_DEST=""
DEPLOY_LABEL=""
DEPLOY_SCOPE=""

usage() {
    sed -n '/^# Usage:/,/^# Exit codes:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

parse_deploy_target() {
    case "${1:-}" in
        --codex-global)
            DEPLOY_DEST="$TARGET_HOME/.codex/AGENTS.md"
            DEPLOY_LABEL="Codex global instructions"
            DEPLOY_SCOPE="read by Codex for every session of user '$TARGET_USER' (global scope)"
            return 0 ;;
        --workspace)
            DEPLOY_DEST="/data/projects/AGENTS.md"
            DEPLOY_LABEL="workspace-root AGENTS.md"
            DEPLOY_SCOPE="a workspace convention; harnesses that walk up from a project root may read it"
            return 0 ;;
        --root)
            DEPLOY_DEST="/AGENTS.md"
            DEPLOY_LABEL="filesystem-root AGENTS.md (legacy)"
            DEPLOY_SCOPE="NOT auto-discovered by agent harnesses; legacy location only"
            return 0 ;;
        --project)
            if [[ -z "${2:-}" || ! -d "${2:-}" ]]; then
                echo "ERROR: --project requires an existing directory" >&2
                return 2
            fi
            DEPLOY_DEST="${2%/}/AGENTS.md"
            DEPLOY_LABEL="project AGENTS.md"
            DEPLOY_SCOPE="read by agents working inside ${2%/} (project scope)"
            return 3 ;;  # consumed two args
        --to)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --to requires a destination path" >&2
                return 2
            fi
            DEPLOY_DEST="$2"
            DEPLOY_LABEL="custom destination"
            DEPLOY_SCOPE="explicit path chosen by the operator"
            return 3 ;;  # consumed two args
        *)
            echo "ERROR: deploy requires a target: --codex-global | --workspace | --root | --project DIR | --to PATH" >&2
            return 2 ;;
    esac
}

case "${1:-}" in
    path)
        echo "$CANONICAL"
        exit 0 ;;
    deploy)
        MODE="deploy"
        shift
        set +e
        parse_deploy_target "$@"
        rc=$?
        set -e
        case $rc in
            0) shift ;;
            3) shift 2 ;;
            *) exit 2 ;;
        esac
        if [[ $# -gt 0 ]]; then
            echo "ERROR: unexpected extra arguments: $*" >&2
            exit 2
        fi
        ;;
esac

if [[ "$MODE" == "generate" ]]; then
    while [[ $# -gt 0 ]]; do
        case "$1" in
            generate)  shift ;;
            --output)  OUTPUT="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) echo "Unknown option: $1" >&2; exit 2 ;;
        esac
    done
fi

TIMESTAMP=$(date -Iseconds)

# --- Tool version detection ---
get_version() {
    local tool="$1"
    local path
    path=$(command -v "$tool" 2>/dev/null) || { echo "not installed"; return; }
    local ver
    ver=$("$tool" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || ver=""
    if [[ -n "$ver" ]]; then
        echo "$ver"
    else
        echo "installed (version unknown)"
    fi
}

# --- Build tool table ---
build_tool_table() {
    local tools=(
        "ntm:Named Tmux Manager:Multi-agent session orchestration (spawn, kill, send, list)"
        "br:Beads Rust:Local-first issue tracker with dependency graphs and JSONL sync"
        "bv:Beads Viewer:Graph-aware task triage and dependency visualization"
        "ru:Repo Updater:Multi-repo git sync, status, and maintenance"
        "cass:Coding Agent Session Search:Full-text search across past agent sessions"
        "cm:CASS Memory:Procedural memory system for AI coding agents"
        "caam:CLI Account Manager:Sub-100ms switching between AI coding CLI accounts"
        "slb:Simultaneous Launch Button:Two-person rule for destructive commands"
        "dcg:Destructive Command Guard:Safety net for dangerous shell commands"
        "ubs:Ultimate Bug Scanner:Automated code review and bug detection"
        "ms:Meta Skill:Claude Code skill management and generation"
        "pt:Process Triage:Process and system triage utilities"
        "apr:Automated Plan Reviser:Automated PR review and management"
        "rch:Remote Compilation Helper:Offload compilation to worker fleet"
    )

    echo "| Tool | Version | Description |"
    echo "|------|---------|-------------|"
    for entry in "${tools[@]}"; do
        IFS=':' read -r cmd name desc <<< "$entry"
        local ver
        ver=$(get_version "$cmd")
        echo "| \`$cmd\` | $ver | $desc |"
    done
}

# --- Generate content ---
generate() {
cat << 'HEADER'
# Flywheel VPS - Agent Guidelines

> This file documents the tools, workflows, and conventions for AI coding agents
> operating on this VPS. All agents should read this before starting work.

HEADER

echo "> Auto-generated: $TIMESTAMP (as user: $TARGET_USER)"
echo '> Canonical source: `~/.acfs/docs/flywheel-agent-guide.md`'
echo '> Regenerate: `flywheel-update-agents-md` (or `acfs agents update`)'
echo '> Deploy into an instruction file: `acfs agents install --help`'
echo ""

cat << 'SECTION1'
## Project Layout

All projects live under `/data/projects/`. Each project has its own git repo,
AGENTS.md, and `.beads/` directory for local issue tracking.

```
/data/projects/
  ntm/                    # Named Tmux Manager (Go)
  beads_rust/             # Issue tracker CLI (Rust)
  coding_agent_session_search/  # Session search (Rust)
  agentic_coding_flywheel_setup/  # VPS setup & scripts (Bash/TS)
  mcp_agent_mail/         # Agent coordination server (Rust)
  ...
```

## Installed Tools

SECTION1

build_tool_table
echo ""

cat << 'SECTION2'
## Common Workflows

### Starting Work on a Project

```bash
cd /data/projects/PROJECT_NAME
cat AGENTS.md                    # Read project-specific guidelines
br list --status open            # See open tasks
br show BEAD_ID                  # Get task details
br update BEAD_ID --status in_progress  # Claim task
```

### Multi-Agent Session Management

```bash
ntm spawn PROJECT [--label LABEL] [--cc N]  # Start agent session
ntm list [--project PROJECT]                 # List sessions
ntm send SESSION "message"                   # Send to session
ntm kill SESSION                             # Kill session
```

### Issue Tracking with Beads

```bash
br list --status open --status in_progress   # Active work
br show BEAD_ID                              # Full details
br update BEAD_ID --status in_progress       # Start working
br close BEAD_ID --reason "description"      # Complete task
br sync --flush-only                         # Export to JSONL
```

### Multi-Repo Maintenance

```bash
ru status                        # Check all repos
ru sync -j4                      # Pull all repos in parallel
```

### Session Archaeology

```bash
cass search "keyword"            # Search past sessions
cm recall TOPIC                  # Recall procedural memory
```

## Agent Coordination

Agents coordinate via **Agent Mail** (MCP server). Key concepts:
- Each agent registers with a project and gets a unique identity
- Messages are sent between named agents within a project
- File reservations prevent edit conflicts on shared files

## Safety Rules

1. **Never force-push to main** without explicit user approval
2. **Never commit secrets** (.env, *.key, credentials.json)
3. **Use `dcg`** — destructive commands are guarded automatically
4. **Read AGENTS.md** in each project before making changes
5. **Mark beads** as you work on them (in_progress -> closed)
6. **Run tests** before committing (go test, rch exec -- cargo test, etc.)

## Git Conventions

- Commit messages: `type(scope): description` (feat, fix, chore, docs, test, refactor)
- Always include: `Co-Authored-By: Claude <noreply@anthropic.com>`
- Push after committing — don't leave unpushed work
- Never amend published commits

SECTION2
}

# --- Content comparison that ignores the volatile timestamp line ---
content_differs() {
    local a="$1" b="$2"
    ! diff -q \
        <(grep -v '^> Auto-generated: ' "$a") \
        <(grep -v '^> Auto-generated: ' "$b") \
        > /dev/null 2>&1
}

write_canonical() {
    mkdir -p "$CANONICAL_DIR"
    fix_ownership "$CANONICAL_DIR"
    local content
    content=$(generate)
    printf '%s\n' "$content" > "$CANONICAL"
    fix_ownership "$CANONICAL"
    echo "Generated $CANONICAL ($(printf '%s\n' "$content" | wc -l) lines)"
}

# --- Deploy: explicit, optional, non-overwriting ---
do_deploy() {
    # Always refresh the canonical source first; it is the only file ACFS owns
    # and may freely replace.
    write_canonical

    echo ""
    echo "Deploy target: $DEPLOY_LABEL"
    echo "  Destination: $DEPLOY_DEST"
    echo "  Scope:       $DEPLOY_SCOPE"

    local dest_dir
    dest_dir="$(dirname "$DEPLOY_DEST")"

    if [[ -e "$DEPLOY_DEST" ]]; then
        if ! content_differs "$CANONICAL" "$DEPLOY_DEST"; then
            echo "  Status:      up to date (content already matches the canonical guide)"
            return 0
        fi
        # Collision: never overwrite. Leave the destination untouched and
        # write an adjacent candidate for manual merging.
        local candidate="$DEPLOY_DEST.acfs-new"
        if ! cp "$CANONICAL" "$candidate" 2>/dev/null; then
            echo "ERROR: destination exists and differs, and the merge candidate could not be written: $candidate" >&2
            echo "       (insufficient permissions? re-run this exact deploy command with sudo)" >&2
            return 1
        fi
        fix_ownership "$candidate"
        echo "  Status:      REFUSED — destination already exists and differs"
        echo ""
        echo "  $DEPLOY_DEST was NOT modified (it may contain user-authored rules)."
        echo "  A merge candidate was written to:"
        echo "    $candidate"
        echo "  Review the differences and merge manually:"
        echo "    diff -u '$DEPLOY_DEST' '$candidate'"
        return 3
    fi

    if ! mkdir -p "$dest_dir" 2>/dev/null; then
        echo "ERROR: cannot create destination directory: $dest_dir" >&2
        echo "       (insufficient permissions? re-run this exact deploy command with sudo)" >&2
        return 1
    fi
    if ! cp "$CANONICAL" "$DEPLOY_DEST" 2>/dev/null; then
        echo "ERROR: cannot write destination: $DEPLOY_DEST" >&2
        echo "       (insufficient permissions? re-run this exact deploy command with sudo)" >&2
        return 1
    fi
    fix_ownership "$DEPLOY_DEST"
    echo "  Status:      created (destination was absent)"
    echo ""
    echo "  Future ACFS updates refresh only the canonical source; re-run this"
    echo "  deploy command whenever you want to pick up a newer guide."
    return 0
}

# --- Output ---
case "$MODE" in
    deploy)
        do_deploy
        exit $? ;;
    generate)
        if $DRY_RUN; then
            generate
            exit 0
        fi
        if [[ -n "$OUTPUT" ]]; then
            # Explicit destination: honored as-is (still no sudo, no magic).
            mkdir -p "$(dirname "$OUTPUT")"
            content=$(generate)
            printf '%s\n' "$content" > "$OUTPUT"
            fix_ownership "$OUTPUT"
            echo "Generated $OUTPUT ($(printf '%s\n' "$content" | wc -l) lines)"
        else
            write_canonical
        fi
        ;;
esac
