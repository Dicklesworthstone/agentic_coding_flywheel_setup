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
  { value: "40+", label: "Stack tools" },
  { value: "1", label: "Command" },
] as const;

const FEATURES = [
  {
    icon: <Package className="h-6 w-6" />,
    title: "pacman for the system layer",
    description:
      "Base packages, CLI tools, Go, PostgreSQL, Vault, Tailscale — everything that is a system package comes from the official Arch repos. No apt, no third-party repos bolted onto your box.",
    accent: TN.green,
  },
  {
    icon: <Terminal className="h-6 w-6" />,
    title: "Your prompt stays yours",
    description:
      "An existing ~/.zshrc is never replaced — ACFS appends one guarded loader line. Running starship? It is initialised in the new shell and your config is left exactly where it was.",
    accent: TN.cyan,
  },
  {
    icon: <CircleSlash className="h-6 w-6" />,
    title: "oh-my-zsh & p10k skipped by design",
    description:
      "On Arch the installer deliberately skips oh-my-zsh, powerlevel10k and their plugins. You get zsh with history, completion and the ACFS aliases — no framework takeover.",
    accent: TN.purple,
  },
  {
    icon: <ShieldCheck className="h-6 w-6" />,
    title: "Doctor knows the difference",
    description:
      "acfs doctor understands the Arch layout: oh-my-zsh and friends report as SKIP, not FAIL, so a clean Omarchy install reads green instead of crying wolf.",
    accent: TN.green,
  },
  {
    icon: <Binary className="h-6 w-6" />,
    title: "Prebuilt binaries over source builds",
    description:
      "The flywheel tools install from their checksum-verified upstream installers, which ship prebuilt Linux binaries. Same tools, same versions as on Ubuntu — minus the compile time.",
    accent: TN.amber,
  },
  {
    icon: <RotateCcw className="h-6 w-6" />,
    title: "Idempotent resume",
    description:
      "Interrupted mid-install? Re-run the same command. Phases are checkpointed in ~/.acfs/state.json and already-installed tools are detected and skipped.",
    accent: TN.red,
  },
] as const;

const ARCH_CHANGES = [
  {
    icon: <ArrowRightLeft className="h-5 w-5" />,
    title: "apt → pacman package sets",
    description:
      "Each Ubuntu package batch has a hand-checked Arch equivalent (bind for dnsutils, github-cli for gh, fd for fd-find…). The database is synced once up front.",
  },
  {
    icon: <ScrollText className="h-5 w-5" />,
    title: "sudoers drop-in 90-acfs",
    description:
      "Vibe mode writes passwordless sudo as a single reversible drop-in, validated with visudo — your /etc/sudoers is never edited.",
  },
  {
    icon: <Users className="h-5 w-5" />,
    title: "wheel, not sudo",
    description:
      "Your user joins wheel the Arch way. The installer configures the account you run it as — it never invents an ubuntu user on your laptop.",
  },
  {
    icon: <Database className="h-5 w-5" />,
    title: "Postgres via pacman + initdb",
    description:
      "Installed from the official repo, cluster initialised with initdb (UTF-8), service enabled with systemd — no PGDG apt repo.",
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

interface ToolEntry {
  name: string;
  description: string;
}

// Every entry is a binary ACFS puts on your PATH. Names come from
// lib/generated/manifest-tools.ts (cliName) — keep them in sync.
const TOOLS: ToolEntry[] = [
  { name: "ntm", description: "Named Tmux Manager — agent cockpit for multi-agent sessions" },
  { name: "am", description: "MCP Agent Mail — agents that message and reserve files" },
  { name: "br", description: "Beads — local-first issue tracking for agents" },
  { name: "bv", description: "Beads Viewer — graph-theory triage for tasks" },
  { name: "ubs", description: "Ultimate Bug Scanner" },
  { name: "cass", description: "Coding Agent Session Search" },
  { name: "cm", description: "CASS Memory System — procedural memory" },
  { name: "caam", description: "Coding Agent Account Manager — sub-100ms auth switching" },
  { name: "slb", description: "Simultaneous Launch Button — two-person rule for dangerous commands" },
  { name: "dcg", description: "Destructive Command Guard" },
  { name: "ru", description: "Repo Updater" },
  { name: "rch", description: "Remote Compilation Helper" },
  { name: "fsfs", description: "FrankenSearch — hybrid code search" },
  { name: "pt", description: "Process Triage" },
  { name: "ms", description: "Meta Skill — skills about skills" },
  { name: "casr", description: "Cross-Agent Session Resumer" },
  { name: "dsr", description: "Doodlestein Self-Releaser" },
  { name: "asb", description: "Agent Settings Backup" },
  { name: "pcr", description: "Post-Compact Reminder" },
  { name: "ee", description: "Eidetic Engine — total recall for repos" },
  { name: "fmd", description: "Franken Markdown" },
  { name: "pi", description: "Pi Agent (Rust)" },
  { name: "pfr", description: "Power Failure Resumer" },
  { name: "sbh", description: "Storage Ballast Helper — disk-pressure defense" },
  { name: "wa", description: "WezTerm Automata — terminal hypervisor" },
  { name: "giil", description: "Get Image from Internet Link" },
  { name: "csctf", description: "Chat Shared Conversation to File" },
  { name: "xf", description: "X Archive Search" },
  { name: "toon", description: "Token-Optimized Notation" },
  { name: "rano", description: "Network Observer" },
  { name: "mdwb", description: "Markdown Web Browser" },
  { name: "s2p", description: "Source to Prompt TUI" },
  { name: "sysmoni", description: "System Resource Protection — live resource monitor" },
  { name: "apr", description: "Automated Plan Reviser Pro" },
  { name: "jfp", description: "JeffreysPrompts CLI" },
  { name: "brenner", description: "Brenner Bot" },
  { name: "opencode", description: "OpenCode agent CLI" },
  { name: "claude", description: "Claude Code" },
  { name: "codex", description: "OpenAI Codex CLI" },
  { name: "agy", description: "Google Antigravity CLI" },
  { name: "bun", description: "The JavaScript runtime" },
  { name: "uv", description: "Python packaging, fast" },
  { name: "cargo", description: "Rust toolchain (rustup)" },
  { name: "go", description: "Go toolchain (pacman)" },
  { name: "gh", description: "GitHub CLI (pacman)" },
  { name: "gum", description: "Glamorous shell scripts (pacman)" },
  { name: "tmux", description: "Terminal multiplexer (pacman)" },
];

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

          {/* Vignette to keep text legible over the storm */}
          <div
            className="pointer-events-none absolute inset-0"
            aria-hidden="true"
            style={{
              background:
                "radial-gradient(ellipse at center, transparent 35%, rgba(10, 14, 26, 0.55) 78%, rgba(10, 14, 26, 0.9) 100%)",
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
                <Link href="/tools">
                  <span className="hidden sm:inline">Tool Stack</span>
                  <span className="sm:hidden">Tools</span>
                  <ChevronRight className="ml-1 h-4 w-4" />
                </Link>
              </Button>
            </div>
          </nav>

          <div className="relative z-10 mx-auto flex w-full max-w-5xl flex-1 items-center px-6 pb-24 pt-8 text-center">
            <motion.div
              variants={staggerContainer}
              initial="hidden"
              animate="visible"
              className="flex w-full flex-col items-center"
            >
              <motion.div
                className="mb-6 inline-flex items-center gap-2 rounded-full border border-[#9ece6a]/30 bg-[#9ece6a]/10 px-4 py-1.5 font-mono text-xs tracking-widest text-[#9ece6a]"
                variants={fadeUp}
              >
                OMARCHY · ARCH LINUX · HYPRLAND
              </motion.div>

              <motion.h1
                className="mb-6 font-mono text-4xl font-bold leading-tight tracking-tight sm:text-5xl lg:text-6xl"
                variants={fadeUp}
              >
                <span className="text-[#c0caf5]">The Flywheel,</span>
                <br />
                <span className="bg-gradient-to-r from-[#9ece6a] via-[#7dcfff] to-[#bb9af7] bg-clip-text text-transparent">
                  native on Omarchy.
                </span>
              </motion.h1>

              <motion.p
                className="mb-8 max-w-2xl text-lg leading-relaxed text-[#a9b1d6]"
                variants={fadeUp}
              >
                Same one-liner, same flywheel. The installer detects Arch and Omarchy, installs the
                system layer with <span className="font-mono text-[#9ece6a]">pacman</span>, keeps
                your <span className="font-mono text-[#e0af68]">starship</span> prompt, and skips{" "}
                <span className="font-mono">oh-my-zsh</span>. Seventy-two modules of agentic coding
                firepower, installed the Arch way.
              </motion.p>

              <motion.div className="mb-8 w-full max-w-2xl" variants={fadeUp}>
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
                Run it as your own user — the installer uses sudo when it needs to.
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
          <SectionHeading eyebrow="why arch users smile" title="Native on Arch, not ported to it" />
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
            <SectionHeading eyebrow="no hand-waving" title="What actually changes on Arch" />
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
                Representative output — versions and the exact check list depend on your install.
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

        {/* ======================== TOOL STORM INDEX ======================== */}
        <section className="mx-auto max-w-7xl px-6 py-24">
          <SectionHeading eyebrow="the storm, indexed" title="Every tool in the vortex" />
          <motion.p
            className="mx-auto mb-12 max-w-2xl text-center text-muted-foreground"
            initial={{ opacity: 0 }}
            whileInView={{ opacity: 1 }}
            viewport={{ once: true }}
            transition={springs.smooth}
          >
            The names swirling above aren&apos;t decoration — each one is a binary on your PATH after
            install. Your desktop, shell and prompt are yours; this is what ACFS adds.
          </motion.p>
          <motion.ul
            className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3"
            variants={staggerContainer}
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true, margin: "-60px" }}
          >
            {TOOLS.map((tool) => (
              <motion.li
                key={tool.name}
                className="flex items-baseline gap-3 rounded-lg border border-border/40 bg-card/40 px-4 py-3 transition-colors hover:border-[#9ece6a]/30 hover:bg-card/70"
                variants={fadeUp}
              >
                <code className="shrink-0 font-mono text-sm font-semibold text-[#9ece6a]">
                  {tool.name}
                </code>
                <span className="min-w-0 text-xs leading-relaxed text-muted-foreground">
                  {tool.description}
                </span>
              </motion.li>
            ))}
          </motion.ul>
          <motion.p
            className="mt-8 text-center text-sm text-muted-foreground"
            initial={{ opacity: 0 }}
            whileInView={{ opacity: 1 }}
            viewport={{ once: true }}
            transition={springs.smooth}
          >
            Want the long version of each one?{" "}
            <Link href="/tools" className="inline-flex items-center gap-1 text-primary hover:underline">
              Browse the tool catalog
              <ArrowRight className="h-3 w-3" />
            </Link>
          </motion.p>
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
                Ride the storm.
              </h2>
              <p className="mb-8 max-w-xl text-muted-foreground">
                One command turns your Arch or Omarchy machine into a fully-configured agentic
                coding environment. Re-run it any time — it only ever moves forward.
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
                <Link href="/tools" className={footerLink}>
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
