# tmux Basics

**Goal:** Never lose work when SSH drops.

---

## What Is tmux?

tmux is a **terminal multiplexer**. It lets you:

1. Keep sessions running after you disconnect
2. Split your terminal into panes
3. Have multiple windows in one connection

---

## Essential Commands

### Start a New Session

```bash
tmux new -s myproject
```

This creates a session named "myproject".

### Detach (Leave Session Running)

Press: `Ctrl+a` then `d`

Your session continues running in the background!

### List Sessions

```bash
tmux ls
```

### Reattach to a Session

```bash
tmux attach -t myproject
```

Or just:
```bash
tmux a
```
(Attaches to the most recent session)

---

## The Prefix Key

In ACFS, the prefix key is `Ctrl+a` (not the default `Ctrl+b`).

All tmux commands start with the prefix.

---

## Splitting Panes

| Keys | Action |
|------|--------|
| `Ctrl+a` then `|` | Split vertically |
| `Ctrl+a` then `-` | Split horizontally |
| `Ctrl+a` then `h/j/k/l` | Move between panes |
| `Ctrl+a` then `x` | Close current pane |

---

## Windows (Tabs)

| Keys | Action |
|------|--------|
| `Ctrl+a` then `c` | New window |
| `Ctrl+a` then `n` | Next window |
| `Ctrl+a` then `p` | Previous window |
| `Ctrl+a` then `0-9` | Go to window number |

---

## Copy Mode (Scrolling)

| Keys | Action |
|------|--------|
| `Ctrl+a` then `[` | Enter copy mode |
| Use arrow keys or `j/k` | Scroll |
| `q` | Exit copy mode |
| `v` | Start selection |
| `y` | Copy selection |

---

## Try It Now

```bash
# Create a session
tmux new -s practice

# Split the screen
# Press Ctrl+a, then |

# Move to the new pane
# Press Ctrl+a, then l

# Run something
ls -la

# Detach
# Press Ctrl+a, then d

# Verify it's still running
tmux ls

# Reattach
tmux attach -t practice
```

---

## Why This Matters for Agents

Your coding agents (Claude, Codex, Gemini) run in tmux panes.

If SSH drops, they keep running. When you reconnect and reattach, they're still there!

---

## Next

Now let's meet your coding agents:

```bash
onboard 4
```
