"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "framer-motion";

export function FlywheelDiagram() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const rm = prefersReducedMotion ?? false;
  const [activeStage, setActiveStage] = useState(0);
  const [cycleDepth, setCycleDepth] = useState(1);
  const [autoTour, setAutoTour] = useState(true);

  const stages = [
    { id: "human", label: "Intent", x: 140, y: 110, color: "#FFFFFF", input: "Fuzzy goals", output: "Mental model", effect: "Defines the 'Why'" },
    { id: "plan", label: "Planning", x: 420, y: 60, color: "#FF5500", input: "Mental model", output: "Markdown plan", effect: "Solves global architecture" },
    { id: "beads", label: "Translation", x: 580, y: 210, color: "#FFBD2E", input: "Markdown plan", output: "Bead graph", effect: "Creates execution substrate" },
    { id: "swarm", label: "Execution", x: 420, y: 360, color: "#A1A1AA", input: "Beads + AGENTS.md", output: "Code changes", effect: "Mechanizes implementation" },
    { id: "review", label: "Harden", x: 140, y: 310, color: "#71717A", input: "Code changes", output: "Verified system", effect: "Produces truth & memory" }
  ] as const;

  const cycleOptions = [1, 3, 6] as const;
  const metrics = [
    { label: "Planning leverage", value: Math.min(99, 58 + cycleDepth * 12) },
    { label: "Swarm determinism", value: Math.min(99, 42 + cycleDepth * 18) },
    { label: "Reusable memory", value: Math.min(99, 28 + cycleDepth * 24) },
  ];
  const loopVelocity = [1, 1.8, 3.2][cycleDepth];
  const currentStage = stages[activeStage];

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
      className="my-16 overflow-hidden rounded-[3rem] border border-white/[0.04] bg-[#05070a] p-8 sm:p-12 lg:p-16 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9),inset_0_1px_1px_rgba(255,255,255,0.05)] relative group/viz"
    >
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.02] mix-blend-overlay pointer-events-none" />
      <div className="absolute top-0 right-0 w-[800px] h-[800px] bg-[radial-gradient(ellipse_at_top_right,rgba(167,139,250,0.03),transparent_60%)] pointer-events-none" />

      <div className="relative z-10 flex flex-col gap-10 border-b border-white/[0.04] pb-12 lg:flex-row lg:items-start lg:justify-between">
        <div className="max-w-2xl">
          <div className="text-[0.65rem] font-bold uppercase tracking-widest text-primary/80 flex items-center gap-3 mb-4">
            <span className="w-1.5 h-1.5 rounded-full bg-primary animate-pulse shadow-[0_0_8px_rgba(var(--primary-rgb),0.8)]" />
            Interactive Visualization
          </div>
          <h4 className="text-3xl font-black tracking-tight text-white sm:text-4xl lg:text-5xl leading-[1.15] drop-shadow-lg">
            Why the flywheel compounds instead of spinning in place
          </h4>
          <p className="mt-6 text-[1.1rem] leading-relaxed text-zinc-400 font-light">
            Step through the loop. The same project gets faster and safer
            because every completed cycle upgrades the artifacts feeding the next one. 
            This is the <span className="font-medium text-white border-b border-primary/40 pb-0.5 relative inline-block group/highlight"><span className="absolute inset-x-0 -bottom-px h-[2px] bg-primary opacity-0 group-hover/highlight:opacity-100 transition-opacity blur-[2px]" />compounding return on planning</span>.
          </p>
        </div>

        <div className="flex flex-col items-start lg:items-end gap-5">
          <div className="flex items-center gap-3">
            <span className="text-[0.6rem] font-bold uppercase tracking-[0.3em] text-white/30">
              Simulation Depth
            </span>
            <div className="flex gap-2 p-1.5 rounded-2xl bg-[#020408] border border-white/[0.05] shadow-inner">
              {cycleOptions.map((cycleCount, index) => (
                <button
                  key={cycleCount}
                  type="button"
                  onClick={() => {
                    setCycleDepth(index);
                    setAutoTour(false);
                  }}
                  className={`px-5 py-2 text-[0.65rem] font-black uppercase tracking-widest rounded-xl transition-all duration-500 ${
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
          <button
            type="button"
            onClick={() => setAutoTour((current) => !current)}
            className={`group flex items-center gap-3 px-5 py-2.5 rounded-xl border transition-all duration-500 ${
              autoTour
                ? "border-primary/30 bg-primary/10 text-primary shadow-[inset_0_1px_1px_rgba(255,255,255,0.05)]"
                : "border-white/10 bg-white/[0.02] text-white/40 hover:bg-white/[0.04]"
            }`}
          >
            <div className={`w-2 h-2 rounded-full ${autoTour ? "bg-primary shadow-[0_0_8px_rgba(var(--primary-rgb),0.8)] animate-pulse" : "bg-white/20"}`} />
            <span className="text-[0.65rem] font-bold uppercase tracking-widest">{autoTour ? "Auto-Tour Active" : "Tour Paused"}</span>
          </button>
        </div>
      </div>

      <div className="relative z-10 mt-16 grid gap-12 xl:grid-cols-[1.2fr_0.8fr] items-center">
        <div className="relative aspect-square sm:aspect-video xl:aspect-square flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(var(--primary-rgb),0.03),transparent_60%)]" />

          <svg
            viewBox="0 0 640 420"
            className="relative z-10 w-full h-full max-h-[500px]"
          >
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
              <filter id="nodeGlow">
                <feGaussianBlur stdDeviation="4" result="coloredBlur"/>
                <feMerge>
                  <feMergeNode in="coloredBlur"/>
                  <feMergeNode in="SourceGraphic"/>
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
                    strokeDasharray: isActive ? [ "0, 500", "500, 0" ] : "4, 12",
                    strokeOpacity: isActive ? 1 : 0.05
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
              <circle cx="320" cy="210" r="85" fill="#020408" stroke="#FF5500" strokeOpacity="0.15" strokeWidth="2" />
              <text x="320" y="190" textAnchor="middle" className="fill-white/30 text-[10px] font-bold uppercase tracking-[0.4em]">
                System Output
              </text>
              <motion.text 
                x="320" 
                y="240" 
                textAnchor="middle" 
                className="fill-white text-[56px] font-black tracking-tighter"
                animate={{ scale: [1, 1.05, 1] }}
                transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
              >
                {loopVelocity.toFixed(1)}x
              </motion.text>
            </g>

            {stages.map((stage, index) => {
              const isActive = index === activeStage;
              return (
                <motion.g
                  key={stage.id}
                  onMouseEnter={() => {
                    setActiveStage(index);
                    setAutoTour(false);
                  }}
                  className="cursor-pointer"
                >
                  <circle cx={stage.x} cy={stage.y} r="50" fill="transparent" />
                  
                  {/* Point core */}
                  <motion.circle
                    cx={stage.x}
                    cy={stage.y}
                    r={isActive ? 10 : 5}
                    fill={isActive ? stage.color : "white"}
                    fillOpacity={isActive ? 1 : 0.15}
                    animate={{ scale: isActive ? [1, 1.4, 1] : 1 }}
                    transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
                    filter={isActive ? "url(#nodeGlow)" : undefined}
                  />
                  
                  {/* Outer rings */}
                  <motion.circle
                    cx={stage.x}
                    cy={stage.y}
                    r={isActive ? 28 : 14}
                    fill="none"
                    stroke={stage.color}
                    strokeOpacity={isActive ? 0.4 : 0}
                    strokeWidth="1.5"
                  />

                  {/* Label */}
                  <text 
                    x={stage.x} 
                    y={stage.y - 24} 
                    textAnchor="middle" 
                    className={`text-[12px] font-black uppercase tracking-widest transition-all duration-500 ${isActive ? "fill-white" : "fill-white/30"}`}
                  >
                    {stage.label}
                  </text>
                </motion.g>
              );
            })}
          </svg>
        </div>

        <div className="flex flex-col gap-10">
          <AnimatePresence mode="wait">
            <motion.div
              key={currentStage.id}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
              transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
              className="flex flex-col gap-8"
            >
              <div className="flex flex-col gap-3">
                <div className="text-[0.65rem] font-bold uppercase tracking-widest flex items-center gap-2" style={{ color: currentStage.color }}>
                  <span className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: currentStage.color }} />
                  Focused Context
                </div>
                <h5 className="text-4xl sm:text-5xl font-black text-white tracking-tight leading-none drop-shadow-md">
                  {currentStage.label}
                </h5>
                <p className="mt-2 text-[1.1rem] leading-relaxed text-zinc-300 font-light">
                  {currentStage.effect}
                </p>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
                <div className="flex flex-col gap-2 p-5 sm:p-6 rounded-2xl bg-white/[0.02] border border-white/[0.04] shadow-sm relative overflow-hidden group/box">
                  <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />
                  <span className="text-[0.6rem] font-bold text-white/30 uppercase tracking-widest flex items-center gap-2">
                    Input
                  </span>
                  <p className="text-sm sm:text-base text-white/90 font-medium">{currentStage.input}</p>
                </div>
                <div className="flex flex-col gap-2 p-5 sm:p-6 rounded-2xl bg-white/[0.02] border border-white/[0.04] shadow-sm relative overflow-hidden group/box">
                  <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />
                  <span className="text-[0.6rem] font-bold text-white/30 uppercase tracking-widest flex items-center gap-2">
                    Output
                  </span>
                  <p className="text-sm sm:text-base text-white/90 font-medium">{currentStage.output}</p>
                </div>
              </div>
            </motion.div>
          </AnimatePresence>

          <div className="mt-auto pt-10 border-t border-white/[0.04] space-y-6">
            <div className="text-[0.65rem] font-bold uppercase tracking-widest text-white/40">
              System Metrics <span className="text-[#FF5500] ml-1 font-mono bg-[#FF5500]/10 px-1.5 py-0.5 rounded">L{cycleOptions[cycleDepth]}</span>
            </div>
            <div className="space-y-5">
              {metrics.map((metric) => (
                <div key={metric.label} className="group/metric">
                  <div className="mb-2.5 flex items-center justify-between">
                    <span className="text-xs font-bold text-zinc-400 group-hover/metric:text-white transition-colors uppercase tracking-widest">{metric.label}</span>
                    <span className="font-mono text-[#FF5500] text-sm font-black drop-shadow-[0_0_8px_rgba(255,85,0,0.5)]">{metric.value}%</span>
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
