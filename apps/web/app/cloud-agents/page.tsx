"use client";

import {
  AlertTriangle,
  ArrowDown,
  ArrowRight,
  BookOpen,
  Brain,
  Check,
  ChevronDown,
  CircleCheck,
  CircleDashed,
  CircleX,
  Clock,
  Cloud,
  Copy,
  ExternalLink,
  Eye,
  EyeOff,
  FileText,
  GitBranch,
  ListChecks,
  Mail,
  Maximize2,
  Minimize2,
  RotateCcw,
  ScanSearch,
  ShieldCheck,
  Sparkles,
  Terminal,
  X,
  ZoomIn,
} from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { Button } from "@/components/ui/button";
import {
  CLAUDE_CODE_WEB_LEFT_OUT,
  CLAUDE_CODE_WEB_OPTIONS,
  CLAUDE_CODE_WEB_SCRIPT_SOURCE_URL,
  CLAUDE_CODE_WEB_TOOLS,
  CLOUD_AGENTS,
  CLOUD_AGENT_RESEARCH_DATE,
  CLOUD_EXECUTABLES,
  cloudSubsetRecipe,
  type CloudAgent,
  type ClaudeCodeWebToolGroup,
} from "@/lib/claude-code-web";
import { copyTextToClipboard, safeGetItem, safeSetItem } from "@/lib/utils";
import { CLOUD_WALKTHROUGHS, getCloudAgentSetupInstructions, type SetupScreenshot, type SetupStep } from "@/lib/cloud-agent-walkthroughs";

const GITHUB_URL = "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup";
const README_URL = `${GITHUB_URL}#cloud-agent-environments`;
const DOWNLOAD_HOSTS = "raw.githubusercontent.com\ndownloads.agent-flywheel.com";
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const [researchYear, researchMonth, researchDay] = CLOUD_AGENT_RESEARCH_DATE.split("-").map(Number);
const RESEARCH_DATE_LABEL = `${researchDay} ${MONTHS[researchMonth - 1]} ${researchYear}`;

const focusRing = "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background";
const textLink = `inline-flex min-h-11 items-center gap-1.5 rounded-sm underline-offset-4 transition-colors hover:text-foreground hover:underline ${focusRing}`;
// The theme's text-3xl/4xl scale is fluid up to 64px; section titles use a fixed, calmer step.
const sectionTitle = "text-[1.875rem] font-semibold leading-tight tracking-tight text-foreground sm:text-[2.5rem]";

const EVIDENCE_STYLE: Record<CloudAgent["evidence"], { dot: string; badge: string }> = {
  "Hosted test": { dot: "bg-emerald-400", badge: "border-emerald-400/30 bg-emerald-400/10 text-emerald-300" },
  "Documented workflow": { dot: "bg-sky-400", badge: "border-sky-400/30 bg-sky-400/10 text-sky-300" },
  "Needs investigation": { dot: "bg-amber-400", badge: "border-amber-400/30 bg-amber-400/10 text-amber-300" },
  "Linux template": { dot: "bg-violet-400", badge: "border-violet-400/30 bg-violet-400/10 text-violet-300" },
};

const BEHAVIORS = [
  {
    icon: ShieldCheck,
    title: "Verified prebuilt tools",
    description:
      "Every bundle is checked against cloud-mirror.json in the ACFS repository before extraction. Upstream checksums and available signatures were verified when the mirror was published. Nothing compiles and no upstream installer runs in your session.",
  },
  {
    icon: Clock,
    title: "Bounded setup time",
    description:
      "Tool jobs run in parallel. Each has a 180-second deadline covering its download, install and version checks, so setup fits inside the provider's setup window.",
  },
  {
    icon: AlertTriangle,
    title: "Failures stay visible",
    description:
      "The installer always exits 0, so one unavailable tool never blocks session startup. Read the summary and setup log: a finished script does not mean every tool installed.",
  },
  {
    icon: Mail,
    title: "Agent Mail without a daemon",
    description:
      "Claude gets an on-demand stdio MCP server. Other recipes expose the Agent Mail CLI without starting a daemon or changing provider MCP settings.",
  },
  {
    icon: FileText,
    title: "A guide the agent can read",
    description:
      "A managed instruction block lists working tools, commands and failures. Claude loads it automatically; other agents need the explicit guide-loading instructions in their recipe.",
  },
];

const TOOL_GROUPS: { id: ClaudeCodeWebToolGroup; title: string; blurb: string; icon: typeof ListChecks; span: string; wide?: boolean }[] = [
  { id: "Plan", title: "Plan the work", blurb: "Issues that live in the repo, triaged by what they unblock.", icon: ListChecks, span: "lg:col-span-2" },
  { id: "Coordinate", title: "Coordinate", blurb: "Messages and file reservations between agents.", icon: Mail, span: "lg:col-span-2" },
  { id: "Check", title: "Check the code", blurb: "Bug scans and structural search before a commit.", icon: ScanSearch, span: "lg:col-span-2" },
  { id: "Remember", title: "Remember", blurb: "Search past sessions and recall learned procedures.", icon: Brain, span: "lg:col-span-3", wide: true },
  { id: "Skills", title: "Skills and prompts", blurb: "Reusable skills and a prompt library from the terminal.", icon: Sparkles, span: "sm:col-span-2 lg:col-span-3", wide: true },
];
// Wide group cards lay their tools out in a row, one column per tool.
const WIDE_GROUP_COLUMNS: Record<number, string> = { 2: "lg:grid-cols-2", 3: "lg:grid-cols-3" };

/* ------------------------------------------------------------------ */
/* Copy                                                                */
/* ------------------------------------------------------------------ */

type CopyState = "idle" | "copying" | "copied" | "error";

function useBoundedCopy(text: string) {
  const [state, setState] = useState<CopyState>("idle");
  const resetTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const deadline = useRef<ReturnType<typeof setTimeout> | null>(null);
  const active = useRef(true);

  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
      if (resetTimer.current) clearTimeout(resetTimer.current);
      if (deadline.current) clearTimeout(deadline.current);
    };
  }, []);

  const copy = useCallback(async () => {
    if (resetTimer.current) clearTimeout(resetTimer.current);
    setState("copying");
    let ok = false;
    try {
      // Some browsers leave clipboard permission requests pending indefinitely.
      ok = await Promise.race([
        copyTextToClipboard(text),
        new Promise<boolean>((resolve) => {
          deadline.current = setTimeout(() => resolve(false), 8000);
        }),
      ]);
    } catch {
      // The error state below keeps the text selectable.
    } finally {
      if (deadline.current) clearTimeout(deadline.current);
      deadline.current = null;
    }
    if (!active.current) return;
    setState(ok ? "copied" : "error");
    if (ok) resetTimer.current = setTimeout(() => setState("idle"), 2000);
  }, [text]);

  return { state, copy };
}

function CodePanel({ text, title, label, copyLabel, className = "" }: {
  text: string;
  title: string;
  label: string;
  copyLabel: string;
  className?: string;
}) {
  const { state, copy } = useBoundedCopy(text);
  const lang = text.startsWith("#!/bin/bash") ? "bash" : text.startsWith("# Merge") ? "yaml" : "text";
  return (
    <div className={`terminal-window min-w-0 w-full text-left shadow-xl shadow-black/30 ring-1 ring-white/[0.04] ${className}`}>
      <div className="flex min-h-12 items-center gap-3 border-b border-white/[0.07] bg-white/[0.03] py-1 pl-4 pr-1.5">
        <Terminal className="size-4 shrink-0 text-[#7aa2f7]" aria-hidden="true" />
        <span title={title} className="min-w-0 flex-1 truncate font-mono text-xs text-[#a9b1d6]">{title}</span>
        <span className="hidden rounded border border-white/10 px-1.5 py-0.5 font-mono text-[10px] uppercase tracking-wider text-[#a9b1d6]/70 sm:inline">{lang}</span>
        <button
          type="button"
          onClick={copy}
          disabled={state === "copying"}
          aria-label={copyLabel}
          className={`inline-flex min-h-11 shrink-0 items-center gap-1.5 rounded-lg px-3 text-sm font-medium transition-colors disabled:opacity-70 ${focusRing} ${state === "copied" ? "text-[#9ece6a]" : "text-[#c0caf5] hover:bg-white/[0.07]"}`}
        >
          {state === "copied" ? <Check className="size-4" aria-hidden="true" /> : <Copy className="size-4" aria-hidden="true" />}
          {state === "copied" ? "Copied" : state === "copying" ? "Copying…" : "Copy"}
        </button>
        <span role="status" aria-live="polite" className="sr-only">{state === "copied" ? `${title} copied to clipboard` : ""}</span>
      </div>
      <pre
        tabIndex={0}
        role="region"
        aria-label={label}
        className="whitespace-pre-wrap break-words p-4 font-mono text-[13px] leading-relaxed text-[#c0caf5] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[#9ece6a]/60 sm:p-5"
      >
        <code>{text}</code>
      </pre>
      {state === "error" && (
        <p role="alert" className="border-t border-amber-400/30 px-4 py-3 text-sm text-amber-200 sm:px-5">
          Clipboard access failed. Select the text above and copy it manually, or try Copy again.
        </p>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Provider picker and agent hand-off                                  */
/* ------------------------------------------------------------------ */

function EvidenceBadge({ evidence, className = "" }: { evidence: CloudAgent["evidence"]; className?: string }) {
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium ${EVIDENCE_STYLE[evidence].badge} ${className}`}>
      <span aria-hidden="true" className={`size-1.5 rounded-full ${EVIDENCE_STYLE[evidence].dot}`} />
      {evidence}
    </span>
  );
}

function ProviderPicker({ agentId, choose }: { agentId: string; choose: (id: string) => void }) {
  return (
    <fieldset id="choose-agent" className="min-w-0">
      <legend className="mb-3 text-sm font-semibold text-foreground">
        <span className="mr-2 font-mono text-primary">1</span>Choose your cloud agent
      </legend>
      <div className="grid grid-cols-2 gap-2">
        {CLOUD_AGENTS.map((item) => {
          const selected = item.id === agentId;
          return (
            <label
              key={item.id}
              className={`relative flex min-h-[3.75rem] min-w-0 cursor-pointer items-center gap-2.5 rounded-xl border px-2.5 py-2 transition-colors last:col-span-2 has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-primary has-[:focus-visible]:ring-offset-2 has-[:focus-visible]:ring-offset-card sm:gap-3 sm:px-3 ${selected ? "border-primary/70 bg-primary/10 shadow-[0_0_0_1px_oklch(0.75_0.18_195/0.35),0_8px_24px_-12px_oklch(0.75_0.18_195/0.5)]" : "border-border/70 bg-background/40 hover:border-primary/40 hover:bg-background/70"}`}
            >
              <input
                type="radio"
                name="cloud-agent"
                value={item.id}
                checked={selected}
                onChange={() => choose(item.id)}
                className="sr-only"
              />
              <span aria-hidden="true" className={`flex size-8 shrink-0 items-center justify-center rounded-lg font-mono text-[11px] font-bold transition-colors max-sm:hidden ${selected ? "bg-primary text-primary-foreground" : "bg-muted text-foreground/80"}`}>{item.initials}</span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-semibold text-foreground">{item.name}</span>
                <span className="mt-0.5 flex items-center gap-1.5 text-[11px] text-muted-foreground sm:text-xs">
                  <span aria-hidden="true" className={`size-1.5 shrink-0 rounded-full ${EVIDENCE_STYLE[item.evidence].dot}`} />
                  <span className="truncate">{item.evidence}</span>
                </span>
              </span>
              {selected && <Check className="size-4 shrink-0 text-primary max-sm:hidden" aria-hidden="true" />}
            </label>
          );
        })}
      </div>
    </fieldset>
  );
}

function HandoffCard({ agent }: { agent: CloudAgent }) {
  const brief = useMemo(() => getCloudAgentSetupInstructions(agent.id), [agent.id]);
  const { state, copy } = useBoundedCopy(brief);
  const [preview, setPreview] = useState(false);
  return (
    <div className="rounded-2xl border border-primary/35 bg-gradient-to-b from-primary/[0.09] to-primary/[0.03] p-4 sm:p-5">
      <p className="inline-flex items-center gap-1.5 rounded-full bg-primary/15 px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wider text-primary">
        <Sparkles className="size-3" aria-hidden="true" />Recommended
      </p>
      <h2 className="mt-2.5 text-base font-semibold tracking-tight text-foreground">Let a browser agent set it up</h2>
      <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">
        Copy one complete brief and paste it into a ChatGPT chat with computer use enabled, or any agent that can operate your browser. It follows every click, fills in the scripts and asks before sign-ins or policy changes.
      </p>
      {agent.id === "muse" && <p className="mt-2 text-xs leading-relaxed text-amber-200/90">Muse starts with a capability check; installation support is unverified.</p>}
      <div className="mt-4 flex flex-col gap-2 sm:flex-row sm:items-center">
        <Button
          type="button"
          size="lg"
          onClick={copy}
          disabled={state === "copying"}
          aria-label={`Copy full instructions for ${agent.name}`}
          className="min-h-12 gap-2 bg-primary px-5 text-base font-semibold text-primary-foreground shadow-[0_10px_30px_-10px_oklch(0.75_0.18_195/0.7)] hover:bg-primary/90"
        >
          {state === "copied" ? <Check className="size-5 shrink-0" aria-hidden="true" /> : <Copy className="size-5 shrink-0" aria-hidden="true" />}
          {state === "copied" ? "Full instructions copied" : state === "copying" ? "Copying…" : "Copy full instructions"}
        </Button>
        <button
          type="button"
          aria-expanded={preview}
          aria-controls="handoff-preview"
          onClick={() => setPreview((open) => !open)}
          className={`inline-flex min-h-11 items-center justify-center gap-2 rounded-lg px-3 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted/50 hover:text-foreground ${focusRing}`}
        >
          {preview ? <EyeOff className="size-4" aria-hidden="true" /> : <Eye className="size-4" aria-hidden="true" />}
          {preview ? "Hide brief" : "Preview brief"}
        </button>
      </div>
      <span role="status" aria-live="polite" className="sr-only">{state === "copied" ? `${agent.name} full instructions copied to clipboard` : ""}</span>
      {state === "error" && (
        <p role="alert" className="mt-3 text-sm leading-relaxed text-amber-200">
          Clipboard access failed. Open the preview, select the whole brief and copy it, or try again.
        </p>
      )}
      {(preview || state === "error") && (
        <pre
          id="handoff-preview"
          tabIndex={0}
          role="region"
          aria-label={`Full agent instructions for ${agent.name}`}
          className="mt-3 max-h-72 overflow-auto whitespace-pre-wrap break-words rounded-xl border border-border/60 bg-background/80 p-3 font-mono text-xs leading-relaxed text-foreground/85 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        >
          {brief}
        </pre>
      )}
      <p className="mt-3 text-xs leading-relaxed text-muted-foreground">
        Every step, field value, script and verification check for {agent.name}, in one paste.
      </p>
    </div>
  );
}

function ScriptTeaser({ agent }: { agent: CloudAgent }) {
  if (!agent.script) {
    return (
      <p className="flex gap-3 rounded-2xl border border-amber-400/25 bg-amber-400/[0.05] p-4 text-sm leading-relaxed text-muted-foreground">
        <AlertTriangle className="mt-0.5 size-4 shrink-0 text-amber-400" aria-hidden="true" />
        <span><strong className="font-semibold text-foreground">No install script for {agent.name} yet.</strong> A supported setup hook has not been established, so the guide starts with a capability check before anything is installed.</span>
      </p>
    );
  }
  const caption = agent.id === "claude"
    ? "That is the entire Claude setup script. The guide shows the exact field."
    : agent.id === "codex"
      ? "The Codex install script. New tasks also need the instructions from the guide."
      : agent.id === "generic"
        ? "The provider-neutral Linux script. Paste it into your provider's setup hook."
        : `The provider-neutral Linux script. The guide shows where ${agent.name} runs it.`;
  return (
    <div className="min-w-0">
      <p className="mb-3 text-sm leading-relaxed text-muted-foreground">
        <span className="font-medium text-foreground">Know your way around? </span>{caption}
      </p>
      <CodePanel text={agent.script} title={`${agent.name} · setup script`} label={`${agent.name} setup script preview`} copyLabel={`Copy ${agent.name} setup script`} />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Screenshots                                                         */
/* ------------------------------------------------------------------ */

function Highlights({ shot }: { shot: SetupScreenshot }) {
  return (
    <>
      {(shot.highlights ?? []).map((box, index) => (
        <span
          key={box.label}
          aria-hidden="true"
          className="pointer-events-none absolute rounded-md border-2 border-[oklch(0.58_0.15_205)] shadow-[0_0_0_3px_oklch(0.75_0.18_195/0.3),0_0_22px_oklch(0.75_0.18_195/0.45)]"
          style={{ left: `${box.x}%`, top: `${box.y}%`, width: `${box.w}%`, height: `${box.h}%` }}
        >
          {/* Badges sit on the right edge so they never cover the label they mark. */}
          <span className={`absolute -top-2.5 flex size-5 items-center justify-center rounded-full bg-primary font-mono text-[11px] font-bold text-primary-foreground shadow-md ring-2 ring-white ${box.x + box.w > 95 ? "-left-2.5" : "-right-2.5"}`}>
            {index + 1}
          </span>
        </span>
      ))}
    </>
  );
}

function HighlightLegend({ shot, className = "" }: { shot: SetupScreenshot; className?: string }) {
  if (!shot.highlights?.length) return null;
  return (
    <ol aria-label="Highlighted controls" className={`flex flex-wrap gap-x-4 gap-y-1.5 text-xs text-foreground/85 ${className}`}>
      {shot.highlights.map((box, index) => (
        <li key={box.label} className="inline-flex items-center gap-1.5">
          <span aria-hidden="true" className="flex size-[18px] items-center justify-center rounded-full bg-primary font-mono text-[10px] font-bold text-primary-foreground">{index + 1}</span>
          {box.label}
        </li>
      ))}
    </ol>
  );
}

/** Safari does not focus a clicked button, so the trigger is passed explicitly for focus return. */
type OpenShot = (shot: SetupScreenshot, opener: HTMLElement) => void;

function ShotFigure({ shot, sizes, onOpen }: { shot: SetupScreenshot; sizes: string; onOpen: OpenShot }) {
  const ratio = shot.width / shot.height;
  return (
    <figure className="min-w-0">
      <div
        className="mx-auto overflow-hidden rounded-xl border border-white/10 bg-[#f6f6f7] shadow-2xl shadow-black/50"
        style={{ maxWidth: `min(100%, ${(34 * ratio).toFixed(2)}rem)` }}
      >
        <div className="relative">
          <Image src={shot.src} alt={shot.alt} width={shot.width} height={shot.height} sizes={sizes} className="block h-auto w-full" />
          <Highlights shot={shot} />
          <button
            type="button"
            onClick={(event) => onOpen(shot, event.currentTarget)}
            aria-label={`Enlarge screenshot: ${shot.alt}`}
            className="group absolute inset-0 flex cursor-zoom-in items-end justify-end p-2.5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
          >
            <span className="inline-flex size-8 items-center justify-center gap-1.5 rounded-full bg-black/70 text-xs font-medium text-white shadow-lg backdrop-blur transition-opacity sm:size-auto sm:px-3 sm:py-1.5 sm:opacity-0 sm:group-hover:opacity-100 sm:group-focus-visible:opacity-100">
              <ZoomIn className="size-4 sm:size-3.5" aria-hidden="true" /><span className="max-sm:hidden">Enlarge</span>
            </span>
          </button>
        </div>
      </div>
      <figcaption className="mx-auto mt-3 space-y-2" style={{ maxWidth: `min(100%, ${(34 * ratio).toFixed(2)}rem)` }}>
        <HighlightLegend shot={shot} />
        <p className="text-xs leading-relaxed text-muted-foreground">{shot.caption}</p>
      </figcaption>
    </figure>
  );
}

function Lightbox({ shot, opener, onClose }: { shot: SetupScreenshot; opener: HTMLElement; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const closeButton = useRef<HTMLButtonElement>(null);
  const [actualSize, setActualSize] = useState(false);
  const ratio = shot.width / shot.height;

  useEffect(() => {
    const node = dialog.current;
    if (!node) return;
    const root = document.documentElement;
    const previousOverflow = root.style.overflow;
    root.style.overflow = "hidden";
    if (!node.open) node.showModal();
    closeButton.current?.focus();
    return () => {
      root.style.overflow = previousOverflow;
      if (node.open) node.close();
      if (opener.isConnected) opener.focus();
    };
  }, [opener]);

  return (
    <dialog
      ref={dialog}
      aria-label={`Screenshot: ${shot.alt}`}
      // `close` is queued as a task; a stale one from an effect cleanup must not
      // dismiss a dialog that has already been reopened.
      onClose={() => { if (!dialog.current?.open) onClose(); }}
      onClick={(event) => { if (event.target === event.currentTarget) onClose(); }}
      className="fixed inset-0 m-0 h-dvh max-h-none w-screen max-w-none bg-[oklch(0.08_0.015_260)] p-0 text-foreground backdrop:bg-black/80"
    >
      <div className="flex h-full flex-col" onClick={(event) => { if (event.target === event.currentTarget) onClose(); }}>
        <div className="flex min-h-14 shrink-0 items-center gap-2 border-b border-white/10 bg-black/40 px-3 sm:px-5">
          <p className="min-w-0 flex-1 truncate text-sm text-foreground/90">{shot.caption}</p>
          <button
            type="button"
            onClick={() => setActualSize((value) => !value)}
            className={`inline-flex min-h-11 items-center gap-1.5 rounded-lg px-3 text-sm text-foreground/90 hover:bg-white/10 ${focusRing}`}
          >
            {actualSize ? <Minimize2 className="size-4" aria-hidden="true" /> : <Maximize2 className="size-4" aria-hidden="true" />}
            <span className="hidden sm:inline">{actualSize ? "Fit to screen" : "Actual size"}</span>
            <span className="sr-only sm:hidden">{actualSize ? "Fit to screen" : "Actual size"}</span>
          </button>
          <a
            href={shot.src}
            target="_blank"
            rel="noopener noreferrer"
            className={`inline-flex min-h-11 items-center gap-1.5 rounded-lg px-3 text-sm text-foreground/90 hover:bg-white/10 ${focusRing}`}
          >
            <ExternalLink className="size-4" aria-hidden="true" />
            <span className="hidden sm:inline">Original</span>
            <span className="sr-only sm:hidden">Open original (new tab)</span>
          </a>
          <button
            ref={closeButton}
            type="button"
            onClick={onClose}
            aria-label="Close screenshot"
            className={`inline-flex size-11 items-center justify-center rounded-lg text-foreground hover:bg-white/10 ${focusRing}`}
          >
            <X className="size-5" aria-hidden="true" />
          </button>
        </div>
        <div className="min-h-0 flex-1 overflow-auto overscroll-contain">
          <div className="flex min-h-full p-3 sm:p-8" onClick={(event) => { if (event.target === event.currentTarget) onClose(); }}>
            <div
              className="relative m-auto shrink-0 overflow-hidden rounded-lg bg-[#f6f6f7] shadow-2xl"
              style={actualSize
                ? { width: `${Math.round(shot.width / 2)}px`, aspectRatio: `${shot.width} / ${shot.height}` }
                : { width: `min(100%, calc((100dvh - 9rem) * ${ratio.toFixed(4)}))`, aspectRatio: `${shot.width} / ${shot.height}` }}
            >
              <Image src={shot.src} alt={shot.alt} fill unoptimized sizes="100vw" className="object-contain" />
              <Highlights shot={shot} />
            </div>
          </div>
        </div>
        {shot.highlights?.length ? (
          <div className="shrink-0 border-t border-white/10 bg-black/40 px-4 py-3 sm:px-5">
            <HighlightLegend shot={shot} />
          </div>
        ) : null}
      </div>
    </dialog>
  );
}

/* ------------------------------------------------------------------ */
/* Step progress (local, per provider)                                 */
/* ------------------------------------------------------------------ */

const PROGRESS_KEY = "acfs-cloud-agents-progress-v1";
const PROGRESS_EVENT = "acfs:cloud-agents-progress";
// Mirrors the last write so marking steps still works when storage is unavailable.
let progressMemory: string | null = null;

function subscribeProgress(onChange: () => void) {
  window.addEventListener("storage", onChange);
  window.addEventListener(PROGRESS_EVENT, onChange);
  return () => {
    window.removeEventListener("storage", onChange);
    window.removeEventListener(PROGRESS_EVENT, onChange);
  };
}

function readProgress(): string | null {
  return safeGetItem(PROGRESS_KEY) ?? progressMemory;
}

function parseProgress(raw: string | null): Record<string, string[]> {
  if (!raw) return {};
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    const result: Record<string, string[]> = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (Array.isArray(value)) result[key] = value.filter((item): item is string => typeof item === "string");
    }
    return result;
  } catch {
    return {};
  }
}

function useStepProgress(agentId: string, steps: SetupStep[]) {
  const raw = useSyncExternalStore(subscribeProgress, readProgress, () => null);
  const all = useMemo(() => parseProgress(raw), [raw]);
  const done = useMemo(() => new Set((all[agentId] ?? []).filter((id) => steps.some((step) => step.id === id))), [all, agentId, steps]);

  const write = useCallback((next: Record<string, string[]>) => {
    progressMemory = JSON.stringify(next);
    safeSetItem(PROGRESS_KEY, progressMemory);
    window.dispatchEvent(new Event(PROGRESS_EVENT));
  }, []);

  const toggle = useCallback((stepId: string) => {
    const current = new Set(done);
    if (current.has(stepId)) current.delete(stepId);
    else current.add(stepId);
    write({ ...all, [agentId]: [...current] });
  }, [agentId, all, done, write]);

  const reset = useCallback(() => {
    const next = { ...all };
    delete next[agentId];
    write(next);
  }, [agentId, all, write]);

  return { done, toggle, reset };
}

/* ------------------------------------------------------------------ */
/* Guide                                                               */
/* ------------------------------------------------------------------ */

const stepAnchor = (agentId: string, stepId: string) => `${agentId}-step-${stepId}`;

function StepBody({ agent, step, onOpenShot }: { agent: CloudAgent; step: SetupStep; onOpenShot: OpenShot }) {
  const shot = step.screenshot;
  const wide = shot ? shot.width / shot.height > 1 : false;
  const paragraphs = step.paragraphs.map((paragraph) => (
    <p key={paragraph} className="max-w-[65ch] text-[15px] leading-relaxed text-muted-foreground sm:text-base">{paragraph}</p>
  ));
  const details = (
    <>
      {step.fields && (
        <div className="max-w-2xl rounded-xl border border-border/70 bg-card/50 p-3 sm:p-4">
          <p className="mb-2 text-[11px] font-semibold uppercase tracking-[0.14em] text-primary">Where this goes</p>
          <dl className="grid gap-2 sm:grid-cols-2">
            {step.fields.map((field) => (
              <div key={field.label} className="min-w-0 rounded-lg border border-border/60 bg-background/60 px-3 py-2">
                <dt className="text-xs text-muted-foreground">{field.label}</dt>
                <dd className="mt-0.5 break-words text-sm font-medium text-foreground">{field.value}</dd>
              </div>
            ))}
          </dl>
        </div>
      )}
      {step.paste && (
        <CodePanel
          text={step.paste.text}
          title={step.paste.title}
          copyLabel={step.paste.label}
          label={step.paste.regionLabel ?? `${agent.name}: ${step.paste.title}`}
        />
      )}
      {step.note && (
        <p className="flex max-w-2xl gap-3 rounded-xl border border-amber-400/25 bg-amber-400/[0.06] px-4 py-3 text-sm leading-relaxed text-foreground/90">
          <AlertTriangle className="mt-0.5 size-4 shrink-0 text-amber-400" aria-hidden="true" />
          <span>{step.note}</span>
        </p>
      )}
    </>
  );

  if (!shot) return <div className="min-w-0 space-y-4">{paragraphs}{details}</div>;
  if (wide) {
    return (
      <div className="min-w-0 space-y-5">
        <div className="space-y-4">{paragraphs}</div>
        <ShotFigure shot={shot} sizes="(min-width: 1024px) 800px, (min-width: 640px) 90vw, 100vw" onOpen={onOpenShot} />
        {details}
      </div>
    );
  }
  return (
    <div className="grid min-w-0 gap-6 md:grid-cols-[minmax(0,1fr)_minmax(0,18rem)] lg:grid-cols-[minmax(0,1fr)_minmax(0,20rem)] lg:gap-8">
      <div className="min-w-0 space-y-4">{paragraphs}{details}</div>
      <ShotFigure shot={shot} sizes="(min-width: 768px) 320px, 90vw" onOpen={onOpenShot} />
    </div>
  );
}

function GuideSection({ agent, choose, onOpenShot }: { agent: CloudAgent; choose: (id: string) => void; onOpenShot: OpenShot }) {
  const walkthrough = CLOUD_WALKTHROUGHS[agent.id];
  const steps = walkthrough.steps;
  const { done, toggle, reset } = useStepProgress(agent.id, steps);
  const [active, setActive] = useState(0);
  const [stepsOpen, setStepsOpen] = useState(false);
  const stepRefs = useRef<(HTMLLIElement | null)[]>([]);
  const mobileBar = useRef<HTMLDivElement>(null);
  const activeIndex = Math.min(active, steps.length - 1);
  const hosted = agent.evidence === "Hosted test";

  useEffect(() => {
    // The active step is the last one whose top has passed a reading line;
    // above the first step that is step 1, so the rail never shows stale state.
    let frame = 0;
    const update = () => {
      frame = 0;
      const line = window.innerHeight * 0.35;
      let index = 0;
      stepRefs.current.forEach((node, i) => {
        if (node && node.getBoundingClientRect().top <= line) index = i;
      });
      setActive(index);
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };
    schedule();
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", schedule);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
    };
  }, []);

  useEffect(() => {
    if (!stepsOpen) return;
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") setStepsOpen(false); };
    const onPointer = (event: PointerEvent) => {
      if (mobileBar.current && !mobileBar.current.contains(event.target as Node)) setStepsOpen(false);
    };
    window.addEventListener("keydown", onKey);
    window.addEventListener("pointerdown", onPointer);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("pointerdown", onPointer);
    };
  }, [stepsOpen]);

  const switcher = (id: string) => (
    <label className="block text-xs font-medium text-muted-foreground">
      Switch cloud agent
      <span className="relative mt-1.5 block">
        <select
          id={id}
          value={agent.id}
          onChange={(event) => choose(event.target.value)}
          className={`min-h-11 w-full appearance-none rounded-lg border border-border/80 bg-background py-2 pl-3 pr-9 text-sm text-foreground ${focusRing}`}
        >
          {CLOUD_AGENTS.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
        </select>
        <ChevronDown className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
      </span>
    </label>
  );

  const stepList = (onPick?: () => void) => (
    <ol className="space-y-0.5">
      {steps.map((step, index) => {
        const isDone = done.has(step.id);
        const isActive = index === activeIndex;
        return (
          <li key={step.id}>
            <a
              href={`#${stepAnchor(agent.id, step.id)}`}
              onClick={onPick}
              aria-current={isActive ? "step" : undefined}
              className={`flex min-h-11 items-start gap-3 rounded-lg px-2.5 py-2 text-sm leading-snug transition-colors ${focusRing} ${isActive ? "bg-primary/10 text-foreground" : "text-muted-foreground hover:bg-muted/40 hover:text-foreground"}`}
            >
              <span aria-hidden="true" className={`mt-px flex size-5 shrink-0 items-center justify-center rounded-full border font-mono text-[10px] font-semibold ${isDone ? "border-primary bg-primary text-primary-foreground" : isActive ? "border-primary text-primary" : "border-border text-muted-foreground"}`}>
                {isDone ? <Check className="size-3" /> : index + 1}
              </span>
              <span>{step.title}{isDone && <span className="sr-only"> (done)</span>}</span>
            </a>
          </li>
        );
      })}
    </ol>
  );

  const progressBar = (
    <div className="flex gap-1" aria-hidden="true">
      {steps.map((step, index) => (
        <span key={step.id} className={`h-1 flex-1 rounded-full transition-colors ${done.has(step.id) ? "bg-primary" : index === activeIndex ? "bg-primary/40" : "bg-border"}`} />
      ))}
    </div>
  );

  return (
    <section id="guide" aria-labelledby="guide-heading" className="relative mx-auto max-w-6xl scroll-mt-4 px-5 pb-20 pt-4 sm:px-8 sm:pb-28">
      <div className="grid gap-6 border-b border-border/60 pb-8 lg:grid-cols-[minmax(0,1.25fr)_minmax(0,0.75fr)] lg:items-end lg:gap-10">
        <div className="min-w-0">
          <p className="mb-3 flex flex-wrap items-center gap-x-3 gap-y-2 font-mono text-xs uppercase tracking-[0.18em] text-primary">
            <span className="inline-flex items-center gap-2"><BookOpen className="size-4" aria-hidden="true" />{steps.some((step) => step.screenshot) ? "Illustrated guide" : "Step-by-step guide"}</span>
            <EvidenceBadge evidence={agent.evidence} className="font-sans normal-case tracking-normal" />
          </p>
          <h2 id="guide-heading" className={sectionTitle}>Set up {agent.name}</h2>
          <p className="mt-3 max-w-2xl text-base leading-relaxed text-muted-foreground sm:text-[17px]">{walkthrough.introduction}</p>
          <p className="mt-2 max-w-2xl text-xs leading-relaxed text-muted-foreground/90">{walkthrough.visualEvidence} Checked {RESEARCH_DATE_LABEL}.</p>
        </div>
        <div className={`flex gap-3 rounded-2xl border p-4 text-sm leading-relaxed ${hosted ? "border-emerald-400/25 bg-emerald-400/[0.05]" : "border-amber-400/25 bg-amber-400/[0.05]"}`}>
          {hosted
            ? <ShieldCheck className="mt-0.5 size-5 shrink-0 text-emerald-400" aria-hidden="true" />
            : <AlertTriangle className="mt-0.5 size-5 shrink-0 text-amber-400" aria-hidden="true" />}
          <p className="text-muted-foreground"><strong className="text-foreground">What is verified. </strong>{agent.caveat}</p>
        </div>
      </div>

      {/* Mobile and tablet: a sticky progress bar with a step menu. */}
      <div ref={mobileBar} className="sticky top-0 z-30 -mx-5 mb-8 border-b border-border/60 bg-background px-5 shadow-[0_8px_24px_-12px_rgb(0_0_0/0.8)] sm:-mx-8 sm:px-8 lg:hidden">
        <div className="flex min-h-14 items-center gap-3 py-2">
          <div className="min-w-0 flex-1">
            <p className="font-mono text-[11px] uppercase tracking-wider text-muted-foreground">
              Step {activeIndex + 1} of {steps.length} · {done.size} done
            </p>
            <p className="truncate text-sm font-medium text-foreground">{steps[activeIndex].title}</p>
          </div>
          <button
            type="button"
            aria-expanded={stepsOpen}
            aria-controls="guide-step-menu"
            onClick={() => setStepsOpen((open) => !open)}
            className={`inline-flex min-h-11 shrink-0 items-center gap-1.5 rounded-lg border border-border/80 bg-card/60 px-3 text-sm font-medium text-foreground ${focusRing}`}
          >
            Steps<ChevronDown className={`size-4 transition-transform ${stepsOpen ? "rotate-180" : ""}`} aria-hidden="true" />
          </button>
        </div>
        <div className="pb-2">{progressBar}</div>
        {stepsOpen && (
          <div id="guide-step-menu" className="absolute inset-x-0 top-full max-h-[70dvh] overflow-y-auto overscroll-contain border-b border-border/60 bg-card px-5 pb-5 pt-3 shadow-2xl shadow-black/70 sm:px-8">
            <nav aria-label={`${agent.name} setup steps`}>{stepList(() => setStepsOpen(false))}</nav>
            <div className="mt-4 border-t border-border/60 pt-4">{switcher("guide-agent-mobile")}</div>
          </div>
        )}
      </div>

      <div className="lg:mt-10 lg:grid lg:grid-cols-[14.5rem_minmax(0,1fr)] lg:gap-12">
        <div className="hidden lg:block">
          <div className="sticky top-8 space-y-6">
            <nav aria-label={`${agent.name} steps`}>
              <p className="mb-2 px-2.5 font-mono text-[11px] uppercase tracking-[0.16em] text-muted-foreground">Steps</p>
              {stepList()}
            </nav>
            <div className="space-y-2 px-2.5">
              {progressBar}
              <div className="flex items-center justify-between text-xs text-muted-foreground">
                <span>{done.size} of {steps.length} marked done</span>
                {done.size > 0 && (
                  <button type="button" onClick={reset} className={`inline-flex min-h-8 items-center gap-1 rounded px-1 hover:text-foreground ${focusRing}`}>
                    <RotateCcw className="size-3" aria-hidden="true" />Reset
                  </button>
                )}
              </div>
            </div>
            <div className="border-t border-border/60 px-2.5 pt-5">{switcher("guide-agent-desktop")}</div>
          </div>
        </div>

        <ol aria-label={`${agent.name} setup walkthrough`} className="min-w-0">
          {steps.map((step, index) => {
            const isDone = done.has(step.id);
            const isActive = index === activeIndex;
            const next = steps[index + 1];
            return (
              <li
                key={step.id}
                id={stepAnchor(agent.id, step.id)}
                ref={(node) => { stepRefs.current[index] = node; }}
                className="relative scroll-mt-28 border-t border-border/50 pb-12 pt-10 first:border-t-0 first:pt-0 last:pb-0 sm:border-t-0 sm:pl-16 sm:pt-0 lg:scroll-mt-8"
              >
                {next && <span aria-hidden="true" className="absolute bottom-0 left-5 top-12 hidden w-px bg-gradient-to-b from-primary/50 via-border to-border/40 sm:block" />}
                <div className="flex items-start gap-4">
                  <span
                    aria-hidden="true"
                    className={`flex size-10 shrink-0 items-center justify-center rounded-full border font-mono text-sm font-semibold transition-colors sm:absolute sm:left-0 sm:top-0 ${isDone ? "border-primary bg-primary text-primary-foreground" : isActive ? "border-primary bg-primary/15 text-primary shadow-[0_0_0_5px_oklch(0.75_0.18_195/0.1)]" : "border-border bg-card text-muted-foreground"}`}
                  >
                    {isDone ? <Check className="size-5" /> : index + 1}
                  </span>
                  <div className="min-w-0 pt-0.5">
                    <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-muted-foreground">Step {index + 1} of {steps.length}</p>
                    <h3 className="mt-1 text-[1.3rem] font-semibold leading-snug tracking-tight text-foreground sm:text-[1.55rem]">{step.title}</h3>
                  </div>
                </div>
                <div className="mt-5">
                  <StepBody agent={agent} step={step} onOpenShot={onOpenShot} />
                  {agent.id === "muse" && step.id === "template" && (
                    <button type="button" onClick={() => choose("generic")} className={`${textLink} mt-3 text-sm font-semibold text-primary`}>
                      Open Linux template<ArrowRight className="size-4" aria-hidden="true" />
                    </button>
                  )}
                </div>
                <div className="mt-6 flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
                  <button
                    type="button"
                    aria-pressed={isDone}
                    aria-label={`Mark as done: ${step.title}`}
                    onClick={() => toggle(step.id)}
                    className={`inline-flex min-h-11 items-center gap-2 rounded-lg border px-3.5 text-sm font-medium transition-colors ${focusRing} ${isDone ? "border-primary/50 bg-primary/10 text-primary" : "border-border/80 text-muted-foreground hover:border-primary/40 hover:text-foreground"}`}
                  >
                    {isDone ? <CircleCheck className="size-4" aria-hidden="true" /> : <CircleDashed className="size-4" aria-hidden="true" />}
                    {isDone ? "Done" : "Mark as done"}
                  </button>
                  {next && (
                    <a href={`#${stepAnchor(agent.id, next.id)}`} className={`${textLink} text-sm font-medium text-primary`}>
                      Next: {next.title}<ArrowRight className="size-4 shrink-0" aria-hidden="true" />
                    </a>
                  )}
                </div>
              </li>
            );
          })}
        </ol>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */
/* What a run prints                                                   */
/* ------------------------------------------------------------------ */

type RunTone = "step" | "detail" | "ok" | "warn" | "prompt";
type RunLine = { tone: RunTone; parts: (string | { muted: string })[] };

const RUN_SECONDS: Record<string, number> = { claude: 12, codex: 6 };

function runLines(agentId: string, failed: boolean): RunLine[] {
  const mode = agentId === "claude" || agentId === "codex" ? agentId : "generic";
  const root = mode === "codex" ? "<repo>/.acfs-cloud" : "~";
  const guide = mode === "claude" ? "~/.claude/CLAUDE.md" : mode === "codex" ? `${root}/.codex/AGENTS.md` : "~/.acfs/cloud/AGENTS.md";
  const logs = `${root}/.acfs/cloud/logs/`;
  const ids = CLAUDE_CODE_WEB_TOOLS.map((tool) => tool.id);
  const seconds = RUN_SECONDS[agentId];
  const lines: RunLine[] = [
    { tone: "step", parts: [`[acfs-cloud] ACFS cloud setup: ${ids.join(" ")}`] },
    { tone: "detail", parts: ["    ACFS ref: main, whole tool job timeout: 180s"] },
    { tone: "detail", parts: [`    Installing ${ids[0]} … Installing ${ids[ids.length - 1]}`, { muted: `  # ${ids.length} parallel jobs` }] },
  ];
  if (mode === "claude") lines.push({ tone: "detail", parts: ["    Registered Agent Mail as the stdio MCP server 'mcp-agent-mail'"] });
  lines.push({ tone: "step", parts: ["[acfs-cloud] Summary (", seconds ? `${seconds}` : { muted: "n" }, "s)"] });
  for (const id of ids) {
    const label = `    ${id.padEnd(5)} `;
    // Illustrate a blocked tool when both public download paths are unavailable.
    if (failed && id === "jsm") lines.push({ tone: "warn", parts: [`${label}mirror and public release blocked/unavailable; use Full or Custom allowing the public download hosts; see ${logs}jsm.log; no source build attempted`] });
    else lines.push({ tone: "ok", parts: [label, { muted: "‹version›" }, " (verified prebuilt)"] });
  }
  lines.push({ tone: "detail", parts: [`    Guide for ${mode}: ${guide}; logs: ${logs}`] });
  if (failed) lines.push({ tone: "prompt", parts: ["$ echo $?", { muted: "   # the session still starts" }] }, { tone: "prompt", parts: ["0"] });
  return lines;
}

const RUN_TONE: Record<RunTone, string> = {
  step: "text-[#7aa2f7]",
  detail: "text-[#8a91b8]",
  ok: "text-[#9ece6a]",
  warn: "text-[#e0af68]",
  prompt: "text-[#c0caf5]",
};

function RunPreview({ agent }: { agent: CloudAgent }) {
  const [failed, setFailed] = useState(false);
  const [phase, setPhase] = useState<"static" | "armed" | "play">("static");
  const [replay, setReplay] = useState(0);
  const panel = useRef<HTMLDivElement>(null);
  const lines = useMemo(() => runLines(agent.id, failed), [agent.id, failed]);

  useEffect(() => {
    const node = panel.current;
    if (!node || typeof IntersectionObserver === "undefined") return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let first = true;
    const observer = new IntersectionObserver(([entry]) => {
      if (first) {
        first = false;
        // Already on screen: leave it static rather than blanking visible text.
        if (!entry.isIntersecting) setPhase("armed");
        else observer.disconnect();
        return;
      }
      if (entry.isIntersecting) {
        setPhase("play");
        observer.disconnect();
      }
    }, { rootMargin: "0px 0px -15% 0px" });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  const pick = (value: boolean) => {
    setFailed(value);
    setReplay((count) => count + 1);
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) setPhase("play");
  };

  return (
    <div ref={panel} className="terminal-window min-w-0 shadow-2xl shadow-black/40 ring-1 ring-white/[0.04]">
      <div className="flex flex-wrap items-center gap-2 border-b border-white/[0.07] bg-white/[0.03] px-4 py-2">
        <span className="mr-auto inline-flex items-center gap-2 font-mono text-xs text-[#a9b1d6]">
          <Terminal className="size-4 text-[#7aa2f7]" aria-hidden="true" />setup output · {agent.name}
        </span>
        <div role="group" aria-label="Example run" className="flex rounded-lg border border-white/10 bg-black/30 p-0.5">
          {[{ value: false, label: "Healthy run" }, { value: true, label: "One tool failed" }].map((option) => (
            <button
              key={option.label}
              type="button"
              aria-pressed={failed === option.value}
              onClick={() => pick(option.value)}
              className={`min-h-9 rounded-md px-2.5 text-xs font-medium transition-colors ${focusRing} ${failed === option.value ? "bg-white/10 text-[#c0caf5]" : "text-[#737aa2] hover:text-[#c0caf5]"}`}
            >
              {option.label}
            </button>
          ))}
        </div>
      </div>
      <pre
        key={`${agent.id}-${replay}`}
        tabIndex={0}
        role="region"
        aria-label={`Example setup output for ${agent.name}`}
        className="overflow-x-auto p-4 font-mono text-[12px] leading-[1.7] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[#9ece6a]/60 sm:p-5 sm:text-[13px]"
      >
        {lines.map((line, index) => (
          <span
            key={index}
            className={`block whitespace-pre-wrap pl-[4ch] -indent-[4ch] [overflow-wrap:anywhere] ${RUN_TONE[line.tone]} ${phase === "armed" ? "opacity-0" : ""}`}
            style={phase === "play" ? { animation: `slide-in-left 0.32s cubic-bezier(0.2, 0.7, 0.2, 1) ${index * 45}ms both` } : undefined}
          >
            {line.parts.map((part, partIndex) => typeof part === "string"
              ? <span key={partIndex}>{part}</span>
              : <span key={partIndex} className="text-[#737aa2]">{part.muted}</span>)}
          </span>
        ))}
      </pre>
      <p className="border-t border-white/[0.07] px-4 py-2.5 text-xs leading-relaxed text-[#8a91b8] sm:px-5">
        Abridged from the script&apos;s real summary. Times are from our hosted runs; versions vary.
      </p>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Shared section pieces                                               */
/* ------------------------------------------------------------------ */

function Disclosure({ title, summary, children }: { title: string; summary: string; children: ReactNode }) {
  return (
    <details className="group rounded-2xl border border-border/60 bg-card/30 transition-colors open:bg-card/50">
      <summary className={`flex min-h-16 cursor-pointer list-none items-center gap-4 rounded-2xl px-4 py-4 sm:px-6 [&::-webkit-details-marker]:hidden ${focusRing}`}>
        <span className="min-w-0 flex-1">
          <span className="block text-[1.0625rem] font-semibold tracking-tight text-foreground sm:text-[1.125rem]">{title}</span>
          <span className="mt-0.5 block text-sm text-muted-foreground">{summary}</span>
        </span>
        <span aria-hidden="true" className="flex size-9 shrink-0 items-center justify-center rounded-full border border-border/70 transition-transform group-open:rotate-180">
          <ChevronDown className="size-4 text-muted-foreground" />
        </span>
      </summary>
      <div className="border-t border-border/50 px-4 pb-6 pt-5 sm:px-6">{children}</div>
    </details>
  );
}

const NETWORK_LEVELS = [
  {
    name: "Full",
    icon: CircleCheck,
    tone: "text-emerald-400",
    verdict: "Works",
    detail: "The setting our Claude hosted run used. Everything comes from the public mirror.",
  },
  {
    name: "Custom",
    icon: CircleCheck,
    tone: "text-emerald-400/80",
    verdict: "Should work",
    detail: "Allow the two hosts below and keep the provider's package-manager defaults so your own installs still work. This allowlist passed the ChatGPT hosted test; Claude's Custom mode has not been accepted.",
  },
  {
    name: "Trusted",
    icon: CircleCheck,
    tone: "text-emerald-400/80",
    verdict: "Tested",
    detail: "Our cold Claude run installed all eleven executables in 53 seconds through verified public GitHub fallbacks, including JSM. The mirror is blocked and UBS fetches its modules on first use. Organization policies may still block downloads; read the summary.",
  },
  {
    name: "None",
    icon: CircleX,
    tone: "text-rose-400",
    verdict: "Nothing installs",
    detail: "Claude's one-line recipe still exits 0, so the session starts without the tools or a log. The Codex and Linux recipes fail so the problem is visible.",
  },
];

/* ------------------------------------------------------------------ */
/* Page                                                                */
/* ------------------------------------------------------------------ */

export default function CloudAgentsPage() {
  const [agentId, setAgentId] = useState("claude");
  const [lightbox, setLightbox] = useState<{ shot: SetupScreenshot; opener: HTMLElement } | null>(null);
  const openShot = useCallback<OpenShot>((shot, opener) => setLightbox({ shot, opener }), []);
  const agent = CLOUD_AGENTS.find((item) => item.id === agentId) ?? CLOUD_AGENTS[0];
  const walkthrough = CLOUD_WALKTHROUGHS[agent.id];
  const firstStep = `#${stepAnchor(agent.id, walkthrough.steps[0].id)}`;
  const screenshotCount = walkthrough.steps.filter((step) => step.screenshot).length;

  useEffect(() => {
    const readHash = () => {
      const fragment = window.location.hash.slice(1);
      const id = fragment.split("-step-")[0].replace("codex-cloud", "codex");
      if (!CLOUD_AGENTS.some((item) => item.id === id)) return;
      setAgentId(id);
      // A bare provider link (README's #claude, legacy #codex-cloud) lands on its guide.
      if (!fragment.includes("-step-")) requestAnimationFrame(() => document.getElementById("guide")?.scrollIntoView({ block: "start" }));
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
    // `dark` island: terminal panels, screenshots and accent tints are tuned for
    // the dark tokens, so a light preference stored by the wizard must not apply.
    <div className="dark relative min-h-screen overflow-x-clip bg-background text-foreground">
      <div aria-hidden="true" className="pointer-events-none absolute inset-x-0 top-0 h-[60rem] overflow-hidden">
        <div className="absolute inset-0 bg-gradient-cosmic opacity-90" />
        <div className="absolute inset-0 bg-grid-pattern opacity-50 [mask-image:radial-gradient(ellipse_75%_55%_at_50%_0%,black,transparent)]" />
        <div className="absolute -top-48 left-1/2 hidden h-[38rem] w-[64rem] -translate-x-1/2 rounded-full bg-[oklch(0.75_0.18_195/0.09)] blur-[120px] sm:block" />
      </div>

      <nav aria-label="Site" className="relative z-10 mx-auto flex max-w-6xl items-center justify-between gap-3 px-5 pt-4 sm:px-8 sm:pt-6">
        <Link href="/" className={`${textLink} gap-2.5 font-mono text-sm font-bold text-foreground hover:no-underline`}>
          <span className="flex size-8 items-center justify-center rounded-lg bg-primary/15 ring-1 ring-primary/25">
            <Terminal className="size-4 text-primary" aria-hidden="true" />
          </span>
          Agent Flywheel
        </Link>
        <div className="flex items-center gap-1 text-sm text-muted-foreground sm:gap-5">
          <Link href="/learn" className={`${textLink} max-sm:hidden`}>Learn</Link>
          <Link href="/tldr" className={`${textLink} max-sm:hidden`}>TL;DR</Link>
          <a href={CLAUDE_CODE_WEB_SCRIPT_SOURCE_URL} target="_blank" rel="noopener noreferrer" className={`${textLink} px-1`}>
            <GitBranch className="size-4" aria-hidden="true" />View source<span className="sr-only"> (new tab)</span>
          </a>
        </div>
      </nav>

      <main id="main-content" tabIndex={-1} className="relative focus:outline-none">
        <section aria-labelledby="hero-heading" className="mx-auto grid max-w-6xl gap-x-14 gap-y-10 px-5 pb-16 pt-10 sm:px-8 sm:pb-20 sm:pt-16 lg:grid-cols-[minmax(0,1fr)_minmax(0,31rem)] lg:pb-24">
          <div className="min-w-0">
            <p className="inline-flex items-center gap-2 rounded-full border border-primary/25 bg-primary/[0.07] px-3 py-1 font-mono text-[11px] uppercase tracking-[0.18em] text-primary">
              <Cloud className="size-3.5" aria-hidden="true" />Cloud agent setup
            </p>
            <h1 id="hero-heading" className="mt-6 text-[2.5rem] font-semibold leading-[1.05] tracking-tight text-foreground sm:text-[3.5rem] lg:text-[4.25rem]">
              Give your cloud agent <span className="text-gradient-cyan">a flywheel.</span>
            </h1>
            <p className="mt-6 max-w-xl text-[17px] leading-relaxed text-muted-foreground sm:text-[19px]">
              Prebuilt tools for tasks, coordination, code checks, memory and reusable skills, installed in your provider&apos;s setup phase. Hand the setup to a browser agent, or follow the illustrated guide.
            </p>
          </div>

          <div className="relative min-w-0 lg:col-start-2 lg:row-span-2 lg:row-start-1 lg:self-start">
            <div aria-hidden="true" className="absolute -inset-px -z-10 rounded-[1.75rem] bg-gradient-to-b from-primary/35 via-primary/5 to-transparent blur-sm" />
            <div className="rounded-[1.6rem] border border-white/10 bg-card/70 p-4 shadow-2xl shadow-black/50 backdrop-blur-xl sm:p-6">
              <ProviderPicker agentId={agentId} choose={choose} />
              <div className="my-5 h-px bg-gradient-to-r from-transparent via-border to-transparent" />
              <p className="mb-3 text-sm font-semibold text-foreground"><span className="mr-2 font-mono text-primary">2</span>Pick how to set it up</p>
              <div className="grid gap-3">
                <HandoffCard key={agent.id} agent={agent} />
                <a href={firstStep} className={`group flex items-center gap-4 rounded-2xl border border-border/70 bg-background/40 p-4 transition-colors hover:border-primary/40 hover:bg-background/70 ${focusRing}`}>
                  <span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-muted text-foreground/80 transition-colors group-hover:bg-primary/15 group-hover:text-primary">
                    <BookOpen className="size-5" aria-hidden="true" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block font-semibold text-foreground">{agent.id === "muse" ? "Start the capability check" : screenshotCount ? "Follow the illustrated guide" : "Follow the step-by-step guide"}</span>
                    <span className="mt-0.5 block text-sm text-muted-foreground">
                      {walkthrough.steps.length} steps{screenshotCount ? ` · ${screenshotCount} real screenshots` : ""} · copy buttons on every script
                    </span>
                  </span>
                  <ArrowDown className="size-5 shrink-0 text-muted-foreground transition-transform group-hover:translate-y-0.5 group-hover:text-primary" aria-hidden="true" />
                </a>
              </div>
            </div>
          </div>

          <div className="min-w-0 space-y-10 lg:col-start-1 lg:row-start-2">
            <dl className="grid grid-cols-2 gap-x-6 gap-y-5 border-t border-border/50 pt-8 sm:grid-cols-4 lg:grid-cols-2 xl:grid-cols-4">
              {[
                { value: "10", label: "tools", sub: `${CLOUD_EXECUTABLES.length} executables` },
                { value: "12s", label: "Claude install", sub: "hosted run" },
                { value: "0", label: "secrets", sub: "no source builds" },
                { value: "2", label: "download hosts", sub: "both public" },
              ].map((fact) => (
                <div key={fact.label} className="flex min-w-0 flex-col-reverse justify-end">
                  <dt className="mt-1 text-sm text-foreground/80">
                    {fact.label}
                    <span className="block text-xs text-muted-foreground">{fact.sub}</span>
                  </dt>
                  <dd className="font-mono text-[1.75rem] font-semibold leading-none tracking-tight text-foreground">{fact.value}</dd>
                </div>
              ))}
            </dl>
            <ScriptTeaser agent={agent} />
          </div>
        </section>

        <GuideSection key={agent.id} agent={agent} choose={choose} onOpenShot={openShot} />

        {/* ========================= HOW IT WORKS ========================= */}
        <section aria-labelledby="how-heading" className="border-y border-border/40 bg-card/20">
          <div className="mx-auto grid max-w-6xl gap-12 px-5 py-20 sm:px-8 sm:py-24 lg:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)] lg:gap-14">
            <div className="min-w-0">
              <p className="font-mono text-xs uppercase tracking-[0.2em] text-primary">How installation works</p>
              <h2 id="how-heading" className={`mt-3 ${sectionTitle}`}>Fast, verified, and honest about failures</h2>
              <ul className="mt-8 space-y-6">
                {BEHAVIORS.map((behavior) => (
                  <li key={behavior.title} className="flex gap-4">
                    <span className="flex size-10 shrink-0 items-center justify-center rounded-xl border border-primary/20 bg-primary/10 text-primary">
                      <behavior.icon className="size-5" aria-hidden="true" />
                    </span>
                    <div className="min-w-0">
                      <h3 className="font-semibold text-foreground">{behavior.title}</h3>
                      <p className="mt-1 text-sm leading-relaxed text-muted-foreground">{behavior.description}</p>
                    </div>
                  </li>
                ))}
              </ul>
            </div>
            <div className="min-w-0 lg:pt-16">
              <div className="lg:sticky lg:top-8">
                <RunPreview agent={agent} />
              </div>
            </div>
          </div>
        </section>

        {/* ============================= TOOLS ============================= */}
        <section aria-labelledby="tools-heading" className="mx-auto max-w-6xl px-5 py-20 sm:px-8 sm:py-24">
          <div className="max-w-2xl">
            <p className="font-mono text-xs uppercase tracking-[0.2em] text-primary">What gets installed</p>
            <h2 id="tools-heading" className={`mt-3 ${sectionTitle}`}>Ten tools that carry the work forward</h2>
            <p className="mt-4 text-base leading-relaxed text-muted-foreground">
              {CLOUD_EXECUTABLES.length} executables from hash-pinned bundles, installed into <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-[0.85em] text-foreground">.local/bin</code> under your data root. Install a subset with ACFS_CLOUD_TOOLS.
            </p>
          </div>
          <div className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-6">
            {TOOL_GROUPS.map((group) => (
              <div key={group.id} className={`flex min-w-0 flex-col rounded-2xl border border-border/60 bg-card/40 p-5 transition-colors hover:border-primary/30 sm:p-6 ${group.span}`}>
                <div className="flex items-center gap-3">
                  <span className="flex size-9 items-center justify-center rounded-lg bg-primary/10 text-primary">
                    <group.icon className="size-[18px]" aria-hidden="true" />
                  </span>
                  <div className="min-w-0">
                    <h3 className="font-semibold text-foreground">{group.title}</h3>
                    <p className="text-xs text-muted-foreground">{group.blurb}</p>
                  </div>
                </div>
                <ul className={`mt-5 grid gap-4 ${group.wide ? WIDE_GROUP_COLUMNS[CLAUDE_CODE_WEB_TOOLS.filter((tool) => tool.group === group.id).length] ?? "" : ""}`}>
                  {CLAUDE_CODE_WEB_TOOLS.filter((tool) => tool.group === group.id).map((tool) => (
                    <li key={tool.id} className="min-w-0 border-t border-border/50 pt-4">
                      <p className="text-sm font-semibold text-foreground">{tool.name}</p>
                      <p className="mt-1.5 flex flex-wrap gap-1.5">
                        {[tool.command, ...(tool.alsoInstalls ?? [])].map((command) => (
                          <code key={command} className="break-all rounded-md bg-primary/10 px-1.5 py-0.5 font-mono text-xs text-primary">{command}</code>
                        ))}
                      </p>
                      <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{tool.role}</p>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </section>

        {/* ============================ NETWORK ============================ */}
        <section aria-labelledby="network-heading" className="border-y border-border/40 bg-card/20">
          <div className="mx-auto grid max-w-6xl gap-10 px-5 py-20 sm:px-8 sm:py-24 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)] lg:gap-14">
            <div className="min-w-0">
              <p className="font-mono text-xs uppercase tracking-[0.2em] text-primary">Network access</p>
              <h2 id="network-heading" className={`mt-3 ${sectionTitle}`}>Two public download hosts</h2>
              <p className="mt-4 text-base leading-relaxed text-muted-foreground">
                No credentials or repository ownership needed. Use full access, or allow these hosts in your provider&apos;s policy. Setup never falls back to a source build.
              </p>
              <CodePanel className="mt-6" text={DOWNLOAD_HOSTS} title="Allowed domains" label="Public download hosts" copyLabel="Copy download hosts" />
            </div>
            <div className="min-w-0">
              <p className="mb-4 text-sm text-muted-foreground">What each level does, in Claude&apos;s terms. Other providers have equivalent settings.</p>
              <ul className="divide-y divide-border/50 overflow-hidden rounded-2xl border border-border/60 bg-background/40">
                {NETWORK_LEVELS.map((level) => (
                  <li key={level.name} className="flex gap-4 p-4 sm:p-5">
                    <level.icon className={`mt-0.5 size-5 shrink-0 ${level.tone}`} aria-hidden="true" />
                    <div className="min-w-0">
                      <p className="flex flex-wrap items-baseline gap-x-2">
                        <span className="font-semibold text-foreground">{level.name}</span>
                        <span className={`text-sm font-medium ${level.tone}`}>{level.verdict}</span>
                      </p>
                      <p className="mt-1 text-sm leading-relaxed text-muted-foreground">{level.detail}</p>
                    </div>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </section>

        {/* ======================== REFERENCE DETAILS ======================== */}
        <section aria-labelledby="reference-heading" className="mx-auto max-w-6xl px-5 py-20 sm:px-8 sm:py-24">
          <p className="font-mono text-xs uppercase tracking-[0.2em] text-primary">Reference</p>
          <h2 id="reference-heading" className={`mt-3 ${sectionTitle}`}>Scope and options</h2>
          <div className="mt-10 space-y-4">
            <Disclosure title="What this bundle leaves out" summary="Machine provisioning and the tools that need a long-lived host.">
              <ul className="divide-y divide-border/40">
                {CLAUDE_CODE_WEB_LEFT_OUT.map((item) => (
                  <li key={item.name} className="flex flex-col gap-1 py-4 first:pt-0 last:pb-0 sm:flex-row sm:gap-8">
                    <span className="shrink-0 font-mono text-sm font-semibold text-foreground sm:w-48">{item.name}</span>
                    <span className="text-sm leading-relaxed text-muted-foreground">{item.reason}</span>
                  </li>
                ))}
              </ul>
            </Disclosure>
            <Disclosure title="Options and environment variables" summary="Pick tools, a data root, a deadline or a pinned ref.">
              <p className="mb-4 text-sm leading-relaxed text-muted-foreground">
                Set options inline on the bash side of the pipe, where the setup script sees them. Your {agent.name} recipe, installing four tools:
              </p>
              <CodePanel text={cloudSubsetRecipe(agent.id)} title={`${agent.name} · subset install`} label={`Subset install example for ${agent.name}`} copyLabel={`Copy subset install example for ${agent.name}`} />
              <table className="mt-6 hidden w-full text-left text-sm md:table">
                <thead className="font-mono text-xs uppercase tracking-wider text-muted-foreground">
                  <tr className="border-b border-border/60">
                    <th scope="col" className="py-3 pr-4 font-medium">Variable</th>
                    <th scope="col" className="py-3 pr-4 font-medium">Default</th>
                    <th scope="col" className="py-3 font-medium">Effect</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border/40">
                  {CLAUDE_CODE_WEB_OPTIONS.map((option) => (
                    <tr key={option.name} className="align-top">
                      <td className="py-3.5 pr-4 font-mono text-xs text-primary">{option.name}</td>
                      <td className="py-3.5 pr-4 font-mono text-xs text-foreground">{option.defaultValue || <span className="font-sans italic text-muted-foreground">unset</span>}</td>
                      <td className="py-3.5 leading-relaxed text-muted-foreground">{option.effect}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <dl className="mt-6 space-y-3 md:hidden">
                {CLAUDE_CODE_WEB_OPTIONS.map((option) => (
                  <div key={option.name} className="rounded-xl border border-border/60 bg-background/40 p-4">
                    <dt className="break-all font-mono text-xs font-semibold text-primary">{option.name}</dt>
                    <dd className="mt-1 font-mono text-xs text-foreground">
                      <span className="font-sans text-muted-foreground">Default: </span>
                      {option.defaultValue || <span className="font-sans italic text-muted-foreground">unset</span>}
                    </dd>
                    <dd className="mt-2 text-sm leading-relaxed text-muted-foreground">{option.effect}</dd>
                  </div>
                ))}
              </dl>
            </Disclosure>
          </div>
        </section>

        {/* ============================== CTA ============================== */}
        <section aria-labelledby="cta-heading" className="relative overflow-hidden border-t border-border/40">
          <div aria-hidden="true" className="pointer-events-none absolute left-1/2 top-1/2 h-72 w-[40rem] max-w-full -translate-x-1/2 -translate-y-1/2 rounded-full bg-[oklch(0.75_0.18_195/0.12)] blur-[110px]" />
          <div className="relative mx-auto flex max-w-3xl flex-col items-center px-5 py-24 text-center sm:px-8 sm:py-28">
            <h2 id="cta-heading" className="text-[2rem] font-semibold leading-tight tracking-tight text-foreground sm:text-[2.75rem]">Want the whole stack?</h2>
            <p className="mt-5 max-w-xl text-base leading-relaxed text-muted-foreground sm:text-[17px]">
              The cloud script covers the tools an agent calls. A VPS of your own gets everything: the shell, tmux, every agent CLI, and the services that keep running between sessions.
            </p>
            <div className="mt-9 flex w-full flex-col items-stretch gap-3 sm:w-auto sm:flex-row sm:items-center">
              <Button asChild size="lg" className="group min-h-12 bg-primary px-6 text-primary-foreground hover:bg-primary/90">
                <Link href="/wizard/os-selection">
                  Set up a VPS with the Wizard
                  <ArrowRight className="ml-2 size-4 transition-transform group-hover:translate-x-1" aria-hidden="true" />
                </Link>
              </Button>
              <Button asChild size="lg" variant="outline" className="min-h-12 border-border/70 bg-transparent px-6">
                <Link href="/learn">
                  <BookOpen className="mr-2 size-4" aria-hidden="true" />
                  Learn the workflow
                </Link>
              </Button>
            </div>
          </div>
        </section>
      </main>

      <footer className="border-t border-border/40">
        <div className="mx-auto flex max-w-6xl flex-col items-center gap-6 px-5 py-10 text-center sm:flex-row sm:justify-between sm:px-8 sm:text-left">
          <Link href="/" className={`${textLink} gap-2 font-mono text-sm font-bold text-foreground hover:no-underline`}>
            <span className="flex size-8 items-center justify-center rounded-lg bg-primary/15">
              <Terminal className="size-4 text-primary" aria-hidden="true" />
            </span>
            Agent Flywheel
          </Link>
          <div className="flex flex-wrap items-center justify-center gap-x-5 gap-y-1 text-sm text-muted-foreground">
            <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer" className={textLink}>GitHub</a>
            <a href={README_URL} target="_blank" rel="noopener noreferrer" className={textLink}>README section</a>
            <Link href="/tldr" className={textLink}>TL;DR</Link>
            <Link href="/omarchy" className={textLink}>Omarchy</Link>
            <Link href="/" className={textLink}>Home</Link>
          </div>
          <p className="text-xs text-muted-foreground">
            Created by{" "}
            <a href="https://jeffreyemanuel.com/" target="_blank" rel="noopener noreferrer" className={`${textLink} text-primary`}>
              Jeffrey Emanuel
            </a>
          </p>
        </div>
      </footer>

      {lightbox && <Lightbox key={lightbox.shot.src} shot={lightbox.shot} opener={lightbox.opener} onClose={() => setLightbox(null)} />}
    </div>
  );
}
