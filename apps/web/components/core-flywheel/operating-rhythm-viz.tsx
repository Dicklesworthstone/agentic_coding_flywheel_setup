"use client";

import type { LucideIcon } from "lucide-react";
import { CheckCircle, Code, Compass, FileText, GitBranch, Mail, RotateCcw } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "@/components/motion";
import { cn, isInteractiveKeyboardTarget } from "@/lib/utils";

/* ------------------------------------------------------------------ */
/*  Constants                                                         */
/* ------------------------------------------------------------------ */

const EXHIBIT_PANEL_CLASS =
  "my-16 overflow-hidden rounded-[1.5rem] sm:rounded-[2rem] lg:rounded-[3rem] border border-white/[0.03] bg-[#020408] p-5 sm:p-12 lg:p-16 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9)]";

const AUTO_PLAY_INTERVAL_MS = 4000;

/* ------------------------------------------------------------------ */
/*  Step data                                                         */
/* ------------------------------------------------------------------ */

interface Step {
  id: string;
  label: string;
  icon: LucideIcon;
  /** Second icon for the "Execute & Close" step */
  iconAlt?: LucideIcon;
  color: string;
  action: string;
  output: string;
  timing: string;
  /** Whether this step is part of the repeating loop (steps 3-5) */
  inLoop: boolean;
}

const STEPS: Step[] = [
  {
    id: "plan",
    label: "Plan",
    icon: FileText,
    color: "#a78bfa",
    action: "A lead planner writes the plan, other model families write competing ones, and the lead merges them",
    output: "A markdown plan covering workflows, constraints, architecture, and tests",
    timing: "Hours, not minutes",
    inLoop: false,
  },
  {
    id: "encode",
    label: "Encode",
    icon: GitBranch,
    color: "#FF5500",
    action: "Have an agent convert the plan into beads with br, then polish them 8-10 times",
    output: "A dependency graph of self-contained beads (dozens to hundreds)",
    timing: "Hours, including polish",
    inLoop: false,
  },
  {
    id: "route",
    label: "Route",
    icon: Compass,
    color: "#FFBD2E",
    action: "Run bv --robot-triage to find the most useful ready bead",
    output: "Ranked recommendations with scores and unblock counts",
    timing: "Seconds",
    inLoop: true,
  },
  {
    id: "coordinate",
    label: "Coordinate",
    icon: Mail,
    color: "#FF5500",
    action: "Claim the bead in br, reserve files and announce it in Agent Mail",
    output: "Claim, thread, and file reservations visible to all agents",
    timing: "A few tool calls",
    inLoop: true,
  },
  {
    id: "execute",
    label: "Execute & Close",
    icon: Code,
    iconAlt: CheckCircle,
    color: "#22c55e",
    action: "Implement, test, fresh-eyes review, close the bead, repeat from step 3",
    output: "Working code + tests, an updated graph, the next bead ready",
    timing: "Minutes to hours per bead",
    inLoop: true,
  },
];

const STEP_COUNT = STEPS.length;

/* ------------------------------------------------------------------ */
/*  StepNode: a single circle on the timeline                         */
/* ------------------------------------------------------------------ */

function StepNode({
  step,
  index,
  isActive,
  onClick,
  reducedMotion,
}: {
  step: Step;
  index: number;
  isActive: boolean;
  onClick: () => void;
  reducedMotion: boolean;
}) {
  const Icon = step.icon;
  const IconAlt = step.iconAlt;

  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={isActive}
      className="group relative flex flex-col items-center gap-2 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-[#FF5500]/50 rounded-xl"
    >
      {/* Glow ring behind active node */}
      {isActive && (
        <motion.div
          layoutId="step-glow"
          className="absolute -inset-3 rounded-full"
          style={{
            background: `radial-gradient(circle, ${step.color}20, transparent 70%)`,
            boxShadow: `0 0 24px ${step.color}40`,
          }}
          transition={{ type: "spring", stiffness: 300, damping: 28 }}
        />
      )}

      {/* Circle node */}
      <motion.div
        className={cn(
          "relative z-10 flex h-12 w-12 items-center justify-center rounded-full border-2 transition-colors duration-300",
          isActive
            ? "bg-[#05070b]"
            : "bg-[#05070b] border-white/[0.14] group-hover:border-white/[0.28]",
        )}
        style={{
          borderColor: isActive ? step.color : undefined,
        }}
        animate={isActive && !reducedMotion ? { scale: [1, 1.08, 1] } : { scale: 1 }}
        transition={
          isActive && !reducedMotion
            ? { duration: 2, repeat: Infinity, ease: "easeInOut" }
            : { duration: 0.2 }
        }
      >
        <div className="flex select-none items-center gap-0.5" aria-hidden="true">
          <Icon
            // Two icons share the "Execute & Close" circle, so each is smaller there.
            className={cn("transition-colors duration-300", IconAlt ? "h-4 w-4" : "h-5 w-5")}
            style={{ color: isActive ? step.color : "rgba(255,255,255,0.55)" }}
          />
          {IconAlt && (
            <>
              <span
                className="text-[10px] font-bold transition-colors duration-300"
                style={{
                  color: isActive ? step.color : "rgba(255,255,255,0.4)",
                }}
              >
                /
              </span>
              <IconAlt
                className="h-3.5 w-3.5 transition-colors duration-300"
                style={{
                  color: isActive ? step.color : "rgba(255,255,255,0.55)",
                }}
              />
            </>
          )}
        </div>
      </motion.div>

      {/* Step number + label */}
      <div className="relative z-10 flex flex-col items-center">
        <span
          className="text-xs font-bold uppercase tracking-widest transition-colors duration-300"
          style={{
            // Inactive text at 60% white clears 4.5:1 on this near-black.
            color: isActive ? step.color : "rgba(255,255,255,0.6)",
          }}
        >
          <span className="sr-only">Step </span>
          {index + 1}
        </span>
        <span
          className="text-xs font-bold tracking-wide transition-colors duration-300 whitespace-nowrap"
          style={{
            color: isActive ? "rgba(255,255,255,0.95)" : "#d4d4d8",
          }}
        >
          {step.label}
        </span>
      </div>
    </button>
  );
}

/* ------------------------------------------------------------------ */
/*  DetailCard: action / output / timing for the active step          */
/* ------------------------------------------------------------------ */

function DetailCard({
  step,
  index,
  reducedMotion,
}: {
  step: Step;
  index: number;
  reducedMotion: boolean;
}) {
  return (
    <motion.div
      key={step.id}
      initial={reducedMotion ? false : { opacity: 0, y: 16, scale: 0.97 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={reducedMotion ? undefined : { opacity: 0, y: -12, scale: 0.97 }}
      transition={{ type: "spring", stiffness: 300, damping: 28 }}
      className="rounded-2xl border p-5 sm:p-6 relative overflow-hidden"
      style={{
        borderColor: `${step.color}20`,
        background: `${step.color}08`,
      }}
    >
      {/* Subtle corner glow */}
      <div
        className="absolute top-0 right-0 w-40 h-40 blur-[60px] opacity-15 pointer-events-none"
        style={{ background: step.color }}
      />

      {/* Step badge */}
      <div className="relative z-10 flex items-center gap-2 mb-4">
        <span
          className="flex h-7 w-7 items-center justify-center rounded-lg border text-xs font-bold"
          style={{
            borderColor: `${step.color}30`,
            background: `${step.color}15`,
            color: step.color,
          }}
        >
          {index + 1}
        </span>
        <span className="text-sm font-bold tracking-tight" style={{ color: step.color }}>
          {step.label}
        </span>
      </div>

      {/* Content grid */}
      <div className="relative z-10 grid gap-4 sm:grid-cols-3">
        {/* Action */}
        <div className="space-y-1.5">
          <div className="text-xs font-bold uppercase tracking-widest text-zinc-400">
            Action
          </div>
          <p className="text-sm leading-relaxed text-zinc-300 font-light">{step.action}</p>
        </div>

        {/* Output */}
        <div className="space-y-1.5">
          <div className="text-xs font-bold uppercase tracking-widest text-zinc-400">
            Output
          </div>
          <p className="text-sm leading-relaxed text-zinc-300 font-light">{step.output}</p>
        </div>

        {/* Timing */}
        <div className="space-y-1.5">
          <div className="text-xs font-bold uppercase tracking-widest text-zinc-400">
            Timing
          </div>
          <div className="flex items-center gap-2">
            <span
              className="inline-flex rounded-full px-2.5 py-0.5 text-xs font-bold border"
              style={{
                borderColor: `${step.color}30`,
                background: `${step.color}10`,
                color: step.color,
              }}
            >
              {step.timing}
            </span>
          </div>
        </div>
      </div>
    </motion.div>
  );
}

/* ------------------------------------------------------------------ */
/*  Connector line between two step nodes                             */
/* ------------------------------------------------------------------ */

/** Desktop geometry: five equal columns, nodes centered in each, and the
 *  node row starts `NODE_ROW_TOP_PX` below the top of the loop bracket so the
 *  bracket's label has room above the nodes. */
const NODE_ROW_TOP_PX = 44;
const NODE_SIZE_PX = 48;
const COLUMN_PCT = 100 / STEP_COUNT;

function Connector({
  fromIndex,
  activeIndex,
  reducedMotion,
  vertical,
}: {
  fromIndex: number;
  activeIndex: number;
  reducedMotion: boolean;
  vertical: boolean;
}) {
  const isCrossing = activeIndex === fromIndex || activeIndex === fromIndex + 1;

  return (
    <div
      aria-hidden="true"
      className={cn(vertical ? "relative h-8 w-0.5" : "absolute h-0.5")}
      style={
        vertical
          ? // Under the node column: button p-2 + half of the 40px node.
            { marginLeft: 27 }
          : {
              // From just right of this node's circle to just left of the next one.
              top: NODE_ROW_TOP_PX + NODE_SIZE_PX / 2 - 1,
              left: `calc(${(fromIndex + 0.5) * COLUMN_PCT}% + ${NODE_SIZE_PX / 2 + 8}px)`,
              width: `calc(${COLUMN_PCT}% - ${NODE_SIZE_PX + 16}px)`,
            }
      }
    >
      <motion.div
        className="absolute inset-0 rounded-full"
        style={{
          background: isCrossing
            ? `linear-gradient(${vertical ? "to bottom" : "to right"}, ${STEPS[fromIndex].color}90, ${STEPS[fromIndex + 1].color}90)`
            : "rgba(255,255,255,0.12)",
        }}
        animate={isCrossing && !reducedMotion ? { opacity: [0.5, 1, 0.5] } : { opacity: 1 }}
        transition={
          isCrossing && !reducedMotion ? { duration: 1.5, repeat: Infinity, ease: "easeInOut" } : {}
        }
      />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  LoopArrow: curved arrow from step 5 back to step 3               */
/* ------------------------------------------------------------------ */

function LoopArrow({
  activeIndex,
  reducedMotion,
  vertical,
}: {
  activeIndex: number;
  reducedMotion: boolean;
  vertical: boolean;
}) {
  const isHighlighted = activeIndex >= 2; // highlight when any loop step is active
  const color = isHighlighted ? "#FFBD2E" : "#a1a1aa"; // amber when live, zinc-400 at rest
  const pulse = isHighlighted && !reducedMotion;

  const label = (
    <span className="flex items-center gap-2">
      <RotateCcw className="h-3.5 w-3.5 shrink-0" style={{ color }} aria-hidden="true" />
      <span className="text-xs font-bold uppercase tracking-widest" style={{ color }}>
        Repeat from Route
      </span>
    </span>
  );

  if (vertical) {
    return (
      <motion.div
        className="flex items-center justify-center py-2"
        animate={pulse ? { opacity: [0.7, 1, 0.7] } : { opacity: 1 }}
        transition={pulse ? { duration: 2, repeat: Infinity, ease: "easeInOut" } : {}}
      >
        {label}
      </motion.div>
    );
  }

  /* Desktop: a dashed return path that drops from step 5, runs back under
     step 4, and rises into step 3 (column centers at 50% and 90%). */
  const left = `${2.5 * COLUMN_PCT}%`;
  const right = `${0.5 * COLUMN_PCT}%`;
  return (
    <motion.div
      className="relative h-14"
      aria-hidden="true"
      animate={pulse ? { opacity: [0.7, 1, 0.7] } : { opacity: 1 }}
      transition={pulse ? { duration: 2, repeat: Infinity, ease: "easeInOut" } : {}}
    >
      <div
        className="absolute top-1 h-5 rounded-b-2xl border-x-[1.5px] border-b-[1.5px] border-dashed transition-colors duration-300"
        style={{ left, right, borderColor: isHighlighted ? "#FFBD2E99" : "rgba(161,161,170,0.45)" }}
      />
      {/* Arrowhead pointing up into step 3 */}
      <svg
        className="absolute -top-1 -translate-x-1/2"
        style={{ left }}
        width="12"
        height="8"
        viewBox="0 0 12 8"
        fill="none"
      >
        <path
          d="M1 7L6 2L11 7"
          stroke={isHighlighted ? "#FFBD2E" : "rgba(161,161,170,0.7)"}
          strokeWidth="1.5"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
      <div
        className="absolute top-8 -translate-x-1/2 whitespace-nowrap"
        style={{ left: `${3.5 * COLUMN_PCT}%` }}
      >
        {label}
      </div>
    </motion.div>
  );
}

/* ------------------------------------------------------------------ */
/*  Main component                                                    */
/* ------------------------------------------------------------------ */

export function OperatingRhythmViz() {
  const [activeIndex, setActiveIndex] = useState(0);
  const [autoPlay, setAutoPlay] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const isInView = useInView(containerRef, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;

  /* Auto-play timer */
  const handleSelect = useCallback((index: number) => {
    setActiveIndex(index);
    setAutoPlay(false);
  }, []);

  /* Keyboard navigation — only when this viz is in the viewport. Left/Right
     only: Space and Up/Down scroll the page. */
  useEffect(() => {
    if (!isInView) return;
    function handleKeyDown(e: KeyboardEvent) {
      if (e.defaultPrevented || e.isComposing || e.ctrlKey || e.metaKey || e.altKey
        || isInteractiveKeyboardTarget(e.target)) return;
      const bounds = containerRef.current?.getBoundingClientRect();
      if (!bounds || bounds.bottom <= 0 || bounds.top >= window.innerHeight) return;
      if (e.key === "ArrowRight") {
        e.preventDefault();
        setActiveIndex((cur) => (cur + 1) % STEP_COUNT);
        setAutoPlay(false);
      } else if (e.key === "ArrowLeft") {
        e.preventDefault();
        setActiveIndex((cur) => (cur - 1 + STEP_COUNT) % STEP_COUNT);
        setAutoPlay(false);
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isInView]);

  useEffect(() => {
    if (!autoPlay || !isInView || reducedMotion) return;

    const timer = setInterval(() => {
      setActiveIndex((prev) => (prev + 1) % STEP_COUNT);
    }, AUTO_PLAY_INTERVAL_MS);

    return () => clearInterval(timer);
  }, [autoPlay, isInView, reducedMotion]);

  const activeStep = STEPS[activeIndex];
  const loopActive = activeStep.inLoop;

  /* One row of the mobile timeline: node + header button, the expandable
     detail, and the connector down to the next step. */
  const renderMobileStep = (step: Step, i: number) => {
    const isActive = activeIndex === i;
    return (
      <div key={step.id}>
        {/* A disclosure: the button holds only the node + header (its
            visible name); the expanded detail is rendered after it. */}
        <button
          type="button"
          onClick={() => handleSelect(i)}
          aria-expanded={isActive}
          aria-controls={isActive ? `rhythm-detail-${step.id}` : undefined}
          className="w-full flex items-center gap-4 text-left rounded-xl p-2 transition-colors focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-[#FF5500]/50"
        >
          <motion.div
            className={cn(
              "flex h-10 w-10 shrink-0 items-center justify-center rounded-full border-2 transition-colors duration-300",
              isActive ? "bg-black/60" : "bg-black/30 border-white/[0.14]",
            )}
            style={{
              borderColor: isActive ? step.color : undefined,
              boxShadow: isActive ? `0 0 16px ${step.color}40` : "none",
            }}
            animate={isActive && !reducedMotion ? { scale: [1, 1.06, 1] } : { scale: 1 }}
            transition={
              isActive && !reducedMotion
                ? { duration: 2, repeat: Infinity, ease: "easeInOut" }
                : { duration: 0.2 }
            }
          >
            <step.icon
              className="h-4 w-4"
              aria-hidden="true"
              style={{ color: isActive ? step.color : "rgba(255,255,255,0.55)" }}
            />
          </motion.div>

          <div className="flex min-w-0 flex-1 items-baseline gap-2">
            <span
              className="shrink-0 text-xs font-bold uppercase tracking-widest"
              style={{ color: isActive ? step.color : "#a1a1aa" }}
            >
              Step {i + 1}
            </span>
            <span
              className="text-sm font-bold tracking-tight transition-colors duration-300"
              style={{ color: isActive ? "rgba(255,255,255,0.95)" : "#d4d4d8" }}
            >
              {step.label}
            </span>
          </div>
        </button>

        {/* Expandable detail (indented to the content column:
            button p-2 + 40px node + gap-4) */}
        <AnimatePresence>
          {isActive && (
            <motion.div
              id={`rhythm-detail-${step.id}`}
              initial={reducedMotion ? false : { height: 0, opacity: 0 }}
              animate={{ height: "auto", opacity: 1 }}
              exit={reducedMotion ? undefined : { height: 0, opacity: 0 }}
              transition={{ type: "spring", stiffness: 300, damping: 28 }}
              className="overflow-hidden pl-[4.5rem] pr-2 pb-2"
            >
              <div
                className="mt-1 rounded-xl border p-4 space-y-3"
                style={{ borderColor: `${step.color}25`, background: `${step.color}08` }}
              >
                <div className="space-y-1">
                  <div className="text-xs font-bold uppercase tracking-widest text-zinc-400">
                    Action
                  </div>
                  <p className="text-sm leading-relaxed text-zinc-300 font-light">{step.action}</p>
                </div>
                <div className="space-y-1">
                  <div className="text-xs font-bold uppercase tracking-widest text-zinc-400">
                    Output
                  </div>
                  <p className="text-sm leading-relaxed text-zinc-300 font-light">{step.output}</p>
                </div>
                <div className="space-y-1">
                  <div className="text-xs font-bold uppercase tracking-widest text-zinc-400">
                    Timing
                  </div>
                  <span
                    className="inline-flex rounded-full px-2.5 py-0.5 text-xs font-bold border"
                    style={{
                      borderColor: `${step.color}30`,
                      background: `${step.color}10`,
                      color: step.color,
                    }}
                  >
                    {step.timing}
                  </span>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Vertical connector down to the next step (none after step 5) */}
        {i < STEP_COUNT - 1 && (
          <Connector
            fromIndex={i}
            activeIndex={activeIndex}
            reducedMotion={reducedMotion}
            vertical
          />
        )}
      </div>
    );
  };

  return (
    <div ref={containerRef} className={cn(EXHIBIT_PANEL_CLASS, "relative group/viz")}>
      {/* Noise texture overlay */}
      <div className="absolute inset-0 noise-overlay opacity-[0.02] mix-blend-overlay pointer-events-none rounded-[inherit]" />

      {/* ---- HEADER ---- */}
      <div className="relative z-10 mb-8 sm:mb-10">
        <div className="text-xs font-bold uppercase tracking-widest text-[#FF5500] mb-2 flex items-center gap-2">
          <span className="w-1.5 h-1.5 rounded-full bg-[#FF5500]" />
          Operating Rhythm
        </div>
        <h3 className="font-serif text-[1.5rem] font-normal leading-[1.12] tracking-[-0.008em] text-white sm:text-[1.875rem]">
          From plan to working code in five steps
        </h3>
        <p className="mt-2 text-sm text-zinc-400 font-light max-w-xl">
          Steps 3-5 repeat for every bead. After a few cycles, the loop becomes routine.
        </p>
      </div>

      {/* ---- DESKTOP HORIZONTAL TIMELINE (lg+) ---- */}
      <div className="relative z-10 hidden lg:block">
        <div className="relative">
          {/* Loop bracket: exactly columns 3-5 (40%-100%), and only as tall
              as the timeline, so it never reaches the detail card. */}
          <div
            aria-hidden="true"
            className={cn(
              "pointer-events-none absolute inset-y-0 right-0 rounded-2xl border border-dashed transition-colors duration-300",
              loopActive
                ? "border-[#FFBD2E]/35 bg-[#FFBD2E]/[0.025]"
                : "border-white/[0.14] bg-white/[0.015]",
            )}
            style={{ left: `calc(${2 * COLUMN_PCT}% + 8px)` }}
          />
          <div
            className="pointer-events-none absolute top-3.5 flex items-center gap-1.5 text-xs font-bold uppercase tracking-widest transition-colors duration-300"
            style={{
              left: `calc(${2 * COLUMN_PCT}% + 24px)`,
              color: loopActive ? "#FFBD2E" : "#a1a1aa",
            }}
          >
            <RotateCcw className="h-3 w-3" aria-hidden="true" />
            Repeating loop
            <span className="font-medium normal-case tracking-normal text-zinc-500">
              · steps 3-5
            </span>
          </div>

          {/* Timeline row: five equal columns, a node centered in each */}
          <div className="relative grid grid-cols-5 pb-3" style={{ paddingTop: NODE_ROW_TOP_PX }}>
            {STEPS.slice(0, -1).map((step, i) => (
              <Connector
                key={`conn-${step.id}`}
                fromIndex={i}
                activeIndex={activeIndex}
                reducedMotion={reducedMotion}
                vertical={false}
              />
            ))}
            {STEPS.map((step, i) => (
              <div key={step.id} className="flex min-w-0 justify-center">
                <StepNode
                  step={step}
                  index={i}
                  isActive={activeIndex === i}
                  onClick={() => handleSelect(i)}
                  reducedMotion={reducedMotion}
                />
              </div>
            ))}
          </div>

          {/* Return path from step 5 back to step 3, inside the bracket */}
          <LoopArrow activeIndex={activeIndex} reducedMotion={reducedMotion} vertical={false} />
        </div>

        {/* Detail card below the timeline */}
        <div className="mt-6">
          <AnimatePresence mode="wait">
            <DetailCard
              key={activeStep.id}
              step={activeStep}
              index={activeIndex}
              reducedMotion={reducedMotion}
            />
          </AnimatePresence>
        </div>
      </div>

      {/* ---- MOBILE VERTICAL TIMELINE ---- */}
      <div className="relative z-10 lg:hidden">
        <div className="relative flex flex-col gap-0">
          {/* Steps 1-2 */}
          {STEPS.slice(0, 2).map((step, i) => renderMobileStep(step, i))}

          {/* Steps 3-5 live inside the loop bracket. It bleeds 8px past the
              column (-mx-2) so the nodes stay on the same rail as steps 1-2. */}
          <div
            className={cn(
              "relative -mx-2 rounded-2xl border border-dashed px-[7px] pt-1 transition-colors duration-300",
              loopActive
                ? "border-[#FFBD2E]/35 bg-[#FFBD2E]/[0.025]"
                : "border-white/[0.14] bg-white/[0.015]",
            )}
          >
            {/* Legend sits on the bracket's top border */}
            <div
              className="absolute -top-2.5 left-[60px] flex items-center gap-1.5 bg-[#020408] px-2 text-xs font-bold uppercase leading-5 tracking-widest transition-colors duration-300"
              style={{ color: loopActive ? "#FFBD2E" : "#a1a1aa" }}
            >
              <RotateCcw className="h-3 w-3" aria-hidden="true" />
              Repeating loop
            </div>
            {STEPS.slice(2).map((step, j) => renderMobileStep(step, j + 2))}

            {/* Loop indicator at the bottom of the bracket */}
            <LoopArrow activeIndex={activeIndex} reducedMotion={reducedMotion} vertical />
          </div>
        </div>
      </div>

      {/* ---- AUTO-PLAY TOGGLE ----
          A toggle with a fixed name ("Auto-Play"; aria-pressed carries the
          state, the visible state and step count are aria-hidden). With
          Reduce Motion auto-play never runs, so only the step count shows. */}
      <div className="relative z-10 mt-6 flex items-center justify-center">
        {reducedMotion ? (
          <span className="rounded-full border border-white/[0.1] bg-white/[0.02] px-3 py-1.5 text-xs font-bold uppercase tracking-widest text-zinc-400">
            Step {activeIndex + 1}/{STEP_COUNT}
          </span>
        ) : (
          <button
            type="button"
            onClick={() => setAutoPlay((prev) => !prev)}
            aria-pressed={autoPlay}
            className={cn(
              "text-xs font-bold uppercase tracking-widest px-3 py-1.5 rounded-full border transition-colors duration-300 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-[#FF5500]/50",
              autoPlay
                ? "border-[#FF5500]/20 text-[#FF5500] bg-[#FF5500]/[0.05] hover:bg-[#FF5500]/[0.1]"
                : "border-white/[0.1] text-zinc-400 bg-white/[0.02] hover:bg-white/[0.04] hover:text-zinc-200",
            )}
          >
            Auto-Play
            <span aria-hidden="true">
              {autoPlay ? " On" : " Paused"} &middot; {activeIndex + 1}/{STEP_COUNT}
            </span>
          </button>
        )}
      </div>
    </div>
  );
}
