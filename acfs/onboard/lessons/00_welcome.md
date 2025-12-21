# Welcome to ACFS

**Goal:** Understand what you have and what you're about to learn.

---

## What You Now Have

Congratulations! You've just set up a fully-armed **agentic engineering workstation**.

Here's what's installed on your VPS:

- **A beautiful terminal** with zsh, Oh My Zsh, and Powerlevel10k
- **Modern CLI tools** like lsd, bat, ripgrep, fzf, and zoxide
- **Language runtimes** for JavaScript (Bun), Python (uv), Rust, and Go
- **Three coding agents** ready to help you build:
  - Claude Code (`cc`)
  - Codex CLI (`cod`)
  - Gemini CLI (`gmi`)
- **The Dicklesworthstone stack** for agent coordination and memory

---

## The Mental Model

Think of your setup like this:

```
Your laptop (cockpit) --SSH--> VPS (the engine room)
                                 |
                                 +-- tmux sessions (persistence)
                                 |
                                 +-- coding agents (the workers)
                                 |
                                 +-- NTM (the orchestrator)
```

Your laptop is just the remote control. The real work happens on the VPS.

If your SSH connection drops? No problem. Your work continues in tmux.

---

## What This Tutorial Will Teach You

1. **Linux basics** - navigating the filesystem
2. **SSH fundamentals** - staying connected
3. **tmux essentials** - persistent sessions
4. **Agent commands** - talking to Claude, Codex, and Gemini
5. **NTM mastery** - orchestrating multiple agents
6. **The flywheel workflow** - putting it all together

---

## Ready?

Run the next lesson:

```bash
onboard 1
```

Or continue in the TUI menu.

---

*Tip: If you ever break something, you can delete this VPS and re-run ACFS. That's the beauty of VPS development!*
