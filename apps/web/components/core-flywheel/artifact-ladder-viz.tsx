"use client";

import {
  CheckCircle,
  ChevronRight,
  FileText,
  GitBranch,
  Lightbulb,
  Pause,
  Play,
  User,
  Zap,
} from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "@/components/motion";
import { cn, isInteractiveKeyboardTarget } from "@/lib/utils";

/* ------------------------------------------------------------------ */
/*  Constants                                                         */
/* ------------------------------------------------------------------ */

const EXHIBIT_PANEL_CLASS =
  "my-16 overflow-clip rounded-[1.5rem] sm:rounded-[2rem] lg:rounded-[3rem] border border-white/[0.03] bg-[#020408] p-5 sm:p-12 lg:p-16 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9)]";

type StageId =
  | "raw-idea"
  | "markdown-plan"
  | "bead-graph"
  | "ready-bead"
  | "claimed-bead"
  | "completed-bead";

interface Stage {
  id: StageId;
  label: string;
  icon: React.ElementType;
  artifact: string;
  meaning: string;
  nextAction: string;
  color: string;
  glowColor: string;
}

const STAGES: readonly Stage[] = [
  {
    id: "raw-idea",
    label: "Raw Idea",
    icon: Lightbulb,
    artifact: "A rough description",
    meaning: "You know the goal but have not designed the system yet.",
    nextAction: "Turn it into a serious markdown plan.",
    color: "#FFFFFF",
    glowColor: "rgba(255,255,255,0.15)",
  },
  {
    id: "markdown-plan",
    label: "Markdown Plan",
    icon: FileText,
    artifact: "Design document",
    meaning: "Workflows, constraints, and architecture are visible.",
    nextAction: "Convert it into beads.",
    color: "#e4e4e7",
    glowColor: "rgba(228,228,231,0.15)",
  },
  {
    id: "bead-graph",
    label: "Bead Graph",
    icon: GitBranch,
    artifact: "Encoded executable work",
    meaning: "Dependencies and boundaries are explicit.",
    nextAction: "Polish it 8-10 times, then ask bv what matters next.",
    color: "#FF5500",
    glowColor: "rgba(255,85,0,0.2)",
  },
  {
    id: "ready-bead",
    label: "Ready Bead",
    icon: Zap,
    artifact: "Unblocked bead",
    meaning: "All its dependencies are closed, so it can start now.",
    nextAction: "Claim it in br and reserve its files in Agent Mail.",
    color: "#FFBD2E",
    glowColor: "rgba(255,189,46,0.2)",
  },
  {
    id: "claimed-bead",
    label: "Claimed Bead",
    icon: User,
    artifact: "In-progress bead with an owner",
    meaning: "The swarm can see who owns it.",
    nextAction: "Implement, test, and post progress in its thread.",
    color: "#a78bfa",
    glowColor: "rgba(167,139,250,0.2)",
  },
  {
    id: "completed-bead",
    label: "Completed Bead",
    icon: CheckCircle,
    artifact: "Closed bead",
    meaning: "The graph has changed; beads that waited on it may now be ready.",
    nextAction: "Ask bv for the next best ready bead.",
    color: "#22c55e",
    glowColor: "rgba(34,197,94,0.2)",
  },
] as const;

const AUTO_PLAY_INTERVAL = 2400;

/* ------------------------------------------------------------------ */
/*  Sub-components                                                    */
/* ------------------------------------------------------------------ */

function StageNode({
  stage,
  index,
  isActive,
  isPast,
  onSelect,
  isInView,
  reducedMotion,
}: {
  stage: Stage;
  index: number;
  isActive: boolean;
  isPast: boolean;
  onSelect: () => void;
  isInView: boolean;
  reducedMotion: boolean;
}) {
  const Icon = stage.icon;

  return (
    <motion.button
      type="button"
      onClick={onSelect}
      // Reduced motion reveals at once; `initial` stays fixed so the
      // server-rendered hidden state is always animated away.
      initial={{ opacity: 0, y: 24 }}
      animate={isInView || reducedMotion ? { opacity: 1, y: 0 } : undefined}
      transition={{
        type: "spring",
        stiffness: 180,
        damping: 22,
        delay: reducedMotion ? 0 : index * 0.1,
      }}
      aria-pressed={isActive}
      className={cn(
        "group/node relative flex items-center gap-4 rounded-2xl border p-4 text-left transition duration-500 w-full min-h-[56px] hover:scale-[1.02] focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-[#FF5500]/50",
        isActive
          ? "border-white/[0.1] bg-white/[0.03] shadow-[0_0_30px_var(--node-glow)]"
          : isPast
            ? "border-white/[0.07] bg-white/[0.015]"
            : "border-white/[0.06] bg-white/[0.01] hover:border-white/[0.1] hover:bg-white/[0.025]",
      )}
      style={
        {
          "--node-glow": stage.glowColor,
        } as React.CSSProperties
      }
    >
      {/* Icon circle */}
      <div className="relative shrink-0">
        <motion.div
          className={cn(
            "flex h-11 w-11 items-center justify-center rounded-xl border transition duration-500",
            isActive ? "border-transparent" : "border-white/[0.1] bg-white/[0.03]",
          )}
          style={{
            backgroundColor: isActive ? `${stage.color}18` : undefined,
            borderColor: isActive ? `${stage.color}30` : undefined,
          }}
          animate={isActive && !reducedMotion ? { scale: [1, 1.08, 1] } : { scale: 1 }}
          // Repeat only while pulsing: an infinite settle-to-1 animation
          // restarts from mid-pulse every 2s after the stage moves on.
          transition={
            isActive && !reducedMotion
              ? { duration: 2, repeat: Infinity, ease: "easeInOut" }
              : { duration: 0.3, ease: "easeOut" }
          }
        >
          <Icon
            className="h-5 w-5 transition-colors duration-500"
            aria-hidden="true"
            style={{
              color: isActive
                ? stage.color
                : isPast
                  ? `${stage.color}b3`
                  : "rgba(255,255,255,0.55)",
            }}
          />
        </motion.div>

        {/* Active ping ring */}
        {isActive && !reducedMotion && (
          <motion.div
            className="absolute inset-0 rounded-xl border"
            style={{ borderColor: `${stage.color}40` }}
            animate={{ scale: [1, 1.5], opacity: [0.6, 0] }}
            transition={{ duration: 1.8, repeat: Infinity, ease: "easeOut" }}
          />
        )}
      </div>

      {/* Label */}
      <div className="flex flex-col gap-0.5 min-w-0">
        <span
          className="text-xs font-black uppercase tracking-[0.2em]"
          style={{
            // Inactive rows stay readable: past stages keep a tint of their
            // color, mixed toward zinc-400 rather than made translucent (70%
            // alpha put the orange "Stage 3" at 3.5:1); upcoming ones use
            // zinc-400.
            color: isActive
              ? stage.color
              : isPast
                ? `color-mix(in srgb, ${stage.color} 60%, #a1a1aa)`
                : "#a1a1aa",
            transition: "color 700ms cubic-bezier(0.4, 0, 0.2, 1)",
          }}
        >
          Stage {index + 1}
        </span>
        <span
          className={cn(
            "text-sm font-bold tracking-tight transition-colors duration-500 truncate",
            isActive ? "text-white" : "text-zinc-300",
          )}
        >
          {stage.label}
        </span>
      </div>

      {/* Arrow indicator */}
      <ChevronRight
        aria-hidden="true"
        className={cn(
          "ml-auto h-4 w-4 shrink-0 transition duration-500",
          isActive
            ? "text-white/60 translate-x-0 opacity-100"
            : "text-white/40 -translate-x-1 opacity-0 group-hover/node:translate-x-0 group-hover/node:opacity-100",
        )}
      />
    </motion.button>
  );
}

function ConnectorLine({
  index,
  isActive,
  isPast,
  fromColor,
  toColor,
  reducedMotion,
}: {
  index: number;
  isActive: boolean;
  isPast: boolean;
  fromColor: string;
  toColor: string;
  reducedMotion: boolean;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-1">
      <motion.div
        className="relative h-8 w-px overflow-hidden"
        initial={reducedMotion ? false : { opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: reducedMotion ? 0 : index * 0.1 + 0.15 }}
      >
        <div
          className="absolute inset-0 transition duration-700"
          style={{
            background:
              isActive || isPast
                ? `linear-gradient(to bottom, ${fromColor}80, ${toColor}80)`
                : "rgba(255,255,255,0.14)",
          }}
        />
        {isActive && !reducedMotion && (
          <motion.div
            className="absolute left-0 right-0 h-3"
            style={{
              background: `linear-gradient(to bottom, transparent, ${toColor}, transparent)`,
            }}
            animate={{ top: ["-12px", "32px"] }}
            transition={{
              duration: 1.2,
              repeat: Infinity,
              ease: "easeInOut",
            }}
          />
        )}
      </motion.div>

      {/* Animated chevron on active connector (mobile / small screens) */}
      {isActive && !reducedMotion && (
        <motion.div
          className="lg:hidden flex items-center justify-center -mt-1"
          animate={{ opacity: [0.3, 0.9, 0.3], y: [0, 3, 0] }}
          transition={{ duration: 1.6, repeat: Infinity, ease: "easeInOut" }}
        >
          <svg
            width="12"
            height="8"
            viewBox="0 0 12 8"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              d="M1 1L6 6L11 1"
              stroke={toColor}
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </motion.div>
      )}
    </div>
  );
}

function DetailPanel({ stage, reducedMotion }: { stage: Stage; reducedMotion: boolean }) {
  return (
    <motion.div
      key={stage.id}
      initial={reducedMotion ? false : { opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={reducedMotion ? undefined : { opacity: 0, y: -20 }}
      transition={{ duration: 0.45, ease: [0.16, 1, 0.3, 1] }}
      className="flex h-full flex-col gap-8"
    >
      {/* Header */}
      <div>
        <div
          className="text-xs font-bold uppercase tracking-widest flex items-center gap-2 mb-4"
          style={{ color: stage.color }}
        >
          <span className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: stage.color }} />
          Active Stage
        </div>
        <h4 className="font-serif text-[2.25rem] font-normal leading-none tracking-[-0.01em] text-white sm:text-[2.75rem]">
          {stage.label}
        </h4>
      </div>

      {/* Detail cards */}
      <div className="flex flex-col gap-4">
        {[
          {
            label: "Main Artifact",
            value: stage.artifact,
            accent: stage.color,
          },
          {
            label: "What It Means",
            value: stage.meaning,
            accent: "#a1a1aa",
          },
          {
            label: "What You Do Next",
            value: stage.nextAction,
            accent: "#FFBD2E",
          },
        ].map((card, cardIndex) => (
          <motion.div
            key={card.label}
            initial={reducedMotion ? false : { opacity: 0, x: 12 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{
              duration: 0.4,
              ease: [0.16, 1, 0.3, 1],
              delay: reducedMotion ? 0 : cardIndex * 0.08,
            }}
            className="rounded-2xl border border-white/[0.04] bg-white/[0.01] p-5 relative overflow-hidden group/card"
            style={{ borderLeftWidth: "2px", borderLeftColor: `${stage.color}40` }}
          >
            <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />
            <div className="relative z-10">
              <span
                className="text-xs font-black uppercase tracking-[0.3em] block mb-2"
                style={{ color: card.accent }}
              >
                {card.label}
              </span>
              <p className="text-[1rem] leading-relaxed text-zinc-300 font-light">{card.value}</p>
            </div>
          </motion.div>
        ))}
      </div>

      {/* Progression indicator */}
      <div className="mt-auto rounded-2xl border border-white/[0.04] bg-white/[0.01] p-5">
        <span className="text-xs font-black uppercase tracking-[0.3em] text-zinc-400 block mb-4">
          Progression
        </span>
        <div className="flex gap-1.5">
          {STAGES.map((s, i) => {
            const isCurrent = s.id === stage.id;
            const isPast = STAGES.findIndex((x) => x.id === stage.id) > i;
            return (
              <motion.div
                key={s.id}
                className="h-2 rounded-full origin-center"
                animate={{
                  flex: isCurrent ? 1.6 : 1,
                  opacity: isCurrent && !reducedMotion ? [1, 0.6, 1] : 1,
                }}
                transition={
                  isCurrent && !reducedMotion
                    ? {
                        flex: {
                          type: "spring",
                          stiffness: 300,
                          damping: 20,
                        },
                        opacity: {
                          duration: 1.5,
                          repeat: Infinity,
                          ease: "easeInOut",
                        },
                      }
                    : {
                        flex: {
                          type: "spring",
                          stiffness: 300,
                          damping: 20,
                        },
                      }
                }
                style={{
                  backgroundColor: isCurrent
                    ? s.color
                    : isPast
                      ? `${s.color}60`
                      : "rgba(255,255,255,0.12)",
                  boxShadow: isCurrent ? `0 0 12px ${s.glowColor}` : "none",
                }}
              />
            );
          })}
        </div>
      </div>
    </motion.div>
  );
}

/* ------------------------------------------------------------------ */
/*  Main export                                                       */
/* ------------------------------------------------------------------ */

export function ArtifactLadderViz() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;

  const [activeIndex, setActiveIndex] = useState(0);
  const [autoPlay, setAutoPlay] = useState(false);

  const handleSelect = useCallback((index: number) => {
    setActiveIndex(index);
    setAutoPlay(false);
  }, []);

  const toggleAutoPlay = useCallback(() => {
    setAutoPlay((prev) => !prev);
  }, []);

  /* Keyboard navigation — only when this viz is in the viewport. Left/Right
     only, like the other exhibits: Up/Down and Space scroll the page. */
  useEffect(() => {
    if (!isInView) return;
    function handleKeyDown(e: KeyboardEvent) {
      if (e.defaultPrevented || e.isComposing || e.ctrlKey || e.metaKey || e.altKey
        || isInteractiveKeyboardTarget(e.target)) return;
      const bounds = ref.current?.getBoundingClientRect();
      if (!bounds || bounds.bottom <= 0 || bounds.top >= window.innerHeight) return;
      if (e.key === "ArrowRight") {
        e.preventDefault();
        setActiveIndex((cur) => (cur + 1) % STAGES.length);
        setAutoPlay(false);
      } else if (e.key === "ArrowLeft") {
        e.preventDefault();
        setActiveIndex((cur) => (cur - 1 + STAGES.length) % STAGES.length);
        setAutoPlay(false);
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isInView]);

  /* Auto-play timer */
  useEffect(() => {
    if (!autoPlay || !isInView || reducedMotion) return undefined;

    const id = window.setInterval(() => {
      setActiveIndex((prev) => (prev + 1) % STAGES.length);
    }, AUTO_PLAY_INTERVAL);

    return () => window.clearInterval(id);
  }, [autoPlay, isInView, reducedMotion]);

  const activeStage = STAGES[activeIndex];

  return (
    <div ref={ref} className={EXHIBIT_PANEL_CLASS + " relative"}>
      {/* Noise texture */}
      <div className="absolute inset-0 noise-overlay opacity-[0.02] mix-blend-overlay pointer-events-none" />

      {/* Ambient glow */}
      <div className="absolute top-0 right-0 w-[min(600px,100%)] h-[600px] bg-[radial-gradient(ellipse_at_top_right,rgba(167,139,250,0.03),transparent_60%)] pointer-events-none" />
      <div className="absolute bottom-0 left-0 w-[min(400px,100%)] h-[400px] bg-[radial-gradient(ellipse_at_bottom_left,rgba(34,197,94,0.02),transparent_60%)] pointer-events-none" />

      {/* Header */}
      <div className="relative z-10 flex flex-col gap-8 border-b border-white/[0.03] pb-12 lg:flex-row lg:items-start lg:justify-between">
        <div className="max-w-2xl">
          {/* Full-strength orange like the other exhibit eyebrows: at
              opacity-60 it was 2.8:1. */}
          <div className="text-xs font-black uppercase tracking-[0.4em] text-[#FF5500] flex items-center gap-3">
            <div className="w-8 h-px bg-[#FF5500]/30" />
            Artifact Progression
          </div>
          <h3 className="mt-6 font-serif text-[1.5rem] font-normal leading-[1.12] tracking-[-0.008em] text-white sm:text-[1.875rem]">
            What you produce at each stage
          </h3>
          <p className="mt-8 text-[1.1rem] leading-relaxed text-zinc-400 font-extralight">
            An idea becomes a plan, the plan becomes beads, and the beads become finished code.
            Click any stage to see the artifact, what it means, and your next move.
          </p>
        </div>

        {/* Not offered with Reduce Motion, where auto-play never runs; the
            stage rows step through by hand. The whole wrapper goes, or an
            empty item would still add the header's gap on phones. The name
            stays "Auto-Play" and aria-pressed carries the state; the visible
            "On" is aria-hidden. */}
        {!reducedMotion && (
          <div className="flex shrink-0 flex-col items-start lg:items-end gap-4">
            <button
              type="button"
              onClick={toggleAutoPlay}
              aria-pressed={autoPlay}
              className={cn(
                "group flex items-center gap-3 whitespace-nowrap px-6 py-3 rounded-2xl border transition duration-500 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-[#FF5500]/50",
                autoPlay
                  ? "border-[#FF5500]/30 bg-[#FF5500]/10 text-[#FF5500] shadow-[inset_0_1px_1px_rgba(255,255,255,0.05)]"
                  : "border-white/10 bg-white/[0.02] text-zinc-400 hover:bg-white/[0.04] hover:text-zinc-200",
              )}
            >
              <div
                className={cn(
                  "w-2 h-2 rounded-full transition duration-500",
                  autoPlay
                    ? "bg-[#FF5500] shadow-[0_0_8px_rgba(255,85,0,0.8)] animate-pulse"
                    : "bg-white/20",
                )}
              />
              {autoPlay ? (
                <Pause className="h-3.5 w-3.5" aria-hidden="true" />
              ) : (
                <Play className="h-3.5 w-3.5" aria-hidden="true" />
              )}
              <span className="text-xs font-black uppercase tracking-[0.2em]">
                Auto-Play{autoPlay && <span aria-hidden="true"> On</span>}
              </span>
            </button>
          </div>
        )}
      </div>

      {/* Main content: ladder + detail panel */}
      <div className="relative z-10 mt-16 grid gap-12 lg:grid-cols-[0.9fr_1.1fr] items-start">
        {/* Left: Ladder */}
        {/* The connectors between rows carry the progress colors at every
            width (a stretched desktop-only SVG rail used to run through the
            icons with its dots off the row centers). */}
        <div className="relative flex flex-col">
          <div className="flex flex-col">
            {STAGES.map((stage, index) => {
              const isActive = index === activeIndex;
              const isPast = index < activeIndex;

              return (
                <div key={stage.id}>
                  <StageNode
                    stage={stage}
                    index={index}
                    isActive={isActive}
                    isPast={isPast}
                    onSelect={() => handleSelect(index)}
                    isInView={isInView}
                    reducedMotion={reducedMotion}
                  />
                  {index < STAGES.length - 1 && (
                    <ConnectorLine
                      index={index}
                      isActive={isActive}
                      isPast={isPast}
                      fromColor={stage.color}
                      toColor={STAGES[index + 1].color}
                      reducedMotion={reducedMotion}
                    />
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* Spotlight effect on desktop: light cone from active stage toward detail panel */}
        <motion.div
          className="pointer-events-none absolute hidden lg:block"
          style={{
            width: "300px",
            height: "200px",
            left: "calc(45% - 150px)",
            zIndex: 0,
          }}
          animate={{
            top: `${(activeIndex / (STAGES.length - 1)) * 60 + 10}%`,
            // closest-side fades to transparent before every edge of the box;
            // centered on the top edge it left a hard horizontal line.
            background: `radial-gradient(closest-side, ${activeStage.color}12, ${activeStage.color}06 50%, transparent)`,
          }}
          transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
        />

        {/* Right: Detail panel */}
        <div className="sticky top-8 rounded-[2.5rem] border border-white/[0.03] bg-white/[0.02] backdrop-blur-sm p-8 shadow-inner relative overflow-hidden min-h-[400px] lg:min-h-[500px]">
          {/* Colored top border that transitions with active stage */}
          <motion.div
            className="absolute top-0 left-0 right-0 h-[3px] pointer-events-none"
            animate={{
              background: `linear-gradient(to right, ${activeStage.color}00, ${activeStage.color}, ${activeStage.color}00)`,
            }}
            transition={{ duration: 0.8 }}
          />

          {/* Mobile accent bar (visible below lg) */}
          <motion.div
            className="absolute top-0 left-0 right-0 h-[2px] pointer-events-none lg:hidden"
            animate={{
              background: `linear-gradient(to right, ${activeStage.color}, #FFBD2E, ${activeStage.color})`,
            }}
            transition={{ duration: 0.8 }}
          />

          {/* Glow accent for active stage */}
          <motion.div
            className="absolute top-0 right-0 w-48 h-48 blur-[60px] pointer-events-none opacity-20"
            animate={{ backgroundColor: activeStage.color }}
            transition={{ duration: 0.8 }}
          />

          <AnimatePresence mode="wait">
            <DetailPanel key={activeStage.id} stage={activeStage} reducedMotion={reducedMotion} />
          </AnimatePresence>
        </div>
      </div>

      {/* Bottom summary strip */}
      <motion.div
        className="relative z-10 mt-16 grid gap-4 sm:grid-cols-3"
        initial={{ opacity: 0, y: 16 }}
        animate={isInView || reducedMotion ? { opacity: 1, y: 0 } : undefined}
        transition={{
          type: "spring",
          stiffness: 120,
          damping: 20,
          delay: reducedMotion ? 0 : 0.6,
        }}
      >
        <div className="rounded-2xl border border-white/[0.04] bg-white/[0.01] p-5 group hover:-translate-y-1 transition-transform duration-500 relative overflow-hidden">
          {/* White gradient top border */}
          <div className="absolute top-0 left-0 right-0 h-[2px] bg-gradient-to-r from-white/0 via-white/40 to-white/0 pointer-events-none" />
          <div className="text-xs font-black uppercase tracking-[0.3em] text-zinc-400 group-hover:text-zinc-300 transition-colors">
            Total Stages
          </div>
          <div className="mt-3 text-4xl font-black tracking-tighter text-white">
            {STAGES.length}
          </div>
          <p className="mt-2 text-sm leading-relaxed text-zinc-400 font-extralight">
            Raw idea to finished code. Each stage adds precision.
          </p>
        </div>

        <div className="rounded-2xl border border-white/[0.04] bg-white/[0.01] p-5 group hover:-translate-y-1 transition-transform duration-500 relative overflow-hidden">
          {/* Orange gradient top border */}
          <div className="absolute top-0 left-0 right-0 h-[2px] bg-gradient-to-r from-[#FF5500]/0 via-[#FF5500] to-[#FFBD2E]/0 pointer-events-none" />
          <div className="text-xs font-black uppercase tracking-[0.3em] text-zinc-400 group-hover:text-zinc-300 transition-colors">
            Key Transition
          </div>
          <div className="mt-3 text-4xl font-black tracking-tighter bg-gradient-to-r from-[#FF5500] to-[#FFBD2E] bg-clip-text text-transparent">
            Plan to Bead
          </div>
          <p className="mt-2 text-sm leading-relaxed text-zinc-400 font-extralight">
            The prose plan becomes beads specific enough that agents no longer have to guess.
          </p>
        </div>

        <div className="rounded-2xl border border-[#22c55e]/20 bg-[#22c55e]/5 p-5 group relative overflow-hidden hover:-translate-y-1 transition-transform duration-500">
          {/* Green gradient top border */}
          <div className="absolute top-0 left-0 right-0 h-[2px] bg-gradient-to-r from-[#22c55e]/0 via-[#22c55e]/60 to-[#22c55e]/0 pointer-events-none" />
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(34,197,94,0.1),transparent_50%)] pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity duration-500" />
          <div className="relative z-10 flex items-center gap-2 text-xs font-black uppercase tracking-[0.3em] text-[#22c55e]">
            <CheckCircle className="h-3.5 w-3.5" />
            What Closing Does
          </div>
          <p className="relative z-10 mt-3 text-sm leading-relaxed text-zinc-300 font-medium">
            Closing a bead can make the beads that waited on it ready, so finished work opens up
            new work.
          </p>
        </div>
      </motion.div>
    </div>
  );
}
