# The Flywheel Loop

**Goal:** Understand how all the tools work together.

---

## The ACFS Flywheel

This isn't just a collection of tools. It's a **compounding loop**:

```
Plan (Beads) --> Coordinate (Agent Mail) --> Execute (NTM + Agents)
      ^                                              |
      |                                              v
      +---- Remember (CASS Memory) <---- Scan (UBS) +
```

Each cycle makes the next one better.

---

## The Nine Tools (And When To Use Them)

### 1. NTM - Your Cockpit
**Command:** `ntm`

Use it to:
- Spawn agent sessions
- Send prompts to multiple agents
- Orchestrate parallel work

### 2. MCP Agent Mail - Coordination
**Command:** `am` (starts server)

Use it when:
- Multiple agents need to share context
- You want agents to "talk" to each other
- Coordinating complex multi-agent workflows

### 3. UBS - Quality Guardrails
**Command:** `ubs`

Use it to:
- Scan code for bugs before committing
- Run comprehensive static analysis
- Catch issues early

```bash
ubs .  # Scan current directory
```

### 4. CASS - Session Search
**Command:** `cass`

Use it to:
- Search across all agent session history
- Find previous solutions
- Review what agents have done

```bash
cass  # Opens TUI
```

### 5. CASS Memory (CM) - Procedural Memory
**Command:** `cm`

Use it to:
- Build persistent agent memory
- Distill learnings from sessions
- Give agents context from past work

```bash
cm context "Building an API"  # Get relevant memories
cm reflect                     # Update procedural memory
```

### 6. Beads Viewer - Task Management
**Command:** `bv`

Use it to:
- Track tasks and issues
- Kanban view of work
- Keep agents focused on goals

```bash
bv  # Opens TUI
```

### 7. CAAM - Account Switching
**Command:** `caam`

Use it when:
- You hit rate limits
- You want to switch between accounts
- Testing with different credentials

```bash
caam status         # See current accounts
caam activate claude backup-account
```

### 8. DCG - Destructive Command Guard
**Command:** `dcg`

Use it to:
- Block dangerous commands before they execute
- Test risky commands with explanations
- Add a safety net for agents in vibe mode

```bash
dcg test "git reset --hard" --explain
```

### 9. SLB - Safety Guardrails
**Command:** `slb`

Use it for:
- Dangerous commands (when you want them reviewed)
- Two-person rule for destructive operations
- Optional safety layer

---

## A Complete Workflow

Here's how a real session might look:

```bash
# 1. Plan your work
bv                              # Check tasks
bd ready                        # See what's ready to work on

# 2. Start your agents
ntm spawn myproject --cc=2 --cod=1

# 3. Set context
cm context "Implementing user authentication" --json

# 4. Send initial prompt
ntm send myproject "Let's implement user authentication.
Here's the context: [paste cm output]"

# 5. Monitor and guide
ntm attach myproject            # Watch progress

# 6. Scan before committing
ubs .                           # Check for bugs

# 7. Update memory
cm reflect                      # Distill learnings

# 8. Close the task
bd close <task-id>
```

---

## The Flywheel Effect

With each cycle:
- **CASS** remembers what worked
- **CM** distills reusable patterns
- **UBS** catches more issues
- **Agent Mail** improves coordination
- **NTM** sessions become more effective

This is why it's called a **flywheel** - it gets better the more you use it.

---

## Your First Real Task

You're ready! Here's how to start your first project:

```bash
# 1. Create a project directory
mkcd /data/projects/my-first-project

# 2. Initialize git
git init

# 3. Initialize beads for task tracking
bd init

# (Recommended) Create a dedicated Beads sync branch
# Beads uses git worktrees for syncing; syncing to your current branch (often `main`)
# can cause worktree conflicts. Once you have a `main` branch and a remote, run:
git branch beads-sync main
git push -u origin beads-sync
bd config set sync.branch beads-sync

# 4. Spawn your agents
ntm spawn my-first-project --cc=2 --cod=1 --gmi=1

# 5. Start building!
ntm send my-first-project "Let's build something awesome.
What kind of project should we create?"
```

---

## Getting Help

- **`acfs doctor`** - Check everything is working
- **`ntm --help`** - NTM help
- **`onboard`** - Re-run this tutorial anytime

---

## Next

One final lesson: keeping everything updated.

```bash
onboard 8
```

---

*The Agentic Coding Flywheel Setup - github.com/Dicklesworthstone/agentic_coding_flywheel_setup*
