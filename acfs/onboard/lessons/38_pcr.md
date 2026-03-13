# Lesson 38: Post-Compact Reminder with PCR

skills:
  - pcr
  - claude-code
  - context-management

---

# What is PCR?

Ever noticed Claude "forgetting" project rules after a long conversation? PCR fixes that.

**PCR (Post-Compact Reminder)** is a Claude Code hook that fires after context compaction. When Claude's conversation grows too long and the system compresses earlier messages, PCR injects a reminder telling Claude to re-read `AGENTS.md` before continuing.

---

# Checking Installation

PCR installs as a Claude Code hook. Check if it's active:

```bash
test -x "$HOME/.local/bin/claude-post-compact-reminder"
grep -q "claude-post-compact-reminder" ~/.claude/settings.json \
  || grep -q "claude-post-compact-reminder" ~/.config/claude/settings.json

# Optional: simulate the exact compact event payload
echo '{"session_id":"demo","source":"compact"}' | ~/.local/bin/claude-post-compact-reminder
```

If you still have a local copy of the installer script around, these are the richer health checks:

```bash
./install-post-compact-reminder.sh --status
./install-post-compact-reminder.sh --doctor
```

After installing or repairing PCR, restart Claude Code so the updated hook config is loaded.

---

# How It Works

PCR operates as a `SessionStart` hook in Claude Code with matcher `compact`:

1. Claude's context window fills up and compaction occurs
2. PCR detects the compaction event
3. PCR prints a reminder message into Claude's fresh context
4. Claude re-reads `AGENTS.md` before continuing work

---

# Why PCR Matters

Without PCR, agents lose awareness of:

- "Never delete files without permission" rules
- Active task context and bead assignments
- Project-specific conventions (e.g., "use bun, never npm")
- Safety constraints like RCH offloading requirements

---

# Configuration

PCR does **not** read `AGENTS.md` or `CLAUDE.md` itself. It emits a reminder telling Claude to re-read the project instructions after compaction.

If you want to customize that reminder, re-run the installer with a template or custom message:

```bash
./install-post-compact-reminder.sh --template minimal
./install-post-compact-reminder.sh --template detailed
./install-post-compact-reminder.sh --template checklist
./install-post-compact-reminder.sh --template default
./install-post-compact-reminder.sh --update-reminder-message "Context compacted. Read AGENTS.md now."
```

The built-in templates are:

- `minimal`: shortest mandatory reminder
- `detailed`: step-by-step instructions after compaction
- `checklist`: checkbox-style reminder for strict workflows
- `default`: the standard balanced reminder installed by default

---

# Common Scenarios

PCR runs automatically. You don't invoke it directly. It activates when:

- A long coding session triggers context compaction
- You resume a conversation after context was compressed
- The agent starts behaving as if it forgot project rules

---

# Summary

You've learned:
1. PCR is a Claude Code hook, not a daily interactive CLI
2. It fires from a `SessionStart` hook only when the event source is `compact`
3. It reminds Claude to re-read `AGENTS.md`; it does not parse project files itself
4. It prevents agents from drifting after compaction
