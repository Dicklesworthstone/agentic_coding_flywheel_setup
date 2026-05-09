// ============================================================
// AUTO-GENERATED FROM acfs.manifest.yaml — DO NOT EDIT
// Regenerate: bun run generate (from packages/manifest)
// ============================================================

export interface ManifestModuleMetadata {
  id: string;
  description: string;
  category: string;
  phase: number;
  dependencies: string[];
  tags: string[];
  enabledByDefault: boolean;
  optional: boolean;
}

export type ManifestSelectionProfileId = "full" | "safe" | "vibe" | "minimal" | "agents-only" | "cloud-only" | "stack-only";

export interface ManifestSelectionProfile {
  id: ManifestSelectionProfileId;
  label: string;
  mode?: "safe" | "vibe";
  onlyModules: string[];
  onlyPhases: string[];
}

export interface ManifestProvenanceMetadata {
  acfsVersion: string;
  manifestSha256: string;
  checksumsYamlSha256: string;
}

export const manifestProvenance = {
  acfsVersion: "0.7.0",
  manifestSha256: "72fd1123034f4cc4dfd71d9a362e9cbf423f8aa6c37460a60352816cb7557b91",
  checksumsYamlSha256: "35cc192aba416a2e7f14214b3c50c53901f9d8c087e5cf061ddfd944ce8bb672",
} as const satisfies ManifestProvenanceMetadata;

export const manifestModules: ManifestModuleMetadata[] = [
  {
    id: "base.system",
    description: "Base packages + sane defaults",
    category: "base",
    phase: 1,
    dependencies: [],
    tags: [
      "critical",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "users.ubuntu",
    description: "Ensure target user + passwordless sudo + ssh keys",
    category: "users",
    phase: 2,
    dependencies: [],
    tags: [
      "orchestration",
      "critical",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "base.filesystem",
    description: "Create workspace and ACFS directories",
    category: "filesystem",
    phase: 3,
    dependencies: [
      "users.ubuntu",
    ],
    tags: [
      "critical",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "shell.zsh",
    description: "Zsh shell package",
    category: "shell",
    phase: 4,
    dependencies: [
      "base.system",
      "base.filesystem",
    ],
    tags: [
      "critical",
      "shell-ux",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "shell.omz",
    description: "Oh My Zsh + Powerlevel10k + plugins + ACFS config",
    category: "shell",
    phase: 4,
    dependencies: [
      "shell.zsh",
    ],
    tags: [
      "critical",
      "shell-ux",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "cli.modern",
    description: "Modern CLI tools referenced by the zshrc intent",
    category: "cli",
    phase: 5,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "cli-modern",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "tools.lazygit",
    description: "Lazygit (apt or binary fallback)",
    category: "tools",
    phase: 5,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "cli-modern",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "tools.lazydocker",
    description: "Lazydocker (binary install)",
    category: "tools",
    phase: 5,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "cli-modern",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "network.tailscale",
    description: "Zero-config mesh VPN for secure remote VPS access",
    category: "network",
    phase: 5,
    dependencies: [
      "base.system",
    ],
    tags: [
      "networking",
      "vpn",
      "security",
      "google-sso",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "network.ssh_keepalive",
    description: "Configure SSH server keepalive to prevent VPN/NAT disconnects",
    category: "network",
    phase: 5,
    dependencies: [
      "base.system",
    ],
    tags: [
      "networking",
      "remote-dev",
      "ssh",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "lang.bun",
    description: "Bun runtime for JS tooling and global CLIs",
    category: "lang",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "critical",
      "runtime",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "lang.uv",
    description: "uv Python tooling (fast venvs)",
    category: "lang",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "critical",
      "runtime",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "lang.rust",
    description: "Rust nightly + cargo",
    category: "lang",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "critical",
      "runtime",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "lang.go",
    description: "Go toolchain",
    category: "lang",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "critical",
      "runtime",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "lang.nvm",
    description: "nvm + latest Node.js",
    category: "lang",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "critical",
      "runtime",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "tools.atuin",
    description: "Atuin shell history (Ctrl-R superpowers)",
    category: "tools",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "shell-ux",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "tools.zoxide",
    description: "Zoxide (better cd)",
    category: "tools",
    phase: 6,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "shell-ux",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "tools.ast_grep",
    description: "ast-grep (used by UBS for syntax-aware scanning)",
    category: "tools",
    phase: 6,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "recommended",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "agents.claude",
    description: "Claude Code",
    category: "agents",
    phase: 7,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "agent",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "agents.codex",
    description: "OpenAI Codex CLI",
    category: "agents",
    phase: 7,
    dependencies: [
      "lang.bun",
    ],
    tags: [
      "recommended",
      "agent",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "agents.gemini",
    description: "Google Gemini CLI",
    category: "agents",
    phase: 7,
    dependencies: [
      "lang.bun",
      "lang.nvm",
    ],
    tags: [
      "recommended",
      "agent",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "agents.opencode",
    description: "OpenCode (multi-provider agent harness)",
    category: "agents",
    phase: 7,
    dependencies: [
      "base.system",
    ],
    tags: [
      "optional",
      "agent",
    ],
    enabledByDefault: false,
    optional: true,
  },
  {
    id: "tools.vault",
    description: "HashiCorp Vault CLI",
    category: "tools",
    phase: 8,
    dependencies: [
      "base.system",
    ],
    tags: [
      "optional",
      "cloud",
    ],
    enabledByDefault: false,
    optional: true,
  },
  {
    id: "db.postgres18",
    description: "PostgreSQL 18",
    category: "db",
    phase: 8,
    dependencies: [
      "base.system",
    ],
    tags: [
      "optional",
      "database",
    ],
    enabledByDefault: false,
    optional: true,
  },
  {
    id: "cloud.wrangler",
    description: "Cloudflare Wrangler CLI",
    category: "cloud",
    phase: 8,
    dependencies: [
      "lang.bun",
    ],
    tags: [
      "optional",
      "cloud",
    ],
    enabledByDefault: false,
    optional: true,
  },
  {
    id: "cloud.supabase",
    description: "Supabase CLI",
    category: "cloud",
    phase: 8,
    dependencies: [
      "base.system",
      "base.filesystem",
    ],
    tags: [
      "optional",
      "cloud",
    ],
    enabledByDefault: false,
    optional: true,
  },
  {
    id: "cloud.vercel",
    description: "Vercel CLI",
    category: "cloud",
    phase: 8,
    dependencies: [
      "lang.bun",
    ],
    tags: [
      "optional",
      "cloud",
    ],
    enabledByDefault: false,
    optional: true,
  },
  {
    id: "stack.ntm",
    description: "Named tmux manager (agent cockpit)",
    category: "stack",
    phase: 9,
    dependencies: [
      "cli.modern",
    ],
    tags: [
      "recommended",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "stack.mcp_agent_mail",
    description: "Like gmail for coding agents; MCP HTTP server + token; installs beads tools",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.bun",
      "lang.uv",
    ],
    tags: [
      "recommended",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "stack.meta_skill",
    description: "Local-first knowledge management with hybrid semantic search (ms)",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.rust",
      "lang.uv",
    ],
    tags: [
      "recommended",
      "agent-skills",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "stack.automated_plan_reviser",
    description: "Automated iterative spec refinement with extended AI reasoning (apr)",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "recommended",
      "agent-tools",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.jeffreysprompts",
    description: "Curated battle-tested prompts for AI agents - browse and install as skills (jfp)",
    category: "stack",
    phase: 9,
    dependencies: [],
    tags: [
      "recommended",
      "agent-skills",
      "prompts",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.process_triage",
    description: "Find and terminate stuck/zombie processes with intelligent scoring (pt)",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "recommended",
      "system-tools",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.ultimate_bug_scanner",
    description: "UBS bug scanning (easy-mode)",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.bun",
      "lang.uv",
      "tools.ast_grep",
    ],
    tags: [
      "recommended",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "stack.beads_rust",
    description: "beads_rust (br) - Rust issue tracker with graph-aware dependencies",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "recommended",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "stack.beads_viewer",
    description: "bv TUI for Beads tasks",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.go",
      "stack.beads_rust",
    ],
    tags: [
      "recommended",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "stack.cass",
    description: "Unified search across agent session history",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.rust",
      "lang.uv",
    ],
    tags: [
      "recommended",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "stack.cm",
    description: "Procedural memory for agents (cass-memory)",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.rust",
      "lang.uv",
    ],
    tags: [
      "recommended",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "stack.caam",
    description: "Instant auth switching for agent CLIs",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.bun",
    ],
    tags: [
      "recommended",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "stack.slb",
    description: "Two-person rule for dangerous commands (optional guardrails)",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.go",
    ],
    tags: [
      "optional",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.dcg",
    description: "Destructive Command Guard - Claude Code hook blocking dangerous git/fs commands",
    category: "stack",
    phase: 9,
    dependencies: [
      "agents.claude",
    ],
    tags: [
      "recommended",
      "safety",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "stack.ru",
    description: "Repo Updater - multi-repo sync + AI-driven commit automation",
    category: "stack",
    phase: 9,
    dependencies: [
      "cli.modern",
      "stack.ntm",
    ],
    tags: [
      "recommended",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "stack.brenner_bot",
    description: "Brenner Bot - research session manager with hypothesis tracking",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.rust",
      "stack.cass",
    ],
    tags: [
      "recommended",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.rch",
    description: "Remote Compilation Helper - transparent build offloading for AI coding agents",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "recommended",
      "performance",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.wezterm_automata",
    description: "WezTerm Automata (wa) - terminal automation and orchestration for AI agents",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "recommended",
      "automation",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.srps",
    description: "System Resource Protection Script - ananicy-cpp rules + TUI monitor for responsive dev workstations",
    category: "stack",
    phase: 9,
    dependencies: [
      "base.system",
      "lang.go",
    ],
    tags: [
      "recommended",
      "system-health",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.frankensearch",
    description: "Two-tier hybrid local search — lexical (BM25) + semantic retrieval with progressive delivery (fsfs)",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "recommended",
      "search",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.storage_ballast_helper",
    description: "Cross-platform disk-pressure defense for AI coding workloads (sbh)",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "recommended",
      "system-tools",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.cross_agent_session_resumer",
    description: "Cross-provider AI coding session resumption — convert and resume sessions across providers (casr)",
    category: "stack",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "recommended",
      "agent-tools",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.doodlestein_self_releaser",
    description: "Fallback release infrastructure — local builds via act when GitHub Actions is throttled (dsr)",
    category: "stack",
    phase: 9,
    dependencies: [
      "cli.modern",
    ],
    tags: [
      "recommended",
      "release",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.agent_settings_backup",
    description: "Smart backup tool for AI coding agent configuration folders (asb)",
    category: "stack",
    phase: 9,
    dependencies: [
      "base.system",
    ],
    tags: [
      "recommended",
      "backup",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "stack.pcr",
    description: "Post-compaction reminder hook for Claude Code that forces an AGENTS.md re-read",
    category: "stack",
    phase: 9,
    dependencies: [
      "agents.claude",
    ],
    tags: [
      "recommended",
      "safety",
      "hooks",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "utils.giil",
    description: "Get Image from Internet Link - download cloud images for visual debugging",
    category: "tools",
    phase: 9,
    dependencies: [
      "base.system",
    ],
    tags: [
      "utility",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "utils.csctf",
    description: "Chat Shared Conversation to File - convert AI share links to Markdown/HTML",
    category: "tools",
    phase: 9,
    dependencies: [
      "base.system",
    ],
    tags: [
      "utility",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "utils.xf",
    description: "xf - Ultra-fast X/Twitter archive search with Tantivy",
    category: "tools",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "utility",
      "search",
    ],
    enabledByDefault: false,
    optional: true,
  },
  {
    id: "utils.toon_rust",
    description: "toon_rust (tru) - Token-optimized notation format for LLM context efficiency",
    category: "tools",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "utility",
      "llm",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "utils.rano",
    description: "rano - Network observer for AI CLIs with request/response logging",
    category: "tools",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "utility",
      "network",
      "debug",
    ],
    enabledByDefault: false,
    optional: true,
  },
  {
    id: "utils.mdwb",
    description: "markdown_web_browser (mdwb) - Convert websites to Markdown for LLM consumption",
    category: "tools",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "utility",
      "web",
      "llm",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "utils.s2p",
    description: "source_to_prompt_tui (s2p) - Code to LLM prompt generator with TUI",
    category: "tools",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "utility",
      "llm",
      "tui",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "utils.rust_proxy",
    description: "rust_proxy - Transparent proxy routing for debugging network traffic",
    category: "tools",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "utility",
      "network",
      "debug",
    ],
    enabledByDefault: false,
    optional: true,
  },
  {
    id: "utils.aadc",
    description: "aadc - ASCII diagram corrector for fixing malformed ASCII art",
    category: "tools",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "utility",
      "ascii",
    ],
    enabledByDefault: false,
    optional: true,
  },
  {
    id: "utils.caut",
    description: "coding_agent_usage_tracker (caut) - LLM provider usage tracker",
    category: "tools",
    phase: 9,
    dependencies: [
      "lang.rust",
    ],
    tags: [
      "utility",
      "tracking",
    ],
    enabledByDefault: false,
    optional: true,
  },
  {
    id: "acfs.workspace",
    description: "Agent workspace with tmux session and project folder",
    category: "acfs",
    phase: 10,
    dependencies: [
      "agents.claude",
      "agents.codex",
      "agents.gemini",
      "cli.modern",
    ],
    tags: [
      "workspace",
      "agents",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "acfs.onboard",
    description: "Onboarding TUI tutorial",
    category: "acfs",
    phase: 10,
    dependencies: [],
    tags: [
      "orchestration",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "acfs.update",
    description: "ACFS update command wrapper",
    category: "acfs",
    phase: 10,
    dependencies: [],
    tags: [
      "orchestration",
    ],
    enabledByDefault: true,
    optional: false,
  },
  {
    id: "acfs.nightly",
    description: "Nightly auto-update timer (systemd)",
    category: "acfs",
    phase: 10,
    dependencies: [
      "acfs.update",
    ],
    tags: [
      "orchestration",
      "maintenance",
    ],
    enabledByDefault: true,
    optional: true,
  },
  {
    id: "acfs.doctor",
    description: "ACFS doctor command for health checks",
    category: "acfs",
    phase: 10,
    dependencies: [],
    tags: [
      "orchestration",
    ],
    enabledByDefault: true,
    optional: false,
  },
];

export const manifestSelectionProfiles: ManifestSelectionProfile[] = [
  {
    id: "full",
    label: "Full",
    onlyModules: [],
    onlyPhases: [],
  },
  {
    id: "safe",
    label: "Safe",
    mode: "safe",
    onlyModules: [],
    onlyPhases: [],
  },
  {
    id: "vibe",
    label: "Vibe",
    mode: "vibe",
    onlyModules: [],
    onlyPhases: [],
  },
  {
    id: "minimal",
    label: "Minimal",
    onlyModules: [
      "shell.omz",
      "cli.modern",
      "lang.bun",
      "lang.uv",
      "agents.claude",
      "agents.codex",
      "agents.gemini",
      "stack.ntm",
      "stack.mcp_agent_mail",
      "stack.ultimate_bug_scanner",
      "stack.beads_rust",
      "stack.beads_viewer",
      "stack.cass",
      "stack.cm",
      "stack.dcg",
      "stack.ru",
      "stack.rch",
      "acfs.workspace",
      "acfs.onboard",
      "acfs.update",
      "acfs.doctor",
    ],
    onlyPhases: [],
  },
  {
    id: "agents-only",
    label: "Agents only",
    onlyModules: [],
    onlyPhases: [
      "agents",
    ],
  },
  {
    id: "cloud-only",
    label: "Cloud only",
    onlyModules: [
      "cloud.wrangler",
      "cloud.supabase",
      "cloud.vercel",
    ],
    onlyPhases: [],
  },
  {
    id: "stack-only",
    label: "Stack only",
    onlyModules: [],
    onlyPhases: [
      "stack",
    ],
  },
];
