"use client";

import Link from "next/link";
import { useMemo, useState, type ReactNode } from "react";
import {
  ArrowLeft,
  Bot,
  Cloud,
  Code2,
  Cpu,
  GitBranch,
  Home,
  Search,
  Terminal,
  Wrench,
  ChevronRight,
  Sparkles,
} from "lucide-react";
import { motion } from "@/components/motion";
import { CommandCard } from "@/components/command-card";
import { springs, staggerDelay } from "@/lib/design-tokens";

type CommandCategory =
  | "agents"
  | "stack"
  | "search"
  | "git"
  | "system"
  | "languages"
  | "cloud";

type CategoryFilter = "all" | CommandCategory;

type CommandEntry = {
  name: string;
  fullName: string;
  description: string;
  example: string;
  category: CommandCategory;
  learnMoreHref?: string;
};

const CATEGORY_META: Array<{
  id: CommandCategory;
  name: string;
  description: string;
  icon: ReactNode;
  gradient: string;
}> = [
  {
    id: "agents",
    name: "AI Agents",
    description: "Your three coding agents (aliases included)",
    icon: <Bot className="h-5 w-5" />,
    gradient: "from-violet-500/20 to-purple-500/20",
  },
  {
    id: "stack",
    name: "Dicklesworthstone Stack",
    description: "The 10-tool orchestration stack (plus utilities)",
    icon: <Terminal className="h-5 w-5" />,
    gradient: "from-primary/20 to-blue-500/20",
  },
  {
    id: "search",
    name: "Search & Navigation",
    description: "Find code and jump around fast",
    icon: <Search className="h-5 w-5" />,
    gradient: "from-emerald-500/20 to-teal-500/20",
  },
  {
    id: "git",
    name: "Git & Repo Tools",
    description: "Version control and GitHub workflows",
    icon: <GitBranch className="h-5 w-5" />,
    gradient: "from-orange-500/20 to-amber-500/20",
  },
  {
    id: "system",
    name: "System & Terminal UX",
    description: "Everyday terminal helpers installed by ACFS",
    icon: <Wrench className="h-5 w-5" />,
    gradient: "from-pink-500/20 to-rose-500/20",
  },
  {
    id: "languages",
    name: "Languages & Runtimes",
    description: "Bun, Python (uv), Rust, Go",
    icon: <Code2 className="h-5 w-5" />,
    gradient: "from-cyan-500/20 to-sky-500/20",
  },
  {
    id: "cloud",
    name: "Cloud & Infra",
    description: "Deploy, DNS, secrets, databases",
    icon: <Cloud className="h-5 w-5" />,
    gradient: "from-indigo-500/20 to-violet-500/20",
  },
];

const COMMANDS: CommandEntry[] = [
  // Agents
  {
    name: "cc",
    fullName: "Claude Code",
    description: "Anthropic coding agent (alias for `claude`)",
    example: 'cc "fix the bug in auth.ts"',
    category: "agents",
    learnMoreHref: "/learn/agent-commands",
  },
  {
    name: "cod",
    fullName: "Codex CLI",
    description: "OpenAI coding agent (alias for `codex`)",
    example: 'cod "add unit tests for utils.ts"',
    category: "agents",
    learnMoreHref: "/learn/agent-commands",
  },
  {
    name: "gmi",
    fullName: "Gemini CLI",
    description: "Google coding agent (alias for `gemini`)",
    example: 'gmi "explain the repo structure"',
    category: "agents",
    learnMoreHref: "/learn/agent-commands",
  },
  {
    name: "claude",
    fullName: "Claude Code",
    description: "Full command (same as `cc` on ACFS)",
    example: "claude --help",
    category: "agents",
    learnMoreHref: "/learn/agent-commands",
  },
  {
    name: "codex",
    fullName: "Codex CLI",
    description: "Full command (same as `cod` on ACFS)",
    example: "codex --help",
    category: "agents",
    learnMoreHref: "/learn/agent-commands",
  },
  {
    name: "gemini",
    fullName: "Gemini CLI",
    description: "Full command (same as `gmi` on ACFS)",
    example: "gemini --help",
    category: "agents",
    learnMoreHref: "/learn/agent-commands",
  },

  // Stack / orchestration
  {
    name: "ntm",
    fullName: "Named Tmux Manager",
    description: "Agent cockpit (spawn, send prompts, dashboards)",
    example: "ntm spawn myproject --cc=2 --cod=1 --gmi=1",
    category: "stack",
    learnMoreHref: "/learn/ntm-palette",
  },
  {
    name: "br",
    fullName: "Beads CLI",
    description: "Create/update issues and dependencies",
    example: "br ready",
    category: "stack",
    learnMoreHref: "/learn/tools/beads",
  },
  {
    name: "bv",
    fullName: "Beads Viewer",
    description: "Analyze the task DAG and pick work (robot protocol)",
    example: "bv --robot-triage --recipe high-impact",
    category: "stack",
    learnMoreHref: "/learn/tools/beads",
  },
  {
    name: "ubs",
    fullName: "Ultimate Bug Scanner",
    description: "Fast polyglot static analysis",
    example: "ubs .",
    category: "stack",
    learnMoreHref: "/learn/tools/ubs",
  },
  {
    name: "cass",
    fullName: "Coding Agent Session Search",
    description: "Search across your agent session history",
    example: "cass --help",
    category: "stack",
    learnMoreHref: "/learn/tools/cass",
  },
  {
    name: "cm",
    fullName: "CASS Memory System",
    description: "Procedural memory for agents",
    example: "cm --help",
    category: "stack",
    learnMoreHref: "/learn/tools/cm",
  },
  {
    name: "caam",
    fullName: "Coding Agent Account Manager",
    description: "Switch agent auth contexts",
    example: "caam --help",
    category: "stack",
    learnMoreHref: "/learn/tools/caam",
  },
  {
    name: "slb",
    fullName: "Simultaneous Launch Button",
    description: "Two-person rule for dangerous commands",
    example: "slb --help",
    category: "stack",
    learnMoreHref: "/learn/tools/slb",
  },
  {
    name: "dcg",
    fullName: "Destructive Command Guard",
    description: "Pre-execution guard blocking dangerous commands",
    example: "dcg --help",
    category: "stack",
    learnMoreHref: "/learn/tools/dcg",
  },
  {
    name: "dcg test",
    fullName: "DCG Test Command",
    description: "Check if a command would be blocked without running it",
    example: "dcg test 'git reset --hard' --explain",
    category: "stack",
    learnMoreHref: "/learn/tools/dcg",
  },
  {
    name: "dcg packs",
    fullName: "DCG Pack List",
    description: "List available protection packs (git, database, k8s, cloud)",
    example: "dcg packs --enabled",
    category: "stack",
    learnMoreHref: "/learn/tools/dcg",
  },
  {
    name: "dcg allow-once",
    fullName: "DCG Allow Once",
    description: "Bypass a block using the short code from denial message",
    example: "dcg allow-once ABC-123",
    category: "stack",
    learnMoreHref: "/learn/tools/dcg",
  },
  {
    name: "dcg doctor",
    fullName: "DCG Doctor",
    description: "Check DCG installation and hook registration status",
    example: "dcg doctor --fix",
    category: "stack",
    learnMoreHref: "/learn/tools/dcg",
  },

  // Search
  {
    name: "rg",
    fullName: "ripgrep",
    description: "Ultra-fast recursive text search",
    example: 'rg "useCompletedLessons" apps/web',
    category: "search",
  },
  {
    name: "sg",
    fullName: "ast-grep",
    description: "Structural search/replace",
    example: "sg --help",
    category: "search",
  },
  {
    name: "fd",
    fullName: "fd-find",
    description: "Fast file finder",
    example: 'fd \"\\.ts$\" apps/web',
    category: "search",
  },
  {
    name: "fzf",
    fullName: "fzf",
    description: "Interactive fuzzy finder",
    example: "fzf",
    category: "search",
  },
  {
    name: "z",
    fullName: "zoxide",
    description: "Smart `cd` (jump to frequently-used folders)",
    example: "z projects",
    category: "search",
  },

  // Git
  {
    name: "git",
    fullName: "Git",
    description: "Version control",
    example: "git status -sb",
    category: "git",
  },
  {
    name: "gh",
    fullName: "GitHub CLI",
    description: "GitHub from the terminal",
    example: "gh auth status",
    category: "git",
  },
  {
    name: "lazygit",
    fullName: "LazyGit",
    description: "Git TUI",
    example: "lazygit",
    category: "git",
  },

  // System
  {
    name: "tmux",
    fullName: "tmux",
    description: "Terminal multiplexer (sessions survive disconnects)",
    example: "tmux new -s demo",
    category: "system",
  },
  {
    name: "bat",
    fullName: "bat",
    description: "Better `cat` with syntax highlighting",
    example: "bat README.md",
    category: "system",
  },
  {
    name: "lsd / eza",
    fullName: "Modern `ls`",
    description: "Prettier directory listing (ACFS installs one of these)",
    example: "lsd -la || eza -la",
    category: "system",
  },
  {
    name: "direnv",
    fullName: "direnv",
    description: "Auto-load per-directory env vars",
    example: "direnv allow",
    category: "system",
  },
  {
    name: "atuin",
    fullName: "atuin",
    description: "Searchable shell history (Ctrl-R)",
    example: "atuin --help",
    category: "system",
  },

  // Languages
  {
    name: "bun",
    fullName: "bun",
    description: "JS/TS runtime + package manager",
    example: "bun --version",
    category: "languages",
  },
  {
    name: "uv",
    fullName: "uv",
    description: "Fast Python tooling (pip/venv replacement)",
    example: "uv --version",
    category: "languages",
  },
  {
    name: "cargo",
    fullName: "cargo",
    description: "Rust package manager/build tool",
    example: "cargo --version",
    category: "languages",
  },
  {
    name: "go",
    fullName: "go",
    description: "Go toolchain",
    example: "go version",
    category: "languages",
  },

  // Cloud
  {
    name: "wrangler",
    fullName: "Cloudflare Wrangler",
    description: "Cloudflare Workers and Pages CLI",
    example: "wrangler --version",
    category: "cloud",
  },
  {
    name: "vercel",
    fullName: "Vercel CLI",
    description: "Deploy and manage Vercel projects",
    example: "vercel --version",
    category: "cloud",
  },
  {
    name: "supabase",
    fullName: "Supabase CLI",
    description: "Supabase management CLI",
    example: "supabase --version",
    category: "cloud",
  },
  {
    name: "vault",
    fullName: "HashiCorp Vault",
    description: "Secrets management",
    example: "vault --version",
    category: "cloud",
  },
];

function toAnchorId(value: string): string {
  return value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function CategoryChip({
  label,
  isSelected,
  onClick,
}: {
  label: string;
  isSelected: boolean;
  onClick: () => void;
}) {
  return (
    <motion.button
      type="button"
      onClick={onClick}
      whileHover={{ scale: 1.03 }}
      whileTap={{ scale: 0.97 }}
      transition={springs.stiff}
      className={`rounded-full border px-5 py-2.5 text-sm font-medium transition-all duration-300 ${
        isSelected
          ? "border-primary/50 bg-gradient-to-r from-primary/20 to-violet-500/20 text-white shadow-[0_0_20px_rgba(var(--primary-rgb),0.3)]"
          : "border-white/[0.08] bg-white/[0.03] text-white/60 hover:border-white/20 hover:bg-white/[0.06] hover:text-white/80"
      }`}
    >
      {label}
    </motion.button>
  );
}

function CategoryCard({
  title,
  description,
  icon,
  commands,
  gradient,
  index = 0,
}: {
  title: string;
  description: string;
  icon: ReactNode;
  commands: CommandEntry[];
  gradient: string;
  index?: number;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 30 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ ...springs.smooth, delay: staggerDelay(index, 0.08) }}
    >
      <div className="group relative overflow-hidden rounded-2xl border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl transition-all duration-500 hover:border-white/[0.15] hover:bg-white/[0.04]">
        {/* Gradient glow on hover */}
        <div className={`absolute inset-0 bg-gradient-to-br ${gradient} opacity-0 group-hover:opacity-100 transition-opacity duration-500`} />

        {/* Header */}
        <div className="relative border-b border-white/[0.06] p-6">
          <div className="flex items-start gap-5">
            {/* Icon with glow */}
            <div className="relative shrink-0">
              <div className={`absolute inset-0 bg-gradient-to-br ${gradient} rounded-xl blur-xl opacity-50 group-hover:opacity-80 transition-opacity duration-500 scale-110`} />
              <motion.div
                className="relative flex h-12 w-12 items-center justify-center rounded-xl bg-white/[0.08] border border-white/[0.12] text-white transition-all duration-300 group-hover:scale-110"
                whileHover={{ rotate: 5 }}
                transition={springs.stiff}
              >
                {icon}
              </motion.div>
            </div>
            <div className="min-w-0">
              <h2 className="text-xl font-bold text-white">{title}</h2>
              <p className="mt-1 text-sm text-white/50">{description}</p>
            </div>
          </div>
        </div>

        {/* Commands */}
        <div className="relative space-y-6 p-6">
          {commands.map((cmd) => {
            const anchorId = toAnchorId(cmd.name);
            return (
              <div key={`${cmd.category}:${cmd.name}`} id={anchorId} className="scroll-mt-28 group/cmd">
                <div className="mb-3 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
                  <div className="min-w-0">
                    <div className="flex items-baseline gap-3">
                      <code className="font-mono text-lg font-bold text-white">
                        {cmd.name}
                      </code>
                      <span className="text-sm font-medium text-white/40">
                        {cmd.fullName}
                      </span>
                    </div>
                    <p className="mt-1 text-sm text-white/50 leading-relaxed">
                      {cmd.description}
                    </p>
                  </div>
                  <div className="flex items-center gap-4 shrink-0">
                    <Link
                      href={`#${anchorId}`}
                      className="text-xs text-white/30 hover:text-white/60 transition-colors font-mono"
                    >
                      #{anchorId}
                    </Link>
                    {cmd.learnMoreHref && (
                      <Link
                        href={cmd.learnMoreHref}
                        className="group/link flex items-center gap-1 text-sm font-medium text-primary hover:text-primary/80 transition-colors"
                      >
                        <span>Docs</span>
                        <ChevronRight className="h-3.5 w-3.5 transition-transform group-hover/link:translate-x-0.5" />
                      </Link>
                    )}
                  </div>
                </div>

                <CommandCard command={cmd.example} description="Example" />
              </div>
            );
          })}
        </div>
      </div>
    </motion.div>
  );
}

export default function CommandReferencePage() {
  const [searchQuery, setSearchQuery] = useState("");
  const [category, setCategory] = useState<CategoryFilter>("all");

  const normalizedQuery = searchQuery.trim().toLowerCase();

  const filteredCommands = useMemo(() => {
    return COMMANDS.filter((cmd) => {
      if (category !== "all" && cmd.category !== category) {
        return false;
      }
      if (!normalizedQuery) return true;
      const haystack = `${cmd.name} ${cmd.fullName} ${cmd.description} ${cmd.example}`.toLowerCase();
      return haystack.includes(normalizedQuery);
    });
  }, [category, normalizedQuery]);

  const grouped = useMemo(() => {
    const groups: Record<CommandCategory, CommandEntry[]> = {
      agents: [],
      stack: [],
      search: [],
      git: [],
      system: [],
      languages: [],
      cloud: [],
    };

    filteredCommands.forEach((cmd) => {
      groups[cmd.category].push(cmd);
    });

    return groups;
  }, [filteredCommands]);

  const hasAnyResults = filteredCommands.length > 0;

  return (
    <div className="min-h-screen bg-black relative overflow-x-hidden">
      {/* Dramatic ambient background */}
      <div className="fixed inset-0 pointer-events-none">
        {/* Large primary orb */}
        <div className="absolute w-[700px] h-[700px] bg-primary/10 blur-[180px] rounded-full -top-48 left-1/4 animate-float" />
        {/* Secondary orb */}
        <div className="absolute w-[500px] h-[500px] bg-violet-500/10 blur-[150px] rounded-full top-1/2 -right-32 animate-float" style={{ animationDelay: "2s" }} />
        {/* Tertiary orb */}
        <div className="absolute w-[400px] h-[400px] bg-emerald-500/8 blur-[120px] rounded-full bottom-0 left-0 animate-float" style={{ animationDelay: "4s" }} />
        {/* Grid */}
        <div className="absolute inset-0 bg-[linear-gradient(to_right,rgba(255,255,255,0.02)_1px,transparent_1px),linear-gradient(to_bottom,rgba(255,255,255,0.02)_1px,transparent_1px)] bg-[size:80px_80px]" />
      </div>

      <div className="relative mx-auto max-w-6xl px-5 py-8 sm:px-8 md:px-12 lg:py-12">
        {/* Header navigation */}
        <motion.header
          className="mb-10 flex items-center justify-between"
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={springs.smooth}
        >
          <Link
            href="/learn"
            className="group flex items-center gap-3 text-white/50 transition-all duration-300 hover:text-white"
          >
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-white/[0.05] border border-white/[0.08] transition-all duration-300 group-hover:scale-110 group-hover:bg-white/[0.1]">
              <ArrowLeft className="h-4 w-4" />
            </div>
            <span className="text-sm font-medium">Learning Hub</span>
          </Link>
          <Link
            href="/"
            className="group flex items-center gap-3 text-white/50 transition-all duration-300 hover:text-white"
          >
            <span className="text-sm font-medium">Home</span>
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-white/[0.05] border border-white/[0.08] transition-all duration-300 group-hover:scale-110 group-hover:bg-white/[0.1]">
              <Home className="h-4 w-4" />
            </div>
          </Link>
        </motion.header>

        {/* Hero section */}
        <motion.section
          className="mb-12 text-center"
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ ...springs.smooth, delay: 0.1 }}
        >
          {/* Icon with glow */}
          <motion.div
            className="mb-6 inline-flex"
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ ...springs.bouncy, delay: 0.2 }}
          >
            <div className="relative">
              <div className="absolute inset-0 bg-gradient-to-br from-primary to-violet-500 rounded-2xl blur-xl opacity-50" />
              <div className="relative flex h-18 w-18 items-center justify-center rounded-2xl bg-gradient-to-br from-primary/30 to-violet-500/30 border border-white/20 shadow-2xl shadow-primary/20">
                <Cpu className="h-9 w-9 text-white drop-shadow-lg" />
              </div>
              <Sparkles className="absolute -right-2 -top-2 h-5 w-5 text-primary animate-pulse" />
            </div>
          </motion.div>

          <h1 className="mb-4 text-4xl sm:text-5xl font-bold tracking-tight">
            <span className="bg-gradient-to-br from-white via-white to-white/50 bg-clip-text text-transparent">
              Command Reference
            </span>
          </h1>
          <p className="mx-auto max-w-2xl text-lg text-white/50 leading-relaxed">
            A quick, searchable list of the commands you&apos;ll use most in an
            ACFS environment.
          </p>
        </motion.section>

        {/* Search - stunning glassmorphic */}
        <motion.div
          className="relative mb-8"
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ ...springs.smooth, delay: 0.2 }}
        >
          <div className="group relative">
            {/* Glow on focus */}
            <div className="absolute -inset-1 rounded-2xl bg-gradient-to-r from-primary/30 via-violet-500/20 to-primary/30 blur-lg opacity-0 group-focus-within:opacity-100 transition-opacity duration-500" />

            <div className="relative">
              <Search className="absolute left-5 top-1/2 h-5 w-5 -translate-y-1/2 text-white/30 transition-colors group-focus-within:text-primary" />
              <input
                type="text"
                placeholder="Search commands..."
                aria-label="Search commands"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full rounded-xl border border-white/[0.08] bg-white/[0.03] py-4 pl-14 pr-5 text-white placeholder:text-white/30 backdrop-blur-xl transition-all duration-300 focus:border-primary/50 focus:bg-white/[0.05] focus:outline-none focus:shadow-[0_0_30px_rgba(var(--primary-rgb),0.15)]"
              />
            </div>
          </div>
        </motion.div>

        {/* Category filters */}
        <motion.div
          className="mb-12 flex flex-wrap gap-2 justify-center"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ ...springs.smooth, delay: 0.3 }}
        >
          <CategoryChip
            label="All"
            isSelected={category === "all"}
            onClick={() => setCategory("all")}
          />
          {CATEGORY_META.map((c) => (
            <CategoryChip
              key={c.id}
              label={c.name}
              isSelected={category === c.id}
              onClick={() => setCategory(c.id)}
            />
          ))}
        </motion.div>

        {/* Content */}
        <div className="space-y-8">
          {hasAnyResults ? (
            CATEGORY_META.map((meta, idx) => {
              const cmds = grouped[meta.id];
              if (cmds.length === 0) return null;
              return (
                <CategoryCard
                  key={meta.id}
                  title={meta.name}
                  description={meta.description}
                  icon={meta.icon}
                  commands={cmds}
                  gradient={meta.gradient}
                  index={idx}
                />
              );
            })
          ) : (
            <motion.div
              className="py-20 text-center"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={springs.smooth}
            >
              <div className="relative inline-flex mb-6">
                <div className="absolute inset-0 bg-white/10 rounded-2xl blur-xl" />
                <div className="relative flex h-16 w-16 items-center justify-center rounded-2xl bg-white/[0.05] border border-white/[0.08]">
                  <Search className="h-8 w-8 text-white/30" />
                </div>
              </div>
              <p className="text-lg text-white/40">
                No commands match your search.
              </p>
              <p className="text-sm text-white/25 mt-2">
                Try a different keyword or clear the filter.
              </p>
            </motion.div>
          )}
        </div>

        {/* Footer spacer */}
        <div className="h-20" />
      </div>
    </div>
  );
}
