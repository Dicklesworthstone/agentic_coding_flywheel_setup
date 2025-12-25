import Link from "next/link";
import { notFound } from "next/navigation";
import { type ReactNode } from "react";
import {
  ArrowLeft,
  ArrowUpRight,
  Bot,
  GitBranch,
  GraduationCap,
  Home,
  KeyRound,
  LayoutGrid,
  Search,
  ShieldCheck,
  Wrench,
} from "lucide-react";
import { motion } from "@/components/motion";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { CommandCard } from "@/components/command-card";
import { springs, backgrounds } from "@/lib/design-tokens";

type ToolId =
  | "claude-code"
  | "codex-cli"
  | "gemini-cli"
  | "ntm"
  | "beads"
  | "agent-mail"
  | "ubs"
  | "cass"
  | "cm"
  | "caam"
  | "slb";

type ToolCard = {
  id: ToolId;
  title: string;
  tagline: string;
  icon: ReactNode;
  accent: string;
  /** Primary docs/repo link */
  docsUrl: string;
  docsLabel: string;
  /** Quick install or start command */
  quickCommand?: string;
  /** Related tools in ACFS */
  relatedTools: ToolId[];
};

const TOOLS: Record<ToolId, ToolCard> = {
  "claude-code": {
    id: "claude-code",
    title: "Claude Code",
    tagline: "Anthropic's AI coding agent - deep reasoning and architecture",
    icon: <Bot className="h-8 w-8 text-white" />,
    accent: "from-orange-400 to-amber-500",
    docsUrl: "https://docs.anthropic.com/en/docs/claude-code",
    docsLabel: "Anthropic Docs",
    quickCommand: "cc",
    relatedTools: ["codex-cli", "gemini-cli", "ntm"],
  },
  "codex-cli": {
    id: "codex-cli",
    title: "Codex CLI",
    tagline: "OpenAI's coding agent - fast iteration and structured work",
    icon: <GraduationCap className="h-8 w-8 text-white" />,
    accent: "from-emerald-400 to-teal-500",
    docsUrl: "https://github.com/openai/codex",
    docsLabel: "GitHub",
    quickCommand: "cod",
    relatedTools: ["claude-code", "gemini-cli", "ntm"],
  },
  "gemini-cli": {
    id: "gemini-cli",
    title: "Gemini CLI",
    tagline: "Google's coding agent - large context exploration",
    icon: <Search className="h-8 w-8 text-white" />,
    accent: "from-blue-400 to-indigo-500",
    docsUrl: "https://github.com/google-gemini/gemini-cli",
    docsLabel: "GitHub",
    quickCommand: "gmi",
    relatedTools: ["claude-code", "codex-cli", "ntm"],
  },
  ntm: {
    id: "ntm",
    title: "Named Tmux Manager",
    tagline: "The agent cockpit - spawn and orchestrate multiple agents",
    icon: <LayoutGrid className="h-8 w-8 text-white" />,
    accent: "from-sky-400 to-blue-500",
    docsUrl: "https://github.com/Dicklesworthstone/named_tmux_manager",
    docsLabel: "GitHub",
    quickCommand: "ntm spawn myproject --cc=2",
    relatedTools: ["claude-code", "codex-cli", "agent-mail"],
  },
  beads: {
    id: "beads",
    title: "Beads",
    tagline: "Task graphs + robot triage for dependency-aware work tracking",
    icon: <GitBranch className="h-8 w-8 text-white" />,
    accent: "from-emerald-400 to-teal-500",
    docsUrl: "https://github.com/Dicklesworthstone/beads_viewer",
    docsLabel: "GitHub",
    quickCommand: "bd ready",
    relatedTools: ["agent-mail", "ubs"],
  },
  "agent-mail": {
    id: "agent-mail",
    title: "MCP Agent Mail",
    tagline: "Gmail for agents - messaging, threads, and file reservations",
    icon: <KeyRound className="h-8 w-8 text-white" />,
    accent: "from-violet-400 to-purple-500",
    docsUrl: "https://github.com/Dicklesworthstone/mcp_agent_mail",
    docsLabel: "GitHub",
    relatedTools: ["ntm", "beads", "cass"],
  },
  ubs: {
    id: "ubs",
    title: "Ultimate Bug Scanner",
    tagline: "Fast polyglot static analysis - your pre-commit quality gate",
    icon: <ShieldCheck className="h-8 w-8 text-white" />,
    accent: "from-rose-400 to-red-500",
    docsUrl: "https://github.com/Dicklesworthstone/ultimate_bug_scanner",
    docsLabel: "GitHub",
    quickCommand: "ubs .",
    relatedTools: ["beads", "slb"],
  },
  cass: {
    id: "cass",
    title: "CASS",
    tagline: "Search across all your agent sessions instantly",
    icon: <Search className="h-8 w-8 text-white" />,
    accent: "from-cyan-400 to-sky-500",
    docsUrl: "https://github.com/Dicklesworthstone/coding_agent_session_search",
    docsLabel: "GitHub",
    quickCommand: "cass search 'auth error' --robot",
    relatedTools: ["cm", "agent-mail"],
  },
  cm: {
    id: "cm",
    title: "CASS Memory",
    tagline: "Procedural memory - playbooks and lessons from past sessions",
    icon: <Wrench className="h-8 w-8 text-white" />,
    accent: "from-fuchsia-400 to-pink-500",
    docsUrl: "https://github.com/Dicklesworthstone/cass_memory_system",
    docsLabel: "GitHub",
    quickCommand: "cm context 'my task' --json",
    relatedTools: ["cass", "beads"],
  },
  caam: {
    id: "caam",
    title: "CAAM",
    tagline: "Switch agent credentials safely without account confusion",
    icon: <Wrench className="h-8 w-8 text-white" />,
    accent: "from-amber-400 to-orange-500",
    docsUrl: "https://github.com/Dicklesworthstone/coding_agent_account_manager",
    docsLabel: "GitHub",
    relatedTools: ["claude-code", "codex-cli", "gemini-cli"],
  },
  slb: {
    id: "slb",
    title: "SLB",
    tagline: "Two-person rule for dangerous commands - safety first",
    icon: <ShieldCheck className="h-8 w-8 text-white" />,
    accent: "from-yellow-400 to-orange-500",
    docsUrl: "https://github.com/Dicklesworthstone/simultaneous_launch_button",
    docsLabel: "GitHub",
    relatedTools: ["ubs", "beads"],
  },
};

function RelatedToolCard({ toolId }: { toolId: ToolId }) {
  const tool = TOOLS[toolId];
  if (!tool) return null;

  return (
    <Link href={`/learn/tools/${toolId}`}>
      <motion.div
        whileHover={{ y: -2 }}
        className="flex items-center gap-3 rounded-lg border border-border/50 bg-card/50 p-3 transition-all hover:border-primary/30 hover:shadow-md hover:shadow-primary/5"
      >
        <div
          className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br ${tool.accent}`}
        >
          <div className="scale-50">{tool.icon}</div>
        </div>
        <div className="min-w-0 flex-1">
          <div className="truncate font-medium text-sm">{tool.title}</div>
        </div>
      </motion.div>
    </Link>
  );
}

interface Props {
  params: { tool: string };
}

export default function ToolCardPage({ params }: Props) {
  const { tool } = params;
  const doc = TOOLS[tool as ToolId];

  if (!doc) {
    notFound();
  }

  return (
    <div className="relative min-h-screen bg-background">
      {/* Background effects */}
      <div className="pointer-events-none fixed inset-0 bg-gradient-cosmic opacity-50" />
      <div className="pointer-events-none fixed inset-0 bg-grid-pattern opacity-20" />

      {/* Floating orbs */}
      <div className={backgrounds.orbCyan} />
      <div className={backgrounds.orbPink} />

      <div className="relative mx-auto max-w-2xl px-6 py-8 md:px-12 md:py-12">
        {/* Header */}
        <motion.div
          className="mb-8 flex items-center justify-between"
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={springs.smooth}
        >
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
        </motion.div>

        {/* Main Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ ...springs.smooth, delay: 0.1 }}
        >
          <Card className="group relative overflow-hidden border-border/50 bg-card/50 p-8 backdrop-blur-sm">
            {/* Gradient glow on hover */}
            <div className="pointer-events-none absolute inset-0 bg-gradient-to-br from-primary/5 via-transparent to-transparent opacity-0 transition-opacity duration-300 group-hover:opacity-100" />

            {/* Icon + Title */}
            <div className="relative mb-6 flex items-start gap-4">
              <motion.div
                className={`flex h-16 w-16 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br shadow-lg ${doc.accent}`}
                initial={{ scale: 0.8, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ ...springs.bouncy, delay: 0.2 }}
              >
                {doc.icon}
              </motion.div>
              <div className="min-w-0 flex-1">
                <h1 className="mb-1 font-mono text-2xl font-bold tracking-tight md:text-3xl">
                  {doc.title}
                </h1>
                <p className="text-muted-foreground">{doc.tagline}</p>
              </div>
            </div>

            {/* Docs Link - Primary CTA */}
            <motion.div
              className="relative mb-6"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ ...springs.smooth, delay: 0.3 }}
            >
              <Button asChild size="lg" className="w-full gap-2">
                <a
                  href={doc.docsUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  View Full Documentation on {doc.docsLabel}
                  <ArrowUpRight className="h-4 w-4" />
                </a>
              </Button>
            </motion.div>

            {/* Quick Command */}
            {doc.quickCommand && (
              <motion.div
                className="relative mb-6"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ ...springs.smooth, delay: 0.4 }}
              >
                <p className="mb-2 text-sm font-medium text-muted-foreground">
                  Quick Start
                </p>
                <CommandCard command={doc.quickCommand} description="Command" />
              </motion.div>
            )}

            {/* Related Tools */}
            {doc.relatedTools.length > 0 && (
              <motion.div
                className="relative"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ ...springs.smooth, delay: 0.5 }}
              >
                <p className="mb-3 text-sm font-medium text-muted-foreground">
                  Related Tools
                </p>
                <div className="grid gap-2 sm:grid-cols-2">
                  {doc.relatedTools.slice(0, 4).map((relatedId) => (
                    <RelatedToolCard key={relatedId} toolId={relatedId} />
                  ))}
                </div>
              </motion.div>
            )}
          </Card>
        </motion.div>

        {/* Footer link back */}
        <motion.div
          className="mt-8 text-center"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ ...springs.smooth, delay: 0.6 }}
        >
          <Link
            href="/learn/commands"
            className="text-sm text-muted-foreground transition-colors hover:text-primary"
          >
            See all commands in the Command Reference →
          </Link>
        </motion.div>
      </div>
    </div>
  );
}
