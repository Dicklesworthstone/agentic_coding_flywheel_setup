import type { ReactNode } from "react";
import {
  Bot,
  GitBranch,
  GitMerge,
  GraduationCap,
  KeyRound,
  LayoutGrid,
  Search,
  Shield,
  ShieldAlert,
  ShieldCheck,
  Wrench,
} from "lucide-react";

export type ToolId =
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
  | "slb"
  | "dcg"
  | "ru"
  | "ms"
  | "apr"
  | "jfp"
  | "pt"
  | "srps"
  | "xf";

export type ToolCard = {
  id: ToolId;
  title: string;
  tagline: string;
  icon: ReactNode;
  gradient: string;
  glowColor: string;
  docsUrl: string;
  docsLabel: string;
  quickCommand?: string;
  relatedTools: ToolId[];
};

export const TOOLS: Record<ToolId, ToolCard> = {
  "claude-code": {
    id: "claude-code",
    title: "Claude Code",
    tagline: "Anthropic's AI coding agent - deep reasoning and architecture",
    icon: <Bot className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-orange-500/20 via-amber-500/20 to-orange-500/20",
    glowColor: "rgba(251,146,60,0.4)",
    docsUrl: "https://docs.anthropic.com/en/docs/claude-code",
    docsLabel: "Anthropic Docs",
    quickCommand: "cc",
    relatedTools: ["codex-cli", "gemini-cli", "ntm"],
  },
  "codex-cli": {
    id: "codex-cli",
    title: "Codex CLI",
    tagline: "OpenAI's coding agent - fast iteration and structured work",
    icon: <GraduationCap className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-emerald-500/20 via-teal-500/20 to-emerald-500/20",
    glowColor: "rgba(52,211,153,0.4)",
    docsUrl: "https://github.com/openai/codex",
    docsLabel: "GitHub",
    quickCommand: "cod",
    relatedTools: ["claude-code", "gemini-cli", "ntm"],
  },
  "gemini-cli": {
    id: "gemini-cli",
    title: "Gemini CLI",
    tagline: "Google's coding agent - large context exploration",
    icon: <Search className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-blue-500/20 via-indigo-500/20 to-blue-500/20",
    glowColor: "rgba(99,102,241,0.4)",
    docsUrl: "https://github.com/google-gemini/gemini-cli",
    docsLabel: "GitHub",
    quickCommand: "gmi",
    relatedTools: ["claude-code", "codex-cli", "ntm"],
  },
  ntm: {
    id: "ntm",
    title: "Named Tmux Manager",
    tagline: "The agent cockpit - spawn and orchestrate multiple agents",
    icon: <LayoutGrid className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-sky-500/20 via-blue-500/20 to-sky-500/20",
    glowColor: "rgba(56,189,248,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/named_tmux_manager",
    docsLabel: "GitHub",
    quickCommand: "ntm spawn myproject --cc=2",
    relatedTools: ["claude-code", "codex-cli", "agent-mail"],
  },
  beads: {
    id: "beads",
    title: "Beads",
    tagline: "Task graphs + robot triage for dependency-aware work tracking",
    icon: <GitBranch className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-emerald-500/20 via-teal-500/20 to-emerald-500/20",
    glowColor: "rgba(52,211,153,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/beads_viewer",
    docsLabel: "GitHub",
    quickCommand: "br ready",
    relatedTools: ["agent-mail", "ubs"],
  },
  "agent-mail": {
    id: "agent-mail",
    title: "MCP Agent Mail",
    tagline: "Gmail for agents - messaging, threads, and file reservations",
    icon: <KeyRound className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-violet-500/20 via-purple-500/20 to-violet-500/20",
    glowColor: "rgba(139,92,246,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/mcp_agent_mail",
    docsLabel: "GitHub",
    relatedTools: ["ntm", "beads", "cass"],
  },
  ubs: {
    id: "ubs",
    title: "Ultimate Bug Scanner",
    tagline: "Fast polyglot static analysis - your pre-commit quality gate",
    icon: <ShieldCheck className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-rose-500/20 via-red-500/20 to-rose-500/20",
    glowColor: "rgba(244,63,94,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/ultimate_bug_scanner",
    docsLabel: "GitHub",
    quickCommand: "ubs .",
    relatedTools: ["beads", "slb"],
  },
  cass: {
    id: "cass",
    title: "CASS",
    tagline: "Search across all your agent sessions instantly",
    icon: <Search className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-cyan-500/20 via-sky-500/20 to-cyan-500/20",
    glowColor: "rgba(34,211,238,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/coding_agent_session_search",
    docsLabel: "GitHub",
    quickCommand: "cass search 'auth error' --robot",
    relatedTools: ["cm", "agent-mail"],
  },
  cm: {
    id: "cm",
    title: "CASS Memory",
    tagline: "Procedural memory - playbooks and lessons from past sessions",
    icon: <Wrench className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-fuchsia-500/20 via-pink-500/20 to-fuchsia-500/20",
    glowColor: "rgba(217,70,239,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/cass_memory_system",
    docsLabel: "GitHub",
    quickCommand: "cm context 'my task' --json",
    relatedTools: ["cass", "beads"],
  },
  caam: {
    id: "caam",
    title: "CAAM",
    tagline: "Switch agent credentials safely without account confusion",
    icon: <Wrench className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-amber-500/20 via-orange-500/20 to-amber-500/20",
    glowColor: "rgba(251,146,60,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/coding_agent_account_manager",
    docsLabel: "GitHub",
    relatedTools: ["claude-code", "codex-cli", "gemini-cli"],
  },
  slb: {
    id: "slb",
    title: "SLB",
    tagline: "Two-person rule for dangerous commands - safety first",
    icon: <ShieldCheck className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-yellow-500/20 via-orange-500/20 to-yellow-500/20",
    glowColor: "rgba(251,191,36,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/simultaneous_launch_button",
    docsLabel: "GitHub",
    relatedTools: ["ubs", "beads", "dcg"],
  },
  dcg: {
    id: "dcg",
    title: "DCG",
    tagline: "Pre-execution safety net - blocks dangerous commands before damage",
    icon: <ShieldAlert className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-red-500/20 via-rose-500/20 to-red-500/20",
    glowColor: "rgba(244,63,94,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/destructive_command_guard",
    docsLabel: "GitHub",
    quickCommand: "dcg test 'rm -rf /' --explain",
    relatedTools: ["slb", "claude-code", "ntm"],
  },
  ru: {
    id: "ru",
    title: "Repo Updater",
    tagline: "Multi-repo sync + AI-driven commit automation",
    icon: <GitMerge className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-indigo-500/20 via-blue-500/20 to-indigo-500/20",
    glowColor: "rgba(99,102,241,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/repo_updater",
    docsLabel: "GitHub",
    quickCommand: "ru sync --parallel 4",
    relatedTools: ["ntm", "beads", "agent-mail"],
  },
  ms: {
    id: "ms",
    title: "Meta Skill",
    tagline: "Local-first knowledge management with hybrid semantic search and Git-backed audit trails",
    icon: <GraduationCap className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-purple-500/20 via-violet-500/20 to-purple-500/20",
    glowColor: "rgba(139,92,246,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/meta_skill",
    docsLabel: "GitHub",
    quickCommand: "ms install my-skill",
    relatedTools: ["jfp", "claude-code", "agent-mail"],
  },
  apr: {
    id: "apr",
    title: "Automated Plan Reviser",
    tagline: "Automated iterative spec refinement with 15+ AI review rounds",
    icon: <Wrench className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-teal-500/20 via-cyan-500/20 to-teal-500/20",
    glowColor: "rgba(45,212,191,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/automated_plan_reviser_pro",
    docsLabel: "GitHub",
    quickCommand: "apr refine plan.md",
    relatedTools: ["beads", "claude-code", "ntm"],
  },
  jfp: {
    id: "jfp",
    title: "JeffreysPrompts",
    tagline: "Battle-tested prompt library for AI agents with one-click skill install",
    icon: <GraduationCap className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-amber-500/20 via-yellow-500/20 to-amber-500/20",
    glowColor: "rgba(245,158,11,0.4)",
    docsUrl: "https://jeffreysprompts.com",
    docsLabel: "Website",
    quickCommand: "jfp list",
    relatedTools: ["ms", "claude-code", "codex-cli"],
  },
  pt: {
    id: "pt",
    title: "Process Triage",
    tagline: "Find and kill stuck/zombie processes with Bayesian scoring and decision memory",
    icon: <Wrench className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-lime-500/20 via-green-500/20 to-lime-500/20",
    glowColor: "rgba(132,204,22,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/process_triage",
    docsLabel: "GitHub",
    quickCommand: "pt --help",
    relatedTools: ["ntm", "slb", "dcg"],
  },
  srps: {
    id: "srps",
    title: "System Resource Protection Script",
    tagline: "Keep your workstation responsive under heavy agent load",
    icon: <Shield className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-yellow-500/20 via-orange-500/20 to-yellow-500/20",
    glowColor: "rgba(234, 179, 8, 0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/system_resource_protection_script",
    docsLabel: "GitHub",
    quickCommand: "sysmoni",
    relatedTools: ["ntm", "dcg", "slb"],
  },
  xf: {
    id: "xf",
    title: "X Archive Search",
    tagline: "Blazingly fast local search across your X/Twitter archive",
    icon: <Search className="h-8 w-8" aria-hidden="true" />,
    gradient: "from-slate-500/20 via-gray-500/20 to-slate-500/20",
    glowColor: "rgba(148,163,184,0.4)",
    docsUrl: "https://github.com/Dicklesworthstone/xf",
    docsLabel: "GitHub",
    quickCommand: "xf search 'keyword'",
    relatedTools: ["cass", "cm"],
  },
};

export const TOOL_IDS = Object.keys(TOOLS) as ToolId[];
