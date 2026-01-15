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
        tool: "bv",
        action: "Creates beads for each issue: `bd create --title='Fix auth bug'`",
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

export const flywheelTools: FlywheelTool[] = [
  {
    id: "ntm",
    name: "Named Tmux Manager",
    shortName: "NTM",
    href: "https://github.com/Dicklesworthstone/ntm",
    icon: "LayoutGrid",
    color: "from-sky-400 to-blue-500",
    tagline: "The agent cockpit",
    description:
      "Transform tmux into a multi-agent command center. Spawn Claude, Codex, and Gemini agents in named panes. Broadcast prompts to specific agent types. Persistent sessions survive SSH disconnects.",
    deepDescription:
      "NTM is the orchestration layer that lets you run multiple AI agents in parallel. Spawn agents with type classification (cc/cod/gmi), broadcast prompts with filtering, use the command palette TUI for quick actions. Features include configurable hooks, robot mode for automation, and deep Agent Mail integration.",
    connectsTo: ["slb", "mail", "cass", "caam", "ru"],
    connectionDescriptions: {
      slb: "Routes dangerous commands through SLB safety checks",
      mail: "Spawned agents auto-register with Mail for coordination",
      cass: "All session history indexed for cross-agent search",
      caam: "Quick-switches credentials when spawning new agents",
      ru: "RU agent-sweep uses ntm robot mode for orchestration",
    },
    stars: 16,
    features: [
      "Spawn multiple agents: ntm spawn project --cc=3 --cod=2 --gmi=1",
      "Broadcast to agent types: ntm send project --cc 'prompt'",
      "Command palette TUI with fuzzy search and categories",
      "Real-time dashboard with Catppuccin color themes",
      "Robot mode for scripting: --robot-status, --robot-plan",
      "Hooks: pre/post-spawn, pre/post-send, pre/post-shutdown",
    ],
    cliCommands: [
      "ntm spawn <session> --cc=N --cod=N --gmi=N",
      "ntm send <session> --cc 'prompt'",
      "ntm palette [session]",
      "ntm dashboard [session]",
    ],
    installCommand:
      "curl --proto '=https' --proto-redir '=https' -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash",
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
      "A complete coordination system for multi-agent workflows. Agents register identities, send/receive messages, search conversations, and declare file reservations to prevent edit conflicts.",
    deepDescription:
      "Agent Mail is the nervous system of the flywheel. It provides: agent identities (adjective+noun names like 'BlueLake'), threaded markdown messages, full-text search, and advisory file locks. SQLite-backed storage means complete audit trails. 20+ MCP tools for programmatic access.",
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
      "Agent identities with auto-generated names",
      "GitHub-flavored Markdown messages with threading",
      "Advisory file reservations (exclusive/shared, TTL)",
      "Full-text search across all conversations",
      "Contact policies: open, auto, contacts_only, block_all",
      "Macro helpers for common workflows",
    ],
    cliCommands: [
      "ensure_project(human_key='/path/to/project')",
      "register_agent(project_key, program='claude-code', model='opus-4.5')",
      "send_message(project_key, sender, to=['Agent'], subject, body_md)",
      "file_reservation_paths(project_key, agent, paths, ttl_seconds)",
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
    tagline: "AST-based pattern detection",
    description:
      "Custom AST-grep patterns detecting subtle bugs across 7+ languages. Designed to have false positives for AI agents to evaluate. Sub-5-second feedback loops. Perfect as pre-commit hook or agent post-processor.",
    deepDescription:
      "UBS uses ast-grep for AST-based pattern matching that tolerates false positives for AI agent review. 18 detection categories including null safety, async bugs, security vulnerabilities, and memory leaks. Zero configuration required. Unified JSON/JSONL/SARIF output for automation.",
    connectsTo: ["bv", "slb"],
    connectionDescriptions: {
      bv: "Creates Beads issues for discovered bugs",
      slb: "Pre-validates code before risky operations",
    },
    stars: 91,
    features: [
      "7 languages: JS/TS, Python, Go, Rust, C/C++, Java, Ruby",
      "18 detection categories: security, async bugs, null safety",
      "Sub-5-second feedback loops",
      "Unified output: --format=json|jsonl|sarif",
      "Baseline comparison for drift detection",
      "On-file-write hooks for Claude Code, Cursor",
    ],
    cliCommands: [
      "ubs . --format=json",
      "ubs --ci --fail-on-warning .",
      "ubs --only=python,js src/",
      "ubs --comparison baseline.json .",
    ],
    installCommand:
      'curl --proto \'=https\' --proto-redir \'=https\' -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/master/install.sh" | bash -s -- --easy-mode',
    language: "Python",
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
    connectsTo: ["mail", "ubs", "cass", "cm", "ru"],
    connectionDescriptions: {
      mail: "Task updates trigger notifications",
      ubs: "Bug scan results create blocking issues",
      cass: "Search prior sessions for task context",
      cm: "Remembers successful approaches",
      ru: "RU integrates with beads for multi-repo task tracking",
    },
    stars: 546,
    demoUrl: "https://dicklesworthstone.github.io/beads_viewer-pages/",
    features: [
      "9 graph metrics: PageRank, Betweenness, HITS, Critical Path",
      "6 TUI views: list, kanban, graph, insights, history, flow",
      "Robot protocol: --robot-triage, --robot-plan, --robot-insights",
      "Time-travel: --as-of HEAD~30, --diff-since '30 days ago'",
      "Export to Markdown, HTML (Cytoscape.js), SQLite",
      "Live reload on beads.jsonl changes",
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
    id: "cass",
    name: "Coding Agent Session Search",
    shortName: "CASS",
    href: "https://github.com/Dicklesworthstone/coding_agent_session_search",
    icon: "Search",
    color: "from-cyan-400 to-sky-500",
    tagline: "Instant search across all agents",
    description:
      "Unified search for all AI coding sessions. Indexes Claude, Codex, Cursor, Gemini, ChatGPT, Cline, and more. Tantivy-powered <60ms prefix queries.",
    deepDescription:
      "CASS unifies session history from 10 agent formats into a single searchable timeline. Edge n-gram indexing for instant prefix matching. Six ranking modes balance relevance, recency, and match quality. Robot mode with cursor pagination and token budgeting.",
    connectsTo: ["cm", "ntm", "bv"],
    connectionDescriptions: {
      cm: "Indexes stored memories for retrieval",
      ntm: "Searches all NTM-managed session histories",
      bv: "Links search results to related tasks",
    },
    stars: 145,
    features: [
      "10 agent formats: Claude Code, Codex, Cursor, Gemini, ChatGPT",
      "Tantivy search with <60ms prefix queries",
      "6 ranking modes: RecentHeavy, Balanced, RelevanceHeavy",
      "Three-pane TUI with 50+ keyboard shortcuts",
      "Robot mode with cursor pagination",
      "Remote sources via SSH/rsync",
    ],
    cliCommands: [
      'cass search "query" --robot --limit 10',
      "cass index --watch",
      "cass sources add user@host --preset macos-defaults",
      "cass timeline --today --json",
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
    tagline: "Persistent agent memory",
    description:
      "Human-like memory for AI agents. Procedural playbooks, episodic session logs, semantic facts. Agents learn from experience and never repeat mistakes.",
    deepDescription:
      "CM implements the ACE (Agentic Context Engineering) framework. Four-stage pipeline: Generator → Reflector → Validator → Curator. Playbook bullets with 90-day decay half-life. Evidence validation against CASS history. The Curator has NO LLM to prevent context collapse.",
    connectsTo: ["mail", "cass", "bv"],
    connectionDescriptions: {
      mail: "Stores conversation summaries",
      cass: "Semantic search over memories",
      bv: "Remembers successful approaches",
    },
    stars: 71,
    demoUrl: "https://dicklesworthstone.github.io/cass-memory-system-agent-mailbox-viewer/viewer/",
    features: [
      "ACE pipeline: Generator → Reflector → Validator → Curator",
      "Playbook bullets with decay (90-day half-life)",
      "5 MCP tools: cm_context, cm_feedback, memory_search",
      "Multi-iteration reflection with deduplication",
      "Evidence validation against session history",
      "4× harmful weight for mistake avoidance",
    ],
    cliCommands: [
      'cm context "task description" --json',
      "cm reflect --days 7 --max-sessions 20",
      "cm feedback --bullet-id b-123 --helpful",
      "cm serve",
    ],
    installCommand:
      "curl --proto '=https' --proto-redir '=https' -fsSL https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh | bash -s -- --easy-mode",
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
      "Manage multiple API keys for Claude, Codex, and Gemini. Sub-100ms account switching. Smart rotation with cooldown tracking. Encrypted credential bundles.",
    deepDescription:
      "CAAM enables seamless multi-account workflows. Smart profile rotation considers cooldown state, health, recency, and plan type. Transparent failover with auto-retry. AES-256-GCM encryption with Argon2id key derivation for secure export.",
    connectsTo: ["ntm"],
    connectionDescriptions: {
      ntm: "Provides credentials when spawning agents",
    },
    stars: 12,
    features: [
      "Sub-100ms account switching",
      "Smart rotation: cooldown, health, recency, plan type",
      "Transparent failover with auto-retry",
      "3 providers: Claude Code, Codex CLI, Gemini CLI",
      "AES-256-GCM encryption for export bundles",
      "Background daemon for proactive token refresh",
    ],
    cliCommands: [
      "caam activate claude alice@gmail.com",
      "caam run claude -- 'your prompt'",
      "caam cooldown set claude/alice --minutes 90",
      "caam daemon start",
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
      "Safety friction for autonomous agents. Three-tier risk classification. Cryptographic command binding with SHA-256+HMAC. Dynamic quorum. Complete audit trails.",
    deepDescription:
      "SLB implements nuclear-launch-style safety for AI agents. CRITICAL commands need 2+ approvals from different models. Commands bound with SHA-256 hash. Reviews signed with HMAC. Self-review protection prevents agents from approving their own requests.",
    connectsTo: ["mail", "ubs", "ntm"],
    connectionDescriptions: {
      mail: "Approval requests sent as urgent messages",
      ubs: "Pre-flight scans before execution",
      ntm: "Coordinates quorum across agents",
    },
    stars: 23,
    features: [
      "3-tier: CRITICAL (2+), DANGEROUS (1), CAUTION (auto-30s)",
      "SHA-256 command binding (raw + cwd + argv)",
      "HMAC-SHA256 review signatures",
      "Different-model enforcement for CRITICAL",
      "Self-review protection",
      "SQLite audit trails",
    ],
    cliCommands: [
      'slb run "rm -rf ./build"',
      "slb approve <request-id>",
      "slb reject <request-id> --reason '...'",
      "slb tui",
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
      "A Claude Code hook that blocks dangerous commands BEFORE they execute. Catches git resets, force pushes, rm -rf, DROP TABLE, and more. Fail-open design ensures you're never blocked by errors.",
    deepDescription:
      "DCG is the safety layer that protects your codebase from destructive operations. It intercepts commands as a PreToolUse hook in Claude Code, checking against 50+ protection packs covering git, filesystem, databases, Kubernetes, and cloud operations. When a dangerous command is detected, DCG blocks it and suggests safer alternatives. The allow-once workflow enables legitimate bypasses with time-limited short codes.",
    connectsTo: ["slb", "ntm", "mail"],
    connectionDescriptions: {
      slb: "DCG and SLB form a two-layer safety system - DCG blocks pre-execution, SLB validates post-execution",
      ntm: "Agents spawned by NTM are protected by DCG hooks in Claude Code",
      mail: "DCG denials can be logged to Mail for agent coordination",
    },
    stars: 50,
    features: [
      "Pre-execution blocking: Catches commands before damage",
      "50+ protection packs: git, database, k8s, cloud, filesystem",
      "Allow-once workflow: Legitimate bypasses with short codes",
      "Fail-open design: Never blocks on errors or timeouts",
      "Pack configuration: Enable packs relevant to your workflow",
      "Explain mode: Understand why commands are blocked",
    ],
    cliCommands: [
      "dcg test 'command'        # Test if command would be blocked",
      "dcg test 'command' --explain  # Detailed explanation",
      "dcg packs                 # List available packs",
      "dcg doctor                # Check installation health",
      "dcg install               # Register Claude Code hook",
      "dcg allow-once CODE       # Bypass for legitimate use",
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
    tagline: "Multi-repo sync + AI automation",
    description:
      "Synchronize dozens of GitHub repos with one command. AI-driven commit automation. Parallel workers, resume support, zero string parsing.",
    deepDescription:
      "RU solves the repo sprawl problem. Pure Bash with git plumbing (no locale issues). Parallel work-stealing sync with portable locking. Agent Sweep: three-phase AI workflow (understand → plan → execute) commits dirty repos intelligently. Review system orchestrates code reviews via ntm.",
    connectsTo: ["ntm", "mail", "bv"],
    connectionDescriptions: {
      ntm: "Uses ntm robot mode for AI-assisted reviews and agent sweep",
      mail: "Can coordinate repo claims across agents",
      bv: "Integrates with beads for multi-repo task tracking",
    },
    stars: 50,
    features: [
      "Parallel sync: ru sync -j4 (work-stealing queue)",
      "Resume from checkpoint: ru sync --resume",
      "Agent Sweep: ru agent-sweep --parallel 4",
      "AI code review: ru review --plan",
      "Repo spec syntax: owner/repo@branch as local-name",
      "JSON output: ru sync --json for automation",
    ],
    cliCommands: [
      "ru sync                    # Clone missing + pull updates",
      "ru sync -j4 --autostash    # Parallel with auto-stash",
      "ru status --fetch          # Check ahead/behind state",
      "ru agent-sweep --dry-run   # Preview AI commit plan",
      "ru agent-sweep --parallel 4 --with-release",
      "ru review --plan           # AI-assisted code review",
    ],
    installCommand:
      'curl --proto \'=https\' --proto-redir \'=https\' -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/repo_updater/main/install.sh" | bash',
    language: "Bash",
  },
  {
    id: "ms",
    name: "Meta Skill",
    shortName: "MS",
    href: "https://github.com/Dicklesworthstone/meta_skill",
    icon: "Sparkles",
    color: "from-teal-400 to-emerald-500",
    tagline: "Complete skill management platform",
    description:
      "Store skills, search them, track effectiveness, package for sharing, and integrate with AI agents via MCP server. Skills come from hand-written files, CASS mining, bundles, or guided workflows.",
    deepDescription:
      "MS is the skill management layer for AI agents. Thompson sampling learns which skills work best over time. The MCP server exposes 6 native tools (search, load, evidence, list, show, doctor) so any AI agent can query skills directly. Multi-layer security: ACIP detects prompt injection, DCG classifies command safety, path policy prevents escapes, secret scanner redacts sensitive data.",
    connectsTo: ["cass", "cm", "bv"],
    connectionDescriptions: {
      cass: "One input source for skill extraction (among several)",
      cm: "Skills and CM memories are complementary knowledge layers",
      bv: "Graph analysis via bv for PageRank, betweenness, cycles",
    },
    stars: 10,
    features: [
      "MCP server: Native AI agent integration (6 tools)",
      "Thompson sampling: Learns from usage to optimize suggestions",
      "ACIP: Prompt-injection detection with quarantine",
      "DCG: Command safety tiers (Safe/Caution/Danger/Critical)",
      "Hybrid search: BM25 + hash embeddings with RRF fusion",
      "Token packing: Optimize skill loading for context budgets",
    ],
    cliCommands: [
      "ms mcp serve              # Start MCP server for AI agents",
      "ms search 'error handling' # Hybrid search",
      "ms load <skill> --pack 2000 # Token-packed loading",
      "ms security scan <file>   # ACIP prompt injection check",
      "ms graph insights         # Dependency analysis via bv",
    ],
    installCommand: "cargo install --git https://github.com/Dicklesworthstone/meta_skill",
    language: "Rust",
  },
];

// ============================================================
// FLYWHEEL DESCRIPTION - The big picture
// ============================================================

export const flywheelDescription = {
  title: "The Agentic Coding Flywheel",
  subtitle: "Ten tools plus utilities that create unheard-of velocity",
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
    toolCount: 11,
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
