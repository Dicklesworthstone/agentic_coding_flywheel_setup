"use client";

import { useEffect, useId, useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "@/components/motion";

/** Where each stage's label sits around its node. "end" ends the label at the
 *  node, so the rightmost stage's label stays inside a phone-width diagram. */
const LABEL_PLACEMENT: Record<string, { side: "top" | "bottom"; align: "center" | "end" }> = {
  human: { side: "top", align: "center" },
  plan: { side: "top", align: "center" },
  beads: { side: "top", align: "end" },
  swarm: { side: "bottom", align: "center" },
  review: { side: "bottom", align: "center" },
};

export function FlywheelDiagram() {
  const ref = useRef<HTMLDivElement>(null);
  const isFinePointer = useRef(false);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const rm = prefersReducedMotion ?? false;
  const [activeStage, setActiveStage] = useState(0);
  const [cycleDepth, setCycleDepth] = useState(1);
  const [autoTour, setAutoTour] = useState(true);
  const depthLabelId = useId();

  const stages = [
    {
      id: "human",
      label: "Intent",
      x: 140,
      y: 110,
      color: "#FFFFFF",
      input: "Fuzzy goals",
      output: "Mental model",
      effect: "Turns fuzzy goals into a clear idea of what to build and why.",
    },
    {
      id: "plan",
      label: "Plan",
      x: 420,
      y: 60,
      color: "#FF5500",
      input: "Mental model",
      output: "Markdown plan",
      effect: "Settles the architecture of the whole system in the plan.",
    },
    {
      id: "beads",
      label: "Translation",
      x: 580,
      y: 210,
      color: "#FFBD2E",
      input: "Markdown plan",
      output: "Bead graph",
      effect: "Turns the plan into beads that agents can claim and implement.",
    },
    {
      id: "swarm",
      label: "Execution",
      x: 420,
      y: 360,
      color: "#A1A1AA",
      input: "Beads + AGENTS.md",
      output: "Code changes",
      effect: "Agents implement the beads, following AGENTS.md.",
    },
    {
      id: "review",
      label: "Harden",
      x: 140,
      y: 310,
      color: "#71717A",
      input: "Code changes",
      output: "Verified system",
      effect: "Review and testing verify the code and record what was learned for the next cycle.",
    },
  ] as const;

  const cycleOptions = [1, 3, 6] as const;
  const metrics = [
    { label: "Return on planning", value: Math.min(99, 58 + cycleDepth * 12) },
    { label: "Swarm determinism", value: Math.min(99, 42 + cycleDepth * 18) },
    { label: "Reusable memory", value: Math.min(99, 28 + cycleDepth * 24) },
  ];
  const loopVelocity = [1, 1.8, 3.2][cycleDepth];
  const currentStage = stages[activeStage];

  useEffect(() => {
    isFinePointer.current = window.matchMedia("(hover: hover) and (pointer: fine)").matches;
  }, []);

  const selectStage = (index: number) => {
    setActiveStage(index);
    setAutoTour(false);
  };

  useEffect(() => {
    if (!isInView || rm || !autoTour) return undefined;

    const intervalId = window.setInterval(() => {
      setActiveStage((current) => (current + 1) % stages.length);
    }, 2600);

    return () => window.clearInterval(intervalId);
  }, [autoTour, isInView, rm, stages.length]);

  const getConnectorPath = (from: { x: number; y: number }, to: { x: number; y: number }) => {
    const center = { x: 320, y: 210 };
    const midX = (from.x + to.x) / 2;
    const midY = (from.y + to.y) / 2;
    const controlX = midX + (center.x - midX) * 0.26;
    const controlY = midY + (center.y - midY) * 0.26;
    return `M ${from.x} ${from.y} Q ${controlX} ${controlY} ${to.x} ${to.y}`;
  };

  return (
    <div
      ref={ref}
      className="my-16 overflow-hidden rounded-2xl border border-white/[0.08] bg-[#05070a] p-5 sm:rounded-[2rem] sm:p-10 lg:p-12 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9),inset_0_1px_1px_rgba(255,255,255,0.05)] relative group/viz"
    >
      <div className="absolute inset-0 noise-overlay opacity-[0.02] mix-blend-overlay pointer-events-none" />
      <div className="absolute top-0 right-0 w-[800px] h-[800px] bg-[radial-gradient(ellipse_at_top_right,rgba(167,139,250,0.03),transparent_60%)] pointer-events-none" />

      {/* Stacked at every width: the guide column (~900px) is too narrow
          for the title, the controls and the 640px loop diagram side by side. */}
      <div className="relative z-10 flex flex-col gap-8 border-b border-white/[0.04] pb-10">
        <div className="max-w-2xl">
          <div className="text-xs font-bold uppercase tracking-widest text-primary flex items-center gap-3 mb-4">
            <span className="w-1.5 h-1.5 rounded-full bg-primary" />
            Interactive Visualization
          </div>
          <h3 className="font-serif text-[1.5rem] font-normal leading-[1.12] tracking-[-0.008em] text-white sm:text-[1.875rem]">
            How each turn of the flywheel speeds up the next
          </h3>
          <p className="mt-6 text-[1.1rem] leading-relaxed text-zinc-400 font-light">
            Step through the loop. Each completed cycle leaves a better plan, better beads, and a
            better AGENTS.md for the next one, so the same project gets faster and safer. This is
            the{" "}
            <span className="font-medium text-white border-b border-primary/40 pb-0.5 relative inline-block group/highlight">
              <span className="absolute inset-x-0 -bottom-px h-[2px] bg-primary opacity-0 group-hover/highlight:opacity-100 transition-opacity blur-[2px]" />
              compounding return on planning
            </span>
            .
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-4">
          {/* Label above the buttons on phones, beside them from sm. */}
          <div className="flex flex-col items-start gap-2 sm:flex-row sm:items-center sm:gap-3">
            <span id={depthLabelId} className="text-xs font-bold uppercase tracking-[0.2em] text-zinc-400">
              Simulation Depth
            </span>
            {/* One choice at a time: the group is named by the label, and
                aria-pressed says which depth is showing. */}
            <div
              role="group"
              aria-labelledby={depthLabelId}
              className="flex gap-2 p-1.5 rounded-2xl bg-[#020408] border border-white/[0.05] shadow-inner"
            >
              {cycleOptions.map((cycleCount, index) => (
                <button
                  key={cycleCount}
                  type="button"
                  aria-pressed={cycleDepth === index}
                  onClick={() => {
                    setCycleDepth(index);
                    setAutoTour(false);
                  }}
                  className={`min-h-9 px-3 py-2 text-xs font-bold uppercase tracking-[0.12em] rounded-xl transition duration-500 sm:px-5 sm:tracking-widest ${
                    cycleDepth === index
                      ? "bg-primary text-black shadow-[0_0_20px_rgba(var(--primary-rgb),0.4)]"
                      : "text-white/40 hover:text-white/80 hover:bg-white/[0.03]"
                  }`}
                >
                  Loop {cycleCount}
                </button>
              ))}
            </div>
          </div>
          {/* Not offered with Reduce Motion, where the tour never runs. A
              toggle with a fixed name: aria-pressed carries the state and the
              visible On/Paused suffix is aria-hidden. Paused text is zinc-400,
              like the core guide's toggles. */}
          {!rm && (
            <button
              type="button"
              onClick={() => setAutoTour((current) => !current)}
              aria-pressed={autoTour}
              className={`group flex items-center gap-3 px-5 py-2.5 rounded-xl border transition duration-500 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-[#FF5500]/60 ${
                autoTour
                  ? "border-primary/30 bg-primary/10 text-primary shadow-[inset_0_1px_1px_rgba(255,255,255,0.05)]"
                  : "border-white/10 bg-white/[0.02] text-zinc-400 hover:bg-white/[0.04] hover:text-zinc-200"
              }`}
            >
              <div
                className={`w-2 h-2 rounded-full ${autoTour ? "bg-primary shadow-[0_0_8px_rgba(var(--primary-rgb),0.8)] animate-pulse" : "bg-white/20"}`}
              />
              <span className="text-xs font-bold uppercase tracking-widest">
                Auto-Tour<span aria-hidden="true">{autoTour ? " On" : " Paused"}</span>
              </span>
            </button>
          )}
        </div>
      </div>

      <div className="relative z-10 mt-12 grid items-center gap-12">
        {/* The SVG draws the orbit and scales to the column; the stage labels
            and the readout are HTML on top, so they stay legible on a phone
            instead of shrinking with the drawing or scrolling sideways. */}
        <div className="relative mx-auto w-full max-w-[720px] py-6">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(var(--primary-rgb),0.05),transparent_60%)]" />
          {/* A size container: the hub readout sizes itself to the drawing
              (the hub is 170/640 of its width), not to the viewport. */}
          <div className="@container relative aspect-[640/420] w-full">
          <svg viewBox="0 0 640 420" className="absolute inset-0 h-full w-full" aria-hidden="true">
            {/* Main structural orbits */}
            <ellipse
              cx="320"
              cy="210"
              rx="240"
              ry="160"
              fill="none"
              stroke="white"
              strokeOpacity="0.04"
              strokeWidth="1"
            />
            <ellipse
              cx="320"
              cy="210"
              rx="200"
              ry="130"
              fill="none"
              stroke="url(#orbitGradient)"
              strokeOpacity="0.08"
              strokeWidth="1.5"
              strokeDasharray="4 4"
            />
            <defs>
              <linearGradient id="orbitGradient" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stopColor="#FF5500" stopOpacity="1" />
                <stop offset="50%" stopColor="#FFBD2E" stopOpacity="1" />
                <stop offset="100%" stopColor="#FFFFFF" stopOpacity="1" />
              </linearGradient>
              {/* In drawing units: the default bounding-box region clips the
                  blur into a square around a node. */}
              <filter id="nodeGlow" filterUnits="userSpaceOnUse" x="0" y="0" width="640" height="420">
                <feGaussianBlur stdDeviation="4" result="coloredBlur" />
                <feMerge>
                  <feMergeNode in="coloredBlur" />
                  <feMergeNode in="SourceGraphic" />
                </feMerge>
              </filter>
            </defs>

            {stages.map((stage, index) => {
              const nextStage = stages[(index + 1) % stages.length];
              const isActive = index === activeStage;

              return (
                <motion.path
                  key={`${stage.id}-${nextStage.id}`}
                  d={getConnectorPath(stage, nextStage)}
                  fill="none"
                  stroke={isActive ? stage.color : "white"}
                  strokeOpacity={isActive ? 0.8 : 0.05}
                  strokeWidth={isActive ? 2.5 : 1}
                  initial={false}
                  animate={{
                    strokeDasharray: isActive ? ["0, 500", "500, 0"] : "4, 12",
                    strokeOpacity: isActive ? 1 : 0.05,
                  }}
                  transition={{ duration: 1.5, ease: "easeInOut" }}
                  filter={isActive ? "url(#nodeGlow)" : undefined}
                />
              );
            })}

            {/* Orbitals */}
            {[0, 1, 2].map((i) => (
              <motion.g
                key={`orbit-${i}`}
                style={{ transformOrigin: "320px 210px" }}
                animate={{ rotate: 360 }}
                transition={{
                  duration: 25 - cycleDepth * 5 + i * 5,
                  repeat: Infinity,
                  ease: "linear",
                }}
              >
                <circle
                  cx="320"
                  cy={210 - (160 + i * 20)}
                  r={3}
                  fill="#FF5500"
                  fillOpacity="0.5"
                  filter="url(#nodeGlow)"
                />
              </motion.g>
            ))}

            <g>
              <circle
                cx="320"
                cy="210"
                r="85"
                fill="#020408"
                stroke="#FF5500"
                strokeOpacity="0.25"
                strokeWidth="2"
              />
            </g>

            {stages.map((stage, index) => {
              const isActive = index === activeStage;
              return (
                <g key={stage.id}>
                  {/* Point core */}
                  <motion.circle
                    cx={stage.x}
                    cy={stage.y}
                    r={isActive ? 10 : 6}
                    fill={isActive ? stage.color : "white"}
                    fillOpacity={isActive ? 1 : 0.45}
                    animate={{ scale: isActive && !rm ? [1, 1.4, 1] : 1 }}
                    // Repeat only while pulsing: an infinite repeat on the
                    // settle-to-1 animation re-ran it from mid-pulse every 2s,
                    // so dots the tour had left kept ticking.
                    transition={
                      isActive && !rm
                        ? { duration: 2, repeat: Infinity, ease: "easeInOut" }
                        : { duration: 0.3, ease: "easeOut" }
                    }
                    filter={isActive ? "url(#nodeGlow)" : undefined}
                  />

                  {/* Outer rings */}
                  <circle
                    cx={stage.x}
                    cy={stage.y}
                    r={isActive ? 28 : 15}
                    fill="none"
                    stroke={stage.color}
                    strokeOpacity={isActive ? 0.5 : 0.3}
                    strokeWidth="1.5"
                  />
                </g>
              );
            })}
          </svg>

          <div className="pointer-events-none absolute left-1/2 top-1/2 flex -translate-x-1/2 -translate-y-1/2 flex-col items-center">
            {/* The 12px label needs a hub of ~76px (diagram 288px+), and
                "System Output" one of ~175px (660px+); below that the label
                is for screen readers only. */}
            <span className="sr-only text-xs font-bold uppercase tracking-[0.15em] text-zinc-400 @min-[18rem]:not-sr-only @min-[41.25rem]:tracking-[0.3em]">
              <span className="hidden @min-[41.25rem]:inline">System </span>Output
            </span>
            <motion.span
              className="text-[clamp(1.25rem,7.5cqw,3.5rem)] font-black leading-none tracking-tighter text-white tabular-nums @min-[18rem]:mt-0.5 @min-[30rem]:mt-2"
              // Not `rm ? undefined`: the hook reports no preference during
              // hydration, and an undefined animate never stops the pulse.
              animate={{ scale: rm ? 1 : [1, 1.05, 1] }}
              transition={
                rm ? { duration: 0 } : { duration: 2, repeat: Infinity, ease: "easeInOut" }
              }
            >
              {loopVelocity.toFixed(1)}x
            </motion.span>
          </div>

          {stages.map((stage, index) => {
            const isActive = index === activeStage;
            const place = LABEL_PLACEMENT[stage.id];
            return (
              <button
                key={stage.id}
                type="button"
                aria-pressed={isActive}
                onClick={() => selectStage(index)}
                onMouseEnter={() => {
                  if (isFinePointer.current) selectStage(index);
                }}
                className="group absolute flex h-11 w-11 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-primary/70"
                style={{ left: `${(stage.x / 640) * 100}%`, top: `${(stage.y / 420) * 100}%` }}
              >
                {/* Inside the button, so the name is part of the click and
                    hover target, as the old SVG hit circles made it. */}
                <span
                  className={`absolute whitespace-nowrap text-xs font-bold uppercase tracking-[0.08em] transition-colors duration-300 sm:tracking-[0.2em] ${
                    isActive ? "text-white" : "text-zinc-400 group-hover:text-zinc-200"
                  } ${place.side === "top" ? "bottom-full mb-0.5 sm:mb-2.5" : "top-full mt-0.5 sm:mt-2.5"} ${
                    place.align === "end" ? "right-2" : "left-1/2 -translate-x-1/2"
                  }`}
                >
                  {stage.label}
                </span>
              </button>
            );
          })}
          </div>
        </div>

        <div className="flex flex-col gap-10">
          <AnimatePresence mode="wait">
            <motion.div
              key={currentStage.id}
              // A short fade: the tour changes stage every 2.6s, and a longer
              // exit-then-enter left the panel blank for much of each step.
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.18, ease: "easeOut" }}
              className="flex flex-col gap-8"
            >
              <div className="flex flex-col gap-3">
                <div
                  className="text-xs font-bold uppercase tracking-widest flex items-center gap-2"
                  style={{ color: currentStage.color }}
                >
                  <span
                    className="w-1.5 h-1.5 rounded-full"
                    style={{ backgroundColor: currentStage.color }}
                  />
                  Current Stage
                </div>
                <h4 className="font-serif text-[2.5rem] font-normal leading-none tracking-[-0.01em] text-white sm:text-[3rem]">
                  {currentStage.label}
                </h4>
                <p className="mt-2 text-[1.1rem] leading-relaxed text-zinc-300 font-light">
                  {currentStage.effect}
                </p>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
                <div className="flex flex-col gap-2 p-5 sm:p-6 rounded-2xl bg-white/[0.02] border border-white/[0.04] shadow-sm relative overflow-hidden group/box">
                  <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />
                  <span className="text-xs font-bold text-white/30 uppercase tracking-widest flex items-center gap-2">
                    Input
                  </span>
                  <p className="text-sm sm:text-base text-white/90 font-medium">
                    {currentStage.input}
                  </p>
                </div>
                <div className="flex flex-col gap-2 p-5 sm:p-6 rounded-2xl bg-white/[0.02] border border-white/[0.04] shadow-sm relative overflow-hidden group/box">
                  <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />
                  <span className="text-xs font-bold text-white/30 uppercase tracking-widest flex items-center gap-2">
                    Output
                  </span>
                  <p className="text-sm sm:text-base text-white/90 font-medium">
                    {currentStage.output}
                  </p>
                </div>
              </div>
            </motion.div>
          </AnimatePresence>

          <div className="mt-auto pt-10 border-t border-white/[0.04] space-y-6">
            <div className="text-xs font-bold uppercase tracking-widest text-white/40">
              System Metrics{" "}
              <span className="text-[#FF5500] ml-1 font-mono bg-[#FF5500]/10 px-1.5 py-0.5 rounded">
                L{cycleOptions[cycleDepth]}
              </span>
            </div>
            <div className="space-y-5">
              {metrics.map((metric) => (
                <div key={metric.label} className="group/metric">
                  <div className="mb-2.5 flex items-center justify-between">
                    <span className="text-xs font-bold text-zinc-400 group-hover/metric:text-white transition-colors uppercase tracking-widest">
                      {metric.label}
                    </span>
                    <span className="font-mono text-[#FF5500] text-sm font-black drop-shadow-[0_0_8px_rgba(255,85,0,0.5)]">
                      {metric.value}%
                    </span>
                  </div>
                  <div className="h-[3px] w-full bg-[#020408] border border-white/[0.05] rounded-full overflow-hidden shadow-inner">
                    <motion.div
                      className="h-full bg-gradient-to-r from-[#FF5500] to-[#FFBD2E] shadow-[0_0_10px_rgba(255,85,0,0.8)]"
                      initial={{ width: 0 }}
                      animate={{ width: `${metric.value}%` }}
                      transition={{ duration: 1, type: "spring", bounce: 0 }}
                    />
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
