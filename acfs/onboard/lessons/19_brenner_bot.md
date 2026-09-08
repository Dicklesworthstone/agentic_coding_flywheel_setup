# Brenner Bot: Research Orchestration for AI Agents

**Goal:** Use brenner_bot for structured research sessions with multi-agent AI workflows.

---

## What is Brenner Bot?

Brenner Bot is a research orchestration platform inspired by Nobel laureate Sydney Brenner's scientific methodology. It coordinates multi-agent AI research sessions with systematic problem formulation and rigorous constraint-based reasoning.

**Key Features:**
- Primary source corpus with stable citation anchors (§n format)
- Multi-model syntheses from Claude, GPT, and Gemini
- Searchable quote bank for pattern identification
- Multi-agent session management via Agent Mail
- Artifact compilation with 50+ validation rules

---

## Essential Commands

### System Health

```bash
# Check installation
brenner --version

# Run diagnostics
brenner doctor
```

### Corpus Search

```bash
# Search the transcript corpus
brenner corpus search "experimental design"

# Top five hits as machine-readable output
brenner corpus search "experimental design" --limit 5 --json
```

### Building Excerpts

```bash
# Compose cited passages from specific sections
brenner excerpt build --sections 42,43,44

# Keep the passages in transcript order
brenner excerpt build --sections 42-50 --ordering chronological
```

Excerpts print as cited Markdown; add `--json` for structured output.

---

## Research Sessions

### Starting a Session

A session is an Agent Mail thread, so you name the thread, the agents, an
excerpt file, and the question:

```bash
# Launch a multi-agent research workflow
brenner session start --thread-id RS-001 --to Claude,Codex \
  --excerpt-file excerpt.md --question "hypothesis about X"

# Check on a running session (add --watch to follow it)
brenner session status --thread-id RS-001

# Compile and publish the artifact when it converges
brenner session compile --thread-id RS-001
brenner session publish --thread-id RS-001 --to Claude,Codex
```

### Session Outputs

Research sessions produce structured artifacts:
- **Hypothesis slates**: Multiple competing explanations
- **Discriminative tests**: Experiments that distinguish hypotheses
- **Assumption ledgers**: Explicit premises with verification
- **Anomaly registers**: Unexplained observations
- **Adversarial critiques**: Challenges to the framing itself

---

## Integration with Flywheel

Brenner Bot coordinates with other tools:

| Tool | Integration |
|------|-------------|
| **Agent Mail** | Durable threads between agents in sessions |
| **NTM** | Spawns parallel agent sessions |
| **Beads** | Research tasks can become tracked issues |
| **CASS** | Session history is searchable |

---

## Quick Reference

| Command | What it does |
|---------|--------------|
| `brenner --version` | Check version |
| `brenner doctor` | Run diagnostics |
| `brenner corpus search "..."` | Search transcripts |
| `brenner excerpt build --sections ...` | Build cited passages |
| `brenner session start --thread-id ...` | Start research session |
| `brenner session status --thread-id ...` | Check a session |
| `brenner session publish --thread-id ...` | Publish the artifact |

---

## Research Methodology

Brenner Bot emphasizes:

1. **Problem Formulation**: Clear statement of what you're trying to understand
2. **Discriminative Design**: Experiments that distinguish between hypotheses
3. **Third Alternative**: Always consider "both hypotheses are wrong"
4. **Constraint-Based Reasoning**: What the data rules out, not just what it suggests
5. **Scale Physics**: Verify assumptions about orders of magnitude

---

## Web Interface

The web app at brennerbot.org provides:
- Corpus browsing with full-text search
- Excerpt composition from selected sections
- Session visualization

---

*Run `brenner corpus search "experimental design"` to try the corpus!*
