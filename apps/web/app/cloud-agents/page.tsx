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
  ZoomIn,
} from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  CLAUDE_CODE_WEB_LEFT_OUT,
  CLAUDE_CODE_WEB_OPTIONS,
  CLAUDE_CODE_WEB_SCRIPT_SOURCE_URL,
  CLAUDE_CODE_WEB_SCRIPT_URL,
  CLAUDE_CODE_WEB_SETUP_SCRIPT,
  CLAUDE_CODE_WEB_TOOLS,
  CLOUD_AGENTS,
  CLOUD_AGENT_RESEARCH_DATE,
} from "@/lib/claude-code-web";
import { copyTextToClipboard } from "@/lib/utils";
import { CLOUD_WALKTHROUGHS, getCloudAgentSetupInstructions, type SetupScreenshot } from "@/lib/cloud-agent-walkthroughs";

const GITHUB_URL = "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup";
const README_URL = `${GITHUB_URL}#cloud-agent-environments`;
const SUBSET_EXAMPLE = `curl -fsSL ${CLAUDE_CODE_WEB_SCRIPT_URL} | ACFS_CLOUD_AGENT=generic ACFS_CLOUD_TOOLS="br bv am ubs" bash`;

const BEHAVIORS = [
  {
    icon: <ShieldCheck className="h-6 w-6" />,
    title: "Verified prebuilt tools",
    description:
      "Every bundle is checked against cloud-mirror.json in the ACFS repository before extraction. Upstream checksums and available signatures are verified when publishing. No source builds or upstream installers run in your session.",
  },
  {
    icon: <Clock className="h-6 w-6" />,
    title: "Bounded setup time",
    description:
      "Downloads and installation run in parallel, with a maximum 180-second deadline per tool job. Tools arrive prebuilt, including JSM, JFP, and ast-grep.",
  },
  {
    icon: <Check className="h-6 w-6" />,
    title: "Failures stay visible",
    description:
      "The installer exits 0 so an unavailable tool does not block startup. Review the summary and setup log: a completed script does not mean every tool installed.",
  },
  {
    icon: <Mail className="h-6 w-6" />,
    title: "Agent Mail without a daemon",
    description:
      "Claude gets an on-demand stdio MCP server. Other recipes expose the Agent Mail CLI without starting a daemon or changing provider MCP settings.",
  },
  {
    icon: <FileText className="h-6 w-6" />,
    title: "A guide the agent can read",
    description:
      "A managed instruction block lists working tools, commands and failures. Claude loads its user guide; other agents need the explicit guide-loading instructions in their recipe.",
  },
];

function SetupScriptCard({ label, script = CLAUDE_CODE_WEB_SETUP_SCRIPT, copyLabel = "Copy setup script", title = "Setup script", wrap = false, buttonOnly = false }: {
  label: string;
  script?: string;
  copyLabel?: string;
  title?: string;
  wrap?: boolean;
  buttonOnly?: boolean;
}) {
  const [copyState, setCopyState] = useState<"idle" | "copying" | "copied" | "error">("idle");
  const resetTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const active = useRef(true);

  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
      if (resetTimer.current) clearTimeout(resetTimer.current);
    };
  }, []);

  const copy = useCallback(async () => {
    if (resetTimer.current) clearTimeout(resetTimer.current);
    setCopyState("copying");
    let ok = false;
    try {
      ok = await copyTextToClipboard(script);
    } catch {
      // Provide selectable text if a browser denies clipboard access.
    }
    if (!active.current) return;
    setCopyState(ok ? "copied" : "error");
    if (!ok) return;
    resetTimer.current = setTimeout(() => setCopyState("idle"), 2000);
  }, [script]);

  if (buttonOnly) return (
    <div className="min-w-0">
      <Button type="button" size="lg" onClick={copy} disabled={copyState === "copying"} aria-label={copyLabel}
        className="min-h-12 w-full gap-2 bg-primary px-4 text-base font-semibold text-primary-foreground hover:bg-primary/90 focus-visible:ring-2 focus-visible:ring-primary sm:w-auto">
        {copyState === "copied" ? <Check className="size-5 shrink-0" aria-hidden="true" /> : <Copy className="size-5 shrink-0" aria-hidden="true" />}
        {copyState === "copied" ? "Full instructions copied" : copyState === "copying" ? "Copying…" : "Copy full instructions"}
      </Button>
      <span role="status" aria-live="polite" className="sr-only">{copyState === "copied" ? `${title} copied to clipboard` : ""}</span>
      {copyState === "error" && <div className="mt-3 rounded-lg border border-amber-400/40 p-3">
        <p role="alert" className="mb-3 text-sm leading-relaxed text-amber-200">Clipboard access failed. Select and copy the full instructions below, or try the button again.</p>
        <pre tabIndex={0} role="region" aria-label={label} className="max-h-72 overflow-auto whitespace-pre-wrap break-words rounded-md bg-background p-3 font-mono text-xs leading-relaxed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"><code>{script}</code></pre>
      </div>}
    </div>
  );

  return (
    <div className="terminal-window min-w-0 w-full text-left shadow-lg ring-1 ring-primary/10">
      <div className="terminal-header">
        <div className="terminal-dot terminal-dot-red" aria-hidden="true" />
        <div className="terminal-dot terminal-dot-yellow" aria-hidden="true" />
        <div className="terminal-dot terminal-dot-green" aria-hidden="true" />
        <span title={title} className="ml-3 min-w-0 flex-1 truncate font-mono text-xs text-[#a9b1d6]/70">{title}</span>
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={copy}
          disabled={copyState === "copying"}
          className="ml-auto min-h-11 shrink-0 border-[#9ece6a]/40 bg-transparent px-3 text-[#c0caf5] hover:bg-[#9ece6a]/10 hover:text-[#c0caf5] focus-visible:ring-2 focus-visible:ring-[#9ece6a]"
          aria-label={copyLabel}
        >
          {copyState === "copied" ? (
            <>
              <Check className="h-4 w-4 text-[#9ece6a]" />
              <span className="text-[#9ece6a]">Copied</span>
            </>
          ) : (
            <>
              <Copy className="h-4 w-4" />
              {copyState === "copying" ? "Copying…" : "Copy"}
            </>
          )}
        </Button>
        <span role="status" aria-live="polite" className="sr-only">
          {copyState === "copied" ? `${title} copied to clipboard` : ""}
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
      {copyState === "error" && (
        <p role="alert" className="border-t border-amber-400/30 px-5 py-3 text-sm text-amber-200">
          Clipboard access failed. Select the text above and copy it manually, or try Copy again.
        </p>
      )}
    </div>
  );
}

function SectionHeading({ eyebrow, title }: { eyebrow: string; title: string }) {
  return (
    <div className="mb-12 text-center">
      <p className="mb-2 font-mono text-xs uppercase tracking-widest text-primary">{eyebrow}</p>
      <h2 className="font-mono text-3xl font-bold tracking-tight sm:text-4xl">{title}</h2>
    </div>
  );
}

const footerLink =
  "inline-flex min-h-11 items-center rounded-sm underline-offset-4 transition-colors hover:text-foreground hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60";

function ScreenshotFigure({ screenshot }: { screenshot: SetupScreenshot }) {
  return (
    <figure className="min-w-0 self-start overflow-hidden rounded-xl border border-border/70 bg-card">
      <a href={screenshot.src} target="_blank" rel="noopener noreferrer"
        aria-label={`Open full-size screenshot: ${screenshot.alt} (new tab)`}
        className="group block bg-[#f5f5f5] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary">
        <Image src={screenshot.src} alt={screenshot.alt} width={screenshot.width} height={screenshot.height}
          sizes="(min-width: 1024px) 520px, (min-width: 640px) 80vw, 100vw"
          className="h-auto max-h-[34rem] w-full object-contain" />
        <span className="flex min-h-11 items-center justify-center gap-2 border-t border-black/10 px-3 text-sm font-medium text-[#31313a] group-hover:underline">
          <ZoomIn className="size-4" aria-hidden="true" />Open full-size screenshot<ExternalLink className="size-3.5" aria-hidden="true" />
        </span>
      </a>
      <figcaption className="px-4 py-3 text-xs leading-relaxed text-muted-foreground">{screenshot.caption}</figcaption>
    </figure>
  );
}

function AgentSetupLauncher({ agentId, choose }: { agentId: string; choose: (id: string) => void }) {
  const agent = CLOUD_AGENTS.find((item) => item.id === agentId) ?? CLOUD_AGENTS[0];
  return (
    <section aria-labelledby="automatic-setup-heading" className="mt-6 rounded-2xl border border-primary/40 bg-primary/5 p-4 sm:p-5">
      <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-primary">Recommended</p>
      <h2 id="automatic-setup-heading" className="text-lg font-semibold tracking-tight">Let ChatGPT set it up for you</h2>
      <p className="mt-2 text-sm leading-relaxed text-muted-foreground">Choose your provider, copy the full guide, then paste it into a ChatGPT app chat with computer use enabled. The agent can follow every click and fill in the scripts for you.</p>
      <label className="mb-3 mt-4 block text-sm font-medium">Provider to set up
        <select value={agentId} onChange={(event) => choose(event.target.value)}
          className="mt-2 min-h-12 w-full rounded-lg border border-primary/40 bg-card px-3 text-base text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
          {CLOUD_AGENTS.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
        </select>
      </label>
      <SetupScriptCard key={agent.id} buttonOnly label={`Full agent instructions for ${agent.name}`} title={`${agent.name} full instructions`} script={getCloudAgentSetupInstructions(agent.id)} copyLabel={`Copy full instructions for ${agent.name}`} />
      <p className="mt-3 text-xs leading-relaxed text-muted-foreground">Includes every step, field value, script, screenshot and verification check. The agent may ask you to sign in or approve a setting. {agent.id === "muse" ? "Muse starts with a capability check; installation support is unverified." : ""}</p>
      <a href="#choose-agent" className={`${footerLink} mt-2 gap-2 text-sm font-medium text-primary`}>Or follow the screenshots yourself<ArrowRight className="size-4 shrink-0" aria-hidden="true" /></a>
    </section>
  );
}

function CloudWorkbench({ agentId, choose }: { agentId: string; choose: (id: string) => void }) {
  const agent = CLOUD_AGENTS.find((item) => item.id === agentId) ?? CLOUD_AGENTS[0];
  const walkthrough = CLOUD_WALKTHROUGHS[agent.id];
  return (
    <section aria-labelledby="choose-agent" className="mx-auto max-w-6xl px-5 pb-16 sm:px-8">
      <div className="mb-6 flex flex-wrap items-end justify-between gap-2">
        <h2 id="choose-agent" className="text-xl font-semibold tracking-tight">Choose your cloud agent</h2>
        <p className="text-xs text-muted-foreground">Guides checked {CLOUD_AGENT_RESEARCH_DATE}</p>
      </div>
      <label className="block text-sm font-medium sm:hidden">Cloud agent
        <select value={agentId} onChange={(event) => choose(event.target.value)}
          className="mt-2 min-h-12 w-full rounded-xl border border-primary/50 bg-card px-3 text-base text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
          {CLOUD_AGENTS.map((item) => <option key={item.id} value={item.id}>{item.name} · {item.evidence}</option>)}
        </select>
      </label>
      <div role="group" aria-label="Cloud agent" className="hidden gap-2 sm:grid sm:grid-cols-3 lg:grid-cols-4">
        {CLOUD_AGENTS.map((item) => (
          <button key={item.id} type="button" aria-pressed={agentId === item.id} aria-controls="agent-setup"
            onClick={() => choose(item.id)}
            className={`flex min-h-16 items-center gap-3 rounded-xl border px-3 py-3 text-left transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary motion-reduce:transition-none ${agentId === item.id ? "border-primary bg-primary/10 text-foreground" : "border-border/60 bg-card/40 text-muted-foreground hover:border-primary/50 hover:text-foreground"}`}>
            <span aria-hidden="true" className={`flex size-8 shrink-0 items-center justify-center rounded-md font-mono text-xs font-semibold ${agentId === item.id ? "bg-primary text-primary-foreground" : "bg-muted text-foreground"}`}>{item.initials}</span>
            <span className="min-w-0"><span className="block text-sm font-semibold">{item.name}</span>
              <span className="mt-0.5 block text-xs">{item.evidence}</span></span>
            {agentId === item.id && <Check className="ml-auto size-4 shrink-0 text-primary" aria-hidden="true" />}
          </button>
        ))}
      </div>
      <div id="agent-setup" className="mt-8 min-w-0">
        <div className="grid gap-6 border-b border-border/60 pb-7 lg:grid-cols-[1.2fr_0.8fr]">
          <div className="min-w-0">
            <p className="mb-3 inline-flex items-center gap-2 text-sm font-medium text-primary"><Cloud className="size-4" aria-hidden="true" />{agent.evidence}</p>
            <h3 className="text-2xl font-semibold tracking-tight sm:text-3xl">Set up {agent.name}</h3>
            <p className="mt-3 max-w-2xl text-base leading-relaxed text-muted-foreground">{walkthrough.introduction}</p>
            <p className="mt-2 text-xs leading-relaxed text-muted-foreground">{walkthrough.visualEvidence}</p>
            <a href={`#${agent.id}-step-${walkthrough.steps[0].id}`} className="mt-5 inline-flex min-h-11 items-center gap-2 rounded-lg bg-primary px-4 text-sm font-semibold text-primary-foreground transition-colors hover:bg-primary/85 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background">{agent.id === "muse" ? "Start the capability check" : "Start the guide"}<ArrowRight className="size-4" aria-hidden="true" /></a>
          </div>
          <div className="flex self-start gap-3 rounded-xl border border-amber-400/25 bg-amber-400/5 p-4 text-sm leading-relaxed">
            <AlertTriangle className="mt-0.5 size-5 shrink-0 text-amber-400" aria-hidden="true" />
            <p className="text-muted-foreground"><strong className="text-foreground">What is verified. </strong>{agent.caveat}</p>
          </div>
        </div>
        <details className="my-6 rounded-xl border border-border/70 bg-card/50 px-4">
          <summary className="min-h-12 cursor-pointer rounded-md py-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">{walkthrough.steps.length} steps · jump to a step</summary>
          <nav aria-label={`${agent.name} setup steps`} className="border-t border-border/60 pb-3 pt-2">
          <ol className="grid gap-x-6 gap-y-1 sm:grid-cols-2">
            {walkthrough.steps.map((step, index) => (
              <li key={step.id}>
                <a href={`#${agent.id}-step-${step.id}`} className={`${footerLink} w-full gap-3 text-sm text-muted-foreground`}>
                  <span className="font-mono text-xs text-primary" aria-hidden="true">{String(index + 1).padStart(2, "0")}</span>{step.title}
                </a>
              </li>
            ))}
          </ol>
          </nav>
        </details>
        <ol className="space-y-8 sm:space-y-10" key={agent.id} aria-label={`${agent.name} setup walkthrough`}>
          {walkthrough.steps.map((step, index) => (
            <li key={step.id} id={`${agent.id}-step-${step.id}`} className="scroll-mt-6 rounded-2xl border border-border/70 bg-card/25 p-4 sm:p-7">
              <div className="mb-5 flex items-start gap-3 sm:gap-4">
                <span aria-hidden="true" className="flex size-9 shrink-0 items-center justify-center rounded-lg border border-primary/40 bg-primary/10 font-mono text-sm font-semibold text-primary">{index + 1}</span>
                <div className="min-w-0"><p className="mb-1 font-mono text-xs uppercase tracking-wider text-muted-foreground">Step {index + 1} of {walkthrough.steps.length}</p><h4 className="text-lg font-semibold tracking-tight sm:text-xl">{step.title}</h4></div>
              </div>
              <div className={`grid min-w-0 gap-6 ${step.screenshot ? "lg:grid-cols-2 lg:gap-8" : ""}`}>
                <div className="min-w-0 space-y-4">
                  {step.paragraphs.map((paragraph) => <p key={paragraph} className="max-w-3xl text-sm leading-7 text-muted-foreground sm:text-base">{paragraph}</p>)}
                  {step.fields && (
                    <div className="max-w-3xl rounded-lg border border-primary/25 bg-primary/5 px-4 py-3">
                      <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-primary">Where this goes</p>
                      <dl className="space-y-3">
                        {step.fields.map((field) => <div key={field.label}><dt className="text-xs leading-relaxed text-muted-foreground">{field.label}</dt><dd className="mt-1 break-words text-sm font-medium text-foreground">{field.value}</dd></div>)}
                      </dl>
                    </div>
                  )}
                  {step.paste && <SetupScriptCard script={step.paste.text} wrap title={step.paste.title} copyLabel={step.paste.label} label={step.paste.regionLabel ?? `${agent.name}: ${step.paste.title}`} />}
                  {step.note && <p className="max-w-3xl rounded-lg border border-amber-400/25 bg-amber-400/5 px-4 py-3 text-sm leading-relaxed text-foreground">{step.note}</p>}
                  {agent.id === "muse" && step.id === "template" && <button type="button" onClick={() => choose("generic")} className={`${footerLink} gap-2 text-sm font-semibold text-primary`}>Open Linux template<ArrowRight className="size-4" aria-hidden="true" /></button>}
                </div>
                {step.screenshot && <ScreenshotFigure screenshot={step.screenshot} />}
              </div>
              {walkthrough.steps[index + 1] && <div className="mt-6 flex justify-end border-t border-border/50 pt-3"><a href={`#${agent.id}-step-${walkthrough.steps[index + 1].id}`} className={`${footerLink} gap-2 text-sm font-medium text-primary`}>Next: {walkthrough.steps[index + 1].title}<ArrowRight className="size-4 shrink-0" aria-hidden="true" /></a></div>}
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}

function GuidePreview() {
  return (
    <div className="relative rounded-2xl border border-primary/25 bg-primary/5 p-5 shadow-xl shadow-primary/5">
      <p className="mb-4 text-sm font-semibold">Every click. Every field. Your setup.</p>
      <div className="grid grid-cols-2 gap-3">
        <a href="#claude-step-cloud-menu" className="group min-w-0 overflow-hidden rounded-xl border border-border/70 bg-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
          <div className="flex h-44 items-center bg-[#f5f5f5] p-2"><Image src="/cloud-agents/claude-network-options.png" alt="Preview of Claude's cloud environment network options." width={1456} height={2328} sizes="240px" className="h-full w-full object-contain" /></div>
          <div className="p-3"><p className="text-sm font-semibold group-hover:text-primary">Claude Code</p><p className="mt-1 text-xs text-muted-foreground">{CLOUD_WALKTHROUGHS.claude.steps.length} illustrated steps</p></div>
        </a>
        <a href="#codex-step-cloud" className="group min-w-0 overflow-hidden rounded-xl border border-border/70 bg-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
          <div className="flex h-44 items-center bg-[#f5f5f5] p-2"><Image src="/cloud-agents/codex-environment-fields.png" alt="Preview of ChatGPT's environment scripts and network settings." width={2326} height={1980} sizes="240px" className="h-full w-full object-contain" /></div>
          <div className="p-3"><p className="text-sm font-semibold group-hover:text-primary">ChatGPT / Codex</p><p className="mt-1 text-xs text-muted-foreground">{CLOUD_WALKTHROUGHS.codex.steps.length} illustrated steps</p></div>
        </a>
      </div>
      <p className="mt-4 text-xs leading-relaxed text-muted-foreground">Actual screens, exact scripts, and a check before your first task.</p>
    </div>
  );
}

export default function CloudAgentsPage() {
  const [agentId, setAgentId] = useState("claude");
  useEffect(() => {
    const readHash = () => {
      const id = window.location.hash.slice(1).split("-step-")[0].replace("codex-cloud", "codex");
      if (CLOUD_AGENTS.some((agent) => agent.id === id)) setAgentId(id);
    };
    readHash();
    window.addEventListener("hashchange", readHash);
    return () => window.removeEventListener("hashchange", readHash);
  }, []);
  useEffect(() => {
    const fragment = window.location.hash.slice(1);
    // A direct step link may arrive before that provider's walkthrough mounts.
    if (fragment.startsWith(`${agentId}-step-`)) document.getElementById(fragment)?.scrollIntoView({ block: "start" });
  }, [agentId]);
  const choose = useCallback((id: string) => {
    setAgentId(id);
    window.history.replaceState(null, "", `#${id}`);
  }, []);
  return (
    <div className="relative min-h-screen overflow-x-clip bg-background">
      <main id="main-content" tabIndex={-1}>
        <nav aria-label="Cloud setup navigation" className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-5 pt-5 sm:px-8">
          <Link href="/" className={`${footerLink} gap-2 font-mono text-sm font-semibold`}><Terminal className="size-5 text-primary" aria-hidden="true" />Agent Flywheel</Link>
          <a href={CLAUDE_CODE_WEB_SCRIPT_SOURCE_URL} target="_blank" rel="noopener noreferrer" className={`${footerLink} gap-2 text-sm text-muted-foreground`}>View source<ExternalLink className="size-4" aria-hidden="true" /></a>
        </nav>
        <section className="mx-auto grid max-w-6xl items-center gap-10 px-5 py-10 sm:px-8 sm:py-12 lg:grid-cols-[1.1fr_0.9fr]">
          <div>
            <p className="mb-5 flex items-center gap-2 font-mono text-xs uppercase tracking-widest text-primary"><Cloud className="size-4" aria-hidden="true" />Cloud agent setup</p>
            <h1 className="max-w-3xl text-4xl font-semibold leading-[1.08] tracking-tight sm:text-5xl lg:text-6xl">Give your cloud agent <span className="text-primary">a flywheel.</span></h1>
            <p className="mt-5 max-w-xl text-base leading-relaxed text-muted-foreground sm:text-lg">Tools for tasks, coordination, code checks and reusable skills. Let ChatGPT handle the setup, or follow our illustrated guide.</p>
            <div className="mt-5 flex flex-wrap gap-x-4 gap-y-2 text-xs font-medium text-muted-foreground"><span className="inline-flex items-center gap-1.5"><ShieldCheck className="size-4 text-primary" aria-hidden="true" />Verified prebuilt tools</span><span className="inline-flex items-center gap-1.5"><Copy className="size-4 text-primary" aria-hidden="true" />Copy-ready scripts</span></div>
            <AgentSetupLauncher agentId={agentId} choose={choose} />
          </div>
          <div className="hidden lg:block"><GuidePreview /></div>
        </section>
        <CloudWorkbench agentId={agentId} choose={choose} />
        <section aria-labelledby="network-heading" className="border-y border-border/40 bg-card/30">
          <div className="mx-auto grid max-w-6xl gap-6 px-5 py-8 sm:px-8 lg:grid-cols-[0.8fr_1.2fr]">
            <div><h2 id="network-heading" className="text-lg font-semibold">Two public download domains</h2><p className="mt-2 text-sm leading-relaxed text-muted-foreground">No credentials or repository ownership needed. Use Full access, or allow these hosts in your provider&apos;s policy.</p></div>
            <div className="min-w-0"><ul className="space-y-2 font-mono text-sm text-primary"><li className="break-all">raw.githubusercontent.com</li><li className="break-all">downloads.agent-flywheel.com</li></ul><p className="mt-3 text-sm leading-relaxed text-muted-foreground">Locked-down environments try pinned public release fallbacks and keep existing tools. Check the log for missing tools; setup never falls back to a source build.</p></div>
          </div>
        </section>

        {/* ============================= TOOLS ============================= */}
        <section className="border-y border-border/30 bg-card/20 py-24">
          <div className="mx-auto max-w-6xl px-6">
            <SectionHeading eyebrow="what lands on PATH" title="Tools that carry the work forward" />
            <div className="grid gap-x-10 sm:grid-cols-2">
              {CLAUDE_CODE_WEB_TOOLS.map((tool) => (
                <div
                  key={tool.id}
                  className="min-w-0 border-b border-border/50 py-5"
                >
                  <div className="mb-2 flex flex-wrap items-baseline justify-between gap-3">
                    <h3 className="font-semibold">{tool.name}</h3>
                    <code className="break-all font-mono text-xs text-primary">
                      {tool.command}
                    </code>
                  </div>
                  <p className="text-sm leading-relaxed text-muted-foreground">{tool.role}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* =========================== BEHAVIOR =========================== */}
        <details className="mx-auto max-w-6xl px-6 py-8">
          <summary className="min-h-11 cursor-pointer rounded-md py-3 text-xl font-semibold focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">How installation works</summary>
          <div className="mt-5 grid gap-6 sm:grid-cols-2">
            {BEHAVIORS.map((behavior) => (
              <div
                key={behavior.title}
                className="rounded-2xl border border-border/50 bg-card/50 p-6 backdrop-blur-sm"
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
              </div>
            ))}
          </div>
        </details>

        {/* ========================== LEFT OUT ========================== */}
        <details className="mx-auto max-w-6xl border-t border-border/30 px-6 py-8">
          <summary className="min-h-11 cursor-pointer rounded-md py-3 text-xl font-semibold focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">What this bundle leaves out</summary>
          <div className="mx-auto max-w-4xl px-6">
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
        </details>

        {/* =========================== OPTIONS =========================== */}
        <details className="mx-auto max-w-6xl border-t border-border/30 px-6 py-8">
          <summary className="mb-4 min-h-11 cursor-pointer rounded-md py-3 text-xl font-semibold focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">Options and network troubleshooting</summary>
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
        </details>

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
                  className={`${footerLink} text-primary`}
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
