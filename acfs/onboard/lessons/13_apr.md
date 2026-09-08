# Lesson 13: Refining Plans with APR

skills:
  - apr
  - planning
  - ai-tools

---

# What is APR?

Complex specifications require multiple review cycles to identify architectural issues, edge cases, and security flaws. Instead of manually running 15-20 AI review rounds, APR automates the process.

**APR (Automated Plan Reviser Pro)** orchestrates iterative specification refinement using extended AI reasoning. Early rounds fix major issues, middle rounds refine structure, later rounds polish abstractions.

---

# Checking Installation

Verify APR is installed:

```bash
apr --version
```

And check available options:

```bash
apr --help
```

---

# The Basic Workflow

APR works in numbered **rounds** against a configured workflow, not on a
loose file. The typical flow looks like this:

1. Generate an initial plan (from Claude Code or write it yourself)
2. Run `apr setup` once to point a workflow at that plan
3. Run `apr run 1`, `apr run 2`, ... to revise it round by round
4. Compare rounds, then feed the result back to Claude Code

---

# Setting Up a Workflow

Point APR at your plan with the interactive wizard:

```bash
apr setup
```

It asks for the workflow name and the plan document, and saves the answers
so later commands can use `-w NAME` (or the default workflow).

---

# Running a Revision Round

Run the first round:

```bash
apr run 1
```

APR sends the plan out for extended-reasoning review and stores the
revised version as round 1, with:
- Clearer structure
- Identified dependencies
- Potential edge cases
- More actionable steps

Add `--dry-run` to preview the bundle without sending anything.

---

# Iterative Refinement

Each round builds on the previous one. If round 1 isn't thorough enough:

```bash
apr run 2
apr run 3 --include-impl   # also send the implementation document
```

Then see what changed between rounds:

```bash
apr diff 3 2
apr stats
```

---

# A Practical Example

Here's a real workflow:

```bash
# 1. Claude Code generates initial plan
# (creates plan.md)

# 2. Point APR at it (once)
apr setup

# 3. Revise it in rounds
apr run 1
apr run 2

# 4. Review the latest round and the delta
apr show 2
apr diff 2 1

# 5. Hand it to Claude Code for implementation
apr integrate 2 --copy   # integration prompt is now on your clipboard
```

---

# Summary

You've learned:
1. **APR** turns rough plans into polished roadmaps
2. **apr setup** configures a workflow around a plan file
3. **apr run <round>** runs one revision round
4. **apr diff** / **apr show** / **apr integrate** review and hand off rounds

APR is especially useful when you want Claude Code to follow a well-structured implementation plan.
