/**
 * Content data for the TL;DR page showcasing all flywheel tools with
 * comprehensive descriptions, implementation highlights, and synergies.
 */

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

export const tldrFlywheelTools: TldrFlywheelTool[] = [
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
      "A mail-like coordination layer for multi-agent workflows. Agents send messages, read threads, and reserve files asynchronously via MCP tools - like Gmail for AI coding agents.",
    whyItsUseful:
      "Critical for multi-agent setups. When 5+ Claude Code instances work the same codebase, they need to coordinate who's editing what. Agent Mail prevents merge conflicts and builds an audit trail of all agent decisions.",
    implementationHighlights: [
      "FastMCP server implementation for universal agent compatibility",
      "SQLite-backed storage for complete audit trails",
      "Advisory file locking to prevent edit conflicts",
      "GitHub-flavored Markdown support in messages",
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
        description: "Launched agents coordinate via mail threads",
      },
    ],
    techStack: ["Python 3.14+", "FastMCP", "FastAPI", "SQLite"],
    keyFeatures: [
      "Threaded messaging between AI agents",
      "Advisory file reservations",
      "SQLite-backed persistent storage",
      "MCP integration for any compatible agent",
    ],
    useCases: [
      "Coordinating file ownership across parallel agents",
      "Passing context between session restarts",
      "Building audit trails of agent decisions",
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
    ],
    techStack: ["Go", "Bubble Tea", "Lip Gloss", "Graph algorithms"],
    keyFeatures: [
      "PageRank-based issue prioritization",
      "Critical path analysis",
      "Robot mode for AI agent integration",
      "Interactive TUI with vim keybindings",
    ],
    useCases: [
      "Identifying which task unblocks the most other work",
      "Visualizing complex dependency graphs",
      "Generating execution plans for AI agents",
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
      "Blazing-fast search across all your past AI coding agent sessions. Indexes conversations from Claude Code, Codex, Cursor, Gemini, ChatGPT and more with sub-millisecond query times.",
    whyItsUseful:
      "You've solved this problem before - but which session? CASS lets you search 'how did I fix that React hydration error' and instantly find the exact conversation. Also supports semantic search and multi-machine sync via SSH.",
    implementationHighlights: [
      "Rust + Tantivy for sub-millisecond full-text search",
      "Hybrid semantic + keyword search with RRF fusion",
      "Robot mode (--robot) for AI agent integration",
      "Multi-machine sync via SSH",
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
    techStack: ["Rust", "Tantivy", "Ratatui", "JSONL parsing"],
    keyFeatures: [
      "Unified search across all agent types",
      "Sub-second search over millions of messages",
      "Robot mode for AI agent integration",
      "TUI for interactive exploration",
    ],
    useCases: [
      "Finding how a similar bug was fixed before",
      "Retrieving context from past project work",
      "Building on previous agent conversations",
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
      "One-command bootstrap that transforms a fresh Ubuntu VPS into a fully-configured agentic coding environment with all flywheel tools installed.",
    whyItsUseful:
      "Setting up a new development environment takes hours. ACFS does it in 30 minutes, installing 30+ tools, three AI agents, and all the flywheel tooling automatically.",
    implementationHighlights: [
      "Single curl | bash installation",
      "Idempotent (safe to re-run)",
      "Manifest-driven architecture",
      "SHA256 checksum verification for security",
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
      "30-minute zero-to-hero setup",
      "Installs Claude Code, Codex, Gemini CLI",
      "All flywheel tools pre-configured",
      "Step-by-step wizard for beginners",
    ],
    useCases: [
      "Setting up new development VPS",
      "Onboarding team members",
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
      "Custom pattern-based bug scanner with 1,000+ detection rules across multiple languages. Catches common bugs, security issues, and code smells before they become problems.",
    whyItsUseful:
      "Instead of managing dozens of separate linters, UBS provides comprehensive bug detection in a single tool. Its pattern-based approach catches issues that traditional static analyzers miss.",
    implementationHighlights: [
      "1,000+ custom detection patterns across languages",
      "Pattern-based scanning with extensible rule definitions",
      "Consistent JSON output across all languages",
      "Exit codes designed for CI/CD integration",
    ],
    synergies: [
      {
        toolId: "bv",
        description: "Bug findings become blocking issues in Beads",
      },
      {
        toolId: "slb",
        description: "Pre-flight scans before risky operations",
      },
    ],
    techStack: ["Bash", "Pattern matching", "JSON output"],
    keyFeatures: [
      "1,000+ built-in detection patterns",
      "Consistent JSON output format",
      "Multi-language support",
      "Perfect for pre-commit hooks",
    ],
    useCases: [
      "Pre-commit validation across polyglot repos",
      "CI/CD pipeline integration",
      "Catching AI-generated code errors",
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
      "Intercepts dangerous shell commands (rm -rf, git reset --hard, etc.) before execution. Requires confirmation for destructive operations.",
    whyItsUseful:
      "AI agents can and will run 'rm -rf /' if they think it solves your problem. DCG is the safety net that catches catastrophic commands before they execute.",
    implementationHighlights: [
      "Rust implementation with SIMD-accelerated pattern matching",
      "Sub-microsecond command analysis overhead",
      "Configurable risk levels and bypass rules",
      "Logging of all intercepted commands",
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
    techStack: ["Rust", "SIMD", "Shell integration"],
    keyFeatures: [
      "Intercepts rm -rf, git reset --hard, etc.",
      "SIMD-accelerated pattern matching",
      "Configurable allowlists",
      "Command audit logging",
    ],
    useCases: [
      "Protecting against accidental data loss",
      "Auditing dangerous commands from agents",
      "Training wheels for new AI agent setups",
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
    stars: 67,
    whatItDoes:
      "Keeps dozens (or hundreds) of Git repositories in sync with a single command. Clones missing repos, pulls updates, detects conflicts.",
    whyItsUseful:
      "Managing many repos across machines is painful. 'ru sync' handles everything: cloning what's missing, pulling what's stale, and reporting conflicts with resolution commands.",
    implementationHighlights: [
      "Pure Bash with git plumbing (no string parsing)",
      "Parallel sync with configurable worker count",
      "AI-assisted code review integration",
      "Meaningful exit codes for CI/CD",
    ],
    synergies: [
      {
        toolId: "ubs",
        description: "Run bug scans across all synced repos",
      },
      {
        toolId: "ntm",
        description: "NTM integration for agent-driven sweeps",
      },
    ],
    techStack: ["Bash 4.0+", "Git plumbing", "GitHub CLI"],
    keyFeatures: [
      "One-command multi-repo sync",
      "Parallel operations",
      "Conflict detection with resolution hints",
      "AI code review integration",
    ],
    useCases: [
      "Keeping development machines in sync",
      "CI/CD repo management",
      "Automated codebase maintenance",
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
      "A memory system built on top of CASS. Implements three-layer cognitive architecture: Episodic (experiences), Working (active context), and Procedural (skills and lessons learned).",
    whyItsUseful:
      "Without persistent memory, every agent session starts from scratch. CM lets agents learn from past sessions - remembering what worked, what failed, and extracting reusable playbook rules for future work.",
    implementationHighlights: [
      "Three-layer cognitive architecture (Episodic, Working, Procedural)",
      "MCP tools for cross-session context persistence",
      "Memory consolidation and summarization",
      "Hierarchical memory organization",
    ],
    synergies: [
      {
        toolId: "mail",
        description:
          "Conversation summaries from mail threads stored as memories",
      },
      {
        toolId: "cass",
        description: "Semantic search over stored memories",
      },
      {
        toolId: "bv",
        description: "Task patterns and solutions remembered",
      },
    ],
    techStack: ["TypeScript", "Bun", "MCP Protocol", "SQLite"],
    keyFeatures: [
      "Three memory layers: episodic, working, procedural",
      "MCP integration for any compatible agent",
      "Automatic memory consolidation",
      "Cross-session context persistence",
    ],
    useCases: [
      "Remembering project conventions across sessions",
      "Learning from past debugging sessions",
      "Building institutional knowledge over time",
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
      "Manages named tmux sessions with project-specific persistence. Creates organized workspaces for multi-agent development with typed panes.",
    whyItsUseful:
      "When running multiple AI coding agents simultaneously, keeping track of which agent is working on what becomes impossible without organization. NTM solves this by providing persistent, named sessions that survive reboots.",
    implementationHighlights: [
      "Go implementation with Bubble Tea TUI framework",
      "Project-aware persistence using XDG conventions",
      "Support for agent type classification (claude, codex, cursor, etc.)",
      "Real-time dashboard showing all active agent panes",
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
          "Agents in different NTM panes communicate via Agent Mail threads",
      },
      {
        toolId: "cass",
        description: "Session history from all NTM panes is indexed for search",
      },
    ],
    techStack: ["Go 1.25+", "Bubble Tea", "tmux 3.0+"],
    keyFeatures: [
      "Spawn named agent panes with type classification",
      "Broadcast prompts to specific agent types",
      "Session persistence across reboots",
      "Dashboard view of all active agents",
    ],
    useCases: [
      "Running 5+ Claude Code agents on different features simultaneously",
      "Organizing development environments by project",
      "Managing long-running agent sessions for complex refactors",
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
      "Two-person rule CLI for approving dangerous shell commands. Requires a second human or AI reviewer to approve risky operations before execution.",
    whyItsUseful:
      "AI agents can accidentally run destructive commands. SLB implements a 'two-person rule' where dangerous commands require explicit approval from another party before executing, preventing catastrophic mistakes.",
    implementationHighlights: [
      "Go implementation with Bubble Tea TUI",
      "SQLite-backed persistent command queue",
      "Configurable risk detection patterns",
      "Real-time approval/rejection notifications",
    ],
    synergies: [
      {
        toolId: "ntm",
        description: "Protects NTM-managed sessions from dangerous commands",
      },
      {
        toolId: "dcg",
        description: "Works alongside DCG for layered command safety",
      },
      {
        toolId: "mail",
        description: "Approval requests can be sent via Agent Mail",
      },
    ],
    techStack: ["Go", "Bubble Tea", "SQLite"],
    keyFeatures: [
      "Two-person rule enforcement",
      "Command queue with approval workflow",
      "Pattern-based risk detection",
      "SQLite persistence",
    ],
    useCases: [
      "Requiring approval for rm -rf and git reset operations",
      "Adding safety gates to autonomous agent workflows",
      "Audit trail of dangerous command approvals",
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
      "Downloads images from iCloud public share links for use in remote debugging sessions. Converts iCloud URLs to direct image downloads.",
    whyItsUseful:
      "When debugging remotely via SSH, you can't easily share screenshots. GIIL lets you upload to iCloud, share the link, and the remote machine downloads the image directly for AI agents to analyze.",
    implementationHighlights: [
      "iCloud public share URL parsing",
      "Direct image download without browser",
      "Automatic file naming from URL metadata",
      "Works over SSH without GUI",
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
    techStack: ["Bash", "curl", "iCloud API"],
    keyFeatures: [
      "iCloud share link support",
      "CLI-based image download",
      "No browser required",
      "Works over SSH",
    ],
    useCases: [
      "Sharing screenshots for remote debugging",
      "Getting images to headless servers",
      "AI agent image analysis workflows",
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
      "Ultra-fast search over X/Twitter data archives. Uses hybrid BM25 + semantic search with Reciprocal Rank Fusion.",
    whyItsUseful:
      "Your X archive is a goldmine of bookmarks, threads, and ideas, but Twitter's search is terrible. XF makes your archive instantly searchable with both keyword and semantic matching.",
    implementationHighlights: [
      "Rust implementation for maximum performance",
      "Hybrid BM25 + semantic search with RRF fusion",
      "Zero-dependency hash embedder (no Python/API calls)",
      "Privacy-first, fully local processing",
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
    techStack: ["Rust", "Tantivy", "Hash embeddings", "RRF"],
    keyFeatures: [
      "Sub-second search over large archives",
      "Semantic + keyword hybrid search",
      "No external API dependencies",
      "Privacy-preserving local processing",
    ],
    useCases: [
      "Finding that thread you bookmarked months ago",
      "Researching past discussions on a topic",
      "Building on ideas from your tweet history",
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
      "Terminal UI for combining source code files into LLM-ready prompts. Select files, preview output, copy to clipboard with token counting.",
    whyItsUseful:
      "Crafting prompts with code context is tedious. s2p lets you interactively select files, see the combined output, and track token count, all in a beautiful TUI.",
    implementationHighlights: [
      "Bun single-binary distribution",
      "React/Ink terminal UI framework",
      "tiktoken-accurate token counting",
      "Gitignore-aware file filtering",
    ],
    synergies: [
      {
        toolId: "cass",
        description: "Generated prompts can be searched later",
      },
      {
        toolId: "cm",
        description: "Effective prompts stored as memories",
      },
    ],
    techStack: ["TypeScript", "Bun", "React", "Ink", "tiktoken"],
    keyFeatures: [
      "Interactive file selection",
      "Real-time token counting",
      "Clipboard integration",
      "Gitignore-aware filtering",
    ],
    useCases: [
      "Preparing code context for Claude/GPT",
      "Creating reproducible prompt templates",
      "Managing context window budget",
    ],
  },
];

export const tldrPageData = {
  hero: {
    title: "The Agentic Coding Flywheel",
    subtitle: "TL;DR Edition",
    description:
      "10 core tools and 3 supporting utilities that transform multi-agent AI coding workflows. Each tool makes the others more powerful - the more you use it, the faster it spins. While others argue about agentic coding, we're just over here building as fast as we can.",
    stats: [
      { label: "Ecosystem Tools", value: "13" },
      { label: "GitHub Stars", value: "3,600+" },
      { label: "Languages", value: "5" },
    ],
  },
  coreDescription:
    "The core flywheel tools form the backbone: Agent Mail for coordination, BV for graph-based prioritization, CASS for instant session search, CM for persistent memory, UBS for bug detection, plus session management, safety guards, and automated setup.",
  supportingDescription:
    "Supporting tools extend the ecosystem: GIIL for remote image debugging, XF for searching your X archive, and S2P for crafting prompts from source code.",
  flywheelExplanation: {
    title: "Why a Flywheel?",
    paragraphs: [
      "A flywheel stores rotational energy - the more you spin it, the easier each push becomes. These tools work the same way. The more you use them, the more valuable the system becomes.",
      "Every agent session generates searchable history (CASS). Past solutions become retrievable memory (CM). Dependencies surface bottlenecks (BV). Agents coordinate without conflicts (Mail). Each piece feeds the others.",
      "The result: I shipped 20,000+ lines of production Go code in a single day with BV. The flywheel keeps spinning faster - my GitHub commits accelerate each week because each tool amplifies the others.",
    ],
  },
};
