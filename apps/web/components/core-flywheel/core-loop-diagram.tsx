"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  AnimatePresence,
  motion,
  useInView,
  useReducedMotion,
} from "framer-motion";
import {
  FileText,
  GitBranch,
  Compass,
  Mail,
  Code,
  CheckCircle,
  Terminal,
  Lightbulb,
  Package,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

/* ------------------------------------------------------------------ */
/*  Constants                                                         */
/* ------------------------------------------------------------------ */

const EXHIBIT_PANEL_CLASS =
  "my-16 overflow-hidden rounded-[1.5rem] sm:rounded-[2rem] lg:rounded-[3rem] border border-white/[0.03] bg-[#020408] p-5 sm:p-12 lg:p-16 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9)]";

const AUTO_TOUR_INTERVAL_MS = 3000;

type StageId =
  | "plan"
  | "encode"
  | "triage"
  | "coordinate"
  | "implement"
  | "close";

interface Stage {
  id: StageId;
  label: string;
  description: string;
  icon: LucideIcon;
  color: string;
  artifact: string;
  command: string;
  tip: string;
}

const STAGES: Stage[] = [
  {
    id: "plan",
    label: "Plan",
    description:
      "Create & refine markdown plan with multiple frontier models",
    icon: FileText,
    color: "#a78bfa",
    artifact: "Markdown Plan",
    command: "Ask 3+ frontier models, synthesize",
    tip: "Planning tokens are far cheaper than implementation tokens",
  },
  {
    id: "encode",
    label: "Encode",
    description: "Convert plan into beads with dependencies using br",
    icon: GitBranch,
    color: "#FF5500",
    artifact: "Bead Graph",
    command: "br create --title '...' --type task --priority 1",
    tip: "Beads are executable memory. Detailed enough that agents never consult the plan.",
  },
  {
    id: "triage",
    label: "Triage",
    description: "Let bv route agents to highest-leverage ready bead",
    icon: Compass,
    color: "#FFBD2E",
    artifact: "Ranked Recommendations",
    command: "bv --robot-triage",
    tip: "The graph does the routing work for you",
  },
  {
    id: "coordinate",
    label: "Coordinate",
    description: "Claim bead, reserve files, announce via Agent Mail",
    icon: Mail,
    color: "#FF5500",
    artifact: "Thread + Reservation",
    command: "send_message(..., thread_id='br-123')",
    tip: "Use the bead ID everywhere: thread, subject, reservation",
  },
  {
    id: "implement",
    label: "Implement",
    description: "Code, test, and review with fresh eyes",
    icon: Code,
    color: "#22c55e",
    artifact: "Code + Tests",
    command: "Fresh-eyes review after each bead",
    tip: "Force a mode switch from writing to adversarial reading",
  },
  {
    id: "close",
    label: "Close",
    description: "Close bead, update graph, ask bv what\u2019s next",
    icon: CheckCircle,
    color: "#FFBD2E",
    artifact: "Updated Graph",
    command: "br close 123 --reason 'Completed'",
    tip: "Each close reshapes the graph. bv sees a different map next time.",
  },
];

const STAGE_COUNT = STAGES.length;

/* ------------------------------------------------------------------ */
/*  Geometry helpers                                                   */
/* ------------------------------------------------------------------ */

/** Compute (x, y) for stage `index` on a circle of given radius, starting at top. */
function stagePosition(
  index: number,
  cx: number,
  cy: number,
  radius: number,
): { x: number; y: number } {
  const angle = (2 * Math.PI * index) / STAGE_COUNT - Math.PI / 2;
  return {
    x: cx + radius * Math.cos(angle),
    y: cy + radius * Math.sin(angle),
  };
}

/** Build a curved path between two points, bowing outward from center. */
function arcBetween(
  from: { x: number; y: number },
  to: { x: number; y: number },
  cx: number,
  cy: number,
): string {
  const midX = (from.x + to.x) / 2;
  const midY = (from.y + to.y) / 2;
  // Push the control point slightly outward from center
  const dx = midX - cx;
  const dy = midY - cy;
  const dist = Math.sqrt(dx * dx + dy * dy) || 1;
  const push = 18;
  const controlX = midX + (dx / dist) * push;
  const controlY = midY + (dy / dist) * push;
  return `M ${from.x} ${from.y} Q ${controlX} ${controlY} ${to.x} ${to.y}`;
}

/* ------------------------------------------------------------------ */
/*  Arrowhead marker (reused in SVG defs)                             */
/* ------------------------------------------------------------------ */

function SvgDefs() {
  return (
    <defs>
      <linearGradient id="clOrbitGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#FF5500" stopOpacity="1" />
        <stop offset="50%" stopColor="#FFBD2E" stopOpacity="1" />
        <stop offset="100%" stopColor="#a78bfa" stopOpacity="1" />
      </linearGradient>
      {/* Conic-style radial gradient for center depth */}
      <radialGradient id="clCenterGlow" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="#FF5500" stopOpacity="0.06" />
        <stop offset="40%" stopColor="#FFBD2E" stopOpacity="0.03" />
        <stop offset="70%" stopColor="#a78bfa" stopOpacity="0.015" />
        <stop offset="100%" stopColor="transparent" stopOpacity="0" />
      </radialGradient>
      {/* Per-stage radial glow for active icon background */}
      {STAGES.map((stage) => (
        <radialGradient
          key={`clIconGlow-${stage.id}`}
          id={`clIconGlow-${stage.id}`}
          cx="50%"
          cy="50%"
          r="50%"
        >
          <stop offset="0%" stopColor={stage.color} stopOpacity="0.25" />
          <stop offset="40%" stopColor={stage.color} stopOpacity="0.1" />
          <stop offset="70%" stopColor={stage.color} stopOpacity="0.03" />
          <stop offset="100%" stopColor={stage.color} stopOpacity="0" />
        </radialGradient>
      ))}
      <filter id="clNodeGlow">
        <feGaussianBlur stdDeviation="4" result="coloredBlur" />
        <feMerge>
          <feMergeNode in="coloredBlur" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
      <filter id="clPulseGlow">
        <feGaussianBlur stdDeviation="6" result="blur" />
        <feMerge>
          <feMergeNode in="blur" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
      {/* Dramatic glow/bloom filter for active connectors */}
      <filter id="clConnectorBloom" x="-40%" y="-40%" width="180%" height="180%">
        <feGaussianBlur in="SourceGraphic" stdDeviation="6" result="blur1" />
        <feGaussianBlur in="SourceGraphic" stdDeviation="2" result="blur2" />
        <feMerge>
          <feMergeNode in="blur1" />
          <feMergeNode in="blur2" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
      {/* Large outer glow filter for active stage node */}
      <filter id="clActiveNodeGlow" x="-100%" y="-100%" width="300%" height="300%">
        <feGaussianBlur stdDeviation="12" result="bigBlur" />
        <feMerge>
          <feMergeNode in="bigBlur" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
      {/* Glow filter for center label */}
      <filter id="clCenterLabelGlow" x="-50%" y="-50%" width="200%" height="200%">
        <feGaussianBlur in="SourceGraphic" stdDeviation="3" result="glow" />
        <feMerge>
          <feMergeNode in="glow" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
      {/* Arrow marker for connector ends */}
      <marker
        id="clArrow"
        viewBox="0 0 10 10"
        refX="8"
        refY="5"
        markerWidth="6"
        markerHeight="6"
        orient="auto-start-reverse"
      >
        <path d="M 0 2 L 8 5 L 0 8 z" fill="white" fillOpacity="0.15" />
      </marker>
      {STAGES.map((stage) => (
        <marker
          key={`clArrow-${stage.id}`}
          id={`clArrow-${stage.id}`}
          viewBox="0 0 10 10"
          refX="8"
          refY="5"
          markerWidth="6"
          markerHeight="6"
          orient="auto-start-reverse"
        >
          <path d="M 0 2 L 8 5 L 0 8 z" fill={stage.color} fillOpacity="0.8" />
        </marker>
      ))}
    </defs>
  );
}

/* ------------------------------------------------------------------ */
/*  StageNode: rendered inside SVG for each stage                      */
/* ------------------------------------------------------------------ */

function StageNode({
  stage,
  pos,
  isActive,
  onClick,
  reducedMotion,
}: {
  stage: Stage;
  pos: { x: number; y: number };
  isActive: boolean;
  onClick: () => void;
  reducedMotion: boolean;
}) {
  const Icon = stage.icon;
  const iconSize = 18;

  return (
    <motion.g
      onClick={onClick}
      className="cursor-pointer"
      role="button"
      aria-label={`Select stage: ${stage.label}`}
    >
      {/* Invisible hit-area */}
      <circle cx={pos.x} cy={pos.y} r="44" fill="transparent" />

      {/* Radial glow behind active icon */}
      {isActive && (
        <motion.circle
          cx={pos.x}
          cy={pos.y}
          r={40}
          fill={`url(#clIconGlow-${stage.id})`}
          initial={{ r: 20, opacity: 0 }}
          animate={{ r: 40, opacity: 1 }}
          transition={{ duration: 0.6, ease: "easeOut" }}
        />
      )}

      {/* Large ambient glow ring behind active node */}
      {isActive && (
        <motion.circle
          cx={pos.x}
          cy={pos.y}
          r={48}
          fill="none"
          stroke={stage.color}
          strokeOpacity={0.12}
          strokeWidth={1}
          filter="url(#clActiveNodeGlow)"
          initial={{ r: 28, opacity: 0 }}
          animate={{ r: 48, opacity: 1 }}
          transition={{ duration: 0.5, ease: "easeOut" }}
        />
      )}

      {/* Outer ring */}
      <motion.circle
        cx={pos.x}
        cy={pos.y}
        r={isActive ? 36 : 28}
        fill="none"
        stroke={stage.color}
        strokeOpacity={isActive ? 0.35 : 0.08}
        strokeWidth={isActive ? 2 : 1}
        initial={false}
        animate={{
          r: isActive ? 36 : 28,
          strokeOpacity: isActive ? 0.35 : 0.08,
        }}
        transition={{ type: "spring", stiffness: 200, damping: 25 }}
      />

      {/* Background circle */}
      <motion.circle
        cx={pos.x}
        cy={pos.y}
        r={isActive ? 28 : 22}
        fill={isActive ? stage.color : "#020408"}
        fillOpacity={isActive ? 0.15 : 1}
        stroke={stage.color}
        strokeOpacity={isActive ? 0.6 : 0.15}
        strokeWidth={isActive ? 2 : 1}
        initial={false}
        animate={{
          r: isActive ? 28 : 22,
          fillOpacity: isActive ? 0.15 : 1,
          strokeOpacity: isActive ? 0.6 : 0.15,
        }}
        transition={{ type: "spring", stiffness: 200, damping: 25 }}
      />

      {/* Pulse ring when active */}
      {isActive && !reducedMotion && (
        <motion.circle
          cx={pos.x}
          cy={pos.y}
          r={28}
          fill="none"
          stroke={stage.color}
          strokeWidth={1.5}
          initial={{ r: 28, opacity: 0.6 }}
          animate={{ r: 44, opacity: 0 }}
          transition={{ duration: 1.8, repeat: Infinity, ease: "easeOut" }}
        />
      )}

      {/* Icon (foreignObject for lucide) */}
      <foreignObject
        x={pos.x - iconSize / 2}
        y={pos.y - iconSize / 2}
        width={iconSize}
        height={iconSize}
        className="pointer-events-none"
      >
        <Icon
          size={iconSize}
          strokeWidth={isActive ? 2.5 : 2}
          color={isActive ? stage.color : "rgba(255,255,255,0.45)"}
          style={{ transition: "color 0.3s" }}
        />
      </foreignObject>

      {/* Label */}
      <text
        x={pos.x}
        y={pos.y + (isActive ? 50 : 40)}
        textAnchor="middle"
        className={`text-[11px] font-black uppercase tracking-[0.15em] transition-all duration-300 ${
          isActive ? "fill-white" : "fill-white/30"
        }`}
      >
        {stage.label}
      </text>
    </motion.g>
  );
}

/* ------------------------------------------------------------------ */
/*  Detail card                                                       */
/* ------------------------------------------------------------------ */

function DetailCard({ stage }: { stage: Stage }) {
  return (
    <motion.div
      key={stage.id}
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
      className="relative flex flex-col gap-6"
      style={{ paddingLeft: 24 }}
    >
      {/* Animated left border that draws downward */}
      <motion.div
        className="absolute left-0 top-0 w-[3px] rounded-full"
        style={{ backgroundColor: stage.color }}
        initial={{ height: "0%" }}
        animate={{ height: "100%" }}
        transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1], delay: 0.1 }}
      />
      {/* Header */}
      <div className="flex flex-col gap-3">
        <div
          className="text-[0.65rem] font-bold uppercase tracking-widest flex items-center gap-2"
          style={{ color: stage.color }}
        >
          <span
            className="w-1.5 h-1.5 rounded-full"
            style={{ backgroundColor: stage.color }}
          />
          Stage Detail
        </div>
        <h5 className="text-3xl sm:text-4xl font-black text-white tracking-tight leading-none drop-shadow-md">
          {stage.label}
        </h5>
        <p className="mt-1 text-[1.05rem] leading-relaxed text-zinc-400 font-light">
          {stage.description}
        </p>
      </div>

      {/* Info grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        {/* Artifact */}
        <div className="flex flex-col gap-2 p-5 rounded-2xl bg-white/[0.03] border border-white/[0.05] shadow-sm relative overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-br from-white/[0.015] to-transparent pointer-events-none" />
          <span className="text-[0.6rem] font-bold text-white/30 uppercase tracking-widest flex items-center gap-2">
            <Package size={10} className="opacity-50" />
            Artifact
          </span>
          <p className="text-sm sm:text-base text-white/90 font-medium">
            {stage.artifact}
          </p>
        </div>

        {/* Command */}
        <div className="flex flex-col gap-2 p-5 rounded-2xl bg-white/[0.02] border border-white/[0.04] shadow-sm relative overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />
          <span className="text-[0.6rem] font-bold text-white/30 uppercase tracking-widest flex items-center gap-2">
            <Terminal size={10} className="opacity-50" />
            Command
          </span>
          <p className="text-sm text-white/90 font-mono font-medium break-all">
            {stage.command}
          </p>
        </div>
      </div>

      {/* Tip */}
      <div className="flex items-start gap-3 p-5 rounded-2xl bg-white/[0.015] border border-white/[0.04] relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-white/[0.005] to-transparent pointer-events-none" />
        <Lightbulb
          size={16}
          className="mt-0.5 shrink-0"
          style={{ color: stage.color }}
        />
        <p className="text-sm leading-relaxed text-zinc-400 font-light">
          {stage.tip}
        </p>
      </div>
    </motion.div>
  );
}

/* ------------------------------------------------------------------ */
/*  Mobile stage list (replaces SVG on small screens)                  */
/* ------------------------------------------------------------------ */

function MobileStageList({
  activeIndex,
  onSelect,
  reducedMotion,
}: {
  activeIndex: number;
  onSelect: (index: number) => void;
  reducedMotion: boolean;
}) {
  return (
    <div className="relative flex flex-col gap-3">
      {/* Connecting vertical line between cards */}
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

        return (
          <motion.button
            key={stage.id}
            type="button"
            onClick={() => onSelect(index)}
            className={`relative flex items-center gap-4 px-5 py-4 rounded-2xl border transition-all duration-300 text-left ${
              isActive
                ? "border-white/[0.08] bg-white/[0.04]"
                : "border-white/[0.03] bg-white/[0.01] hover:bg-white/[0.03]"
            }`}
            style={{
              borderLeftWidth: isActive ? 3 : 1,
              borderLeftColor: isActive ? stage.color : undefined,
              boxShadow: isActive
                ? `0 4px 24px -4px ${stage.color}30, 0 0 0 1px ${stage.color}15`
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
            <div
              className={`relative z-10 flex items-center justify-center w-10 h-10 rounded-xl transition-all duration-300 ${
                isActive ? "shadow-lg" : ""
              }`}
              style={{
                backgroundColor: isActive
                  ? `${stage.color}15`
                  : "rgba(255,255,255,0.02)",
                borderWidth: 1,
                borderStyle: "solid",
                borderColor: isActive
                  ? `${stage.color}40`
                  : "rgba(255,255,255,0.04)",
              }}
            >
              <Icon
                size={18}
                color={isActive ? stage.color : "rgba(255,255,255,0.3)"}
              />
            </div>

            <div className="flex flex-col gap-0.5 min-w-0">
              <span
                className={`text-xs font-black uppercase tracking-widest transition-colors duration-300 ${
                  isActive ? "text-white" : "text-white/40"
                }`}
              >
                {stage.label}
              </span>
              <span
                className={`text-[0.7rem] text-white/25 ${
                  isActive ? "" : "truncate"
                }`}
              >
                {stage.description}
              </span>
            </div>

            {/* Step indicator */}
            <span
              className="ml-auto text-[0.6rem] font-mono font-bold shrink-0"
              style={{ color: isActive ? stage.color : "rgba(255,255,255,0.15)" }}
            >
              {index + 1}/{STAGE_COUNT}
            </span>
          </motion.button>
        );
      })}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Pulsing dot that travels along the circle path                     */
/* ------------------------------------------------------------------ */

/** Particle trail specs: each one is smaller and more transparent, with a staggered delay. */
const TRAIL_PARTICLES = [
  { radius: 3.5, opacity: 0.5, delay: 0.08 },
  { radius: 2.5, opacity: 0.3, delay: 0.18 },
  { radius: 1.8, opacity: 0.15, delay: 0.3 },
];

function TravelingDot({
  cx,
  cy,
  radius,
  activeIndex,
  reducedMotion,
}: {
  cx: number;
  cy: number;
  radius: number;
  activeIndex: number;
  reducedMotion: boolean;
}) {
  const pos = stagePosition(activeIndex, cx, cy, radius);

  if (reducedMotion) {
    return (
      <circle cx={pos.x} cy={pos.y} r={4} fill="#FF5500" fillOpacity={0.8} />
    );
  }

  return (
    <g>
      {/* Particle trail -- smaller, more transparent circles that lag behind */}
      {TRAIL_PARTICLES.map((particle, i) => (
        <motion.circle
          key={`trail-${i}`}
          cx={pos.x}
          cy={pos.y}
          r={particle.radius}
          fill="#FF5500"
          fillOpacity={particle.opacity}
          initial={false}
          animate={{ cx: pos.x, cy: pos.y }}
          transition={{
            cx: {
              duration: 0.6,
              delay: particle.delay,
              ease: [0.16, 1, 0.3, 1],
            },
            cy: {
              duration: 0.6,
              delay: particle.delay,
              ease: [0.16, 1, 0.3, 1],
            },
          }}
        />
      ))}

      {/* Main traveling dot */}
      <motion.circle
        cx={pos.x}
        cy={pos.y}
        r={5}
        fill="#FF5500"
        filter="url(#clPulseGlow)"
        initial={false}
        animate={{
          cx: pos.x,
          cy: pos.y,
          scale: [1, 1.6, 1],
        }}
        transition={{
          cx: { duration: 0.6, ease: [0.16, 1, 0.3, 1] },
          cy: { duration: 0.6, ease: [0.16, 1, 0.3, 1] },
          scale: { duration: 1.6, repeat: Infinity, ease: "easeInOut" },
        }}
      />
    </g>
  );
}

/* ------------------------------------------------------------------ */
/*  Main component                                                     */
/* ------------------------------------------------------------------ */

export function CoreLoopDiagram() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const rm = prefersReducedMotion ?? false;

  const [activeIndex, setActiveIndex] = useState(0);
  const [autoTour, setAutoTour] = useState(false);

  const currentStage = STAGES[activeIndex];

  /* Auto-tour timer */
  useEffect(() => {
    if (!isInView || rm || !autoTour) return undefined;

    const id = window.setInterval(() => {
      setActiveIndex((cur) => (cur + 1) % STAGE_COUNT);
    }, AUTO_TOUR_INTERVAL_MS);

    return () => window.clearInterval(id);
  }, [autoTour, isInView, rm]);

  /* Keyboard navigation */
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "ArrowRight") {
        e.preventDefault();
        setActiveIndex((cur) => (cur + 1) % STAGE_COUNT);
        setAutoTour(false);
      } else if (e.key === "ArrowLeft") {
        e.preventDefault();
        setActiveIndex((cur) => (cur - 1 + STAGE_COUNT) % STAGE_COUNT);
        setAutoTour(false);
      } else if (e.key === " ") {
        e.preventDefault();
        setAutoTour((cur) => !cur);
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  const handleStageSelect = useCallback(
    (index: number) => {
      setActiveIndex(index);
      setAutoTour(false);
    },
    [],
  );

  /* SVG layout constants */
  const svgCx = 200;
  const svgCy = 200;
  const svgRadius = 140;
  const viewBox = "0 0 400 400";

  return (
    <div ref={ref} className={EXHIBIT_PANEL_CLASS + " relative group/viz"}>
      {/* Background texture & ambient glow */}
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.02] mix-blend-overlay pointer-events-none" />
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[900px] h-[900px] bg-[radial-gradient(ellipse_at_center,rgba(255,85,0,0.02),transparent_60%)] pointer-events-none" />

      {/* Header */}
      <div className="relative z-10 border-b border-white/[0.04] pb-10 flex flex-col gap-6 sm:flex-row sm:items-start sm:justify-between">
        <div className="max-w-xl">
          <div className="text-[0.65rem] font-bold uppercase tracking-widest text-[#FF5500]/80 flex items-center gap-3 mb-4">
            <span className="w-1.5 h-1.5 rounded-full bg-[#FF5500] animate-pulse shadow-[0_0_8px_rgba(255,85,0,0.8)]" />
            Core Loop
          </div>
          <h4 className="text-3xl font-black tracking-tight text-white sm:text-4xl leading-[1.15] drop-shadow-lg">
            Six stages, one loop, compounding leverage
          </h4>
          <p className="mt-4 text-[1.05rem] leading-relaxed text-zinc-400 font-light">
            Each closed bead reshapes the graph. The next agent gets a
            better map. Click any stage to see the details.
          </p>
        </div>

        {/* Auto-tour toggle */}
        <button
          type="button"
          onClick={() => setAutoTour((cur) => !cur)}
          className={`group shrink-0 flex items-center gap-3 px-5 py-2.5 rounded-xl border transition-all duration-500 ease-out hover:scale-[1.02] active:scale-[0.98] ${
            autoTour
              ? "border-[#FF5500]/30 bg-[#FF5500]/10 text-[#FF5500] shadow-[inset_0_1px_1px_rgba(255,255,255,0.05)] hover:border-[#FF5500]/50 hover:bg-[#FF5500]/15"
              : "border-white/10 bg-white/[0.02] text-white/40 hover:bg-white/[0.05] hover:border-white/15 hover:text-white/60"
          }`}
        >
          <div
            className={`w-2 h-2 rounded-full ${
              autoTour
                ? "bg-[#FF5500] shadow-[0_0_8px_rgba(255,85,0,0.8)] animate-pulse"
                : "bg-white/20"
            }`}
          />
          <span className="text-[0.65rem] font-bold uppercase tracking-widest">
            {autoTour ? "Auto-Tour Active" : "Tour Paused"}
          </span>
        </button>
      </div>

      {/* Body grid */}
      <div className="relative z-10 mt-12 grid gap-12 lg:grid-cols-[1fr_1fr] items-start">
        {/* ---- SVG diagram (hidden on mobile, shown md+) ---- */}
        <div className="hidden md:flex items-center justify-center">
          <div className="relative w-full max-w-[480px] aspect-square">
            <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(255,85,0,0.025),transparent_60%)]" />
            <svg
              viewBox={viewBox}
              className="relative z-10 w-full h-full"
              aria-label="Core loop diagram with six stages arranged in a circle"
            >
              <SvgDefs />

              {/* Outer orbit ring */}
              <circle
                cx={svgCx}
                cy={svgCy}
                r={svgRadius + 18}
                fill="none"
                stroke="white"
                strokeOpacity="0.03"
                strokeWidth="1"
              />

              {/* Main orbit ring with rotating dash animation */}
              <circle
                cx={svgCx}
                cy={svgCy}
                r={svgRadius}
                fill="none"
                stroke="url(#clOrbitGrad)"
                strokeOpacity="0.06"
                strokeWidth="1.5"
                strokeDasharray="4 6"
              >
                {!rm && (
                  <animateTransform
                    attributeName="transform"
                    type="rotate"
                    from={`0 ${svgCx} ${svgCy}`}
                    to={`360 ${svgCx} ${svgCy}`}
                    dur="60s"
                    repeatCount="indefinite"
                  />
                )}
              </circle>

              {/* Center depth gradient */}
              <circle
                cx={svgCx}
                cy={svgCy}
                r={60}
                fill="url(#clCenterGlow)"
              />

              {/* Connector paths between stages */}
              {STAGES.map((stage, index) => {
                const from = stagePosition(index, svgCx, svgCy, svgRadius);
                const to = stagePosition(
                  (index + 1) % STAGE_COUNT,
                  svgCx,
                  svgCy,
                  svgRadius,
                );
                const isActive = index === activeIndex;
                const path = arcBetween(from, to, svgCx, svgCy);
                const connId = `clConn-${stage.id}`;

                return (
                  <g key={`conn-group-${stage.id}`}>
                    {/* Hidden path used for animateMotion reference */}
                    <path id={connId} d={path} fill="none" stroke="none" />

                    <motion.path
                      key={`conn-${stage.id}`}
                      d={path}
                      fill="none"
                      stroke={isActive ? stage.color : "white"}
                      strokeWidth={isActive ? 2.5 : 1}
                      markerEnd={
                        isActive
                          ? `url(#clArrow-${stage.id})`
                          : "url(#clArrow)"
                      }
                      initial={false}
                      animate={{
                        strokeDasharray: isActive
                          ? ["0, 600", "600, 0"]
                          : "4, 12",
                        strokeOpacity: isActive ? 0.9 : 0.06,
                      }}
                      transition={{ duration: 1.2, ease: "easeInOut" }}
                      filter={isActive ? "url(#clConnectorBloom)" : undefined}
                    />

                    {/* Flowing direction dots on active connector */}
                    {isActive &&
                      !rm &&
                      [0, 1, 2].map((dotIdx) => (
                        <circle
                          key={`flow-${stage.id}-${dotIdx}`}
                          r={1.5}
                          fill={stage.color}
                          opacity={0.6 - dotIdx * 0.15}
                        >
                          <animateMotion
                            dur="2s"
                            repeatCount="indefinite"
                            begin={`${dotIdx * 0.6}s`}
                          >
                            <mpath xlinkHref={`#${connId}`} />
                          </animateMotion>
                        </circle>
                      ))}
                  </g>
                );
              })}

              {/* Traveling pulse dot */}
              <TravelingDot
                cx={svgCx}
                cy={svgCy}
                radius={svgRadius}
                activeIndex={activeIndex}
                reducedMotion={rm}
              />

              {/* Stage nodes */}
              {STAGES.map((stage, index) => {
                const pos = stagePosition(index, svgCx, svgCy, svgRadius);
                return (
                  <StageNode
                    key={stage.id}
                    stage={stage}
                    pos={pos}
                    isActive={index === activeIndex}
                    onClick={() => handleStageSelect(index)}
                    reducedMotion={rm}
                  />
                );
              })}

              {/* Center label with glow */}
              <text
                x={svgCx}
                y={svgCy + 4}
                textAnchor="middle"
                className="text-[13px] font-black uppercase tracking-[0.25em]"
                fill="#FF5500"
                fillOpacity={0.25}
                filter="url(#clCenterLabelGlow)"
              >
                Core Loop
              </text>
            </svg>
          </div>
        </div>

        {/* ---- Mobile stage list (shown only below md) ---- */}
        <div className="md:hidden">
          <MobileStageList
            activeIndex={activeIndex}
            onSelect={handleStageSelect}
            reducedMotion={rm}
          />
        </div>

        {/* ---- Detail panel (always visible) ---- */}
        <div className="flex flex-col gap-8">
          <AnimatePresence mode="wait">
            <DetailCard stage={currentStage} />
          </AnimatePresence>

          {/* Stage indicator dots */}
          <div className="flex items-center gap-2 pt-6 border-t border-white/[0.04]">
            <span className="text-[0.6rem] font-bold uppercase tracking-[0.3em] text-white/20 mr-2">
              Stage
            </span>
            {STAGES.map((stage, index) => (
              <button
                key={stage.id}
                type="button"
                onClick={() => handleStageSelect(index)}
                aria-label={`Go to stage: ${stage.label}`}
                title={`${index + 1}. ${stage.label}`}
                className="p-1 group/dot"
              >
                <motion.div
                  className="rounded-full transition-all duration-300"
                  style={{
                    width: index === activeIndex ? 20 : 8,
                    height: 8,
                    backgroundColor:
                      index === activeIndex
                        ? stage.color
                        : "rgba(255,255,255,0.1)",
                    boxShadow:
                      index === activeIndex
                        ? `0 0 10px ${stage.color}60`
                        : "none",
                  }}
                  layout
                  transition={{ type: "spring", stiffness: 200, damping: 25 }}
                />
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
