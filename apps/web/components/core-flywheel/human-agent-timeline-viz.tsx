"use client";

import type { LucideIcon } from "lucide-react";
import {
  BookOpen,
  Bot,
  Code,
  Eye,
  FileText,
  Layers,
  Lightbulb,
  Radio,
  Rocket,
  ShieldCheck,
  User,
  Wrench,
} from "lucide-react";
import { Fragment, useCallback, useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "@/components/motion";
import { COMPLETE_GUIDE_MODELS } from "@/lib/complete-guide";
import { isInteractiveKeyboardTarget } from "@/lib/utils";

/** Wrap a tool list only at spaces, so hyphenated model names or flags like
 *  `--robot-triage` never split at their hyphens. */
function WordsKeptWhole({ text }: { text: string }) {
  return (
    <>
      {text.split(" ").map((word, i) => (
        <Fragment key={i}>
          {i > 0 && " "}
          <span className="whitespace-nowrap">{word}</span>
        </Fragment>
      ))}
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  Constants                                                         */
/* ------------------------------------------------------------------ */

const EXHIBIT_PANEL_CLASS =
  "my-16 overflow-hidden rounded-[1.5rem] sm:rounded-[2rem] lg:rounded-[3rem] border border-white/[0.03] bg-[#020408] p-5 sm:p-12 lg:p-16 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9)]";

type ActorType = "human" | "agent" | "both";

interface TimelineStage {
  id: string;
  label: string;
  actor: ActorType;
  color: string;
  icon: LucideIcon;
  who: string;
  what: string;
  tools: string;
  insight: string;
}

const HUMAN_COLOR = "#a78bfa";
const HUMAN_COLOR_LIGHT = "#c4b5fd";
const AGENT_COLOR = "#FF5500";

const STAGES: TimelineStage[] = [
  {
    id: "plan",
    label: "Create the Plan",
    actor: "human",
    color: HUMAN_COLOR,
    icon: FileText,
    who: "You",
    what: "Have a lead planner write the plan and two other model families write competing ones, then have the lead merge them into a single strong design document",
    tools: `${COMPLETE_GUIDE_MODELS.leadPlanner.replace(/^Claude /, "")} (lead), ${COMPLETE_GUIDE_MODELS.gptPro}, ${COMPLETE_GUIDE_MODELS.openaiPlanner}, ${COMPLETE_GUIDE_MODELS.antigravity}`,
    insight: "The plan and the beads are where most of your time and thinking go. No code yet.",
  },
  {
    id: "beads",
    label: "Convert to Beads",
    actor: "human",
    color: HUMAN_COLOR_LIGHT,
    icon: Layers,
    who: "You (via the lead)",
    what: "Tell the lead planner to create beads from the plan, with dependencies. Then have it polish them 8\u201310 times.",
    tools: `${COMPLETE_GUIDE_MODELS.leadPlannerSurface} (${COMPLETE_GUIDE_MODELS.leadPlanner.replace(/^Claude /, "")}) with br`,
    insight: "You prompt the agent. The agent runs the br commands.",
  },
  {
    id: "agents-md",
    label: "Write AGENTS.md",
    actor: "human",
    color: HUMAN_COLOR,
    icon: BookOpen,
    who: "You",
    what: "Finish the operating manual before launch: agent behavior rules, tool usage, and coordination protocol.",
    tools: "Your editor, plus br agents --add",
    insight: "Every agent reads this file on startup. After compaction, you tell it to reread the file instead of repeating instructions in chat.",
  },
  {
    id: "launch",
    label: "Launch Agents",
    actor: "human",
    color: HUMAN_COLOR,
    icon: Rocket,
    who: "You",
    what: "Start 2\u20134 agent sessions one at a time and give each the marching orders prompt.",
    tools: "Terminal, tmux, or ntm",
    insight: "Same generic prompt every time, for every project.",
  },
  {
    id: "coordinate",
    label: "Claim & Coordinate",
    actor: "agent",
    color: AGENT_COLOR,
    icon: Radio,
    who: "Agents (automatically)",
    what: "Register with Agent Mail, discover peers, claim beads in br, reserve files, and announce what they\u2019re working on.",
    tools: "Agent Mail (MCP), br, bv",
    insight: "You never type these commands. Agents do it because AGENTS.md tells them to.",
  },
  {
    id: "implement",
    label: "Implement & Test",
    actor: "agent",
    color: AGENT_COLOR,
    icon: Code,
    who: "Agents (automatically)",
    what: "Write code, run tests, do a fresh-eyes self-review, close the bead, release reservations, and pick the next one via bv.",
    tools: "br, bv, the project's tests",
    insight: "The bead carries all the context. The agent doesn\u2019t need to ask you what to do.",
  },
  {
    id: "tend",
    label: "Tend the Swarm",
    actor: "human",
    color: HUMAN_COLOR,
    icon: Eye,
    who: "You (every 10\u201315 min)",
    what: "Look for stuck beads, rescue confused agents by telling them to reread AGENTS.md, and add missing beads.",
    tools: "bv --robot-triage, br list, Agent Mail threads",
    insight: "A few minutes of checking, every 10–15 minutes.",
  },
  {
    id: "review",
    label: "Review & Harden",
    actor: "both",
    color: HUMAN_COLOR, // gradient handled visually
    icon: ShieldCheck,
    who: "You direct, agents execute",
    what: "Send review prompts. Agents do random code exploration, cross-agent review, test coverage, and UI polish.",
    tools: "Your review prompts \u2192 agents\u2019 code analysis",
    insight: "You decide when quality is high enough. Agents do the actual reviewing.",
  },
];

const STAGE_COUNT = STAGES.length;

/* ------------------------------------------------------------------ */
/*  Color helpers                                                     */
/* ------------------------------------------------------------------ */

function actorLabel(actor: ActorType): string {
  if (actor === "human") return "You";
  if (actor === "agent") return "Agents";
  return "Both";
}

/* ------------------------------------------------------------------ */
/*  Legend                                                            */
/* ------------------------------------------------------------------ */

function Legend() {
  return (
    <div className="flex items-center gap-6 text-xs font-medium">
      <span className="flex items-center gap-2">
        <span
          className="inline-block w-3 h-3 rounded-full"
          style={{ backgroundColor: HUMAN_COLOR }}
        />
        <span className="text-white/60">You</span>
      </span>
      <span className="flex items-center gap-2">
        <span
          className="inline-block w-3 h-3 rounded-full"
          style={{ backgroundColor: AGENT_COLOR }}
        />
        <span className="text-white/60">Agents</span>
      </span>
      <span className="flex items-center gap-2">
        <span
          className="inline-block w-3 h-3 rounded-full"
          style={{
            background: `linear-gradient(135deg, ${HUMAN_COLOR}, ${AGENT_COLOR})`,
          }}
        />
        <span className="text-white/60">Both</span>
      </span>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Timeline node (desktop)                                           */
/* ------------------------------------------------------------------ */

function stageNodeColor(stage: TimelineStage): string {
  if (stage.actor === "both") return HUMAN_COLOR;
  return stage.color;
}

function stageNodeGradient(stage: TimelineStage): string | undefined {
  if (stage.actor === "both") {
    return `linear-gradient(135deg, ${HUMAN_COLOR}, ${AGENT_COLOR})`;
  }
  return undefined;
}

/* ------------------------------------------------------------------ */
/*  Detail card                                                       */
/* ------------------------------------------------------------------ */

function DetailCard({ stage, reducedMotion }: { stage: TimelineStage; reducedMotion: boolean }) {
  const dur = reducedMotion ? 0 : 0.4;
  const borderColor = stage.actor === "both" ? AGENT_COLOR : stage.color;

  return (
    <motion.div
      key={stage.id}
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      transition={{ duration: dur, ease: [0.16, 1, 0.3, 1] }}
      className="relative flex flex-col gap-5"
      style={{ paddingLeft: 24 }}
    >
      {/* Animated left border */}
      <motion.div
        className="absolute left-0 top-0 w-[3px] rounded-full"
        style={{
          background:
            stage.actor === "both"
              ? `linear-gradient(to bottom, ${HUMAN_COLOR}, ${AGENT_COLOR})`
              : borderColor,
        }}
        initial={{ height: "0%" }}
        animate={{ height: "100%" }}
        transition={{
          duration: reducedMotion ? 0 : 0.5,
          ease: [0.16, 1, 0.3, 1],
          delay: 0.1,
        }}
      />

      {/* Header */}
      <div className="flex flex-col gap-3">
        <div className="flex items-center gap-3">
          <span
            className="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-bold uppercase tracking-widest"
            style={{
              backgroundColor:
                stage.actor === "agent"
                  ? `${AGENT_COLOR}18`
                  : stage.actor === "both"
                    ? `${AGENT_COLOR}10`
                    : `${HUMAN_COLOR}18`,
              color:
                stage.actor === "agent"
                  ? AGENT_COLOR
                  : stage.actor === "both"
                    ? "#e2e8f0"
                    : HUMAN_COLOR,
              border: `1px solid ${stage.actor === "agent" ? `${AGENT_COLOR}30` : stage.actor === "both" ? "rgba(255,255,255,0.08)" : `${HUMAN_COLOR}30`}`,
            }}
          >
            {stage.actor === "agent" ? (
              <Bot size={10} />
            ) : stage.actor === "both" ? (
              <>
                <User size={10} style={{ color: HUMAN_COLOR }} />
                <span className="text-zinc-500">+</span>
                <Bot size={10} style={{ color: AGENT_COLOR }} />
              </>
            ) : (
              <User size={10} />
            )}
            {actorLabel(stage.actor)}
          </span>
        </div>
        <h4 className="font-serif text-[2rem] font-normal leading-none tracking-[-0.01em] text-white sm:text-[2.5rem]">
          {stage.label}
        </h4>
      </div>

      {/* Info grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        {/* Who */}
        <div className="flex flex-col gap-2 p-4 rounded-2xl bg-white/[0.03] border border-white/[0.05] relative overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-br from-white/[0.015] to-transparent pointer-events-none" />
          <span className="text-xs font-bold text-zinc-400 uppercase tracking-widest flex items-center gap-2">
            <User size={10} className="opacity-70" aria-hidden="true" />
            Who
          </span>
          <p className="text-sm text-white/90 font-medium">{stage.who}</p>
        </div>

        {/* Tools: wrap only between words (each word is nowrap), so a single
            token longer than the card would be clipped, not broken. */}
        <div className="flex flex-col gap-2 p-4 rounded-2xl bg-white/[0.02] border border-white/[0.04] relative overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />
          <span className="text-xs font-bold text-zinc-400 uppercase tracking-widest flex items-center gap-2">
            <Wrench size={10} className="opacity-70" aria-hidden="true" />
            Tools
          </span>
          <p className="text-sm leading-relaxed text-white/90 font-mono font-medium break-words">
            <WordsKeptWhole text={stage.tools} />
          </p>
        </div>
      </div>

      {/* What */}
      <div className="p-4 rounded-2xl bg-white/[0.02] border border-white/[0.04] relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />
        <p className="text-sm leading-relaxed text-zinc-400 font-light">{stage.what}</p>
      </div>

      {/* Insight */}
      <div className="flex items-start gap-3 p-4 rounded-2xl bg-white/[0.015] border border-white/[0.04] relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-white/[0.005] to-transparent pointer-events-none" />
        <Lightbulb
          size={16}
          className="mt-0.5 shrink-0"
          style={{
            color: stage.actor === "agent" ? AGENT_COLOR : HUMAN_COLOR,
          }}
        />
        <p className="text-sm leading-relaxed text-zinc-400 font-light italic">{stage.insight}</p>
      </div>
    </motion.div>
  );
}

/* ------------------------------------------------------------------ */
/*  Desktop horizontal timeline                                       */
/* ------------------------------------------------------------------ */

function DesktopTimeline({
  activeIndex,
  onSelect,
  reducedMotion,
}: {
  activeIndex: number;
  onSelect: (index: number) => void;
  reducedMotion: boolean;
}) {
  const dur = reducedMotion ? 0 : 0.3;

  return (
    <div className="hidden lg:block">
      <div className="flex items-start relative">
        {STAGES.map((stage, index) => {
          const isActive = index === activeIndex;
          const isPast = index < activeIndex;
          const nodeColor = stageNodeColor(stage);
          const gradient = stageNodeGradient(stage);
          const Icon = stage.icon;

          return (
            <button
              key={stage.id}
              type="button"
              onClick={() => onSelect(index)}
              className="relative z-10 flex flex-col items-center gap-2 group cursor-pointer rounded-xl pb-1 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-[#a78bfa]/60"
              aria-label={`Select stage ${index + 1}: ${stage.label}`}
              aria-pressed={isActive}
              style={{ flex: "1 1 0%" }}
            >
              {/* Connecting segment to the next node. Every button is the same
                  width, so the next node's center sits at 150% of this one:
                  the segment runs between the two circles, level with their
                  centers, and never crosses the labels below. */}
              {index < STAGE_COUNT - 1 && (
                <div
                  className="absolute top-[21px] left-[calc(50%+28px)] w-[calc(100%-56px)] h-[2px] rounded-full pointer-events-none"
                  style={{
                    background:
                      isPast || isActive
                        ? `linear-gradient(to right, ${nodeColor}, ${stageNodeColor(STAGES[index + 1])})`
                        : "rgba(255,255,255,0.12)",
                    opacity: isPast || isActive ? 0.6 : 1,
                  }}
                >
                  {/* Animated flow dot */}
                  {isActive && !reducedMotion && (
                    <motion.div
                      className="absolute top-[-2px] w-1.5 h-1.5 rounded-full"
                      style={{ backgroundColor: nodeColor }}
                      animate={{ left: ["0%", "100%"] }}
                      transition={{
                        duration: 1.5,
                        repeat: Infinity,
                        ease: "linear",
                      }}
                    />
                  )}
                </div>
              )}

              {/* Fixed 44px slot, so the circle's center (and the segments)
                  stay level whether or not this stage is active. */}
              <span className="relative flex h-11 w-11 items-center justify-center">
                {/* Pulse ring */}
                {isActive && !reducedMotion && (
                  <motion.span
                    className="absolute inset-1 rounded-full"
                    style={{ border: `2px solid ${nodeColor}` }}
                    initial={{ scale: 1, opacity: 0.6 }}
                    animate={{ scale: 1.8, opacity: 0 }}
                    transition={{
                      duration: 1.8,
                      repeat: Infinity,
                      ease: "easeOut",
                    }}
                  />
                )}

                {/* Node circle (opaque base so nothing shows through it) */}
                <motion.span
                  className="relative flex items-center justify-center rounded-full transition-shadow duration-300"
                  style={{
                    width: isActive ? 44 : 36,
                    height: isActive ? 44 : 36,
                    background: gradient
                      ? isActive
                        ? gradient
                        : `linear-gradient(${nodeColor}22, ${nodeColor}22), #05070b`
                      : isActive
                        ? nodeColor
                        : `linear-gradient(${nodeColor}22, ${nodeColor}22), #05070b`,
                    border: `2px solid ${isActive ? nodeColor : isPast ? `${nodeColor}88` : `${nodeColor}55`}`,
                    boxShadow: isActive ? `0 0 20px ${nodeColor}40, 0 0 40px ${nodeColor}15` : "none",
                  }}
                  transition={{ duration: dur }}
                >
                  <Icon
                    size={isActive ? 20 : 16}
                    color={isActive ? "#fff" : isPast ? nodeColor : `${nodeColor}bb`}
                    strokeWidth={isActive ? 2.5 : 2}
                    aria-hidden="true"
                  />
                </motion.span>
              </span>

              {/* Label */}
              <span
                className="text-xs font-bold uppercase tracking-wider text-center leading-tight max-w-[80px] transition-colors duration-300"
                style={{
                  color: isActive ? "#fff" : isPast ? "#d4d4d8" : "#a1a1aa",
                }}
              >
                {stage.label}
              </span>

              {/* Step number (zinc-400 when inactive: zinc-500 is 4.2:1 here) */}
              <span
                className="text-xs font-mono font-bold"
                style={{
                  color: isActive ? nodeColor : "#a1a1aa",
                }}
              >
                {index + 1}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Mobile vertical timeline                                          */
/* ------------------------------------------------------------------ */

function MobileTimeline({
  activeIndex,
  onSelect,
  reducedMotion,
}: {
  activeIndex: number;
  onSelect: (index: number) => void;
  reducedMotion: boolean;
}) {
  return (
    <div className="lg:hidden relative flex flex-col gap-2">
      {/* Vertical connecting line, on the icon column (px-5 + half the
          40px icon); the icon tiles are opaque, so it reads as a rail. */}
      <div
        aria-hidden="true"
        className="absolute left-[41px] top-6 bottom-6 w-px pointer-events-none"
        style={{
          background:
            "linear-gradient(to bottom, transparent, rgba(255,255,255,0.1) 10%, rgba(255,255,255,0.1) 90%, transparent)",
        }}
      />

      {STAGES.map((stage, index) => {
        const Icon = stage.icon;
        const isActive = index === activeIndex;
        const nodeColor = stageNodeColor(stage);
        const gradient = stageNodeGradient(stage);

        return (
          <motion.button
            key={stage.id}
            type="button"
            onClick={() => onSelect(index)}
            aria-pressed={isActive}
            className={`relative flex items-center gap-4 px-5 py-3.5 rounded-2xl border transition-[border-left-width,border-color,background-color,box-shadow] duration-300 text-left focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-[#a78bfa]/60 ${
              isActive
                ? "border-white/[0.08] bg-white/[0.04]"
                : "border-white/[0.03] bg-white/[0.01] hover:bg-white/[0.03]"
            }`}
            style={{
              borderLeftWidth: isActive ? 3 : 1,
              // Absorb the thicker active border so the icon stays on the rail.
              paddingLeft: isActive ? 18 : 20,
              borderLeftColor: isActive ? nodeColor : undefined,
              boxShadow: isActive
                ? `0 4px 24px -4px ${nodeColor}30, 0 0 0 1px ${nodeColor}15`
                : undefined,
            }}
            animate={isActive && !reducedMotion ? { scale: [1, 1.01, 1] } : { scale: 1 }}
            transition={
              isActive && !reducedMotion
                ? {
                    scale: {
                      duration: 3,
                      repeat: Infinity,
                      ease: "easeInOut",
                    },
                  }
                : { duration: 0.3 }
            }
          >
            {/* Node icon (opaque, so the rail behind it doesn't show through) */}
            <div
              className={`relative z-10 flex items-center justify-center w-10 h-10 rounded-xl shrink-0 transition duration-300 ${
                isActive ? "shadow-lg" : ""
              }`}
              style={{
                background: isActive
                  ? gradient || `linear-gradient(${nodeColor}20, ${nodeColor}20), #05070b`
                  : "linear-gradient(rgba(255,255,255,0.03), rgba(255,255,255,0.03)), #05070b",
                borderWidth: 1,
                borderStyle: "solid",
                borderColor: isActive ? `${nodeColor}50` : "rgba(255,255,255,0.08)",
              }}
            >
              <Icon
                size={18}
                aria-hidden="true"
                color={isActive ? (gradient ? "#fff" : nodeColor) : "rgba(255,255,255,0.55)"}
              />
            </div>

            {/* Text */}
            <div className="flex flex-col gap-0.5 min-w-0">
              <span
                className={`text-xs font-black uppercase tracking-widest transition-colors duration-300 ${
                  isActive ? "text-white" : "text-zinc-300"
                }`}
              >
                {stage.label}
              </span>
              <span
                className={`text-xs transition-colors duration-300 ${
                  isActive ? "text-zinc-300" : "text-zinc-400 truncate"
                }`}
              >
                {stage.who}
              </span>
            </div>

            {/* Actor badge + step number */}
            <div className="ml-auto flex flex-col items-end gap-1 shrink-0">
              {/* Full strength even when inactive: at 75% opacity the orange
                  "Agents" badge fell to 3.9:1. */}
              <span
                className="text-xs font-bold uppercase tracking-widest"
                style={{ color: stage.actor === "agent" ? AGENT_COLOR : HUMAN_COLOR }}
              >
                {actorLabel(stage.actor)}
              </span>
              <span
                className="text-xs font-mono font-bold"
                style={{
                  color: isActive ? nodeColor : "#a1a1aa",
                }}
              >
                {index + 1}/{STAGE_COUNT}
              </span>
            </div>
          </motion.button>
        );
      })}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Main component                                                     */
/* ------------------------------------------------------------------ */

export function HumanAgentTimelineViz() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const rm = prefersReducedMotion ?? false;

  const [activeIndex, setActiveIndex] = useState(0);

  const currentStage = STAGES[activeIndex];

  const handleSelect = useCallback((index: number) => {
    setActiveIndex(index);
  }, []);

  const advance = useCallback(() => {
    setActiveIndex((prev) => Math.min(prev + 1, STAGE_COUNT - 1));
  }, []);

  const reset = useCallback(() => {
    setActiveIndex(0);
  }, []);

  /* Keyboard navigation — only when this viz is in the viewport */
  useEffect(() => {
    if (!isInView) return;
    function handleKeyDown(e: KeyboardEvent) {
      if (e.defaultPrevented || e.isComposing || e.ctrlKey || e.metaKey || e.altKey
        || isInteractiveKeyboardTarget(e.target)) return;
      const bounds = ref.current?.getBoundingClientRect();
      if (!bounds || bounds.bottom <= 0 || bounds.top >= window.innerHeight) return;
      if (e.key === "ArrowRight") {
        e.preventDefault();
        setActiveIndex((cur) => Math.min(cur + 1, STAGE_COUNT - 1));
      } else if (e.key === "ArrowLeft") {
        e.preventDefault();
        setActiveIndex((cur) => Math.max(cur - 1, 0));
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isInView]);

  /* Count by actor type for the summary */
  const humanCount = STAGES.filter((s) => s.actor === "human").length;
  const agentCount = STAGES.filter((s) => s.actor === "agent").length;
  const bothCount = STAGES.filter((s) => s.actor === "both").length;

  return (
    <div ref={ref} className={EXHIBIT_PANEL_CLASS + " relative group/viz"}>
      {/* Background texture & ambient glow */}
      <div className="absolute inset-0 noise-overlay opacity-[0.02] mix-blend-overlay pointer-events-none" />
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[min(900px,100%)] h-[900px] bg-[radial-gradient(ellipse_at_center,rgba(167,139,250,0.02),transparent_60%)] pointer-events-none" />

      {/* Header */}
      <div className="relative z-10 border-b border-white/[0.04] pb-10 flex flex-col gap-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="max-w-xl">
            <div className="text-xs font-bold uppercase tracking-widest text-[#a78bfa]/80 flex items-center gap-3 mb-4">
              <span className="w-1.5 h-1.5 rounded-full bg-[#a78bfa]" />
              Interactive Exhibit
            </div>
            <h3 className="font-serif text-[1.5rem] font-normal leading-[1.12] tracking-[-0.008em] text-white sm:text-[1.875rem]">
              Who Does What in the Core Loop
            </h3>
            <p className="mt-4 text-[1.05rem] leading-relaxed text-zinc-400 font-light">
              You design the system and tend the swarm.{" "}
              <span className="text-white/60">Agents do the coordination work.</span>
            </p>
          </div>

          {/* Proportion summary */}
          <div className="shrink-0 flex flex-col gap-2 px-5 py-4 rounded-2xl bg-white/[0.02] border border-white/[0.04]">
            <span className="text-xs font-bold uppercase tracking-widest text-zinc-400">
              Breakdown
            </span>
            <div className="flex items-center gap-4 text-sm font-mono">
              <span style={{ color: HUMAN_COLOR }}>{humanCount} you</span>
              <span style={{ color: AGENT_COLOR }}>{agentCount} agents</span>
              <span className="text-zinc-300">{bothCount} both</span>
            </div>
          </div>
        </div>

        {/* Legend */}
        <Legend />
      </div>

      {/* Body */}
      <div className="relative z-10 mt-10 flex flex-col gap-10">
        {/* Timeline */}
        {isInView && (
          <>
            <DesktopTimeline activeIndex={activeIndex} onSelect={handleSelect} reducedMotion={rm} />
            <MobileTimeline activeIndex={activeIndex} onSelect={handleSelect} reducedMotion={rm} />
          </>
        )}

        {/* Detail card */}
        <div className="min-h-[280px]">
          <AnimatePresence mode="wait">
            <DetailCard stage={currentStage} reducedMotion={rm} />
          </AnimatePresence>
        </div>

        {/* Controls */}
        {/* Wraps on phones: the dots get their own row and the two buttons
            share the row below, instead of squeezing into one line. */}
        <div className="flex flex-wrap items-center justify-center gap-x-6 gap-y-4 pt-6 border-t border-white/[0.04] sm:justify-between">
          {/* Stage indicator dots */}
          <div className="flex items-center gap-1 sm:gap-2">
            <span className="text-xs font-bold uppercase tracking-[0.3em] text-zinc-500 mr-2 hidden sm:inline">
              Stage
            </span>
            {STAGES.map((stage, index) => {
              const dotColor = stageNodeColor(stage);
              const gradient = stageNodeGradient(stage);
              return (
                <button
                  key={stage.id}
                  type="button"
                  onClick={() => handleSelect(index)}
                  aria-label={`Go to stage ${index + 1}: ${stage.label}`}
                  title={`${index + 1}. ${stage.label}`}
                  aria-current={index === activeIndex ? "step" : undefined}
                  className="inline-flex min-h-6 min-w-6 items-center justify-center rounded-full p-2 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-[#a78bfa]/60"
                >
                  <motion.div
                    className="rounded-full"
                    style={{
                      width: index === activeIndex ? 20 : 8,
                      height: 8,
                      background:
                        index === activeIndex ? gradient || dotColor : "rgba(255,255,255,0.22)",
                      boxShadow: index === activeIndex ? `0 0 10px ${dotColor}60` : "none",
                    }}
                    layout
                    transition={
                      rm ? { duration: 0 } : { type: "spring", stiffness: 200, damping: 25 }
                    }
                  />
                </button>
              );
            })}
          </div>

          {/* Advance / Reset buttons */}
          <div className="flex w-full gap-3 sm:w-auto">
            <button
              type="button"
              onClick={advance}
              disabled={activeIndex >= STAGE_COUNT - 1}
              // Dark text: white on #a78bfa / #FF5500 is only 2.7-3.3:1.
              className="flex-1 whitespace-nowrap rounded-xl px-5 py-2.5 text-sm font-bold text-slate-950 transition hover:scale-[1.02] active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-40 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-white/70 focus-visible:ring-offset-2 focus-visible:ring-offset-[#020408] sm:flex-none"
              style={{
                background: currentStage.actor === "agent" ? AGENT_COLOR : HUMAN_COLOR,
              }}
            >
              Advance
            </button>
            <button
              type="button"
              onClick={reset}
              className="flex-1 whitespace-nowrap rounded-xl border px-5 py-2.5 text-sm font-medium text-slate-300 transition hover:bg-white/5 hover:scale-[1.02] active:scale-[0.98] focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-[#a78bfa]/60 sm:flex-none"
              style={{ borderColor: "#334155" }}
            >
              Reset
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
