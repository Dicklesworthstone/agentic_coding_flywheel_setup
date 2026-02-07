// ============================================================
// AGENTIC CODING FLYWHEEL - The Complete Multi-Agent Ecosystem
// ============================================================
//
// A self-reinforcing system that enables remarkable velocity in
// complex software development. Multiple AI agents working in
// parallel across 8+ projects, reviewing each other's work,
// creating and executing tasks, making incredible autonomous
// progress.
//
// The power comes from composition: three tools used together
// deliver 10x what any single tool can achieve alone.
// ============================================================

import { getManifestTool } from './manifest-adapter';

export type FlywheelTool = {
  id: string;
  name: string;
  shortName: string;
  href: string;
  icon: string;
  color: string;
  tagline: string;
  description: string;
  deepDescription: string;
  connectsTo: string[];
  connectionDescriptions: Record<string, string>;
  stars?: number;
  demoUrl?: string;
  features: string[];
  cliCommands?: string[];
  installCommand?: string;
  language: string;
};

export type WorkflowScenario = {
  id: string;
  title: string;
  description: string;
  steps: Array<{
    tool: string;
    action: string;
    result: string;
  }>;
  outcome: string;
  timeframe: string;
};

export type AgentPrompt = {
  id: string;
  title: string;
  category: "exploration" | "review" | "improvement" | "planning" | "execution";
  prompt: string;
  whenToUse: string;
  bestWith: string[];
};

// ============================================================
// WORKFLOW SCENARIOS - How the tools work together in practice
// ============================================================

export const workflowScenarios: WorkflowScenario[] = [
  {
    id: "daily-parallel",
    title: "Daily Parallel Progress",
    description:
      "Keep multiple projects moving forward simultaneously, even when you don't have mental bandwidth for all of them.",
    steps: [
      {
        tool: "ntm",
        action: "Spawn agents across 3 projects: `ntm spawn proj1 --cc=2 proj2 --cod=1 proj3 --gmi=1`",
        result: "6 agents running in parallel across your machines",
      },
      {
        tool: "bv",
        action: "Each agent runs `bv --robot-triage` to find what to work on",
        result: "Agents autonomously select high-priority unblocked tasks",
      },
      {
        tool: "mail",
        action: "Agents coordinate via mail threads when their work overlaps",
        result: "No file conflicts, clear communication trails",
      },
      {
        tool: "cm",
        action: "Memory system provides context from previous sessions",
        result: "Agents don't repeat past mistakes or rediscover solutions",
      },
    ],
    outcome: "Come back 3+ hours later to find incredible autonomous progress across all projects",
    timeframe: "3+ hours of autonomous work",
  },
  {
    id: "agent-review",
    title: "Agents Reviewing Agents",
    description: "Have your agents review each other's work to catch bugs, errors, and issues before they become problems.",
    steps: [
      {
        tool: "cass",
        action: "Agent searches prior sessions: `cass search 'authentication flow' --robot`",
        result: "Finds all previous work on the topic across all agents",
      },
      {
        tool: "ubs",
        action: "Bug scanner runs: `ubs . --format=json`",
        result: "Static analysis catches issues in 7 languages",
      },
      {
        tool: "br",
        action: "Creates beads for each issue: `br create --title='Fix auth bug'`",
        result: "Issues tracked with dependencies and priorities",
      },
      {
        tool: "slb",
        action: "Dangerous fixes require approval: `slb run 'git reset --hard'`",
        result: "Two-person rule prevents catastrophic mistakes",
      },
    ],
    outcome: "Multiple agents catching each other's errors before they ship",
    timeframe: "Continuous improvement loop",
  },
  {
    id: "massive-planning",
    title: "5,500 Lines to 347 Beads",
    description:
      "Transform massive planning documents into executable, dependency-tracked task graphs that agents can work through systematically.",
    steps: [
      {
        tool: "bv",
        action: "Create granular beads with dependency structure",
        result: "347 tasks with clear blocking relationships",
      },
      {
        tool: "mail",
        action: "Agents claim tasks and communicate progress",
        result: "Coordination without conflicts",
      },
      {
        tool: "cass",
        action: "Search for prior art and existing solutions",
        result: "Reuse patterns, avoid reinventing",
      },
      {
        tool: "cm",
        action: "Store successful approaches as procedural memory",
        result: "Future agents learn from successes",
      },
    ],
    outcome: "Project nearly complete the same day, agents pushing commits while you're in bed",
    timeframe: "~1 day for complex feature",
  },
  {
    id: "fresh-eyes",
    title: "Fresh Eyes Code Review",
    description: "Have agents deeply investigate code with fresh perspectives, finding bugs that humans miss.",
    steps: [
      {
        tool: "cass",
        action: "Agent explores codebase, tracing execution flows",
        result: "Deep understanding of how code actually works",
      },
      {
        tool: "ubs",
        action: "Static analysis with 18 detection categories",
        result: "Null safety, async bugs, security issues found",
      },
      {
        tool: "cm",
        action: "Cross-reference with memory of past bugs",
        result: "Pattern recognition across projects",
      },
      {
        tool: "bv",
        action: "Critical issues become blocking beads",
        result: "Nothing ships until issues resolved",
      },
    ],
    outcome: "Systematic, methodical bug discovery and correction",
    timeframe: "Continuous",
  },
  {
    id: "multi-repo-morning",
    title: "Multi-Repo Morning Sync",
    description: "Start your day with all repos synced, agents spawned, and ready to execute tasks across the fleet.",
    steps: [
      {
        tool: "ru",
        action: "Sync all repos: `ru sync -j4 --autostash`",
        result: "20+ repos cloned/updated in under 2 minutes",
      },
      {
        tool: "ru",
        action: "Check status: `ru status --fetch`",
        result: "See which repos have unpushed commits or conflicts",
      },
      {
        tool: "ntm",
        action: "Spawn agents into key repos: `ntm spawn proj1 --cc=2 proj2 --cc=2`",
        result: "4 Claude agents ready across 2 projects",
      },
      {
        tool: "bv",
        action: "Each agent runs `bv --robot-triage` to find work",
        result: "Agents autonomously select high-impact tasks",
      },
    ],
    outcome: "Full fleet of repos synced and agents working before your first coffee is done",
    timeframe: "< 10 minutes to full productivity",
  },
  {
    id: "agent-sweep-bulk",
    title: "Bulk AI Commit Automation",
    description: "Use RU's Agent Sweep to intelligently commit dirty repos across your entire fleet with AI-generated commit messages.",
    steps: [
      {
        tool: "ru",
        action: "Preview sweep: `ru agent-sweep --dry-run`",
        result: "See which repos have uncommitted changes",
      },
      {
        tool: "ru",
        action: "Run sweep: `ru agent-sweep --parallel 4`",
        result: "AI analyzes each repo, creates intelligent commits",
      },
      {
        tool: "ntm",
        action: "Agent Sweep spawns Claude agents via ntm robot mode",
        result: "Three-phase workflow: understand → plan → execute",
      },
      {
        tool: "bv",
        action: "Update beads as work is committed",
        result: "Tasks auto-close when related commits push",
      },
    ],
    outcome: "20+ repos committed with intelligent, contextual messages while you're away",
    timeframe: "30 mins - 2 hours depending on repo count",
  },
  {
    id: "resource-protected-swarm",
    title: "Resource-Protected Agent Swarm",
    description:
      "Run multiple heavy agents simultaneously without your workstation becoming unresponsive. SRPS keeps everything smooth.",
    steps: [
      {
        tool: "srps",
        action: "Verify SRPS is running: `systemctl status ananicy-cpp`",
        result: "ananicy-cpp daemon is active, auto-managing process priorities",
      },
      {
        tool: "ntm",
        action: "Launch heavy multi-agent session: `ntm spawn proj1 --cc=2 proj2 --cod=2`",
        result: "4 agents start, each spawning compilers and test runners",
      },
      {
        tool: "srps",
        action: "Monitor in real-time: `sysmoni`",
        result: "See agents' subprocesses being auto-deprioritized as they spawn",
      },
      {
        tool: "slb",
        action: "Add more agents safely: `slb run 'ntm spawn proj3 --gmi=2'`",
        result: "Even with 6 agents, terminal stays responsive",
      },
    ],
    outcome: "Run 6+ heavy agents simultaneously without system lockup - SRPS keeps your UI snappy",
    timeframe: "Hours of unattended work without freezes",
  },
];

// ============================================================
// AGENT PROMPTS - The actual prompts that power the workflow
// ============================================================

export const agentPrompts: AgentPrompt[] = [
  {
    id: "exploration",
    title: "Deep Code Exploration",
    category: "exploration",
    prompt: `I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them.`,
    whenToUse: "When you want agents to find hidden bugs and understand the codebase deeply",
    bestWith: ["cass", "ubs", "bv"],
  },
  {
    id: "peer-review",
    title: "Agent Peer Review",
    category: "review",
    prompt: `Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!`,
    whenToUse: "After agents have been working independently, have them review each other",
    bestWith: ["mail", "cass", "ubs"],
  },
  {
    id: "ux-polish",
    title: "UX/UI Deep Scrutiny",
    category: "improvement",
    prompt: `I want you to super carefully scrutinize every aspect of the application workflow and implementation and look for things that just seem sub-optimal or even wrong/mistaken to you, things that could very obviously be improved from a user-friendliness and intuitiveness standpoint, places where our UI/UX could be improved and polished to be slicker, more visually appealing, and more premium feeling and just ultra high-quality, like Stripe-level apps.`,
    whenToUse: "When dissatisfied with UX but don't have energy to grapple with it directly",
    bestWith: ["bv", "cm"],
  },
  {
    id: "beads-creation",
    title: "Comprehensive Beads Planning",
    category: "planning",
    prompt: `OK so please take ALL of that and elaborate on it more and then create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting (including relevant background, reasoning/justification, considerations, etc.-- anything we'd want our "future self" to know about the goals and intentions and thought process and how it serves the over-arching goals of the project.)`,
    whenToUse: "After generating improvement suggestions, turn them into actionable tasks",
    bestWith: ["bv", "mail"],
  },
  {
    id: "beads-validation",
    title: "Plan Space Validation",
    category: "planning",
    prompt: `Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things!`,
    whenToUse: "Before executing a large batch of beads, validate the plan",
    bestWith: ["bv"],
  },
  {
    id: "systematic-execution",
    title: "Systematic Bead Execution",
    category: "execution",
    prompt: `OK, so start systematically and methodically and meticulously and diligently executing those remaining beads tasks that you created in the optimal logical order! Don't forget to mark beads as you work on them.`,
    whenToUse: "After planning and validation, execute the work",
    bestWith: ["bv", "mail", "slb", "ru"],
  },
  {
    id: "fresh-eyes-review",
    title: "Post-Implementation Review",
    category: "review",
    prompt: `Great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with "fresh eyes" looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.`,
    whenToUse: "After a batch of implementation work, review everything",
    bestWith: ["ubs", "cass"],
  },
  {
    id: "smart-commit",
    title: "Intelligent Commit Grouping",
    category: "execution",
    prompt: `Now, based on your knowledge of the project, commit all changed files now in a series of logically connected groupings with super detailed commit messages for each and then push. Take your time to do it right. Don't edit the code at all. Don't commit obviously ephemeral files.`,
    whenToUse: "Final step after all work is done",
    bestWith: ["slb", "ru"],
  },
];

// ============================================================
// SYNERGY EXPLANATIONS - Why using multiple tools is 10x better
// ============================================================

export const synergyExplanations = [
  {
    tools: ["ntm", "mail", "bv"],
    title: "The Core Loop",
    description:
      "NTM spawns agents that register with Mail for coordination. They use BV to find tasks to work on. The result: autonomous agents that figure out what to do next without human intervention.",
    multiplier: "10x",
    example:
      "Spawn 6 agents across 3 projects. Each finds work via BV, coordinates via Mail. You return 3 hours later to merged PRs.",
  },
  {
    tools: ["cass", "cm"],
    title: "Collective Memory",
    description:
      "CASS indexes all agent sessions for instant search. CM stores learnings as procedural memory. Together: agents that never repeat mistakes and always remember what worked.",
    multiplier: "5x",
    example:
      "New agent asks 'how did we handle auth?' CASS finds the answer in 60ms. CM surfaces the playbook that worked.",
  },
  {
    tools: ["ubs", "slb"],
    title: "Safety Net",
    description:
      "UBS catches bugs before they're committed. SLB prevents dangerous commands from running without approval. Together: aggressive automation with guardrails.",
    multiplier: "∞",
    example:
      "Agent finds a bug, wants to `git reset --hard`. SLB requires a second agent to approve. UBS validates the fix before merge.",
  },
  {
    tools: ["mail", "slb"],
    title: "Approval Workflow",
    description:
      "SLB sends approval requests directly to agent inboxes via Mail. Recipients can review context and approve or reject. Fully auditable decision trail.",
    multiplier: "Trust",
    example:
      "Agent proposes database migration. SLB notifies reviewers via Mail. Second agent reviews diff, approves. Audit log preserved.",
  },
  {
    tools: ["bv", "cm"],
    title: "Learned Patterns",
    description:
      "BV tracks task patterns and completion history. CM stores what approaches worked. Together: each new task benefits from all past solutions.",
    multiplier: "Compounding",
    example:
      "Similar bug appears in new project. CM surfaces the pattern. BV creates bead linking to successful prior fix.",
  },
  {
    tools: ["caam", "ntm"],
    title: "Account Orchestration",
    description:
      "CAAM manages API keys for all your agent accounts. NTM spawns agents with the right credentials automatically. Seamless multi-account workflows.",
    multiplier: "Infinite agents",
    example:
      "Rate limited on one Claude account? NTM spawns agents with fresh credentials from CAAM. No manual switching.",
  },
  {
    tools: ["ru", "ntm", "bv"],
    title: "Multi-Repo Orchestra",
    description:
      "RU syncs all your repos with parallel workers. NTM spawns agents into each repo. BV tracks tasks across the entire fleet. Coordinated progress across dozens of projects.",
    multiplier: "N× projects",
    example:
      "Morning: `ru sync -j4`. RU clones 3 new repos, pulls 15 updates. NTM spawns agents. By lunch, beads completed across 8 projects.",
  },
  {
    tools: ["ru", "mail"],
    title: "Repo Coordination",
    description:
      "RU agent-sweep can coordinate via Mail to prevent conflicts. Agents claim repos before committing. Complete audit trail of which agent touched which repo.",
    multiplier: "Conflict-free",
    example:
      "Agent A claims repo-1, Agent B claims repo-2. Both run agent-sweep in parallel. No conflicts, clear ownership.",
  },
  {
    tools: ["dcg", "slb"],
    title: "Layered Safety Net",
    description:
      "DCG blocks dangerous commands before execution. SLB provides a human-in-the-loop confirmation after Claude proposes risky operations. Together they create defense in depth - DCG catches obvious destructive patterns, SLB catches contextual risks that require human judgment.",
    multiplier: "Defense in Depth",
    example:
      "Claude proposes 'rm -rf ./old_code' - DCG blocks it instantly. Claude rephrases to 'mv ./old_code ./archive' - SLB prompts for confirmation before the move.",
  },
  {
    tools: ["dcg", "ntm", "mail"],
    title: "Protected Agent Fleet",
    description:
      "NTM spawns multiple Claude agents. Each agent runs under DCG protection. If one agent attempts something dangerous, DCG blocks it and can notify via Mail so other agents (or you) know what happened.",
    multiplier: "Fleet-wide protection",
    example:
      "Agent 1 working on repo cleanup tries 'git clean -fdx'. DCG blocks it. Mail notification: 'Agent 1 attempted blocked command in project-x'.",
  },
];

// ============================================================
// TOOL DEFINITIONS - Detailed info about each tool
// ============================================================

const _flywheelTools: FlywheelTool[] = [
  {
    id: "ntm",
    name: "Named Tmux Manager",
    shortName: "NTM",
    href: "https://github.com/Dicklesworthstone/ntm",
    icon: "LayoutGrid",
    color: "from-sky-400 to-blue-500",
    tagline: "Multi-agent tmux command center",
    description:
      "Orchestrate multiple AI coding agents across tmux sessions. Spawn Claude, Codex, and Gemini agents in named panes. 80+ commands for session management, prompt broadcasting, file conflict detection, and context rotation. Persistent sessions survive SSH disconnects.",
    deepDescription:
      "NTM transforms tmux into a multi-agent command center with 80+ commands. Spawn agents with type classification (cc/cod/gmi), broadcast prompts with filtering, and use the command palette TUI for quick actions. Features context window monitoring with automatic compaction recovery, checkpoints for session state management, agent profiles/personas for specialized roles, and deep integrations with Agent Mail (file reservations, messaging), CASS (session search), and beads (--robot-bead-* commands). Robot mode (--robot-*) provides JSON output for automation.",
    connectsTo: ["slb", "mail", "cass", "caam", "ru", "srps", "bv", "br", "dcg"],
    connectionDescriptions: {
      slb: "Routes dangerous commands through SLB safety checks",
      mail: "Agents auto-register with Mail; ntm mail commands for messaging; pre-commit guard for file reservations",
      cass: "Direct integration via --robot-cass-search, --robot-cass-context, --robot-cass-status",
      caam: "Quick-switches credentials when spawning new agents",
      ru: "RU agent-sweep uses ntm robot mode for orchestration",
      srps: "SRPS keeps tmux sessions responsive when agents spawn heavy builds",
      bv: "Graph analysis via --robot-plan, --robot-graph for dependency insights",
      br: "Bead management via --robot-bead-create, --robot-bead-claim, --robot-bead-close",
      dcg: "DCG hooks protect agents in NTM sessions from destructive commands",
    },
    stars: 16,
    features: [
      "80+ commands: spawn, send, dashboard, palette, checkpoint, health, and more",
      "Agent types: Claude (cc), Codex (cod), Gemini (gmi) with named panes",
      "Context rotation: monitors usage, warns at 80%, auto-compaction recovery",
      "Command palette TUI with fuzzy search, Catppuccin themes, pinned commands",
      "Robot mode: --robot-status, --robot-snapshot, --robot-plan, --robot-mail",
      "Hooks: pre/post-spawn, pre/post-send, pre/post-shutdown with env vars",
    ],
    cliCommands: [
      "ntm spawn <session> --cc=N --cod=N --gmi=N",
      "ntm send <session> --cc 'prompt'",
      "ntm --robot-status",
      "ntm --robot-snapshot",
      "ntm dashboard <session>",
      "ntm checkpoint save <session> -m 'description'",
    ],
    installCommand:
      "curl --proto '=https' --proto-redir '=https' -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash -s -- --easy-mode",
    language: "Go",
  },
  {
    id: "mail",
    name: "MCP Agent Mail",
    shortName: "Mail",
    href: "https://github.com/Dicklesworthstone/mcp_agent_mail",
    icon: "Mail",
    color: "from-violet-400 to-purple-500",
    tagline: "Gmail for your agents",
    description:
      "A complete coordination system for multi-agent workflows. Agents register identities, send/receive messages, search conversations, and declare file reservations to prevent edit conflicts. HTTP-only FastMCP server with static export and Web UI.",
    deepDescription:
      "Agent Mail is the nervous system of the flywheel. HTTP-only transport (Streamable HTTP) for modern MCP clients. Provides: agent identities (adjective+noun names like 'BlueLake'), threaded GFM messages, FTS5 full-text search, and advisory file reservations. SQLite + Git dual persistence means human-auditable artifacts. 30+ MCP tools including macros for common workflows. Static mailbox export with Ed25519 signing and age encryption for audits. Web UI for exploration and Human Overseer for human-to-agent messaging.",
    connectsTo: ["bv", "cm", "slb", "ntm", "ru"],
    connectionDescriptions: {
      bv: "Task IDs link conversations to Beads issues",
      cm: "Shared memories accessible across sessions",
      slb: "Approval requests delivered to agent inboxes",
      ntm: "NTM-spawned agents auto-register",
      ru: "RU can coordinate repo claims via Mail",
    },
    stars: 1015,
    demoUrl: "https://dicklesworthstone.github.io/cass-memory-system-agent-mailbox-viewer/viewer/",
    features: [
      "Agent identities with adjective+noun names (BlueLake, GreenCastle)",
      "GitHub-flavored Markdown messages with threading",
      "Advisory file reservations with pre-commit guard enforcement",
      "FTS5 full-text search with boolean operators",
      "Contact policies with auto-allow heuristics",
      "Static export with Ed25519 signing and age encryption",
      "Web UI and Human Overseer for human-to-agent messaging",
      "Product bus for multi-repo coordination",
    ],
    cliCommands: [
      "mcp-agent-mail serve-http --port 8765",
      "mcp-agent-mail guard install <project> <repo>",
      "mcp-agent-mail share wizard",
      "mcp-agent-mail doctor check --verbose",
    ],
    installCommand:
      'curl --proto \'=https\' --proto-redir \'=https\' -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh" | bash -s -- --yes',
    language: "Python",
  },
  {
    id: "ubs",
    name: "Ultimate Bug Scanner",
    shortName: "UBS",
    href: "https://github.com/Dicklesworthstone/ultimate_bug_scanner",
    icon: "Bug",
    color: "from-rose-400 to-red-500",
    tagline: "1000+ bug patterns for AI workflows",
    description:
      "AST-grep patterns detecting 1000+ bug types across 8 languages. 18 detection categories from null safety to security vulnerabilities. Sub-5-second scans. Auto-wires into Claude Code, Codex, Cursor, Gemini, and Windsurf agents.",
    deepDescription:
      "UBS is a meta-runner that fans out per-language scanners (ubs-js.sh, ubs-python.sh, etc.) and merges results into unified output. Uses ast-grep for AST-based pattern matching with 18 detection categories: null safety, async/await bugs, security holes (XSS, injection), memory leaks, type coercion, and more. Supports --beads-jsonl for Beads integration. The installer auto-detects local coding agents and wires guardrails (on-file-write hooks for Claude Code, .cursorrules blocks).",
    connectsTo: ["bv", "br"],
    connectionDescriptions: {
      bv: "Bug findings create blocking issues via --beads-jsonl output",
      br: "Direct JSONL output for beads_rust issue creation",
    },
    stars: 91,
    features: [
      "8 languages: JS/TS, Python, Go, Rust, C/C++, Java, Ruby, Swift",
      "18 detection categories: security, async, null safety, memory leaks",
      "5 output formats: text, json, jsonl, sarif, toon",
      "Agent guardrails: Claude Code hooks, .cursorrules, .codex/rules",
      "Baseline comparison: --comparison for drift detection",
      "Git-aware: --staged, --diff for targeted scans",
    ],
    cliCommands: [
      "ubs . --format=json",
      "ubs --staged --fail-on-warning",
      "ubs --only=python,js src/",
      "ubs --beads-jsonl findings.jsonl .",
    ],
    installCommand:
      'curl --proto \'=https\' --proto-redir \'=https\' -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/master/install.sh" | bash -s -- --easy-mode',
    language: "Shell",
  },
  {
    id: "bv",
    name: "Beads Viewer",
    shortName: "BV",
    href: "https://github.com/Dicklesworthstone/beads_viewer",
    icon: "GitBranch",
    color: "from-emerald-400 to-teal-500",
    tagline: "Task dependency graphs",
    description:
      "Transforms task tracking with DAG-based analysis. Nine graph metrics, robot protocol for AI, time-travel diffing. Agents use BV to figure out what to work on next.",
    deepDescription:
      "BV treats your project as a Directed Acyclic Graph. Computes PageRank, Betweenness Centrality, HITS, Critical Path, and more. Robot protocol (--robot-*) outputs structured JSON for agents. Time-travel lets you diff across git history.",
    connectsTo: ["br", "mail", "ubs", "cass", "cm", "ru", "ntm"],
    connectionDescriptions: {
      br: "Reads and visualizes issues created by beads_rust (br)",
      mail: "Task updates trigger notifications",
      ubs: "Bug scan results create blocking issues",
      cass: "Search prior sessions for task context",
      cm: "Remembers successful approaches",
      ru: "RU integrates with beads for multi-repo task tracking",
      ntm: "NTM uses --robot-plan, --robot-graph for dependency insights during agent orchestration",
    },
    stars: 546,
    demoUrl: "https://dicklesworthstone.github.io/beads_viewer-pages/",
    features: [
      "9 graph metrics: PageRank, Betweenness, HITS, Critical Path, Eigenvector, Degree, Density, Cycles, Topo Sort",
      "6 TUI views: list, kanban, graph, tree, insights, history",
      "Robot protocol: --robot-triage, --robot-plan, --robot-insights, --robot-alerts, --robot-forecast",
      "11 built-in recipes: actionable, high-impact, bottlenecks, stale, quick-wins",
      "Export to Markdown, HTML (D3.js force-graph), SQLite static sites (--pages)",
      "Live reload on beads.jsonl changes, TOON format for low-token output",
    ],
    cliCommands: [
      "bv --robot-triage",
      "bv --robot-plan --label backend",
      "bv --robot-insights --force-full-analysis",
      "bv --diff-since HEAD~100",
    ],
    installCommand:
      'curl --proto \'=https\' --proto-redir \'=https\' -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh" | bash',
    language: "Go",
  },
  {
    id: "br",
    name: "beads_rust",
    shortName: "BR",
    href: "https://github.com/Dicklesworthstone/beads_rust",
    icon: "ListTodo",
    color: "from-amber-400 to-orange-500",
    tagline: "Rust-powered issue tracking CLI",
    description:
      "Local-first issue tracking for AI agents. SQLite primary storage with JSONL export for git. Dependencies, labels, priorities (P0-P4), blocking relationships. Non-invasive: never runs git commands automatically. The bd alias provides backward compatibility.",
    deepDescription:
      "beads_rust (br) is the ~20K line Rust port of the beads issue tracker. SQLite for fast local queries, JSONL for git-friendly collaboration. Full dependency graph, labels, priorities, comments. Agent-first design: all commands support --json. Explicit sync (flush-only/import-only). Works offline. Doctor diagnostics and schema output (--format toon/json).",
    connectsTo: ["bv", "mail", "ntm", "ru", "ubs"],
    connectionDescriptions: {
      bv: "BV visualizes and analyzes beads from br",
      mail: "Task updates notify agents via mail",
      ntm: "NTM spawns agents that pick work from beads",
      ru: "RU syncs repos containing beads across projects",
      ubs: "UBS --beads-jsonl outputs findings as importable beads",
    },
    stars: 128,
    features: [
      "SQLite + JSONL hybrid: fast queries, git-friendly export",
      "Non-invasive: never runs git commands automatically",
      "Full dependency graph: blocks/blocked-by, cycles detection",
      "Labels, priorities (P0-P4), comments, assignees",
      "Agent-first: all commands support --json/--robot output",
      "Rich terminal output with auto TTY detection, doctor diagnostics",
    ],
    cliCommands: [
      "br create 'Fix bug' --priority 1 --type bug",
      "br list --status open --priority 0-1 --json",
      "br ready --json",
      "br dep add bd-child bd-parent",
      "br sync --flush-only",
    ],
    installCommand:
      'curl --proto \'=https\' --proto-redir \'=https\' -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh" | bash',
    language: "Rust",
  },
  {
    id: "cass",
    name: "Coding Agent Session Search",
    shortName: "CASS",
    href: "https://github.com/Dicklesworthstone/coding_agent_session_search",
    icon: "Search",
    color: "from-cyan-400 to-sky-500",
    tagline: "Instant search across all agents",
    description:
      "Unified search for all AI coding sessions. Indexes 11 agent formats: Claude Code, Codex, Cursor, Gemini, ChatGPT, Cline, Aider, Pi-Agent, Factory, OpenCode, Amp. Tantivy-powered <60ms queries with optional semantic search.",
    deepDescription:
      "CASS unifies session history from 11 agent formats into a single searchable timeline. Three search modes: lexical (BM25 with edge n-grams), semantic (local MiniLM or hash embedder fallback), and hybrid (RRF fusion). Robot mode with cursor pagination, field selection, and token budgeting. HTML export with optional AES-256-GCM encryption. Multi-machine search via SSH/rsync with interactive setup wizard.",
    connectsTo: ["cm", "ntm", "bv"],
    connectionDescriptions: {
      cm: "Indexes stored memories for retrieval",
      ntm: "Searches all NTM-managed session histories",
      bv: "Links search results to related tasks",
    },
    stars: 145,
    features: [
      "11 agent formats: Claude Code, Codex, Cursor, Gemini, ChatGPT, Cline, Aider, Pi-Agent, Factory",
      "Three search modes: lexical (BM25), semantic (MiniLM/hash fallback), hybrid (RRF)",
      "Sub-60ms queries with edge n-gram prefix matching",
      "Aggregations for 99% token reduction (--aggregate agent,workspace)",
      "Robot mode with cursor pagination and token budgeting",
      "Context command finds related sessions for a source path",
      "HTML export with optional AES-256-GCM encryption",
      "Multi-machine search via SSH with interactive setup wizard",
    ],
    cliCommands: [
      'cass search "query" --robot --limit 10 --fields minimal',
      'cass search "*" --json --aggregate agent',
      "cass context /path/to/file.ts --json",
      "cass health --json",
      "cass sources setup",
    ],
    installCommand:
      "curl --proto '=https' --proto-redir '=https' -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh | bash -s -- --easy-mode",
    language: "Rust",
  },
  {
    id: "cm",
    name: "CASS Memory System",
    shortName: "CM",
    href: "https://github.com/Dicklesworthstone/cass_memory_system",
    icon: "Brain",
    color: "from-pink-400 to-fuchsia-500",
    tagline: "Cross-agent procedural memory",
    description:
      "Transforms scattered agent sessions into persistent, cross-agent memory. Patterns discovered in Cursor automatically help Claude Code on the next session. Three-layer cognitive architecture: Episodic → Working → Procedural.",
    deepDescription:
      "CM implements a three-layer memory system mirroring human expertise: raw sessions (episodic via CASS) → structured summaries (working via diary) → distilled playbook rules (procedural). Rules have 90-day decay half-life and 4× harmful weight. Scientific validation requires evidence from CASS history before rules are accepted. Bad rules auto-invert into anti-pattern warnings.",
    connectsTo: ["cass", "mail", "bv"],
    connectionDescriptions: {
      cass: "Primary dependency - mines sessions for episodic memory",
      mail: "Shares memory context across agent conversations",
      bv: "Task patterns and successful approaches remembered",
    },
    stars: 71,
    features: [
      "Three-layer architecture: Episodic → Working → Procedural",
      "Cross-agent learning: all agent sessions feed unified playbook",
      "Confidence decay (90-day half-life) prevents stale rules",
      "Anti-pattern learning: bad rules become warnings",
      "Scientific validation against CASS history",
      "Agent-native onboarding with gap analysis",
    ],
    cliCommands: [
      'cm context "task description" --json',
      "cm onboard status --json",
      "cm playbook list --json",
      "cm stats --json",
    ],
    installCommand:
      "curl --proto '=https' --proto-redir '=https' -fsSL https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh | bash -s -- --easy-mode --verify",
    language: "TypeScript",
  },
  {
    id: "caam",
    name: "Coding Agent Account Manager",
    shortName: "CAAM",
    href: "https://github.com/Dicklesworthstone/coding_agent_account_manager",
    icon: "KeyRound",
    color: "from-amber-400 to-orange-500",
    tagline: "Instant auth switching",
    description:
      "Manage multiple accounts for Claude Code, Codex CLI, and Gemini CLI with sub-100ms switching. Smart rotation algorithms, cooldown tracking, health scoring, and vault-based profile isolation for parallel agent sessions.",
    deepDescription:
      "CAAM enables seamless multi-account workflows for AI coding CLIs. Vault profiles store auth files for instant switching without browser flows. Smart rotation considers cooldown state, health status (healthy/warning/critical), recency, and plan type. Robot mode provides JSON output for agent automation. Features include profile isolation for parallel sessions, background token refresh daemon, and multi-machine vault sync. AES-256-GCM encrypted bundles with Argon2id key derivation for secure export/import.",
    connectsTo: ["ntm", "slb", "mail"],
    connectionDescriptions: {
      ntm: "Provides credentials when spawning agents; enables parallel sessions with isolated profiles",
      slb: "Account switching can be coordinated through SLB for team approval workflows",
      mail: "Account switches can trigger Agent Mail notifications for coordination",
    },
    stars: 12,
    features: [
      "Sub-100ms account switching via vault profiles",
      "3 providers: Claude Code, Codex CLI, Gemini CLI",
      "Smart rotation: cooldown, health, recency, plan type",
      "Health scoring: healthy (🟢), warning (🟡), critical (🔴)",
      "caam run with automatic failover on rate limits",
      "Project-profile associations (per-directory defaults)",
      "Profile isolation for parallel agent sessions",
      "Robot mode with JSON output for agent automation",
    ],
    cliCommands: [
      "caam pick claude              # fzf-style profile picker",
      "caam run claude -- 'prompt'   # Auto-failover on limits",
      "caam project set claude work  # Per-directory profile",
      "caam robot status             # JSON status for agents",
      "caam cooldown set claude/work # Mark rate-limited",
      "caam exec codex work -- 'x'   # Isolated session",
    ],
    installCommand:
      'curl --proto \'=https\' --proto-redir \'=https\' -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_account_manager/main/install.sh" | bash',
    language: "Go",
  },
  {
    id: "slb",
    name: "Simultaneous Launch Button",
    shortName: "SLB",
    href: "https://github.com/Dicklesworthstone/simultaneous_launch_button",
    icon: "ShieldCheck",
    color: "from-yellow-400 to-amber-500",
    tagline: "Two-person rule for agents",
    description:
      "Nuclear-launch-style safety for AI agents. Four risk tiers (CRITICAL/DANGEROUS/CAUTION/SAFE) with 40+ regex patterns. CRITICAL commands require 2+ approvals from different agents. Cryptographic signing, rollback support, and outcome analytics.",
    deepDescription:
      "SLB implements a two-person authorization rule for dangerous commands. Commands are classified by regex patterns: CRITICAL (rm -rf /, DROP DATABASE, terraform destroy) needs 2+ approvals, DANGEROUS (git reset --hard, rm -rf) needs 1, CAUTION auto-approves after 30s, SAFE skips entirely. Approvals are cryptographically signed with HMAC. Features include Claude Code hooks, Cursor rules generation, session management for agents, watch mode (NDJSON streaming) for reviewing agents, pre-execution state capture for rollback, and outcome recording for pattern improvement.",
    connectsTo: ["dcg", "mail", "ntm", "caam"],
    connectionDescriptions: {
      dcg: "DCG blocks pre-execution, SLB validates with multi-agent approval",
      mail: "Approval requests can be routed via Agent Mail for coordination",
      ntm: "Coordinates approval quorum across NTM-managed agents",
      caam: "Account switching can require SLB approval for team workflows",
    },
    stars: 23,
    features: [
      "4-tier risk: CRITICAL (2+), DANGEROUS (1), CAUTION (30s), SAFE (skip)",
      "40+ regex patterns: 24 critical, 15 dangerous, 6 safe",
      "HMAC-SHA256 cryptographic approval signatures",
      "Self-review protection (agents can't approve own requests)",
      "Watch mode for reviewing agents (NDJSON streaming)",
      "Rollback support with pre-execution state capture",
      "Claude Code hooks and Cursor rules generation",
      "Outcome recording for pattern analytics and learning",
    ],
    cliCommands: [
      'slb run "rm -rf ./build" --reason "Clean artifacts"',
      'slb check "git push --force"      # Test classification',
      "slb approve <id> -s $SESSION_ID -k $KEY",
      "slb watch --auto-approve-caution  # Review agent mode",
      "slb tui                           # Interactive dashboard",
      "slb session start -a MyAgent      # Start agent session",
    ],
    installCommand:
      "curl --proto '=https' --proto-redir '=https' -fsSL https://raw.githubusercontent.com/Dicklesworthstone/simultaneous_launch_button/main/scripts/install.sh | bash",
    language: "Go",
  },
  {
    id: "dcg",
    name: "Destructive Command Guard",
    shortName: "DCG",
    href: "https://github.com/Dicklesworthstone/destructive_command_guard",
    icon: "ShieldAlert",
    color: "from-red-400 to-rose-500",
    tagline: "Pre-execution safety net",
    description:
      "Claude Code PreToolUse hook blocking dangerous commands BEFORE execution. 50+ packs across 17 categories: git, filesystem, databases, Kubernetes, cloud providers, CI/CD, and more. Fail-open design ensures you're never blocked by errors.",
    deepDescription:
      "DCG protects your codebase from destructive operations. As a PreToolUse hook, it intercepts commands before execution with sub-millisecond latency. 50+ protection packs cover git (reset --hard, force push, branch -D), filesystem (rm -rf outside temp dirs), databases (DROP TABLE, TRUNCATE), Kubernetes (delete namespace, drain), and cloud providers (AWS, GCP, Azure). Commands are classified as blocked or allowed with safe directory exceptions (/tmp, /var/tmp, $TMPDIR). Output formats include text, JSON, and SARIF for security tooling integration.",
    connectsTo: ["slb", "ntm", "mail", "srps"],
    connectionDescriptions: {
      slb: "DCG and SLB form a two-layer safety system - DCG blocks pre-execution, SLB validates post-execution",
      ntm: "Agents spawned by NTM are protected by DCG hooks in Claude Code",
      mail: "DCG denials can be logged to Mail for agent coordination",
      srps: "Together with SRPS: DCG blocks dangerous commands, SRPS blocks resource exhaustion",
    },
    stars: 50,
    features: [
      "Sub-millisecond SIMD-accelerated PreToolUse hook",
      "Heredoc/inline script scanning (python -c, bash -c, etc.)",
      "Smart context detection: data vs execution contexts",
      "49+ packs: git, filesystem, database, k8s, cloud, cicd",
      "Agent-specific trust profiles (claude-code, gemini, etc.)",
      "MCP server mode for direct agent integration",
      "Fail-open design: never blocks on errors/timeouts",
      "Output: text, JSON, SARIF for security tooling",
    ],
    cliCommands: [
      "dcg test 'rm -rf /'       # Test if command blocked",
      "dcg explain 'command'     # Decision trace with reasons",
      "dcg scan src/             # CI/pre-commit integration",
      "dcg packs --verbose       # List packs with counts",
      "dcg mcp-server            # Start MCP server",
      "dcg doctor                # Health check + verification",
    ],
    installCommand:
      "curl --proto '=https' --proto-redir '=https' -fsSL https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/install.sh | bash",
    language: "Rust",
  },
  {
    id: "ru",
    name: "Repo Updater",
    shortName: "RU",
    href: "https://github.com/Dicklesworthstone/repo_updater",
    icon: "GitMerge",
    color: "from-indigo-400 to-blue-500",
    tagline: "Multi-repo sync + AI review orchestration",
    description:
      "Synchronize 100+ GitHub repos with one command. AI-assisted code review with priority scoring. Dependency updates across package managers. Pure Bash with git plumbing.",
    deepDescription: `RU is a multi-repo management system with AI orchestration. Pure Bash using git plumbing commands
(rev-list, status --porcelain) - never parses human-readable output, so it's locale-independent.

**Core sync:** Clone missing repos, pull updates, detect conflicts. Parallel work-stealing queue with
portable locking. Resume interrupted syncs from checkpoint. Actionable resolution commands for every
conflict type (dirty tree, diverged branches, auth failures).

**AI-Assisted Review (ru review):**
- GraphQL batch queries discover issues/PRs across all repos
- Multi-factor priority scoring: type (+20 PRs), labels (+50 security), age, staleness
- Git worktree isolation for parallel sessions (main directory untouched)
- Session drivers: auto, ntm (robot mode API), local (raw tmux)
- Two-phase workflow: --plan (discover) → --apply --push (execute)
- Quality gates: ShellCheck, tests, lint before push

**Agent Sweep (ru agent-sweep):**
- Three-phase AI workflow: understand → plan → execute
- Parallel execution with phase timeouts
- Secret scanning (none/warn/block modes)

**Dependency Updates (ru dep-update):**
- Supported: npm, pip, cargo, go, composer
- Per-dependency test verification with auto-fix attempts
- Major version filtering, regex include/exclude patterns

**Automation & Scripting:**
- Output modes: text, TOON, JSON for CI integration
- Meaningful exit codes: 0=ok, 1=partial, 2=conflicts, 3=system, 4=bad args, 5=interrupted
- Bulk import from GitHub/GitLab/Bitbucket/Gitea (ru import)
- Orphan repo cleanup with ru prune`,
    connectsTo: ["ntm", "mail", "bv", "gh"],
    connectionDescriptions: {
      ntm: "Uses ntm robot mode for AI-assisted reviews and agent sweep",
      mail: "Can coordinate repo claims across agents",
      bv: "Integrates with beads for multi-repo task tracking",
      gh: "GraphQL API for batched issue/PR discovery",
    },
    stars: 78,
    features: [
      "Parallel sync with work-stealing queue (ru sync -j4)",
      "AI code review with priority scoring (ru review)",
      "Dependency updates across package managers (ru dep-update)",
      "Agent sweep for multi-repo automation",
      "Git worktree isolation for parallel sessions",
      "Resume from checkpoint: ru sync --resume",
      "Quality gates: ShellCheck, tests, lint",
      "TOON/JSON output modes for CI integration",
      "Bulk import from GitHub/GitLab/Bitbucket (ru import)",
    ],
    cliCommands: [
      "ru sync                    # Clone missing + pull updates",
      "ru sync -j4 --autostash    # Parallel with auto-stash",
      "ru sync --resume           # Resume interrupted sync",
      "ru status --no-fetch       # Quick local status check",
      "ru review --plan           # AI-assisted code review",
      "ru review --apply --push   # Apply approved changes",
      "ru agent-sweep -j4         # Parallel AI commit automation",
      "ru import github user/org  # Bulk import repos",
      "ru prune                   # Remove orphan repos",
    ],
    installCommand:
      'curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/repo_updater/main/install.sh" | bash',
    language: "Bash",
  },
  {
    id: "ms",
    name: "Meta Skill",
    shortName: "MS",
    href: "https://github.com/Dicklesworthstone/meta_skill",
    icon: "Sparkles",
    color: "from-teal-500 to-emerald-600",
    tagline: "Local-first skill management platform",
    description:
      "Dual persistence (SQLite + Git), hybrid search (BM25 + semantic + RRF), UCB bandit optimization, multi-layer security (ACIP + DCG), graph analysis via bv, MCP server for AI agents.",
    deepDescription: `MS is a local-first skill management platform with comprehensive capabilities:

**Persistence:** Dual storage - SQLite for fast queries, Git for audit trails. Neither is privileged;
they serve different needs. Database corrupts? Rebuild from Git. Git unavailable? SQLite still works.

**Search:** Hybrid BM25 + hash embeddings (deterministic, no external models) fused with RRF.
Same text = same vector on any machine. Combines keyword precision with semantic recall.

**Suggestions:** UCB bandit optimization that learns from feedback. Each signal (BM25, semantic,
recency, feedback) is an arm with beta distributions. Context modifiers adjust for project type.
Over time, the system learns which signals matter for your workflow.

**Security:** Multi-layer defense:
- ACIP: Classifies content by trust boundary, quarantines prompt injections
- DCG: Command safety tiers (Safe/Caution/Danger/Critical) with approval gates
- Path Policy: Prevents symlink escapes and directory traversal
- Secret Scanner: Redacts credentials and API keys

**Graph Analysis:** Converts skills to JSONL and delegates to bv for PageRank, betweenness,
cycles, critical path analysis, HITS algorithm. Use the right tool for each job.

**MCP Server:** Exposes 12 tools (search, load, evidence, list, show, doctor, lint, suggest,
feedback, index, validate, config) so Claude, Codex, and other MCP-aware agents can use ms
as a native tool, not string-parsing.`,
    connectsTo: ["cass", "cm", "bv", "br", "jfp"],
    connectionDescriptions: {
      cass: "One input source for skill extraction (among several)",
      cm: "Skills and CM memories are complementary knowledge layers",
      bv: "Graph analysis via bv for PageRank, betweenness, cycles",
      br: "Skill workflows generate beads for execution tracking",
      jfp: "JFP downloads remote prompts, MS manages local skills",
    },
    stars: 68,
    features: [
      "Dual persistence: SQLite + Git archive",
      "Hybrid search: BM25 + hash embeddings + RRF",
      "UCB bandit: Learns from feedback to optimize suggestions",
      "MCP server: 12 native tools for AI agent integration",
      "ACIP + DCG: Multi-layer security with quarantine",
      "Token packing with pack contracts (debug/refactor/learn)",
      "Auto-loading: Context-aware skill suggestions",
      "Graph analysis: PageRank, bottlenecks, cycles via bv",
    ],
    cliCommands: [
      "ms doctor                 # Health checks and repairs",
      "ms search 'error handling' # Hybrid BM25 + semantic search",
      "ms suggest                # Bandit-optimized suggestions",
      "ms mcp serve              # Start MCP server (12 tools)",
      "ms build --from-cass <query> # Build skills from CASS",
      "ms sync                   # Multi-machine Git sync",
    ],
    installCommand: "cargo install --git https://github.com/Dicklesworthstone/meta_skill",
    language: "Rust",
  },
  {
    id: "rch",
    name: "Remote Compilation Helper",
    shortName: "RCH",
    href: "https://github.com/Dicklesworthstone/remote_compilation_helper",
    icon: "Cloud",
    color: "from-blue-500 to-indigo-600",
    tagline: "Offload Rust builds to remote workers",
    description:
      "Claude Code PreToolUse hook that offloads cargo builds to remote workers. Intercepts build commands, syncs source via rsync + zstd, compiles on server-grade hardware, and streams artifacts back.",
    deepDescription:
      "RCH runs as a PreToolUse hook intercepting cargo commands before execution. Workers are managed via `rch workers` with health probes and priority scheduling. The daemon mode maintains persistent SSH connections for low-latency builds. Agent detection (`rch agents`) finds running Claude Code, Codex, and Gemini sessions to coordinate multi-agent builds. Doctor command validates workers, daemon, and hook configuration.",
    connectsTo: ["ntm", "ru", "br"],
    connectionDescriptions: {
      ntm: "NTM can spawn agents on same machines RCH uses as workers",
      ru: "RU syncs repos that RCH then builds remotely",
      br: "Build tasks tracked via beads",
    },
    stars: 45,
    features: [
      "PreToolUse hook intercepts cargo commands automatically",
      "rsync + zstd sync with incremental artifact streaming",
      "Worker pool with health probes and priority scheduling",
      "Daemon mode with persistent SSH connections",
      "Agent detection for Claude Code, Codex, Gemini CLI",
      "Doctor command validates entire configuration",
    ],
    cliCommands: [
      "rch doctor                  # Comprehensive diagnostics",
      "rch workers list            # Show configured workers",
      "rch workers probe --all     # Test worker connectivity",
      "rch daemon start            # Start persistent daemon",
      "rch hook install            # Install PreToolUse hook",
      "rch agents                  # Detect running AI agents",
    ],
    installCommand:
      'curl --proto \'=https\' --proto-redir \'=https\' -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/master/install.sh" | bash',
    language: "Rust",
  },
  {
    id: "wa",
    name: "WezTerm Automata",
    shortName: "WA",
    href: "https://github.com/Dicklesworthstone/wezterm_automata",
    icon: "Terminal",
    color: "from-purple-500 to-violet-600",
    tagline: "Terminal hypervisor for AI agents",
    description:
      "A terminal hypervisor that captures pane output in real-time, detects AI agent state transitions via pattern matching, and enables event-driven automation across multi-agent swarms.",
    deepDescription: `WA is a terminal hypervisor - not just an automation tool. It runs a daemon that continuously
observes WezTerm panes with sub-50ms latency, capturing output deltas and detecting state
transitions in AI coding agents (Claude Code, Codex, Gemini).

The pattern detection engine recognizes agent-specific states: ready for input, thinking,
rate limited, awaiting approval, idle timeout. When states change, WA can trigger automated
responses via callbacks or Robot Mode.

Robot Mode provides a JSON API for external orchestration:
- wa robot state: Get current state of all observed panes
- wa robot get-text: Extract screen content from specific panes
- wa robot send: Inject keystrokes with configurable delays
- wa robot wait-for: Block until a pattern matches
- wa robot search: Query the FTS5-indexed capture history

The policy engine allows capability gates (e.g., "agent X can only send to its own pane")
to prevent runaway automation. All captured content is stored in SQLite with FTS5 for
full-text search across sessions - invaluable for debugging agent behavior.`,
    connectsTo: ["ntm", "mail", "br"],
    connectionDescriptions: {
      ntm: "WA observes agents spawned by NTM sessions",
      mail: "State changes can trigger Agent Mail notifications",
      br: "Task completions can update bead status",
    },
    stars: 42,
    features: [
      "Real-time delta capture (sub-50ms latency)",
      "Multi-agent pattern detection engine",
      "Robot Mode JSON API for orchestration",
      "FTS5-powered search with BM25 ranking",
      "Policy engine with capability gates",
      "Workflow automation triggered by pattern matches",
      "TOON output format for token-efficient AI consumption",
      "Explainability via 'wa why' command",
    ],
    cliCommands: [
      "wa daemon start              # Start background observer",
      "wa robot state               # JSON state of all panes",
      "wa robot get-text --pane 1   # Extract pane content",
      "wa robot send --pane 1 'cmd' # Inject keystrokes",
      "wa robot wait-for 0 'pattern' # Event-driven wait",
      "wa robot events              # Recent detection events",
      "wa why deny.alt_screen       # Explain policy denials",
    ],
    installCommand: "cargo install --git https://github.com/Dicklesworthstone/wezterm_automata",
    language: "Rust",
  },
  {
    id: "brenner",
    name: "Brenner Bot",
    shortName: "BRENNER",
    href: "https://github.com/Dicklesworthstone/brenner_bot",
    icon: "Bot",
    color: "from-rose-500 to-red-600",
    tagline: "Multi-agent scientific research orchestration",
    description:
      "Operationalizes Sydney Brenner's scientific methodology. Orchestrates multi-agent research sessions with hypothesis lifecycle tracking, discriminative test design, anomaly management, and evidence pack integration.",
    deepDescription: `Brenner Bot is a research orchestration platform that turns AI agents into a collaborative research group.
Built around Sydney Brenner's methodology (Nobel laureate, discoverer of mRNA), it provides a curated corpus (236 transcript
sections with §n anchors), multi-model syntheses (Opus, GPT, Gemini), and full artifact lifecycle management.

**Research Artifact Lifecycle:**
- Hypothesis management: proposed → active → under_attack → killed/validated/dormant
- Discriminative tests: designed → pending → completed/blocked (exclusion beats accumulation)
- Anomaly tracking: active → resolved/deferred/paradigm_shifting (can spawn new hypotheses)
- Critique system: adversarial attacks with severity levels and response tracking
- Evidence packs: import papers, datasets, prior sessions with stable EV-NNN citations

**Cockpit Runtime:**
- Multi-agent sessions via ntm with role-specific prompts (hypothesis_generator, test_designer, adversarial_critic)
- Thread ID is global join key: ties Agent Mail, ntm sessions, artifacts, beads
- Session state machine with phase detection (awaiting_responses → partially_complete → awaiting_compilation)
- Artifact compiler with 50+ validation rules: third alternative checks, potency controls, citation anchors

**The Brenner Approach:**
- Two axioms: Reality has a generative grammar, Understanding = Reconstruction
- "Exclusion is always a tremendously good thing" - design for sharp discriminative experiments
- Third alternative check: "Both could be wrong" - always consider misspecification`,
    connectsTo: ["mail", "ntm", "cass", "br"],
    connectionDescriptions: {
      mail: "Research sessions coordinate via Agent Mail threads with acknowledgment tracking",
      ntm: "Cockpit runtime spawns parallel research agents with role-specific prompts",
      cass: "Research session history is searchable for prior solutions",
      br: "Research tasks and session artifacts tracked via beads",
    },
    stars: 28,
    features: [
      "Hypothesis lifecycle: proposed → active → killed/validated with discriminative tests",
      "Evidence packs: import papers, datasets, prior sessions with stable EV-NNN citations",
      "Anomaly tracking with paradigm_shifting status and hypothesis spawning",
      "Critique system for adversarial review with severity levels",
      "Cockpit runtime: multi-agent sessions with role-specific prompts",
      "236-section transcript corpus with §n citations and quote bank",
      "Artifact compiler with 50+ Brenner-style validation rules",
      "Session state machine with phase detection and progress tracking",
      "Experiment capture with result encoding and Agent Mail posting",
    ],
    cliCommands: [
      "brenner corpus search 'query' # Full-text corpus search with §n anchors",
      "brenner hypothesis create --statement 'H' # Create hypothesis with category",
      "brenner evidence add --type paper --title 'T' # Import external evidence",
      "brenner anomaly create --observation 'O' # Track unexpected results",
      "brenner session start --to A,B --question 'Q' # Orchestrate multi-agent session",
      "brenner cockpit start --role-map 'A=hypothesis_generator' # Full cockpit",
      "brenner critique create --target H-001 --attack 'A' # Adversarial critique",
      "brenner doctor --json # Verify installation with JSON output",
    ],
    installCommand:
      'curl --proto \'=https\' --proto-redir \'=https\' -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/brenner_bot/main/install.sh" | bash',
    language: "TypeScript",
  },
  {
    id: "jfp",
    name: "JeffreysPrompts",
    shortName: "JFP",
    href: "https://jeffreysprompts.com",
    icon: "BookOpen",
    color: "from-amber-400 to-yellow-500",
    tagline: "Curated prompt library + skill installer",
    description:
      "Browse a curated library of battle-tested prompts and install them directly as Claude Code skills. Works via CLI or web UI with interactive fzf-style picker.",
    deepDescription:
      "JFP (JeffreysPrompts.com CLI) is the fastest way to discover prompts that actually work in production agent workflows. It mirrors the website library in a CLI: search, preview, and install prompts as Claude Code skills in seconds. Features include an interactive fzf-style picker (jfp i), task-based suggestion engine (jfp suggest), and workflow bundles for team standardization. Premium features include collections, sync across machines, and a skills marketplace.",
    connectsTo: ["ms", "apr", "cm"],
    connectionDescriptions: {
      ms: "Use JFP to discover prompts, then manage/curate them locally with MS",
      apr: "Feed high-quality prompts into APR to refine and harden specifications",
      cm: "Prompts that work become reusable memory artifacts",
    },
    stars: 50,
    features: [
      "Interactive fzf-style prompt picker (jfp i)",
      "Task-based prompt suggestions (jfp suggest)",
      "Install prompts as Claude Code skills",
      "Workflow bundles for team standardization",
      "MCP server mode for agent integration (jfp serve)",
      "Variable rendering with placeholder fill (jfp render --fill)",
      "Premium: collections, sync, notes, marketplace",
      "Shell completion and auto-updates",
    ],
    cliCommands: [
      "jfp i",
      "jfp suggest \"write unit tests\"",
      "jfp search \"code review\"",
      "jfp install idea-wizard",
      "jfp bundles",
      "jfp serve",
    ],
    installCommand: "curl -fsSL https://jeffreysprompts.com/install-cli.sh | bash",
    language: "TypeScript (Bun)",
  },
  {
    id: "srps",
    name: "System Resource Protection Script",
    shortName: "SRPS",
    href: "https://github.com/Dicklesworthstone/system_resource_protection_script",
    icon: "Shield",
    color: "from-yellow-400 to-orange-500",
    tagline: "Keep your workstation responsive under heavy agent load",
    description:
      "Installs ananicy-cpp with curated rules to automatically deprioritize background processes. Includes sysmoni Go TUI with per-process IO throughput, FD counts, and JSON export. Works on Linux and WSL2.",
    deepDescription: `When AI coding agents run cargo build, npm install, or spawn
multiple parallel processes, your system can become unresponsive. SRPS solves this
by automatically lowering the priority of known resource hogs (compilers, bundlers,
test runners) while keeping your terminal and IDE snappy.

Built on ananicy-cpp with curated rules for developer workloads. The sysmoni Go TUI
(Bubble Tea) shows real-time CPU/memory per process, IO throughput (read/write kB/s),
open FD counts, per-core sparklines, and JSON/NDJSON export.

Helper tools: check-throttled, cursor-guard (log/renice-only), srps-doctor, srps-reload-rules.
Safety-first: no automated process killing. Aliases: limited, cargo-limited, make-limited.

Supports Linux (Debian/Ubuntu) and WSL2. Idempotent installer with --plan dry-run.`,
    connectsTo: ["ntm", "dcg", "slb", "pt"],
    connectionDescriptions: {
      ntm: "SRPS ensures tmux sessions stay responsive even during heavy builds - no frozen terminals",
      dcg: "Combined safety: DCG prevents destructive commands, SRPS prevents resource exhaustion from runaway processes",
      slb: "When SLB launches multiple agents, SRPS keeps them from starving each other for CPU/memory",
      pt: "PT identifies stuck processes, SRPS deprioritizes resource hogs - complementary approaches",
    },
    stars: 50,
    features: [
      "ananicy-cpp daemon with curated process priority rules",
      "sysmoni Go TUI: CPU/MEM gauges, IO throughput, FD counts",
      "Per-core sparklines, JSON/NDJSON export, GPU monitoring",
      "Sysctl tweaks + systemd limits for WSL2 compatibility",
      "Helper tools: check-throttled, srps-doctor, cursor-guard",
      "Idempotent installer with --plan dry-run, --uninstall",
    ],
    cliCommands: [
      "sysmoni",
      "check-throttled",
      "srps-doctor",
      "sysmoni --json",
    ],
    installCommand:
      "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/system_resource_protection_script/main/install.sh | bash -s -- --install",
    language: "Go + C++ + Bash",
  },
  {
    id: "apr",
    name: "Automated Plan Reviser Pro",
    shortName: "APR",
    href: "https://github.com/Dicklesworthstone/automated_plan_reviser_pro",
    icon: "FileText",
    color: "from-amber-500 to-yellow-600",
    tagline: "Iterative spec refinement via GPT Pro Extended Reasoning + Oracle",
    description:
      "Automates multi-round specification review using GPT Pro 5.2 Extended Reasoning. Document bundling, convergence analytics, session management, and robot mode for coding agents.",
    deepDescription: `APR (v1.2.2) automates iterative specification refinement like numerical optimization converging on a steady state. Rounds 1-3 fix major architectural issues and security gaps, rounds 4-7 refine interfaces, rounds 8-12 handle edge cases, rounds 13+ polish abstractions.

Workflow: apr setup (interactive wizard) → apr run <N> (execute round) → apr integrate <N> (Claude Code prompt). Document bundling automatically combines README + spec + implementation (every 3-4 rounds). Background execution with 10-60 minute GPT Pro reasoning and desktop notifications on completion.

Convergence analytics: apr stats shows weighted score (output_trend 35% + change_velocity 35% + similarity_trend 30%). Score ≥0.75 = approaching stability. apr diff compares rounds with delta/diff. apr dashboard provides full-screen analytics.

Reliability: Pre-flight validation before expensive Oracle runs. Auto-retry with exponential backoff (10s → 30s → 90s). Session locking prevents concurrent runs. Identity validation for GPT Pro Extended Thinking stability (minStableMs=30s, stableCycles=12).

Robot mode (JSON API): apr robot validate <N> → apr robot run <N> → apr robot history. Semantic error codes: ok, usage_error, not_configured, config_error, validation_failed, dependency_missing, busy. TOON format support via tru.`,
    connectsTo: ["jfp", "cm", "bv"],
    connectionDescriptions: {
      jfp: "Battle-tested prompts from JFP can be refined into comprehensive specifications via APR",
      cm: "Refined plans become searchable procedural memory - find what worked before",
      bv: "Well-refined specifications become granular, dependency-tracked beads for execution",
    },
    stars: 85,
    features: [
      "Iterative convergence: architecture → refinement → polish",
      "Document bundling (README + spec + implementation)",
      "Background processing with session management",
      "Convergence analytics with weighted scoring",
      "Pre-flight validation and auto-retry",
      "Session locking prevents concurrent runs",
      "Robot mode JSON API with semantic error codes",
      "Claude Code integration prompts (apr integrate)",
      "Round diff comparison with delta support",
    ],
    cliCommands: [
      "apr setup",
      "apr run <N>",
      "apr run <N> --include-impl",
      "apr status",
      "apr diff <N> [M]",
      "apr integrate <N> --copy",
      "apr stats",
      "apr robot validate <N>",
    ],
    installCommand:
      "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/automated_plan_reviser_pro/main/install.sh | bash",
    language: "Bash",
  },
  {
    id: "pt",
    name: "Process Triage",
    shortName: "PT",
    href: "https://github.com/Dicklesworthstone/process_triage",
    icon: "Activity",
    color: "from-red-500 to-orange-600",
    tagline: "Bayesian-inference zombie/abandoned process detection and cleanup",
    description:
      "Four-state classification model (Useful, Useful-but-bad, Abandoned, Zombie) with evidence-based posterior inference. Interactive TUI via gum, agent/robot mode for automation.",
    deepDescription: `PT identifies abandoned processes using Bayesian posterior inference. Every process is classified into one of four states: Useful (productive work), Useful-but-bad (stuck/leaking), Abandoned (forgotten), or Zombie (terminated but not reaped).

Evidence sources: process type (test runner? dev server?), age vs expected lifetime, parent PID (orphaned?), CPU activity, I/O activity, TTY state, memory usage, and past decisions (learns from your patterns). Confidence levels: very_high (>0.99), high (>0.95), medium (>0.80), low (<0.80).

Safety model: Identity validation (boot_id:start_time_ticks:pid) prevents PID reuse attacks. Protected processes (systemd, sshd, docker, postgres, etc.) are never flagged. Staged kill signals: SIGTERM → wait → SIGKILL. Blast radius assessment includes memory freed, CPU released, and child process impact.

Agent/robot mode safety gates: min_posterior (0.95 default), max_kills (10/session), max_blast_radius (4GB), fdr_budget (0.05). Output formats: json, toon, md, jsonl, summary, metrics, slack, exitcode, prose.

Tech stack: Rust pt-core inference engine + Bash wrapper + gum TUI. Session bundles (.ptb) enable sharing and reproducibility with optional encryption.`,
    connectsTo: ["srps", "ntm"],
    connectionDescriptions: {
      srps: "PT terminates stuck processes, SRPS prevents them from starving the system",
      ntm: "Clean up runaway processes across all your tmux sessions",
    },
    stars: 45,
    features: [
      "Four-state Bayesian classification (Useful/Bad/Abandoned/Zombie)",
      "Evidence-based posterior inference with confidence levels",
      "Protected process lists (systemd, sshd, docker, postgres)",
      "Identity validation prevents PID reuse attacks",
      "Staged kill signals (SIGTERM → wait → SIGKILL)",
      "Blast radius assessment before termination",
      "Interactive gum TUI for process selection",
      "Agent/robot mode with safety gates",
      "Session bundles (.ptb) for sharing/reproducibility",
    ],
    cliCommands: [
      "pt",
      "pt scan",
      "pt deep",
      "pt agent plan --format json",
      "pt robot plan --format toon",
      "pt history",
    ],
    installCommand:
      "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/process_triage/master/install.sh | bash",
    language: "Rust/Bash",
  },
  {
    id: "xf",
    name: "X Archive Search",
    shortName: "XF",
    href: "https://github.com/Dicklesworthstone/xf",
    icon: "Archive",
    color: "from-blue-500 to-indigo-600",
    tagline: "Ultra-fast search over your X/Twitter archive",
    description:
      "Hybrid BM25 + semantic search over X/Twitter data exports. Zero-dependency local processing with Reciprocal Rank Fusion.",
    deepDescription: `XF indexes your X (Twitter) data export and provides sub-millisecond full-text search
across tweets, likes, DMs, and Grok conversations. Three search modes: hybrid (default),
lexical (BM25 keyword matching), and semantic (vector similarity via hash embedder or
optional MiniLM with --semantic flag).

Key capabilities:
- Rust + Tantivy for sub-millisecond lexical search (<10ms typical)
- Hybrid BM25 + semantic search with RRF fusion
- Zero-dependency hash embedder (default) or optional MiniLM embeddings (--semantic)
- SIMD-accelerated vector search with F16 quantization
- Fully local, privacy-preserving processing (no network calls)
- DM context search: view full conversation threads with matches highlighted
- Parses all X archive formats: tweets, likes, DMs, Grok chats, followers`,
    connectsTo: ["cass", "cm"],
    connectionDescriptions: {
      cass: "Similar search architecture - hybrid retrieval patterns",
      cm: "Found tweets can become memories for agent context",
    },
    stars: 156,
    features: [
      "Sub-millisecond lexical search (<10ms typical)",
      "Hybrid BM25 + semantic search with RRF fusion",
      "Hash embedder (default) or MiniLM (--semantic)",
      "SIMD-accelerated vector search, F16 quantization",
      "DM context search with full conversation threads",
      "Parses tweets, likes, DMs, Grok chats, followers",
    ],
    cliCommands: [
      "xf index ~/x-archive               # Index archive",
      "xf search 'query'                  # Hybrid search (default)",
      "xf search 'query' --mode semantic  # Vector similarity",
      "xf search 'topic' --types dm --context  # DM threads",
      "xf stats --format json             # Archive stats",
    ],
    installCommand:
      "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/xf/main/install.sh | bash",
    language: "Rust",
  },
  // ============================================================
  // UTILITY TOOLS - Supporting tools for the flywheel
  // ============================================================
  {
    id: "giil",
    name: "Get Image from Internet Link",
    shortName: "GIIL",
    href: "https://github.com/Dicklesworthstone/giil",
    icon: "Image",
    color: "from-slate-500 to-slate-600",
    tagline: "Download full-resolution cloud images via four-tier capture",
    description:
      "Download images from iCloud, Dropbox, Google Photos, and Google Drive share links with intelligent four-tier capture strategy and MozJPEG compression.",
    deepDescription: `GIIL (v3.1.0 Hybrid Edition) solves the remote image retrieval problem for AI-assisted debugging.
When users share screenshots via cloud links, agents can download full-resolution originals directly.

Four-tier capture strategy ensures maximum quality:
1. Download button detection (e.g., Dropbox "Download" button click)
2. Network CDN interception (catches direct image URLs from requests)
3. Element screenshot (targets largest image element)
4. Viewport screenshot (final fallback)

Supports iCloud (share.icloud.com), Dropbox (dropbox.com/s/, dl.dropbox.com), Google Photos (photos.google.com),
and Google Drive (drive.google.com). Album mode (--all flag) extracts all images from multi-image shares.

Processing: MozJPEG compression (default 85% quality), HEIC/AVIF to JPEG conversion via Sharp.
Output formats: default (file + path), JSON ({"file","format","size"}), TOON (formatted log), base64.

Exit codes enable scripting: 0=success, 10=network error, 11=auth required, 12=not found, 13=unsupported platform.
Tech stack: Bash wrapper orchestrating Node.js/Playwright/Chromium/Sharp for headless browser automation.`,
    connectsTo: ["cass", "cm"],
    connectionDescriptions: {
      cass: "Downloaded images become part of session context for future reference",
      cm: "Visual debugging patterns become searchable memories",
    },
    stars: 24,
    features: [
      "Four-tier capture strategy (download→CDN→element→viewport)",
      "iCloud, Dropbox, Google Photos, Google Drive support",
      "Album mode (--all) for multi-image shares",
      "MozJPEG compression with configurable quality",
      "HEIC/AVIF to JPEG conversion",
      "JSON/TOON/base64 output formats",
      "Structured exit codes for scripting",
      "Headless Chromium via Playwright",
    ],
    cliCommands: [
      'giil "https://share.icloud.com/..."',
      'giil --all "https://photos.google.com/share/..."',
      "giil --format json --quality 90 URL",
      "giil --help",
    ],
    installCommand:
      "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/giil/main/install.sh | bash",
    language: "Bash/Node.js",
  },
  {
    id: "csctf",
    name: "Chat Shared Conversation to File",
    shortName: "CSCTF",
    href: "https://github.com/Dicklesworthstone/csctf",
    icon: "FileText",
    color: "from-emerald-500 to-teal-600",
    tagline: "Convert AI chat share links to Markdown/HTML",
    description:
      "Archive AI conversations from ChatGPT, Claude, and Gemini share links into clean Markdown and HTML files.",
    deepDescription: `AI conversations are ephemeral - share links expire, contexts get lost. CSCTF converts
share links from major AI platforms into permanent Markdown and HTML archives.

Perfect for:
- Building a searchable knowledge base of solved problems
- Sharing AI-assisted solutions with team members
- Documenting debugging sessions for future reference
- Creating training data from real conversations

Key capabilities:
- ChatGPT share link conversion
- Claude share link conversion
- Gemini share link conversion
- Clean Markdown with preserved code blocks
- Static HTML with syntax highlighting
- Batch processing of multiple links`,
    connectsTo: ["cass", "cm"],
    connectionDescriptions: {
      cass: "Archived conversations become searchable in CASS",
      cm: "Converted conversations feed into procedural memory",
    },
    stars: 45,
    features: [
      "ChatGPT share link support",
      "Claude share link support",
      "Gemini share link support",
      "Clean Markdown output",
      "Static HTML with syntax highlighting",
      "Batch processing support",
    ],
    cliCommands: ['csctf "https://chatgpt.com/share/..."', "csctf --md-only", "csctf --help"],
    installCommand:
      "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/csctf/main/install.sh | bash",
    language: "Rust",
  },
  {
    id: "tru",
    name: "TOON Rust",
    shortName: "TRU",
    href: "https://github.com/Dicklesworthstone/toon_rust",
    icon: "Minimize2",
    color: "from-violet-500 to-purple-600",
    tagline: "Token-optimized notation for LLM context efficiency",
    description:
      "Compress structured data into token-efficient TOON format, reducing LLM context usage by 30-50%.",
    deepDescription: `LLM context windows are precious. TOON (Token-Optimized Object Notation) is a format
designed specifically to minimize token usage while preserving semantic meaning.

Instead of verbose JSON, TOON uses abbreviations, removes redundant structure, and employs
format-aware compression. The result: 30-50% fewer tokens for the same information.

Key capabilities:
- JSON to TOON conversion with automatic optimization
- TOON to JSON restoration for downstream processing
- Token count estimation and comparison
- Streaming support for large documents
- LLM-aware compression heuristics`,
    connectsTo: ["cm", "cass"],
    connectionDescriptions: {
      cm: "Compressed memories use fewer tokens in agent context",
      cass: "Search results can be TOON-compressed before inclusion",
    },
    stars: 67,
    features: [
      "30-50% token reduction",
      "JSON to TOON conversion",
      "TOON to JSON restoration",
      "Token count estimation",
      "Streaming support",
      "LLM-aware compression",
    ],
    cliCommands: ["tru compress file.json", "tru expand file.toon", "tru --help"],
    installCommand:
      "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/toon_rust/master/install.sh | bash",
    language: "Rust",
  },
  {
    id: "rano",
    name: "Request/Response Network Observer",
    shortName: "RANO",
    href: "https://github.com/Dicklesworthstone/rano",
    icon: "Wifi",
    color: "from-cyan-500 to-blue-600",
    tagline: "Network observer for AI CLIs with request/response logging",
    description:
      "Transparent proxy that logs all HTTP traffic from AI coding agents for debugging and analysis.",
    deepDescription: `When AI agents make API calls, understanding what's being sent and received is crucial
for debugging and optimization. RANO acts as a transparent proxy, logging all HTTP traffic
from Claude Code, Codex, and other AI CLIs.

Use cases:
- Debug failed API calls to understand error responses
- Analyze token usage across different prompts
- Monitor rate limiting and retry behavior
- Audit AI agent network activity

Key capabilities:
- Transparent proxy requiring no code changes
- Request/response body logging with formatting
- Token usage extraction from API responses
- Filtering by host, path, or content type`,
    connectsTo: ["caut", "cm"],
    connectionDescriptions: {
      caut: "Network logs feed into usage tracking for cost analysis",
      cm: "Patterns in API usage become procedural memories",
    },
    stars: 32,
    features: [
      "Transparent proxy operation",
      "Request/response logging",
      "Token usage extraction",
      "No code changes required",
      "Filtering by host/path",
      "Formatted output",
    ],
    cliCommands: ["rano start", "rano logs", "rano --help"],
    installCommand:
      "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/rano/main/install.sh | bash",
    language: "Rust",
  },
  {
    id: "mdwb",
    name: "Markdown Web Browser",
    shortName: "MDWB",
    href: "https://github.com/Dicklesworthstone/markdown_web_browser",
    icon: "Globe",
    color: "from-orange-500 to-amber-600",
    tagline: "Convert websites to Markdown for LLM consumption",
    description:
      "Fetch web pages and convert them to clean Markdown, perfect for including documentation in LLM context.",
    deepDescription: `AI agents often need to reference documentation, but web pages are full of navigation,
ads, and formatting that waste precious context tokens. MDWB fetches pages and converts them
to clean, readable Markdown.

Perfect for:
- Including API documentation in agent context
- Referencing library docs without leaving the terminal
- Creating offline documentation archives
- Feeding web content to AI for analysis

Key capabilities:
- Intelligent content extraction (removes nav, ads, footers)
- Code block preservation with language detection
- Link and image handling with optional resolution
- Recursive crawling for documentation sites`,
    connectsTo: ["tru", "cm"],
    connectionDescriptions: {
      tru: "Converted markdown can be TOON-compressed to save tokens",
      cm: "Web content becomes searchable procedural memory",
    },
    stars: 89,
    features: [
      "Intelligent content extraction",
      "Code block preservation",
      "Language detection",
      "Link and image handling",
      "Recursive crawling",
      "Clean Markdown output",
    ],
    cliCommands: ["mdwb fetch https://docs.example.com", "mdwb --recursive", "mdwb --help"],
    installCommand:
      "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/markdown_web_browser/main/install.sh | bash",
    language: "Rust",
  },
  {
    id: "s2p",
    name: "Source to Prompt TUI",
    shortName: "S2P",
    href: "https://github.com/Dicklesworthstone/source_to_prompt_tui",
    icon: "FileCode",
    color: "from-green-500 to-emerald-600",
    tagline: "World-class TUI for combining source code into LLM-ready prompts",
    description:
      "Terminal UI for selecting code files and generating structured, token-counted prompts with XML-like output format optimized for LLM parsing.",
    deepDescription: `S2P solves the code-to-context problem for AI-assisted development. Features a tree explorer with file sizes and line counts, vim-style navigation (j/k/h/l), quick file-type selects (1-9,0,r for JS/React/TS/JSON/MD/Python/Go/Java/Ruby/PHP/Rust), live syntax preview, and real-time token estimation using tiktoken (cl100k_base).

Structured XML-like output with <preamble>, <goal>, <project_structure>, and <files> tags for reliable LLM parsing. Context window bar shows usage against 128K limit with cost estimates.

Processing options: JS/TS minification via Terser, CSS via csso, comment stripping for multiple languages. Presets save file selections and options to ~/.source2prompt.json for reproducible workflows.

Single compiled binary via Bun with zero runtime dependencies. Respects .gitignore recursively including nested gitignores. Handles large projects (10K+ files) with lazy content loading and virtualized rendering.`,
    connectsTo: ["cass", "cm"],
    connectionDescriptions: {
      cass: "Generated prompts become part of session history for later search",
      cm: "Effective prompt patterns stored as procedural memories",
    },
    stars: 78,
    features: [
      "Tree file explorer with sizes and line counts",
      "Vim-style navigation (j/k/h/l)",
      "Quick file-type shortcuts (1-9,0,r)",
      "Live syntax-highlighted preview",
      "Real-time tiktoken token counting",
      "Context window usage bar with cost estimate",
      "Code minification (Terser/csso)",
      "Comment stripping (C-style, hash-style, HTML)",
      "Preset save/load to ~/.source2prompt.json",
      "Recursive .gitignore support",
      "Clipboard integration (Ctrl+G, y to copy)",
    ],
    cliCommands: ["s2p", "s2p /path/to/project", "s2p --help"],
    installCommand:
      "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/source_to_prompt_tui/main/install.sh | bash",
    language: "TypeScript",
  },
  {
    id: "rust_proxy",
    name: "Rust Proxy",
    shortName: "RustProxy",
    href: "https://github.com/Dicklesworthstone/rust_proxy",
    icon: "Network",
    color: "from-gray-500 to-zinc-600",
    tagline: "Transparent proxy routing for debugging network traffic",
    description:
      "High-performance transparent proxy for routing and debugging network traffic in development environments.",
    deepDescription: `When debugging network issues or analyzing API traffic, a transparent proxy is invaluable.
Rust Proxy provides a lightweight, high-performance proxy that can intercept, log, and modify
HTTP/HTTPS traffic.

Use cases:
- Debugging microservice communication
- Analyzing third-party API behavior
- Testing error handling with injected failures
- Capturing traffic for replay testing

Key capabilities:
- Transparent HTTP/HTTPS proxying
- Request/response modification
- Traffic capture and replay
- Minimal performance overhead
- Configuration via TOML`,
    connectsTo: ["rano"],
    connectionDescriptions: {
      rano: "Rust Proxy handles routing, RANO handles logging and analysis",
    },
    stars: 28,
    features: [
      "Transparent HTTP/HTTPS proxy",
      "Request/response modification",
      "Traffic capture and replay",
      "Minimal performance overhead",
      "TOML configuration",
      "TLS support",
    ],
    cliCommands: ["rust_proxy start", "rust_proxy --config proxy.toml", "rust_proxy --help"],
    installCommand:
      "cargo install --git https://github.com/Dicklesworthstone/rust_proxy",
    language: "Rust",
  },
  {
    id: "aadc",
    name: "ASCII Diagram Corrector",
    shortName: "AADC",
    href: "https://github.com/Dicklesworthstone/aadc",
    icon: "BoxSelect",
    color: "from-indigo-500 to-blue-600",
    tagline: "Fix malformed ASCII art diagrams",
    description:
      "Automatically correct alignment and connection issues in ASCII diagrams generated by AI or written by hand.",
    deepDescription: `AI-generated ASCII diagrams often have subtle alignment issues - boxes that don't quite
connect, arrows that are off by one character, or inconsistent spacing. AADC automatically
detects and fixes these issues.

Common fixes:
- Box corner alignment
- Arrow endpoint connection
- Consistent spacing and padding
- Line continuation across breaks
- Unicode box-drawing character normalization

Perfect for:
- Cleaning up AI-generated architecture diagrams
- Fixing documentation ASCII art
- Standardizing diagram styles across a codebase`,
    connectsTo: ["cm"],
    connectionDescriptions: {
      cm: "Diagram correction patterns become procedural memory",
    },
    stars: 34,
    features: [
      "Automatic alignment correction",
      "Box corner detection and fixing",
      "Arrow endpoint connection",
      "Unicode normalization",
      "Consistent spacing",
      "Multiple diagram styles",
    ],
    cliCommands: ["aadc fix diagram.txt", "aadc --style unicode", "aadc --help"],
    installCommand: "cargo install --git https://github.com/Dicklesworthstone/aadc",
    language: "Rust",
  },
  {
    id: "caut",
    name: "Coding Agent Usage Tracker",
    shortName: "CAUT",
    href: "https://github.com/Dicklesworthstone/coding_agent_usage_tracker",
    icon: "BarChart3",
    color: "from-pink-500 to-rose-600",
    tagline: "Track LLM provider usage and costs",
    description:
      "Monitor token usage, API costs, and rate limits across Claude, OpenAI, and other LLM providers.",
    deepDescription: `Running multiple AI agents across projects quickly adds up in API costs. CAUT tracks
usage across all your LLM providers in one place, helping you understand where tokens go
and optimize spending.

Tracks:
- Token usage per provider, project, and session
- Estimated costs based on current pricing
- Rate limit hits and retry patterns
- Usage trends over time

Key capabilities:
- Multi-provider support (Anthropic, OpenAI, Google, etc.)
- Project and session attribution
- Cost estimation with customizable pricing
- Export to CSV/JSON for analysis
- Integration with rano for automatic tracking`,
    connectsTo: ["rano", "cm"],
    connectionDescriptions: {
      rano: "RANO captures the traffic, CAUT calculates the costs",
      cm: "Usage patterns become memories for optimizing future sessions",
    },
    stars: 42,
    features: [
      "Multi-provider usage tracking",
      "Cost estimation",
      "Project attribution",
      "Rate limit monitoring",
      "Usage trend analysis",
      "CSV/JSON export",
    ],
    cliCommands: ["caut status", "caut report --days 7", "caut --help"],
    installCommand:
      "cargo install --git https://github.com/Dicklesworthstone/coding_agent_usage_tracker",
    language: "Rust",
  },
];

// Merge basic metadata from manifest (source of truth for names, taglines,
// stars, language, href). Rich UI data (deepDescription, connectsTo,
// connectionDescriptions, icon, color) stays hand-maintained.
export const flywheelTools: FlywheelTool[] = _flywheelTools.map((tool) => {
  const gen = getManifestTool(tool.id);
  if (!gen) return tool;
  return {
    ...tool,
    name: gen.displayName,
    shortName: gen.shortName,
    href: gen.href ?? tool.href,
    tagline: gen.tagline,
    stars: gen.stars ?? tool.stars,
    language: gen.language ?? tool.language,
    features: gen.features.length > 0 ? gen.features : tool.features,
  };
});

// ============================================================
// FLYWHEEL DESCRIPTION - The big picture
// ============================================================

export const flywheelDescription = {
  title: "The Agentic Coding Flywheel",
  subtitle: "Twenty tools that create unheard-of velocity",
  description:
    "A self-reinforcing system that enables multiple AI agents to work in parallel across 10+ projects, reviewing each other's work, creating and executing tasks, and making incredible autonomous progress while you're away.",
  philosophy: [
    {
      title: "Unix Philosophy",
      description:
        "Each tool does one thing exceptionally well. They compose through JSON, MCP, and Git.",
    },
    {
      title: "Agent-First",
      description:
        "Every tool has --robot mode. Designed for AI agents to call programmatically.",
    },
    {
      title: "Self-Reinforcing",
      description:
        "Using three tools is 10x better than one. The flywheel effect compounds over time.",
    },
    {
      title: "Battle-Tested",
      description:
        "Born from daily use across 8+ projects with multiple AI agents running simultaneously.",
    },
  ],
  metrics: {
    totalStars: "2K+",
    toolCount: 20,
    languages: ["Go", "Rust", "TypeScript", "Python", "Bash"],
    avgInstallTime: "< 30s each",
    projectsSimultaneous: "8+",
    agentsParallel: "6+",
  },
  keyInsight:
    "The power comes from how these tools work together. Agents figure out what to work on using BV, coordinate via Mail, search past sessions with CASS, learn from CM, stay protected by SLB and DCG, and sync repos with RU. NTM orchestrates everything.",
};

// ============================================================
// HELPER FUNCTIONS
// ============================================================

export function getToolSynergy(toolId: string): number {
  const tool = flywheelTools.find((t) => t.id === toolId);
  if (!tool) return 0;
  let connections = tool.connectsTo.length;
  connections += flywheelTools.filter((t) => t.connectsTo.includes(toolId)).length;
  return connections;
}

export function getToolsBySynergy(): FlywheelTool[] {
  return [...flywheelTools].sort((a, b) => getToolSynergy(b.id) - getToolSynergy(a.id));
}

export function getAllConnections(): Array<{ from: string; to: string }> {
  const seen = new Set<string>();
  const connections: Array<{ from: string; to: string }> = [];
  flywheelTools.forEach((tool) => {
    tool.connectsTo.forEach((targetId) => {
      const key = [tool.id, targetId].sort().join("-");
      if (!seen.has(key)) {
        seen.add(key);
        connections.push({ from: tool.id, to: targetId });
      }
    });
  });
  return connections;
}

export function getPromptsByCategory(category: AgentPrompt["category"]): AgentPrompt[] {
  return agentPrompts.filter((p) => p.category === category);
}

export function getScenarioById(id: string): WorkflowScenario | undefined {
  return workflowScenarios.find((s) => s.id === id);
}
