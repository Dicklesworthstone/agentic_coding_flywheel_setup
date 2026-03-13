# Lesson 37: Agent Settings Backup with ASB

skills:
  - asb
  - configuration
  - backup

---

# What is ASB?

If you spend time dialing in Claude Code hooks, Codex settings, Gemini config, MCP files, and editor-specific agent preferences, a reinstall can wipe out hours of careful setup.

**ASB (Agent Settings Backup)** solves that by backing up AI agent configuration folders into git-versioned repositories. That gives you:

- point-in-time recovery after bad changes
- a portable archive you can move between machines
- visible history of what changed and when
- a repeatable way to keep multiple VPS machines aligned

ASB supports **13 agent families** out of the box:

- Claude Code
- OpenAI Codex CLI
- Cursor
- Gemini CLI
- Cline
- Amp / Sourcegraph
- Aider
- OpenCode
- Factory Droid
- Windsurf
- Plandex
- Qwen Code
- Amazon Q

---

# Quick Start

First confirm the tool is installed:

```bash
asb --help
```

Then create a backup right now:

```bash
asb backup
```

`asb backup` with no agent arguments backs up every detected supported agent. The backups live under:

```bash
~/.agent_settings_backups
```

---

# Why This Matters

ASB protects you from the most common agent-config failure modes:

1. You experiment with hooks or settings and need to roll back quickly.
2. You rebuild a VPS and do not want to manually re-create every agent config.
3. You want the same agent behavior across multiple machines.
4. You need proof of what changed in a config folder over time.

This is especially useful for configuration that is easy to forget but expensive to rebuild:

- hook definitions
- MCP config files
- agent-specific settings
- project instruction files such as `CLAUDE.md`
- keybindings, prompts, and provider-specific preferences

---

# See What You Have

List backup status for every supported agent:

```bash
asb list
```

Review the history for one agent:

```bash
asb history claude
```

Check what changed since the last backup:

```bash
asb diff claude
```

Use `asb history <agent>` before restoring so you know which commit or tag you want.

---

# Restore Workflow

Restore the latest backup for one agent:

```bash
asb restore claude
```

Restore a specific backup after finding the commit in `asb history claude`:

```bash
asb restore claude b2d375c
```

You can also restore from a tag name after tagging an important snapshot:

```bash
asb restore claude pre-upgrade
```

ASB shows a preview and asks for confirmation before overwriting your current config unless you explicitly force it.

---

# Portable Backups Across Machines

Export a backup as a portable archive:

```bash
asb export claude
```

Use a custom archive filename when you want something easy to move around:

```bash
asb export claude claude-backup.tar.gz
```

Import that archive on another machine:

```bash
asb import claude-backup.tar.gz
```

This is the easiest path when you want a new VPS to inherit a known-good agent setup.

---

# Scheduling Automatic Backups

Set up recurring backups if your agent configs change often.

Daily cron job:

```bash
asb schedule --cron
```

Systemd timer with a faster cadence:

```bash
asb schedule --systemd --interval hourly
```

Check the current schedule:

```bash
asb schedule --status
```

If you prefer weekly instead of daily:

```bash
asb schedule --cron --interval weekly
```

---

# Tag Important Snapshots

Before a risky experiment, tag the current backup so you can get back to it by name:

```bash
asb tag claude pre-upgrade
```

List tags later:

```bash
asb tag claude --list
```

This is much easier to remember than a raw commit hash.

---

# Command Reference

| Goal | Command |
| --- | --- |
| Back up all detected agents | `asb backup` |
| Back up one agent | `asb backup claude` |
| Show backup status | `asb list` |
| Inspect one agent's history | `asb history claude` |
| Diff current config vs last backup | `asb diff claude` |
| Restore latest backup | `asb restore claude` |
| Restore a specific commit or tag | `asb restore claude <commit-or-tag>` |
| Export portable archive | `asb export claude claude-backup.tar.gz` |
| Import portable archive | `asb import claude-backup.tar.gz` |
| Verify backup integrity | `asb verify claude` |
| Add recurring cron backups | `asb schedule --cron` |
| Check schedule state | `asb schedule --status` |
| Tag a known-good snapshot | `asb tag claude pre-upgrade` |

---

# Summary

You've learned:

1. `asb backup` creates git-versioned snapshots of your agent configs.
2. `asb list`, `asb history`, and `asb diff` help you inspect what exists before changing anything.
3. `asb restore`, `asb export`, and `asb import` let you recover or move configs safely.
4. `asb schedule` and `asb tag` turn ASB into a long-term safety net instead of a one-off utility.
