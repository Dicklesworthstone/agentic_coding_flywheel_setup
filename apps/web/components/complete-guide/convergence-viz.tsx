"use client";

import { Radar, Target } from "lucide-react";
import { useCallback, useRef, useState } from "react";
import { motion, useInView, useReducedMotion } from "@/components/motion";
import { cn } from "@/lib/utils";

// Thresholds and signals follow the guide: finalize at 0.75+, diminishing
// returns above 0.90, keep iterating below 0.50.
const READY_THRESHOLD = 0.75;

function getConvergencePhase(s: number) {
  if (s < 0.2) return "Major Fixes";
  if (s < 0.5) return "Architecture";
  if (s < READY_THRESHOLD) return "Refinement";
  if (s < 0.95) return "Polishing";
  return "Steady State";
}

function getConvergenceVerdict(s: number) {
  if (s < 0.5) return "Keep polishing. The structure still changes a lot between rounds.";
  if (s < READY_THRESHOLD) return "Good progress. Run one or two more rounds.";
  if (s < 0.9) return "Ready to move on to implementation.";
  return "Diminishing returns. Stop polishing and start implementing.";
}

const CONVERGENCE_SIGNALS = [
  {
    id: "output",
    label: "Output Size Shrinking",
    weight: 0.35,
    weightLabel: "35%",
    color: "#A1A1AA",
  },
  {
    id: "velocity",
    label: "Change Velocity Slowing",
    weight: 0.35,
    weightLabel: "35%",
    color: "#FF5500",
  },
  {
    id: "similarity",
    label: "Content Similarity Rising",
    weight: 0.3,
    weightLabel: "30%",
    color: "#FFBD2E",
  },
] as const;

const CONVERGENCE_PRESETS = [
  { label: "Draft", vals: [0.1, 0.12, 0.1] },
  { label: "Mid", vals: [0.55, 0.6, 0.5] },
  { label: "Ready", vals: [0.8, 0.78, 0.8] },
  { label: "Ship", vals: [0.95, 0.96, 0.95] },
] as const;

export function ConvergenceViz() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: false, margin: "-50px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;

  // 0.0 to 1.0
  const [values, setValues] = useState([0.3, 0.2, 0.4]);
  const [particles] = useState(() =>
    Array.from({ length: 40 }, (_, i) => ({
      id: i,
      angle: (i / 40) * Math.PI * 2 + (((i * 137.508 * Math.PI) / 180) % (Math.PI * 2)),
      distance: ((i * 7 + 3) % 40) / 40,
      speed: 0.2 + ((i * 13 + 5) % 40) / 50,
      size: 2 + ((i * 11 + 7) % 30) / 10,
      signalIdx: i % CONVERGENCE_SIGNALS.length,
    })),
  );

  const score = CONVERGENCE_SIGNALS.reduce(
    (total, signal, idx) => total + values[idx] * signal.weight,
    0,
  );
  const phase = getConvergencePhase(score);
  const verdict = getConvergenceVerdict(score);

  const updateSignal = useCallback((idx: number, val: number) => {
    setValues((prev) => {
      const next = [...prev];
      next[idx] = val;
      return next;
    });
  }, []);

  // Visual constants
  const center = 150;
  // Sized so the widest (score 0) cloud still fits the ~250px-tall canvas.
  const maxRadius = 100;

  // Calculate dynamic radius based on convergence score.
  // High score (1.0) = tight radius (converged). Low score (0.0) = wide radius (chaotic).
  const radiusAt = (s: number) => maxRadius * (1 - s * 0.85); // Never quite 0
  const convergenceRadius = radiusAt(score);
  // Particles sit between 0.2R and ~1.18R, so this is the cloud's outer edge.
  const spreadRadius = convergenceRadius * 1.18;
  // The ring the cloud has to shrink inside before the plan counts as ready.
  const readyRadius = radiusAt(READY_THRESHOLD) * 1.18 + 4;
  const isReady = score >= READY_THRESHOLD;
  // Seconds per revolution: a quick churn when chaotic, a slow settle when converged.
  const rotationSpeed = 6 + score * 14;

  return (
    <div
      ref={ref}
      className="my-12 rounded-3xl border border-white/[0.06] bg-[#05070a] shadow-2xl transition duration-500 hover:border-primary/20 overflow-hidden relative group/viz"
    >
      <div className="absolute inset-0 noise-overlay opacity-[0.02] mix-blend-overlay pointer-events-none" />

      {/* HEADER */}
      <div className="relative z-10 flex flex-col lg:flex-row items-start lg:items-center justify-between gap-6 p-6 sm:p-8 border-b border-white/[0.04] bg-white/[0.01] backdrop-blur-md">
        <div className="min-w-0">
          <div className="text-xs font-bold text-zinc-500 uppercase tracking-widest mb-2 flex items-center gap-2">
            <span className="w-1.5 h-1.5 rounded-full bg-[#FFBD2E]" />
            Interactive Simulator
          </div>
          <div className="flex items-center gap-3">
            <span className="flex h-8 w-8 items-center justify-center rounded-xl bg-[#FFBD2E]/10 text-[#FFBD2E] border border-[#FFBD2E]/20 shadow-inner">
              <Radar className="h-4 w-4" />
            </span>
            <h3 className="font-serif text-[1.5rem] font-normal leading-[1.12] tracking-[-0.008em] text-white sm:text-[1.875rem]">
              Convergence Detection
            </h3>
          </div>
          <p className="mt-2 text-sm text-zinc-400 font-light max-w-xl">
            Drag the sliders or pick a preset to see how the weighted convergence score tells you
            when the beads are ready for implementation.
          </p>
        </div>

        {/* PRESETS */}
        <div className="flex shrink-0 items-center gap-1 sm:gap-2 p-1.5 bg-black/40 rounded-2xl border border-white/[0.05] shadow-inner">
          <span className="text-xs text-zinc-500 mx-1.5 sm:mx-2 uppercase tracking-wider sm:tracking-widest font-bold">
            Presets
          </span>
          {CONVERGENCE_PRESETS.map((preset) => {
            const active = preset.vals.every((v, i) => v === values[i]);
            return (
              <button
                key={preset.label}
                type="button"
                aria-pressed={active}
                onClick={() => setValues([...preset.vals])}
                className={cn(
                  "whitespace-nowrap rounded-xl border px-2.5 sm:px-3 py-1.5 text-xs font-bold transition duration-300 active:scale-95 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/60",
                  active
                    ? "border-white/10 bg-white/[0.08] text-white"
                    : "border-transparent text-zinc-400 hover:border-white/10 hover:bg-white/[0.06] hover:text-zinc-100",
                )}
              >
                {preset.label}
              </button>
            );
          })}
        </div>
      </div>

      <div className="relative z-10 grid grid-cols-1 lg:grid-cols-[1.2fr_1fr] gap-8 p-6 sm:p-8">
        {/* Sliders Area */}
        <div className="flex flex-col justify-center space-y-7 sm:space-y-8 bg-[#0A0D14] p-5 sm:p-8 rounded-2xl border border-white/[0.04] shadow-inner relative overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />

          {CONVERGENCE_SIGNALS.map((signal, idx) => (
            <div key={signal.label} className="relative z-10">
              <div className="flex items-baseline justify-between gap-3 mb-3">
                <span className="min-w-0 text-sm font-bold text-white/90">{signal.label}</span>
                <span className="shrink-0 whitespace-nowrap text-xs text-zinc-400 uppercase tracking-wider font-bold bg-white/[0.03] px-2 py-0.5 rounded-md border border-white/[0.05]">
                  Weight: {signal.weightLabel}
                </span>
              </div>
              <div className="relative flex items-center gap-5">
                <div className="relative flex-1 group/slider">
                  <input
                    type="range"
                    min={0}
                    max={1}
                    step={0.01}
                    value={values[idx]}
                    onChange={(e) => updateSignal(idx, Number(e.target.value))}
                    aria-label={signal.label}
                    className="w-full h-2 rounded-full appearance-none cursor-ew-resize [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:h-6 [&::-webkit-slider-thumb]:w-6 [&::-moz-range-thumb]:h-6 [&::-moz-range-thumb]:w-6 [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-[var(--thumb-color)] [&::-webkit-slider-thumb]:shadow-[0_0_15px_var(--thumb-color)] [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-[#0A0D14] hover:[&::-webkit-slider-thumb]:scale-110 [&::-webkit-slider-thumb]:transition-transform relative z-10"
                    style={{
                      background: `linear-gradient(to right, ${signal.color} ${values[idx] * 100}%, rgba(255,255,255,0.05) ${values[idx] * 100}%)`,
                      // eslint-disable-next-line @typescript-eslint/no-explicit-any
                      ["--thumb-color" as any]: signal.color,
                    }}
                  />
                </div>
                <div
                  className="w-12 text-right text-sm font-mono font-black"
                  style={{ color: signal.color }}
                >
                  {(values[idx] * 100).toFixed(0)}%
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* Physics Visualizer Area */}
        <div className="relative bg-[#020408] rounded-2xl border border-white/[0.05] overflow-hidden flex flex-col min-h-[350px] shadow-lg">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(255,255,255,0.02),transparent_70%)] pointer-events-none" />

          {/* SVG Canvas */}
          <div className="flex-1 relative flex items-center justify-center min-h-[250px] overflow-hidden">
            {/* Background glowing orb representing the target state */}
            <motion.div
              className="absolute w-20 h-20 rounded-full blur-[30px] pointer-events-none mix-blend-screen"
              style={{
                backgroundColor:
                  score >= READY_THRESHOLD ? "#FFBD2E" : score > 0.5 ? "#FF5500" : "#A1A1AA",
              }}
              animate={{
                scale: 1 + score * 1.5,
                opacity: score * 0.4 + 0.1,
              }}
              transition={{ duration: 0.5 }}
            />

            <Target className="absolute h-10 w-10 text-white/5" />

            {/* Ready zone: the cloud has to shrink inside this ring before the
                beads count as ready, so convergence reads as the cloud
                tightening past a fixed line. */}
            <div
              className={cn(
                "absolute rounded-full border border-dashed pointer-events-none transition-colors duration-500",
                isReady ? "border-[#FFBD2E]/60" : "border-white/20",
              )}
              style={{ width: readyRadius * 2, height: readyRadius * 2 }}
            >
              <span
                className={cn(
                  "absolute left-1/2 -top-2.5 -translate-x-1/2 whitespace-nowrap rounded-full bg-[#020408] px-2 text-xs font-bold uppercase leading-5 tracking-widest transition-colors duration-500",
                  isReady ? "text-[#FFBD2E]" : "text-zinc-400",
                )}
              >
                Ready zone
              </span>
            </div>

            {/* The cloud's current outer edge */}
            <motion.div
              className="absolute rounded-full border pointer-events-none"
              initial={false}
              animate={{
                width: spreadRadius * 2,
                height: spreadRadius * 2,
                borderColor: isReady
                  ? "rgba(255,189,46,0.35)"
                  : score > 0.5
                    ? "rgba(255,85,0,0.3)"
                    : "rgba(161,161,170,0.25)",
              }}
              transition={
                reducedMotion ? { duration: 0 } : { type: "spring", stiffness: 150, damping: 20 }
              }
            />

            {/* Particle System. Reduced motion keeps the cloud, still and
                without the orbit, so the size change is still visible. */}
            {(isInView || reducedMotion) && (
              <motion.div
                className="absolute inset-0 origin-center"
                animate={reducedMotion ? { rotate: 0 } : { rotate: 360 }}
                transition={
                  reducedMotion
                    ? { duration: 0 }
                    : { duration: rotationSpeed, ease: "linear", repeat: Infinity }
                }
              >
                {particles.map((p) => {
                  const signalScore = values[p.signalIdx];
                  const color =
                    score >= READY_THRESHOLD ? "#FFBD2E" : score > 0.5 ? "#FF5500" : "#A1A1AA";
                  const currentRad = p.distance * convergenceRadius + convergenceRadius * 0.2;
                  const x = center + Math.cos(p.angle) * currentRad;
                  const y = center + Math.sin(p.angle) * currentRad;
                  const particleOpacity = 0.35 + signalScore * 0.65;

                  return (
                    <motion.div
                      key={p.id}
                      className="absolute rounded-full"
                      style={{
                        left: `calc(50% + ${x - center}px)`,
                        top: `calc(50% + ${y - center}px)`,
                        width: p.size,
                        height: p.size,
                        backgroundColor: color,
                        boxShadow: `0 0 ${p.size * 2}px ${color}`,
                        opacity: particleOpacity,
                      }}
                      animate={{
                        left: `calc(50% + ${x - center}px)`,
                        top: `calc(50% + ${y - center}px)`,
                        backgroundColor: color,
                        boxShadow: `0 0 ${p.size * 2}px ${color}`,
                        opacity: particleOpacity,
                      }}
                      transition={
                        reducedMotion
                          ? { duration: 0 }
                          : { type: "spring", stiffness: 150, damping: 20, mass: 0.8 }
                      }
                    />
                  );
                })}
              </motion.div>
            )}
          </div>

          {/* Status HUD Footer */}
          <div className="p-5 sm:p-6 bg-white/[0.01] border-t border-white/[0.05] flex flex-col gap-4 backdrop-blur-md relative z-10">
            <div className="flex items-center justify-between">
              <span className="text-xs uppercase tracking-widest text-zinc-400 font-bold">
                Overall Convergence
              </span>
              <span
                className={cn(
                  "text-lg font-black tracking-tight",
                  score >= READY_THRESHOLD
                    ? "text-[#FFBD2E] drop-shadow-[0_0_10px_rgba(255,189,46,0.5)]"
                    : score > 0.5
                      ? "text-[#FF5500] drop-shadow-[0_0_10px_rgba(255,85,0,0.5)]"
                      : "text-zinc-400 drop-shadow-[0_0_10px_rgba(161,161,170,0.5)]",
                )}
              >
                {(score * 100).toFixed(1)}%
              </span>
            </div>

            <div className="h-2 w-full bg-black/40 rounded-full overflow-hidden border border-white/[0.05] shadow-inner">
              <motion.div
                className="h-full bg-gradient-to-r from-zinc-500 via-[#FF5500] to-[#FFBD2E]"
                animate={{ width: `${score * 100}%` }}
                transition={{ duration: 0.5, type: "spring", bounce: 0 }}
              />
            </div>

            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-x-4 gap-y-2 pt-2">
              <span
                className={cn(
                  "shrink-0 whitespace-nowrap text-sm font-bold tracking-tight",
                  score >= READY_THRESHOLD
                    ? "text-[#FFBD2E]"
                    : score > 0.5
                      ? "text-[#FF5500]"
                      : "text-zinc-400",
                )}
              >
                {phase}
              </span>
              <span className="text-xs text-zinc-400 sm:text-right">{verdict}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
