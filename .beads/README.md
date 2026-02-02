# Beads - AI-Native Issue Tracking

Welcome to Beads! This repository uses **Beads** for issue tracking - a modern, AI-native tool designed to live directly in your codebase alongside your code.

## What is Beads?

Beads is issue tracking that lives in your repo, making it perfect for AI coding agents and developers who want their issues close to their code. No web UI required - everything works through the CLI and integrates seamlessly with git.

**Learn more:** [github.com/steveyegge/beads](https://github.com/steveyegge/beads)

## Quick Start

### Essential Commands

```bash
# Create new issues
br create "Add user authentication"

# View all issues
br list

# View issue details
br show <issue-id>

# Update issue status
br update <issue-id> --status in_progress
br update <issue-id> --status done

# Sync with git remote
br sync
```

## Daemon (Optional)

Beads has an optional background daemon (`br daemon`) that auto-syncs issues with git.

In this repo, the sync branch is configured as `main`. Running the daemon while you are on a different branch can cause `.beads/issues.jsonl` to be rewritten from `main`, leaving your working tree dirty and blocking `git pull --rebase`.

Recommended workflow:
- Prefer manual sync: `br sync` (default).
- If you use the daemon, run it only while you are on `main`, or run it in local-only mode: `br daemon --start --local`.
- If `.beads/issues.jsonl` is changing unexpectedly, check/stop the daemon: `br daemon --status` / `br daemon --stop`.

### Working with Issues

Issues in Beads are:
- **Git-native**: Stored in `.beads/issues.jsonl` and synced like code
- **AI-friendly**: CLI-first design works perfectly with AI coding agents
- **Branch-aware**: Issues can follow your branch workflow
- **Always in sync**: Auto-syncs with your commits

## Why Beads?

✨ **AI-Native Design**
- Built specifically for AI-assisted development workflows
- CLI-first interface works seamlessly with AI coding agents
- No context switching to web UIs

🚀 **Developer Focused**
- Issues live in your repo, right next to your code
- Works offline, syncs when you push
- Fast, lightweight, and stays out of your way

🔧 **Git Integration**
- Automatic sync with git commits
- Branch-aware issue tracking
- Intelligent JSONL merge resolution

## Get Started with Beads

Try Beads in your own projects:

```bash
# Install Beads
curl -sSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash

# Initialize in your repo
br init

# Create your first issue
br create "Try out Beads"
```

## Learn More

- **Documentation**: [github.com/steveyegge/beads/docs](https://github.com/steveyegge/beads/tree/main/docs)
- **Quick Start Guide**: Run `br quickstart`
- **Examples**: [github.com/steveyegge/beads/examples](https://github.com/steveyegge/beads/tree/main/examples)

---

*Beads: Issue tracking that moves at the speed of thought* ⚡
