# Lesson 35: Cross-Agent Session Resumption with CASR

skills:
  - casr
  - multi-agent
  - session-management

---

# What is CASR?

Ever started a task with Claude, hit a rate limit, and wanted to continue with Gemini without losing context? CASR handles that.

**CASR (Cross-Agent Session Resumer)** reads the session an AI coding agent already saved on disk and converts it into another agent's native session format. It preserves file context, conversation history, and task progress across provider boundaries.

---

# Checking Installation

Verify CASR is installed:

```bash
casr --help
```

---

# Listing Available Providers

See which AI agents CASR can hand off between:

```bash
casr providers
```

This shows supported agents (Claude Code, Codex CLI, Gemini CLI) and their session formats.

---

# Finding the Session to Hand Off

There is nothing to capture: agents save their sessions as they go, and
CASR discovers them. From the project directory:

```bash
casr list
```

This lists recent sessions for this project across every installed
provider (add `--all` for every workspace). Inspect one before handing it
off:

```bash
casr info <session-id> --peek
```

---

# Why CASR Matters for Agents

In multi-agent workflows, rate limits and context windows force agent switches. CASR ensures:

- No lost context when switching providers
- Task continuity across Claude, Codex, and Gemini
- Structured handoff prompts that preserve intent
- Reduced ramp-up time for the receiving agent

---

# Common Scenarios

```bash
# Find the Claude session you were working in
casr list

# Preview what converting it to Codex would do
casr resume cod <session-id> --dry-run

# Convert it and resume in Codex (target aliases: cc, cod, gmi, agy, ...)
casr resume cod <session-id>
```

If the same session ID exists in two providers, add `--source cc` to pick
the Claude one.

---

# Summary

You've learned:
1. **casr providers** - List supported agents
2. **casr list** / **casr info** - Find and inspect saved sessions
3. **casr resume <target> <session-id>** - Continue work in a different agent
4. How cross-agent handoffs maintain task continuity
