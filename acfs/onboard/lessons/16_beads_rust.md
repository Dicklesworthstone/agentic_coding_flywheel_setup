# Beads Rust (br): Issue Tracking for AI Agents

**Goal:** Track tasks with dependencies using the `br` command.

---

## What is beads_rust?

beads_rust (`br`) is a local-first issue tracker designed for AI agents. Issues live in the `.beads/` directory, with JSONL exports such as `.beads/issues.jsonl` committed alongside your code.

**Key Features:**
- SQLite + JSONL hybrid storage
- Full dependency graph (blocks/blocked-by)
- Labels, priorities, comments
- JSON output for agent consumption
- Works offline, syncs on commit

> **Note:** `br` is the primary command for beads_rust issue tracking.

---

## Essential Commands

### Create an Issue

```bash
br create --title "Add user authentication" --priority 1 --labels backend
```

### List Open Issues

```bash
br list --status open
```

### Get Machine-Readable Output

```bash
br list --status open --json
```

### Find Ready Work (Unblocked Tasks)

```bash
br ready --json
```

---

## Working with Issues

### View Issue Details

```bash
br show bd-1234
```

### Update Issue Status

```bash
br update bd-1234 --status in_progress
```

### Add a Comment

```bash
br comments add bd-1234 "Found the root cause - null check missing"
```

### Close an Issue

```bash
br close bd-1234 --reason "Fixed in commit abc123"
```

---

## Managing Dependencies

### Add a Blocking Dependency

```bash
# bd-1235 cannot start until bd-1234 is done
br dep add bd-1235 bd-1234
```

### View Dependency Graph

Use `bv` (beads_viewer) for visual dependency analysis:

```bash
bv --robot-triage
```

---

## Integration with BV

Beads Viewer (`bv`) provides graph-based analysis of your issues:

```bash
# Get AI-optimized task recommendations
bv --robot-triage

# Find what to work on next
bv --robot-next

# Analyze project insights
bv --robot-insights
```

---

---

## Quick Reference

| Command | What it does |
|---------|--------------|
| `br create --title "..." -p N` | Create issue with priority |
| `br list --status open` | List open issues |
| `br ready --json` | Find unblocked tasks |
| `br show <id>` | View issue details |
| `br update <id> --status ...` | Update status |
| `br close <id> --reason "..."` | Close with reason |
| `br comments add <id> "..."` | Add a comment |
| `bv --robot-triage` | Get AI task recommendations |

---

## Common Workflow

```bash
# 1. Find what to work on
bv --robot-next

# 2. Claim the task
br update bd-1234 --status in_progress

# 3. Do the work
# ...

# 4. Close when done
br close bd-1234 --reason "Implemented in this session"
```

---

## Next Steps

- Learn about `bv` for graph visualization
- Explore `ntm` for multi-agent orchestration
- Check `am` (Agent Mail) for agent coordination

---

*Run `br ready` to see available tasks in the current project!*
