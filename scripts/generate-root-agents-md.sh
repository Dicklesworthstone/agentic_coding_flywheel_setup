#!/usr/bin/env bash
# generate-root-agents-md.sh - Generate /AGENTS.md for Flywheel VPS
#
# Creates a comprehensive AGENTS.md at /AGENTS.md that documents all
# installed flywheel tools, common workflows, and agent guidelines.
#
# Usage:
#   ./scripts/generate-root-agents-md.sh [--output PATH] [--dry-run]
#
# Options:
#   --output PATH  Write to PATH instead of /AGENTS.md (default: /AGENTS.md)
#   --dry-run      Print to stdout instead of writing file
#
# Exit codes:
#   0  Success
#   1  Write failed
#   2  Missing prerequisites

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT="/AGENTS.md"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)  OUTPUT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) echo "Usage: $0 [--output PATH] [--dry-run]"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

TIMESTAMP=$(date -Iseconds)

# --- Tool version detection ---
get_version() {
    local tool="$1"
    local path
    path=$(command -v "$tool" 2>/dev/null) || { echo "not installed"; return; }
    local ver
    ver=$("$tool" --version 2>/dev/null | head -1 | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1) || ver=""
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
        "pt:Prompt Tools:Prompt engineering utilities"
        "apr:APR:Automated PR review and management"
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

echo "> Auto-generated: $TIMESTAMP"
echo '> Regenerate: `sudo /data/projects/agentic_coding_flywheel_setup/scripts/generate-root-agents-md.sh`'
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
  mcp_agent_mail/         # Agent coordination server (Python)
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

1. **Never force-push to main/master** without explicit user approval
2. **Never commit secrets** (.env, *.key, credentials.json)
3. **Use `dcg`** — destructive commands are guarded automatically
4. **Read AGENTS.md** in each project before making changes
5. **Mark beads** as you work on them (in_progress -> closed)
6. **Run tests** before committing (go test, cargo test, etc.)

## Git Conventions

- Commit messages: `type(scope): description` (feat, fix, chore, docs, test, refactor)
- Always include: `Co-Authored-By: Claude <noreply@anthropic.com>`
- Push after committing — don't leave unpushed work
- Never amend published commits

SECTION2
}

# --- Output ---
if $DRY_RUN; then
    generate
    exit 0
fi

content=$(generate)

if [[ "$OUTPUT" == "/AGENTS.md" ]]; then
    # Writing to root requires sudo
    echo "$content" | sudo tee "$OUTPUT" > /dev/null
    sudo chmod 644 "$OUTPUT"
    sudo chown root:root "$OUTPUT"
else
    echo "$content" > "$OUTPUT"
fi

echo "Generated $OUTPUT ($(echo "$content" | wc -l) lines)"
