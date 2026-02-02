import { manifestCommands } from './generated/manifest-web-index';

export type CommandCategory =
  | "agents"
  | "search"
  | "git"
  | "system"
  | "stack"
  | "languages"
  | "cloud";

export interface CommandRef {
  name: string;
  fullName: string;
  description: string;
  category: CommandCategory;
  example: string;
  aliases?: string[];
  docsUrl?: string;
}

export const COMMAND_CATEGORIES: Array<{
  id: CommandCategory;
  label: string;
  description: string;
}> = [
  {
    id: "agents",
    label: "Agents",
    description: "AI coding assistants installed by ACFS",
  },
  {
    id: "search",
    label: "Search",
    description: "Find files and patterns fast",
  },
  {
    id: "git",
    label: "Git",
    description: "Version control helpers",
  },
  {
    id: "system",
    label: "System",
    description: "Shell, terminal, and quality-of-life tools",
  },
  {
    id: "stack",
    label: "Stack",
    description: "Dicklesworthstone tools for agent workflows",
  },
  {
    id: "languages",
    label: "Languages",
    description: "Language runtimes and package managers",
  },
  {
    id: "cloud",
    label: "Cloud",
    description: "Cloud and database CLIs",
  },
];

export const COMMANDS: CommandRef[] = [
  {
    name: "cc",
    fullName: "Claude Code",
    description: "Anthropic coding agent (alias for claude).",
    category: "agents",
    example: 'cc "fix the auth bug in auth.ts"',
    aliases: ["claude"],
    docsUrl: "/learn/agent-commands",
  },
  {
    name: "cod",
    fullName: "Codex CLI",
    description: "OpenAI coding agent (alias for codex).",
    category: "agents",
    example: 'cod "add tests for utils.ts"',
    aliases: ["codex"],
    docsUrl: "/learn/agent-commands",
  },
  {
    name: "gmi",
    fullName: "Gemini CLI",
    description: "Google coding agent (alias for gemini).",
    category: "agents",
    example: 'gmi "review this PR"',
    aliases: ["gemini"],
    docsUrl: "/learn/agent-commands",
  },
  {
    name: "rg",
    fullName: "ripgrep",
    description: "Ultra-fast code search.",
    category: "search",
    example: 'rg "TODO" ./apps',
    aliases: ["grep"],
  },
  {
    name: "fd",
    fullName: "fd-find",
    description: "Fast file finder.",
    category: "search",
    example: 'fd "*.ts"',
    aliases: ["find", "fdfind"],
  },
  {
    name: "fzf",
    fullName: "Fuzzy Finder",
    description: "Interactive fuzzy search for files and commands.",
    category: "search",
    example: "fzf",
  },
  {
    name: "sg",
    fullName: "ast-grep",
    description: "Structural code search and replace.",
    category: "search",
    example: 'sg -p "foo($A)" -r "bar($A)"',
  },
  {
    name: "git",
    fullName: "Git",
    description: "Version control system.",
    category: "git",
    example: "git status",
  },
  {
    name: "lazygit",
    fullName: "LazyGit",
    description: "Terminal UI for Git.",
    category: "git",
    example: "lazygit",
    aliases: ["lg"],
  },
  {
    name: "ntm",
    fullName: "Named Tmux Manager",
    description: "Session management for agents and workflows.",
    category: "system",
    example: "ntm new acfs",
  },
  {
    name: "tmux",
    fullName: "tmux",
    description: "Terminal multiplexer.",
    category: "system",
    example: "tmux new -s work",
  },
  {
    name: "lsd",
    fullName: "LSDeluxe",
    description: "Modern ls replacement (eza fallback).",
    category: "system",
    example: "lsd -la",
    aliases: ["eza", "ls"],
  },
  {
    name: "bat",
    fullName: "bat",
    description: "Cat with syntax highlighting.",
    category: "system",
    example: "bat README.md",
    aliases: ["cat", "batcat"],
  },
  {
    name: "zoxide",
    fullName: "zoxide",
    description: "Smart cd replacement.",
    category: "system",
    example: "z project",
  },
  {
    name: "atuin",
    fullName: "atuin",
    description: "Shell history sync with powerful search.",
    category: "system",
    example: "atuin search ssh",
  },
  {
    name: "ananicy-cpp",
    fullName: "Ananicy-CPP Daemon",
    description: "Process priority daemon with 1700+ rules for auto-deprioritization.",
    category: "system",
    example: "systemctl status ananicy-cpp",
    docsUrl: "https://gitlab.com/ananicy-cpp/ananicy-cpp",
  },
  {
    name: "direnv",
    fullName: "direnv",
    description: "Directory-specific env vars.",
    category: "system",
    example: "direnv allow",
  },
  {
    name: "br",
    fullName: "Beads CLI",
    description: "Task graph management.",
    category: "stack",
    example: "br ready",
  },
  {
    name: "bv",
    fullName: "Beads Viewer",
    description: "Issue and workflow viewer (use --robot-* flags).",
    category: "stack",
    example: "bv --robot-triage",
  },
  {
    name: "ms",
    fullName: "Meta Skill",
    description: "Local-first knowledge management with hybrid semantic search.",
    category: "stack",
    example: "ms search 'auth flow'",
    aliases: ["meta-skill"],
  },
  {
    name: "ubs",
    fullName: "Ultimate Bug Scanner",
    description: "Static analysis with guardrails.",
    category: "stack",
    example: "ubs .",
  },
  {
    name: "cass",
    fullName: "CASS",
    description: "Session search across agents.",
    category: "stack",
    example: "cass health",
  },
  {
    name: "cm",
    fullName: "CASS Memory",
    description: "Procedural memory for agent workflows.",
    category: "stack",
    example: 'cm context "auth flow"',
  },
  {
    name: "caam",
    fullName: "CAAM",
    description: "Agent account manager.",
    category: "stack",
    example: "caam status",
  },
  {
    name: "slb",
    fullName: "Simultaneous Launch Button",
    description: "Two-person rule for dangerous commands.",
    category: "stack",
    example: "slb",
  },
  {
    name: "dcg",
    fullName: "Destructive Command Guard",
    description: "Claude Code hook blocking dangerous git/fs commands before execution.",
    category: "stack",
    example: "dcg test 'rm -rf /'",
    aliases: ["destructive-command-guard"],
  },
  {
    name: "ru",
    fullName: "Repo Updater",
    description: "Multi-repo sync with AI-driven commit automation.",
    category: "stack",
    example: "ru sync -j4",
    aliases: ["repo-updater"],
  },
  {
    name: "am",
    fullName: "Agent Mail",
    description: "Agent coordination and messaging.",
    category: "stack",
    example: "am status",
  },
  {
    name: "apr",
    fullName: "Automated Plan Reviser",
    description: "Automated iterative spec refinement with extended AI reasoning.",
    category: "stack",
    example: "apr refine plan.md",
    aliases: ["automated-plan-reviser"],
  },
  {
    name: "jfp",
    fullName: "JeffreysPrompts CLI",
    description: "Battle-tested prompt library with one-click skill install.",
    category: "stack",
    example: "jfp install idea-wizard",
    aliases: ["jeffreysprompts"],
    docsUrl: "https://jeffreysprompts.com",
  },
  {
    name: "pt",
    fullName: "Process Triage",
    description: "Find and kill stuck/zombie processes with Bayesian scoring.",
    category: "stack",
    example: "pt",
    aliases: ["process-triage"],
  },
  {
    name: "sysmoni",
    fullName: "SRPS System Monitor",
    description: "Real-time TUI showing CPU/memory per process with ananicy rule status.",
    category: "stack",
    example: "sysmoni",
    docsUrl: "https://github.com/Dicklesworthstone/system_resource_protection_script",
  },
  {
    name: "xf",
    fullName: "X Archive Search",
    description: "Blazingly fast local search across your X/Twitter archive.",
    category: "stack",
    example: 'xf search "machine learning"',
    docsUrl: "https://github.com/Dicklesworthstone/xf",
  },
  {
    name: "bun",
    fullName: "Bun",
    description: "JS/TS runtime and package manager.",
    category: "languages",
    example: "bun install",
  },
  {
    name: "uv",
    fullName: "uv",
    description: "Fast Python package manager.",
    category: "languages",
    example: "uv venv",
  },
  {
    name: "cargo",
    fullName: "Rust Cargo",
    description: "Rust package manager.",
    category: "languages",
    example: "cargo build",
  },
  {
    name: "go",
    fullName: "Go",
    description: "Go toolchain.",
    category: "languages",
    example: "go test ./...",
  },
  {
    name: "wrangler",
    fullName: "Wrangler",
    description: "Cloudflare CLI.",
    category: "cloud",
    example: "wrangler whoami",
  },
  {
    name: "supabase",
    fullName: "Supabase CLI",
    description: "Supabase management tools.",
    category: "cloud",
    example: "supabase status",
  },
  {
    name: "vercel",
    fullName: "Vercel CLI",
    description: "Vercel deployment tools.",
    category: "cloud",
    example: "vercel whoami",
  },
  {
    name: "psql",
    fullName: "PostgreSQL Client",
    description: "Connect to PostgreSQL databases.",
    category: "cloud",
    example: "psql -h localhost -U postgres",
  },
  {
    name: "vault",
    fullName: "Vault CLI",
    description: "HashiCorp Vault secrets manager.",
    category: "cloud",
    example: "vault status",
  },
];

// Auto-merge any manifest-defined commands not already in the hand-maintained list.
// This ensures new tools added to acfs.manifest.yaml appear automatically.
const _handMaintainedNames = new Set(COMMANDS.map((c) => c.name));
const _generatedExtras: CommandRef[] = manifestCommands
  .filter((mc) => !_handMaintainedNames.has(mc.cliName))
  .map((mc) => ({
    name: mc.cliName,
    fullName: mc.description.split(" - ")[0] || mc.cliName,
    description: mc.description,
    category: "stack" as CommandCategory,
    example: mc.commandExample ?? `${mc.cliName} --help`,
    aliases: mc.cliAliases.length > 0 ? mc.cliAliases : undefined,
    docsUrl: mc.docsUrl,
  }));

/** All commands: hand-maintained + auto-discovered from manifest. */
export const ALL_COMMANDS: CommandRef[] = [...COMMANDS, ..._generatedExtras];
