# Keeping Everything Updated

**Goal:** Learn how to keep your ACFS tools current.

---

## Why Updates Matter

Your VPS has 30+ tools installed. Each one gets improvements:
- Bug fixes and security patches
- New features and capabilities
- Better performance

Keeping things updated means:
- Fewer mysterious errors
- Better security
- Access to new agent features

---

## The Update Command

ACFS provides a single command to update everything:

```bash
acfs-update
```

That's it! This updates:
- System packages (apt)
- Shell tools (OMZ, P10K, plugins)
- Coding agents (Claude, Codex, Gemini)
- Cloud CLIs (Wrangler, Supabase, Vercel)
- Language runtimes (Bun, Rust, uv)

---

## Common Update Patterns

### Quick Agent Update

If you just want the latest agent versions:

```bash
acfs-update --agents-only
```

### Skip System Packages

apt updates can be slow. Skip them when you're in a hurry:

```bash
acfs-update --no-apt
```

### Preview Changes

See what would be updated without changing anything:

```bash
acfs-update --dry-run
```

### Include Stack Tools

The Dicklesworthstone stack (ntm, slb, ubs, etc.) is skipped by default because it takes longer. Include it with:

```bash
acfs-update --stack
```

---

## Automated Updates

For hands-off maintenance, use quiet mode:

```bash
acfs-update --yes --quiet
```

This runs without prompts and only shows errors.

You can add this to a cron job for weekly updates:

```bash
# Edit crontab
crontab -e

# Add this line for weekly Sunday 3am updates
0 3 * * 0 $HOME/.local/bin/acfs-update --yes --quiet >> $HOME/.acfs/logs/cron-update.log 2>&1
```

---

## Checking Update Logs

Every update is logged:

```bash
# List recent logs
ls -lt ~/.acfs/logs/updates/ | head -5

# View the most recent log
cat ~/.acfs/logs/updates/$(ls -1t ~/.acfs/logs/updates | head -1)

# Watch a running update
tail -f ~/.acfs/logs/updates/$(ls -1t ~/.acfs/logs/updates | head -1)
```

---

## Troubleshooting

### apt is locked

If you see "apt is locked by another process":

```bash
# Wait for other apt operations to finish, or:
sudo rm /var/lib/dpkg/lock-frontend
sudo dpkg --configure -a
```

### Agent update failed

Try updating directly:

```bash
# Claude
claude update --channel latest

# Codex
bun install -g --trust @openai/codex@latest

# Gemini
bun install -g --trust @google/gemini-cli@latest
```

### Shell tools won't update

Check git remote access:

```bash
git -C ~/.oh-my-zsh remote -v
```

---

## Quick Reference

| Command | What it does |
|---------|--------------|
| `acfs-update` | Update everything (except stack) |
| `acfs-update --stack` | Include stack tools |
| `acfs-update --agents-only` | Just update agents |
| `acfs-update --no-apt` | Skip apt (faster) |
| `acfs-update --dry-run` | Preview changes |
| `acfs-update --yes --quiet` | Automated mode |
| `acfs-update --help` | Full help |

---

## How Often to Update?

Recommendations:
- **Weekly**: Full update including stack
- **After issues**: If something breaks, update first
- **Before major work**: Get latest agent versions

---

## Next

Learn about managing multiple repositories with Repo Updater:

```bash
onboard 9
```

---

*Tip: Run `acfs-update --dry-run` right now to see what's out of date!*
