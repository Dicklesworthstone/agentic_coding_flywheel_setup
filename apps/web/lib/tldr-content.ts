/**
 * Content data for the TL;DR page showcasing all flywheel tools with
 * comprehensive descriptions, implementation highlights, and synergies.
 */

import { getManifestTldr } from './manifest-adapter';

export type TldrToolCategory = "core" | "supporting";

export type TldrFlywheelTool = {
  id: string;
  name: string;
  shortName: string;
  href: string;
  icon: string;
  color: string;
  category: TldrToolCategory;
  stars?: number;
  whatItDoes: string;
  whyItsUseful: string;
  implementationHighlights: string[];
  synergies: Array<{
    toolId: string;
    description: string;
  }>;
  techStack: string[];
  keyFeatures: string[];
  useCases: string[];
};

const _tldrFlywheelTools: TldrFlywheelTool[] = [
  // ===========================================================================
  // CORE FLYWHEEL TOOLS - Ordered by importance for workflow
  // ===========================================================================
  {
    id: "mail",
    name: "MCP Agent Mail",
    shortName: "Mail",
    href: "https://github.com/Dicklesworthstone/mcp_agent_mail",
    icon: "Mail",
    color: "from-violet-500 to-purple-600",
    category: "core",
    stars: 1400,
    whatItDoes:
      "A mail-like coordination layer for multi-agent workflows. Agents send messages, read threads, and reserve files asynchronously via MCP tools - like Gmail for AI coding agents. HTTP-only FastMCP transport with static export.",
    whyItsUseful:
      "Critical for multi-agent setups. When 5+ Claude Code instances work the same codebase, they need to coordinate who's editing what. Agent Mail prevents merge conflicts via advisory file reservations with pre-commit guard enforcement, and builds an audit trail of all agent decisions via SQLite + Git dual persistence.",
    implementationHighlights: [
      "HTTP-only FastMCP server (Streamable HTTP transport)",
      "SQLite + Git dual persistence for human-auditable artifacts",
      "FTS5 full-text search with boolean operators",
      "Pre-commit guard for file reservation enforcement",
      "Static export with Ed25519 signing and age encryption",
    ],
    synergies: [
      {
        toolId: "bv",
        description: "Task IDs in mail threads link to Beads issues",
      },
      {
        toolId: "cm",
        description: "Shared context persists across agent sessions via CM",
      },
      {
        toolId: "slb",
        description: "Two-person approval requests delivered via agent inboxes",
      },
      {
        toolId: "ntm",
        description: "NTM-spawned agents auto-register with Agent Mail",
      },
    ],
    techStack: ["Python 3.14+", "FastMCP", "SQLAlchemy async", "SQLite + FTS5", "LiteLLM"],
    keyFeatures: [
      "Threaded GFM messages with importance levels",
      "Advisory file reservations with pre-commit guard",
      "SQLite + Git dual persistence (human-auditable)",
      "Contact policies with auto-allow heuristics",
      "Static export with Ed25519 signing and age encryption",
      "Web UI and Human Overseer for human-to-agent messaging",
    ],
    useCases: [
      "Coordinating file ownership across parallel agents",
      "Passing context between session restarts",
      "Building audit trails of agent decisions",
      "Exporting encrypted archives for security audits",
    ],
  },
  {
    id: "bv",
    name: "Beads Viewer",
    shortName: "BV",
    href: "https://github.com/Dicklesworthstone/beads_viewer",
    icon: "GitBranch",
    color: "from-emerald-500 to-teal-600",
    category: "core",
    stars: 891,
    whatItDoes:
      "A fast terminal UI for viewing and analyzing Beads issues. Applies graph theory (PageRank, betweenness centrality, critical path) to identify which tasks unblock the most other work.",
    whyItsUseful:
      "Issue tracking is really a dependency graph. BV lets Claude prioritize beads intelligently by computing actual bottlenecks. The --robot-insights flag gives PageRank rankings for what to tackle first.",
    implementationHighlights: [
      "20,000+ lines of Go shipped in a single day",
      "Graph theory inspired by Frank Harary ('Mr. Graph Theory')",
      "Robot protocol (--robot-*) for AI-ready JSON output",
      "60fps TUI rendering with vim keybindings",
    ],
    synergies: [
      {
        toolId: "br",
        description: "Reads and visualizes issues from beads_rust (.beads/*.jsonl)",
      },
      {
        toolId: "mail",
        description: "Task updates trigger notifications via Agent Mail",
      },
      {
        toolId: "ubs",
        description: "Bug scanner findings become blocking issues",
      },
      {
        toolId: "cass",
        description: "Search prior sessions for task context",
      },
      {
        toolId: "ntm",
        description: "NTM uses --robot-plan for dependency analysis during multi-agent orchestration",
      },
    ],
    techStack: ["Go", "Bubble Tea", "Lip Gloss", "Graph algorithms"],
    keyFeatures: [
      "9 graph metrics: PageRank, Betweenness, HITS, Eigenvector, Critical Path",
      "6 TUI views with recipe system (11 built-in recipes)",
      "Robot protocol with TOON format for low-token output",
      "Static site export with SQLite FTS5 search",
    ],
    useCases: [
      "Identifying which task unblocks the most other work",
      "Visualizing complex dependency graphs",
      "Generating execution plans for AI agents",
    ],
  },
  {
    id: "br",
    name: "beads_rust",
    shortName: "BR",
    href: "https://github.com/Dicklesworthstone/beads_rust",
    icon: "ListTodo",
    color: "from-amber-500 to-orange-600",
    category: "core",
    stars: 128,
    whatItDoes:
      "Local-first issue tracking for AI agents. SQLite for fast local queries, JSONL export for git-friendly collaboration. Full dependency graph with blocking/blocked-by relationships, priorities P0-P4.",
    whyItsUseful:
      "Your issues travel with your repo - no external service required. Non-invasive design: never runs git commands automatically. Agents can create, update, and close issues with simple CLI commands. The bd alias provides backward compatibility.",
    implementationHighlights: [
      "~20K lines of Rust (vs 276K in original Go)",
      "SQLite primary storage + JSONL export (hybrid architecture)",
      "Non-invasive: explicit sync, never runs git automatically",
      "Full dependency graph with cycles detection",
    ],
    synergies: [
      {
        toolId: "bv",
        description: "BV visualizes and analyzes issues created by br",
      },
      {
        toolId: "mail",
        description: "Task updates notify agents via mail",
      },
      {
        toolId: "ntm",
        description: "NTM spawns agents that pick work from beads",
      },
      {
        toolId: "ubs",
        description: "UBS --beads-jsonl outputs findings as importable beads",
      },
    ],
    techStack: ["Rust", "SQLite", "Serde", "JSONL"],
    keyFeatures: [
      "SQLite + JSONL hybrid: fast queries, git-friendly export",
      "Dependency graph with cycles detection",
      "Labels, priorities (P0-P4), comments, assignees",
      "Agent-first: --json/--robot output, doctor diagnostics",
    ],
    useCases: [
      "Tracking tasks that travel with the code",
      "Finding actionable work with br ready --json",
      "Enabling agents to manage their own work queues",
    ],
  },
  {
    id: "cass",
    name: "Coding Agent Session Search",
    shortName: "CASS",
    href: "https://github.com/Dicklesworthstone/coding_agent_session_search",
    icon: "Search",
    color: "from-cyan-500 to-sky-600",
    category: "core",
    stars: 307,
    whatItDoes:
      "Blazing-fast search across all your past AI coding agent sessions. Indexes 11 agent formats: Claude Code, Codex, Cursor, Gemini, ChatGPT, Cline, Aider, Pi-Agent, Factory, OpenCode, Amp. Sub-60ms queries with optional semantic search.",
    whyItsUseful:
      "You've solved this problem before - but which session? CASS lets you search 'how did I fix that React hydration error' and instantly find the exact conversation. Three search modes (lexical, semantic, hybrid), HTML export with encryption, and multi-machine sync via SSH.",
    implementationHighlights: [
      "Rust + Tantivy BM25 with edge n-gram prefix indexing",
      "Three search modes: lexical, semantic (MiniLM/hash fallback), hybrid (RRF)",
      "Aggregations for 99% token reduction (--aggregate agent,workspace)",
      "Context command finds related sessions for source paths",
      "Multi-machine sync via SSH with interactive setup wizard",
    ],
    synergies: [
      {
        toolId: "cm",
        description: "Indexes memories stored by CM for retrieval",
      },
      {
        toolId: "ntm",
        description: "Searches all managed agent session histories",
      },
      {
        toolId: "bv",
        description: "Links search results to related Beads tasks",
      },
    ],
    techStack: ["Rust", "Tantivy", "Ratatui", "SQLite FTS5", "FastEmbed"],
    keyFeatures: [
      "Unified search across 11 agent formats",
      "Aggregations for 99% token reduction",
      "Context command for path-based session discovery",
      "Robot mode with cursor pagination and token budgeting",
      "Hash embedder fallback for deterministic searches",
    ],
    useCases: [
      "Finding how a similar bug was fixed before",
      "Aggregating session stats across agents/workspaces",
      "Path-based context discovery for related sessions",
      "Multi-machine search across laptop, desktop, and servers",
    ],
  },
  {
    id: "acfs",
    name: "Flywheel Setup",
    shortName: "ACFS",
    href: "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup",
    icon: "Cog",
    color: "from-purple-500 to-violet-600",
    category: "core",
    stars: 234,
    whatItDoes:
      "One-command bootstrap that transforms a fresh Ubuntu VPS into a fully-configured agentic coding environment. CLI provides doctor (47+ health checks), update (category-specific), cheatsheet (50+ aliases), and session management.",
    whyItsUseful:
      "Setting up a new development environment takes hours. ACFS does it in 30 minutes, installing 30+ tools, three AI agents, and all flywheel tooling. Post-install CLI provides `acfs doctor` for health checks and `acfs update` for maintenance.",
    implementationHighlights: [
      "Single curl | bash installation with SHA256 verification",
      "Idempotent and resumable installation",
      "Manifest-driven architecture (acfs.manifest.yaml)",
      "47+ doctor checks + --deep for auth/DB functional tests",
      "Category-specific updates with --dry-run preview and logging",
    ],
    synergies: [
      {
        toolId: "ntm",
        description: "Installs and configures NTM",
      },
      {
        toolId: "mail",
        description: "Sets up Agent Mail MCP server",
      },
      {
        toolId: "dcg",
        description: "Installs DCG safety hooks",
      },
    ],
    techStack: ["Bash", "YAML manifest", "Next.js wizard"],
    keyFeatures: [
      "acfs doctor: 47+ health checks across 7 categories",
      "acfs doctor --deep: Functional tests (auth, DB connectivity)",
      "acfs update: Category-specific with --dry-run preview",
      "acfs cheatsheet: 50+ aliases for modern CLI tools",
      "acfs dashboard: Static HTML dashboard generation",
      "Update logging to ~/.acfs/logs/updates/",
    ],
    useCases: [
      "Setting up new development VPS",
      "Ongoing maintenance with acfs doctor and acfs update",
      "Reproducible environment provisioning",
    ],
  },
  {
    id: "ubs",
    name: "Ultimate Bug Scanner",
    shortName: "UBS",
    href: "https://github.com/Dicklesworthstone/ultimate_bug_scanner",
    icon: "Bug",
    color: "from-rose-500 to-red-600",
    category: "core",
    stars: 132,
    whatItDoes:
      "A meta-runner that fans out per-language scanners across 8 languages (JS/TS, Python, Go, Rust, C/C++, Java, Ruby, Swift). Uses ast-grep for AST-based pattern matching with 18 detection categories and 1000+ bug patterns.",
    whyItsUseful:
      "AI coding agents move 10-100x faster than humans. UBS keeps pace with sub-5-second scans and auto-wires guardrails into Claude Code, Codex, Cursor, Gemini, and Windsurf agents. The --beads-jsonl output creates Beads issues directly from findings.",
    implementationHighlights: [
      "Shell meta-runner with per-language modules (ubs-js.sh, ubs-python.sh, etc.)",
      "ast-grep for syntax-aware pattern matching (not regex)",
      "18 detection categories: null safety, async bugs, XSS, memory leaks",
      "5 output formats: text, json, jsonl, sarif, toon",
    ],
    synergies: [
      {
        toolId: "bv",
        description: "Bug findings become blocking issues via --beads-jsonl",
      },
      {
        toolId: "br",
        description: "Direct JSONL output for beads_rust issue tracking",
      },
    ],
    techStack: ["Bash", "ast-grep", "Per-language scanners", "ripgrep"],
    keyFeatures: [
      "1000+ bug patterns across 8 languages",
      "18 detection categories with severity levels",
      "Agent guardrails: Claude Code hooks, .cursorrules",
      "Git-aware: --staged, --diff for targeted scans",
    ],
    useCases: [
      "Pre-commit quality gate for AI-generated code",
      "CI/CD pipeline integration with --fail-on-warning",
      "Baseline comparison for regression detection",
    ],
  },
  {
    id: "dcg",
    name: "Destructive Command Guard",
    shortName: "DCG",
    href: "https://github.com/Dicklesworthstone/destructive_command_guard",
    icon: "ShieldAlert",
    color: "from-red-500 to-rose-600",
    category: "core",
    stars: 89,
    whatItDoes:
      "Claude Code PreToolUse hook that blocks dangerous commands BEFORE execution. 50+ packs across 17 categories: git (reset --hard, force push), filesystem (rm -rf), databases (DROP TABLE), Kubernetes, cloud providers, and more.",
    whyItsUseful:
      "AI agents can and will run 'rm -rf /' if they think it solves your problem. DCG catches catastrophic commands before they execute with sub-millisecond latency. Safe directory exceptions (/tmp, /var/tmp, $TMPDIR) allow temp operations without friction.",
    implementationHighlights: [
      "SIMD-accelerated sub-millisecond PreToolUse hook",
      "Heredoc/inline script scanning (python -c, bash -c, node -e)",
      "Smart context detection: data vs execution contexts",
      "Agent-specific trust profiles with configurable permissions",
      "MCP server mode for direct agent integration",
    ],
    synergies: [
      {
        toolId: "slb",
        description: "Works alongside SLB for layered command safety",
      },
      {
        toolId: "ntm",
        description: "Guards all commands in NTM-managed sessions",
      },
    ],
    techStack: ["Rust", "Claude Code hooks", "SARIF output", "MCP"],
    keyFeatures: [
      "Heredoc/inline script AST scanning",
      "49+ packs: git, filesystem, database, k8s, cloud",
      "Agent-specific trust levels and profiles",
      "dcg scan for CI/pre-commit integration",
      "MCP server for direct agent access",
    ],
    useCases: [
      "Pre-execution safety for AI coding agents",
      "Catching hidden destructive ops in inline scripts",
      "CI integration via dcg scan command",
      "MCP server mode for agent workflows",
    ],
  },
  {
    id: "ru",
    name: "Repo Updater",
    shortName: "RU",
    href: "https://github.com/Dicklesworthstone/repo_updater",
    icon: "RefreshCw",
    color: "from-orange-500 to-amber-600",
    category: "core",
    stars: 78,
    whatItDoes:
      "Multi-repo management system: sync 100+ repos, AI-assisted code review with priority scoring, dependency updates across package managers, and agent-driven commit automation.",
    whyItsUseful:
      "Managing 100+ repos manually is impossible. 'ru sync' handles clone/pull in parallel. 'ru review' discovers issues/PRs via GraphQL batch queries, scores by priority (security+50, bugs+30, age), and spawns isolated Claude Code sessions in worktrees.",
    implementationHighlights: [
      "Pure Bash with git plumbing (rev-list, status --porcelain)",
      "Work-stealing queue for parallel sync with portable locking",
      "GraphQL batch queries for efficient issue/PR discovery",
      "Git worktree isolation for parallel AI review sessions",
      "Meaningful exit codes: 0=ok, 1=partial, 2=conflicts, 3=system",
      "TOON/JSON output modes for CI/automation integration",
    ],
    synergies: [
      {
        toolId: "ntm",
        description: "Uses ntm robot mode API for AI review session management",
      },
      {
        toolId: "mail",
        description: "Coordinates repo claims across parallel agents",
      },
      {
        toolId: "bv",
        description: "Multi-repo task tracking via beads integration",
      },
    ],
    techStack: ["Bash 4.0+", "Git plumbing", "GitHub CLI GraphQL", "ntm robot mode"],
    keyFeatures: [
      "Parallel sync with work-stealing queue (-j4)",
      "AI code review with priority scoring (ru review)",
      "Dependency updates (npm, pip, cargo, go, composer)",
      "Agent sweep for multi-repo automation",
      "Bulk import from GitHub/GitLab/Bitbucket (ru import)",
      "Orphan cleanup with ru prune",
      "Resume from checkpoint (--resume)",
    ],
    useCases: [
      "Syncing 100+ repos across development machines",
      "AI-assisted code review at scale",
      "Automated dependency updates with testing",
      "Bulk onboarding repos from multiple Git providers",
    ],
  },
  {
    id: "cm",
    name: "CASS Memory System",
    shortName: "CM",
    href: "https://github.com/Dicklesworthstone/cass_memory_system",
    icon: "Brain",
    color: "from-pink-500 to-fuchsia-600",
    category: "core",
    stars: 152,
    whatItDoes:
      "Cross-agent procedural memory system. Transforms scattered sessions from all your AI agents into persistent, unified knowledge. Three-layer cognitive architecture: Episodic (raw sessions via CASS) → Working (diary summaries) → Procedural (playbook rules with confidence tracking).",
    whyItsUseful:
      "A debugging technique discovered in Cursor is immediately available to Claude Code. Rules have 90-day decay half-life and 4× harmful weight for mistakes. Bad rules auto-invert into anti-pattern warnings. Every agent learns from every other agent's experience.",
    implementationHighlights: [
      "Cross-agent learning: Claude Code, Codex, Cursor, Aider sessions unified",
      "Confidence decay system with 90-day half-life",
      "Scientific validation: rules require CASS evidence before acceptance",
      "Anti-pattern learning: harmful rules become warnings",
    ],
    synergies: [
      {
        toolId: "cass",
        description:
          "Primary dependency - provides episodic memory via session search",
      },
      {
        toolId: "mail",
        description: "Memory context shared across agent conversations",
      },
      {
        toolId: "bv",
        description: "Task patterns and successful approaches remembered",
      },
    ],
    techStack: ["TypeScript", "Bun", "SQLite"],
    keyFeatures: [
      "Cross-agent learning from all AI coding tools",
      "Confidence decay prevents stale rules",
      "Agent-native onboarding with gap analysis",
      "cm context returns rules, anti-patterns, and history snippets",
    ],
    useCases: [
      "Cross-pollinating debugging knowledge between agents",
      "Building institutional memory that persists across tools",
      "Learning from past mistakes with anti-pattern warnings",
    ],
  },
  {
    id: "ntm",
    name: "Named Tmux Manager",
    shortName: "NTM",
    href: "https://github.com/Dicklesworthstone/ntm",
    icon: "LayoutGrid",
    color: "from-sky-500 to-blue-600",
    category: "core",
    stars: 69,
    whatItDoes:
      "A multi-agent tmux orchestration tool with 80+ commands. Spawns Claude, Codex, and Gemini agents in named panes with type classification (cc/cod/gmi). Monitors context windows, detects file conflicts, and provides robot mode for automation.",
    whyItsUseful:
      "Running multiple AI agents simultaneously creates chaos without orchestration. NTM provides the command center: spawn agents with one command, broadcast prompts to specific types, monitor context usage, and coordinate via Agent Mail. Sessions persist across SSH disconnects and system reboots.",
    implementationHighlights: [
      "Go implementation with Bubble Tea TUI and Catppuccin themes",
      "Context rotation monitors usage, warns at 80%, triggers compaction recovery",
      "Robot mode (--robot-*) outputs JSON for agent automation",
      "Direct CASS integration: --robot-cass-search, --robot-cass-context",
      "Bead management: --robot-bead-create, --robot-bead-claim, --robot-bead-close",
    ],
    synergies: [
      {
        toolId: "slb",
        description:
          "SLB provides two-person rule safety checks for dangerous commands in NTM sessions",
      },
      {
        toolId: "mail",
        description:
          "Agents auto-register with Mail; ntm mail commands for messaging; pre-commit guard enforces file reservations",
      },
      {
        toolId: "cass",
        description: "Direct integration via --robot-cass-search and --robot-cass-context commands",
      },
      {
        toolId: "bv",
        description: "Graph analysis via --robot-plan and --robot-graph for dependency insights",
      },
      {
        toolId: "br",
        description: "Bead management via --robot-bead-* commands for issue tracking",
      },
    ],
    techStack: ["Go 1.25+", "Bubble Tea", "tmux 3.0+", "Catppuccin themes"],
    keyFeatures: [
      "80+ commands: spawn, send, dashboard, checkpoint, health, and more",
      "Agent type classification with named panes (cc, cod, gmi)",
      "Context window monitoring with automatic compaction recovery",
      "Command palette TUI with fuzzy search and pinned commands",
      "Robot mode for scripting and agent automation",
      "Hooks: pre/post-spawn, pre/post-send, pre/post-shutdown",
    ],
    useCases: [
      "Running 10+ agents across multiple projects simultaneously",
      "Broadcasting prompts to all Claude agents: ntm send proj --cc 'prompt'",
      "Monitoring context window usage to prevent agent context exhaustion",
      "Checkpointing session state before risky operations",
    ],
  },
  {
    id: "slb",
    name: "Simultaneous Launch Button",
    shortName: "SLB",
    href: "https://github.com/Dicklesworthstone/simultaneous_launch_button",
    icon: "ShieldCheck",
    color: "from-amber-500 to-orange-600",
    category: "core",
    stars: 49,
    whatItDoes:
      "Nuclear-launch-style two-person rule for dangerous commands. Four risk tiers classify commands via 40+ regex patterns: CRITICAL (2+ approvals), DANGEROUS (1 approval), CAUTION (30s auto-approve), SAFE (skip). Cryptographic signing, rollback support, and outcome analytics.",
    whyItsUseful:
      "AI agents can and will run destructive commands if they think it solves your problem. SLB intercepts commands like 'rm -rf /', 'DROP DATABASE', and 'terraform destroy' requiring explicit approval from another agent or human reviewer before execution. Watch mode lets reviewing agents stream pending requests.",
    implementationHighlights: [
      "Go implementation with Bubble Tea TUI dashboard",
      "40+ regex patterns: 24 critical, 15 dangerous, 6 safe",
      "HMAC-SHA256 cryptographic approval signatures",
      "Watch mode streams NDJSON events for reviewing agents",
      "Pre-execution state capture for rollback",
      "Outcome recording for pattern improvement",
    ],
    synergies: [
      {
        toolId: "dcg",
        description: "DCG blocks pre-execution, SLB validates with multi-agent approval",
      },
      {
        toolId: "ntm",
        description: "Coordinates approval quorum across NTM-managed agents",
      },
      {
        toolId: "mail",
        description: "Approval requests can be routed via Agent Mail",
      },
      {
        toolId: "caam",
        description: "Account switching can require SLB approval for team workflows",
      },
    ],
    techStack: ["Go 1.24+", "Bubble Tea", "SQLite", "HMAC-SHA256"],
    keyFeatures: [
      "4-tier risk: CRITICAL (2+), DANGEROUS (1), CAUTION (30s), SAFE (skip)",
      "40+ regex patterns for command classification",
      "Self-review protection (agents can't approve own requests)",
      "Watch mode for reviewing agents (NDJSON streaming)",
      "Claude Code hooks and Cursor rules generation",
      "Session management with cryptographic signing",
    ],
    useCases: [
      "Two-person approval for rm -rf, DROP DATABASE, terraform destroy",
      "Agent coordination for dangerous operations",
      "Audit trail of all dangerous command approvals",
      "Rollback support when commands cause problems",
    ],
  },
  {
    id: "ms",
    name: "Meta Skill",
    shortName: "MS",
    href: "https://github.com/Dicklesworthstone/meta_skill",
    icon: "Sparkles",
    color: "from-teal-500 to-emerald-600",
    category: "core",
    stars: 68,
    whatItDoes:
      "Local-first skill management platform: dual persistence (SQLite + Git), hybrid search (BM25 + semantic + RRF), UCB bandit optimization, multi-layer security (ACIP + DCG), graph analysis via bv, MCP server for AI agents.",
    whyItsUseful:
      "AI agents need reusable context to be effective. MS doesn't just store skills—it learns which ones work via UCB bandit optimization. Context-aware auto-loading suggests skills based on project type. Pack contracts optimize token budgets. The MCP server makes skills native tools for any AI agent.",
    implementationHighlights: [
      "Dual persistence: SQLite for queries + Git for audit trails (neither privileged)",
      "UCB bandit learns from feedback to optimize suggestions",
      "Hybrid search: BM25 + deterministic hash embeddings + RRF fusion",
      "MCP server exposes 12 native tools (search, load, evidence, list, show, doctor, lint, suggest, feedback, index, validate, config)",
      "ACIP prompt-injection quarantine + DCG command safety tiers",
      "Graph analysis via bv: PageRank, betweenness, cycles, critical path",
    ],
    synergies: [
      {
        toolId: "cass",
        description: "One input source for skill extraction (not the only one)",
      },
      {
        toolId: "cm",
        description: "Skills and CM memories are complementary knowledge layers",
      },
      {
        toolId: "bv",
        description: "Graph analysis via bv for PageRank, bottlenecks, cycles",
      },
      {
        toolId: "jfp",
        description: "JFP downloads remote prompts, MS manages local skills",
      },
    ],
    techStack: ["Rust", "SQLite + FTS5", "Git archive", "MCP stdio/HTTP"],
    keyFeatures: [
      "MCP server: 12 native tools for AI agent integration",
      "UCB bandit optimization learns from feedback",
      "Context-aware auto-loading (ms load --auto)",
      "Pack contracts: debug/refactor/learn/quickref/codegen",
      "Multi-layer security (ACIP, DCG, path policy, secrets)",
      "Hybrid search: BM25 + hash embeddings + RRF",
    ],
    useCases: [
      "AI agents querying skills via MCP during sessions",
      "Context-aware skill suggestions based on project type",
      "Token-optimized loading with pack contracts",
      "Graph analysis of skill dependencies via bv",
    ],
  },
  {
    id: "rch",
    name: "Remote Compilation Helper",
    shortName: "RCH",
    href: "https://github.com/Dicklesworthstone/remote_compilation_helper",
    icon: "Cpu",
    color: "from-indigo-500 to-blue-600",
    category: "core",
    stars: 35,
    whatItDoes:
      "Claude Code PreToolUse hook that offloads Rust compilation to remote workers. Intercepts cargo commands, syncs source via rsync + zstd, compiles on server-grade hardware, streams artifacts back.",
    whyItsUseful:
      "Multi-agent swarms trigger many concurrent builds. RCH intercepts commands before execution and routes them to remote workers with health probes and priority scheduling. Agent detection coordinates builds across Claude Code, Codex, and Gemini sessions.",
    implementationHighlights: [
      "PreToolUse hook intercepts cargo before execution",
      "rsync + zstd with incremental artifact streaming",
      "Worker health probes and priority scheduling",
      "Agent detection for multi-agent coordination",
    ],
    synergies: [
      {
        toolId: "ntm",
        description: "Agents in NTM sessions use RCH for builds",
      },
      {
        toolId: "ru",
        description: "RU syncs repos that RCH then builds remotely",
      },
      {
        toolId: "bv",
        description: "Build tasks can be tracked via beads",
      },
    ],
    techStack: ["Rust", "rsync", "zstd", "SSH", "Claude Code hooks"],
    keyFeatures: [
      "PreToolUse hook intercepts cargo automatically",
      "Worker pool with health probes and priorities",
      "Daemon mode with persistent SSH connections",
      "Agent detection: Claude Code, Codex, Gemini",
    ],
    useCases: [
      "Offloading builds during multi-agent sessions",
      "Reducing local CPU usage during heavy compilation",
      "Distributing builds across powerful remote servers",
    ],
  },
  {
    id: "caam",
    name: "Coding Agent Account Manager",
    shortName: "CAAM",
    href: "https://github.com/Dicklesworthstone/coding_agent_account_manager",
    icon: "KeyRound",
    color: "from-amber-500 to-orange-600",
    category: "core",
    stars: 12,
    whatItDoes:
      "Manages multiple accounts for Claude Code, Codex CLI, and Gemini CLI with sub-100ms switching. Vault profiles store auth files for instant activation without browser flows. Smart rotation algorithms automatically select the best profile based on cooldown state, health, and usage patterns.",
    whyItsUseful:
      "When running multiple agents, you'll hit rate limits. CAAM lets you switch accounts instantly - no browser login, no waiting. Profile isolation enables parallel sessions where each agent uses its own credentials. Health scoring (🟢/🟡/🔴) shows which profiles are ready vs. cooling down.",
    implementationHighlights: [
      "Go implementation with 50+ commands",
      "Vault-based profile storage for instant switching",
      "Robot mode with JSON output for agent integration",
      "AES-256-GCM encrypted bundles with Argon2id key derivation",
      "Background daemon for proactive token refresh",
    ],
    synergies: [
      {
        toolId: "ntm",
        description: "NTM spawns agents with isolated CAAM profiles for parallel sessions",
      },
      {
        toolId: "mail",
        description: "Account switches can trigger Agent Mail notifications",
      },
      {
        toolId: "slb",
        description: "Team approval workflows for account switching",
      },
    ],
    techStack: ["Go", "SQLite", "OAuth", "AES-256-GCM", "Argon2id"],
    keyFeatures: [
      "Sub-100ms switching via vault profiles",
      "caam run: automatic failover on rate limits",
      "Project-profile associations (per-directory defaults)",
      "Smart rotation: cooldown, health, recency, plan type",
      "Health scoring: healthy/warning/critical status",
      "Robot mode with JSON output for agents",
    ],
    useCases: [
      "caam run with automatic rate limit failover",
      "Per-directory profile defaults for projects",
      "Running parallel agents with isolated credentials",
      "Automated rotation for long-running sessions",
    ],
  },
  {
    id: "wa",
    name: "WezTerm Automata",
    shortName: "WA",
    href: "https://github.com/Dicklesworthstone/wezterm_automata",
    icon: "Monitor",
    color: "from-cyan-500 to-teal-600",
    category: "core",
    stars: 42,
    whatItDoes:
      "Terminal hypervisor that captures pane output in real-time, detects agent state transitions through pattern matching, and enables event-driven automation across multiple AI coding agents.",
    whyItsUseful:
      "When running multiple AI agents in WezTerm, you need to know when they hit rate limits, complete tasks, or need approval. WA observes all panes with sub-50ms latency and triggers automated responses.",
    implementationHighlights: [
      "Real-time delta extraction (sub-50ms latency)",
      "Multi-agent pattern detection engine",
      "FTS5-powered full-text search with BM25 ranking",
      "TOON output format for token-efficient AI consumption",
      "Workflow automation triggered by pattern matches",
    ],
    synergies: [
      {
        toolId: "ntm",
        description: "WA observes agents spawned by NTM",
      },
      {
        toolId: "mail",
        description: "State changes trigger Agent Mail notifications",
      },
      {
        toolId: "bv",
        description: "Task completions can update bead status",
      },
    ],
    techStack: ["Rust", "WezTerm API", "SQLite FTS5", "Pattern matching"],
    keyFeatures: [
      "Real-time terminal observation (<50ms latency)",
      "Multi-agent pattern detection (Claude, Codex, Gemini)",
      "Robot Mode JSON/TOON API",
      "Event-driven wait-for automation",
      "Explainability via 'wa why' command",
    ],
    useCases: [
      "Detecting agent rate limits and errors",
      "Coordinating multi-agent workflows",
      "Searching across captured terminal sessions",
      "Triggering automated responses on state changes",
    ],
  },
  {
    id: "brenner",
    name: "Brenner Bot",
    shortName: "Brenner",
    href: "https://github.com/Dicklesworthstone/brenner_bot",
    icon: "FlaskConical",
    color: "from-rose-500 to-pink-600",
    category: "core",
    stars: 28,
    whatItDoes:
      "Multi-agent scientific research orchestration platform based on Sydney Brenner's methodology. Manages full research artifact lifecycle: hypotheses, discriminative tests, anomalies, critiques, and evidence packs with cockpit runtime for parallel agent sessions.",
    whyItsUseful:
      "Transforms AI agents into a collaborative research group with rigorous scientific discipline. The Brenner approach emphasizes exclusion over accumulation, third-alternative thinking, and discriminative experiments that collapse hypothesis space fast.",
    implementationHighlights: [
      "Hypothesis lifecycle management: proposed → active → killed/validated with discriminative tests",
      "Evidence packs: import papers, datasets, prior sessions with stable EV-NNN citations",
      "Anomaly tracking with paradigm_shifting status and hypothesis spawning capability",
      "Cockpit runtime: multi-agent sessions with role-specific prompts (hypothesis_generator, test_designer, adversarial_critic)",
      "Session state machine with phase detection and artifact compiler (50+ validation rules)",
    ],
    synergies: [
      {
        toolId: "mail",
        description: "Research sessions coordinate via Agent Mail threads with acknowledgment tracking",
      },
      {
        toolId: "ntm",
        description: "Cockpit runtime spawns parallel research agents with role-specific prompts",
      },
      {
        toolId: "cass",
        description: "Research session history searchable for prior solutions and patterns",
      },
    ],
    techStack: ["TypeScript", "Bun", "Agent Mail", "ntm", "Multi-model AI"],
    keyFeatures: [
      "Hypothesis lifecycle: create, activate, kill, validate with test evidence",
      "Evidence packs with stable EV-NNN citations for papers, datasets, prior sessions",
      "Anomaly management: track, defer, resolve, spawn new hypotheses",
      "Critique system: adversarial attacks with severity levels and responses",
      "Cockpit runtime: orchestrate multi-agent sessions with role assignments",
      "Corpus search with 236 transcript sections and §n anchors",
    ],
    useCases: [
      "Running structured multi-agent research sessions with hypothesis tracking",
      "Managing evidence from external sources with citation anchors",
      "Designing discriminative experiments that eliminate rather than confirm",
      "Orchestrating parallel AI agents as a collaborative research group",
    ],
  },
  // ===========================================================================
  // SUPPORTING FLYWHEEL TOOLS
  // ===========================================================================
  {
    id: "giil",
    name: "Get Image from Internet Link",
    shortName: "GIIL",
    href: "https://github.com/Dicklesworthstone/giil",
    icon: "Image",
    color: "from-slate-500 to-gray-600",
    category: "supporting",
    stars: 24,
    whatItDoes:
      "Downloads full-resolution images from iCloud, Dropbox, Google Photos, and Google Drive share links using a four-tier capture strategy with headless Chromium automation.",
    whyItsUseful:
      "When debugging remotely, users share cloud links but you're SSH'd into a headless server. GIIL's four-tier capture (download button → CDN interception → element screenshot → viewport fallback) ensures maximum quality retrieval for AI agent analysis.",
    implementationHighlights: [
      "Four-tier capture: download→CDN→element→viewport",
      "Playwright/Chromium headless browser automation",
      "MozJPEG compression with configurable quality",
      "Album mode (--all) extracts all images from shares",
      "Structured exit codes (0/10/11/12/13) for scripting",
    ],
    synergies: [
      {
        toolId: "mail",
        description: "Downloaded images can be referenced in Agent Mail",
      },
      {
        toolId: "cass",
        description: "Image analysis sessions are searchable",
      },
    ],
    techStack: ["Bash", "Node.js", "Playwright", "Chromium", "Sharp", "MozJPEG"],
    keyFeatures: [
      "iCloud, Dropbox, Google Photos, Google Drive support",
      "Four-tier intelligent capture strategy",
      "Album mode for multi-image shares",
      "JSON/TOON/base64 output formats",
      "HEIC/AVIF to JPEG conversion",
    ],
    useCases: [
      "Retrieving user screenshots for remote debugging",
      "Extracting full albums from cloud shares",
      "AI agent visual analysis workflows",
      "Scripted image collection with exit code handling",
    ],
  },
  {
    id: "srps",
    name: "System Resource Protection Script",
    shortName: "SRPS",
    href: "https://github.com/Dicklesworthstone/system_resource_protection_script",
    icon: "Shield",
    color: "from-yellow-400 to-orange-500",
    category: "supporting",
    stars: 50,
    whatItDoes:
      "Installs ananicy-cpp with curated rules to auto-deprioritize background processes. Includes sysmoni Go TUI (Bubble Tea) with IO throughput, FD counts, per-core sparklines, JSON export. Works on Linux and WSL2.",
    whyItsUseful:
      "When running cargo build, npm install, or multiple AI agents, SRPS prevents unresponsive systems by lowering priority of known resource hogs. Safety-first: no automated process killing. Helper tools for diagnostics.",
    implementationHighlights: [
      "ananicy-cpp daemon with curated process rules",
      "sysmoni Go TUI: CPU/MEM, IO throughput, FD counts",
      "Per-core sparklines, JSON/NDJSON export, GPU monitoring",
      "Helper tools: check-throttled, srps-doctor, cursor-guard",
    ],
    synergies: [
      {
        toolId: "ntm",
        description: "Keeps tmux sessions responsive during heavy workloads",
      },
      {
        toolId: "slb",
        description: "Prevents multiple agents from starving each other for resources",
      },
      {
        toolId: "dcg",
        description: "Combined safety: resource protection + command protection",
      },
      {
        toolId: "pt",
        description: "PT identifies stuck processes, SRPS deprioritizes resource hogs",
      },
    ],
    techStack: ["Go", "Bubble Tea", "C++", "ananicy-cpp", "systemd"],
    keyFeatures: [
      "Automatic process deprioritization via ananicy-cpp",
      "sysmoni TUI with IO and FD monitoring",
      "WSL2-compatible systemd limits",
      "Idempotent installer with --plan dry-run",
    ],
    useCases: [
      "Multi-agent coding sessions",
      "Large compilation jobs",
      "Heavy test suite runs",
      "Background indexing (rust-analyzer, typescript server)",
    ],
  },
  {
    id: "xf",
    name: "X Archive Search",
    shortName: "XF",
    href: "https://github.com/Dicklesworthstone/xf",
    icon: "Archive",
    color: "from-blue-500 to-indigo-600",
    category: "supporting",
    stars: 156,
    whatItDoes:
      "Ultra-fast search over X/Twitter data archives with sub-millisecond latency. Uses hybrid BM25 + semantic search with Reciprocal Rank Fusion. Indexes tweets, likes, DMs, and Grok conversations.",
    whyItsUseful:
      "Your X archive is a goldmine of bookmarks, threads, and ideas, but Twitter's search is terrible. XF makes your archive instantly searchable (<10ms) with both keyword and semantic matching. DM context search shows full conversation threads.",
    implementationHighlights: [
      "Rust + Tantivy for sub-millisecond lexical search",
      "Hybrid BM25 + semantic search with RRF fusion",
      "Hash embedder (default) or optional MiniLM (--semantic)",
      "SIMD-accelerated vector search with F16 quantization",
      "Privacy-first, fully local processing (no network calls)",
    ],
    synergies: [
      {
        toolId: "cass",
        description: "Similar search architecture and patterns",
      },
      {
        toolId: "cm",
        description: "Found tweets can become memories",
      },
    ],
<<<<<<< Updated upstream
    techStack: ["Rust", "Tantivy", "SQLite", "FNV-1a hash embeddings"],
    keyFeatures: [
      "Sub-millisecond lexical, <10ms hybrid search",
      "DM context view with full conversation threads",
      "JSON/CSV/compact output formats",
      "Interactive REPL shell (xf shell)",
    ],
    useCases: [
      "Finding that thread you bookmarked months ago",
      "Searching DMs with full conversation context",
      "Exporting tweets to JSON for analysis pipelines",
    techStack: ["Rust", "Tantivy", "SQLite", "SIMD", "F16 quantization"],
    keyFeatures: [
      "Sub-millisecond lexical search (<10ms typical)",
      "Hybrid BM25 + semantic with RRF fusion",
      "DM context search with full threads",
      "Indexes tweets, likes, DMs, Grok chats",
    ],
    useCases: [
      "Finding that thread you bookmarked months ago",
=======
    techStack: ["Rust", "Tantivy", "SQLite", "SIMD", "F16 quantization"],
    keyFeatures: [
      "Sub-millisecond lexical search (<10ms typical)",
      "Hybrid BM25 + semantic with RRF fusion",
      "DM context search with full threads",
      "Indexes tweets, likes, DMs, Grok chats",
    ],
    useCases: [
      "Finding that thread you bookmarked months ago",
>>>>>>> Stashed changes
      "Searching DM conversations with full context",
      "Researching past discussions on a topic",
    ],
  },
  {
    id: "s2p",
    name: "Source to Prompt TUI",
    shortName: "s2p",
    href: "https://github.com/Dicklesworthstone/source_to_prompt_tui",
    icon: "FileCode",
    color: "from-green-500 to-emerald-600",
    category: "supporting",
    stars: 78,
    whatItDoes:
      "World-class terminal UI for combining source code files into LLM-ready prompts. Tree explorer with vim-style navigation, live syntax preview, token counting, and structured XML-like output optimized for AI parsing.",
    whyItsUseful:
      "Crafting prompts with code context is tedious and error-prone. S2P provides visual file selection with sizes and line counts, real-time token/cost estimation, quick file-type shortcuts (1-9,0,r), and produces structured output that LLMs parse reliably.",
    implementationHighlights: [
      "Bun single-binary with zero runtime dependencies",
      "React/Ink terminal UI with virtualized rendering",
      "tiktoken cl100k_base encoding (GPT-4 compatible)",
      "Structured XML output: <preamble>, <goal>, <project_structure>, <files>",
      "JS/TS minification via Terser, CSS via csso",
      "Recursive .gitignore support including nested gitignores",
    ],
    synergies: [
      {
        toolId: "cass",
        description: "Generated prompts become searchable session history",
      },
      {
        toolId: "cm",
        description: "Effective prompt patterns stored as procedural memories",
      },
    ],
    techStack: ["TypeScript", "Bun", "React", "Ink", "tiktoken", "Terser", "csso"],
    keyFeatures: [
      "Tree file explorer with sizes and line counts",
      "Vim-style navigation (j/k/h/l)",
      "Quick file-type shortcuts (1-9,0,r)",
      "Live syntax-highlighted preview",
      "Real-time token count and cost estimate",
      "Context window usage bar (128K limit)",
      "Preset save/load (~/.source2prompt.json)",
      "Code minification and comment stripping",
    ],
    useCases: [
      "Preparing code context for Claude Code, Codex, or GPT",
      "Creating reproducible prompt templates with presets",
      "Managing context window budget visually",
      "Generating documentation or code review prompts",
      "Sharing code context in structured format",
    ],
  },
  {
    id: "apr",
    name: "Automated Plan Reviser Pro",
    shortName: "APR",
    href: "https://github.com/Dicklesworthstone/automated_plan_reviser_pro",
    icon: "FileText",
    color: "from-amber-500 to-yellow-600",
    category: "supporting",
    stars: 85,
    whatItDoes:
      "Iterative specification refinement via GPT Pro 5.2 Extended Reasoning + Oracle. Document bundling (README + spec + impl), convergence analytics with weighted scoring, session management, and robot mode JSON API for coding agents.",
    whyItsUseful:
      "Complex specs need 15-20 review cycles. APR automates the loop: rounds 1-3 fix architecture, 4-7 refine interfaces, 8-12 handle edge cases, 13+ polish abstractions. Convergence score (≥0.75 = stable) tells you when to stop.",
    implementationHighlights: [
      "GPT Pro 5.2 Extended Reasoning via Oracle browser automation",
      "Convergence analytics (output_trend + change_velocity + similarity)",
      "Pre-flight validation and auto-retry with exponential backoff",
      "Session locking prevents concurrent runs",
      "Robot mode: apr robot validate/run/history with semantic error codes",
    ],
    synergies: [
      {
        toolId: "jfp",
        description: "Battle-tested prompts can be refined into specifications",
      },
      {
        toolId: "cm",
        description: "Refined plans become searchable memories",
      },
      {
        toolId: "bv",
        description: "Refined specs generate well-structured beads",
      },
    ],
    techStack: ["Bash", "Oracle", "Node.js", "gum", "GPT Pro 5.2"],
    keyFeatures: [
      "Document bundling (README + spec + implementation)",
      "Convergence analytics with weighted scoring",
      "Background processing with session management",
      "Claude Code integration prompts (apr integrate)",
      "Robot mode JSON API with semantic error codes",
    ],
    useCases: [
      "Multi-round spec refinement converging on stable design",
      "Background 10-60 minute reviews with desktop notifications",
      "Automated agent workflows via robot mode",
      "Tracking convergence to know when specs are ready",
    ],
  },
  {
    id: "jfp",
    name: "JeffreysPrompts CLI",
    shortName: "JFP",
    href: "https://jeffreysprompts.com",
    icon: "Sparkles",
    color: "from-pink-500 to-rose-600",
    category: "supporting",
    stars: 120,
    whatItDoes:
      "Official CLI for jeffreysprompts.com - browse, search, and install battle-tested prompts as Claude Code skills. Features interactive fzf-style picker and task-based suggestion engine.",
    whyItsUseful:
      "Instead of writing prompts from scratch, install proven patterns. The interactive mode (jfp i) lets you fuzzy-search the entire library, while jfp suggest recommends prompts based on your task description. Premium features include collections, cross-machine sync, and a skills marketplace.",
    implementationHighlights: [
      "TypeScript/Bun compiled to standalone binary",
      "Interactive fzf-style picker (jfp i) for browsing",
      "Task-based suggestions (jfp suggest) using semantic matching",
      "MCP server mode (jfp serve) for agent integration",
      "Variable rendering with placeholder fill (jfp render --fill)",
    ],
    synergies: [
      {
        toolId: "ms",
        description: "JFP downloads remote prompts, MS manages local skills - they complement each other",
      },
      {
        toolId: "apr",
        description: "Downloaded prompts can be refined into comprehensive specs via APR",
      },
      {
        toolId: "cm",
        description: "Effective prompts become retrievable memories",
      },
    ],
    techStack: ["TypeScript", "Bun", "Claude Code Skills API"],
    keyFeatures: [
      "Interactive fzf-style prompt picker (jfp i)",
      "Task-based suggestions (jfp suggest)",
      "Workflow bundles for team patterns",
      "MCP server mode for agent workflows",
      "Premium: collections, sync, marketplace",
    ],
    useCases: [
      "Bootstrapping a new project with proven prompts",
      "Task-based discovery with jfp suggest",
      "Running as MCP server for agent access",
      "Syncing prompt libraries across machines",
    ],
  },
  {
    id: "pt",
    name: "Process Triage",
    shortName: "PT",
    href: "https://github.com/Dicklesworthstone/process_triage",
    icon: "Activity",
    color: "from-red-500 to-orange-600",
    category: "supporting",
    stars: 45,
    whatItDoes:
      "Bayesian-inference zombie/abandoned process detection using four-state classification (Useful, Useful-but-bad, Abandoned, Zombie) with evidence-based posterior probability scoring.",
    whyItsUseful:
      "When builds hang or test runners go rogue, PT computes P(state|evidence) using process type, age, CPU/IO activity, memory, and past decisions. Confidence levels (very_high >0.99 to low <0.80) guide safe termination with identity validation and staged kill signals.",
    implementationHighlights: [
      "Rust pt-core inference engine + Bash wrapper",
      "Four-state Bayesian posterior classification",
      "Identity validation (boot_id:start_time:pid) prevents PID reuse",
      "Protected process lists (systemd, sshd, docker, postgres)",
      "Agent/robot mode with safety gates (min_posterior, max_kills, fdr_budget)",
    ],
    synergies: [
      {
        toolId: "srps",
        description: "PT terminates stuck processes, SRPS prevents them from hogging resources",
      },
      {
        toolId: "ntm",
        description: "Clean up runaway processes in tmux sessions",
      },
    ],
    techStack: ["Rust", "Bash", "gum", "procfs", "Bayesian inference"],
    keyFeatures: [
      "Four-state classification with posterior probabilities",
      "Evidence-based scoring (process type, age, CPU, IO, memory)",
      "Protected processes and identity validation",
      "Interactive gum TUI for process selection",
      "Session bundles (.ptb) for sharing/reproducibility",
    ],
    useCases: [
      "Identifying and killing abandoned dev servers",
      "Cleaning up zombie processes with confidence scores",
      "Automated triage via agent/robot mode with safety gates",
      "Sharing reproducible triage sessions via .ptb bundles",
    ],
  },
  {
    id: "tru",
    name: "TOON Rust",
    shortName: "TRU",
    href: "https://github.com/Dicklesworthstone/toon_rust",
    icon: "FileJson",
    color: "from-violet-500 to-purple-600",
    category: "supporting",
    stars: 32,
    whatItDoes:
      "Token-optimized notation format for efficient LLM context packing. Compresses structured data into a dense format that maximizes information per token.",
    whyItsUseful:
      "LLM context windows are precious. TRU compresses JSON, YAML, and other structured data into a compact notation that conveys the same information in fewer tokens, letting you fit more context into each request.",
    implementationHighlights: [
      "Rust implementation for speed",
      "Lossless compression of structured data",
      "Multiple output formats (TOON, JSON, YAML)",
      "CLI and library modes",
    ],
    synergies: [
      {
        toolId: "s2p",
        description: "Compress source prompts for maximum context efficiency",
      },
      {
        toolId: "cass",
        description: "Compact session data for storage and search",
      },
    ],
    techStack: ["Rust", "Serde", "Token optimization"],
    keyFeatures: [
      "Token-optimized notation format",
      "Structured data compression",
      "Multiple format support",
      "Fast Rust implementation",
    ],
    useCases: [
      "Fitting more context into LLM requests",
      "Compressing structured data for agents",
      "Optimizing token usage in prompts",
    ],
  },
  {
    id: "rust_proxy",
    name: "Rust Proxy",
    shortName: "RustProxy",
    href: "https://github.com/Dicklesworthstone/rust_proxy",
    icon: "Network",
    color: "from-slate-500 to-zinc-600",
    category: "supporting",
    stars: 18,
    whatItDoes:
      "Transparent HTTP/HTTPS proxy for debugging and inspecting network traffic. Routes requests through a local proxy for analysis.",
    whyItsUseful:
      "When debugging API integrations or AI agent network calls, you need visibility into what's being sent and received. Rust Proxy provides transparent interception without modifying your code.",
    implementationHighlights: [
      "Rust implementation with async I/O",
      "HTTPS interception with certificate generation",
      "Request/response logging",
      "Minimal latency overhead",
    ],
    synergies: [
      {
        toolId: "rano",
        description: "Complementary network debugging - proxy vs observer",
      },
      {
        toolId: "cass",
        description: "Log network calls alongside session history",
      },
    ],
    techStack: ["Rust", "Tokio", "TLS", "HTTP proxy"],
    keyFeatures: [
      "Transparent HTTP/HTTPS proxy",
      "Request/response inspection",
      "Certificate generation",
      "Low latency overhead",
    ],
    useCases: [
      "Debugging API integrations",
      "Inspecting AI agent network calls",
      "Analyzing third-party API traffic",
    ],
  },
  {
    id: "rano",
    name: "RANO",
    shortName: "RANO",
    href: "https://github.com/Dicklesworthstone/rano",
    icon: "Radio",
    color: "from-cyan-500 to-blue-600",
    category: "supporting",
    stars: 25,
    whatItDoes:
      "Network observer for AI CLI tools that logs requests and responses without proxying. Passive monitoring of LLM API traffic.",
    whyItsUseful:
      "Understanding what your AI agents are actually sending to APIs helps with debugging, cost tracking, and optimization. RANO passively observes network traffic without adding proxy overhead.",
    implementationHighlights: [
      "Rust implementation for performance",
      "Passive network observation (no proxy)",
      "LLM-specific request/response parsing",
      "JSON output for analysis",
    ],
    synergies: [
      {
        toolId: "caut",
        description: "Network observations feed usage tracking",
      },
      {
        toolId: "cass",
        description: "Correlate network calls with session history",
      },
    ],
    techStack: ["Rust", "pcap", "Network monitoring"],
    keyFeatures: [
      "Passive network observation",
      "LLM API traffic parsing",
      "Request/response logging",
      "Zero proxy overhead",
    ],
    useCases: [
      "Debugging AI agent API calls",
      "Tracking LLM API usage",
      "Analyzing request patterns",
    ],
  },
  {
    id: "mdwb",
    name: "Markdown Web Browser",
    shortName: "MDWB",
    href: "https://github.com/Dicklesworthstone/markdown_web_browser",
    icon: "Globe",
    color: "from-emerald-500 to-teal-600",
    category: "supporting",
    stars: 42,
    whatItDoes:
      "Converts websites to clean Markdown for LLM consumption. Strips ads, navigation, and boilerplate to extract just the content.",
    whyItsUseful:
      "AI agents need web content in a format they can understand. MDWB fetches pages and converts them to clean Markdown, perfect for feeding into LLM context windows.",
    implementationHighlights: [
      "Rust implementation with async fetching",
      "Intelligent content extraction (reader mode)",
      "Configurable output formatting",
      "Handles JavaScript-rendered pages",
    ],
    synergies: [
      {
        toolId: "tru",
        description: "Compress fetched content for maximum token efficiency",
      },
      {
        toolId: "cm",
        description: "Store fetched content as memories",
      },
    ],
    techStack: ["Rust", "HTML parsing", "Markdown", "HTTP client"],
    keyFeatures: [
      "Website to Markdown conversion",
      "Content extraction (reader mode)",
      "JavaScript rendering support",
      "Clean output formatting",
    ],
    useCases: [
      "Feeding web content to AI agents",
      "Research automation",
      "Documentation scraping",
    ],
  },
  {
    id: "aadc",
    name: "ASCII Art Diagram Corrector",
    shortName: "AADC",
    href: "https://github.com/Dicklesworthstone/aadc",
    icon: "PenTool",
    color: "from-amber-500 to-yellow-600",
    category: "supporting",
    stars: 15,
    whatItDoes:
      "Fixes malformed ASCII art diagrams generated by AI. Corrects alignment, box characters, and connection lines.",
    whyItsUseful:
      "AI models often generate ASCII diagrams with alignment issues, broken lines, or inconsistent characters. AADC automatically detects and fixes these problems.",
    implementationHighlights: [
      "Rust implementation for speed",
      "Pattern detection for common diagram types",
      "Character alignment correction",
      "Box-drawing character normalization",
    ],
    synergies: [
      {
        toolId: "s2p",
        description: "Clean up diagrams in generated prompts",
      },
      {
        toolId: "cm",
        description: "Store corrected diagrams as memories",
      },
    ],
    techStack: ["Rust", "Pattern matching", "Text processing"],
    keyFeatures: [
      "ASCII diagram detection",
      "Alignment correction",
      "Box-drawing normalization",
      "Line connection repair",
    ],
    useCases: [
      "Fixing AI-generated diagrams",
      "Cleaning up documentation",
      "Preparing diagrams for version control",
    ],
  },
  {
    id: "caut",
    name: "Coding Agent Usage Tracker",
    shortName: "CAUT",
    href: "https://github.com/Dicklesworthstone/coding_agent_usage_tracker",
    icon: "BarChart",
    color: "from-rose-500 to-pink-600",
    category: "supporting",
    stars: 28,
    whatItDoes:
      "Tracks LLM provider usage across multiple coding agents. Monitors API calls, token consumption, and costs.",
    whyItsUseful:
      "When running multiple AI agents simultaneously, costs can spiral. CAUT provides visibility into which agents are using how many tokens and at what cost.",
    implementationHighlights: [
      "Rust implementation with SQLite storage",
      "Multi-provider support (Anthropic, OpenAI, Google)",
      "Real-time usage monitoring",
      "Cost estimation and alerts",
    ],
    synergies: [
      {
        toolId: "rano",
        description: "Network observations feed usage data",
      },
      {
        toolId: "ntm",
        description: "Track usage per NTM-managed session",
      },
      {
        toolId: "mail",
        description: "Usage alerts via Agent Mail",
      },
    ],
    techStack: ["Rust", "SQLite", "API monitoring"],
    keyFeatures: [
      "Multi-provider usage tracking",
      "Token consumption monitoring",
      "Cost estimation",
      "Usage alerts and reporting",
    ],
    useCases: [
      "Tracking AI agent costs",
      "Budget monitoring for teams",
      "Identifying expensive operations",
    ],
  },
];

// Merge basic metadata from manifest (source of truth for names, shortNames,
// hrefs, stars, techStack, keyFeatures, useCases). Rich UI data (whatItDoes,
// whyItsUseful, implementationHighlights, synergies, category, color, icon)
// stays hand-maintained.
export const tldrFlywheelTools: TldrFlywheelTool[] = _tldrFlywheelTools.map(
  (tool) => {
    const gen = getManifestTldr(tool.id);
    if (!gen) return tool;
    return {
      ...tool,
      name: gen.displayName,
      shortName: gen.shortName,
      href: gen.href ?? tool.href,
      stars: gen.stars ?? tool.stars,
      techStack: gen.techStack.length > 0 ? gen.techStack : tool.techStack,
      keyFeatures: gen.features.length > 0 ? gen.features : tool.keyFeatures,
      useCases: gen.useCases.length > 0 ? gen.useCases : tool.useCases,
    };
  },
);

export const tldrPageData = {
  hero: {
    title: "The Agentic Coding Flywheel",
    subtitle: "TL;DR Edition",
    description:
<<<<<<< Updated upstream
      "15 core tools and 7 supporting utilities that transform multi-agent AI coding workflows. Each tool makes the others more powerful - the more you use it, the faster it spins. While others argue about agentic coding, we're just over here building as fast as we can.",
    stats: [
      { label: "Ecosystem Tools", value: "22" },
      "16 core tools and 13 supporting utilities that transform multi-agent AI coding workflows. Each tool makes the others more powerful - the more you use it, the faster it spins. While others argue about agentic coding, we're just over here building as fast as we can.",
    stats: [
=======
      "16 core tools and 13 supporting utilities that transform multi-agent AI coding workflows. Each tool makes the others more powerful - the more you use it, the faster it spins. While others argue about agentic coding, we're just over here building as fast as we can.",
    stats: [
>>>>>>> Stashed changes
      { label: "Ecosystem Tools", value: "29" },
      { label: "GitHub Stars", value: "3,600+" },
      { label: "Languages", value: "5" },
    ],
  },
  coreDescription:
    "The core flywheel tools form the backbone: Agent Mail for coordination, BV for graph-based prioritization, CASS for instant session search, CM for persistent memory, UBS for bug detection, MS for skill management with MCP integration, plus session management, safety guards, and automated setup.",
  supportingDescription:
    "Supporting tools extend the ecosystem: GIIL for remote image debugging, SRPS for system responsiveness under heavy load, XF for searching your X archive, S2P for crafting prompts from source code, APR for spec refinement, JFP for curated prompt discovery, PT for process triage, TRU for token-optimized notation, RANO for network observation, MDWB for website-to-Markdown conversion, AADC for ASCII diagram correction, and CAUT for usage tracking.",
  flywheelExplanation: {
    title: "Why a Flywheel?",
    paragraphs: [
      "A flywheel stores rotational energy - the more you spin it, the easier each push becomes. These tools work the same way. The more you use them, the more valuable the system becomes.",
      "Every agent session generates searchable history (CASS). Past solutions become retrievable memory (CM). Dependencies surface bottlenecks (BV). Agents coordinate without conflicts (Mail). Each piece feeds the others.",
      "The result: I shipped 20,000+ lines of production Go code in a single day with BV. The flywheel keeps spinning faster - my GitHub commits accelerate each week because each tool amplifies the others.",
    ],
  },
};
