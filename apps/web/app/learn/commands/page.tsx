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
} from "lucide-react";
import { motion } from "@/components/motion";
import { Card } from "@/components/ui/card";
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
}> = [
  {
    id: "agents",
    name: "AI Agents",
    description: "Your three coding agents (aliases included)",
    icon: <Bot className="h-5 w-5" />,
  },
  {
    id: "stack",
    name: "Dicklesworthstone Stack",
    description: "The 8-tool orchestration stack (plus Beads)",
    icon: <Terminal className="h-5 w-5" />,
  },
  {
    id: "search",
    name: "Search & Navigation",
    description: "Find code and jump around fast",
    icon: <Search className="h-5 w-5" />,
  },
  {
    id: "git",
    name: "Git & Repo Tools",
    description: "Version control and GitHub workflows",
    icon: <GitBranch className="h-5 w-5" />,
  },
  {
    id: "system",
    name: "System & Terminal UX",
    description: "Everyday terminal helpers installed by ACFS",
    icon: <Wrench className="h-5 w-5" />,
  },
  {
    id: "languages",
    name: "Languages & Runtimes",
    description: "Bun, Python (uv), Rust, Go",
    icon: <Code2 className="h-5 w-5" />,
  },
  {
    id: "cloud",
    name: "Cloud & Infra",
    description: "Deploy, DNS, secrets, databases",
    icon: <Cloud className="h-5 w-5" />,
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
    name: "bd",
    fullName: "Beads CLI",
    description: "Create/update issues and dependencies",
    example: "bd ready",
    category: "stack",
    learnMoreHref: "/learn/tools/beads",
  },
  {
    name: "bv",
    fullName: "Beads Viewer",
    description: "Analyze the task DAG and pick work (robot protocol)",
    example: "bv -robot-triage -recipe high-impact",
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
    name: "convex",
    fullName: "Convex CLI",
    description: "Convex database and backend CLI",
    example: "convex --version",
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
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      transition={springs.stiff}
      className={`rounded-full border px-4 py-2 text-sm font-medium transition-colors ${
        isSelected
          ? "border-primary/50 bg-primary/15 text-primary shadow-sm shadow-primary/10"
          : "border-border/50 bg-card/40 text-muted-foreground hover:border-primary/30 hover:bg-primary/5 hover:text-foreground"
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
  index = 0,
}: {
  title: string;
  description: string;
  icon: ReactNode;
  commands: CommandEntry[];
  index?: number;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ ...springs.smooth, delay: staggerDelay(index, 0.08) }}
    >
      <Card className="group overflow-hidden border-border/50 bg-card/50 backdrop-blur-sm transition-all duration-300 hover:border-primary/20 hover:shadow-lg hover:shadow-primary/5">
        <div className="border-b border-border/30 bg-muted/20 p-5">
          <div className="flex items-start gap-4">
            <motion.div
              className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary transition-all group-hover:bg-primary/20 group-hover:shadow-md group-hover:shadow-primary/10"
              whileHover={{ scale: 1.05, rotate: 3 }}
              transition={springs.stiff}
            >
              {icon}
            </motion.div>
            <div className="min-w-0">
              <h2 className="text-lg font-semibold">{title}</h2>
              <p className="mt-1 text-sm text-muted-foreground">{description}</p>
            </div>
          </div>
        </div>

        <div className="space-y-6 p-5">
          {commands.map((cmd) => {
            const anchorId = toAnchorId(cmd.name);
            return (
              <div key={`${cmd.category}:${cmd.name}`} id={anchorId} className="scroll-mt-28">
                <div className="mb-2 flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                  <div className="min-w-0">
                    <div className="flex items-baseline gap-3">
                      <code className="font-mono text-base font-bold text-foreground">
                        {cmd.name}
                      </code>
                      <span className="text-sm font-medium text-muted-foreground">
                        {cmd.fullName}
                      </span>
                    </div>
                    <p className="mt-1 text-sm text-muted-foreground">
                      {cmd.description}
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <Link
                      href={`#${anchorId}`}
                      className="text-xs text-muted-foreground hover:text-foreground"
                    >
                      #{anchorId}
                    </Link>
                    {cmd.learnMoreHref && (
                      <Link
                        href={cmd.learnMoreHref}
                        className="text-sm text-primary hover:underline"
                      >
                        Full docs →
                      </Link>
                    )}
                  </div>
                </div>

                <CommandCard command={cmd.example} description="Example" />
              </div>
            );
          })}
        </div>
      </Card>
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
    <div className="relative min-h-screen bg-background">
      {/* Background effects */}
      <div className="pointer-events-none fixed inset-0 bg-gradient-cosmic opacity-50" />
      <div className="pointer-events-none fixed inset-0 bg-grid-pattern opacity-20" />

      {/* Floating orbs */}
      <div className="pointer-events-none fixed inset-0 overflow-hidden">
        <div className="absolute -left-32 top-1/4 h-96 w-96 rounded-full bg-[oklch(0.75_0.18_195/0.08)] blur-[100px] animate-pulse-glow" />
        <div className="absolute -right-32 top-2/3 h-80 w-80 rounded-full bg-[oklch(0.7_0.2_330/0.06)] blur-[80px] animate-pulse-glow" style={{ animationDelay: "2s" }} />
      </div>

      <div className="relative mx-auto max-w-5xl px-6 py-8 md:px-12 md:py-12">
        {/* Header */}
        <div className="mb-8 flex items-center justify-between">
          <Link
            href="/learn"
            className="flex items-center gap-2 text-muted-foreground transition-colors hover:text-foreground"
          >
            <ArrowLeft className="h-4 w-4" />
            <span className="text-sm">Learning Hub</span>
          </Link>
          <Link
            href="/"
            className="flex items-center gap-2 text-muted-foreground transition-colors hover:text-foreground"
          >
            <Home className="h-4 w-4" />
            <span className="text-sm">Home</span>
          </Link>
        </div>

        {/* Hero */}
        <div className="mb-10 text-center">
          <div className="mb-4 flex justify-center">
            <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-primary to-[oklch(0.7_0.2_330)] shadow-lg shadow-primary/20">
              <Cpu className="h-8 w-8 text-primary-foreground" />
            </div>
          </div>
          <h1 className="mb-3 text-3xl font-bold tracking-tight md:text-4xl">
            Command Reference
          </h1>
          <p className="mx-auto max-w-xl text-lg text-muted-foreground">
            A quick, searchable list of the commands you&apos;ll use most in an
            ACFS environment.
          </p>
        </div>

        {/* Search */}
        <div className="relative mb-6 group">
          <Search className="absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-muted-foreground transition-colors group-focus-within:text-primary" />
          <input
            type="text"
            placeholder="Search commands..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full rounded-xl border border-border/50 bg-card/60 py-3.5 pl-12 pr-4 text-foreground shadow-sm backdrop-blur-sm placeholder:text-muted-foreground transition-all duration-200 focus:border-primary/50 focus:outline-none focus:ring-2 focus:ring-primary/20 focus:shadow-lg focus:shadow-primary/5"
          />
        </div>

        {/* Category filter */}
        <div className="mb-10 flex flex-wrap gap-2">
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
        </div>

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
                  index={idx}
                />
              );
            })
          ) : (
            <motion.div
              className="py-12 text-center"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={springs.smooth}
            >
              <Search className="mx-auto mb-4 h-12 w-12 text-muted-foreground/50" />
              <p className="text-muted-foreground">
                No commands match your search.
              </p>
            </motion.div>
          )}
        </div>
      </div>
    </div>
  );
}
