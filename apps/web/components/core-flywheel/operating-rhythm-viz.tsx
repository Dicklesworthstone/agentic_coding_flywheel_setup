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
  RotateCcw,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

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
    action:
      "Ask 3+ frontier models for competing plans, synthesize into one",
    output:
      "A markdown plan covering workflows, architecture, and tests",
    timing: "~1-3 hours",
    inLoop: false,
  },
  {
    id: "encode",
    label: "Encode",
    icon: GitBranch,
    color: "#FF5500",
    action: "Convert plan into beads with dependencies using br",
    output: "A dependency graph of 50-500 self-contained beads",
    timing: "~30-60 minutes",
    inLoop: false,
  },
  {
    id: "route",
    label: "Route",
    icon: Compass,
    color: "#FFBD2E",
    action:
      "Run bv --robot-triage to find highest-leverage ready bead",
    output: "Ranked recommendations with scores and unblock counts",
    timing: "< 1 second",
    inLoop: true,
  },
  {
    id: "coordinate",
    label: "Coordinate",
    icon: Mail,
    color: "#FF5500",
    action:
      "Claim bead in Agent Mail, reserve files, announce to swarm",
    output: "Thread + file reservations visible to all agents",
    timing: "~ 30 seconds",
    inLoop: true,
  },
  {
    id: "execute",
    label: "Execute & Close",
    icon: Code,
    iconAlt: CheckCircle,
    color: "#22c55e",
    action:
      "Implement, test, fresh-eyes review, close bead, repeat from step 3",
    output:
      "Working code + tests, updated graph, next bead queued",
    timing: "10-60 minutes per bead",
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
      aria-label={`Step ${index + 1}: ${step.label}`}
      className="group relative flex flex-col items-center gap-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/50 rounded-xl"
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
            ? "bg-black/60"
            : "bg-black/30 border-white/[0.08] hover:border-white/[0.15]",
        )}
        style={{
          borderColor: isActive ? step.color : undefined,
        }}
        animate={
          isActive && !reducedMotion
            ? { scale: [1, 1.08, 1] }
            : { scale: 1 }
        }
        transition={
          isActive && !reducedMotion
            ? { duration: 2, repeat: Infinity, ease: "easeInOut" }
            : { duration: 0.2 }
        }
      >
        <div className="flex items-center gap-0.5">
          <Icon
            className="h-5 w-5 transition-colors duration-300"
            style={{ color: isActive ? step.color : "rgba(255,255,255,0.35)" }}
          />
          {IconAlt && (
            <>
              <span
                className="text-[10px] font-bold transition-colors duration-300"
                style={{
                  color: isActive ? step.color : "rgba(255,255,255,0.2)",
                }}
              >
                /
              </span>
              <IconAlt
                className="h-4 w-4 transition-colors duration-300"
                style={{
                  color: isActive ? step.color : "rgba(255,255,255,0.35)",
                }}
              />
            </>
          )}
        </div>
      </motion.div>

      {/* Step number + label */}
      <div className="relative z-10 flex flex-col items-center">
        <span
          className="text-[0.55rem] font-bold uppercase tracking-widest transition-colors duration-300"
          style={{
            color: isActive ? step.color : "rgba(255,255,255,0.2)",
          }}
        >
          {index + 1}
        </span>
        <span
          className="text-[0.7rem] font-bold tracking-wide transition-colors duration-300 whitespace-nowrap"
          style={{
            color: isActive ? "rgba(255,255,255,0.9)" : "rgba(255,255,255,0.3)",
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
        <span
          className="text-sm font-bold tracking-tight"
          style={{ color: step.color }}
        >
          {step.label}
        </span>
      </div>

      {/* Content grid */}
      <div className="relative z-10 grid gap-4 sm:grid-cols-3">
        {/* Action */}
        <div className="space-y-1.5">
          <div className="text-[0.6rem] font-bold uppercase tracking-widest text-white/30">
            Action
          </div>
          <p className="text-sm leading-relaxed text-zinc-300 font-light">
            {step.action}
          </p>
        </div>

        {/* Output */}
        <div className="space-y-1.5">
          <div className="text-[0.6rem] font-bold uppercase tracking-widest text-white/30">
            Output
          </div>
          <p className="text-sm leading-relaxed text-zinc-300 font-light">
            {step.output}
          </p>
        </div>

        {/* Timing */}
        <div className="space-y-1.5">
          <div className="text-[0.6rem] font-bold uppercase tracking-widest text-white/30">
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
  const isCrossing =
    activeIndex === fromIndex || activeIndex === fromIndex + 1;

  return (
    <div
      className={cn(
        "relative flex items-center justify-center",
        vertical ? "h-8 w-0.5 mx-auto" : "w-full h-0.5 flex-1",
      )}
    >
      <motion.div
        className={cn(
          "absolute",
          vertical ? "inset-y-0 left-1/2 -translate-x-1/2 w-0.5" : "inset-x-0 top-1/2 -translate-y-1/2 h-0.5",
        )}
        style={{
          background: isCrossing
            ? `linear-gradient(${vertical ? "to bottom" : "to right"}, ${STEPS[fromIndex].color}60, ${STEPS[fromIndex + 1].color}60)`
            : "rgba(255,255,255,0.06)",
        }}
        animate={
          isCrossing && !reducedMotion
            ? { opacity: [0.5, 1, 0.5] }
            : { opacity: 1 }
        }
        transition={
          isCrossing && !reducedMotion
            ? { duration: 1.5, repeat: Infinity, ease: "easeInOut" }
            : {}
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

  if (vertical) {
    return (
      <motion.div
        className="flex items-center justify-center gap-2 py-2"
        animate={
          isHighlighted && !reducedMotion
            ? { opacity: [0.6, 1, 0.6] }
            : { opacity: 0.5 }
        }
        transition={
          isHighlighted && !reducedMotion
            ? { duration: 2, repeat: Infinity, ease: "easeInOut" }
            : {}
        }
      >
        <RotateCcw
          className="h-4 w-4"
          style={{ color: isHighlighted ? "#FFBD2E" : "rgba(255,255,255,0.15)" }}
        />
        <span
          className="text-[0.6rem] font-bold uppercase tracking-widest"
          style={{ color: isHighlighted ? "#FFBD2E" : "rgba(255,255,255,0.15)" }}
        >
          Repeat from Route
        </span>
      </motion.div>
    );
  }

  return (
    <motion.div
      className="absolute -bottom-10 right-0 flex items-center gap-1.5"
      style={{
        /* Position the loop arrow under the last three steps */
        left: "40%",
      }}
      animate={
        isHighlighted && !reducedMotion
          ? { opacity: [0.5, 1, 0.5] }
          : { opacity: 0.4 }
      }
      transition={
        isHighlighted && !reducedMotion
          ? { duration: 2, repeat: Infinity, ease: "easeInOut" }
          : {}
      }
    >
      {/* Curved line using SVG */}
      <svg
        width="100%"
        height="28"
        viewBox="0 0 300 28"
        fill="none"
        className="overflow-visible"
        aria-hidden="true"
      >
        <path
          d="M290 2 C290 20, 150 26, 10 20"
          stroke={isHighlighted ? "#FFBD2E" : "rgba(255,255,255,0.1)"}
          strokeWidth="1.5"
          strokeDasharray="4 4"
          fill="none"
        />
        {/* Arrowhead */}
        <polygon
          points="6,16 14,20 10,24"
          fill={isHighlighted ? "#FFBD2E" : "rgba(255,255,255,0.1)"}
        />
      </svg>
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
  const handleSelect = useCallback(
    (index: number) => {
      setActiveIndex(index);
      setAutoPlay(false);
    },
    [],
  );

  /* Keyboard navigation — only when this viz is in the viewport */
  useEffect(() => {
    if (!isInView) return;
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "ArrowRight") {
        e.preventDefault();
        setActiveIndex((cur) => (cur + 1) % STEP_COUNT);
        setAutoPlay(false);
      } else if (e.key === "ArrowLeft") {
        e.preventDefault();
        setActiveIndex((cur) => (cur - 1 + STEP_COUNT) % STEP_COUNT);
        setAutoPlay(false);
      } else if (e.key === " ") {
        e.preventDefault();
        setAutoPlay((cur) => !cur);
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

  return (
    <div
      ref={containerRef}
      className={cn(EXHIBIT_PANEL_CLASS, "relative group/viz")}
    >
      {/* Noise texture overlay */}
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.02] mix-blend-overlay pointer-events-none rounded-[inherit]" />

      {/* ---- HEADER ---- */}
      <div className="relative z-10 mb-8 sm:mb-10">
        <div className="text-[0.65rem] font-bold uppercase tracking-widest text-[#FF5500]/70 mb-2 flex items-center gap-2">
          <span className="w-1.5 h-1.5 rounded-full bg-[#FF5500] animate-pulse shadow-[0_0_8px_rgba(255,85,0,0.8)]" />
          Operating Rhythm
        </div>
        <h4 className="text-xl sm:text-2xl font-black text-white tracking-tight">
          From plan to production in five steps
        </h4>
        <p className="mt-2 text-sm text-zinc-400 font-light max-w-xl">
          Steps 3-5 repeat for every bead. You stop thinking about the process after the second cycle.
        </p>
      </div>

      {/* ---- DESKTOP HORIZONTAL TIMELINE (lg+) ---- */}
      <div className="relative z-10 hidden lg:block">
        {/* Loop background: subtle pill behind steps 3-5 */}
        <div className="absolute top-0 -bottom-12 rounded-2xl border border-dashed border-white/[0.04] bg-white/[0.015]" style={{ left: "38%", right: "0%" }} />
        <div
          className="absolute top-1 flex items-center gap-1 text-[0.55rem] font-bold uppercase tracking-widest"
          style={{ left: "40%", color: "rgba(255,255,255,0.12)" }}
        >
          <RotateCcw className="h-3 w-3" />
          Repeating loop
        </div>

        {/* Timeline row */}
        <div className="relative flex items-start pt-8 pb-4">
          {STEPS.map((step, i) => (
            <div key={step.id} className="flex items-center flex-1 min-w-0">
              <StepNode
                step={step}
                index={i}
                isActive={activeIndex === i}
                onClick={() => handleSelect(i)}
                reducedMotion={reducedMotion}
              />
              {i < STEP_COUNT - 1 && (
                <Connector
                  fromIndex={i}
                  activeIndex={activeIndex}
                  reducedMotion={reducedMotion}
                  vertical={false}
                />
              )}
            </div>
          ))}
        </div>

        {/* Loop arrow from step 5 back to step 3 */}
        <div className="relative h-10">
          <LoopArrow
            activeIndex={activeIndex}
            reducedMotion={reducedMotion}
            vertical={false}
          />
        </div>

        {/* Detail card below the timeline */}
        <div className="mt-4">
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
        {/* Loop background behind steps 3-5 */}
        <div className="absolute rounded-2xl border border-dashed border-white/[0.04] bg-white/[0.015]" style={{ top: "55%", bottom: "0%", left: "-4px", right: "-4px" }}>
          <div className="flex items-center gap-1 px-3 pt-2 text-[0.55rem] font-bold uppercase tracking-widest" style={{ color: "rgba(255,255,255,0.12)" }}>
            <RotateCcw className="h-3 w-3" />
            Repeating loop
          </div>
        </div>

        <div className="relative flex flex-col gap-0">
          {STEPS.map((step, i) => (
            <div key={step.id}>
              {/* Step node + card combined as a clickable row */}
              <button
                type="button"
                onClick={() => handleSelect(i)}
                aria-pressed={activeIndex === i}
                aria-label={`Step ${i + 1}: ${step.label}`}
                className="w-full flex items-start gap-4 text-left rounded-xl p-2 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/50"
              >
                {/* Vertical connector + node */}
                <div className="flex flex-col items-center shrink-0">
                  <motion.div
                    className={cn(
                      "flex h-10 w-10 items-center justify-center rounded-full border-2 transition-colors duration-300",
                      activeIndex === i
                        ? "bg-black/60"
                        : "bg-black/30 border-white/[0.08]",
                    )}
                    style={{
                      borderColor: activeIndex === i ? step.color : undefined,
                      boxShadow:
                        activeIndex === i
                          ? `0 0 16px ${step.color}40`
                          : "none",
                    }}
                    animate={
                      activeIndex === i && !reducedMotion
                        ? { scale: [1, 1.06, 1] }
                        : { scale: 1 }
                    }
                    transition={
                      activeIndex === i && !reducedMotion
                        ? {
                            duration: 2,
                            repeat: Infinity,
                            ease: "easeInOut",
                          }
                        : { duration: 0.2 }
                    }
                  >
                    <step.icon
                      className="h-4 w-4"
                      style={{
                        color:
                          activeIndex === i
                            ? step.color
                            : "rgba(255,255,255,0.35)",
                      }}
                    />
                  </motion.div>
                </div>

                {/* Content */}
                <div className="flex-1 min-w-0 pb-2">
                  <div className="flex items-center gap-2 mb-1">
                    <span
                      className="text-[0.55rem] font-bold uppercase tracking-widest"
                      style={{
                        color:
                          activeIndex === i
                            ? step.color
                            : "rgba(255,255,255,0.2)",
                      }}
                    >
                      Step {i + 1}
                    </span>
                    <span
                      className="text-sm font-bold tracking-tight transition-colors duration-300"
                      style={{
                        color:
                          activeIndex === i
                            ? "rgba(255,255,255,0.9)"
                            : "rgba(255,255,255,0.35)",
                      }}
                    >
                      {step.label}
                    </span>
                  </div>

                  {/* Expandable detail */}
                  <AnimatePresence>
                    {activeIndex === i && (
                      <motion.div
                        initial={
                          reducedMotion ? false : { height: 0, opacity: 0 }
                        }
                        animate={{ height: "auto", opacity: 1 }}
                        exit={
                          reducedMotion
                            ? undefined
                            : { height: 0, opacity: 0 }
                        }
                        transition={{
                          type: "spring",
                          stiffness: 300,
                          damping: 28,
                        }}
                        className="overflow-hidden"
                      >
                        <div
                          className="mt-2 rounded-xl border p-4 space-y-3"
                          style={{
                            borderColor: `${step.color}20`,
                            background: `${step.color}08`,
                          }}
                        >
                          <div className="space-y-1">
                            <div className="text-[0.6rem] font-bold uppercase tracking-widest text-white/30">
                              Action
                            </div>
                            <p className="text-sm leading-relaxed text-zinc-300 font-light">
                              {step.action}
                            </p>
                          </div>
                          <div className="space-y-1">
                            <div className="text-[0.6rem] font-bold uppercase tracking-widest text-white/30">
                              Output
                            </div>
                            <p className="text-sm leading-relaxed text-zinc-300 font-light">
                              {step.output}
                            </p>
                          </div>
                          <div className="space-y-1">
                            <div className="text-[0.6rem] font-bold uppercase tracking-widest text-white/30">
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
                </div>
              </button>

              {/* Vertical connector line */}
              {i < STEP_COUNT - 1 && (
                <Connector
                  fromIndex={i}
                  activeIndex={activeIndex}
                  reducedMotion={reducedMotion}
                  vertical
                />
              )}
            </div>
          ))}

          {/* Loop indicator at the bottom on mobile */}
          <LoopArrow
            activeIndex={activeIndex}
            reducedMotion={reducedMotion}
            vertical
          />
        </div>
      </div>

      {/* ---- AUTO-PLAY INDICATOR ---- */}
      <div className="relative z-10 mt-6 flex items-center justify-center">
        <button
          type="button"
          onClick={() => setAutoPlay((prev) => !prev)}
          className={cn(
            "text-[0.6rem] font-bold uppercase tracking-widest px-3 py-1.5 rounded-full border transition-colors duration-300",
            autoPlay
              ? "border-[#FF5500]/20 text-[#FF5500]/60 bg-[#FF5500]/[0.05] hover:bg-[#FF5500]/[0.1]"
              : "border-white/[0.06] text-white/20 bg-white/[0.02] hover:bg-white/[0.04]",
          )}
        >
          {autoPlay ? "Auto-playing" : "Paused"} &middot;{" "}
          {activeIndex + 1}/{STEP_COUNT}
        </button>
      </div>
    </div>
  );
}
