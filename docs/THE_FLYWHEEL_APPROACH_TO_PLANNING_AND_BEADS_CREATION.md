# The Flywheel Approach to Planning and Beads Creation

> A comprehensive guide to Jeffrey Emanuel's methodology for creating software with frontier AI models, exhaustive markdown planning, beads-based task management, and coordinated agent swarms. This revision is synthesized from the prior Claude Code session that originally created this document, the [Agentic Coding Flywheel Setup](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup) documentation, planning- and beads-related skill/background docs, [CASS](https://github.com/Dicklesworthstone/coding_agent_session_search)-mined session rituals, and X posts/threads about planning, [`br`](https://github.com/Dicklesworthstone/beads_rust), [`bv`](https://github.com/Dicklesworthstone/beads_viewer), and [Agent Mail](https://github.com/Dicklesworthstone/mcp_agent_mail).

---

## How to Read This Guide

This document serves two different audiences at once:

- **New to the Flywheel**: Read Section 0 first, then Sections 1-15 in order. That gives you the mental movie, the core workflow, and the operating loop before the later reference material.
- **Already using the tools**: Jump to Sections 8-15 if you mainly need the plan-to-beads-to-swarm workflow, or Section 24 if you want the prompt library.
- **Adapting an existing project**: Focus especially on Sections 4-9, 11-14, and 20. That is where the reasoning about plans, beads, AGENTS.md, and swarm execution is most explicit.

This document is intentionally comprehensive and exhaustive. That is useful once you are committed to the methodology, but it can feel overwhelming on a first encounter. As the Flywheel system has grown to 20+ tools, many people have said that the full setup feels like too much to absorb at once.

The important thing to understand is that there is also a gentler on-ramp: a smaller "core loop" that captures most of the value with just three tools, [Agent Mail](https://github.com/Dicklesworthstone/mcp_agent_mail) for multi-agent coordination and communication, [`br`](https://github.com/Dicklesworthstone/beads_rust) for task management, and [`bv`](https://github.com/Dicklesworthstone/beads_viewer) for graph-aware triage so agents keep choosing the highest-leverage next bead. That smaller loop is still planning-first and still begins by creating a strong markdown plan from multiple frontier-model proposals. If this guide feels like too much at first, start with [THE_FLYWHEEL_CORE_LOOP.md](/data/projects/THE_FLYWHEEL_CORE_LOOP.md) and come back to this longer document later.

This guide is about moving the hardest thinking into representations that still fit into model context windows. That is the whole game.

---

## Table of Contents

0. [If You're New: The 15-Minute Mental Model](#0-if-youre-new-the-15-minute-mental-model)
1. [The Flywheel: A Compounding Loop](#1-the-flywheel-a-compounding-loop)
2. [Philosophy: Why Planning Dominates](#2-philosophy-why-planning-dominates)
3. [Infrastructure: Setting Up the Environment](#3-infrastructure-setting-up-the-environment)
4. [Phase 0: Pre-Planning](#4-phase-0-pre-planning)
5. [Phase 1: Creating the Initial Markdown Plan](#5-phase-1-creating-the-initial-markdown-plan)
6. [Phase 2: Multi-Model Plan Synthesis](#6-phase-2-multi-model-plan-synthesis)
7. [Phase 3: Iterative Plan Refinement](#7-phase-3-iterative-plan-refinement)
8. [Phase 4: Converting the Plan into Beads](#8-phase-4-converting-the-plan-into-beads)
9. [Phase 5: Iterative Bead Polishing](#9-phase-5-iterative-bead-polishing)
10. [Phase 5b: The Idea-Wizard Pipeline (Alternative)](#10-phase-5b-the-idea-wizard-pipeline-alternative)
11. [Phase 6: The AGENTS.md File](#11-phase-6-the-agentsmd-file)
12. [Phase 7: Agent Swarm Implementation](#12-phase-7-agent-swarm-implementation)
13. [Phase 8: The Single-Branch Git Model](#13-phase-8-the-single-branch-git-model)
14. [Phase 9: Code Review Loops](#14-phase-9-code-review-loops)
15. [Phase 10: Testing and Quality Assurance](#15-phase-10-testing-and-quality-assurance)
16. [Phase 11: UI/UX Polish](#16-phase-11-uiux-polish)
17. [Phase 12: Deep Bug Hunting](#17-phase-12-deep-bug-hunting)
18. [Phase 13: Committing and Shipping](#18-phase-13-committing-and-shipping)
19. [The Complete Toolchain](#19-the-complete-toolchain)
20. [Key Principles and Insights](#20-key-principles-and-insights)
21. [Operationalizing the Method: Kernel, Operators, and Validation Gates](#21-operationalizing-the-method-kernel-operators-and-validation-gates)
22. [Observed Patterns and Lessons from Real Sessions](#22-observed-patterns-and-lessons-from-real-sessions)
23. [Practical Considerations](#23-practical-considerations)
24. [The Complete Prompt Library](#24-the-complete-prompt-library)

---

## 0. If You're New: The 15-Minute Mental Model

Most first-time readers do not get confused because the ideas are bad or vague. They get confused because three things are changing at once:

- the **artifact** you are working in
- the **entity doing the thinking**
- the **source of truth** for what happens next

This section gives you a compact mental movie you can replay while reading the rest of the guide.

### Hold These Three Sentences in Your Head

1. **The markdown plan is where the big thinking happens.**
2. **The beads are how that thinking gets packaged for execution by many agents.**
3. **The swarm is not there to invent the system; it is there to execute, review, test, and harden a system that was mostly designed already.**

If you keep those three sentences in your head, the rest of the document gets much easier to follow.

### Mental Model Glossary

| Term | Plain-English meaning | Why it matters |
|------|-----------------------|----------------|
| **Markdown plan** | A huge design document where the whole project still fits in context | This is where architecture, workflows, tradeoffs, and intent get worked out |
| **Bead** | A self-contained work unit in `br` with context, dependencies, and test obligations | This is what agents actually execute |
| **Bead graph** | The full dependency structure across all beads | This is what lets `bv` compute the right next work |
| **Plan space** | The reasoning mode where you are still shaping the whole system | This is the cheapest place to buy correctness |
| **Bead space** | The reasoning mode where you are shaping executable work packets | This is where planning becomes swarm-ready |
| **Code space** | The implementation and verification layer inside the codebase | This is where local execution happens |
| **`AGENTS.md`** | The operating manual every agent must reload after compaction | This keeps the swarm from forgetting how to behave |
| **Skill** | A reusable instruction bundle, usually packaged as a `SKILL.md`-style artifact, that teaches agents how to use a tool or execute a workflow well | This is how methods become repeatable instead of staying as tacit lore |
| **Agent Mail** | The shared messaging and file-reservation layer | This is how agents coordinate without stepping on each other |
| **`bv`** | The graph-theory routing tool for beads | This keeps agents from choosing work randomly |
| **Compaction** | Context compression inside a long-running agent session | This is why re-reading `AGENTS.md` is mandatory |
| **Fungible agents** | Generalist agents that can replace one another | This makes crashes and amnesia survivable |
| **[CASS](https://github.com/Dicklesworthstone/coding_agent_session_search) / [CM](https://github.com/Dicklesworthstone/cass_memory_system)** | Session history and procedural memory | This is how the workflow learns from itself over time |
| **[`rch`](https://github.com/Dicklesworthstone/remote_compilation_helper)** | The offloading layer for heavy builds/tests | This prevents local CPU contention from degrading the swarm |

### One Complete Flywheel Run

Use this tiny example project as a running case study while you read:

> **Atlas Notes**: a small internal web app where a team uploads Markdown notes, tags them, searches them, and reviews ingestion failures in an admin screen.

We will keep returning to Atlas Notes in Sections 5, 8, 12, and 18 so the methodology stays tied to one concrete project instead of dissolving into abstractions.

Here is what one complete Flywheel run looks like at a high level:

1. **Human intent arrives.**  
   The human says: "I want a simple internal app for uploading and searching team notes. It should feel fast, make ingestion failures visible, and be easy for non-technical users."

2. **The first markdown plan gets expanded.**  
   Before any code exists, the plan spells out workflows like upload, parse, tag, search, and admin review. It also captures constraints like performance, authentication, and failure handling.

3. **Competing models improve the plan.**  
   GPT Pro, Claude, Gemini, and others produce alternative versions. The strongest ideas get merged into one much better plan.

4. **The plan turns into beads.**  
   Instead of one vague task like "build Atlas Notes," the plan becomes many self-contained beads:
   - `br-101`: upload + parse pipeline
   - `br-102`: search index and query UX
   - `br-103`: ingestion failure dashboard
   - `br-104`: auth and permission model
   - `br-105`: e2e coverage for upload/search/admin flows

5. **The beads get polished before implementation.**  
   Agents cross-check each bead against the plan, expand missing rationale, tighten dependencies, and add explicit test obligations.

6. **The swarm launches.**  
   Agents read `AGENTS.md`, register with Agent Mail, inspect the codebase, claim beads, reserve files, and use `bv` to choose work that unlocks the most downstream progress.

7. **The human tends flow, not code details.**  
   The human checks for stuck beads, sends review prompts, handles compactions, and occasionally updates beads when reality reveals something that planning missed.

8. **Reviews, tests, [UBS](https://github.com/Dicklesworthstone/ultimate_bug_scanner), and shipping happen.**  
   The swarm self-reviews, cross-reviews, writes tests, runs quality gates, commits, pushes, and then CASS captures the session history so the next swarm starts smarter.

That is the whole movie. The rest of the guide zooms into each stage.

### The Representation Ladder

The easiest way to stay oriented is to know what artifact is "in charge" at each moment.

| Stage | Primary artifact | Source of truth right now | Main question being answered | Exit signal | What comes next |
|-------|------------------|---------------------------|------------------------------|-------------|-----------------|
| Intent shaping | Human notes / prompts | The human's goals and workflows | What are we trying to build and why? | Workflows and constraints are explicit enough to plan | Markdown planning |
| Planning | Markdown plan | The plan document | What should the whole system be? | The plan is comprehensive and converged enough to translate | Plan-to-beads conversion |
| Translation | `br` beads under construction | The emerging bead graph, checked against the plan | How do we convert design into executable work packets without losing meaning? | Every important plan element is represented in beads | Bead polishing |
| Execution prep | Polished bead graph + `AGENTS.md` | Beads, dependencies, and operating rules | Can a fresh swarm execute this without guessing? | Beads are self-contained and launch-ready | Swarm launch |
| Swarm implementation | Code + bead state + Agent Mail threads | Current codebase plus bead/thread state | Is implementation progressing coherently? | Beads close cleanly and reviews stop finding major issues | Deep review and shipping |
| Hardening / shipping | Tests, UBS results, commit history, remaining beads | Verified code plus issue status | Is the project actually ready to land? | Quality gates pass and remaining work is captured | Memory / next cycle |
| Memory / improvement | CASS sessions, CM rules, updated skills and AGENTS docs | Distilled lessons from real usage | What should the next swarm inherit automatically? | Reusable artifacts updated | Better next project |

### Where the Rest of the Guide Zooms In

If the mental movie above already makes sense, this is how the rest of the document maps onto it:

| If you want to understand... | Go to... |
|------------------------------|----------|
| why planning dominates and why this is a flywheel | Sections 1-2 |
| how to bootstrap the environment and prepare the project | Sections 3-4 |
| how the markdown planning loop actually works | Sections 5-7 |
| how plans become beads and how beads get polished | Sections 8-10 |
| how agents stay aligned after compaction and during swarm execution | Sections 11-15 |
| how polish, deep review, shipping, and hardening work | Sections 16-18 |
| how the tools, method contract, and prompt corpus fit together | Sections 19-24 |

### The Core Five Prompts You'll Use First

The full prompt library is later in Section 24. But for a first successful run, most people only need these five categories in their head:

| Prompt family | What it does | Why it matters |
|---------------|--------------|----------------|
| **Kickoff / marching orders** | Gets a fresh agent oriented, registered, and working | Prevents passive agents and communication purgatory |
| **Plan to beads** | Converts the markdown plan into self-contained executable work units | This is where planning becomes swarm-ready |
| **Bead polishing** | Expands and stress-tests the bead graph before coding starts | This is where a good project stops being fragile |
| **Self-review** | Forces the author to re-read its own code with fresh eyes | This catches cheap bugs immediately |
| **Deep review** | Alternates cross-agent criticism with random code exploration | This catches the bugs local implementation review misses |

Keep reading if you want to understand why those prompts work. Jump to Section 24 if you want their full verbatim text.

---

## 1. The Flywheel: A Compounding Loop

It is a **compounding loop** built around moving work through the right representation at the right time.

At a high level:

1. The human clarifies goals, workflows, tradeoffs, and constraints.
2. Frontier models help turn that into a large but coherent markdown plan.
3. That plan is converted into a dependency-structured bead graph rich enough to stand on its own.
4. A fungible swarm executes those beads in a shared workspace using Agent Mail for coordination and `bv` for routing.
5. Reviews, tests, UBS, CASS, and memory tooling feed lessons back into the next plan.

The flywheel looks like this:

```
Human Intent -> Markdown Plan -> Beads -> Swarm Execution
      ^                                  |
      |                                  v
      +---- Memory / QA / Tooling <--- Reviews / Tests / UBS
```

It behaves like a flywheel rather than a checklist for a few reasons:

- **Planning quality compounds** because you keep reusing prompts, patterns, and reasoning structures that CASS proves actually worked.
- **Execution quality compounds** because better beads make swarm behavior more deterministic and less dependent on ad hoc human steering.
- **Tool quality compounds** because agents use the tools, complain about them, and then help improve them.
- **Memory compounds** because the results of one swarm become training data, rituals, and infrastructure for the next one.

The key supporting pieces:

- **Markdown plans** are the whole-system reasoning artifact.
- **Beads (`br`)** are the executable task graph.
- **AGENTS.md** is the shared operating manual every agent can reload after compaction.
- **Agent Mail** is the coordination layer.
- **`bv`** is the graph-theoretic routing layer.
- **[NTM](https://github.com/Dicklesworthstone/ntm)** is the launch and lifecycle layer.
- **CASS / CM / UBS** are the memory, pattern-extraction, and quality-feedback layers.

> "More agents -> more sessions -> better memory -> better coordination -> safer speed -> better output -> more sessions."

Each successful cycle makes the next one faster, safer, and less dependent on improvisation. That is the flywheel effect.

---

## 2. Philosophy: Why Planning Dominates

The central thesis of the Flywheel approach is that **85%+ of your time, attention, and energy should go into planning**, not implementation. This feels wrong the first time you do it because there is a long stretch where little or no code is written. But that is precisely why it works: the expensive thinking happens while the project still fits inside the model's head.

### The Core Insight

> "The models are far smarter when reasoning about a plan that is very detailed and fleshed out but still trivially small enough to easily fit within their context window. This is really the key insight behind my obsessive focus on planning and why I spent 80%+ of my time on that part."

A markdown plan, even a massive 6,000-line one, is still vastly smaller than the codebase it describes. When models reason about a plan instead of raw implementation, they can hold the whole system in their context window at once. Once you start turning that plan into code, the system rapidly becomes too large to understand holistically.

Planning is front-loaded because **you are doing global reasoning while global reasoning is still possible**.

### Human Leverage Is Front-Loaded

One of the recurring themes across the source material is that planning remains the most human, highest-leverage part of the workflow.

> "The planning is something I still do in a pretty manual way because I think it's where you have the biggest impact on the entire process."

> "The plan creation is the most free form, creative, human part of the process."

The human is not there to hand-author every line of the plan. The human is there to inject intent, judgment, taste, product sense, and strategic direction at the point where those qualities affect the entire downstream system. Once the plan is excellent, the rest becomes much more mechanical.

### Plan Space, Bead Space, and Code Space

The methodology makes more sense if you separate it into three reasoning spaces:

| Space | Primary artifact | What you decide there | Why it belongs there |
|-------|------------------|-----------------------|----------------------|
| **Plan space** | Large markdown plan | Architecture, features, workflows, tradeoffs, sequencing, rationale | Whole system still fits in context |
| **Bead space** | `br` issues + dependencies | Task boundaries, execution order, embedded context, test obligations | Distributed agents need explicit, local work units |
| **Code space** | Source files + tests | Actual implementation and verification | The plan has already constrained most high-level decisions |

Plan space is where you figure out what the system should be.

Bead space is where you turn that into **executable memory**: a graph of self-contained work units detailed enough that agents do not have to keep consulting the full plan.

Code space is where agents implement, review, test, and iterate locally without pretending they can continuously keep the entire product in their head.

### Why This Prevents Slop

Another recurring point from the X posts is that this workflow prevents the models from drifting into generic, over-engineered, or incoherent output:

> "This workflow is what prevents it from generating slop. I spend 85% of my time and energy in the planning phases."

Without this front-loaded planning, agents are effectively improvising architecture from a narrow local window into the codebase. That is exactly when you get placeholder abstractions, missing workflow details, contradictory assumptions, and compatibility shims that nobody actually wanted.

With a detailed plan and polished beads, the models are no longer inventing the system from scratch while coding. They are executing a constrained, coherent design.

### The Economic Argument

Planning tokens are far fewer and cheaper than implementation tokens. A big, complex markdown plan is shorter than a few substantive code files, let alone a whole project. That means:

- you can afford many more refinement rounds in planning than in implementation
- each planning round evaluates system-wide consequences, not just local code edits
- each improvement to the plan gets amortized across every downstream bead and code change

The methodology is comfortable spending hours in planning because it is the cheapest place to buy correctness, coherence, and ambition.

### The Woodworking Maxim, Revised

> "The old woodworking maxim of 'Measure twice, cut once!' is worth revising as 'Check your beads N times, implement once,' where N is basically as many as you can stomach."

### V1 Is Not Everything

A common misconception is that you have to do everything in one shot. In this approach, that's true only for version 1. Once you have a functioning v1, adding new features follows the same process: create a super detailed markdown plan for the new feature, turn it into beads, and implement. The same process that creates the initial version also handles all subsequent iterations.

### Debates Belong in Planning, Not Implementation

> "Arguably you should be doing the debates internally in the planning stages so that they can just execute the beads, but sometimes things come up during implementation that weren't anticipated."

That is the posture of the workflow. Implementation can still surface surprises, but as many important disagreements as possible should happen before the swarm is burning expensive implementation tokens.

---

## 3. Infrastructure: Setting Up the Environment

### ACFS: The One-Liner Bootstrapper

The [Agentic Coding Flywheel Setup (ACFS)](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup) is a "Rails installer" for agentic engineering. A beginner with a credit card and a laptop can:

1. Visit the wizard website at [agent-flywheel.com](https://agent-flywheel.com/)
2. Follow step-by-step instructions to rent a VPS (~$40-56/month)
3. Paste **one `curl|bash` command**
4. Type `onboard` and learn the workflow
5. Start vibe coding with AI agents immediately

The installer is idempotent (safe to re-run), checkpointed (resumes on failure), and handles connection drops. It installs the complete Dicklesworthstone stack of 10 tools plus all coding agent CLIs.

### The VPS Environment

| Aspect | Value |
|--------|-------|
| User | `ubuntu` |
| Shell | zsh (with oh-my-zsh + powerlevel10k) |
| Workspace | `/data/projects` |
| Sudo | Passwordless (vibe mode) |
| Tmux prefix | `Ctrl-a` |

### Vibe Mode Agent Aliases

```bash
alias cc='NODE_OPTIONS="--max-old-space-size=32768" claude --dangerously-skip-permissions'
alias cod='codex --dangerously-bypass-approvals-and-sandbox'
alias gmi='gemini --yolo'
```

### Bootstrapping a New Project

Use `acfs newproj` to create a project with full tooling:

```bash
acfs newproj myproject --interactive
```

This creates:
```
myproject/
├── .git/              # Git repository initialized
├── .beads/            # Local issue tracking (br)
├── .claude/           # Claude Code settings
├── AGENTS.md          # Instructions for AI agents
└── .gitignore         # Standard ignores
```

`acfs newproj` prepares the project structure; `ntm spawn` starts agents.

---

## 4. Phase 0: Pre-Planning

Before writing the plan itself, several foundational decisions need to be made.

### Define Goals, Intent, and Workflows

The most critical input to the planning process is a clear articulation of:

- **What** the software is supposed to do
- **Why** it exists: the overarching goals
- **How** the user interacts with it: the complete user workflows

> "When prompting the model to create the initial markdown plan version, I spend a lot of time explaining the goals and intent of the project and detailing the workflows. That is, how you want the final software to work from the standpoint of the user's interactions. The more the model understands about what it is you're really trying to accomplish and the end goal and why, it can do a better job for you."

### Choose the Tech Stack

Usually this is known ahead of time based on the type of project:

- **Web apps**: TypeScript, Next.js 16, React 19, Tailwind, Supabase, with performance-critical parts in Rust compiled to WASM
- **CLI tools**: Golang or Rust (Rust for very performance-critical tools)

If the stack isn't obvious, do a deep research round with GPT Pro or Gemini and have them study all the relevant libraries and make a suggestion taking your goals into account.

### Prepare Best Practices Guides

Keep best practices guides in the project folder and reference them in the AGENTS.md file. These guides should be kept up to date. You can have Claude Code search the web and update them to the latest versions.

Example collection: https://github.com/Dicklesworthstone/claude_code_agent_farm/tree/main/best_practices_guides

### Build the Foundation Bundle

One useful way to think about pre-planning is that you are assembling a **foundation bundle** before the plan ever starts. Across the source material, the recurring ingredients are:

- a coherent tech stack
- an initial architectural direction
- a strong `AGENTS.md`
- up-to-date best-practices guides
- enough product/workflow explanation for the models to understand what "good" looks like

Weak foundations leak uncertainty into every later stage. One X reply puts it well:

> "You need a good foundation, a good and coherent tech stack and project architecture, a good AGENTS dot md file, best practice guides, and good planning documents."

If any of those are missing, the plan will silently absorb ambiguity that later shows up as bad beads, confused agents, and sloppy implementation.

In practice, a strong bootstrap move is to start every new project by copying the `AGENTS.md` from [`destructive_command_guard`](https://github.com/Dicklesworthstone/destructive_command_guard), i.e. `/dp/destructive_command_guard/AGENTS.md`, into the new repo. At the beginning, you usually do not yet know all the project-specific rules. You still need the general behavioral rules, safety notes, tool blurbs, and coordination guidance from minute one. Later, once the plan and beads are clearer, you ask agents to replace the destructive-command-guard-specific content with the new project's actual tech stack, workflows, and architecture while preserving the general rules and tooling notes that should carry across projects.

---

## 5. Phase 1: Creating the Initial Markdown Plan

### The Human Part

> "The plan creation is the most free form, creative, human part of the process. I just usually start writing in a messy stream of thought way to convey the basic concept and then collaboratively work the agent to flesh it out in an initial draft."

You do not need to write the initial plan yourself line by line. You can simply explain what you want to make to a frontier model. The key is conveying the concept, goals, user workflows, and success criteria clearly.

What remains manual is the **highest-leverage direction-setting**:

- what the product should feel like
- which tradeoffs are acceptable
- which workflows matter most
- which ideas from model output are actually good versus merely plausible

That is why the workflow still treats planning as the part where the human has the biggest impact on the final result.

### Using GPT Pro for Initial Drafts

GPT Pro with Extended Reasoning in the web app is the recommended tool for creating the initial plan. The "all-you-can-eat" nature of the Pro subscription means you can iterate extensively without worrying about costs.

> "No other model can touch Pro on the web when it's dealing with input that easily fits into its context window. It's truly unique."

Claude Opus in the web app is also good for this, but GPT Pro remains the top choice for initial planning.

### Multi-Model Initial Plans

For the best results, ask multiple frontier models to independently create plans for the same project:

1. **GPT Pro** (with Extended Reasoning)
2. **Claude Opus** (in the web app)
3. **Gemini** (with Deep Think enabled)
4. **Grok Heavy**

Each model brings different strengths and perspectives. The goal is to generate diverse raw material that will be synthesized in the next phase.

### What This Looks Like in Practice

From session history: plans are typically stored as similarly-named markdown files in the project directory (e.g., `competing_proposal_plans/claude_version/`, `competing_proposal_plans/gpt_version/`, etc.). This pattern has been observed across at least 10 sessions spanning 7+ projects including ntm, destructive_command_guard, vibe_cockpit, mcp_agent_mail_rust, and frankensqlite.

In the CASS Memory System project, the competing plans are publicly visible:
https://github.com/Dicklesworthstone/cass_memory_system/tree/main/competing_proposal_plans

### Running Case Study: What the First Plan Actually Looks Like

Returning to the **Atlas Notes** example from Section 0, the first serious markdown plan would not say "build a notes app." It would start spelling out the actual user-visible system, for example:

```markdown
- Users upload Markdown files through a drag-and-drop UI.
- The system parses frontmatter tags and stores upload failures for review.
- Search must support keyword, tag, and date filtering with low perceived latency.
- Admins need a dedicated screen showing ingestion failures, parse reasons, and retry actions.
- Auth is internal-only; unauthorized users must never see document content or metadata.
- We need e2e coverage for upload success, upload failure, search, filtering, and admin review.
```

That is still only the beginning of the plan. But it already shows the key difference between ordinary brainstorming and Flywheel planning: the plan is trying to make the whole product legible before any code exists.

---

## 6. Phase 2: Multi-Model Plan Synthesis

Once you have competing plans from multiple models, synthesize them into a single superior plan. This is done using GPT Pro as the "final arbiter."

### The Synthesis Prompt

```
I asked 3 competing LLMs to do the exact same thing and they came up with
pretty different plans which you can read below. I want you to REALLY
carefully analyze their plans with an open mind and be intellectually honest
about what they did that's better than your plan. Then I want you to come up
with the best possible revisions to your plan (you should simply update your
existing document for your original plan with the revisions) that artfully
and skillfully blends the "best of all worlds" to create a true, ultimate,
superior hybrid version of the plan that best achieves our stated goals and
will work the best in real-world practice to solve the problems we are
facing and our overarching goals while ensuring the extreme success of the
enterprise as best as possible; you should provide me with a complete series
of git-diff style changes to your original plan to turn it into the new,
enhanced, much longer and detailed plan that integrates the best of all the
plans with every good idea included (you don't need to mention which ideas
came from which models in the final revised enhanced plan):
```

This is the signature phrase of the methodology: **"best of all worlds."** It appears in 10+ distinct sessions across 7+ projects in the session archive.

### How to Integrate the Synthesis

Take GPT Pro's output (the git-diff style revisions) and paste it into Claude Code or Codex with:

```
OK, now integrate these revisions to the markdown plan in-place; be
meticulous. At the end, you can tell me which changes you wholeheartedly
agree with, which you somewhat agree with, and which you disagree with:

[Pasted synthesis output]
```

This step has Claude Code actually modify the plan file while also providing its own critical assessment of the changes.

### Real-World Pitfall

In the destructive_command_guard sessions, agents occasionally got stuck between plan revision and bead operationalization: the competing plan was revised but no beads were created. Always ensure the synthesis step concludes with an explicit transition to Phase 3 or Phase 4.

---

## 7. Phase 3: Iterative Plan Refinement

After the initial synthesis, the plan goes through multiple rounds of refinement. This is where the plan transforms from good to great.

### The Refinement Prompt

```
Carefully review this entire plan for me and come up with your best
revisions in terms of better architecture, new features, changed features,
etc. to make it better, more robust/reliable, more performant, more
compelling/useful, etc. For each proposed change, give me your detailed
analysis and rationale/justification for why it would make the project
better along with the git-diff style changes relative to the original
markdown plan shown below:

<PASTE YOUR EXISTING COMPLETE PLAN HERE>
```

### The Refinement Loop

1. Paste the current plan into a **fresh** GPT Pro conversation with the refinement prompt
2. Take GPT Pro's output and have Claude Code or Codex integrate the revisions in-place
3. Repeat with a **fresh** conversation each time

> "This has never failed to improve a plan significantly for me. The best part is that you can start a fresh conversation in ChatGPT and do it all again once Claude Code or Codex finishes integrating your last batch of suggested revisions."

### The "Lie to Them" Technique

A powerful hack for ensuring thoroughness during revision: models tend to stop looking for problems after finding a "reasonable" number (typically ~20-25). If you tell them to find "all" problems, they stop early. The solution:

> "If you tell it to find 'all' of the problems, because it doesn't know how many it missed, it tends to just go until it has found a lot of them. If you tell it to go until it has found at least 20 of them, it will usually come back after it has found 23 problems/mismatches. Anyway, the solution is to lie to them and give them a huge number, and then they keep cranking until they've uncovered all of them."

The prompt:

```
Do this again, and actually be super super careful: can you please check
over the plan again and compare it to all that feedback I gave you? I am
positive that you missed or screwed up at least 80 elements of that
complex feedback.
```

By claiming 80+ errors exist, the model keeps searching exhaustively rather than satisfying itself with a partial list. This works for plan revisions, bead-to-plan cross-references, and any comparison/audit task.

### Convergence

After 4-5 rounds, the suggestions become very incremental and you reach a steady state. This is when the plan is ready for conversion to beads.

In practical terms, the handoff decision is this:

- stay in plan refinement if whole-workflow questions are still moving around, major architecture debates are still open, or fresh models keep finding substantial missing features, constraints, or tradeoffs
- switch to beads when the plan mostly feels stable and the remaining improvements are about execution structure, testing obligations, sequencing, and embedded context rather than about what the system fundamentally is

That is the key threshold. If you are still redesigning the product, stay in plan space. If you are mainly packaging the work for execution, move to bead space.

### Real-World Example

For the Cass GitHub Pages export feature, the plan went through multiple rounds over about 3 hours, growing to approximately 3,500 lines. The revisions in GitHub show massive improvements from v2 to v3, with improvements continuing all the way to the end:

https://github.com/Dicklesworthstone/coding_agent_session_search/blob/main/PLAN_TO_CREATE_GH_PAGES_WEB_EXPORT_APP.md

### The Result: Not Slop

Plans created this way routinely reach 3,000-6,000+ lines. They are the result of countless iterations and blending of ideas and feedback from many models, not slop. Example of a 6,000-line plan:

https://github.com/Dicklesworthstone/jeffreysprompts.com/blob/main/PLAN_TO_MAKE_JEFFREYSPROMPTS_WEBAPP_AND_CLI_TOOL.md

---

## 8. Phase 4: Converting the Plan into Beads

Beads (from Steve Yegge's project) are like Jira or Linear, but optimized for use by coding agents. They represent epics, tasks, and subtasks with an explicit dependency structure, stored locally in `.beads/*.jsonl` files that commit with your code.

If you want a concrete picture of the target artifact before reading the large conversion prompt, jump briefly to [Running Case Study: What Three Good Beads Look Like](#running-case-study-what-three-good-beads-look-like) and then come back here.

### The Conversion Prompt

The canonical prompt used throughout the rest of this guide is:

```
OK so please take ALL of that and elaborate on it and use it to create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting (including relevant background, reasoning/justification, considerations, etc.-- anything we'd want our "future self" to know about the goals and intentions and thought process and how it serves the over-arching goals of the project.). The beads should be so detailed that we never nead to consult back to the original markdown plan document. Remember to ONLY use the `br` tool to create and modify the beads and add the dependencies.
```

Older sessions sometimes used a shorter variant like this:

```
OK so please take ALL of that and elaborate on it more and then create a
comprehensive and granular set of beads for all this with tasks, subtasks,
and dependency structure overlaid, with detailed comments so that the whole
thing is totally self-contained and self-documenting (including relevant
background, reasoning/justification, considerations, etc.-- anything we'd
want our "future self" to know about the goals and intentions and thought
process and how it serves the over-arching goals of the project.) Use only
the `br` tool to create and modify the beads and add the dependencies.
```

For existing projects with a specific plan file:

```
OK so now read ALL of PLAN_FILE_NAME.md; please take ALL of that and
elaborate on it and use it to create a comprehensive and granular set of
beads for all this with tasks, subtasks, and dependency structure overlaid,
with detailed comments so that the whole thing is totally self-contained and
self-documenting (including relevant background, reasoning/justification,
considerations, etc.-- anything we'd want our "future self" to know about
the goals and intentions and thought process and how it serves the
over-arching goals of the project.). The beads should be so detailed that we
never need to consult back to the original markdown plan document. Remember
to ONLY use the `br` tool to create and modify the beads and add the
dependencies.
```

### The Two-Stage Process

There's a critical distinction between plan-level and bead-level work:

> "No, there are two separate stages of doing this. The first is in the markdown plan itself, then you convert that to initial beads, then you do it again and again on the beads themselves to ensure that they've captured all the details from the markdown document and are as perfect as possible."

The plan document and the beads are different representations with different affordances. Plans are for holistic reasoning; beads are for distributed execution. The conversion is a translation, not a copy.

> "The planning is and should be prior to and orthogonal to beads. You should always have a super detailed markdown plan first. Then treat transforming that markdown plan into beads as a separate, distinct problem with its own challenges. But once you're in 'bead space' you never look back at the markdown plan. But that's why it's so critical to transfer all the details over to the beads."

The practical nuance is: the markdown plan stops being the day-to-day execution artifact once the beads are strong enough, but it is still legitimate to consult it during bead polishing to prove that nothing important was lost in translation. After that audit phase, the beads become the active source of truth for execution.

> "I never have beads or beads commands in textual form as part of markdown documents. I go directly from markdown plan to actual real beads, and then from that point on it's just adding/changing actual beads."

### [Beads](https://github.com/Dicklesworthstone/beads_rust) as Executable Memory

Beads are the plan after it has been transformed into a format optimized for distributed execution.

The plan is still the best artifact for whole-system thought. But once a swarm is involved, what you need is not a beautiful essay. What you need is a task graph that carries enough local context for agents to act correctly without repeatedly loading the whole project back into memory.

For that reason, the methodology insists that most important decisions get made ahead of time and then embedded into the beads:

> "It works better if most of the decision making is made ahead of time during the planning phases and then is embedded in the beads."

If the beads are weak, the swarm becomes improvisational. If the beads are rich, the swarm becomes almost mechanical.

### Critical Design Principles for Beads

1. **Self-contained**: Beads must be so detailed that you never need to refer back to the original markdown plan. Every piece of context, reasoning, and intent from the plan should be embedded in the beads themselves.

2. **Rich content**: Beads can and should contain long descriptions with embedded markdown. They don't need to be short bullet-point entries. Design decisions, rationale, and background should live inside the beads.

3. **Complete coverage**: Everything from the markdown plan must be embedded into the beads. You should lose nothing in the conversion.

4. **Dependency structure**: The dependency graph between beads must be explicit and correct. This is what enables agents to use `bv` to determine the optimal order of work.

5. **Include testing**: Beads should include comprehensive unit tests and e2e test scripts with great, detailed logging.

6. **Beads are for agents**: The models are the primary consumer of beads, not humans. You can always have agents interpret beads back into markdown if needed. "Conceptually, the beads are more for them than for you."

### [Beads](https://github.com/Dicklesworthstone/beads_rust) CLI Reference

```bash
br create --title "..." --priority 2 --label backend    # Create issue
br list --status open --json                             # List open issues
br ready --json                                          # Show unblocked tasks
br show <id>                                             # View issue details
br update <id> --status in_progress                      # Claim task
br close <id> --reason "Completed"                       # Close task
br dep add <id> <other-id>                               # Add dependency
br comments add <id> "Found root cause..."               # Add comment
br sync --flush-only                                     # Export to JSONL (no git ops)
```

Key concepts:
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers)
- **Types**: task, bug, feature, epic, question, docs
- **Dependencies**: `br ready` shows only unblocked work
- **Storage**: SQLite + JSONL hybrid; JSONL files commit with code

### Scale Example

For the CASS Memory System (5,500-line plan), the conversion produced 347 beads (epics and tasks) with complete dependency structure. FrankenSQLite had hundreds of beads created via parallel subagents. Frankensearch had 122 open beads across 3 epics.

### Running Case Study: What Three Good Beads Look Like

Using **Atlas Notes** again, here is the kind of transformation you are aiming for:

- **`br-101 Upload and Parse Pipeline`**
  This bead would describe accepted file formats, frontmatter parsing expectations, where failures are logged, what happens on malformed input, and which unit and e2e tests prove the pipeline works.
- **`br-102 Search Index and Query UX`**
  This bead would carry the search behavior, indexing rules, latency expectations, filter semantics, empty-state UX, and test coverage for keyword/tag/date combinations.
- **`br-103 Ingestion Failure Dashboard`**
  This bead would include the admin workflow, permission boundaries, retry logic, logging expectations, and the exact reasons this dashboard matters for operational trust.

The titles are not the important part. What matters is that each bead is rich enough that a fresh agent can open it and immediately understand what correct implementation looks like, why it matters, and how to verify it.

---

## 9. Phase 5: Iterative Bead Polishing

This is the "check your beads N times" phase. It's the step most people underinvest in.

### The Polishing Prompt

The canonical polishing prompt is:

```
Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY! Also make sure that as part of the beads we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation.  Make sure to ONLY use the `br` cli tool for all changes, and you can and should also use the `bv` tool to help diagnose potential problems with the beads.
```

Many operators prepend an `AGENTS.md` reread, producing a common variant like this:

```
Reread AGENTS.md so it's still fresh in your mind. Check over each bead
super carefully-- are you sure it makes sense? Is it optimal? Could we
change anything to make the system work better for users? If so, revise the
beads. It's a lot easier and faster to operate in "plan space" before we
start implementing these things!

DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY!

Also, make sure that as part of these beads, we include comprehensive unit
tests and e2e test scripts with great, detailed logging so we can be sure
that everything is working perfectly after implementation. Remember to ONLY
use the `br` tool to create and modify the beads and to add the dependencies
to beads.
```

### How Many Rounds?

> "I used to only run that once or twice before starting implementation, but I experimented recently with running it 6+ times, and it kept making useful refinements."

The practical synthesis across the sessions is:

- **minimum**: 3 passes if the project is small
- **normal**: 4-6 passes for real projects
- **heavyweight / high-stakes**: keep going past 6 if fresh passes are still finding meaningful issues

The stop rule matters more than the raw number. Do not stop because you hit an arbitrary pass count; stop when the improvements have become genuinely marginal and your explicit convergence checks come back clean.

In practice, session history suggests agents typically manage 2-3 polishing passes before running out of context window. Starting fresh sessions for additional passes matters. The apollobot project had 26 beads polished through 2-3 rounds in a single session; the mcp_agent_mail_rust session explicitly notes: "I just completed... Let me do one more pass as the skill instructions say to repeat Phase 6 4-5 times."

### What Polishing Actually Does

From real sessions, bead polishing involves:

- **Duplicate detection and merging**: FrankenSQLite identified 9 exact duplicate pairs and closed them, choosing survivors based on "richer testing specs, better dependency chains, and higher priority"
- **Quality scoring**: Agents assess beads on WHAT/WHY/HOW criteria, rating each as "Excellent" or identifying gaps
- **Description filling**: Empty bead descriptions get filled via parallel subagents, each reading the relevant spec section
- **Dependency correction**: Fixing missing or incorrect dependency links
- **Coverage verification**: Cross-referencing beads against the markdown plan to ensure nothing was lost

### Cross-Reference Against the Plan

Additionally, you should tell agents to:
- Go through each bead and explicitly check it against the markdown plan
- Go through the markdown plan and cross-reference every single thing against the beads (both closed and open) to ensure complete coverage

### Fresh Eyes Technique

If improvements start to flatline, start a brand new Claude Code session:

```
First read ALL of the AGENTS.md file and README.md file super carefully and
understand ALL of both! Then use your code investigation agent mode to fully
understand the code, and technical architecture and purpose of the project.
```

Then follow up with:

```
We recently transformed a markdown plan file into a bunch of new beads. I
want you to very carefully review and analyze these using `br` and `bv`.
```

And then run the standard polishing prompt.

### Final Cross-Model Check

As a final step, have Codex with GPT (high reasoning effort) do one last round using the same polishing prompt. Different models catch different things.

### Convergence Detection: When to Stop

Bead polishing follows numerical optimization convergence patterns:

| Phase | Rounds | Character |
|-------|--------|-----------|
| Major Fixes | 1-3 | Wild swings, fundamental changes |
| Architecture | 4-7 | Interface improvements, boundary refinements |
| Refinement | 8-12 | Edge cases, nuanced handling |
| Polishing | 13+ | Converging to steady state |

Three signals indicate convergence (weighted):

| Signal | Weight | What to Check |
|--------|--------|---------------|
| Output size shrinking | 35% | Are agent responses getting shorter? |
| Change velocity slowing | 35% | Is the rate of change decelerating? |
| Content similarity increasing | 30% | Are successive rounds more similar? |

When the weighted convergence score reaches **0.75+**, you're ready to finalize. Above **0.90**, you're hitting diminishing returns. Below **0.50**, keep iterating.

**Early termination red flags:**
- **Oscillation** (alternating between two versions) -- apply the "Third Alternative" and reframe
- **Expansion** (output growing instead of shrinking) -- step back, the agent is adding complexity
- **Plateau at low quality** -- kill the current approach and restart fresh

The more complex and intricate your markdown plan is, the more relevant this technique is. If you have a small, trivial plan, it's obviously overkill.

---

## 10. Phase 5b: The Idea-Wizard Pipeline (Alternative)

For existing projects that need new features or enhancements, the **Idea-Wizard** is a formalized 6-phase pipeline that is codified as a Claude Code skill. Session history shows this being executed across many projects (frankensearch, apollobot, jeffrey_emanuel_personal_site, alien_cs_graveyard, and more).

### The 6 Phases

**Phase 1 -- Ground in reality:** Agents always start by reading AGENTS.md and listing all existing beads (`br list --json`). This is mandatory to prevent creating duplicate beads.

**Phase 2 -- Generate 30, winnow to 5:** The agent brainstorms 30 ideas for improvements, then self-selects the very best 5 with justification. In practice, this is often dispatched as a subagent task.

**Phase 3 -- Expand to 15:** Prompt the agent with "ok and your next best 10 and why." The agent produces ideas 6-15, carefully checking each against existing beads for novelty.

**Phase 4 -- Human review:** The user reviews the 15 ideas and selects which to pursue.

**Phase 5 -- Turn into beads:** Selected ideas are converted into beads with `br create` commands, including full descriptions, dependencies, and priority levels.

**Phase 6 -- Refine (repeat 4-5x):** The polishing loop from Phase 5 above. The skill's anti-pattern table explicitly warns: "Single-pass beads" is wrong -- "4-5 passes, first draft never optimal."

### When to Use Idea-Wizard vs. Full Planning

- **New project from scratch**: Full planning pipeline (Phases 0-5)
- **Adding features to an existing project**: Idea-Wizard pipeline
- **The two can combine**: Use Idea-Wizard to generate ideas, then create a full markdown plan for the selected ideas, then convert to beads

### Ad-Hoc Changes: TODO Mode vs. Formal Beads

Not every useful change begins with a full markdown plan and a polished bead graph. In actual day-to-day operation, once an agent proposes a sensible improvement, you usually choose between two paths:

1. **Formalize it into beads** if the change is substantial, touches multiple workflows, or would benefit from dependencies, reviewability, and durable project documentation.
2. **Execute it ad hoc with the built-in TODO system** if it is a quick, bounded change and the overhead of immediate bead creation would slow you down more than it helps.

The ad-hoc execution prompt is:

```
OK, please do ALL of that now. Keep a super detailed, granular, and complete TODO list of all items so you don't lose track of anything and remember to complete all the tasks and sub-tasks you identified or which you think of during the course of your work on these items!
```

This works especially well when the agent has a built-in TODO system that survives compaction. The TODO list becomes a lightweight local execution scaffold. It does not give you the graph structure or shared visibility of beads, but it is much safer than leaving a long ad-hoc task in the agent's short-term conversational memory.

If the task starts expanding, accumulating dependencies, or involving multiple agents, that is usually the signal to stop treating it as ad hoc and convert it into proper beads. If a quick ad-hoc change later matters historically, it is perfectly reasonable to retroactively create beads for the completed work so the project keeps an unbroken record of what happened and why.

---

## 11. Phase 6: The AGENTS.md File

The AGENTS.md file is the single most critical piece of infrastructure for agent coordination. Without a good one, nothing works well.

The phase numbering can mislead newcomers here, so be explicit: a baseline `AGENTS.md` should already exist much earlier as part of the foundation bundle in Phase 0. It appears here as "Phase 6" only because this is the point in the story where its operational importance becomes impossible to miss.

### What It Contains

The AGENTS.md file explains to every agent:
- All the tools available to them (br, bv, agent mail, ubs, cass, cm, etc.)
- How to use each tool with prepared blurbs
- Project-specific rules and conventions
- Safety rules (no file deletion, no destructive git commands)
- Best practices references
- What the project is and how it works

`AGENTS.md` is the swarm's durable operating manual. It tells a fresh or partially-amnesic agent how to behave, what tools exist, what safety constraints matter, how the project is supposed to work, and what "doing a good job" means in this repo.

### Bootstrap From a Known-Good Template

In real usage, a strong `AGENTS.md` usually does not get written from scratch on day one. A highly effective bootstrap pattern is:

1. copy `/dp/destructive_command_guard/AGENTS.md` into the new project
2. use that as the initial control plane while the new plan and beads are still being worked out
3. once the new project is better understood, ask agents to replace the destructive-command-guard-specific content with the new project's actual details
4. keep the general rules, safety notes, and tool blurbs that should remain common across projects

A blank or weak `AGENTS.md` creates chaos immediately. Agents need a mature default behavioral contract before they need a perfect project-specific one. Starting from the destructive-command-guard template gives them that contract from the first session.

### Core Rules (from the ACFS AGENTS.md)

1. **Rule 0 -- The Override Prerogative**: The human's instructions override everything
2. **Rule 1 -- No File Deletion**: Never delete files without explicit permission
3. **No destructive git commands**: `git reset --hard`, `git clean -fd`, `rm -rf` are absolutely forbidden
4. **Branch policy**: All work happens on `main`, never `master`
5. **No script-based code changes**: Always make code changes manually
6. **No file proliferation**: No `mainV2.rs` or `main_improved.rs` variants
7. **Compiler checks after changes**: `cargo check`, `cargo clippy`, `cargo fmt --check`
8. **Multi-agent awareness**: Never stash, revert, or overwrite other agents' changes

### Why Agents Must Constantly Re-Read It

> "That's also why I'm so insistent on ensuring that they constantly re-read the AGENTS dot md file; otherwise, they totally forget what they're doing and how to operate."

From session history, "Reread AGENTS.md" is the **single most common prompt prefix** across the entire session archive. It appears at the start of virtually every new session or post-compaction continuation. After every context compaction, agents should re-read AGENTS.md:

```
Reread AGENTS.md so it's still fresh in your mind.
```

That short line does a lot of work. It reloads the agent's operating rules, tool affordances, project norms, and coordination posture after the model has just compressed away a large amount of working context.

### Compaction Management

Context compaction is the single biggest threat to agent quality. After compaction, agents lose the nuances from AGENTS.md and start making mistakes:

> "After compaction they become like drug-addled children and all bets are off. They need to be forced to read it again or they start acting insane."

> "The main thing that's dangerous is for them to do a compaction and then not immediately reread AGENTS.md because that file contains their whole marching orders. Suddenly they're like a bumbling new employee who doesn't know the ropes at all."

The pragmatic approach: don't fight compaction, just re-read AGENTS.md and roll with it. If the agent starts doing dumb things even after re-reading, start a fresh session.

> "I used to be a compaction absolutist, but now I just tell them to re-read AGENTS.md and roll with it until they start doing dumb stuff, then start a new session."

In practice, this reread ritual is important enough that it has been automated for Claude Code with [`post_compact_reminder`](https://github.com/Dicklesworthstone/post_compact_reminder) at `/dp/post_compact_reminder`. That is a good example of a small automation attached to a validated ritual. The behavior was discovered manually first, then operationalized once it proved repeatedly necessary.

When beads are well-constructed, compaction matters less because each bead is self-contained with full context. The agent can pick up any bead fresh without needing the full conversation history.

> "Not sure exactly when the compaction happens matters that much when you use beads the way I do."

### Tool Blurbs Are Essential

Every tool in the system should come with a prepared blurb designed for inclusion in AGENTS.md. This is like the modern equivalent of a man page. Users shouldn't have to figure out how to explain the tool to agents themselves.

> "I view that as a core part of creating a new agent tool, you have to also give the blurb; it's like the new man page or something."

### Project-Specific Customization

Each project should have its own AGENTS.md that includes only the blurbs for the tools relevant to that project. Creating a new project with `acfs newproj` generates a starter AGENTS.md automatically.

### Examples

- Complex NextJS webapp + TypeScript CLI: https://github.com/Dicklesworthstone/brenner_bot/blob/main/AGENTS.md
- Bash script project: https://github.com/Dicklesworthstone/repo_updater/blob/main/AGENTS.md

### Tradeoff: Size vs. Compaction Frequency

More content in AGENTS.md means more frequent compactions, but it saves time and avoids mistakes by giving agents all the context upfront. This is a worthwhile tradeoff.

---

## 12. Phase 7: Agent Swarm Implementation

Once beads are polished, it's time to unleash the swarm.

### [NTM](https://github.com/Dicklesworthstone/ntm): The Agent Cockpit

NTM (Named Tmux Manager) is the command center for orchestrating multiple agents:

```bash
# Spawn a multi-agent session
ntm spawn myproject --cc=2 --cod=1 --gmi=1

# This creates:
# - A tmux session named "myproject"
# - 2 Claude Code panes
# - 1 Codex pane
# - 1 Gemini pane

# Send a prompt to ALL agents
ntm send myproject "Your marching orders prompt here"

# Send to specific agent type
ntm send myproject --cc "Focus on the API layer"
ntm send myproject --cod "Focus on the frontend"

# List active sessions
ntm list

# Attach to watch progress
ntm attach myproject

# Open the command palette (battle-tested prompts)
ntm palette
```

NTM is useful, but it is not mandatory. The methodology needs a way to run multiple agents, send them prompts quickly, and keep them coordinated. It does not require tmux specifically.

### What a Mux Is, and What tmux Is

A **mux** is a terminal multiplexer: a layer that lets you manage multiple shell sessions inside one higher-level session manager. In practice, that usually means some combination of tabs, panes, detached sessions, and reconnection to work that is still running on a local or remote machine.

**tmux** is the classic Unix terminal multiplexer. It is powerful, battle-tested, and widely available on remote Linux machines. NTM is built on top of tmux, which is why NTM is such a natural fit for multi-agent work.

But tmux is only one mux. WezTerm has its own built-in mux. Zellij is another mux. The method cares that you have a workable orchestration layer, not that you picked one specific brand of multiplexer.

One common alternative to NTM is to use WezTerm because native scrollback and text selection are more convenient there than in tmux. A very workable setup is:

- run agents in separate tabs using WezTerm and its built-in mux, often across remote machines
- trigger your most common prompts from a Stream Deck with the prompts preconfigured
- keep a large prompt file open in Zed and paste rarer prompts manually
- in Claude Code, use the project-specific `Ctrl-r` prompt history search when you want to recall something you already used recently

There is no single correct operator interface for this part. NTM is one good cockpit. WezTerm tabs plus mux is another. The important thing is that you can launch agents, get prompts into them quickly, monitor them, and keep the coordination layer (`AGENTS.md`, Agent Mail, beads, `bv`) intact.

[FrankenTerm](https://github.com/Dicklesworthstone/frankenterm), which is built on WezTerm, is aimed more explicitly at this style of workflow, but it is not ready yet.

For concrete setup notes on these operator environments, see:

- WezTerm persistent remote sessions: https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts#wezterm-persistent-remote-sessions
- Ghostty terminfo for remote machines: https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts#ghostty-terminfo-for-remote-machines
- Host-aware color themes for Ghostty and WezTerm: https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts?tab=readme-ov-file#host-aware-color-themes

Those guides also help explain why WezTerm is so convenient for this work. They describe its native mux as supporting persistent remote sessions that survive disconnects, sleep, or reboot, while still preserving native scrollback and text selection. They also describe Ghostty as a good terminal frontend in its own right, whether used directly or paired with another mux such as Zellij.

### Typical Swarm Composition

Why the ratio `--cc=2 --cod=1 --gmi=1`?
- **2 Claude** -- Great for architecture and complex reasoning; the workhorse
- **1 Codex** -- Fast iteration and testing; complementary strengths
- **1 Gemini** -- Different perspective; good for docs and review duty

For larger projects, scale up proportionally. The skills codify a **weighted allocation formula** based on bead backlog:

| Open Beads | Claude (cc) | Codex (cod) | Gemini (gmi) |
|-----------|-------------|-------------|--------------|
| 400+ | 4 | 4 | 2 |
| 100-399 | 3 | 3 | 2 |
| <100 | 1 | 1 | 1 |

The practical limit is around 12 agents on a single project, sometimes higher.

### The Marching Orders Prompt

Give each agent in the swarm this initial prompt:

```
First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Then register with MCP Agent Mail and introduce yourself to the other agents. Be sure to check your agent mail and to promptly respond if needed to any messages; then proceed meticulously with your next assigned beads, working on the tasks systematically and meticulously and tracking your progress via beads and agent mail messages. Don't get stuck in "communication purgatory" where nothing is getting done; be proactive about starting tasks that need to be done, but inform your fellow agents via messages when you do so and mark beads appropriately. When you're not sure what to do next, us the bv tool mentioned in AGENTS.md to prioritize the best beads to work on next; pick the next one that you can usefully work on and get started. Make sure to acknowledge all communication requests from other agents and that you are aware of all active agents and their names. *CRITICAL*: All cargo builds and tests and other CPU intensive operations MUST be done using rch to offload them!!! see AGENTS.md for details on how to do this!!!
```

### The First 10 Minutes After Launching a Swarm

Newcomers often understand each individual tool but still do not have a clean picture of the first live operating loop. In practice, the first 10 minutes usually look like this:

1. Your session manager creates the agent terminals, whether that is `ntm spawn`, WezTerm mux, or something equivalent.
2. You send the marching-orders prompt above.
3. Each agent reads `AGENTS.md` and the repo docs, inspects the codebase, and joins Agent Mail.
4. Each agent checks who else is active, acknowledges any waiting messages, and learns the bead-thread naming conventions.
5. Each agent either receives an assigned bead or uses `bv --robot-*` and `br ready --json` to choose one.
6. Before editing, the agent reserves the relevant file surface and announces the claim in the matching `br-###` thread.
7. Only then does the agent start coding, reviewing, or testing.

That sequence matters because it turns a pile of terminals into a coordinated swarm. If you skip the join-up steps, you get duplicate work, silent conflicts, and "communication purgatory." If you skip the routing steps, agents choose work randomly instead of unlocking the dependency graph intelligently.

### What the Human Actually Does During an Active Swarm

This is one of the places newcomers get lost. They imagine the human either has to micromanage every agent or disappear completely. In practice, the human does neither. The human tends the swarm the way an operator tends a machine that mostly runs on its own.

On roughly a **10-30 minute cadence**, the human does some subset of the following:

1. Check `br` or `bv` to see whether progress is flowing or whether work has jammed up behind a blocker.
2. Look for beads that have been `in_progress` for too long or that keep bouncing between agents.
3. Check Agent Mail for unanswered requests, reservation conflicts, or silence from agents that should be talking.
4. Send a fresh-eyes review prompt to one agent while the others keep implementing.
5. Rescue agents after compaction by forcing a re-read of `AGENTS.md`.
6. Reassign or add agents if a project phase has become lopsided.
7. Make sure heavy builds/tests are being offloaded instead of thrashing the local box.
8. Periodically designate one agent to handle organized commits and pushes.

The key idea is that the human is managing **flow quality**, not hand-authoring every local decision.

### Diagnosing a Stuck Swarm

When a swarm goes bad, the failure is usually one of two things:

1. a **local coordination jam**, where the agents are stepping on each other or losing operational context
2. a **strategic drift problem**, where the swarm is busy but is no longer closing the real gap to the goal

The most common symptoms and interventions are:

| Symptom | Likely Cause | What to Do |
|---------|--------------|------------|
| Multiple agents keep picking the same bead | Starts were not staggered; agents are not marking `in_progress`; Agent Mail claims/reservations are weak | Stagger starts, force explicit Agent Mail claim messages, check reservations, and make sure agents are actually using `bv` plus bead/thread conventions |
| An agent starts going in circles after compaction | It forgot the operating contract in `AGENTS.md` | Force `Reread AGENTS.md so it's still fresh in your mind.`, use the post-compaction reminder tooling, and kill/restart the session if the agent still behaves erratically |
| A bead sits `in_progress` for too long with little or no signal | The agent crashed, silently blocked, or lost the plot | Check Agent Mail, check whether the session is alive, reclaim the bead if needed, and split out the blocker into a clearer bead if the task was underspecified |
| Agents produce contradictory implementations | They are not coordinating through Agent Mail and reservations, or the bead boundary is wrong | Audit reservation use, make sure the work is threaded through the matching `br-###` conversation, and revise bead boundaries if two agents are independently inventing overlapping solutions |
| The swarm is generating lots of code and commits, but the real goal still feels far away | Strategic drift; the current open/in-progress beads do not actually close the remaining gap | Stop and run a high-level diagnosis before burning more implementation tokens |

That last case is the one people miss most often because the swarm can look productive while still heading in the wrong direction. A recent X post about FrankenEngine described these as **"Come to Jesus" moments** with the agents, used to make sure **"we aren't losing sight of the bigger picture"** after days of methodically cranking through beads.

Source: https://x.com/doodlestein/status/2030805574091231425

In those moments, the right move is not another local review. It is a high-level reality check such as:

```
Where are we on this project? Do we actually have the thing we are trying to build? If not, what is blocking us? If we intelligently implement all open and in-progress beads, would we close that gap completely? Why or why not?
```

If the answer is "no," do not just keep coding blindly. Add or revise beads, re-polish them, and then resume swarm execution with a corrected frontier. Busy agents are not the goal; a bead graph that actually converges on the project goal is the goal.

### Running Case Study: What Atlas Notes Looks Like as a Live Swarm

For the same example project, a small first swarm might look like this:

- **Claude agent A** claims `br-101` and implements upload + parse handling.
- **Codex agent B** claims `br-102` and works on the search path plus tests.
- **Claude agent C** claims `br-103` and builds the admin failure dashboard.
- **Gemini agent D** stays flexible: reviews recent work, checks docs, and fills in test or UX gaps where needed.

All four agents share the same codebase, read the same `AGENTS.md`, coordinate via Agent Mail, and use `bv` whenever they are uncertain about what unlocks the most progress next. That is what makes the swarm feel like one system rather than four unrelated terminals.

### Agent Coordination Architecture

The system is **distributed and decentralized**, built on a trio of tools that work together:

- **Beads (`br`)** are the centralized task store, the single source of truth for what needs to be done
- **Agent Mail (`am`)** handles inter-agent communication and file reservations
- **Beads Viewer (`bv`)** acts as a graph-theory "compass" directing agents to optimal next tasks

> "Agent Mail + Beads + bv are what unlock the truly insane productivity gains."

Each tool is essential but insufficient alone. Agent Mail without beads leaves agents with no structured work to coordinate around. Beads without bv leaves agents randomly choosing tasks instead of mechanically computing the right answer from the dependency graph. bv without Agent Mail leaves agents unable to communicate what they're doing.

> "Each agent just uses bv on its own to find the next optimal bead to work on and marks it as being in-progress and communicates about this to the other agents using Agent Mail. It's a distributed, robust system where every agent is fungible and replaceable if they crash or get amnesia."

### Why Naive Agent Communication Fails

Building your own agent coordination from scratch is full of footguns that Agent Mail was designed to sidestep:

**Footgun #1: Broadcast-to-all defaults.** Agents are lazy and will only use broadcast mode, spamming every agent with mostly irrelevant information. It's like if your email system defaulted to reply-all every time. This burns precious context window.

**Footgun #2: Poor MCP ergonomics.** It takes a huge amount of careful iteration and observation to get the API surface right so agents use it reliably without wasting tokens. Bad documentation and clunky tool signatures cause agents to either misuse the system or ignore it entirely.

**Footgun #3: Forcing git worktrees.** Worktrees demolish development velocity and create reconciliation debt when agents diverge. Working in one shared space surfaces conflicts immediately so you can deal with them, which is easy when agents can communicate.

**Footgun #4: Rigid identity and locking.** You need a system that's robust to agents suddenly dying or getting their memory wiped, because that happens all the time. Rigid locks held by dead agents block everyone else. That's why Agent Mail uses **advisory** reservations with TTL expiry and reclaim mechanics (see Section 13).

### Bead IDs as Threading Anchors

Bead IDs create a unified audit trail across all coordination layers:

```
1. Pick work:        br ready --json → choose br-123
2. Reserve files:    file_reservation_paths(..., reason="br-123")
3. Announce:         send_message(..., thread_id="br-123", subject="[br-123] Starting auth refactor")
4. Work:             Reply in thread with progress updates
5. Complete:         br close br-123, release_file_reservations(...), final message
6. Commit:           git commit -m "feat: auth refactor (br-123)"
```

The bead ID goes in: thread_id, subject prefix, reservation reason, and commit message. This makes all coordination activity traceable back to a single task.

### [Agent Mail](https://github.com/Dicklesworthstone/mcp_agent_mail) Registration and Macros

Agent Mail provides four high-level macros that wrap common multi-step patterns:

1. `macro_start_session` -- Bootstrap: ensure project → register agent → fetch inbox
2. `macro_prepare_thread` -- Join existing thread with summary
3. `macro_file_reservation_cycle` -- Reserve → work → auto-release
4. `macro_contact_handshake` -- Cross-agent contact setup

The raw registration flow is:

1. `ensure_project(project_key="/data/projects/myrepo")`
2. `register_agent(project_key, program="claude_code", model="opus")` -- auto-generates names like "ScarletCave", "CoralBadger" (best to omit the `name` parameter and let it auto-generate)
3. `fetch_inbox(project_key, agent_name)` -- check for existing messages
4. read `resource://agents/{project_key}` (or use the project inbox/contact tools) -- see who else is active

### bv for Task Selection: The Graph-Theory Compass

With 200-500 initial beads, you don't want agents randomly choosing tasks or wasting too much time communicating about what to do next. There's usually a mechanically correct answer for what each agent should work on, and it comes from the dependency structure of the tasks:

> "That right answer comes from the dependency structure of the tasks, and this can be mechanically computed using basic graph theory. And that's what bv does. It's like a compass that each agent can use to tell them which direction will unlock the most work overall."

bv precomputes dependency metrics (PageRank, betweenness, HITS, critical path, cycle detection) so agents get deterministic, dependency-aware output instead of parsing JSONL or hallucinating graph traversals:

```bash
bv --robot-triage        # THE MEGA-COMMAND: full recommendations with scores
bv --robot-next          # Minimal: just the single top pick + claim command
bv --robot-plan          # Parallel execution tracks with unblocks lists
bv --robot-insights      # Full graph metrics: PageRank, betweenness, HITS
bv --robot-priority      # Priority recommendations with reasoning and confidence
bv --robot-diff --diff-since <commit|date>  # Changes since last check
bv --robot-recipes       # List pre-filter/sort recipes (actionable, blocked, etc.)
```

**CRITICAL: Use ONLY `--robot-*` flags. Bare `bv` launches an interactive TUI that blocks your session.**

### The bv Origin Story and Design Philosophy

bv was made in a single day and was "just under 7k lines of Golang." It was later rewritten to 80k lines with advanced features. This illustrates a key insight:

> "I find myself using my beads_viewer (bv) tool constantly, or rather my agents use it all the time, as a kind of compass directing them on what to work on next. Which is funny to me because I literally made bv in one day from start to finish. It goes to show that effort doesn't correspond at all to impact."

The tool started for humans but pivoted to being primarily for agents:

> "bv started out a tool for humans but always had a robust agent mode. It's just that my use of it has pivoted to being mostly about the robots."

> "But the biggest improvement in terms of actual usefulness isn't for you humans at all! It's for your coding agents. They just need to run one simple command, `bv --robot-triage`, and they instantly get a massive wealth of insights into what to work on next."

A critical design principle is that robot mode should not be the human TUI dumped to JSON. It needs its own affordances:

> "The robot mode shouldn't just be the human mode as a CLI with json."

When multiple agents each independently query bv for priority, the result is **emergent coordination**. Agents naturally spread across the optimal work frontier without needing a central coordinator. This is the distributed alternative to a "ringleader" agent:

> "The best solution is to add this to the mix and have the agents use the bv robot priority mode and then you get sort of emergent coordination."

Taken to its endpoint, this design supports full autonomy: one puppet master agent controlling ntm via robot mode and replacing the human for routine machine-tending:

> "I might be building towards having one puppet master agent that replaces me completely by controlling ntm via robot mode..."

### bv Graph Metrics: A Decision Framework

When agents look at `bv --robot-insights` output, here's how to interpret the graph metrics:

| Pattern | Meaning | Action |
|---------|---------|--------|
| High PageRank + High Betweenness | Critical bottleneck | DROP EVERYTHING, fix this first |
| High PageRank + Low Betweenness | Foundation piece | Important but not currently blocking |
| Low PageRank + High Betweenness | Unexpected chokepoint | Investigate why this is a bridge |
| Low PageRank + Low Betweenness | Leaf work | Safe to parallelize freely |

PageRank finds what everything depends on. Betweenness finds bottlenecks. The math knows your priorities better than gut intuition.

Advanced filtering:
```bash
bv --robot-plan --label backend              # Scope to label's subgraph
bv --robot-insights --as-of HEAD~30          # Historical point-in-time
bv --recipe actionable --robot-plan          # Only unblocked items
bv --recipe high-impact --robot-triage       # Top PageRank scores
bv --robot-triage --robot-triage-by-track    # Group by parallel streams
bv --robot-triage --robot-triage-by-label    # Group by domain
```

### How to Get Agents to Use bv

Drop this blurb into your AGENTS.md:

```
### Using bv as an AI sidecar

bv is a fast terminal UI for Beads projects (.beads/beads.jsonl). It renders
lists/details and precomputes dependency metrics (PageRank, critical path,
cycles, etc.) so you instantly see blockers and execution order. For agents,
it's a graph sidecar: instead of parsing JSONL or risking hallucinated
traversal, call the robot flags to get deterministic, dependency-aware outputs.

- bv --robot-help: shows all AI-facing commands.
- bv --robot-insights: JSON graph metrics with top-N summaries for triage.
- bv --robot-plan: JSON execution plan with parallel tracks and unblocks lists.
- bv --robot-priority: JSON priority recommendations with reasoning.
- bv --robot-recipes: list recipes; apply via bv --recipe <name>.
- bv --robot-diff --diff-since <commit|date>: JSON diff of issue changes.

Use these commands instead of hand-rolling graph logic; bv already computes
the hard parts so agents can act safely and quickly.
```

For humans, the TUI has an insights tab (`i` key), graph view (`g`), kanban board (`b`), and fuzzy search (`/`). You can also view beads remotely via the GitHub Pages static site export, e.g. https://dicklesworthstone.github.io/beads_viewer_for_agentic_coding_flywheel_setup/

### The "Clockwork Deity" Mindset

> "YOU are the bottleneck. Be the clockwork deity to your agent swarms: design a beautiful and intricate machine, set it running, and then move on to the next project. By the time you come back to the first one, you should have huge chunks of work already done and ready."

The human's job is front-loaded: create the plan, turn it into beads, set up the agents, then step away. The agents execute autonomously while you move to other projects or activities.

> "If you use the right tooling and workflows (agent mail + beads + bv), it transforms into 80% planning (AI-assisted, based on an initial prompt) and turning the markdown plan into very detailed and granular beads. And then the rest is just making sure the swarm of agents stay busy and executing their beads tasks effectively."

### No Role Specialization

> "No, every agent is fungible and a generalist. They are all using the same base model and reading the same AGENTS dot md file. Simply telling one that it's a frontend agent doesn't make it better at frontend."

### The Thundering Herd Problem

When multiple agents start simultaneously, they may all pick the same bead. Solutions:
- Tell agents to immediately mark beads as in-progress
- **Stagger the start** by **30 seconds minimum** between each agent launch (not 20s; that came from trial and error with Agent Mail server stability)
- Wait **4 seconds** after launch before sending the initial prompt
- For Codex specifically: send Enter **twice** after pasting long prompts (Codex input buffer quirk)
- Use Agent Mail to announce what you're working on

> "Classic 'thundering herd' problem. Usually addressed with retry with exponential backoff and jitter, but in this case marking the beads quickly and staggered start is the best."

### Scaling Considerations

> "Efficiency definitely declines as N grows but if you have enough tasks to work on in beads and they have agent mail and you don't start them all at the exact same time, you go faster as N grows."

Practical strategies:
- 12 agents max on a single project
- Or run 5 agents per project across multiple projects simultaneously
- Don't divide roles -- all agents are generalists
- Agents do rounds of reviewing their own work and the work of others

### Account Switching with [CAAM](https://github.com/Dicklesworthstone/coding_agent_account_manager)

When you hit rate limits, use CAAM (Coding Agent Account Manager) for sub-100ms account switching:

```bash
caam status                     # See current accounts
caam activate claude backup-2   # Switch instantly
```

---

## 13. Phase 8: The Single-Branch Git Model

ACFS uses **one branch (`main`) with one worktree**. All agents commit directly to `main`. This may surprise you if you're used to feature branches.

### Why Not Branches or Worktrees?

> "I hate worktrees, to me they create more problems than they solve. This is especially true in the early stages (first 30 minutes of the swarm executing the beads) where it's critical that all the agents be on the same page in terms of a shared state."

**Branch-per-agent creates merge hell.** With 10+ agents making frequent commits, merging N branches back to main produces cascading conflicts that waste more time than they save.

**Worktrees add filesystem complexity.** Each worktree is a full checkout. With many agents, disk usage multiplies and path confusion leads to cross-worktree edits that corrupt state.

**Agents lose context across branches.** When an agent switches branches, its in-context understanding of the codebase becomes stale. Single-branch means every agent always sees the latest state.

**Logical conflicts survive textual merges.** Even when two changes don't conflict at the text level, they can break semantics. A function signature change on one branch and a new callsite on another will merge cleanly but fail to compile. On a single branch, the second agent sees the signature change immediately and adapts.

### Three Conflict Prevention Mechanisms

Instead of branch isolation, ACFS uses three complementary mechanisms:

#### 1. File Reservations ([Agent Mail](https://github.com/Dicklesworthstone/mcp_agent_mail))

Before editing files, agents reserve them:

```
file_reservation_paths(
    project_key="/data/projects/my-repo",
    agent_name="BlueLake",
    paths=["src/auth/*.rs"],
    ttl_seconds=3600,
    exclusive=true,
    reason="br-42: refactor auth"
)
```

Other agents see the reservation and work on different files.

Crucially, reservations are **advisory, not rigid**. They expire automatically via TTL, and agents can observe if reserved files haven't been touched recently and reclaim them. This design is deliberate:

> "This is critical because you want a system that's robust to agents suddenly dying or getting their memory wiped, because that happens all the time! That's why you also don't want ringleaders."

A rigid locking system would deadlock when an agent crashes while holding a lock. Advisory reservations with expiry degrade gracefully. The worst case is a brief window where two agents touch the same file, which the pre-commit guard catches anyway.

#### 2. Pre-Commit Guard

The [Agent Mail](https://github.com/Dicklesworthstone/mcp_agent_mail) pre-commit hook checks reservations at commit time. If you try to commit a file reserved by another agent, the commit is blocked with an explanation of who holds the reservation.

#### 3. [DCG](https://github.com/Dicklesworthstone/destructive_command_guard) (Destructive Command Guard)

DCG mechanically blocks dangerous commands that could destroy other agents' work. When blocked, agents should use safe alternatives:

| Blocked Command | Safe Alternative | Why |
|----------------|------------------|-----|
| `git reset --hard` | `git stash` | Recoverable |
| `git checkout -- file` | `git stash push file` | Preserves changes |
| `git push --force` | `git push --force-with-lease` | Checks remote unchanged |
| `git clean -fd` | `git clean -fdn` (preview first) | Shows what would delete |
| `rm -rf /path` | `rm -ri /path` | Interactive confirmation |

**Origin:** On December 17, 2025, an agent ran `git checkout --` on uncommitted work. Files were recovered via `git fsck --lost-found`, but the incident proved that instructions don't prevent execution -- **mechanical enforcement does**.

### The Recommended Git Workflow

```
1. Pull latest          git pull --rebase
2. Reserve files        file_reservation_paths(...)
3. Edit and test        cargo test / bun test / go test
4. Commit immediately   git add <files> && git commit
5. Push                 git push
6. Release reservation  release_file_reservations(...)
```

**Key principles:**
- **Commit early, commit often.** Small commits reduce the window for conflicts
- **Push after every commit.** Unpushed commits are invisible to other agents
- **Reserve before editing.** Don't touch files without a reservation
- **Release when done.** Don't hold reservations longer than needed

### Handling Other Agents' Changes

From AGENTS.md:

> "You NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents. Just treat those changes identically to changes that you yourself made. Just fool yourself into thinking YOU made the changes and simply don't recall it for some reason."

---

## 14. Phase 9: Code Review Loops

Code review in a multi-agent swarm follows a different rhythm than traditional code review. There's no pull request, no human reviewer, no approval gate. Instead, review is woven into the implementation cycle itself: agents review their own work after each bead, review each other's work periodically, and the human triggers broader review rounds at natural checkpoints.

### Self-Review After Each Bead

After an agent finishes implementing a bead, it should immediately review its own work before moving on:

```
great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with "fresh eyes" looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.
```

**How many rounds?** Run this until the agent reports "I reviewed everything and found no issues." Typically 1-2 rounds for simple beads, 2-3 for complex ones. If an agent keeps finding bugs after 3 rounds of self-review, the implementation approach may be fundamentally off; consider having a different agent take over.

**When to send this prompt:** You don't need to send it manually every time. Include it as part of the agent's workflow expectations in AGENTS.md: "After completing each bead, do a self-review before moving to the next one." Well-trained agents (with a good skill) will do this automatically.

### Cross-Agent Review (Periodic)

Every 30-60 minutes during active implementation, or after a natural milestone (e.g., all beads in an epic are done), trigger cross-agent review:

```
Ok can you now turn your attention to reviewing the code written by your
fellow agents and checking for any issues, bugs, errors, problems,
inefficiencies, security problems, reliability issues, etc. and carefully
diagnose their underlying root causes using first-principle analysis and
then fix or revise them if necessary? Don't restrict yourself to the latest
commits, cast a wider net and go super deep!
```

Cross-agent review catches a fundamentally different class of bugs than self-review. When Agent A implements a function and Agent B calls it, Agent A's self-review won't catch the fact that Agent B is passing arguments in the wrong order, because Agent A doesn't know about Agent B's code. Cross-agent review surfaces these integration issues.

**Practical tip:** Don't have all agents stop work to review simultaneously. Pick one or two agents that have just finished a bead and send them the cross-agent review prompt while the others continue implementing. This keeps the swarm productive while still catching inter-agent issues.

### How Fresh-Eyes Reviews Work in Practice

From session history, the most effective reviews use **subagent delegation**: the parent agent identifies recently changed files (via `git diff --name-only HEAD~5`) and dispatches a fresh subagent (with no context of the original implementation) to review each file or related group of files. The fresh subagent approaches the code with genuinely fresh eyes because it has no memory of the design decisions that produced it.

Each review should answer:
1. **Is the implementation correct?** Does it do what the bead description says it should?
2. **Are there edge cases?** Empty inputs, concurrent access, error paths, boundary conditions
3. **Are there similar issues elsewhere?** If you find a bug, search for the same pattern in other files
4. **Should the approach be different?** Sometimes the implementation is correct but there's a simpler or more robust way

### Moving to the Next Bead

After reviews come up clean, the transition prompt combines re-reading AGENTS.md (for compaction safety), querying bv for priority, and communicating with the swarm:

```
Reread AGENTS.md so it's still fresh in your mind. Use bv with the robot
flags (see AGENTS.md for info on this) to find the most impactful bead(s)
to work on next and then start on it. Remember to mark the beads
appropriately and communicate with your fellow agents. Pick the next bead
you can actually do usefully now and start coding on it immediately;
communicate what you're working on to your fellow agents and mark beads
appropriately as you work. And respond to any agent mail messages you've
received.
```

This transition prompt is the glue between beads. It ensures the agent doesn't just pick an arbitrary next task but uses graph-theory routing (bv) to choose the task that unblocks the most downstream work.

---

## 15. Phase 10: Testing and Quality Assurance

### UBS: The Quality Gate

UBS (Ultimate Bug Scanner) is the quality gate that catches errors beyond what linters and type checkers find:

```bash
ubs file.rs file2.rs                    # Specific files (< 1s)
ubs $(git diff --name-only --cached)    # Staged files -- before commit
ubs --only=rust,toml src/               # Language filter (3-5x faster)
ubs .                                   # Whole project
```

**Golden Rule:** `ubs <changed-files>` before every commit. Exit 0 = safe. Exit >0 = fix and re-run.

### Creating Test Beads

If test coverage is insufficient after implementation:

```
Do we have full unit test coverage without using mocks/fake stuff? What
about complete e2e integration test scripts with great, detailed logging? If
not, then create a comprehensive and granular set of beads for all this with
tasks, subtasks, and dependency structure overlaid with detailed comments.
```

### Testing With Agent Swarms

In this methodology, tests are effectively free labor:

> "The tests become obsolete and need to be revised as the code changes, which slows down dev velocity. But if all the tests are written and maintained by agents, who cares? Add another couple agents to the swarm and let them deal with updating the tests and running them. It's free!"

Larger projects produce massive test suites:

> "By the time all the beads are done I generally have hundreds and hundreds of unit tests and e2e integration tests. Larger projects like brennerbot.org have nearly 5,000 tests! Stuff tends to 'just work' in that case."

### The Review Philosophy

> "I'm constantly having them review themselves the work of other agents throughout the process. I had routines where I just do this deep review with them until they stop coming up with any problems. Then I have them also create tons of unit tests and e2e tests. And I use the code."

### Compiler Checks (CRITICAL)

After any substantive code changes, always verify:

```bash
# Rust
cargo check --all-targets
cargo clippy --all-targets -- -D warnings
cargo fmt --check

# Go
go build ./...
go vet ./...

# TypeScript
bun typecheck
bun lint
```

---

## 16. Phase 11: UI/UX Polish

For projects with a user interface (web apps, TUIs, interactive CLIs), there's a dedicated polishing phase that happens after core functionality works but before shipping. This is separate from bug hunting because the problems you're looking for aren't bugs; they're friction, ugliness, and missed opportunities to delight.

### Why This Is a Separate Phase

UI/UX polish doesn't fit naturally into the bead implementation cycle. When an agent implements a "user authentication" bead, it focuses on making authentication work correctly. Whether the login form has good visual hierarchy, whether the error messages are helpful, whether the flow feels smooth on mobile; these are orthogonal concerns that require a different mode of attention. Trying to do both at once produces mediocre results on both.

### The Polish Workflow

**Step 1: Run the general review prompt.** This produces a list of improvement suggestions, not code changes:

```
Great, now I want you to super carefully scrutinize every aspect of the
application workflow and implementation and look for things that just seem
sub-optimal or even wrong/mistaken to you, things that could very obviously
be improved from a user-friendliness and intuitiveness standpoint, places
where our UI/UX could be improved and polished to be slicker, more visually
appealing, and more premium feeling and just ultra high quality, like
Stripe-level apps.
```

**Step 2: Review the suggestions and pick which to pursue.** The agent will typically generate 15-30 suggestions. Some will be excellent, some will be unnecessary. This is a human judgment step: you decide which improvements are worth the implementation cost.

**Step 3: Turn selected suggestions into beads** and implement them through the normal swarm process. This keeps polish work tracked and prevents scope creep.

**Step 4: Run the platform-specific polish prompt** to ensure desktop and mobile are both optimized:

```
I still think there are strong opportunities to enhance the UI/UX look and
feel and to make everything work better and be more intuitive, user-
friendly, visually appealing, polished, slick, and world class in terms of
following UI/UX best practices like those used by Stripe, don't you agree?
And I want you to carefully consider desktop UI/UX and mobile UI/UX
separately while doing this and hyper-optimize for both separately to play
to the specifics of each modality. I'm looking for true world-class visual
appeal, polish, slickness, etc. that makes people gasp at how stunning and
perfect it is in every way.
```

The "don't you agree?" phrasing isn't politeness; it triggers the model to critically evaluate its own previous work rather than just validating it. Models are more likely to find genuine issues when prompted to express an opinion.

**Step 5: Repeat steps 1-4** until the improvements become marginal. Typically 2-3 rounds is enough; diminishing returns set in quickly for UI polish.

For projects with dedicated frontend design skills (like the `frontend-design` skill), use those instead of these generic prompts for significantly better results.

### De-Slopification

After agents write documentation (README, user-facing text), run a de-slopify pass to remove telltale AI writing patterns:

| Pattern | Problem |
|---------|---------|
| Emdash overuse | LLMs use emdashes constantly, even when semicolons, commas, or sentence splits work better |
| "It's not X, it's Y" | Formulaic contrast structure |
| "Here's why" / "Here's why it matters:" | Clickbait-style lead-in |
| "Let's dive in" | Forced enthusiasm |
| "At its core..." | Pseudo-profound opener |
| "It's worth noting..." | Unnecessary hedge |

This must be done manually, not via regex. Read each line and revise systematically. The de-slopify prompt is in the prompt library below.

---

## 17. Phase 12: Deep Bug Hunting

This phase is distinct from the per-bead reviews in Phase 9. Phase 9 reviews happen after each bead is completed and focus on the code that was just written. Phase 12 happens after all (or most) beads are done and casts a wider net across the entire codebase, looking for problems that only become visible when you see how all the pieces fit together.

The two prompts below serve different purposes and should be alternated:

This is one of the more art-than-science parts of the methodology. The prompts overlap in literal meaning, but they reliably activate different search behaviors in the models. This is where the "agent theory of mind" or "gestalt psychology of LLMs" framing becomes useful.

### Random Exploration Review

```
I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file.
```

The "randomly explore" framing is deliberate. Directed reviews tend to focus on the files that seem important, which are also the files that got the most attention during implementation. The bugs that survive to this phase are typically in the less-obvious files: utility modules, error handling paths, configuration parsing, edge-case branches. By telling the agent to explore randomly, you increase the probability that it looks at code that nobody has carefully reviewed yet.

### Cross-Agent Deep Review

```
Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!
```

This prompt works because agents that didn't write the code approach it without the assumptions the author had. An agent that implemented the auth module naturally thinks its approach is correct. A different agent reading that same code for the first time is much more likely to notice that the token expiry check has an off-by-one error or that the error message leaks internal state.

These prompts are worth alternating rather than picking one favorite. The cross-agent prompt tends to induce a suspicious, adversarial stance aimed at boundary failures and root causes in code written by others. The random-exploration prompt tends to induce a curiosity-driven stance aimed at reconstructing workflows and finding latent bugs in code that nobody is actively staring at.

### How to Run Deep Bug Hunting

**Workflow:** Send the random exploration prompt to 2-3 agents simultaneously. Each will explore different parts of the codebase (the randomness ensures variety). After they report back, send the cross-agent review prompt. Alternate between the two prompts until agents consistently come back with "I reviewed X, Y, Z files and found no issues."

**When to stop:** When two consecutive rounds (one random exploration, one cross-agent review) both come back clean, the codebase is in good shape. If agents keep finding bugs after 4+ rounds, that's a signal that something more fundamental is wrong; consider going back to bead space and creating specific fix beads rather than continuing open-ended review.

**Combine with UBS:** Run `ubs .` on the full project before starting deep bug hunting. Fix everything UBS flags first, then let agents hunt for the subtler issues that static analysis can't catch.

---

## 18. Phase 13: Committing and Shipping

### Organized Commits

Periodically have one agent handle git operations:

```
Now, based on your knowledge of the project, commit all changed files now
in a series of logically connected groupings with super detailed commit
messages for each and then push. Take your time to do it right. Don't edit
the code at all. Don't commit obviously ephemeral files.
```

### Landing the Plane (Mandatory Session Completion)

When ending a work session, agents MUST complete ALL steps:

1. **File issues for remaining work** -- Create beads for anything that needs follow-up
2. **Run quality gates** -- Tests, linters, builds (if code changed)
3. **Update issue status** -- Close finished work, update in-progress items
4. **PUSH TO REMOTE** -- This is MANDATORY:

```bash
git pull --rebase
br sync --flush-only    # Export beads to JSONL (no git ops)
git add .beads/         # Stage beads changes
git add <other files>   # Stage code changes
git commit -m "..."     # Commit everything
git push
git status              # MUST show "up to date with origin"
```

5. **Verify** -- All changes committed AND pushed

> Work is NOT complete until `git push` succeeds. NEVER stop before pushing -- that leaves work stranded locally.

### Running Case Study: What "Done for Now" Looks Like

For **Atlas Notes**, "done for now" would not mean "the upload page appears." It would mean something like:

- the upload, parse, search, and admin-review workflows all work end to end
- the key beads are closed and the remaining polish/future ideas exist as new beads
- tests cover the critical user journeys and known failure paths
- UBS and compiler/lint checks are clean
- commits and pushes are complete
- the next session can restart from beads, `AGENTS.md`, and Agent Mail threads rather than from human memory

That last point matters. A Flywheel session is only truly landable when a future swarm can pick it back up without the human re-explaining the project from scratch.

---

## 19. The Complete Toolchain

### The Flywheel Stack (11 Tools)

| Tool | Command | Purpose | Key Feature |
|------|---------|---------|-------------|
| **[NTM](https://github.com/Dicklesworthstone/ntm)** | `ntm` | Named Tmux Manager | Agent cockpit: spawn/send/broadcast/palette |
| **[MCP Agent Mail](https://github.com/Dicklesworthstone/mcp_agent_mail)** | `am` | Agent coordination | Identities, inbox/outbox, file reservations |
| **[UBS](https://github.com/Dicklesworthstone/ultimate_bug_scanner)** | `ubs` | Ultimate Bug Scanner | 1000+ patterns, pre-commit guardrails |
| **[Beads](https://github.com/Dicklesworthstone/beads_rust)** | `br` | Issue tracking | Dependency-aware, JSONL+SQLite hybrid |
| **[Beads Viewer](https://github.com/Dicklesworthstone/beads_viewer)** | `bv` | Triage engine | PageRank, betweenness, HITS, robot mode |
| **[Remote Command Harness](https://github.com/Dicklesworthstone/remote_compilation_helper)** | `rch` | Build/test offloading | Keeps heavy CPU work off the local swarm box |
| **[CASS](https://github.com/Dicklesworthstone/coding_agent_session_search)** | `cass` | Session search | Unified agent history indexing |
| **[CASS Memory](https://github.com/Dicklesworthstone/cass_memory_system)** | `cm` | Procedural memory | Episodic -> working -> procedural |
| **[CAAM](https://github.com/Dicklesworthstone/coding_agent_account_manager)** | `caam` | Auth switching | Sub-100ms account swap |
| **[DCG](https://github.com/Dicklesworthstone/destructive_command_guard)** | `dcg` | Safety guard | Blocks destructive git/fs operations |
| **[SLB](https://github.com/Dicklesworthstone/slb)** | `slb` | Two-person rule | Optional guardrails for dangerous commands |

Not every entry is used the same way. `br`, `bv`, `ubs`, and `rch` are ordinary shell commands you run directly. Agent Mail is primarily experienced through MCP tools/macros plus the artifacts it creates, even if some environments also expose helper commands or aliases around it.

### Supporting Infrastructure

| Component | Purpose |
|-----------|---------|
| **AGENTS.md** | Per-project configuration teaching agents about tools and rules |
| **Best practices guides** | Referenced in AGENTS.md, kept current |
| **Markdown plan files** | Source-of-truth planning documents |
| **`acfs newproj`** | Bootstraps projects with full tooling |
| **`acfs doctor`** | Single command to verify entire installation |
| **NTM command palette** | Battle-tested prompt library |
| **Claude Code Skills** | Each tool has a dedicated skill for automated workflows |

### The Skills Ecosystem

The term "skill" confuses people at first, so define it plainly: a skill is a reusable operational instruction pack for an agent. In Claude Code terms, that usually means a `SKILL.md` file plus optional references, scripts, or templates that tell the agent how to use a tool, how to execute a methodology, what pitfalls to avoid, and what a good result looks like. A good skill is closer to executable know-how than to ordinary prose documentation.

This is an important distinction. A tool changes what the agent can do. A skill changes how well the agent knows how to do it. The same model with and without a good skill often behaves like two different agents.

Every Flywheel tool has a corresponding Claude Code skill that encodes best practices and automates common workflows. Many of these skills are bundled directly in the repos for the tools themselves and get installed automatically when the tool is installed, which means users often benefit from them without having to think about "skill management" explicitly. There is also a broader public skills collection here: https://github.com/Dicklesworthstone/agent_flywheel_clawdbot_skills_and_integrations/tree/main/skills

For a much larger paid library of higher-end skills, see [jeffreys-skills.md](https://jeffreys-skills.md). It is a $20/month service with many of the strongest curated skills, new skills added continuously, and a dedicated proprietary CLI called `jsm` for managing them. Unlike jeffreysprompts.com, it does not have a free section.

The prompt side has a similar split. [jeffreysprompts.com](https://jeffreysprompts.com) has a generous free section and is open source at [Dicklesworthstone/jeffreysprompts.com](https://github.com/Dicklesworthstone/jeffreysprompts.com). It also has a paid Pro tier with additional prompts and a dedicated proprietary CLI called `jfp` for managing prompt collections.

Both paid offerings, the Pro side of jeffreysprompts.com and jeffreys-skills.md, are still under active development. That means readers should expect the occasional rough edge or bug. Active work is underway to fix issues quickly, feedback is genuinely appreciated, and refunds are available if someone tries them and is unhappy.

Skills provide the prompts, procedures, anti-pattern guidance, and tool-specific workflows directly to agents, which reduces the amount of bespoke prompting a human needs to do by hand.

### The Flywheel Interactions

```
NTM spawns agents --> Agents read AGENTS.md
                  --> Agents register with Agent Mail
                  --> Agents query bv for task priority
                  --> Agents claim beads via br
                  --> Agents reserve files via Agent Mail
                  --> Agents implement and test
                  --> UBS scans for bugs
                  --> Agents commit and push
                  --> CASS indexes the session
                  --> CM distills procedural memory
                  --> Next cycle is better
```

### Model Recommendations by Phase

| Phase | Recommended Model | Why |
|-------|-------------------|-----|
| Initial plan creation | GPT Pro (web) | Extended reasoning, all-you-can-eat pricing |
| Plan synthesis | GPT Pro (web) | Best at being the "final arbiter" |
| Plan refinement | GPT Pro + Opus (web) | Pro reviews, Claude integrates |
| Plan -> Beads conversion | Claude Code (Opus) | Best coding agent for structured creation |
| Bead polishing | Claude Code (Opus) | Consistent, thorough |
| Implementation | Claude Code + Codex + Gemini | Diverse swarm |
| Code review | Claude Code + Gemini | Gemini good for review duty |
| Final verification | Codex (GPT) | Different model catches different things |

---

## 20. Key Principles and Insights

Before the numbered principles, keep one framing idea in mind: the workflow works because it keeps different kinds of context in different layers.

- **The markdown plan** holds whole-system intent and reasoning.
- **The beads** hold executable task structure and embedded local context.
- **`AGENTS.md`** holds operating rules and tool knowledge that must survive compaction.
- **The codebase** holds the implementation itself, which is too large to be the primary planning medium.

### 1. Plans Fit in Context Windows; Code Doesn't

Even a 6,000-line plan fits easily in a context window. The equivalent codebase won't. Reasoning at the plan level is therefore fundamentally more effective than reasoning at the code level.

### 2. One Comprehensive Plan, Not Incremental Skeletons

> "I think you get a better result faster by creating one big comprehensive, detailed, granular plan. That's the only way to get these models to use their big brains to understand the entire system all at the same time."

### 3. Beads Supersede the Plan

Once beads are created properly, the plan becomes a historical artifact:

> "Once you convert the plan docs into beads, you're supposed to not really need to refer back to the docs if you did a good job. The docs are still useful though, for people and for agents in various contexts, but you don't need to swamp all the agents with the full plan once you've turned it into beads."

### 4. Agent Fungibility

Every agent is a generalist. No role specialization. All agents read the same AGENTS.md and can pick up any bead. If an agent crashes, any other agent can seamlessly continue its work.

> "When one agent breaks, it's not even a problem when all the agents are fungible. Agents become like commodities and can be instantiated and destroyed at will and the only downside is some slowdown and some wasted tokens."

This is deliberately opposed to "specialist agent" architectures where one agent has a special role. Specialist agents become bottlenecks. When the special agent crashes or needs compaction, the whole system suffers. With 12 fungible agents, losing one makes almost no difference.

Think of it like **RaptorQ fountain codes**: beads are "blobs" in a stream, any agent catches any bead in any order. There is no "rarest chunk" bottleneck, and the system is resilient to partial agent failures by design.

**Failure recovery is trivial:**
1. Bead remains marked `in_progress`
2. Any other agent can resume it (or mark it `blocked`)
3. No dependency on the specific dead agent
4. Replacement: `ntm add PROJECT --cc=1`, give the standard init prompt, and continue

### 5. Shared Workspace Over Worktrees

All agents work in the same directory. Agent Mail's file reservation system, pre-commit guards, and DCG handle coordination. Worktrees create more problems than they solve, especially in early implementation where shared state is critical.

> "I really think worktrees are a bad pattern and not worth the trouble. There are other, much better ways at getting multiple agents to work well together at the same time that don't come with the overhead and reconciliation burden of worktrees."

> "I run like 10+ of them at once in a single project without git worktrees. Agent Mail is the solution."

### 6. Semi-Persistent Identity

Agent identity in the system is deliberately designed to be ephemeral enough to survive crashes but persistent enough to enable coordination:

> "You want 'semi-persistent identity.' An identity that can last for the duration of a discrete task or sub-task (for the purpose of coordination), but one that can also vanish without a trace and not break things."

Agent Mail generates whimsical names like "ScarletCave" and "CoralBadger" because they are meaningful enough for agents to address each other during a work session, but disposable enough that losing one doesn't corrupt the system's state. No agent's identity is load-bearing.

### 7. Security Comes Free with Good Planning

Security review is baked into the standard workflow at multiple levels rather than being a separate phase you have to remember to run. The cross-agent deep review prompt (used in Phase 9 and Phase 12) explicitly calls out security:

```
Ok can you now turn your attention to reviewing the code written by your
fellow agents and checking for any issues, bugs, errors, problems,
inefficiencies, security problems, reliability issues, etc. and carefully
diagnose their underlying root causes using first-principle analysis and
then fix or revise them if necessary? Don't restrict yourself to the latest
commits, cast a wider net and go super deep!
```

That prompt runs repeatedly throughout implementation and produces security findings alongside every other kind of defect. In addition:

- **Plan-level security**: When models reason about an entire system's architecture at once (which is what the plan enables), they spot authentication gaps, data exposure risks, and trust boundary violations without being told to look for them. These are architectural issues, and architecture review is what planning is.
- **UBS catches security anti-patterns mechanically**: Unpinned dependencies, missing input validation, hardcoded secrets, unsafe unwraps, and supply chain vulnerabilities are all in UBS's 1000+ pattern set. Running `ubs <changed-files>` before every commit catches these without relying on agent judgment.
- **Testing-level security**: Beads that include comprehensive e2e tests naturally cover authentication and authorization paths.

The key insight is that security vulnerabilities are usually symptoms of incomplete reasoning about the system. If the plan is detailed enough to cover all user workflows, edge cases, and failure modes, security considerations emerge from that completeness rather than requiring a separate checklist. The cross-agent review prompt ensures security is always on the checklist, and UBS ensures the mechanical patterns are caught even when agents miss them.

**This is true when:**
- the plan actually covers trust boundaries, auth flows, failure paths, and data exposure risks
- cross-agent review and UBS are both part of the normal loop
- the project is not so regulated or high-stakes that explicit security process is mandatory

**A newcomer should not misread this as:** "security needs no deliberate thought." The claim is narrower: the standard Flywheel loop already forces a large amount of security reasoning and security bug detection if you actually run it properly.

For projects with explicit security requirements (financial, healthcare, infrastructure), you should add a dedicated security review bead and reference relevant compliance standards in the plan.

### 8. The Prompts Are Deliberately Generic

> "My projects all start with a ridiculously detailed and comprehensive markdown plan file which is then turned into a comprehensive set of beads (tasks), so the vagueness in the prompts is a feature, letting me reuse them for every project, while the agent gets the specifics they need from the plan and the beads."

This is a design decision that confuses people when they first see the prompt library. The prompts say things like "check over each bead super carefully" rather than "check over each bead in the authentication module for SQL injection risks." That generality is the point.

The specificity lives in three places that the agent already has access to:
1. **The beads themselves** contain detailed descriptions, context, and rationale embedded during the plan-to-bead conversion
2. **AGENTS.md** contains project-specific rules, conventions, and tool documentation
3. **The codebase** contains the actual implementation context

The prompts are the reusable scaffolding that directs the agent's attention. The beads and AGENTS.md supply the project-specific substance. This separation means you can use the exact same prompt library across every project without modification. The prompt "reread AGENTS.md so it's still fresh in your mind" followed by "use bv to find the most impactful bead to work on next" works identically whether you're building a CLI tool, a web app, or a protocol library, because the specifics come from the project's own artifacts, not from the prompt.

### 9. Tools Must Be Agent-First (and Agent-Designed)

> "I view that as a core part of creating a new agent tool, you have to also give the blurb; it's like the new man page or something. Users shouldn't have to figure that out themselves."

Every tool ships with a prepared AGENTS.md blurb. The tool isn't complete without documentation that agents can consume.

But it goes further than documentation. The tools themselves should be **designed by agents, for agents**, with iterative feedback:

> "Every new dev tool in the year of our lord 2025 should have a robot mode designed specifically for agents to use. And it should probably be designed by agents, too. And then you iterate based on the feedback of the agents actually using the tool in real-world scenarios."

> "I make sure the agents enjoy using them and solicit their feedback to improve the tooling. If they don't like the tools, they won't use them without constant nagging."

### 9b. Agent Feedback Forms and Net Promoter Scores

A surprisingly powerful technique is to apply the same feedback mechanisms used for humans, such as structured surveys, satisfaction ratings, and net promoter scores, directly to agents evaluating tools. This is the "by robots, for robots" principle.

The feedback prompt (used with UBS as the canonical example):

```
Based on your experience with [TOOL] today in this project, how would you
rate [TOOL] across multiple dimensions, from 0 (worst) to 100 (best)? Was
it helpful to you? Did it flag a lot of useful things that you would have
missed otherwise? Did the issues it flagged have a good signal-to-noise
ratio? What did it do well, and what was it bad at? Did you run into any
errors or problems while using it?

What changes to [TOOL] would make it work even better for you and be more
useful in your development workflow? Would you recommend it to fellow
coding agents? How strongly, and why or why not? The more specific you can
be, and the more dimensions you can score [TOOL] on, the more helpful it
will be for me as I improve it and incorporate your feedback to make [TOOL]
even better for you in the future!
```

This produces structured, actionable feedback. When used across multiple agents working on different project types, you get a diverse sample of experiences. One agent reviewing UBS for a Python ML project said:

> "UBS proved to be an extremely high-leverage tool. It successfully shifted my focus from just 'writing code' to 'engineering robust software.' While standard linters (like ruff or clippy) catch syntax and style errors, UBS caught architectural and operational risks -- security holes, supply chain vulnerabilities (unpinned datasets), and runtime stability issues (hangs due to missing timeouts, panics from unwrap)."

The feedback loop closes when you pipe the agent reviews directly into another agent working on the tool itself:

> "Another satisfied customer! (I'll be piping that feedback directly into another agent which is working on UBS itself. How's that for customer responsiveness?). All the complaints it had are very easy to fix."

> "I took all of the feedback from agents above and had Gemini 3 implement fixes and improvements in a generic way for all the common issues and complaints."

This is fundamentally different from traditional user testing because the iteration speed is orders of magnitude faster. You can go from feedback to fix to re-test in minutes, not weeks.

> "Many of the same concepts we use for people will be directly applicable to agents. For example, feedback forms and 'net promoter score' (i.e., would you recommend this tool to your fellow agents?). I'm already using this for tools. By robots, for robots."

### 10. The Flywheel Compounds

Each session makes the next one better. This is easy to say abstractly, so here's concretely how it works:

**Session N produces raw data.** CASS automatically logs every agent session: what prompts were given, what tools were used, what worked, what failed, how long things took, what the agent's final output was.

**Between sessions, CM (CASS Memory) distills patterns.** Running `cm reflect` processes recent sessions and extracts procedural rules like "always run `cargo check` after modifying Cargo.toml" or "the `--robot-triage` flag is more useful than `--robot-next` for projects with 50+ beads." These rules have confidence scores that decay without reinforcement (90-day half-life) and amplify with repetition.

**Session N+1 starts with those patterns loaded.** Running `cm context "Building an API"` at the start of a session retrieves relevant procedural memory, so the agent begins with knowledge distilled from every previous session that touched similar work.

**Simultaneously, UBS patterns grow.** If agents repeatedly encounter a certain class of bug, that pattern gets added to UBS's rule set. The next scan catches it mechanically.

**Simultaneously, Agent Mail coordination improves.** The file reservation patterns, TTL values, and communication norms that worked well in previous swarms get documented in AGENTS.md and refined in skills.

The compounding is real but not automatic in the early stages. You have to actually run `cm reflect`, actually review CASS session data, actually update AGENTS.md with lessons learned. As you build out the recursive self-improvement layers (Principle 13), more of this becomes automated. But even manually, spending 15 minutes between projects reviewing what worked and updating your AGENTS.md template produces outsized returns on every subsequent project.

### 11. Avoid Vendor Lock-In

> "PSA: you should avoid vendor lock-in for agent coding primitives like task management (e.g., beads) and agent communication (e.g., MCP Agent Mail) so you can use all the agents together, which is more powerful anyway. They want you in a walled garden, but it's 100% unnecessary."

This principle has concrete implications for how you choose tools:

**Use model-agnostic coordination primitives.** Beads (`br`), Agent Mail (`am`), and bv are all CLI tools that work identically regardless of which agent invokes them. A Claude Code agent and a Codex agent and a Gemini agent can all call `br ready --json` and get the same task list. They can all register with Agent Mail and message each other. This means you can mix agents from different providers in the same swarm, which is valuable because different models have different strengths.

**Avoid provider-specific task management.** If you use Claude's built-in task tracking, your Codex agents can't see those tasks. If you use Cursor's internal project context, your Claude agents are blind to it. Beads live in `.beads/` files that commit with your code and are readable by any agent with filesystem access.

**Avoid provider-specific communication.** Same reasoning. Agent Mail is an MCP server that any MCP-capable agent can connect to. If tomorrow a new coding agent from a different provider launches and it supports MCP, it can join your swarm immediately without any integration work.

The practical test: could you swap out every Claude Code agent for Codex or Gemini (or vice versa) without changing your AGENTS.md, your beads, your Agent Mail setup, or your workflow? If yes, you're vendor-neutral. If not, you have lock-in that will cost you when the competitive landscape shifts.

### 12. The Project Is a Foregone Conclusion

Once beads are in good shape based on a great markdown plan, implementation success is essentially guaranteed:

> "Once you have the beads in good shape based on a great markdown plan, I almost view the project as a foregone conclusion at that point. The rest is basically mindless 'machine tending' of your swarm of 5-15 agents."

This claim sounds bold, but it follows logically from everything above. If the plan is thorough (Phase 1-3), and the beads faithfully encode it with full context and correct dependencies (Phase 4-5), and the agents have a clear AGENTS.md (Phase 6), then implementation becomes a mechanical process of agents picking up beads, implementing them, reviewing, and moving on.

**This is true when:**
- the plan has genuinely converged rather than merely become long
- the beads are self-contained enough that fresh agents can execute them without guessing
- the swarm has working coordination, review, and testing loops
- the human is still tending the machine when the flow jams or reality diverges from the plan

**It stops being true when:**
- the architecture is still being invented during implementation
- the bead graph is thin, vague, or missing dependencies
- the swarm cannot coordinate cleanly because `AGENTS.md`, Agent Mail, or `bv` usage is weak

**What "machine tending" actually looks like hour by hour:**

The human's role during implementation is a repeating cycle:

1. **Check bead progress** (`br list --status in_progress --json` or `bv --robot-triage`). Are agents making steady progress? Are any beads stuck?
2. **Handle compactions.** When you see an agent acting confused or repeating itself, send: "Reread AGENTS.md so it's still fresh in your mind." This is the single most common intervention. It takes 5 seconds.
3. **Run periodic reviews.** Every 30-60 minutes, pick an agent and send the "fresh eyes" review prompt. This catches bugs before they compound.
4. **Manage rate limits.** When an agent gets rate-limited, switch its account with `caam activate claude backup-2` or start a new agent with `ntm add PROJECT --cc=1`.
5. **Commit periodically.** Every 1-2 hours, designate one agent to do the organized commit prompt. This keeps the git history clean and ensures all agents see each other's work.
6. **Handle surprises.** Occasionally something comes up during implementation that wasn't anticipated in the plan. Create a new bead for it, or if it's a plan-level issue, update the plan and create new beads.

The key realization is that none of these tasks require deep thought. They're monitoring and maintenance, not design. The hard cognitive work happened during planning. That's why you can tend multiple project swarms simultaneously: set up Project A's swarm, switch to Project B's planning, come back to Project A an hour later and find chunks of work done.

**When the "foregone conclusion" breaks down:**

It breaks when any of the upstream steps were weak:
- **Vague beads**: agents start improvising, producing inconsistent implementations
- **Missing dependencies**: agents work on tasks whose prerequisites aren't done yet
- **Thin AGENTS.md**: agents don't know the project conventions and produce non-idiomatic code
- **No Agent Mail**: agents step on each other's files without coordination

If you find yourself doing heavy cognitive work during implementation, that's a signal that your planning or bead polishing was insufficient. The remedy is usually to pause implementation, go back to bead space, and add the missing detail.

### 13. Recursive Self-Improvement: The Meta-Skill Pattern

This is the most advanced concept in the flywheel, and the one that separates linear productivity gains from exponential ones. The core idea: **your agent toolchain should improve itself using its own output as fuel.**

Most developers treat skills and tools as static artifacts. You write a skill, agents use it, and if it works well enough, you move on. The recursive approach instead treats every agent session as training data for the next version of the skill, creating a tight feedback loop where the system gets measurably better each cycle without additional human effort.

#### Why This Matters Practically

Consider what happens without recursive improvement. You build a CLI tool, write a Claude Code skill for it, and deploy both. Agents use the tool, but they misinterpret certain flags, forget to pass required arguments, or use workarounds because the skill's instructions were ambiguous. Every agent that hits the same snag wastes the same tokens re-discovering the same workaround. Multiply that across dozens of agents and hundreds of sessions, and the waste is enormous.

Now consider the alternative: after those sessions happen, you automatically mine them, discover the failure patterns, rewrite the skill to prevent them, and the next wave of agents never hits those snags at all. The skill becomes a living document shaped by real usage rather than a guess about how agents will behave.

> "Using skills to improve skills, skills to improve tool use, and then feeding the actual experience in the form of session logs (surfaced and searched by my cass tool and /cass skill) back into the design skill for improving the tool interface to make it more natural and intuitive and powerful for the agents. Then taking that revised tool and improving the skill for using that tool, then rinse and repeat."

#### How to Actually Do This (Step by Step)

**Step 1: Build the baseline.** Create a tool. Create a skill for it using `sc` (skill creator). The first version of the skill will be imperfect; that's expected. Ship it anyway.

**Step 2: Let agents use it in real work.** Don't test in isolation. Deploy the tool and skill into actual project work where agents are implementing beads, running reviews, doing real tasks. CASS automatically logs every session.

**Step 3: Mine the sessions.** After 10+ sessions of real usage, search CASS for sessions where agents invoked the tool:

```bash
cass search "tool_name" --workspace /data/projects/PROJECT --json --limit 100
```

What to look for in the results:

- **Clarifying questions**: where agents asked "do you mean X or Y?" means the skill was ambiguous
- **Repeated mistakes across different agents**: a systematic gap in the skill's instructions
- **Creative workarounds**: agents inventing their own approach means the skill is missing a useful pattern
- **Outright failures**: the skill directed agents to do something wrong or impossible

**Step 4: Feed findings into a rewrite.** Give the session analysis to a fresh agent along with the current skill file. Ask it to rewrite the skill to fix every issue. This is the "skill-refiner meta skill" in action:

> "This is the way. Make a skill-refiner meta skill. CASS is unbelievably handy for this."

The key insight is that this rewriting step itself can be a skill. You can write a meta-skill whose entire purpose is: take a skill file + CASS session data as input, produce a better skill file as output. Then the meta-skill can also be refined using its own session data, which is the self-referential property that makes the whole system accelerate:

> "Documentation for this documentation refining tool (so meta -- I should run it on itself, like a snake eating its own tail!)"

**Step 5: Repeat.** The revised skill produces better sessions, which give you better data for the next revision. After 3-4 cycles, the skill is dramatically more reliable than the original. Each cycle takes less human effort than the previous one because the meta-skill itself has improved.

#### The Hidden Knowledge Extraction Principle

The recursive loop has a second, subtler benefit that matters even more at the frontier. Models have internalized vast amounts of academic CS literature: obscure algorithmic techniques, mathematical proofs, design patterns from papers that only a handful of people ever read. Most of this knowledge never surfaces because nobody asks for it with enough precision.

Skills are the mechanism for asking precisely the right questions. Consider the difference:

- **Without a skill**: "Optimize this function." → The agent applies generic improvements like caching, loop unrolling, or reducing allocations. Useful but shallow.
- **With an extreme-optimization skill**: The skill directs the agent to systematically consider cache-oblivious data structures, SIMD vectorization opportunities, branch-free arithmetic, van Emde Boas layout, fractional cascading, and carry-less multiplication, then benchmark before and after each change. → The agent draws on deep knowledge it wouldn't volunteer unprompted.

The skill acts as a key that unlocks specific rooms in the model's knowledge base. Without the key, the model defaults to common patterns. With it, the model reaches into the long tail of techniques that most human developers have never encountered.

> "I'm going over each tool with my extreme optimization skill and applying insane algorithmic lore that Knuth himself probably forgot about already to make things as fast as the metal can go in memory-safe Rust."

> "The knowledge is just sitting there and the models have it. But you need to know how to coax it out of them."

This explains why the recursive loop accelerates rather than plateaus. Each cycle of skill refinement doesn't just fix bugs in the skill's instructions; it also sharpens the skill's ability to extract deeper knowledge from the model. The optimization skill gets better at asking for the right techniques, because CASS sessions reveal which techniques actually produced measurable gains and which were dead ends. The next cycle of optimization is better informed because the previous cycle's results are now part of the feedback corpus.

When you stack enough cycles, the result is code that looks like it was written by someone who read every obscure CS paper ever published, because in a functional sense it was. The agent served as a lens focusing decades of dispersed academic knowledge onto a single practical target, and the skill was the lens prescription.

#### The Four Layers (Start at Layer 1, Not Layer 4)

The recursive pattern operates at increasing levels of ambition. The mistake is trying to build all four layers at once. Start simple and let the need for the next layer emerge naturally.

**Layer 1: Feedback forms after tool use (start here, no infrastructure needed).** After an agent finishes using a tool in a real project, ask it to fill out a structured feedback survey (the prompt from Principle 9b). Feed that feedback to another agent working on the tool itself. This requires nothing beyond two agent sessions and produces immediate, actionable improvements. You can do this today, right now, with any tool.

**Layer 2: CASS-powered skill refinement (requires session logging).** Instead of relying on one agent's opinion, mine session logs to find systematic patterns across many agents. This is qualitatively better than Layer 1 because you see patterns that no single agent would notice from its own experience. An agent using a tool for the first time might blame itself for a confusing flag; when you see 15 agents all struggling with the same flag, you know the flag is the problem.

**Layer 3: Skills that generate work (the system proposes its own improvements).** The `idea-wizard` skill examines a project and generates improvement ideas. The `optimization` skill finds performance bottlenecks. These skills create new beads, which agents implement, which improve the tools, which make the skills more effective:

> "Usually there is a big backlog from the initial planning phase. But then I use my idea wizard skill to generate new features, my optimization skill to speed things up, responding to GH issues, and any other random ideas I have to improve and better integrate the tools."

At this layer, the system is not just refining how it works but actively deciding what to work on next. The idea-wizard examines the project as it currently stands and proposes the highest-leverage improvements, which become beads, which agents implement, which change the project, which the idea-wizard evaluates again in a future cycle. The human's role shifts from directing specific work to curating which generated ideas are worth pursuing.

**Layer 4: Skills bundled with tool installers (the skill improves before the user ever sees it).** The most mature expression: every tool you ship includes a pre-optimized Claude Code skill baked into its installer. The skill was refined through multiple CASS cycles before shipping. When a new user installs the tool, their agents immediately benefit from all the refinement work done across every previous user's sessions:

> "I'm going to start having my tool installers always add a highly optimized skill. It makes a massive difference."

#### Why the Acceleration Compounds

Most productivity techniques produce linear improvements: you get 10% better each cycle, and those gains don't stack. The recursive skill pattern compounds because each cycle improves the tools that perform the next cycle.

When you improve the extreme-optimization skill, every future optimization pass across every tool benefits. When you improve the idea-wizard skill, every future brainstorming session across every project benefits. When you improve the skill-refiner meta-skill, every future skill refinement benefits. The improvements multiply rather than add.

This is the practical meaning of "things accelerating very rapidly." It's not hyperbole; it's the natural consequence of a system where the output of each cycle is an input to the next:

> "Remember I said I'd do all this crazy stuff by early February? I did, and since then I've ramped things up even more dramatically."

The tools produced by the recursive loop are the tools that produce the next tools. This is why the Knuth analogy is apt: it is genuinely the same concept as a compiler that compiles itself, except applied to the entire agent-driven development workflow rather than just a compiler.

---

## 21. Operationalizing the Method: Kernel, Operators, and Validation Gates

Up to this point, the guide explains the Flywheel well enough that a strong human or model can follow it. But explanation is not the same thing as operationalization. Once a method matters, it needs to become a contract: what is invariant, which cognitive moves are reusable, what failure modes recur, and what must be true before the workflow advances to the next phase.

This is the layer that turns CASS-mined rituals into skills, skills into `AGENTS.md` blurbs, and those blurbs into more deterministic swarm behavior. Without it, agents imitate the style of the workflow. With it, they can audit whether they are actually following the real method.

### The First-Pass Kernel

In a fuller operationalization pass, you would triangulate this kernel across multiple distillations and anchor it to a quote bank. For this document, a first-pass kernel is enough to make the core method explicit and reusable.

<!-- FLYWHEEL_KERNEL_START v0.1 -->

1. **Global reasoning belongs in plan space.** Do the hardest architectural and product reasoning while the whole project still fits in context.
2. **The markdown plan must be comprehensive before coding starts.** Skeleton-first coding throws away the main advantage of frontier models.
3. **Plan-to-beads is a distinct translation problem.** A good plan does not automatically produce a good bead graph.
4. **Beads are the execution substrate.** Once they are good enough, they should carry enough context that agents no longer need the full markdown plan during execution.
5. **Convergence matters more than first drafts.** Plans and beads both improve through repeated polishing rounds until the changes become small, local, and mostly corrective.
6. **Swarm agents are fungible.** Coordination must live in artifacts and tools, not in special agents or unstated tribal knowledge.
7. **Coordination must survive crashes and compaction.** `AGENTS.md`, Agent Mail, bead state, and robot modes exist to keep work moving when sessions die.
8. **Session history is part of the system.** Repeated prompts, failures, and recoveries should be mined via CASS and folded back into tools, skills, `AGENTS.md`, and validators.
9. **Implementation is not the finish line.** Review, testing, UBS, and feedback-to-infrastructure loops are part of the core method, not cleanup.

<!-- FLYWHEEL_KERNEL_END v0.1 -->

### Operator Library

The recurring moves below show up throughout real Flywheel sessions. These operators matter more than any single prompt because they say when to apply a move, what failure looks like, and what output is expected.

#### Operator 1: Plan-First Expansion

**Definition**: Move scope, architecture, and workflow reasoning upward into markdown before code exists.

**When-to-Use Triggers**:
- The project still fits in a plan but would explode in size once implemented
- Multiple architectural paths are plausible
- The desired user workflow is still fuzzy

**Failure Modes**:
- Skeleton-first coding that locks in bad boundaries
- Treating local code exploration as a substitute for product reasoning

**Prompt Module**:
```text
[OPERATOR: plan-first-expansion]
1) Restate the goals, workflows, and constraints in concrete terms.
2) Expand the markdown plan until the main architectural and user-flow decisions are explicit.
3) Do not start coding until the plan covers testing, failure paths, and sequencing.

Output (required): revised markdown plan with clarified workflows, architecture, and test obligations.
```

**Canonical tag**: `plan-first-expansion`

#### Operator 2: Competing-Plan Triangulation

**Definition**: Generate multiple independent plan candidates and synthesize the strongest consensus into a single superior plan.

**When-to-Use Triggers**:
- The project is important enough that one model's biases are dangerous
- You want broader architectural search before committing to a direction
- Early drafts feel plausible but not obviously excellent

**Failure Modes**:
- Picking the first decent plan and calling it done
- Combining every idea indiscriminately instead of filtering for quality

**Prompt Module**:
```text
[OPERATOR: competing-plan-triangulation]
1) Collect independent plans from multiple strong frontier models.
2) Compare them for better ideas, missing concerns, and incompatible assumptions.
3) Integrate only the strongest elements into one revised plan.

Output (required): a single merged markdown plan plus explicit notes on what changed and why.
```

**Canonical tag**: `competing-plan-triangulation`

#### Operator 3: Overshoot Mismatch Hunt

**Definition**: Force the model to keep searching for plan or bead flaws by giving it a deliberately high miss count target.

**When-to-Use Triggers**:
- Review output looks too short or self-satisfied
- You suspect the model stopped after finding a "reasonable" number of problems
- A large plan or bead graph still feels under-audited

**Failure Modes**:
- Asking for "all problems" and getting a shallow pass
- Accepting a review that found only the most obvious issues

**Prompt Module**:
```text
[OPERATOR: overshoot-mismatch-hunt]
1) Tell the model it likely missed a large number of issues.
2) Make it compare the artifact against prior feedback or source material again.
3) Require another full pass rather than a small patch list.

Output (required): an expanded list of missed elements, contradictions, and corrections.
```

**Canonical tag**: `overshoot-mismatch-hunt`

#### Operator 4: Plan-to-Beads Transfer Audit

**Definition**: Treat conversion from markdown plan to beads as a coverage-preserving translation problem with its own QA loop.

**When-to-Use Triggers**:
- A large plan is about to be turned into execution tasks
- Agents are creating beads quickly and may drop rationale or testing obligations
- You want to know whether the swarm can operate without repeatedly reopening the plan

**Failure Modes**:
- Assuming a beautiful plan automatically implies good beads
- Creating terse beads that depend on tacit knowledge from the markdown file

**Prompt Module**:
```text
[OPERATOR: plan-to-beads-transfer-audit]
1) Walk every important part of the markdown plan and map it to actual beads.
2) Ensure rationale, constraints, and tests are embedded in the bead descriptions.
3) Identify anything in the plan that has no bead or any bead that has no clear plan backing.

Output (required): coverage report plus bead edits that close the gaps.
```

**Canonical tag**: `plan-to-beads-transfer-audit`

#### Operator 5: Convergence Polish Loop

**Definition**: Re-run plan or bead refinement until changes slow down, output shrinks, and the revisions become mostly local improvements.

**When-to-Use Triggers**:
- A plan or bead graph exists but still has visible rough edges
- The first polishing pass found real issues
- You want to know whether you're near steady state or still far from it

**Failure Modes**:
- Treating the first decent revision as final
- Continuing endless polishing after returns have gone flat

**Prompt Module**:
```text
[OPERATOR: convergence-polish-loop]
1) Re-run a full critical review in a fresh session.
2) Integrate the fixes and compare the magnitude of changes to the previous round.
3) Stop only when the revisions are small, mostly corrective, and coverage checks keep passing.

Output (required): revised artifact plus a judgment of whether it is still in major-change mode or near convergence.
```

**Canonical tag**: `convergence-polish-loop`

#### Operator 6: Fresh-Eyes Reset

**Definition**: Start a fresh session or model pass when context saturation begins to flatten the quality of review.

**When-to-Use Triggers**:
- The agent has already done several long review rounds
- Suggestions are getting repetitive or shallow
- You need a more independent read of the artifact

**Failure Modes**:
- Trusting a tired context window to keep finding subtle flaws
- Mistaking context exhaustion for genuine convergence

**Prompt Module**:
```text
[OPERATOR: fresh-eyes-reset]
1) Start a fresh session.
2) Reload AGENTS.md and the relevant project context.
3) Ask for a full review of the plan or beads as if seeing them for the first time.

Output (required): a fresh critical pass unconstrained by the prior session's local minima.
```

**Canonical tag**: `fresh-eyes-reset`

#### Operator 7: Fungible Swarm Launch

**Definition**: Launch generalist agents into a shared workspace only after coordination primitives are ready and the work frontier is clear.

**When-to-Use Triggers**:
- Beads are polished enough to execute
- Multiple agents are about to work in the same repository
- You want distributed coordination instead of a specialist-agent hierarchy

**Failure Modes**:
- Launching too early, before beads are self-contained
- Letting agent identity or role specialization become load-bearing

**Prompt Module**:
```text
[OPERATOR: fungible-swarm-launch]
1) Confirm AGENTS.md, bead state, Agent Mail, and bv routing are all ready.
2) Start agents in a staggered way and make them claim work immediately.
3) Keep coordination in beads, reservations, and threads rather than in a special overseer agent.

Output (required): an active swarm with claimed work, low collision risk, and no special-agent bottleneck.
```

**Canonical tag**: `fungible-swarm-launch`

#### Operator 8: Feedback-to-Infrastructure Closure

**Definition**: Convert repeated successes and failures from real sessions into better tools, better skills, and better instructions.

**When-to-Use Triggers**:
- The same confusion, prompt, or recovery pattern appears repeatedly in CASS
- Agents complain about a tool, blurb, or workflow
- A project finishes and there are clear lessons worth retaining

**Failure Modes**:
- Treating lessons as anecdotes instead of durable system inputs
- Improving the code but never improving the method that produced it

**Prompt Module**:
```text
[OPERATOR: feedback-to-infrastructure-closure]
1) Mine CASS for repeated prompts, breakdowns, and fixes.
2) Distill the useful patterns into skills, AGENTS.md guidance, blurbs, or tool changes.
3) Update the reusable artifact so the next swarm starts from the improved baseline.

Output (required): a revised reusable artifact plus a short note describing the lesson it now encodes.
```

**Canonical tag**: `feedback-to-infrastructure-closure`

### Validation Gates

The gates below turn the methodology into a contract. If a gate fails, the workflow should drop back a phase instead of pushing forward optimistically.

| Gate | Must be true before advancing | Common failure if skipped |
|------|-------------------------------|---------------------------|
| **Foundation Gate** | Goals, workflows, stack, architecture direction, `AGENTS.md`, and best-practices guides exist and are coherent | The plan silently absorbs ambiguity that later shows up as confused agents and weak beads |
| **Plan Gate** | The markdown plan covers workflows, architecture, sequencing, constraints, testing expectations, and major failure paths | Agents improvise architecture during coding from a narrow local window |
| **Translation Gate** | Every material plan element maps to one or more beads, and the mapping has been checked in both directions | Features, rationale, and tests disappear during conversion |
| **Bead Gate** | Beads are self-contained, dependency-correct, rich in context, and explicit about test obligations | Swarm execution depends on reopening the markdown plan or guessing intent |
| **Launch Gate** | Agent Mail, file reservations, bead IDs, `bv`, `AGENTS.md`, and staggered startup procedures are all ready | Agents collide, duplicate work, or create communication purgatory |
| **Ship Gate** | Reviews, tests, UBS, remaining-work beads, and feedback capture into reusable artifacts are complete | The code ships, but the method does not improve and the same mistakes recur next time |

### Anti-Patterns That Deserve Their Own Alarm Bells

Some failures matter enough that they should be treated as explicit warnings rather than as mere "best practice" suggestions:

- **Verbosity mistaken for completeness**: a long plan that still fails to cover real workflows or failure paths
- **First-draft beads treated as ready**: the most common way to turn a good idea into a buggy swarm
- **Hidden rationale**: critical design decisions left only in the markdown plan instead of being carried into beads
- **Cargo-cult prompts**: copying words that once worked without understanding the trigger and failure mode for the operator behind them
- **Load-bearing agents**: relying on a special reviewer, architect, or coordinator agent instead of fungible swarm behavior
- **Phase skipping**: moving into execution because the artifact feels impressive rather than because the gate actually passed
- **No closure loop**: finishing a project without mining CASS and updating the reusable method artifacts

### How CASS, Skills, `AGENTS.md`, and Validators Fit Together

This section only becomes fully powerful when it is wired into the rest of the Flywheel:

- **CASS** discovers repeated prompts, recurring breakdowns, and successful recoveries.
- **Skills** package the operators and anti-patterns into reusable workflows agents can load on demand.
- **`AGENTS.md`** carries the compressed operating subset that every in-flight agent must keep available after compaction.
- **Validators** turn the gates into scripts, checklists, or CI-enforced contracts.

That is the real progression from tacit method to explicit system: repeated behavior becomes ritual, ritual becomes skill, skill becomes infrastructure, and infrastructure changes what the next swarm can do.

---

## 22. Observed Patterns and Lessons from Real Sessions

### Patterns That Work

**The "30 to 5 to 15" funnel**: When generating ideas, having agents brainstorm 30 then winnow to 5 produces much better results than asking for 5 directly. The winnowing forces critical evaluation.

**Parallel subagents for bulk bead operations**: Creating dozens of beads is faster when dispatched to parallel subagents, each handling a subset. This pattern was used extensively in FrankenSQLite and alien_cs_graveyard projects.

**Staggered agent starts**: Starting agents 30-60 seconds apart avoids the thundering herd problem where multiple agents pick the same bead.

**One agent for git operations**: Designating one agent to handle all commits prevents merge conflicts and produces coherent commit messages.

### Anti-Patterns to Avoid

**Single-pass beads**: First-draft beads are never optimal. Always do 4-5 polishing passes minimum.

**Skipping plan-to-bead validation**: Not cross-referencing beads against the plan leads to missing features discovered only during implementation.

**Communication purgatory**: Agents spending more time messaging each other than actually coding. Be proactive about starting work.

**Holding reservations too long**: File reservations with long TTLs block other agents unnecessarily. Reserve, edit, commit, release.

**Not re-reading AGENTS.md after compaction**: Context compaction loses nuances from AGENTS.md. The re-read is mandatory, not optional.

### Scale Observations from Real Projects

| Project | Beads | Plan Lines | Agents | Time to MVP |
|---------|-------|------------|--------|-------------|
| CASS Memory System | 347+ | 5,500 | ~25 | ~5 hours |
| FrankenSQLite | Hundreds | Large spec | Many parallel | Multi-session |
| Frankensearch | 122+ (3 epics) | - | Multiple | Multi-session |
| Apollobot | 26 | - | Single session | 2-3 polish rounds |

### Ritual Detection via CASS

The flywheel's learning loop depends on mining past sessions to find what actually works. CASS enables **ritual detection**, which means discovering prompts that are repeated so frequently they constitute validated methodology:

| Repetition Count | Status | Action |
|-----------------|--------|--------|
| count >= 10 | **RITUAL** | Validated methodology. Extract into skill. |
| count 5-9 | **Emerging pattern** | Worth investigating further |
| count < 5 | **One-off** | Not generalizable yet |

The mining query:
```bash
cass search "*" --workspace /data/projects/PROJECT --json --fields minimal --limit 500 \
  | jq '[.hits[] | select(.line_number <= 3) | .title[0:80]]
        | group_by(.) | map({prompt: .[0], count: length})
        | sort_by(-.count) | map(select(.count >= 5)) | .[0:30]'
```

User prompts live at lines 1-3 of session entries. The `--fields minimal` flag reduces output 5x. This is how the prompt library in this document was originally discovered and validated. It was not invented top-down; it was mined bottom-up from hundreds of real sessions.

### Common Problems Encountered

1. **Agent Mail CLI availability**: Sometimes the binary wasn't at the expected path; agents fall back to REST API calls
2. **Context window exhaustion**: Agents typically manage 2-3 polishing passes before needing a fresh session
3. **Duplicate beads at scale**: Large bead sets (100+) develop duplicates; dedicated dedup passes are necessary
4. **Plan-bead gap**: The synthesis step sometimes stalls between plan revision and bead creation; always explicitly transition

---

## 23. Practical Considerations

### The Incremental Onboarding Path

For beginners who find the full system overwhelming, here's the recommended layering order:

This is the recommended learning order for the toolchain, not the ideal order of operations inside a serious project. On a real project, the workflow still begins with planning, then beads, then swarm execution.

There is also no single correct session-management layer. You can use NTM, tmux directly, WezTerm mux with one agent per tab, or another setup entirely. The method cares about coordination and operator ergonomics, not about one mandatory terminal multiplexer.

1. **Start with**: Agent Mail + Beads (`br`) + Beads Viewer (`bv`)
2. **Then add**: UBS for bug hunting
3. **Then add**: DCG for destructive command protection
4. **Then add**: CASS for session history
5. **Then add**: CM (CASS Memory) for codifying lessons

Common mistakes beginners make:
- **Slipshod plan**: Making a hasty plan all at once with Claude Code instead of using the multi-model iterative process
- **One-shot beads**: Trying to convert the plan to beads in a single pass. "Well, of course the project is going to suck and be a buggy mess if you do that."
- **Skipping polishing**: Not doing at least 3 rounds of checking, improving, and expanding the beads

### Cost

- ~$500/month for Claude Max and GPT Pro subscriptions (at minimum)
- ~$50/month for a cloud server (OVH, Contabo)
- Multiple Max accounts may be needed for large swarms
- CAAM enables instant switching between accounts when hitting rate limits

At scale: "I have 14 Claude Max accounts and 7 GPT Pro accounts now. If I need to get more then I'll do it." Token usage for a single intensive session can reach ~20M input tokens, ~3.5M output tokens, ~2.6M reasoning tokens, and ~1.15 billion cached token reads.

### Time Investment

- Planning phase: 3+ hours for a complex feature (e.g., the Cass export wizard)
- Plan to beads conversion: Can take significant time (Claude "needed coaxing and cajoling" for 347 beads)
- Bead polishing: 2-3 passes per session, multiple sessions for complex projects
- Implementation: With a good swarm, remarkably fast. The CASS Memory System went from nothing to 11k lines of code in ~5 hours

### Live Status Update (From a Real Session)

A snapshot of the methodology in action, ~5 hours into a project that started from just a plan document:

> "Starting from absolutely nothing ~5 hours ago except a big ol' plan document, I turned that into over 350 beads (we got a bunch of new testing beads), I now have conjured up ~11k lines of code, about 8k of which is the core code and the rest is testing code. Around 204 commits so far. Probably at least 25 agents have been involved at some point or other. For a 'can I use this tool effectively' definition: ~85-90% done. The core ACE pipeline is complete and functional. What remains is mostly test coverage, polish, and future-phase features. If this were a startup product, you'd say: 'MVP shipped, now hardening for production.'"

Another example: CASS itself (a complex Rust program used by thousands of people) was made "in around a week, but I personally only spent a few hours on it; the rest of the time was spent by a swarm of agents implementing and polishing it and writing tests."

### What This Approach Can Produce

> "If you simply use these tools, workflows, and prompts in the way I just described, you can create really incredible software in just a couple days, sometimes in just one day."
>
> "I've done it a bunch of times now in the past few weeks and it really does work, as crazy as that may sound. You see my GitHub profile for the proof of this. It looks like the output from a team of 100+ developers."

### Getting Started

The complete system is free and 100% open-source: https://agent-flywheel.com/

> "You don't even need to know much at all about computers; you just need the desire to learn and some grit and determination."

### The Complete Getting-Started Sequence

```bash
# 1. Rent a VPS (OVH or Contabo, ~$40-56/month, Ubuntu)
# 2. SSH in
ssh ubuntu@your-server-ip

# 3. Run the one-liner
curl -fsSL https://agent-flywheel.com/install.sh | bash

# 4. Reconnect (if was root)
ssh ubuntu@your-server-ip

# 5. Learn the workflow
onboard

# 6. Create your first project
acfs newproj my-first-project --interactive

# 7. Spawn agents
ntm spawn my-first-project --cc=2 --cod=1 --gmi=1

# 8. Start building!
ntm send my-first-project "Let's build something awesome."
```

For a real project, that last `ntm send` line quickly gets replaced by the canonical marching-orders prompt from Section 24 once you have an actual plan and bead graph. The short example above is just enough to get the first session moving.

---

## 24. The Complete Prompt Library

Treat the prompt blocks below as the canonical wording unless a surrounding note explicitly labels something as a contextual or operator-specific variant. Some prompts contain quirks or typos because they are preserved verbatim from prompts that worked well in real sessions.

This guide includes the Flywheel-specific prompts most central to the methodology. For a much larger public prompt collection, see [jeffreysprompts.com](https://jeffreysprompts.com), which has a generous free section. The site is also open source at [Dicklesworthstone/jeffreysprompts.com](https://github.com/Dicklesworthstone/jeffreysprompts.com). There is also a paid Pro tier with additional prompts and a proprietary CLI, `jfp`, for managing prompt collections. The Pro tier is still under active development, so some rough edges are still being worked through; feedback is appreciated, and refunds are available for unhappy users.

### Plan Creation: Multi-Model Synthesis

```
I asked 3 competing LLMs to do the exact same thing and they came up with
pretty different plans which you can read below. I want you to REALLY
carefully analyze their plans with an open mind and be intellectually honest
about what they did that's better than your plan. Then I want you to come up
with the best possible revisions to your plan (you should simply update your
existing document for your original plan with the revisions) that artfully
and skillfully blends the "best of all worlds" to create a true, ultimate,
superior hybrid version of the plan that best achieves our stated goals and
will work the best in real-world practice to solve the problems we are
facing and our overarching goals while ensuring the extreme success of the
enterprise as best as possible; you should provide me with a complete series
of git-diff style changes to your original plan to turn it into the new,
enhanced, much longer and detailed plan that integrates the best of all the
plans with every good idea included (you don't need to mention which ideas
came from which models in the final revised enhanced plan):
```

**Where:** GPT Pro web app with Extended Reasoning

---

### Plan Refinement: Iterative Improvement

```
Carefully review this entire plan for me and come up with your best
revisions in terms of better architecture, new features, changed features,
etc. to make it better, more robust/reliable, more performant, more
compelling/useful, etc. For each proposed change, give me your detailed
analysis and rationale/justification for why it would make the project
better along with the git-diff style changes relative to the original
markdown plan shown below:

<PASTE YOUR EXISTING COMPLETE PLAN HERE>
```

**Where:** GPT Pro web app, fresh conversation each round

---

### Plan Refinement: Integration

```
OK, now integrate these revisions to the markdown plan in-place; be
meticulous. At the end, you can tell me which changes you wholeheartedly
agree with, which you somewhat agree with, and which you disagree with:

[Pasted GPT Pro output]
```

**Where:** Claude Code

---

### Plan to Beads: Conversion

```
OK so please take ALL of that and elaborate on it and use it to create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting (including relevant background, reasoning/justification, considerations, etc.-- anything we'd want our "future self" to know about the goals and intentions and thought process and how it serves the over-arching goals of the project.). The beads should be so detailed that we never nead to consult back to the original markdown plan document. Remember to ONLY use the `br` tool to create and modify the beads and add the dependencies.
```

**Where:** Claude Code (Opus)

**Why it works:** This prompt forces the agent to treat plan-to-beads as a translation problem rather than as mere task extraction. The key sentence is the requirement that the beads be so detailed that you never need to reopen the markdown plan. That pushes rationale, test expectations, design intent, and sequencing into the bead graph itself, which is what later makes swarm execution possible without constant context reloads.

**What it is doing under the hood:** It also blocks a common failure mode where the model collapses a rich plan into terse todo items. By explicitly asking for tasks, subtasks, dependency structure, comments, and future-self context, you are telling the model that memory density matters more than brevity. Restricting it to `br` prevents the agent from drifting into pseudo-beads in markdown instead of editing the actual task graph.

---

### Beads: Iterative Polishing

```
Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY! Also make sure that as part of the beads we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation.  Make sure to ONLY use the `br` cli tool for all changes, and you can and should also use the `bv` tool to help diagnose potential problems with the beads.
```

**Where:** Claude Code (Opus), usually 4-6 rounds across one or more fresh sessions

**Why it works:** This is the prompt that keeps the system from freezing beads too early. It tells the model to stay in plan space for as long as it is still finding meaningful improvements, which is exactly where the reasoning is cheapest and most global. The warnings against oversimplifying and losing functionality are crucial because models otherwise tend to "improve" artifacts by deleting complexity they do not fully understand.

**What it is doing under the hood:** It combines local bead QA with graph QA. `br` handles the actual bead edits, while `bv` gives the model another view of dependency quality, missing structure, and priority weirdness. The prompt also forces tests into the bead definitions themselves, which keeps test work from being deferred into an afterthought.

---

### Beads: Deduplication Check

```
Reread AGENTS.md so it's still fresh in your mind. Check over ALL open
beads. Make sure none of them are duplicative or excessively overlapping...
try to intelligently and cleverly merge them into single canonical beads
that best exemplify the strengths of each.
```

**Where:** Claude Code, after large bead creation batches

---

### Beads: Fresh Eyes Review

```
First read ALL of the AGENTS.md file and README.md file super carefully and
understand ALL of both! Then use your code investigation agent mode to fully
understand the code, and technical architecture and purpose of the project.
```

Then:

```
We recently transformed a markdown plan file into a bunch of new beads. I
want you to very carefully review and analyze these using `br` and `bv`.
```

**Where:** New Claude Code session

---

### Implementation: Agent Marching Orders

```
First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Then register with MCP Agent Mail and introduce yourself to the other agents. Be sure to check your agent mail and to promptly respond if needed to any messages; then proceed meticulously with your next assigned beads, working on the tasks systematically and meticulously and tracking your progress via beads and agent mail messages. Don't get stuck in "communication purgatory" where nothing is getting done; be proactive about starting tasks that need to be done, but inform your fellow agents via messages when you do so and mark beads appropriately. When you're not sure what to do next, us the bv tool mentioned in AGENTS.md to prioritize the best beads to work on next; pick the next one that you can usefully work on and get started. Make sure to acknowledge all communication requests from other agents and that you are aware of all active agents and their names. *CRITICAL*: All cargo builds and tests and other CPU intensive operations MUST be done using rch to offload them!!! see AGENTS.md for details on how to do this!!!
```

**Where:** Every agent in the swarm (via `ntm send`)

**Why it works:** This is the closest thing to a canonical swarm kickoff packet. It front-loads the shared operating context, forces the agent to establish social presence through Agent Mail, and then immediately pivots it away from passive waiting and toward actual execution. The line about "communication purgatory" matters because swarm failure often comes from over-coordination rather than under-coordination.

**What it is doing under the hood:** The prompt establishes a control loop: load rules, understand the codebase, join the coordination layer, claim work, keep state synchronized, and use `bv` whenever local judgment is insufficient. The `rch` requirement is especially important in real swarms because it externalizes expensive builds and tests, preventing local CPU contention from degrading the entire multi-agent system. That one sentence is operational, not cosmetic.

---

### Review: Self-Review

```
great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with "fresh eyes" looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.
```

**Where:** Each agent after completing a bead

**Why it works:** This prompt is short because it is not trying to redirect the agent into a new domain of work. It is only trying to force a mode switch from generative coding to adversarial reading. That transition catches a surprising number of mistakes because the agent still has the implementation fresh in memory, but the wording nudges it to re-encounter the code as a critic rather than as its author.

**What it is doing under the hood:** The phrase "fresh eyes" is doing real work here. It pushes the model to reframe the just-written code as something potentially wrong, confusing, or internally inconsistent. That reduces the common pattern where an agent stops once the code compiles and never performs the immediate low-cost bug sweep that could have fixed obvious issues.

---

### Review: Cross-Agent Review

```
Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!
```

**Where:** Periodically during implementation

**Why it works:** This prompt forces the swarm to stop treating code ownership as sacred. Once multiple agents are working in the same repository, a large share of real defects live at the boundaries between their changes or in assumptions nobody revisits because they were made by "someone else." Cross-agent review converts the swarm from a parallel writing system into a parallel criticism system.

**What it is doing under the hood:** The instruction not to restrict review to the latest commits is important. It prevents shallow PR-style skimming and pushes the agent to trace older surrounding code, dependency surfaces, and adjacent workflows where the real root cause may live. The first-principles wording also matters because it nudges the reviewer away from symptom-fixing and toward actual causal diagnosis.

---

### Context Recovery: Post-Compaction

```
Reread AGENTS.md so it's still fresh in your mind.
```

**Where:** Immediately after any context compaction (the single most commonly used prompt)

**Why it works:** Compaction wipes out the soft operational knowledge that keeps the swarm sane: how to behave, how to coordinate, what tools exist, what rules matter, and what kinds of mistakes to avoid. The reread prompt restores that control plane in one move.

**What it is doing under the hood:** It rehydrates the agent's behavioral contract after context loss. In practice, this prompt is important enough that the reminder has been automated for Claude Code with `/dp/post_compact_reminder`. That is a clean example of good operationalization: discover the ritual first, then automate it.

---

### Swarm Diagnosis: High-Level Reality Check

```
Where are we on this project? Do we actually have the thing we are trying to build? If not, what is blocking us? If we intelligently implement all open and in-progress beads, would we close that gap completely? Why or why not?
```

**Where:** When the swarm looks active but you suspect it is not actually closing the real gap to the goal

**Why it works:** This prompt breaks the spell of local productivity. Instead of asking whether the current bead is going well, it asks whether the current frontier of work actually converges on the project outcome. That is the right question when a swarm feels busy but directionally off.

**What it is doing under the hood:** It forces an agent with accumulated code context to compare the real project state against the actual goal and the current bead graph. If the agent concludes that finishing the current open/in-progress beads still would not get you there, the answer is not "work harder." The answer is to revise the bead graph and re-aim the swarm.

---

### Navigation: Move to Next Bead

```
Reread AGENTS.md so it's still fresh in your mind. Use bv with the robot
flags (see AGENTS.md for info on this) to find the most impactful bead(s)
to work on next and then start on it. Remember to mark the beads
appropriately and communicate with your fellow agents. Pick the next bead
you can actually do usefully now and start coding on it immediately;
communicate what you're working on to your fellow agents and mark beads
appropriately as you work. And respond to any agent mail messages you've
received.
```

**Where:** After reviews come up clean

---

### Execution: Ad-Hoc TODO Mode

```
OK, please do ALL of that now. Keep a super detailed, granular, and complete TODO list of all items so you don't lose track of anything and remember to complete all the tasks and sub-tasks you identified or which you think of during the course of your work on these items!
```

**Where:** Quick, bounded changes that are not worth full bead formalization upfront

**Why it works:** This prompt forces the agent to externalize its local execution plan into a durable checklist instead of trying to juggle a sprawling ad-hoc task in conversational memory. In tools that support a built-in TODO system, that checklist survives compaction. That makes the prompt especially useful for medium-sized one-off changes.

**What it is doing under the hood:** It creates a temporary execution scaffold that is lighter than full bead creation and much safer than "just remember everything." This is the right mode when the work is too small to justify immediate bead formalization but too large to trust to ephemeral context alone.

**When not to use it:** If the change is expanding, depends on other work, needs graph-aware sequencing, or should be part of the permanent project record from the start, stop and turn it into proper beads instead. If an ad-hoc change later proves important, you can retroactively create beads for the completed work to preserve continuity and documentation.

---

### Testing: Coverage Check

```
Do we have full unit test coverage without using mocks/fake stuff? What
about complete e2e integration test scripts with great, detailed logging? If
not, then create a comprehensive and granular set of beads for all this with
tasks, subtasks, and dependency structure overlaid with detailed comments.
```

**Where:** After all implementation beads are completed

---

### UI/UX: General Polish

```
Great, now I want you to super carefully scrutinize every aspect of the
application workflow and implementation and look for things that just seem
sub-optimal or even wrong/mistaken to you, things that could very obviously
be improved from a user-friendliness and intuitiveness standpoint, places
where our UI/UX could be improved and polished to be slicker, more visually
appealing, and more premium feeling and just ultra high quality, like
Stripe-level apps.
```

---

### UI/UX: Platform-Specific Deep Polish

```
I still think there are strong opportunities to enhance the UI/UX look and
feel and to make everything work better and be more intuitive, user-
friendly, visually appealing, polished, slick, and world class in terms of
following UI/UX best practices like those used by Stripe, don't you agree?
And I want you to carefully consider desktop UI/UX and mobile UI/UX
separately while doing this and hyper-optimize for both separately to play
to the specifics of each modality. I'm looking for true world-class visual
appeal, polish, slickness, etc. that makes people gasp at how stunning and
perfect it is in every way.
```

---

### Bug Hunting: Random Exploration

```
I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file.
```

**Why it works:** This prompt breaks the locality trap. If you only inspect code adjacent to the last bead or last commit, you mostly find local mistakes. Random exploration forces the agent to sample the codebase in a broader way, follow import and execution edges, and reconstruct workflows from the code outward. That is exactly how you catch boundary bugs, incoherent assumptions, and implementation drift.

**What it is doing under the hood:** The prompt first asks the agent to build a mental model of purpose and flow, then asks for criticism. That ordering matters. A bug hunt without workflow understanding tends to degrade into linting; a bug hunt after tracing execution flows is much more likely to catch logic errors, mismatched assumptions, and silent product-level breakage.

**Why you should alternate this with the cross-agent review prompt:** These two prompts reliably activate different search modes in the model. The cross-agent review prompt tends to induce a suspicious, adversarial stance focused on boundaries, regressions, hidden bad assumptions, and causal root diagnosis in code written by others. The random-exploration prompt tends to induce a curiosity-driven, systems-mapping stance focused on workflow reconstruction, execution tracing, and latent bugs that are not obviously tied to a recent change. In practice, alternating them produces better coverage than repeating either one alone. This is one of the more art-than-science parts of the methodology: prompt framing changes the agent's effective "theory of mind" about what kind of mistake it is supposed to be looking for.

---

### README: The README Reviser

```
OK, we have made tons of recent changes that aren't yet reflected in the
README file. First, reread AGENTS.md so it's still fresh in your mind.
Now, we need to revise the README for these changes (don't write about them
as "changes" however, make it read like it was always like that, since we
don't have any users yet!). Also, what else can we put in there to make the
README longer and more detailed about what we built, why it's useful, how
it works, the algorithms/design principles used, etc? This should be
incremental NEW content, not replacement for what is there already.
```

**Where:** After significant implementation work

---

### Review: Catch-All Oversight

```
Great. Look over everything again for any obvious oversights or omissions
or mistakes, conceptual errors, blunders, etc.
```

**Where:** After any significant change, as a quick final sanity check

---

### Plan Refinement: The "Lie to Them" Exhaustive Check

```
Do this again, and actually be super super careful: can you please check
over the plan again and compare it to all that feedback I gave you? I am
positive that you missed or screwed up at least 80 elements of that
complex feedback.
```

**Where:** During plan revision, when initial comparison only finds ~20 issues

---

### Committing: Organized Git Operations

```
Now, based on your knowledge of the project, commit all changed files now
in a series of logically connected groupings with super detailed commit
messages for each and then push. Take your time to do it right. Don't edit
the code at all. Don't commit obviously ephemeral files.
```

---

### [CASS Memory](https://github.com/Dicklesworthstone/cass_memory_system): Context Retrieval

CM implements a three-layer memory architecture:

```
EPISODIC MEMORY (cass): Raw session logs from all agents
         ↓ cass search
WORKING MEMORY (Diary): Structured session summaries
         ↓ reflect + curate
PROCEDURAL MEMORY (Playbook): Distilled rules with confidence scores
```

Rules have a **90-day confidence half-life** (decays without feedback) and a **4x harmful multiplier** (one mistake counts 4x as much as one success). Rules mature through stages: `candidate` → `established` → `proven`.

```bash
cm context "Building an API" --json   # Get relevant memories for a task
cm recall "authentication patterns"   # Search past sessions
cm reflect                            # Update procedural memory from recent sessions
cm mark b-8f3a2c --helpful            # Reinforce a useful rule
cm mark b-xyz789 --harmful --reason "Caused regression"  # Flag a bad rule
```

**Where:** At the start of a session, to give agents context from past work. The `cm context` command is the single most important pre-task ritual.

---

### Idea-Wizard: Generate Ideas for Existing Projects

```
Come up with 30 ideas for improvements, enhancements, new features, or
fixes for this project. Then winnow to your VERY best 5 and explain why
each is valuable.
```

Then: `ok and your next best 10 and why.`

**Where:** Claude Code, for existing projects needing new features

---

### Meta-Skill: Skill Refinement via CASS Mining

```
Search CASS for all sessions where agents used the [SKILL] skill. Look for:
patterns of confusion, repeated mistakes, steps agents skipped, workarounds
they invented, and things they did that weren't in the skill but should be.

Then rewrite the skill to fix every issue you found. Make the happy path
obvious, add guardrails for the common mistakes, and incorporate the best
workarounds as official steps. Test the rewritten skill against the failure
cases from the session logs.
```

**Where:** Claude Code, targeting any skill with 10+ CASS sessions of usage data. This is the meta-skill pattern in action, specifically the skill-refiner skill.

---

### Documentation: De-Slopify

```
I want you to read through the complete text carefully and look for any
telltale signs of "AI slop" style writing; one big tell is the use of
emdash. You should try to replace this with a semicolon, a comma, or just
recast the sentence accordingly so it sounds good while avoiding emdash.

Also, you want to avoid certain telltale writing tropes, like sentences of
the form "It's not [just] XYZ, it's ABC" or "Here's why" or "Here's why it
matters:". Basically, anything that sounds like the kind of thing an LLM
would write disproportionately more commonly than a human writer and which
sounds inauthentic/cringe.

And you can't do this sort of thing using regex or a script, you MUST
manually read each line of the text and revise it manually in a systematic,
methodical, diligent way.
```

**Where:** After agents write README or any user-facing documentation

---

### Tool Feedback: Agent Satisfaction Survey

```
Based on your experience with [TOOL] today in this project, how would you
rate [TOOL] across multiple dimensions, from 0 (worst) to 100 (best)? Was
it helpful to you? Did it flag a lot of useful things that you would have
missed otherwise? Did the issues it flagged have a good signal-to-noise
ratio? What did it do well, and what was it bad at? Did you run into any
errors or problems while using it?

What changes to [TOOL] would make it work even better for you and be more
useful in your development workflow? Would you recommend it to fellow
coding agents? How strongly, and why or why not? The more specific you can
be, and the more dimensions you can score [TOOL] on, the more helpful it
will be for me as I improve it and incorporate your feedback to make [TOOL]
even better for you in the future!
```

**Where:** After agents have used a tool extensively in a real project. Pipe the output into another agent working on the tool itself for immediate improvements.

---

*Synthesized from ~75+ substantive X posts by [@doodlestein](https://x.com/doodlestein) (Jeffrey Emanuel) mined via [xf](https://github.com/Dicklesworthstone/xf) archive search, the [Agentic Coding Flywheel Setup](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup) documentation, and real-world usage patterns from coding agent session history via CASS. Source posts compiled in [COMPLETE_X_POSTS_ABOUT_PLANNING_AND_BEADS.md](./COMPLETE_X_POSTS_ABOUT_PLANNING_AND_BEADS.md).*
