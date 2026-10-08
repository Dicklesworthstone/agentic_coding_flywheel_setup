"use client";

import {
  AlertTriangle,
  ArrowRight,
  BookOpen,
  Check,
  Clock,
  Cloud,
  Copy,
  ExternalLink,
  FileText,
  Mail,
  ShieldCheck,
  Terminal,
} from "lucide-react";
import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { fadeUp, motion, springs, staggerContainer } from "@/components/motion";
import { Button } from "@/components/ui/button";
import {
  CLAUDE_CODE_WEB_DOCS_URL,
  CLAUDE_CODE_WEB_LEFT_OUT,
  CLAUDE_CODE_WEB_OPTIONS,
  CLAUDE_CODE_WEB_SCRIPT_SOURCE_URL,
  CLAUDE_CODE_WEB_SCRIPT_URL,
  CLAUDE_CODE_WEB_SETUP_SCRIPT,
  CLAUDE_CODE_WEB_TOOLS,
  CODEX_CLOUD_DOCS_URL,
  CODEX_CLOUD_SETUP_SCRIPT,
  CODEX_CLOUD_START_SKILL,
} from "@/lib/claude-code-web";
import { staggerDelay } from "@/lib/hooks/useScrollReveal";
import { copyTextToClipboard } from "@/lib/utils";

const GITHUB_URL = "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup";
const README_URL = `${GITHUB_URL}#claude-code-on-the-web-cloud-environments`;
const SUBSET_EXAMPLE = `curl -fsSL ${CLAUDE_CODE_WEB_SCRIPT_URL} | ACFS_CLOUD_TOOLS="br bv am ubs" bash`;

const STEPS = [
  {
    title: "Add a cloud environment",
    description:
      "In claude.ai/code, open the environment menu and choose Add cloud environment, or edit one you already use. Any name works.",
  },
  {
    title: "Set Network access to Full",
    description:
      "Recommended for the public prebuilt mirror. Custom can allow raw.githubusercontent.com and downloads.agent-flywheel.com. Trusted tries public release fallbacks and reports unavailable tools.",
  },
  {
    title: "Paste the setup script",
    description:
      "It runs once, the VM is snapshotted, and every later session in the environment starts with the tools already installed.",
  },
];

const BEHAVIORS = [
  {
    icon: <ShieldCheck className="h-6 w-6" />,
    title: "Verified prebuilt tools",
    description:
      "Every bundle is checked against cloud-mirror.json in the ACFS repository before extraction. Upstream checksums and available signatures are verified when publishing. No source builds or upstream installers run in your session.",
  },
  {
    icon: <Clock className="h-6 w-6" />,
    title: "Fits the cache window",
    description:
      "Downloads and installation run in parallel, with a maximum 180-second deadline per tool job. Tools arrive prebuilt, including JSM, JFP, and ast-grep.",
  },
  {
    icon: <Check className="h-6 w-6" />,
    title: "Never blocks a session",
    description:
      "A setup script that exits non-zero stops the session from starting, so this one always exits 0. Anything that did not install is listed in the summary and in ~/.acfs/cloud/setup.log.",
  },
  {
    icon: <Mail className="h-6 w-6" />,
    title: "Agent Mail without a daemon",
    description:
      "Background processes do not survive the snapshot, so Agent Mail is registered as a stdio MCP server that Claude Code starts on demand.",
  },
  {
    icon: <FileText className="h-6 w-6" />,
    title: "Claude knows what is installed",
    description:
      "A managed block in ~/.claude/CLAUDE.md, which cloud sessions load as user instructions, lists each installed tool and how to call it. Anything else in that file is kept.",
  },
];

function SetupScriptCard({ label, script = CLAUDE_CODE_WEB_SETUP_SCRIPT, copyLabel = "Copy setup script", title = "Setup script", wrap = false }: {
  label: string;
  script?: string;
  copyLabel?: string;
  title?: string;
  wrap?: boolean;
}) {
  const [copied, setCopied] = useState(false);
  const resetTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (resetTimer.current) clearTimeout(resetTimer.current);
    };
  }, []);

  const copy = useCallback(async () => {
    const ok = await copyTextToClipboard(script);
    if (!ok) return;
    setCopied(true);
    if (resetTimer.current) clearTimeout(resetTimer.current);
    resetTimer.current = setTimeout(() => setCopied(false), 2000);
  }, [script]);

  return (
    <div className="terminal-window w-full text-left shadow-2xl ring-1 ring-primary/10">
      <div className="terminal-header">
        <div className="terminal-dot terminal-dot-red" aria-hidden="true" />
        <div className="terminal-dot terminal-dot-yellow" aria-hidden="true" />
        <div className="terminal-dot terminal-dot-green" aria-hidden="true" />
        <span className="ml-3 font-mono text-xs text-[#a9b1d6]/70">{title}</span>
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={copy}
          className="ml-auto h-7 shrink-0 border-[#9ece6a]/40 bg-transparent text-[#c0caf5] hover:bg-[#9ece6a]/10 hover:text-[#c0caf5]"
          aria-label={copyLabel}
        >
          {copied ? (
            <>
              <Check className="h-4 w-4 text-[#9ece6a]" />
              <span className="text-[#9ece6a]">Copied</span>
            </>
          ) : (
            <>
              <Copy className="h-4 w-4" />
              Copy
            </>
          )}
        </Button>
        <span role="status" aria-live="polite" className="sr-only">
          {copied ? `${title} copied to clipboard` : ""}
        </span>
      </div>
      <pre
        tabIndex={0}
        role="region"
        aria-label={label}
        className={`overflow-x-auto p-5 font-mono text-sm leading-relaxed text-[#c0caf5] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#9ece6a]/60 ${wrap ? "whitespace-pre-wrap break-words" : ""}`}
      >
        <code>{script}</code>
      </pre>
    </div>
  );
}

function SectionHeading({ eyebrow, title }: { eyebrow: string; title: string }) {
  return (
    <motion.div
      className="mb-12 text-center"
      initial={{ opacity: 0, y: 20 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-80px" }}
      transition={springs.smooth}
    >
      <p className="mb-2 font-mono text-xs uppercase tracking-widest text-primary">{eyebrow}</p>
      <h2 className="font-mono text-3xl font-bold tracking-tight sm:text-4xl">{title}</h2>
    </motion.div>
  );
}

const footerLink =
  "inline-flex min-h-6 items-center rounded-sm underline-offset-4 transition-colors hover:text-foreground hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60";

export default function ClaudeCodeWebPage() {
  return (
    <div className="relative min-h-screen overflow-x-clip bg-background">
      <main id="main-content" tabIndex={-1}>
        {/* ============================= HERO ============================= */}
        <section className="relative overflow-hidden border-b border-border/30">
          <div
            className="pointer-events-none absolute left-1/2 top-0 h-[480px] w-[800px] -translate-x-1/2 rounded-full bg-primary/10 blur-[120px]"
            aria-hidden="true"
          />
          <motion.div
            className="relative mx-auto flex max-w-4xl flex-col items-center px-6 pb-20 pt-24 text-center sm:pt-32"
            variants={staggerContainer}
            initial="hidden"
            animate="visible"
          >
            <motion.p
              className="mb-4 inline-flex items-center gap-2 rounded-full border border-primary/30 bg-primary/10 px-3 py-1 font-mono text-xs uppercase tracking-widest text-primary"
              variants={fadeUp}
            >
              <Cloud className="h-3.5 w-3.5" />
              Claude Code on the web
            </motion.p>
            <motion.h1
              className="mb-6 font-mono text-4xl font-bold tracking-tight sm:text-5xl"
              variants={fadeUp}
            >
              The flywheel in every cloud session
            </motion.h1>
            <motion.p
              className="mb-10 max-w-2xl text-lg leading-relaxed text-muted-foreground"
              variants={fadeUp}
            >
              Cloud sessions run on disposable VMs, so the full VPS installer is the wrong tool. One
              setup script puts br, bv, Agent Mail, ubs, cass, and the rest of the agent-facing
              stack in your VM, verified against the repository&apos;s pinned bundle hashes.
              Export <code className="font-mono text-base">$HOME/.local/bin</code> onto PATH in each task shell.
            </motion.p>
            <motion.div className="w-full max-w-3xl" variants={fadeUp}>
              <SetupScriptCard label="Setup script for a Claude Code cloud environment" />
            </motion.div>
            <motion.div className="mt-8 flex flex-col gap-3 sm:flex-row" variants={fadeUp}>
              <Button asChild size="lg" variant="outline" className="border-border/50">
                <a href={CLAUDE_CODE_WEB_SCRIPT_SOURCE_URL} target="_blank" rel="noopener noreferrer">
                  <Terminal className="mr-2 h-4 w-4" />
                  Read the script
                </a>
              </Button>
              <Button asChild size="lg" variant="outline" className="border-border/50">
                <a href={CLAUDE_CODE_WEB_DOCS_URL} target="_blank" rel="noopener noreferrer">
                  <ExternalLink className="mr-2 h-4 w-4" />
                  Cloud environment docs
                </a>
              </Button>
            </motion.div>
          </motion.div>
        </section>

        {/* ============================= STEPS ============================= */}
        <section className="mx-auto max-w-6xl px-6 py-24">
          <SectionHeading eyebrow="three fields" title="Set it up once" />
          <motion.ol
            className="grid gap-6 md:grid-cols-3"
            variants={staggerContainer}
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true, margin: "-80px" }}
          >
            {STEPS.map((step, index) => (
              <motion.li
                key={step.title}
                className="rounded-2xl border border-border/50 bg-card/50 p-6 backdrop-blur-sm"
                variants={fadeUp}
                transition={{ ...springs.snappy, delay: staggerDelay(index, 0.08) }}
              >
                <span className="mb-4 inline-flex h-8 w-8 items-center justify-center rounded-full bg-primary/15 font-mono text-sm font-bold text-primary">
                  {index + 1}
                </span>
                <h3 className="mb-2 font-mono text-lg font-semibold tracking-tight">
                  {step.title}
                </h3>
                <p className="text-sm leading-relaxed text-muted-foreground">{step.description}</p>
              </motion.li>
            ))}
          </motion.ol>
        </section>

        {/* ============================= TOOLS ============================= */}
        <section className="border-y border-border/30 bg-card/20 py-24">
          <div className="mx-auto max-w-6xl px-6">
            <SectionHeading eyebrow="what lands on PATH" title="The agent-facing stack" />
            <motion.div
              className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3"
              variants={staggerContainer}
              initial="hidden"
              whileInView="visible"
              viewport={{ once: true, margin: "-80px" }}
            >
              {CLAUDE_CODE_WEB_TOOLS.map((tool, index) => (
                <motion.div
                  key={tool.id}
                  className="rounded-xl border border-border/50 bg-background/60 p-5"
                  variants={fadeUp}
                  transition={{ ...springs.snappy, delay: staggerDelay(index, 0.05) }}
                >
                  <div className="mb-2 flex items-baseline justify-between gap-3">
                    <h3 className="font-semibold">{tool.name}</h3>
                    <code className="shrink-0 rounded bg-muted px-1.5 py-0.5 font-mono text-xs text-primary">
                      {tool.command}
                    </code>
                  </div>
                  <p className="text-sm leading-relaxed text-muted-foreground">{tool.role}</p>
                </motion.div>
              ))}
            </motion.div>
          </div>
        </section>

        {/* =========================== BEHAVIOR =========================== */}
        <section className="mx-auto max-w-6xl px-6 py-24">
          <SectionHeading eyebrow="built for a disposable VM" title="How it behaves" />
          <motion.div
            className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3"
            variants={staggerContainer}
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true, margin: "-80px" }}
          >
            {BEHAVIORS.map((behavior, index) => (
              <motion.div
                key={behavior.title}
                className="rounded-2xl border border-border/50 bg-card/50 p-6 backdrop-blur-sm"
                variants={fadeUp}
                transition={{ ...springs.snappy, delay: staggerDelay(index, 0.08) }}
              >
                <div className="mb-4 inline-flex rounded-xl bg-primary/10 p-3 text-primary">
                  {behavior.icon}
                </div>
                <h3 className="mb-2 font-mono text-lg font-semibold tracking-tight">
                  {behavior.title}
                </h3>
                <p className="text-sm leading-relaxed text-muted-foreground">
                  {behavior.description}
                </p>
              </motion.div>
            ))}
          </motion.div>
        </section>

        {/* ========================== LEFT OUT ========================== */}
        <section className="border-y border-border/30 bg-card/20 py-24">
          <div className="mx-auto max-w-4xl px-6">
            <SectionHeading eyebrow="on purpose" title="What it leaves out" />
            <ul className="divide-y divide-border/40 rounded-2xl border border-border/50 bg-background/60">
              {CLAUDE_CODE_WEB_LEFT_OUT.map((item) => (
                <li key={item.name} className="flex flex-col gap-1 p-5 sm:flex-row sm:gap-6">
                  <span className="shrink-0 font-mono text-sm font-semibold sm:w-48">
                    {item.name}
                  </span>
                  <span className="text-sm leading-relaxed text-muted-foreground">
                    {item.reason}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        </section>

        <section id="codex-cloud" className="mx-auto max-w-4xl px-6 py-24">
          <SectionHeading eyebrow="same prebuilt tools" title="ChatGPT / Codex cloud" />
          <p className="mb-6 text-sm leading-relaxed text-muted-foreground">
            In Work in → Cloud, add this to your environment&apos;s Install script. Enable internet
            access and allow raw.githubusercontent.com and downloads.agent-flywheel.com, review the
            setup log, then Publish the environment. Republish after changing its setup.
            Tools and logs live in the writable repo workspace; HOME and CODEX_HOME stay intact.
          </p>
          <SetupScriptCard label="Install script for a Codex cloud environment" script={CODEX_CLOUD_SETUP_SCRIPT}
            copyLabel="Copy Codex install script" title="Install script" />
          <p className="mb-4 mt-8 text-sm leading-relaxed text-muted-foreground">
            Save these instructions in its Start skill and include them at the start of each new
            task. Hosted tests reused all eleven executables, but did not automatically load the
            saved Start skill or generated repository skill. These instructions explicitly load
            the guide and set PATH:
          </p>
          <SetupScriptCard label="Codex Start skill instructions" script={CODEX_CLOUD_START_SKILL}
            copyLabel="Copy Codex task instructions" title="Task instructions" wrap />
          <p className="mt-6 text-sm leading-relaxed text-muted-foreground">
            Agent Mail is available as a CLI; hosted MCP is not configured. If your task does not
            discover acfs-cloud-tools, read its SKILL.md or the workspace guide explicitly.
            Older environments with Setup and Maintenance
            script fields use the install command in Setup. Verify PATH, instruction loading and
            network access in your hosted task before relying on the tools.
          </p>
          <a href={CODEX_CLOUD_DOCS_URL} target="_blank" rel="noopener noreferrer" className={`${footerLink} mt-4 text-sm text-primary`}>
            OpenAI cloud environment guide <ExternalLink className="ml-2 h-4 w-4" />
          </a>
        </section>

        {/* =========================== OPTIONS =========================== */}
        <section className="mx-auto max-w-4xl px-6 py-24">
          <SectionHeading eyebrow="optional" title="Tune it" />
          <p className="mb-6 text-center text-muted-foreground">
            Set options inline, where the setup script itself sees them:
          </p>
          <pre
            tabIndex={0}
            className="mb-8 overflow-x-auto rounded-xl border border-border/50 bg-muted/40 p-4 font-mono text-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60"
          >
            <code>{SUBSET_EXAMPLE}</code>
          </pre>
          <div className="overflow-x-auto rounded-2xl border border-border/50">
            <table className="w-full text-left text-sm">
              <thead className="bg-card/50 font-mono text-xs uppercase tracking-wider text-muted-foreground">
                <tr>
                  <th className="p-4">Variable</th>
                  <th className="p-4">Default</th>
                  <th className="p-4">Effect</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border/40">
                {CLAUDE_CODE_WEB_OPTIONS.map((option) => (
                  <tr key={option.name}>
                    <td className="p-4 font-mono text-xs text-primary">{option.name}</td>
                    <td className="p-4 font-mono text-xs">{option.defaultValue}</td>
                    <td className="p-4 text-muted-foreground">{option.effect}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="mt-10 flex gap-4 rounded-2xl border border-amber-500/30 bg-amber-500/5 p-6">
            <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-amber-500" />
            <div className="text-sm leading-relaxed text-muted-foreground">
              <p className="mb-2 font-semibold text-foreground">Full network access recommended</p>
              <p>
                Anyone can use the public mirror without credentials or repository ownership.
                Select Full, or Custom allowing raw.githubusercontent.com and
                downloads.agent-flywheel.com. Under Trusted, setup tries pinned public release
                binaries when the mirror is blocked. What installs depends on the environment&apos;s
                GitHub proxy. Existing working tools are retained, unavailable tools are listed in
                the setup log and guide, and no source build is attempted.
              </p>
            </div>
          </div>
        </section>

        {/* ============================== CTA ============================== */}
        <section className="border-t border-border/30 py-24">
          <div className="mx-auto flex max-w-3xl flex-col items-center px-6 text-center">
            <h2 className="mb-4 font-mono text-3xl font-bold tracking-tight sm:text-4xl">
              Want the whole stack?
            </h2>
            <p className="mb-8 max-w-xl text-muted-foreground">
              The cloud script covers the tools an agent calls. A VPS of your own gets everything:
              the shell, tmux, every agent CLI, and the services that keep running between
              sessions.
            </p>
            <div className="flex flex-col items-center gap-3 sm:flex-row">
              <Button asChild size="lg" variant="outline" className="border-border/50">
                <Link href="/learn">
                  <BookOpen className="mr-2 h-4 w-4" />
                  Learn the workflow
                </Link>
              </Button>
              <Button
                asChild
                size="lg"
                className="group bg-primary text-primary-foreground hover:bg-primary/90"
              >
                <Link href="/wizard/os-selection">
                  Set up a VPS with the Wizard
                  <ArrowRight className="ml-2 h-4 w-4 transition-transform group-hover:translate-x-1" />
                </Link>
              </Button>
            </div>
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
                <a href={README_URL} target="_blank" rel="noopener noreferrer" className={footerLink}>
                  README section
                </a>
                <Link href="/tldr" className={footerLink}>
                  TL;DR
                </Link>
                <Link href="/omarchy" className={footerLink}>
                  Omarchy
                </Link>
                <Link href="/" className={footerLink}>
                  Home
                </Link>
              </div>

              <p className="text-xs text-muted-foreground">
                Created by{" "}
                <a
                  href="https://jeffreyemanuel.com/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex min-h-6 items-center text-primary hover:underline"
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
