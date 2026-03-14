"use client";

import { useState, useCallback, useEffect, useRef } from "react";
import {
  AnimatePresence,
  motion,
  useInView,
  useReducedMotion,
} from "framer-motion";
import {
  FileText,
  Layers,
  BookOpen,
  Rocket,
  Radio,
  Code,
  Eye,
  ShieldCheck,
  Lightbulb,
  User,
  Bot,
  Wrench,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

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
    what: "Ask multiple frontier models for competing plans, then synthesize into one strong design document",
    tools: "GPT Pro, Claude, Gemini web apps",
    insight: "This is where 85% of your thinking goes. No code yet.",
  },
  {
    id: "beads",
    label: "Convert to Beads",
    actor: "human",
    color: HUMAN_COLOR_LIGHT,
    icon: Layers,
    who: "You (via an agent)",
    what: "Tell a coding agent to create beads from the plan with dependencies. Then polish them 4\u20136 times.",
    tools: "Claude Code with br",
    insight: "You prompt the agent. The agent runs the br commands.",
  },
  {
    id: "agents-md",
    label: "Write AGENTS.md",
    actor: "human",
    color: HUMAN_COLOR,
    icon: BookOpen,
    who: "You",
    what: "Write the operating manual: agent behavior rules, tool usage, and coordination protocol.",
    tools: "Your text editor",
    insight: "Every agent reads this file on startup. It replaces verbal instructions.",
  },
  {
    id: "launch",
    label: "Launch Agents",
    actor: "human",
    color: HUMAN_COLOR,
    icon: Rocket,
    who: "You",
    what: "Start 2\u20134 agent sessions and paste the marching orders prompt into each one.",
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
    what: "Register with Agent Mail, discover peers, claim beads, reserve files, announce what they\u2019re working on.",
    tools: "Agent Mail MCP, br, bv",
    insight:
      "You never type these commands. Agents do it because AGENTS.md tells them to.",
  },
  {
    id: "implement",
    label: "Implement & Test",
    actor: "agent",
    color: AGENT_COLOR,
    icon: Code,
    who: "Agents (automatically)",
    what: "Write code, run tests, do fresh-eyes self-review, close the bead, pick the next one via bv.",
    tools: "br, bv, code editor",
    insight:
      "The bead carries all the context. The agent doesn\u2019t need to ask you what to do.",
  },
  {
    id: "tend",
    label: "Tend the Swarm",
    actor: "human",
    color: HUMAN_COLOR,
    icon: Eye,
    who: "You (every 10\u201315 min)",
    what: "Check bv for stuck beads, rescue confused agents by telling them to reread AGENTS.md, add missing beads.",
    tools: "bv --robot-triage, Agent Mail inbox",
    insight:
      "About 5 minutes of checking every 15 minutes.",
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
    insight:
      "You decide when quality is high enough. Agents do the actual reviewing.",
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

function DetailCard({
  stage,
  reducedMotion,
}: {
  stage: TimelineStage;
  reducedMotion: boolean;
}) {
  const dur = reducedMotion ? 0 : 0.4;
  const borderColor =
    stage.actor === "both"
      ? AGENT_COLOR
      : stage.color;

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
            className="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-[0.6rem] font-bold uppercase tracking-widest"
            style={{
              backgroundColor:
                stage.actor === "agent"
                  ? `${AGENT_COLOR}18`
                  : stage.actor === "both"
                    ? `${AGENT_COLOR}10`
                    : `${HUMAN_COLOR}18`,
              color: stage.actor === "agent" ? AGENT_COLOR : stage.actor === "both" ? "#e2e8f0" : HUMAN_COLOR,
              border: `1px solid ${stage.actor === "agent" ? `${AGENT_COLOR}30` : stage.actor === "both" ? "rgba(255,255,255,0.08)" : `${HUMAN_COLOR}30`}`,
            }}
          >
            {stage.actor === "agent" ? (
              <Bot size={10} />
            ) : stage.actor === "both" ? (
              <>
                <User size={10} style={{ color: HUMAN_COLOR }} />
                <span className="text-white/30">+</span>
                <Bot size={10} style={{ color: AGENT_COLOR }} />
              </>
            ) : (
              <User size={10} />
            )}
            {actorLabel(stage.actor)}
          </span>
        </div>
        <h5 className="text-2xl sm:text-3xl font-black text-white tracking-tight leading-none drop-shadow-md">
          {stage.label}
        </h5>
      </div>

      {/* Info grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        {/* Who */}
        <div className="flex flex-col gap-2 p-4 rounded-2xl bg-white/[0.03] border border-white/[0.05] relative overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-br from-white/[0.015] to-transparent pointer-events-none" />
          <span className="text-[0.6rem] font-bold text-white/30 uppercase tracking-widest flex items-center gap-2">
            <User size={10} className="opacity-50" />
            Who
          </span>
          <p className="text-sm text-white/90 font-medium">{stage.who}</p>
        </div>

        {/* Tools */}
        <div className="flex flex-col gap-2 p-4 rounded-2xl bg-white/[0.02] border border-white/[0.04] relative overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />
          <span className="text-[0.6rem] font-bold text-white/30 uppercase tracking-widest flex items-center gap-2">
            <Wrench size={10} className="opacity-50" />
            Tools
          </span>
          <p className="text-sm text-white/90 font-mono font-medium break-all">
            {stage.tools}
          </p>
        </div>
      </div>

      {/* What */}
      <div className="p-4 rounded-2xl bg-white/[0.02] border border-white/[0.04] relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />
        <p className="text-sm leading-relaxed text-zinc-400 font-light">
          {stage.what}
        </p>
      </div>

      {/* Insight */}
      <div className="flex items-start gap-3 p-4 rounded-2xl bg-white/[0.015] border border-white/[0.04] relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-white/[0.005] to-transparent pointer-events-none" />
        <Lightbulb
          size={16}
          className="mt-0.5 shrink-0"
          style={{
            color:
              stage.actor === "agent"
                ? AGENT_COLOR
                : HUMAN_COLOR,
          }}
        />
        <p className="text-sm leading-relaxed text-zinc-400 font-light italic">
          {stage.insight}
        </p>
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
    <div className="hidden md:block">
      <div className="flex items-center justify-between relative">
        {/* Connecting line behind nodes */}
        <div className="absolute top-1/2 left-0 right-0 h-px -translate-y-1/2 pointer-events-none">
          <div
            className="w-full h-full"
            style={{
              background:
                "linear-gradient(to right, transparent, rgba(255,255,255,0.08) 5%, rgba(255,255,255,0.08) 95%, transparent)",
            }}
          />
        </div>

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
              className="relative z-10 flex flex-col items-center gap-2 group cursor-pointer"
              aria-label={`Select stage ${index + 1}: ${stage.label}`}
              style={{ flex: "1 1 0%" }}
            >
              {/* Connecting segment to next node */}
              {index < STAGE_COUNT - 1 && (
                <div
                  className="absolute top-[22px] left-[calc(50%+22px)] right-0 h-[2px] pointer-events-none"
                  style={{
                    background:
                      isPast || isActive
                        ? `linear-gradient(to right, ${nodeColor}, ${stageNodeColor(STAGES[index + 1])})`
                        : "rgba(255,255,255,0.05)",
                    opacity: isPast || isActive ? 0.5 : 1,
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

              {/* Pulse ring */}
              {isActive && !reducedMotion && (
                <motion.div
                  className="absolute top-[6px] w-[36px] h-[36px] rounded-full"
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

              {/* Node circle */}
              <motion.div
                className="relative flex items-center justify-center rounded-full transition-shadow duration-300"
                style={{
                  width: isActive ? 44 : 36,
                  height: isActive ? 44 : 36,
                  background: gradient
                    ? isActive
                      ? gradient
                      : `${nodeColor}22`
                    : isActive
                      ? nodeColor
                      : `${nodeColor}22`,
                  border: `2px solid ${isActive ? nodeColor : isPast ? `${nodeColor}66` : `${nodeColor}25`}`,
                  boxShadow: isActive
                    ? `0 0 20px ${nodeColor}40, 0 0 40px ${nodeColor}15`
                    : "none",
                }}
                transition={{ duration: dur }}
              >
                <Icon
                  size={isActive ? 20 : 16}
                  color={isActive ? "#fff" : isPast ? nodeColor : `${nodeColor}88`}
                  strokeWidth={isActive ? 2.5 : 2}
                />
              </motion.div>

              {/* Label */}
              <span
                className="text-[0.55rem] font-bold uppercase tracking-wider text-center leading-tight max-w-[80px] transition-colors duration-300"
                style={{
                  color: isActive
                    ? "#fff"
                    : isPast
                      ? "rgba(255,255,255,0.5)"
                      : "rgba(255,255,255,0.25)",
                }}
              >
                {stage.label}
              </span>

              {/* Step number */}
              <span
                className="text-[0.5rem] font-mono font-bold"
                style={{
                  color: isActive ? nodeColor : "rgba(255,255,255,0.15)",
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
    <div className="md:hidden relative flex flex-col gap-2">
      {/* Vertical connecting line */}
      <div
        className="absolute left-[1.25rem] top-4 bottom-4 w-px pointer-events-none"
        style={{
          background:
            "linear-gradient(to bottom, transparent, rgba(255,255,255,0.06) 15%, rgba(255,255,255,0.06) 85%, transparent)",
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
            className={`relative flex items-center gap-4 px-5 py-3.5 rounded-2xl border transition-all duration-300 text-left ${
              isActive
                ? "border-white/[0.08] bg-white/[0.04]"
                : "border-white/[0.03] bg-white/[0.01] hover:bg-white/[0.03]"
            }`}
            style={{
              borderLeftWidth: isActive ? 3 : 1,
              borderLeftColor: isActive ? nodeColor : undefined,
              boxShadow: isActive
                ? `0 4px 24px -4px ${nodeColor}30, 0 0 0 1px ${nodeColor}15`
                : undefined,
            }}
            animate={
              isActive && !reducedMotion
                ? { scale: [1, 1.01, 1] }
                : { scale: 1 }
            }
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
            {/* Node icon */}
            <div
              className={`relative z-10 flex items-center justify-center w-10 h-10 rounded-xl shrink-0 transition-all duration-300 ${
                isActive ? "shadow-lg" : ""
              }`}
              style={{
                background: isActive
                  ? gradient || `${nodeColor}20`
                  : "rgba(255,255,255,0.02)",
                borderWidth: 1,
                borderStyle: "solid",
                borderColor: isActive
                  ? `${nodeColor}50`
                  : "rgba(255,255,255,0.04)",
              }}
            >
              <Icon
                size={18}
                color={isActive ? (gradient ? "#fff" : nodeColor) : "rgba(255,255,255,0.3)"}
              />
            </div>

            {/* Text */}
            <div className="flex flex-col gap-0.5 min-w-0">
              <span
                className={`text-xs font-black uppercase tracking-widest transition-colors duration-300 ${
                  isActive ? "text-white" : "text-white/40"
                }`}
              >
                {stage.label}
              </span>
              <span
                className={`text-[0.65rem] transition-colors duration-300 ${
                  isActive ? "text-white/40" : "text-white/20 truncate"
                }`}
              >
                {stage.who}
              </span>
            </div>

            {/* Actor badge + step number */}
            <div className="ml-auto flex flex-col items-end gap-1 shrink-0">
              <span
                className="text-[0.5rem] font-bold uppercase tracking-widest"
                style={{
                  color: isActive
                    ? stage.actor === "agent"
                      ? AGENT_COLOR
                      : HUMAN_COLOR
                    : "rgba(255,255,255,0.15)",
                }}
              >
                {actorLabel(stage.actor)}
              </span>
              <span
                className="text-[0.55rem] font-mono font-bold"
                style={{
                  color: isActive ? nodeColor : "rgba(255,255,255,0.12)",
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
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.02] mix-blend-overlay pointer-events-none" />
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[900px] h-[900px] bg-[radial-gradient(ellipse_at_center,rgba(167,139,250,0.02),transparent_60%)] pointer-events-none" />

      {/* Header */}
      <div className="relative z-10 border-b border-white/[0.04] pb-10 flex flex-col gap-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="max-w-xl">
            <div className="text-[0.65rem] font-bold uppercase tracking-widest text-[#a78bfa]/80 flex items-center gap-3 mb-4">
              <span className="w-1.5 h-1.5 rounded-full bg-[#a78bfa] animate-pulse shadow-[0_0_8px_rgba(167,139,250,0.8)]" />
              Interactive Exhibit
            </div>
            <h4 className="text-3xl font-black tracking-tight text-white sm:text-4xl leading-[1.15] drop-shadow-lg">
              Who Does What in the Core Loop
            </h4>
            <p className="mt-4 text-[1.05rem] leading-relaxed text-zinc-400 font-light">
              You design the system and tend the swarm.{" "}
              <span className="text-white/60">
                Agents do the coordination work.
              </span>
            </p>
          </div>

          {/* Proportion summary */}
          <div className="shrink-0 flex flex-col gap-2 px-5 py-4 rounded-2xl bg-white/[0.02] border border-white/[0.04]">
            <span className="text-[0.55rem] font-bold uppercase tracking-widest text-white/25">
              Breakdown
            </span>
            <div className="flex items-center gap-4 text-sm font-mono">
              <span style={{ color: HUMAN_COLOR }}>
                {humanCount} you
              </span>
              <span style={{ color: AGENT_COLOR }}>
                {agentCount} agents
              </span>
              <span className="text-white/50">
                {bothCount} both
              </span>
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
            <DesktopTimeline
              activeIndex={activeIndex}
              onSelect={handleSelect}
              reducedMotion={rm}
            />
            <MobileTimeline
              activeIndex={activeIndex}
              onSelect={handleSelect}
              reducedMotion={rm}
            />
          </>
        )}

        {/* Detail card */}
        <div className="min-h-[280px]">
          <AnimatePresence mode="wait">
            <DetailCard
              stage={currentStage}
              reducedMotion={rm}
            />
          </AnimatePresence>
        </div>

        {/* Controls */}
        <div className="flex items-center justify-between pt-6 border-t border-white/[0.04]">
          {/* Stage indicator dots */}
          <div className="flex items-center gap-2">
            <span className="text-[0.6rem] font-bold uppercase tracking-[0.3em] text-white/20 mr-2 hidden sm:inline">
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
                  className="p-1"
                >
                  <motion.div
                    className="rounded-full"
                    style={{
                      width: index === activeIndex ? 20 : 8,
                      height: 8,
                      background:
                        index === activeIndex
                          ? gradient || dotColor
                          : "rgba(255,255,255,0.1)",
                      boxShadow:
                        index === activeIndex
                          ? `0 0 10px ${dotColor}60`
                          : "none",
                    }}
                    layout
                    transition={
                      rm
                        ? { duration: 0 }
                        : { type: "spring", stiffness: 200, damping: 25 }
                    }
                  />
                </button>
              );
            })}
          </div>

          {/* Advance / Reset buttons */}
          <div className="flex gap-3">
            <button
              type="button"
              onClick={advance}
              disabled={activeIndex >= STAGE_COUNT - 1}
              className="rounded-xl px-5 py-2.5 text-sm font-bold text-white transition-all hover:scale-[1.02] active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-40"
              style={{
                background:
                  currentStage.actor === "agent"
                    ? AGENT_COLOR
                    : HUMAN_COLOR,
              }}
            >
              Advance
            </button>
            <button
              type="button"
              onClick={reset}
              className="rounded-xl border px-5 py-2.5 text-sm font-medium text-slate-300 transition-all hover:bg-white/5 hover:scale-[1.02] active:scale-[0.98]"
              style={{ borderColor: "#1e293b" }}
            >
              Reset
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
