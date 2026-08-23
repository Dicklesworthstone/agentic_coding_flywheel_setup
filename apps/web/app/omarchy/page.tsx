"use client";

import Link from "next/link";
import {
  ArrowRight,
  ArrowRightLeft,
  Binary,
  BookOpen,
  ChevronRight,
  CircleSlash,
  Database,
  ExternalLink,
  GitBranch,
  Package,
  RotateCcw,
  ScrollText,
  ShieldCheck,
  Stethoscope,
  Terminal,
  Users,
  Zap,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { motion, fadeUp, springs, staggerContainer } from "@/components/motion";
import StormCanvas from "@/components/omarchy/storm-canvas";
import { staggerDelay } from "@/lib/hooks/useScrollReveal";
import CopyCommand from "@/components/omarchy/copy-command";
import { TldrSynergyDiagram } from "@/components/tldr/tldr-synergy-diagram";
import { tldrFlywheelTools } from "@/lib/tldr-content";
import { manifestTools } from "@/lib/generated/manifest-tools";

// Same command the home page shows; /install 302s to the raw install.sh.
// Without --yes the installer asks one "Proceed?" question on the TTY, which
// is the right default for someone sitting at their own laptop.
const INSTALL_COMMAND = "curl -fsSL https://agent-flywheel.com/install | bash";
const ARCH_NOTES_URL =
  "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup#omarchy-arch-support";
const GITHUB_URL = "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup";

// Tokyo Night — Omarchy's default theme. The hero is always dark (it is a
// window onto the storm), so its text colours are fixed rather than theme
// tokens; everything below the fold uses the site's normal light/dark tokens.
const TN = {
  fg: "#c0caf5",
  fgMuted: "#a9b1d6",
  green: "#9ece6a",
  cyan: "#7dcfff",
  purple: "#bb9af7",
  amber: "#e0af68",
  red: "#f7768e",
} as const;

const STATS = [
  { value: "72", label: "Modules" },
  { value: "3", label: "AI Agents" },
  { value: "35", label: "Flywheel tools" },
  { value: "1", label: "Command" },
] as const;

const FEATURES = [
  {
    icon: <Package className="h-6 w-6" />,
    title: "pacman for the system layer",
    description:
      "Base packages, CLI tools, Go, PostgreSQL, Vault, and Tailscale all come from the official Arch repos. The installer never adds apt or a third-party repo to your machine.",
    accent: TN.green,
  },
  {
    icon: <Terminal className="h-6 w-6" />,
    title: "Your prompt stays yours",
    description:
      "ACFS never replaces an existing ~/.zshrc; it appends one guarded loader line. If you use starship, the new shell initialises it and your starship.toml is left where it was.",
    accent: TN.cyan,
  },
  {
    icon: <CircleSlash className="h-6 w-6" />,
    title: "oh-my-zsh & p10k skipped",
    description:
      "On Arch the installer skips oh-my-zsh, powerlevel10k, and their plugins. You get zsh with history, completion, and the ACFS aliases, with nothing else layered onto your shell.",
    accent: TN.purple,
  },
  {
    icon: <ShieldCheck className="h-6 w-6" />,
    title: "Doctor knows the difference",
    description:
      "acfs doctor knows the Arch layout. The oh-my-zsh checks report SKIP rather than FAIL, so a clean Omarchy install passes instead of showing four false failures.",
    accent: TN.green,
  },
  {
    icon: <Binary className="h-6 w-6" />,
    title: "Prebuilt binaries, no source builds",
    description:
      "The flywheel tools install from their checksum-verified upstream installers, which ship prebuilt Linux binaries. You get the same tools and versions as on Ubuntu without compiling anything.",
    accent: TN.amber,
  },
  {
    icon: <RotateCcw className="h-6 w-6" />,
    title: "Idempotent resume",
    description:
      "If the install is interrupted, re-run the same command. Phases are checkpointed in ~/.acfs/state.json, and tools that are already installed are skipped.",
    accent: TN.red,
  },
] as const;

const ARCH_CHANGES = [
  {
    icon: <ArrowRightLeft className="h-5 w-5" />,
    title: "apt → pacman package sets",
    description:
      "Each Ubuntu package batch has a hand-checked Arch equivalent (bind for dnsutils, github-cli for gh, fd for fd-find). The package database is synced once before any installs.",
  },
  {
    icon: <ScrollText className="h-5 w-5" />,
    title: "sudoers drop-in 90-acfs",
    description:
      "Vibe mode writes passwordless sudo as a single drop-in file, validated with visudo. /etc/sudoers itself is never edited, so deleting the file reverts it.",
  },
  {
    icon: <Users className="h-5 w-5" />,
    title: "wheel group, not a sudo group",
    description:
      "Your user is added to wheel, as Arch expects. The installer configures the account you run it as and does not create an ubuntu user.",
  },
  {
    icon: <Database className="h-5 w-5" />,
    title: "Postgres via pacman + initdb",
    description:
      "Installed from the official repo, cluster initialised with initdb (UTF-8), service enabled with systemd. The PGDG apt repo is not used.",
  },
] as const;

// Mock of what `acfs doctor` prints on Omarchy — the SKIP lines are the point.
const DOCTOR_LINES: ReadonlyArray<{ status: "ok" | "skip"; label: string; note?: string }> = [
  { status: "ok", label: "zsh installed" },
  { status: "skip", label: "Oh My Zsh", note: "not used on Arch-family; existing prompt preserved" },
  { status: "skip", label: "Powerlevel10k", note: "not used on Arch-family" },
  { status: "skip", label: "zsh-autosuggestions", note: "not used on Arch-family" },
  { status: "skip", label: "zsh-syntax-highlighting", note: "not used on Arch-family" },
  { status: "ok", label: "acfs.zshrc sourced" },
  { status: "ok", label: "bun 1.3.x" },
  { status: "ok", label: "uv 0.9.x" },
  { status: "ok", label: "cargo 1.9x" },
  { status: "ok", label: "go 1.2x (pacman)" },
  { status: "ok", label: "claude / codex / agy" },
  { status: "ok", label: "ntm · am · bv · br · cass · cm · dcg · ru …" },
];

type ToolTier = "cornerstone" | "flywheel" | "thirdParty";

interface ToolEntry {
  name: string;
  description: string;
  tier: ToolTier;
  /** Project page. Flywheel tools resolve this from the manifest (see toolHref). */
  href?: string;
}

// Third-party tools are not in acfs.manifest.yaml's web metadata, so their
// project pages are listed here.
const THIRD_PARTY_HREFS: Record<string, string> = {
  claude: "https://github.com/anthropics/claude-code",
  codex: "https://github.com/openai/codex",
  agy: "https://antigravity.google/",
  opencode: "https://github.com/sst/opencode",
  omp: "https://omp.sh",
  bun: "https://github.com/oven-sh/bun",
  uv: "https://github.com/astral-sh/uv",
  cargo: "https://github.com/rust-lang/cargo",
  go: "https://github.com/golang/go",
  gh: "https://github.com/cli/cli",
  tmux: "https://github.com/tmux/tmux",
  rg: "https://github.com/BurntSushi/ripgrep",
  fzf: "https://github.com/junegunn/fzf",
  atuin: "https://github.com/atuinsh/atuin",
  zoxide: "https://github.com/ajeetdsouza/zoxide",
  gum: "https://github.com/charmbracelet/gum",
};

/** Project page for a tool: manifest href for flywheel tools, explicit map otherwise. */
function toolHref(name: string): string | undefined {
  const fromManifest = manifestTools.find(
    (tool) => tool.cliName === name || tool.cliAliases.includes(name),
  )?.href;
  return fromManifest ?? THIRD_PARTY_HREFS[name];
}

// Tier presentation: label, colour, and one line on what the tier means.
const TIERS: Record<ToolTier, { label: string; blurb: string; color: string }> = {
  cornerstone: {
    label: "Cornerstone",
    blurb: "The tools the flywheel turns on. Learn these first.",
    color: TN.green,
  },
  flywheel: {
    label: "Flywheel",
    blurb: "The rest of the Agent Flywheel stack; each one plugs into the cornerstones.",
    color: TN.cyan,
  },
  thirdParty: {
    label: "Third-party",
    blurb: "Agents, runtimes, and CLIs the stack works alongside. On Arch, most come from pacman.",
    color: TN.amber,
  },
};

const TIER_ORDER: ToolTier[] = ["cornerstone", "flywheel", "thirdParty"];

// Every entry is a binary ACFS puts on your PATH. Names come from
// lib/generated/manifest-tools.ts (cliName) — keep them in sync.
const TOOLS: ToolEntry[] = [
  // Cornerstones: the ten tools a working session runs through, in workflow order.
  { name: "ntm", description: "Named Tmux Manager: spawn and monitor agent sessions", tier: "cornerstone" },
  { name: "am", description: "MCP Agent Mail (Rust rewrite): messaging and file reservations between agents", tier: "cornerstone" },
  { name: "br", description: "beads_rust: local-first issue tracking for agents", tier: "cornerstone" },
  { name: "bv", description: "Beads Viewer: dependency-graph triage for tasks", tier: "cornerstone" },
  { name: "cass", description: "Coding Agent Session Search (CASS): every past agent session, searchable", tier: "cornerstone" },
  { name: "cm", description: "CASS Memory System: procedural memory for agents", tier: "cornerstone" },
  { name: "ubs", description: "Ultimate Bug Scanner: static checks before every commit", tier: "cornerstone" },
  { name: "dcg", description: "Destructive Command Guard: blocks rm -rf and git reset --hard in agents", tier: "cornerstone" },
  { name: "ru", description: "Repo Updater: multi-repo sync and AI-driven commits", tier: "cornerstone" },
  { name: "rch", description: "Remote Compilation Helper: offload cargo builds to a worker fleet", tier: "cornerstone" },
  // Flywheel: the rest of the Agent Flywheel stack.
  { name: "slb", description: "Simultaneous Launch Button: two-person rule for dangerous commands", tier: "flywheel" },
  { name: "caam", description: "Coding Agent Account Manager: switch agent accounts in under 100ms", tier: "flywheel" },
  { name: "fsfs", description: "FrankenSearch: hybrid lexical and semantic code search", tier: "flywheel" },
  { name: "ee", description: "Eidetic Engine: durable local memory for agents", tier: "flywheel" },
  { name: "pt", description: "Process Triage: find and kill runaway processes", tier: "flywheel" },
  { name: "ms", description: "Meta Skill: skill management with MCP integration", tier: "flywheel" },
  { name: "casr", description: "Cross-Agent Session Resumer: resume a Claude session in Codex, or vice versa", tier: "flywheel" },
  { name: "dsr", description: "Doodlestein Self-Releaser: local cross-platform release builds", tier: "flywheel" },
  { name: "asb", description: "Agent Settings Backup: git-versioned agent configs", tier: "flywheel" },
  { name: "pcr", description: "Post-Compact Reminder: re-inject instructions after context compaction", tier: "flywheel" },
  { name: "pfr", description: "Power Failure Resumer: restart agent sessions after a reboot", tier: "flywheel" },
  { name: "sbh", description: "Storage Ballast Helper: reserve disk to survive full-disk events", tier: "flywheel" },
  { name: "sysmoni", description: "System Resource Protection: deprioritizes background processes so the workstation stays responsive", tier: "flywheel" },
  { name: "fmd", description: "Franken Markdown: one binary turns Markdown into HTML and PDF", tier: "flywheel" },
  { name: "pi", description: "Pi Agent: single-binary coding agent with local model support", tier: "flywheel" },
  { name: "giil", description: "Get Image from Internet Link: pull iCloud and Dropbox shares into the terminal", tier: "flywheel" },
  { name: "csctf", description: "Chat Shared Conversation to File: archive AI chat share links as Markdown", tier: "flywheel" },
  { name: "xf", description: "X Archive Search: fast search over X/Twitter data archives", tier: "flywheel" },
  { name: "toon", description: "Token-Optimized Notation: compress source code for LLM context", tier: "flywheel" },
  { name: "rano", description: "Network Observer: monitor AI CLI network traffic", tier: "flywheel" },
  { name: "mdwb", description: "Markdown Web Browser: fetch pages as Markdown for agents", tier: "flywheel" },
  { name: "s2p", description: "Source to Prompt TUI: pack a repo into one prompt", tier: "flywheel" },
  { name: "apr", description: "Automated Plan Reviser Pro: multi-pass plan refinement", tier: "flywheel" },
  { name: "jfp", description: "JeffreysPrompts CLI: curated prompt library", tier: "flywheel" },
  { name: "brenner", description: "Brenner Bot: hypothesis-driven research sessions", tier: "flywheel" },
  // Third-party: agents, runtimes, and CLIs the stack depends on.
  { name: "claude", description: "Claude Code (Anthropic)", tier: "thirdParty" },
  { name: "codex", description: "Codex CLI (OpenAI)", tier: "thirdParty" },
  { name: "agy", description: "Antigravity CLI (Google)", tier: "thirdParty" },
  { name: "opencode", description: "OpenCode agent CLI", tier: "thirdParty" },
  { name: "omp", description: "omp: a coding agent with the IDE wired in (omp.sh)", tier: "thirdParty" },
  { name: "bun", description: "JavaScript runtime and package manager", tier: "thirdParty" },
  { name: "uv", description: "Python package manager", tier: "thirdParty" },
  { name: "cargo", description: "Rust toolchain (rustup)", tier: "thirdParty" },
  { name: "go", description: "Go toolchain (pacman)", tier: "thirdParty" },
  { name: "gh", description: "GitHub CLI (pacman)", tier: "thirdParty" },
  { name: "tmux", description: "Terminal multiplexer (pacman)", tier: "thirdParty" },
  { name: "rg", description: "ripgrep (pacman)", tier: "thirdParty" },
  { name: "fzf", description: "Fuzzy finder (pacman)", tier: "thirdParty" },
  { name: "atuin", description: "Shell history with search", tier: "thirdParty" },
  { name: "zoxide", description: "Smarter cd", tier: "thirdParty" },
  { name: "gum", description: "Glamorous shell scripts (pacman)", tier: "thirdParty" },
];

/**
 * One tool in the index. Hover/focus lifts the tile, lights the border and a
 * left accent bar in the tier colour, and brightens the description. The
 * featured (cornerstone) variant is taller with a larger name.
 */
function ToolTile({ tool, featured }: { tool: ToolEntry; featured: boolean }) {
  const { color, label } = TIERS[tool.tier];
  const href = tool.href ?? toolHref(tool.name);
  const layout = featured ? "flex flex-col gap-2 p-4 pr-9" : "flex items-baseline gap-3 py-3 pl-4 pr-9";
  const body = (
    <>
      {/* Accent bar + glow, tier-coloured, revealed on hover/focus */}
      <span
        className="pointer-events-none absolute inset-y-0 left-0 w-0.5 origin-bottom scale-y-0 transition-transform duration-300 group-hover:scale-y-100 group-focus-within:scale-y-100"
        style={{ backgroundColor: color }}
        aria-hidden="true"
      />
      <span
        className="pointer-events-none absolute inset-0 rounded-xl opacity-0 transition-opacity duration-300 group-hover:opacity-100 group-focus-within:opacity-100"
        style={{
          boxShadow: `inset 0 0 0 1px ${color}66, 0 12px 32px -16px ${color}99`,
          background: `radial-gradient(120% 80% at 0% 0%, ${color}14, transparent 60%)`,
        }}
        aria-hidden="true"
      />
      <code
        className={`relative shrink-0 font-mono font-semibold transition-colors ${featured ? "text-xl font-bold" : "text-sm"}`}
        style={{ color }}
      >
        {tool.name}
      </code>
      <span className="relative min-w-0 text-xs leading-relaxed text-muted-foreground transition-colors group-hover:text-foreground/90 group-focus-within:text-foreground/90">
        {tool.description}
      </span>
      {href ? (
        <ExternalLink
          className="absolute right-3 top-3 h-3.5 w-3.5 text-muted-foreground/0 transition-colors group-hover:text-muted-foreground/70 group-focus-within:text-muted-foreground/70"
          aria-hidden="true"
        />
      ) : null}
    </>
  );
  const shell =
    "group relative block h-full overflow-hidden rounded-xl border border-border/40 bg-card/40 transition-[border-color,background-color,box-shadow] duration-300 hover:bg-card focus-visible:bg-card focus-visible:outline-none";
  return (
    <motion.li variants={fadeUp} whileHover={{ y: -3 }} transition={springs.snappy} className="h-full">
      {href ? (
        <a
          href={href}
          target="_blank"
          rel="noopener noreferrer"
          className={`${shell} ${layout}`}
          aria-label={`${tool.name}: ${tool.description} (${label}). Opens the project page in a new tab.`}
        >
          {body}
        </a>
      ) : (
        <div className={`${shell} ${layout}`} aria-label={`${tool.name}: ${tool.description} (${label})`}>
          {body}
        </div>
      )}
    </motion.li>
  );
}

function TierBadge({ tier }: { tier: ToolTier }) {
  const { label, color } = TIERS[tier];
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 font-mono text-[10px] font-semibold uppercase tracking-wider"
      style={{ backgroundColor: `${color}1a`, color, boxShadow: `inset 0 0 0 1px ${color}40` }}
    >
      <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} aria-hidden="true" />
      {label}
    </span>
  );
}

function SectionHeading({ eyebrow, title }: { eyebrow?: string; title: string }) {
  return (
    <motion.div
      className="mb-12 text-center"
      initial={{ opacity: 0, y: 20 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-80px" }}
      transition={springs.smooth}
    >
      {eyebrow ? (
        <p className="mb-2 font-mono text-xs uppercase tracking-widest text-[#7dcfff]">{eyebrow}</p>
      ) : null}
      <h2 className="font-mono text-3xl font-bold tracking-tight sm:text-4xl">{title}</h2>
    </motion.div>
  );
}

const footerLink =
  "rounded-sm underline-offset-4 transition-colors hover:text-foreground hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60";

export default function OmarchyPage() {
  return (
    <div className="relative min-h-screen overflow-x-clip bg-background">
      <main>
        {/* ============================= HERO ============================= */}
        {/* Fixed min-height + absolutely-positioned canvas: zero layout shift.
            Always dark, regardless of site theme — see TN above. */}
        <section className="relative flex min-h-[100svh] flex-col overflow-hidden bg-gradient-to-b from-[#0a0e1a] via-[#10121f] to-[#1a1b26] text-[#c0caf5]">
          <StormCanvas className="absolute inset-0 h-full w-full" />

          {/* Readability scrims — solid navy under the text column, clearing
              toward the storm on the right; vertical fade on small screens */}
          <div
            className="pointer-events-none absolute inset-0 hidden md:block"
            aria-hidden="true"
            style={{
              background:
                "linear-gradient(90deg, rgba(10,14,26,0.96) 0%, rgba(10,14,26,0.88) 30%, rgba(10,14,26,0.45) 52%, rgba(10,14,26,0) 72%)",
            }}
          />
          <div
            className="pointer-events-none absolute inset-0 md:hidden"
            aria-hidden="true"
            style={{
              background:
                "linear-gradient(0deg, rgba(10,14,26,0.95) 0%, rgba(10,14,26,0.82) 40%, rgba(10,14,26,0.25) 100%)",
            }}
          />
          {/* Scanlines — terminal flavor, barely-there */}
          <div
            className="pointer-events-none absolute inset-0 opacity-[0.04]"
            aria-hidden="true"
            style={{
              backgroundImage:
                "repeating-linear-gradient(0deg, #c0caf5 0px, #c0caf5 1px, transparent 1px, transparent 4px)",
            }}
          />

          {/* Navigation — same items as the home page, overlaid on the storm */}
          <nav className="relative z-20 mx-auto flex w-full max-w-7xl items-center justify-between px-6 py-6">
            <Link href="/" className="flex items-center gap-2 rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7dcfff]/60">
              <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-[#7dcfff]/15">
                <Terminal className="h-5 w-5 text-[#7dcfff]" />
              </div>
              <span className="font-mono text-lg font-bold tracking-tight">Agent Flywheel</span>
            </Link>
            <div className="flex items-center gap-2 sm:gap-4">
              <a
                href={GITHUB_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="flex h-11 w-11 items-center justify-center rounded-lg text-[#a9b1d6] transition-colors hover:bg-white/5 hover:text-[#c0caf5] sm:h-auto sm:w-auto sm:rounded-none sm:bg-transparent sm:hover:bg-transparent"
                aria-label="GitHub"
              >
                <GitBranch className="h-5 w-5 sm:hidden" />
                <span className="hidden text-sm sm:inline">GitHub</span>
              </a>
              <Link
                href="/learn"
                className="flex h-11 w-11 items-center justify-center rounded-lg text-[#a9b1d6] transition-colors hover:bg-white/5 hover:text-[#c0caf5] sm:h-auto sm:w-auto sm:gap-1 sm:rounded-none sm:bg-transparent sm:hover:bg-transparent"
                aria-label="Learn"
              >
                <BookOpen className="h-5 w-5 sm:h-4 sm:w-4" />
                <span className="hidden text-sm sm:inline">Learn</span>
              </Link>
              <Link
                href="/tldr"
                className="flex h-11 w-11 items-center justify-center rounded-lg text-[#a9b1d6] transition-colors hover:bg-white/5 hover:text-[#c0caf5] sm:h-auto sm:w-auto sm:gap-1 sm:rounded-none sm:bg-transparent sm:hover:bg-transparent"
                aria-label="TL;DR"
              >
                <Zap className="h-5 w-5 sm:h-4 sm:w-4" />
                <span className="hidden text-sm sm:inline">TL;DR</span>
              </Link>
              <Button
                asChild
                size="sm"
                variant="outline"
                className="border-[#9ece6a]/40 bg-transparent text-[#c0caf5] hover:bg-[#9ece6a]/10 hover:text-[#c0caf5]"
              >
                <Link href="/tldr">
                  <span className="hidden sm:inline">Tool Stack</span>
                  <span className="sm:hidden">Tools</span>
                  <ChevronRight className="ml-1 h-4 w-4" />
                </Link>
              </Button>
            </div>
          </nav>

          {/* Text column sits left on the scrim; the storm owns the right side */}
          <div className="relative z-10 mx-auto grid w-full max-w-7xl flex-1 grid-cols-1 items-center px-6 pb-24 pt-8 lg:grid-cols-[minmax(0,42rem)_1fr]">
            <motion.div
              variants={staggerContainer}
              initial="hidden"
              animate="visible"
              className="flex w-full flex-col items-start text-left"
            >
              <motion.div
                className="mb-6 inline-flex items-center gap-2 rounded-full border border-[#9ece6a]/30 bg-[#9ece6a]/10 px-4 py-1.5 font-mono text-xs tracking-widest text-[#9ece6a]"
                variants={fadeUp}
              >
                OMARCHY · ARCH LINUX · HYPRLAND
              </motion.div>

              <motion.h1
                className="mb-6 font-mono text-5xl font-bold leading-[1.06] tracking-tighter sm:text-6xl xl:text-[4.25rem]"
                variants={fadeUp}
              >
                <span className="text-white">The Flywheel,</span>
                <br />
                <span className="text-[#9ece6a]">native on Omarchy.</span>
              </motion.h1>

              <motion.p
                className="mb-8 max-w-xl text-lg leading-relaxed text-[#c0caf5]/85"
                variants={fadeUp}
              >
                The same one-liner as on Ubuntu. The installer detects Arch and Omarchy, installs
                the system layer with <span className="font-mono text-[#9ece6a]">pacman</span>,
                keeps your <span className="font-mono text-[#e0af68]">starship</span> prompt, and
                skips <span className="font-mono">oh-my-zsh</span>. All 72 modules, three coding
                agents, and the full tool stack.
              </motion.p>

              <motion.div className="mb-8 w-full max-w-xl" variants={fadeUp}>
                <CopyCommand command={INSTALL_COMMAND} />
              </motion.div>

              <motion.div className="flex flex-col gap-3 sm:flex-row" variants={fadeUp}>
                <Button
                  asChild
                  size="lg"
                  className="group relative overflow-hidden bg-[#9ece6a] text-[#0a0e1a] hover:bg-[#9ece6a]/90"
                >
                  <a href="#what-changes">
                    <span className="relative z-10 flex items-center gap-2">
                      What changes on Arch
                      <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-y-0.5" />
                    </span>
                  </a>
                </Button>
                <Button
                  asChild
                  size="lg"
                  variant="outline"
                  className="border-[#c0caf5]/20 bg-transparent text-[#c0caf5] hover:bg-white/5 hover:text-[#c0caf5]"
                >
                  <a href={ARCH_NOTES_URL} target="_blank" rel="noopener noreferrer">
                    <GitBranch className="mr-2 h-4 w-4" />
                    Read the Arch notes
                  </a>
                </Button>
              </motion.div>

              <motion.p className="mt-6 font-mono text-xs text-[#a9b1d6]/70" variants={fadeUp}>
                Run it as your own user; the installer calls sudo only for the steps that need it.
              </motion.p>
            </motion.div>
          </div>
        </section>

        {/* ========================== STATS STRIP ========================== */}
        <section className="border-y border-border/30 bg-card/30 py-12">
          <div className="mx-auto grid max-w-5xl grid-cols-2 gap-8 px-6 sm:grid-cols-4">
            {STATS.map((stat, index) => (
              <motion.div
                key={stat.label}
                className="flex flex-col items-center gap-1 text-center"
                initial={{ opacity: 0, y: 16 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ ...springs.snappy, delay: staggerDelay(index, 0.08) }}
              >
                <span className="font-mono text-3xl font-bold text-gradient-cyan sm:text-4xl">
                  {stat.value}
                </span>
                <span className="font-mono text-xs uppercase tracking-widest text-muted-foreground">
                  {stat.label}
                </span>
              </motion.div>
            ))}
          </div>
        </section>

        {/* ======================= NATIVE ON ARCH GRID ====================== */}
        <section className="mx-auto max-w-7xl px-6 py-24">
          <SectionHeading eyebrow="what arch users get" title="Native on Arch" />
          <motion.div
            className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3"
            variants={staggerContainer}
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true, margin: "-80px" }}
          >
            {FEATURES.map((feature, index) => (
              <motion.div
                key={feature.title}
                className="group relative overflow-hidden rounded-2xl border border-border/50 bg-card/50 p-6 backdrop-blur-sm transition-all duration-300 hover:border-primary/30"
                variants={fadeUp}
                transition={{ ...springs.snappy, delay: staggerDelay(index, 0.08) }}
              >
                <div
                  className="mb-4 inline-flex rounded-xl p-3"
                  style={{ backgroundColor: `${feature.accent}1a`, color: feature.accent }}
                >
                  {feature.icon}
                </div>
                <h3 className="mb-2 font-mono text-lg font-semibold tracking-tight">{feature.title}</h3>
                <p className="text-sm leading-relaxed text-muted-foreground">{feature.description}</p>
              </motion.div>
            ))}
          </motion.div>
        </section>

        {/* ===================== WHAT CHANGES ON ARCH ======================= */}
        <section id="what-changes" className="scroll-mt-8 border-y border-border/30 bg-card/20 py-20">
          <div className="mx-auto max-w-7xl px-6">
            <SectionHeading eyebrow="the details" title="What changes on Arch" />
            <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
              {ARCH_CHANGES.map((change, index) => (
                <motion.div
                  key={change.title}
                  className="rounded-xl border border-border/50 bg-card/50 p-5"
                  initial={{ opacity: 0, y: 16 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ ...springs.snappy, delay: staggerDelay(index, 0.07) }}
                >
                  <div className="mb-3 inline-flex rounded-lg bg-[#7dcfff]/10 p-2 text-[#7dcfff]">
                    {change.icon}
                  </div>
                  <h3 className="mb-1 font-mono text-sm font-semibold">{change.title}</h3>
                  <p className="text-xs leading-relaxed text-muted-foreground">{change.description}</p>
                </motion.div>
              ))}
            </div>

            {/* Doctor output mock — shows the SKIP-not-FAIL behaviour concretely */}
            <motion.div
              className="mx-auto mt-12 max-w-3xl"
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-60px" }}
              transition={springs.smooth}
            >
              <div className="terminal-window text-left shadow-2xl ring-1 ring-[#9ece6a]/10">
                <div className="terminal-header">
                  <div className="terminal-dot terminal-dot-red" aria-hidden="true" />
                  <div className="terminal-dot terminal-dot-yellow" aria-hidden="true" />
                  <div className="terminal-dot terminal-dot-green" aria-hidden="true" />
                  <span className="ml-3 inline-flex items-center gap-1.5 font-mono text-xs text-[#a9b1d6]/70">
                    <Stethoscope className="h-3.5 w-3.5" aria-hidden="true" />
                    acfs doctor
                  </span>
                </div>
                <div className="overflow-x-auto p-5 font-mono text-xs leading-6 text-[#c0caf5] sm:text-sm">
                  <p className="mb-2 text-[#a9b1d6]/70">
                    <span className="select-none text-[#9ece6a]">$ </span>acfs doctor
                  </p>
                  <ul className="space-y-0.5">
                    {DOCTOR_LINES.map((line) => (
                      <li key={line.label} className="flex flex-wrap items-baseline gap-x-3">
                        {line.status === "ok" ? (
                          <span className="shrink-0 font-bold text-[#9ece6a]">✔ OK  </span>
                        ) : (
                          <span className="shrink-0 font-bold text-[#a9b1d6]/70">○ SKIP</span>
                        )}
                        <span className={line.status === "skip" ? "text-[#a9b1d6]/70" : ""}>{line.label}</span>
                        {line.note ? (
                          <span className="basis-full pl-[4.5rem] text-[11px] italic text-[#a9b1d6]/50 sm:basis-auto sm:pl-0">
                            — {line.note}
                          </span>
                        ) : null}
                      </li>
                    ))}
                  </ul>
                  <p className="mt-3 text-[#a9b1d6]/70">
                    Overall: <span className="text-[#9ece6a]">all checks passed</span>
                    <span className="text-[#a9b1d6]/50"> (4 skipped — Arch-family)</span>
                  </p>
                </div>
              </div>
              <p className="mt-4 text-center text-xs text-muted-foreground">
                Representative output; versions and the exact check list depend on your install.
              </p>
            </motion.div>

            <motion.p
              className="mt-10 text-center text-sm text-muted-foreground"
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={springs.smooth}
            >
              Full detail in the{" "}
              <a
                href={ARCH_NOTES_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-1 text-primary hover:underline"
              >
                README&apos;s Omarchy (Arch) support section
                <ArrowRight className="h-3 w-3" />
              </a>
              .
            </motion.p>
          </div>
        </section>

        {/* ===================== HOW THE TOOLS CONNECT ====================== */}
        <section className="mx-auto max-w-7xl px-6 py-24">
          <SectionHeading eyebrow="one system, not a pile of binaries" title="How the tools feed each other" />
          <div className="grid items-center gap-10 lg:grid-cols-2 lg:gap-14">
            <motion.div
              className="space-y-4 text-muted-foreground"
              initial={{ opacity: 0, x: -16 }}
              whileInView={{ opacity: 1, x: 0 }}
              viewport={{ once: true, margin: "-60px" }}
              transition={springs.smooth}
            >
              <p>
                The inner ring is the loop a working session runs through:{" "}
                <code className="font-mono text-[#9ece6a]">ntm</code> spawns the agents,{" "}
                <code className="font-mono text-[#9ece6a]">am</code> lets them message each other and
                reserve files, <code className="font-mono text-[#9ece6a]">bv</code> picks the next
                task from the Beads graph, <code className="font-mono text-[#9ece6a]">ubs</code> scans
                the diff before commit, and <code className="font-mono text-[#9ece6a]">cass</code> and{" "}
                <code className="font-mono text-[#9ece6a]">cm</code> turn every finished session into
                searchable history and procedural memory for the next one.
              </p>
              <p>
                The outer ring is the support crew: guards (<code className="font-mono">dcg</code>,{" "}
                <code className="font-mono">slb</code>), repo sync (<code className="font-mono">ru</code>),
                account switching (<code className="font-mono">caam</code>), and the rest. Builds go through{" "}
                <code className="font-mono text-[#9ece6a]">rch</code>, which ships cargo work to remote
                workers so twenty agents compiling at once do not flatten the box. Each tool exists because
                running many agents at once exposed a specific problem.
              </p>
              <p className="text-sm">
                Every line in the diagram is a real integration: shared IDs, MCP calls, or files one
                tool writes and another reads. Hover a node to see its connections.
              </p>
            </motion.div>
            <motion.div
              className="mx-auto w-full max-w-md lg:max-w-none"
              initial={{ opacity: 0, x: 16 }}
              whileInView={{ opacity: 1, x: 0 }}
              viewport={{ once: true, margin: "-60px" }}
              transition={springs.smooth}
            >
              <TldrSynergyDiagram tools={tldrFlywheelTools} />
            </motion.div>
          </div>
        </section>

        {/* ======================== TOOL STORM INDEX ======================== */}
        <section className="border-t border-border/30 bg-card/20 py-24">
          <div className="mx-auto max-w-7xl px-6">
            <SectionHeading eyebrow="the storm, indexed" title="Every tool in the vortex" />
            <motion.p
              className="mx-auto mb-8 max-w-2xl text-center text-muted-foreground"
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={springs.smooth}
            >
              Every name in the storm above is a binary on your PATH after install. ACFS leaves your
              desktop, shell, and prompt alone; the first two tiers are what it adds, and the third is
              what it works alongside.
            </motion.p>

            {/* Legend */}
            <motion.ul
              className="mx-auto mb-12 flex max-w-4xl flex-col gap-3 sm:flex-row sm:justify-center sm:gap-6"
              initial={{ opacity: 0, y: 12 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={springs.smooth}
              aria-label="Tool tiers"
            >
              {TIER_ORDER.map((tier) => (
                <li key={tier} className="flex items-start gap-3 sm:max-w-xs">
                  <TierBadge tier={tier} />
                  <span className="text-xs leading-relaxed text-muted-foreground">{TIERS[tier].blurb}</span>
                </li>
              ))}
            </motion.ul>

            <div className="space-y-14">
              {TIER_ORDER.map((tier) => {
                const tools = TOOLS.filter((tool) => tool.tier === tier);
                const { label, color } = TIERS[tier];
                return (
                  <div key={tier}>
                    <motion.div
                      className="mb-5 flex items-center gap-3"
                      initial={{ opacity: 0 }}
                      whileInView={{ opacity: 1 }}
                      viewport={{ once: true }}
                      transition={springs.smooth}
                    >
                      <h3 className="font-mono text-lg font-semibold tracking-tight" style={{ color }}>
                        {label}
                      </h3>
                      <span className="font-mono text-xs text-muted-foreground">{tools.length} tools</span>
                      <span className="h-px flex-1" style={{ background: `linear-gradient(90deg, ${color}66, transparent)` }} aria-hidden="true" />
                    </motion.div>
                    <motion.ul
                      className={
                        tier === "cornerstone"
                          ? "grid gap-4 sm:grid-cols-2 lg:grid-cols-5"
                          : "grid gap-3 sm:grid-cols-2 lg:grid-cols-3"
                      }
                      variants={staggerContainer}
                      initial="hidden"
                      whileInView="visible"
                      viewport={{ once: true, margin: "-60px" }}
                    >
                      {tools.map((tool) => (
                        <ToolTile key={tool.name} tool={tool} featured={tier === "cornerstone"} />
                      ))}
                    </motion.ul>
                  </div>
                );
              })}
            </div>

            <motion.p
              className="mt-12 text-center text-sm text-muted-foreground"
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={springs.smooth}
            >
              Want the long version of each one?{" "}
              <Link href="/tldr" className="inline-flex items-center gap-1 text-primary hover:underline">
                Read the TL;DR
                <ArrowRight className="h-3 w-3" />
              </Link>
            </motion.p>
          </div>
        </section>

        {/* =========================== FINAL CTA ============================ */}
        <section className="relative overflow-hidden border-t border-border/30 py-24">
          <div
            className="pointer-events-none absolute left-1/2 top-1/2 h-[500px] w-[700px] -translate-x-1/2 -translate-y-1/2 rounded-full blur-[120px]"
            style={{ backgroundColor: "rgba(158, 206, 106, 0.06)" }}
            aria-hidden="true"
          />
          <div className="relative mx-auto max-w-3xl px-6 text-center">
            <motion.div
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={springs.smooth}
              className="flex flex-col items-center"
            >
              <h2 className="mb-4 font-mono text-3xl font-bold tracking-tight sm:text-4xl">
                Get on the Flywheel!
              </h2>
              <p className="mb-8 max-w-xl text-muted-foreground">
                One command sets up your Arch or Omarchy machine for agentic coding. Re-run it
                any time; it skips whatever is already installed.
              </p>
              <div className="mb-8 w-full max-w-xl">
                <CopyCommand command={INSTALL_COMMAND} />
              </div>
              <div className="flex flex-col items-center gap-3 sm:flex-row">
                <Button asChild size="lg" variant="outline" className="border-border/50 hover:bg-muted/50">
                  <Link href="/learn">
                    <BookOpen className="mr-2 h-4 w-4" />
                    Learn the workflow
                  </Link>
                </Button>
                <Button
                  asChild
                  size="lg"
                  className="group relative overflow-hidden bg-primary text-primary-foreground hover:bg-primary/90"
                >
                  <Link href="/wizard/os-selection">
                    <span className="relative z-10 flex items-center gap-2">
                      Prefer a VPS? Start the Wizard
                      <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-1" />
                    </span>
                  </Link>
                </Button>
              </div>
            </motion.div>
          </div>
        </section>

        {/* ============================= FOOTER ============================= */}
        <footer className="border-t border-border/30 py-12">
          <div className="mx-auto max-w-7xl px-6">
            <div className="flex flex-col items-center gap-8 text-center sm:flex-row sm:justify-between sm:text-left">
              <div className="flex items-center gap-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/20">
                  <Terminal className="h-4 w-4 text-primary" />
                </div>
                <span className="font-mono text-sm font-bold">Agent Flywheel</span>
              </div>

              <div className="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-sm text-muted-foreground">
                <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer" className={footerLink}>
                  GitHub
                </a>
                <Link href="/learn" className={footerLink}>
                  Learning Hub
                </Link>
                <Link href="/tldr" className={footerLink}>
                  Tools
                </Link>
                <Link href="/tldr" className={footerLink}>
                  TL;DR
                </Link>
                <Link href="/" className={footerLink}>
                  Home
                </Link>
                <a href={ARCH_NOTES_URL} target="_blank" rel="noopener noreferrer" className={footerLink}>
                  Arch notes
                </a>
              </div>

              <p className="text-xs text-muted-foreground">
                Created by{" "}
                <a
                  href="https://jeffreyemanuel.com/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-primary hover:underline"
                >
                  Jeffrey Emanuel
                </a>
              </p>
            </div>
          </div>
        </footer>
      </main>
    </div>
  );
}
