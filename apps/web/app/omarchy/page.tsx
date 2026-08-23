import type { Metadata } from "next";
import Link from "next/link";
import {
  ArrowRight,
  ArrowRightLeft,
  Binary,
  CircleSlash,
  Database,
  GitBranch,
  Package,
  RotateCcw,
  ScrollText,
  ShieldCheck,
import { motion, fadeUp, springs, staggerContainer } from "@/components/motion";
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { motion } from "@/components/motion";
import { fadeUp, springs, staggerContainer } from "@/components/motion";
import { staggerDelay } from "@/lib/hooks/useScrollReveal";
import StormCanvas from "@/components/omarchy/storm-canvas";
import CopyCommand from "@/components/omarchy/copy-command";

const INSTALL_COMMAND = "curl -fsSL https://agent-flywheel.com/install | bash";
const ARCH_NOTES_URL =
  "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup#omarchy-arch-support";

export const metadata: Metadata = {
  title: "ACFS on Omarchy — The Flywheel, Native on Arch",
  description:
    "The Agentic Coding Flywheel Setup runs natively on Omarchy and Arch Linux: pacman-native packages, your starship prompt untouched, oh-my-zsh skipped by design, doctor-verified with zero failures. One command.",
  alternates: {
    canonical: "/omarchy",
  },
  openGraph: {
    title: "ACFS on Omarchy — The Flywheel, Native on Arch",
    description:
      "72 modules · 3 AI agents · 30+ tools · 1 command. The full agentic coding flywheel, native on Arch — no apt, no oh-my-zsh, no compromises.",
    url: "/omarchy",
    siteName: "Agent Flywheel",
    type: "website",
  },
};

const STATS = [
  { value: "72", label: "Modules" },
  { value: "3", label: "AI Agents" },
  { value: "30+", label: "Tools" },
  { value: "1", label: "Command" },
] as const;

const FEATURES = [
  {
    icon: <Package className="h-6 w-6" />,
    title: "pacman-native packages",
    description:
      "Everything installs through pacman and the AUR where possible — no apt, no foreign package managers squatting on your system.",
    accent: "#9ece6a",
  },
  {
    icon: <Terminal className="h-6 w-6" />,
    title: "Your starship prompt stays yours",
    description:
      "Already running starship? ACFS detects it and leaves your config untouched. Your prompt is exactly how you left it.",
    accent: "#7dcfff",
  },
  {
    icon: <CircleSlash className="h-6 w-6" />,
    title: "oh-my-zsh & p10k skipped by design",
    description:
      "On Arch the installer deliberately skips oh-my-zsh and powerlevel10k. No framework takeover — just zsh, configured cleanly.",
    accent: "#bb9af7",
  },
  {
    icon: <ShieldCheck className="h-6 w-6" />,
    title: "Doctor-verified, 0 failures",
    description:
      "The built-in doctor runs a full post-install verification matrix on Arch. Every check green before you write a line of code.",
    accent: "#9ece6a",
  },
  {
    icon: <Binary className="h-6 w-6" />,
    title: "Prebuilt binaries over source builds",
    description:
      "Where upstream ships prebuilts, ACFS uses them — faster installs, fewer compiler toolchain surprises, same result.",
    accent: "#e0af68",
  },
  {
    icon: <RotateCcw className="h-6 w-6" />,
    title: "Idempotent resume",
    description:
      "Interrupted mid-install? Re-run the same command. Phases detect completed work and resume exactly where they stopped.",
    accent: "#f7768e",
  },
] as const;

const ARCH_CHANGES = [
  {
    icon: <ArrowRightLeft className="h-5 w-5" />,
    title: "apt → pacman name maps",
    description: "Every Ubuntu package name maps to its Arch equivalent automatically.",
  },
  {
    icon: <ScrollText className="h-5 w-5" />,
    title: "sudoers drop-in 90-acfs",
    description: "Passwordless sudo lands as a single reversible drop-in file — never an edited sudoers.",
  },
  {
    icon: <Users className="h-5 w-5" />,
    title: "wheel group",
    description: "Your user joins wheel the Arch way; no ad-hoc group creation.",
  },
  {
    icon: <Database className="h-5 w-5" />,
    title: "Postgres via pacman + initdb",
    description: "Installed from official repos, then initialized with initdb — no third-party apt repo.",
  },
] as const;

interface ToolEntry {
  name: string;
  description: string;
}

// ACFS stack tools first (grounded in manifest-tools.ts), then the ecosystem
// CLIs and desktop layer that orbit them.
const TOOLS: ToolEntry[] = [
  { name: "ntm", description: "Named Tmux Manager — agent orchestration across sessions" },
  { name: "am", description: "MCP Agent Mail — agents that message each other" },
  { name: "ubs", description: "Ultimate Bug Scanner" },
  { name: "bv", description: "Beads Viewer — issue tracking UI" },
  { name: "cass", description: "Coding Agent Session Search" },
  { name: "cm", description: "CASS Memory System — persistent context memory" },
  { name: "caam", description: "Coding Agent Account Manager — auth for every CLI" },
  { name: "slb", description: "Simultaneous Launch Button — fan out agents safely" },
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
  { name: "giil", description: "Get Image from Internet Link" },
  { name: "csctf", description: "Chat Shared Conversation to File" },
  { name: "xf", description: "X Archive Search" },
  { name: "tru", description: "Token-Optimized Notation" },
  { name: "rano", description: "Network Observer" },
  { name: "mdwb", description: "Markdown Web Browser" },
  { name: "s2p", description: "Source to Prompt TUI" },
  { name: "srps", description: "System Resource Protection Script" },
  { name: "apr", description: "Automated Plan Reviser Pro" },
  { name: "jfp", description: "JeffreysPrompts CLI" },
  { name: "brenner", description: "Brenner Bot" },
  { name: "opencode", description: "OpenCode agent CLI" },
  { name: "claude", description: "Claude Code" },
  { name: "codex", description: "OpenAI Codex CLI" },
  { name: "agy", description: "Google Antigravity CLI" },
  { name: "bun", description: "The JavaScript runtime" },
  { name: "uv", description: "Python packaging, fast" },
  { name: "cargo", description: "Rust toolchain" },
  { name: "go", description: "Go toolchain" },
  { name: "gh", description: "GitHub CLI" },
  { name: "gum", description: "Glamorous shell scripts" },
  { name: "tmux", description: "Terminal multiplexer" },
  { name: "zsh", description: "Your shell" },
  { name: "starship", description: "Your prompt, untouched" },
  { name: "hyprland", description: "The Omarchy desktop" },
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

export default function OmarchyPage() {
  return (
    <div className="relative min-h-screen overflow-x-clip bg-background">
      {/* ============================= HERO ============================= */}
      {/* Fixed min-height + absolutely-positioned canvas: zero layout shift */}
      <section className="relative flex min-h-[100svh] items-center justify-center overflow-hidden bg-gradient-to-b from-[#0a0e1a] via-[#10121f] to-[#1a1b26]">
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

        <div className="relative z-10 mx-auto max-w-5xl px-6 py-24 text-center">
          <motion.div
            variants={staggerContainer}
            initial="hidden"
            animate="visible"
            className="flex flex-col items-center"
          >
            <motion.div
              className="mb-6 inline-flex items-center gap-2 rounded-full border border-[#9ece6a]/30 bg-[#9ece6a]/10 px-4 py-1.5 font-mono text-xs tracking-widest text-[#9ece6a]"
              variants={fadeUp}
            >
              OMARCHY 4 · ARCH FAMILY · HYPRLAND
            </motion.div>

            <motion.h1
              className="mb-6 font-mono text-4xl font-bold leading-tight tracking-tight sm:text-5xl lg:text-6xl"
              variants={fadeUp}
            >
              <span className="text-foreground">The Flywheel,</span>
              <br />
              <span className="bg-gradient-to-r from-[#9ece6a] via-[#7dcfff] to-[#bb9af7] bg-clip-text text-transparent">
                native on Omarchy.
              </span>
            </motion.h1>

            <motion.p
              className="mb-8 max-w-2xl text-lg leading-relaxed text-muted-foreground"
              variants={fadeUp}
            >
              Same one-liner, same flywheel — auto-detects Arch and Omarchy, keeps your{" "}
              <span className="font-mono text-[#e0af68]">starship</span> prompt, skips{" "}
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
                className="group relative overflow-hidden bg-primary text-primary-foreground hover:bg-primary/90"
              >
                <Link href="/wizard/os-selection">
                  <span className="relative z-10 flex items-center gap-2">
                    Start the Wizard
                    <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-1" />
                  </span>
                </Link>
              </Button>
              <Button asChild size="lg" variant="outline" className="border-border/50 hover:bg-muted/50">
                <a href={ARCH_NOTES_URL} target="_blank" rel="noopener noreferrer">
                  <GitBranch className="mr-2 h-4 w-4" />
                  Read the Arch notes
                </a>
              </Button>
            </motion.div>
          </motion.div>
        </div>
      </section>

      <main>
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
                <div className="mb-4 inline-flex rounded-xl p-3" style={{ backgroundColor: `${feature.accent}1a`, color: feature.accent }}>
                  {feature.icon}
                </div>
                <h3 className="mb-2 font-mono text-lg font-semibold tracking-tight">{feature.title}</h3>
                <p className="text-sm leading-relaxed text-muted-foreground">{feature.description}</p>
              </motion.div>
            ))}
          </motion.div>
        </section>

        {/* ===================== WHAT CHANGES ON ARCH ======================= */}
        <section className="border-y border-border/30 bg-card/20 py-20">
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
            <motion.p
              className="mt-10 text-center text-sm text-muted-foreground"
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={springs.smooth}
            >
              Full diff-by-diff detail in the{" "}
              <a
                href={ARCH_NOTES_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-1 text-primary hover:underline"
              >
                README&apos;s Arch support section
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
            The names swirling above aren&apos;t decoration — each one is a real binary on your
            machine after install. Here&apos;s the whole swarm.
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
              <Button
                asChild
                size="lg"
                className="group relative overflow-hidden bg-primary text-primary-foreground hover:bg-primary/90"
              >
                <Link href="/wizard/os-selection">
                  <span className="relative z-10 flex items-center gap-2">
                    Start the Wizard
                    <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-1" />
                  </span>
                </Link>
              </Button>
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
                <a
                  href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="underline-offset-4 transition-colors hover:text-foreground hover:underline"
                >
                  GitHub
                </a>
                <Link href="/learn" className="underline-offset-4 transition-colors hover:text-foreground hover:underline">
                  Learning Hub
                </Link>
                <Link href="/tldr" className="underline-offset-4 transition-colors hover:text-foreground hover:underline">
                  TL;DR
                </Link>
                <Link href="/" className="underline-offset-4 transition-colors hover:text-foreground hover:underline">
                  Home
                </Link>
                <a
                  href={ARCH_NOTES_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="underline-offset-4 transition-colors hover:text-foreground hover:underline"
                >
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
