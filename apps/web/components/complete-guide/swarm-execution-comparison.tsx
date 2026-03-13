"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "framer-motion";
import {
  AlertTriangle,
  CheckCircle2,
  ChevronRight,
  Pause,
  Play,
  RotateCcw,
  Users,
} from "lucide-react";
import { cn } from "@/lib/utils";

const EXHIBIT_PANEL_CLASS =
  "my-10 overflow-hidden rounded-[28px] border border-white/[0.12] bg-[radial-gradient(circle_at_top,rgba(16,185,129,0.1),transparent_42%),linear-gradient(180deg,rgba(15,23,42,0.96),rgba(2,6,23,0.96))] p-5 sm:p-6 lg:p-7 backdrop-blur-xl shadow-[0_35px_90px_-40px_rgba(2,6,23,0.95),inset_0_1px_1px_rgba(255,255,255,0.08)]";

type ScenarioId = "herd" | "staggered";
type AgentTone = "idle" | "boot" | "claiming" | "blocked" | "working" | "done";
type BeadTone = "ready" | "claimed" | "contested" | "done";

type AgentFrame = {
  status: string;
  progress: number;
  tone: AgentTone;
  target?: string;
};

type BeadFrame = {
  id: string;
  tone: BeadTone;
  owner?: string;
  note: string;
};

type ScenarioFrame = {
  caption: string;
  verdict: string;
  metrics: {
    conflicts: number;
    idleBurn: number;
    completed: number;
  };
  agents: readonly AgentFrame[];
  beads: readonly BeadFrame[];
};

type ScenarioDefinition = {
  title: string;
  accent: string;
  badge: string;
  summary: string;
  frames: readonly ScenarioFrame[];
};

const PHASES = [
  { label: "Spawn", detail: "Who starts when" },
  { label: "Claim", detail: "First contact with ready beads" },
  { label: "Resolve", detail: "Lock collisions or clean frontier" },
  { label: "Flow", detail: "Parallel work settles in" },
  { label: "Outcome", detail: "Who spent the cycle shipping" },
] as const;

const AGENTS = [
  { id: "A1", role: "UI" },
  { id: "A2", role: "API" },
  { id: "A3", role: "DB" },
  { id: "A4", role: "Tests" },
] as const;

const SCENARIOS: Record<ScenarioId, ScenarioDefinition> = {
  herd: {
    title: "Thundering Herd",
    accent: "#FF5500",
    badge: "Collision-prone",
    summary: "All agents wake together, re-read context together, and pile onto the same frontier.",
    frames: [
      {
        caption: "The swarm is synchronized before any useful work has started.",
        verdict: "Nothing is broken yet, but the timing guarantees a crowded first claim.",
        metrics: { conflicts: 0, idleBurn: 6, completed: 0 },
        agents: [
          { status: "Booting from the same starting gun", progress: 18, tone: "boot" },
          { status: "Booting from the same starting gun", progress: 18, tone: "boot" },
          { status: "Booting from the same starting gun", progress: 18, tone: "boot" },
          { status: "Booting from the same starting gun", progress: 18, tone: "boot" },
        ],
        beads: [
          { id: "br-201", tone: "ready", note: "ready" },
          { id: "br-202", tone: "ready", note: "ready" },
          { id: "br-203", tone: "ready", note: "ready" },
          { id: "br-204", tone: "ready", note: "ready" },
        ],
      },
      {
        caption: "Everyone reaches the ready queue together and dogpiles the same bead.",
        verdict: "The first lock is now a traffic jam instead of a clean assignment.",
        metrics: { conflicts: 3, idleBurn: 22, completed: 0 },
        agents: [
          { status: "Claiming", progress: 34, tone: "claiming", target: "br-201" },
          { status: "Claiming", progress: 34, tone: "claiming", target: "br-201" },
          { status: "Claiming", progress: 34, tone: "claiming", target: "br-201" },
          { status: "Claiming", progress: 34, tone: "claiming", target: "br-201" },
        ],
        beads: [
          { id: "br-201", tone: "contested", note: "4 lock attempts" },
          { id: "br-202", tone: "ready", note: "ignored" },
          { id: "br-203", tone: "ready", note: "ignored" },
          { id: "br-204", tone: "ready", note: "ignored" },
        ],
      },
      {
        caption: "One agent wins. The rest spend their first real cycle retrying or waiting.",
        verdict: "Parallelism already degraded because the swarm fought over the same frontier.",
        metrics: { conflicts: 3, idleBurn: 38, completed: 0 },
        agents: [
          { status: "Working", progress: 58, tone: "working", target: "br-201" },
          { status: "Lock retry", progress: 41, tone: "blocked", target: "br-201" },
          { status: "Lock retry", progress: 37, tone: "blocked", target: "br-201" },
          { status: "Fallback claim", progress: 45, tone: "claiming", target: "br-202" },
        ],
        beads: [
          { id: "br-201", tone: "claimed", owner: "A1", note: "locked" },
          { id: "br-202", tone: "claimed", owner: "A4", note: "late claim" },
          { id: "br-203", tone: "ready", note: "still idle" },
          { id: "br-204", tone: "ready", note: "still idle" },
        ],
      },
      {
        caption: "The queue recovers slowly, but the first round of wasted motion cannot be reclaimed.",
        verdict: "Some progress appears, but the cycle has already paid unnecessary coordination tax.",
        metrics: { conflicts: 2, idleBurn: 31, completed: 2 },
        agents: [
          { status: "Done", progress: 100, tone: "done", target: "br-201" },
          { status: "Working", progress: 62, tone: "working", target: "br-203" },
          { status: "Still resynchronizing", progress: 46, tone: "blocked", target: "br-203" },
          { status: "Done", progress: 100, tone: "done", target: "br-202" },
        ],
        beads: [
          { id: "br-201", tone: "done", owner: "A1", note: "complete" },
          { id: "br-202", tone: "done", owner: "A4", note: "complete" },
          { id: "br-203", tone: "claimed", owner: "A2", note: "in progress" },
          { id: "br-204", tone: "ready", note: "still waiting" },
        ],
      },
      {
        caption: "Throughput returns, but two agents spent most of the early phase negotiating for the same lock.",
        verdict: "The herd eventually moves, but not before burning the exact cycles parallelism was supposed to save.",
        metrics: { conflicts: 2, idleBurn: 28, completed: 3 },
        agents: [
          { status: "Done", progress: 100, tone: "done", target: "br-201" },
          { status: "Done", progress: 100, tone: "done", target: "br-203" },
          { status: "Working", progress: 74, tone: "working", target: "br-204" },
          { status: "Done", progress: 100, tone: "done", target: "br-202" },
        ],
        beads: [
          { id: "br-201", tone: "done", owner: "A1", note: "complete" },
          { id: "br-202", tone: "done", owner: "A4", note: "complete" },
          { id: "br-203", tone: "done", owner: "A2", note: "complete" },
          { id: "br-204", tone: "claimed", owner: "A3", note: "late start" },
        ],
      },
    ],
  },
  staggered: {
    title: "Staggered Start",
    accent: "#FFBD2E",
    badge: "Frontier-friendly",
    summary: "Agents enter a few beats apart, so each arrival sees a different clean frontier.",
    frames: [
      {
        caption: "Only the first agent is awake. The rest are still off the critical path.",
        verdict: "The swarm keeps optionality because it has not synchronized itself into contention.",
        metrics: { conflicts: 0, idleBurn: 2, completed: 0 },
        agents: [
          { status: "Booting", progress: 20, tone: "boot" },
          { status: "Queued", progress: 0, tone: "idle" },
          { status: "Queued", progress: 0, tone: "idle" },
          { status: "Queued", progress: 0, tone: "idle" },
        ],
        beads: [
          { id: "br-201", tone: "ready", note: "ready" },
          { id: "br-202", tone: "ready", note: "ready" },
          { id: "br-203", tone: "ready", note: "ready" },
          { id: "br-204", tone: "ready", note: "ready" },
        ],
      },
      {
        caption: "A1 reaches the first bead before anyone else is even ready to fight for it.",
        verdict: "The lock becomes a handoff surface instead of a collision surface.",
        metrics: { conflicts: 0, idleBurn: 4, completed: 0 },
        agents: [
          { status: "Claiming", progress: 36, tone: "claiming", target: "br-201" },
          { status: "Booting", progress: 18, tone: "boot" },
          { status: "Queued", progress: 0, tone: "idle" },
          { status: "Queued", progress: 0, tone: "idle" },
        ],
        beads: [
          { id: "br-201", tone: "claimed", owner: "A1", note: "clean lock" },
          { id: "br-202", tone: "ready", note: "next up" },
          { id: "br-203", tone: "ready", note: "next up" },
          { id: "br-204", tone: "ready", note: "next up" },
        ],
      },
      {
        caption: "As A1 works, A2 and A3 arrive onto still-open territory instead of retry loops.",
        verdict: "The swarm expands like a wave rather than collapsing into a knot.",
        metrics: { conflicts: 0, idleBurn: 8, completed: 0 },
        agents: [
          { status: "Working", progress: 68, tone: "working", target: "br-201" },
          { status: "Claiming", progress: 34, tone: "claiming", target: "br-202" },
          { status: "Booting", progress: 20, tone: "boot" },
          { status: "Queued", progress: 0, tone: "idle" },
        ],
        beads: [
          { id: "br-201", tone: "claimed", owner: "A1", note: "in progress" },
          { id: "br-202", tone: "claimed", owner: "A2", note: "clean lock" },
          { id: "br-203", tone: "ready", note: "open frontier" },
          { id: "br-204", tone: "ready", note: "open frontier" },
        ],
      },
      {
        caption: "By the time A4 wakes, the first beads are already turning over cleanly.",
        verdict: "The stagger converts startup timing into sustained throughput.",
        metrics: { conflicts: 0, idleBurn: 10, completed: 2 },
        agents: [
          { status: "Done", progress: 100, tone: "done", target: "br-201" },
          { status: "Working", progress: 70, tone: "working", target: "br-202" },
          { status: "Claiming", progress: 38, tone: "claiming", target: "br-203" },
          { status: "Booting", progress: 18, tone: "boot" },
        ],
        beads: [
          { id: "br-201", tone: "done", owner: "A1", note: "complete" },
          { id: "br-202", tone: "claimed", owner: "A2", note: "in progress" },
          { id: "br-203", tone: "claimed", owner: "A3", note: "clean lock" },
          { id: "br-204", tone: "ready", note: "still open" },
        ],
      },
      {
        caption: "Each agent spends its first serious cycle on a different bead instead of on lock arbitration.",
        verdict: "More of the swarm's attention ends up in shipping, not queue negotiation.",
        metrics: { conflicts: 0, idleBurn: 12, completed: 4 },
        agents: [
          { status: "Done", progress: 100, tone: "done", target: "br-201" },
          { status: "Done", progress: 100, tone: "done", target: "br-202" },
          { status: "Working", progress: 82, tone: "working", target: "br-203" },
          { status: "Claiming", progress: 36, tone: "claiming", target: "br-204" },
        ],
        beads: [
          { id: "br-201", tone: "done", owner: "A1", note: "complete" },
          { id: "br-202", tone: "done", owner: "A2", note: "complete" },
          { id: "br-203", tone: "claimed", owner: "A3", note: "steady work" },
          { id: "br-204", tone: "claimed", owner: "A4", note: "clean lock" },
        ],
      },
    ],
  },
};

function getAgentToneClasses(tone: AgentTone) {
  switch (tone) {
    case "boot":
      return "border-[#A1A1AA]/22 bg-[#A1A1AA]/10 text-[#A1A1AA]";
    case "claiming":
      return "border-[#FFBD2E]/22 bg-[#FFBD2E]/10 text-[#FFBD2E]";
    case "blocked":
      return "border-[#FF5500]/24 bg-[#FF5500]/10 text-[#FF5500]";
    case "working":
      return "border-zinc-500/24 bg-zinc-500/10 text-zinc-300";
    case "done":
      return "border-zinc-400/30 bg-zinc-400/14 text-zinc-200";
    default:
      return "border-white/10 bg-white/[0.04] text-white/60";
  }
}

function getBeadToneClasses(tone: BeadTone) {
  switch (tone) {
    case "claimed":
      return "border-[#FFBD2E]/22 bg-[#FFBD2E]/10";
    case "contested":
      return "border-[#FF5500]/28 bg-[#FF5500]/10";
    case "done":
      return "border-zinc-500/28 bg-zinc-500/10";
    default:
      return "border-white/10 bg-white/[0.03]";
  }
}

function ScenarioPanel({
  scenarioId,
  phaseIndex,
}: {
  scenarioId: ScenarioId;
  phaseIndex: number;
}) {
  const scenario = SCENARIOS[scenarioId];
  const frame = scenario.frames[phaseIndex];
  const accent = scenario.accent;

  return (
    <div
      className="rounded-[28px] border p-5"
      style={{
        borderColor: `${accent}33`,
        background:
          scenarioId === "herd"
            ? "linear-gradient(180deg,rgba(69,10,10,0.18),rgba(15,23,42,0.7))"
            : "linear-gradient(180deg,rgba(6,78,59,0.16),rgba(15,23,42,0.7))",
      }}
    >
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <div
            className="text-[0.65rem] font-semibold uppercase tracking-[0.22em]"
            style={{ color: accent }}
          >
            {scenario.badge}
          </div>
          <div className="mt-1 text-lg sm:text-xl font-black tracking-[-0.03em] text-white">
            {scenario.title}
          </div>
          <p className="mt-1.5 text-xs sm:text-sm leading-relaxed text-white/62 pr-4">{scenario.summary}</p>
        </div>

        <div className="flex gap-2 sm:shrink-0 sm:self-start">
          <div className="rounded-xl border border-white/10 bg-slate-950/60 px-2 py-1.5 min-w-[70px] flex flex-col items-center justify-center">
            <div className="text-[9px] uppercase tracking-[0.15em] text-white/40">conflicts</div>
            <div className="mt-0.5 text-base font-black text-white leading-none">{frame.metrics.conflicts}</div>
          </div>
          <div className="rounded-xl border border-white/10 bg-slate-950/60 px-2 py-1.5 min-w-[70px] flex flex-col items-center justify-center">
            <div className="text-[9px] uppercase tracking-[0.15em] text-white/40">idle burn</div>
            <div className="mt-0.5 text-base font-black text-white leading-none">{frame.metrics.idleBurn}</div>
          </div>
          <div className="rounded-xl border border-white/10 bg-slate-950/60 px-2 py-1.5 min-w-[70px] flex flex-col items-center justify-center">
            <div className="text-[9px] uppercase tracking-[0.15em] text-white/40">completed</div>
            <div className="mt-0.5 text-base font-black text-white leading-none">{frame.metrics.completed}</div>
          </div>
        </div>
      </div>

      <p className="mt-4 rounded-xl border border-white/8 bg-slate-950/50 px-4 py-2.5 text-xs sm:text-sm leading-relaxed text-white/72">
        {frame.caption}
      </p>

      <div className="mt-4 space-y-2">
        {AGENTS.map((agent, index) => {
          const agentFrame = frame.agents[index];
          return (
            <motion.div
              key={`${scenarioId}-${agent.id}-${phaseIndex}`}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: index * 0.05 }}
              className={cn(
                "relative overflow-hidden rounded-[16px] border p-2.5",
                getAgentToneClasses(agentFrame.tone),
              )}
            >
              <div
                className="absolute inset-y-0 left-0 bg-white/[0.05]"
                style={{ width: `${agentFrame.progress}%` }}
              />
              <div className="relative z-10 flex items-center gap-3">
                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-white/10 bg-slate-950/70 text-[10px] font-black text-white">
                  {agent.id}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <span className="text-xs font-semibold text-white">{agent.role}</span>
                    {agentFrame.target && (
                      <span className="rounded-full border border-white/10 bg-black/25 px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-[0.18em] text-white/70 whitespace-nowrap">
                        {agentFrame.target}
                      </span>
                    )}
                  </div>
                  <div className="mt-0.5 text-[10px] sm:text-[11px] text-white/75 truncate">{agentFrame.status}</div>
                </div>
                <div className="text-xs font-black tabular-nums text-white shrink-0">
                  {agentFrame.progress}%
                </div>
              </div>
            </motion.div>
          );
        })}
      </div>

      <div className="mt-4 grid grid-cols-2 gap-2">
        {frame.beads.map((bead) => (
          <div
            key={`${scenarioId}-${bead.id}-${phaseIndex}`}
            className={cn(
              "rounded-[16px] border p-2.5",
              getBeadToneClasses(bead.tone),
            )}
          >
            <div className="flex items-center justify-between gap-2">
              <span className="font-mono text-[10px] sm:text-xs text-white/72">{bead.id}</span>
              {bead.tone === "contested" ? (
                <AlertTriangle className="h-3 w-3 sm:h-3.5 sm:w-3.5 text-[#FF5500]" />
              ) : bead.tone === "done" ? (
                <CheckCircle2 className="h-3 w-3 sm:h-3.5 sm:w-3.5 text-zinc-400" />
              ) : (
                <div className="h-1.5 w-1.5 rounded-full bg-white/35" />
              )}
            </div>
            <div className="mt-2 text-[9px] sm:text-[10px] uppercase tracking-[0.18em] text-white/35 truncate">
              {bead.owner ? `owner ${bead.owner}` : "frontier"}
            </div>
            <div className="mt-0.5 text-xs text-white/72 truncate">{bead.note}</div>
          </div>
        ))}
      </div>

      <div className="mt-4 rounded-[16px] border border-white/10 bg-black/25 px-4 py-2.5 text-xs sm:text-sm leading-relaxed text-white/75">
        {frame.verdict}
      </div>
    </div>
  );
}

export function SwarmExecutionViz() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;
  const [phaseIndex, setPhaseIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const timerRef = useRef<number | null>(null);

  const maxPhaseIndex = PHASES.length - 1;
  const comparisonPlaying = isPlaying && phaseIndex < maxPhaseIndex;
  const herdFrame = SCENARIOS.herd.frames[phaseIndex];
  const staggeredFrame = SCENARIOS.staggered.frames[phaseIndex];

  useEffect(() => {
    if (timerRef.current !== null) {
      window.clearTimeout(timerRef.current);
      timerRef.current = null;
    }

    if (!comparisonPlaying || !isInView || reducedMotion) return undefined;

    timerRef.current = window.setTimeout(() => {
      setPhaseIndex((current) => Math.min(current + 1, maxPhaseIndex));
    }, 2200);

    return () => {
      if (timerRef.current !== null) {
        window.clearTimeout(timerRef.current);
        timerRef.current = null;
      }
    };
  }, [comparisonPlaying, isInView, maxPhaseIndex, phaseIndex, reducedMotion]);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) {
        window.clearTimeout(timerRef.current);
      }
    };
  }, []);

  const handleReset = () => {
    setIsPlaying(false);
    setPhaseIndex(0);
  };

  return (
    <div ref={ref} className={EXHIBIT_PANEL_CLASS}>
      <div className="flex flex-col gap-4 border-b border-white/10 pb-5 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <div className="flex items-center gap-2 text-[0.65rem] font-semibold uppercase tracking-[0.28em] text-[#FFBD2E]/70">
            <Users className="h-3.5 w-3.5" />
            Interactive Exhibit
          </div>
          <h4 className="mt-2 text-xl font-black tracking-[-0.03em] text-white sm:text-2xl">
            The same swarm can either stampede or flow
          </h4>
          <p className="mt-2 max-w-2xl text-sm leading-relaxed text-white/60">
            Advance phase by phase and compare the exact same four agents under
            two launch strategies. The lesson is timing, not talent.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] p-1">
          <button
            type="button"
            aria-label={comparisonPlaying ? "Pause comparison" : "Play comparison"}
            onClick={() => {
              if (phaseIndex >= maxPhaseIndex) {
                setPhaseIndex(0);
                setIsPlaying(true);
                return;
              }
              setIsPlaying((current) => !current);
            }}
            className="flex min-h-[44px] items-center gap-2 rounded-full px-4 py-2 text-xs font-semibold text-white/78 transition-colors hover:bg-white/[0.08]"
          >
            {comparisonPlaying ? <Pause className="h-3.5 w-3.5" /> : <Play className="h-3.5 w-3.5" />}
            {comparisonPlaying ? "Pause" : "Play"}
          </button>
          <button
            type="button"
            aria-label="Previous phase"
            onClick={() => {
              setIsPlaying(false);
              setPhaseIndex((current) => Math.max(current - 1, 0));
            }}
            className="flex min-h-[44px] items-center justify-center rounded-full px-4 py-2 text-white/72 transition-colors hover:bg-white/[0.08]"
          >
            <ChevronRight className="h-4 w-4 rotate-180" />
          </button>
          <button
            type="button"
            aria-label="Next phase"
            onClick={() => {
              setIsPlaying(false);
              setPhaseIndex((current) => Math.min(current + 1, maxPhaseIndex));
            }}
            className="flex min-h-[44px] items-center justify-center rounded-full px-4 py-2 text-white/72 transition-colors hover:bg-white/[0.08]"
          >
            <ChevronRight className="h-4 w-4" />
          </button>
          <button
            type="button"
            aria-label="Reset comparison"
            onClick={handleReset}
            className="flex min-h-[44px] items-center gap-2 rounded-full px-4 py-2 text-xs font-semibold text-white/72 transition-colors hover:bg-white/[0.08]"
          >
            <RotateCcw className="h-3.5 w-3.5" />
            Reset
          </button>
        </div>
      </div>

      <div className="mt-5 grid gap-3 md:grid-cols-5">
        {PHASES.map((phase, index) => (
          <button
            key={phase.label}
            type="button"
            aria-pressed={phaseIndex === index}
            onClick={() => {
              setIsPlaying(false);
              setPhaseIndex(index);
            }}
            className={cn(
              "rounded-[22px] border px-4 py-3 text-left transition-colors",
              phaseIndex === index
                ? "border-white/18 bg-white/[0.09]"
                : "border-white/8 bg-white/[0.03] hover:border-white/14 hover:bg-white/[0.05]",
            )}
          >
            <div className="text-[0.65rem] font-semibold uppercase tracking-[0.22em] text-white/35">
              {index + 1}
            </div>
            <div className="mt-2 text-sm font-bold text-white">{phase.label}</div>
            <div className="mt-1 text-xs text-white/58">{phase.detail}</div>
          </button>
        ))}
      </div>

      <div className="mt-6 grid gap-6 xl:grid-cols-2">
        <ScenarioPanel scenarioId="herd" phaseIndex={phaseIndex} />
        <ScenarioPanel scenarioId="staggered" phaseIndex={phaseIndex} />
      </div>

      <AnimatePresence mode="wait">
        <motion.div
          key={`comparison-${phaseIndex}`}
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -10 }}
          className="mt-6 rounded-[28px] border border-white/10 bg-white/[0.02] p-5 shadow-inner"
        >
          <div className="text-[0.65rem] font-semibold uppercase tracking-[0.22em] text-[#FFBD2E]">
            Comparative takeaway
          </div>
          <p className="mt-3 text-sm leading-relaxed text-white/76">
            At this phase, the herd path has <strong>{herdFrame.metrics.conflicts}</strong> lock
            conflict{herdFrame.metrics.conflicts === 1 ? "" : "s"} and{" "}
            <strong>{herdFrame.metrics.idleBurn}</strong> units of idle burn,
            while the staggered path has <strong>{staggeredFrame.metrics.conflicts}</strong>{" "}
            conflicts and <strong>{staggeredFrame.metrics.idleBurn}</strong> idle burn. The
            difference is not smarter agents. It is whether the system lets them reach distinct
            frontier at distinct times.
          </p>
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
