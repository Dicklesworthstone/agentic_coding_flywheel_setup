# NTM: Your Agent Cockpit

**Goal:** Master NTM (Named Tmux Manager) for orchestrating agents.

---

## What Is NTM?

NTM is your **command center** for managing multiple coding agents.

It creates organized tmux sessions with dedicated panes for each agent.

---

## The NTM Tutorial

NTM has a built-in tutorial. Start it now:

```bash
ntm tutorial
```

This will walk you through the basics interactively.

---

## Essential NTM Commands

### Check Dependencies

```bash
ntm deps -v
```

Verifies all required tools are installed.

### Create a Project Session

```bash
ntm spawn myproject --cc=2 --cod=1 --agy=1
```

This creates:
- A tmux session named "myproject"
- 2 Claude Code panes
- 1 Codex pane
- 1 Gemini pane

### List Sessions

```bash
ntm list
```

### Attach to a Session

```bash
ntm attach myproject
```

### Send a Command to All Agents

```bash
ntm send myproject "Analyze this codebase and summarize what it does"
```

This sends the same prompt to **all** agents in the session!

### Send to Specific Agent Type

```bash
ntm send myproject --cc "Focus on the API layer"
ntm send myproject --cod "Focus on the frontend"
```

---

## The Power of NTM

Imagine this workflow:

1. Spawn a session with multiple agents
2. Send a high-level task to all of them
3. Each agent works in parallel
4. Compare their solutions
5. Take the best parts from each

That's the power of multi-agent development!

---

## Quick Session Template

For a typical project:

```bash
ntm spawn myproject --cc=2 --cod=1 --agy=1
```

Why this ratio?
- **2 Claude** - Great for architecture and complex reasoning
- **1 Codex** - Fast iteration and testing
- **1 Gemini** - Different perspective, good for docs

---

## Session Navigation

Once inside an NTM session:

| Keys | Action |
|------|--------|
| `Ctrl+a` then `n` | Next window |
| `Ctrl+a` then `p` | Previous window |
| `Ctrl+a` then `h/j/k/l` | Move between panes |
| `Ctrl+a` then `z` | Zoom current pane |

---

## Try It Now

```bash
# Optional but recommended: build the CASS index once before sending
# tasks. ntm send runs a duplicate-check against past agent sessions
# via cass; on a fresh install with no index, that check is a no-op
# (ntm warns and continues), but you'll get more useful dedup
# behavior after this.
#
# `cass index --full` has no bound/limit/since/timeout flag, so on a
# real, long-lived session history it can run for a very long time.
# Never run it inline here — it will block the rest of this
# walkthrough. Kick it off detached instead:
mkdir -p ~/.cache
nohup cass index --full --json > ~/.cache/cass-index-full.log 2>&1 &
disown
echo "cass index --full is running in the background."
echo "Check progress any time with: cass health --json   (see index.status)"
echo "Or: tail -f ~/.cache/cass-index-full.log"

# Create a test session. Pass --no-cass-context so spawn does not
# stall behind the still-running index above — a concurrent index
# rebuild holds a lock that CASS context injection can block on
# (this is what --no-cass-context exists for). Drop the flag once
# `cass health --json` reports index.status = "fresh".
ntm spawn test-session --cc=1 --no-cass-context

# List sessions
ntm list

# Send a simple task
ntm send test-session "Say hello and confirm you're working"

# Attach to see the result
ntm attach test-session
```

> **CASS first run:** `cass --version` works the moment cass is
> installed, but the search-backed code paths (dedup, context
> injection) need an initial index. `cass index --full` builds it —
> but the command has no bound/limit/timeout flag, so always run it
> backgrounded (see above) rather than waiting on it in the
> foreground. Poll `cass health --json` for `index.status: "fresh"`
> instead of waiting for the command to return.

---

## Next

The real power is in the command palette:

```bash
onboard 6
```
