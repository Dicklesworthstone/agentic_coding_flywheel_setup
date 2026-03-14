"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "framer-motion";
import {
  Lightbulb,
  FileText,
  GitBranch,
  Zap,
  User,
  CheckCircle,
  Play,
  Pause,
  ChevronRight,
} from "lucide-react";
import { cn } from "@/lib/utils";

/* ------------------------------------------------------------------ */
/*  Constants                                                         */
/* ------------------------------------------------------------------ */

const EXHIBIT_PANEL_CLASS =
  "my-16 overflow-hidden rounded-[1.5rem] sm:rounded-[2rem] lg:rounded-[3rem] border border-white/[0.03] bg-[#020408] p-5 sm:p-12 lg:p-16 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9)]";

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
    meaning: "You know the goal, not the system.",
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
    nextAction: "Ask bv what matters next.",
    color: "#FF5500",
    glowColor: "rgba(255,85,0,0.2)",
  },
  {
    id: "ready-bead",
    label: "Ready Bead",
    icon: Zap,
    artifact: "Unblocked bead",
    meaning: "Can be started now.",
    nextAction: "Claim it and reserve surface.",
    color: "#FFBD2E",
    glowColor: "rgba(255,189,46,0.2)",
  },
  {
    id: "claimed-bead",
    label: "Claimed Bead",
    icon: User,
    artifact: "Agent working on it",
    meaning: "The swarm can see who owns it.",
    nextAction: "Implement, test, update progress.",
    color: "#a78bfa",
    glowColor: "rgba(167,139,250,0.2)",
  },
  {
    id: "completed-bead",
    label: "Completed Bead",
    icon: CheckCircle,
    artifact: "Finished work",
    meaning: "The graph has changed.",
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
      initial={reducedMotion ? false : { opacity: 0, y: 24 }}
      animate={isInView ? { opacity: 1, y: 0 } : undefined}
      transition={{
        type: "spring",
        stiffness: 180,
        damping: 22,
        delay: reducedMotion ? 0 : index * 0.1,
      }}
      className={cn(
        "group/node relative flex items-center gap-4 rounded-2xl border p-4 text-left transition-all duration-500 w-full min-h-[56px] hover:scale-[1.02]",
        isActive
          ? "border-white/[0.08] bg-white/[0.03] shadow-[0_0_30px_var(--node-glow)]"
          : isPast
            ? "border-white/[0.04] bg-white/[0.01]"
            : "border-white/[0.03] bg-white/[0.005] hover:border-white/[0.06] hover:bg-white/[0.02]",
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
            "flex h-11 w-11 items-center justify-center rounded-xl border transition-all duration-500",
            isActive
              ? "border-transparent"
              : "border-white/[0.06] bg-white/[0.02]",
          )}
          style={{
            backgroundColor: isActive ? `${stage.color}18` : undefined,
            borderColor: isActive ? `${stage.color}30` : undefined,
          }}
          animate={
            isActive && !reducedMotion
              ? { scale: [1, 1.08, 1] }
              : { scale: 1 }
          }
          transition={{
            duration: 2,
            repeat: Infinity,
            ease: "easeInOut",
          }}
        >
          <Icon
            className="h-5 w-5 transition-colors duration-500"
            style={{ color: isActive ? stage.color : isPast ? `${stage.color}99` : "rgba(255,255,255,0.25)" }}
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
          className="text-[0.6rem] font-black uppercase tracking-[0.2em]"
          style={{
            color: isActive
              ? stage.color
              : isPast
                ? `${stage.color}80`
                : "rgba(255,255,255,0.2)",
            transition: "color 700ms cubic-bezier(0.4, 0, 0.2, 1)",
          }}
        >
          Stage {index + 1}
        </span>
        <span
          className={cn(
            "text-sm font-bold tracking-tight transition-colors duration-500 truncate",
            isActive ? "text-white" : isPast ? "text-white/60" : "text-white/30",
          )}
        >
          {stage.label}
        </span>
      </div>

      {/* Arrow indicator */}
      <ChevronRight
        className={cn(
          "ml-auto h-4 w-4 shrink-0 transition-all duration-500",
          isActive
            ? "text-white/60 translate-x-0 opacity-100"
            : "text-white/10 -translate-x-1 opacity-0 group-hover/node:translate-x-0 group-hover/node:opacity-100",
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
          className="absolute inset-0 transition-all duration-700"
          style={{
            background:
              isActive || isPast
                ? `linear-gradient(to bottom, ${fromColor}80, ${toColor}80)`
                : "rgba(255,255,255,0.08)",
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

function DetailPanel({
  stage,
  reducedMotion,
}: {
  stage: Stage;
  reducedMotion: boolean;
}) {
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
          className="text-[0.65rem] font-bold uppercase tracking-widest flex items-center gap-2 mb-4"
          style={{ color: stage.color }}
        >
          <span
            className="w-1.5 h-1.5 rounded-full"
            style={{ backgroundColor: stage.color }}
          />
          Active Stage
        </div>
        <h5 className="text-3xl font-black tracking-tight text-white sm:text-4xl leading-none">
          {stage.label}
        </h5>
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
            accent: "rgba(255,255,255,0.4)",
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
                className="text-[0.6rem] font-black uppercase tracking-[0.3em] block mb-2"
                style={{ color: card.accent }}
              >
                {card.label}
              </span>
              <p className="text-[1rem] leading-relaxed text-zinc-300 font-light">
                {card.value}
              </p>
            </div>
          </motion.div>
        ))}
      </div>

      {/* Progression indicator */}
      <div className="mt-auto rounded-2xl border border-white/[0.04] bg-white/[0.01] p-5">
        <span className="text-[0.6rem] font-black uppercase tracking-[0.3em] text-white/20 block mb-4">
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
                      : "rgba(255,255,255,0.06)",
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
/*  Diagonal SVG connector for desktop                                */
/* ------------------------------------------------------------------ */

function DiagonalTrail({
  activeIndex,
  reducedMotion,
}: {
  activeIndex: number;
  reducedMotion: boolean;
}) {
  const nodeCount = STAGES.length;
  const height = nodeCount * 80;

  return (
    <svg
      viewBox={`0 0 40 ${height}`}
      className="absolute left-5 top-0 h-full w-10 pointer-events-none hidden lg:block"
      preserveAspectRatio="none"
    >
      <defs>
        <linearGradient id="trailGradient" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.3" />
          <stop offset="40%" stopColor="#FF5500" stopOpacity="0.5" />
          <stop offset="100%" stopColor="#22c55e" stopOpacity="0.3" />
        </linearGradient>
      </defs>

      {/* Background trail */}
      <line
        x1="20"
        y1="0"
        x2="20"
        y2={height}
        stroke="rgba(255,255,255,0.04)"
        strokeWidth="2"
      />

      {/* Active trail */}
      <motion.line
        x1="20"
        y1="0"
        x2="20"
        y2={height}
        stroke="url(#trailGradient)"
        strokeWidth="2"
        strokeLinecap="round"
        initial={{ pathLength: 0 }}
        animate={{
          pathLength: (activeIndex + 1) / nodeCount,
        }}
        transition={
          reducedMotion
            ? { duration: 0 }
            : { duration: 0.8, ease: [0.16, 1, 0.3, 1] }
        }
      />

      {/* Dot markers at each node position */}
      {STAGES.map((s, i) => {
        const cy = (i / (nodeCount - 1)) * height;
        const isAtOrBefore = i <= activeIndex;
        return (
          <circle
            key={s.id}
            cx="20"
            cy={cy}
            r={i === activeIndex ? 4 : 3}
            fill={isAtOrBefore ? s.color : "rgba(255,255,255,0.1)"}
            opacity={isAtOrBefore ? 0.9 : 0.4}
          />
        );
      })}
    </svg>
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

  const handleSelect = useCallback(
    (index: number) => {
      setActiveIndex(index);
      setAutoPlay(false);
    },
    [],
  );

  const toggleAutoPlay = useCallback(() => {
    setAutoPlay((prev) => !prev);
  }, []);

  /* Keyboard navigation */
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "ArrowRight" || e.key === "ArrowDown") {
        e.preventDefault();
        setActiveIndex((cur) => (cur + 1) % STAGES.length);
        setAutoPlay(false);
      } else if (e.key === "ArrowLeft" || e.key === "ArrowUp") {
        e.preventDefault();
        setActiveIndex((cur) => (cur - 1 + STAGES.length) % STAGES.length);
        setAutoPlay(false);
      } else if (e.key === " ") {
        e.preventDefault();
        setAutoPlay((cur) => !cur);
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

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
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.02] mix-blend-overlay pointer-events-none" />

      {/* Ambient glow */}
      <div className="absolute top-0 right-0 w-[600px] h-[600px] bg-[radial-gradient(ellipse_at_top_right,rgba(167,139,250,0.03),transparent_60%)] pointer-events-none" />
      <div className="absolute bottom-0 left-0 w-[400px] h-[400px] bg-[radial-gradient(ellipse_at_bottom_left,rgba(34,197,94,0.02),transparent_60%)] pointer-events-none" />

      {/* Header */}
      <div className="relative z-10 flex flex-col gap-8 border-b border-white/[0.03] pb-12 lg:flex-row lg:items-start lg:justify-between">
        <div className="max-w-2xl">
          <div className="text-[0.65rem] font-black uppercase tracking-[0.4em] text-[#FF5500] opacity-60 flex items-center gap-3">
            <div className="w-8 h-px bg-[#FF5500]/30" />
            Artifact Progression
          </div>
          <h4 className="mt-6 text-3xl font-black tracking-[-0.04em] text-white sm:text-4xl lg:text-5xl leading-[1.1]">
            How artifacts transform through the core loop
          </h4>
          <p className="mt-8 text-[1.1rem] leading-relaxed text-zinc-400 font-extralight">
            An idea becomes a plan, a plan becomes beads, beads become
            finished code. Click any stage to see the artifact, what it
            means, and your next move.
          </p>
        </div>

        <div className="flex flex-col items-start lg:items-end gap-4">
          <button
            type="button"
            onClick={toggleAutoPlay}
            className={cn(
              "group flex items-center gap-3 px-6 py-3 rounded-2xl border transition-all duration-500",
              autoPlay
                ? "border-[#FF5500]/30 bg-[#FF5500]/10 text-[#FF5500] shadow-[inset_0_1px_1px_rgba(255,255,255,0.05)]"
                : "border-white/10 bg-white/[0.02] text-white/40 hover:bg-white/[0.04] hover:text-white/60",
            )}
          >
            <div
              className={cn(
                "w-2 h-2 rounded-full transition-all duration-500",
                autoPlay
                  ? "bg-[#FF5500] shadow-[0_0_8px_rgba(255,85,0,0.8)] animate-pulse"
                  : "bg-white/20",
              )}
            />
            {autoPlay ? (
              <Pause className="h-3.5 w-3.5" />
            ) : (
              <Play className="h-3.5 w-3.5" />
            )}
            <span className="text-[0.65rem] font-black uppercase tracking-[0.2em]">
              {autoPlay ? "Auto-Play Active" : "Auto-Play"}
            </span>
          </button>
        </div>
      </div>

      {/* Main content: ladder + detail panel */}
      <div className="relative z-10 mt-16 grid gap-12 lg:grid-cols-[0.9fr_1.1fr] items-start">
        {/* Left: Ladder */}
        <div className="relative flex flex-col">
          <DiagonalTrail
            activeIndex={activeIndex}
            reducedMotion={reducedMotion}
          />

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
            background: `radial-gradient(ellipse at 50% 0%, ${activeStage.color}12, ${activeStage.color}06 40%, transparent 70%)`,
          }}
          transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
        />

        {/* Right: Detail panel */}
        <div className="sticky top-8 rounded-[2.5rem] border border-white/[0.03] bg-white/[0.02] backdrop-blur-sm p-8 shadow-inner relative overflow-hidden min-h-[400px] lg:min-h-[500px]">
          {/* Colored top border that transitions with active stage */}
          <motion.div
            className="absolute top-0 left-0 right-0 h-[3px] pointer-events-none"
            animate={{ background: `linear-gradient(to right, ${activeStage.color}00, ${activeStage.color}, ${activeStage.color}00)` }}
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
            <DetailPanel
              key={activeStage.id}
              stage={activeStage}
              reducedMotion={reducedMotion}
            />
          </AnimatePresence>
        </div>
      </div>

      {/* Bottom summary strip */}
      <motion.div
        className="relative z-10 mt-16 grid gap-4 sm:grid-cols-3"
        initial={reducedMotion ? false : { opacity: 0, y: 16 }}
        animate={isInView ? { opacity: 1, y: 0 } : undefined}
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
          <div className="text-[0.6rem] font-black uppercase tracking-[0.3em] text-white/20 group-hover:text-white/40 transition-colors">
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
          <div className="text-[0.6rem] font-black uppercase tracking-[0.3em] text-white/20 group-hover:text-white/40 transition-colors">
            Key Transition
          </div>
          <div className="mt-3 text-4xl font-black tracking-tighter bg-gradient-to-r from-[#FF5500] to-[#FFBD2E] bg-clip-text text-transparent">
            Plan to Bead
          </div>
          <p className="mt-2 text-sm leading-relaxed text-zinc-400 font-extralight">
            Prose becomes executable memory. This is where agents stop
            guessing.
          </p>
        </div>

        <div className="rounded-2xl border border-[#22c55e]/20 bg-[#22c55e]/5 p-5 group relative overflow-hidden hover:-translate-y-1 transition-transform duration-500">
          {/* Green gradient top border */}
          <div className="absolute top-0 left-0 right-0 h-[2px] bg-gradient-to-r from-[#22c55e]/0 via-[#22c55e]/60 to-[#22c55e]/0 pointer-events-none" />
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(34,197,94,0.1),transparent_50%)] pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity duration-500" />
          <div className="relative z-10 flex items-center gap-2 text-[0.6rem] font-black uppercase tracking-[0.3em] text-[#22c55e]">
            <CheckCircle className="h-3.5 w-3.5" />
            The Insight
          </div>
          <p className="relative z-10 mt-3 text-sm leading-relaxed text-zinc-300 font-medium">
            Each completed bead reshapes the graph and unblocks new work.
            Finished beads create ready beads.
          </p>
        </div>
      </motion.div>
    </div>
  );
}
