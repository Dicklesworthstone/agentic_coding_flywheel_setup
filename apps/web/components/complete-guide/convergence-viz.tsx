"use client";

import { useCallback, useRef, useState } from "react";
import { motion, useInView, useReducedMotion } from "framer-motion";
import { Radar, Target } from "lucide-react";
import { cn } from "@/lib/utils";

function getConvergencePhase(s: number) {
  if (s < 0.2) return "Chaotic Expansion";
  if (s < 0.5) return "Rapid Refinement";
  if (s < 0.8) return "Incremental Tuning";
  if (s < 0.95) return "Asymptotic Convergence";
  return "Stable State (Do not touch)";
}

function getConvergenceVerdict(s: number) {
  if (s < 0.4) return "Keep polishing. High structural volatility.";
  if (s < 0.7) return "Good progress. Run 1-2 more passes.";
  if (s < 0.9) return "Ready to move on to implementation.";
  return "Diminishing returns — stop polishing, start coding.";
}

const CONVERGENCE_SIGNALS = [
  { id: "size", label: "Output Size Shrinking", weight: 0.35, weightLabel: "35%", color: "#38bdf8" },
  { id: "velocity", label: "Change Velocity Slowing", weight: 0.35, weightLabel: "35%", color: "#a78bfa" },
  { id: "similarity", label: "Content Similarity Rising", weight: 0.30, weightLabel: "30%", color: "#34d399" },
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
      angle: (i / 40) * Math.PI * 2 + (i * 137.508 * Math.PI / 180) % (Math.PI * 2),
      distance: ((i * 7 + 3) % 40) / 40,
      speed: 0.2 + ((i * 13 + 5) % 40) / 50,
      size: 2 + ((i * 11 + 7) % 30) / 10,
    })),
  );

  const score = values[0] * 0.35 + values[1] * 0.35 + values[2] * 0.30;
  const phase = getConvergencePhase(score);
  const verdict = getConvergenceVerdict(score);

  const updateSignal = useCallback((idx: number, val: number) => {
    setValues(prev => { const next = [...prev]; next[idx] = val; return next; });
  }, []);

  // Visual constants
  const center = 150;
  const maxRadius = 120;
  
  // Calculate dynamic radius based on convergence score. 
  // High score (1.0) = tight radius (converged). Low score (0.0) = wide radius (chaotic).
  const convergenceRadius = maxRadius * (1 - score * 0.85); // Never quite 0
  const rotationSpeed = (1 - score) * 10 + 2; // Fast when chaotic, slow when converged

  return (
    <div ref={ref} className="my-12 rounded-3xl border border-white/[0.06] bg-[#05070a] shadow-2xl transition-all duration-500 hover:border-primary/20 overflow-hidden relative group/viz">
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.02] mix-blend-overlay pointer-events-none" />
      
      {/* HEADER */}
      <div className="relative z-10 flex flex-col sm:flex-row items-start sm:items-center justify-between p-6 sm:p-8 border-b border-white/[0.04] bg-white/[0.01] backdrop-blur-md">
        <div>
          <div className="text-[0.65rem] font-bold text-white/30 uppercase tracking-widest mb-2 flex items-center gap-2">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse shadow-[0_0_8px_rgba(52,211,153,0.8)]" />
            Interactive Simulator
          </div>
          <div className="flex items-center gap-3">
            <span className="flex h-8 w-8 items-center justify-center rounded-xl bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 shadow-inner">
              <Radar className="h-4 w-4" />
            </span>
            <h4 className="text-xl sm:text-2xl font-black text-white tracking-tight">Convergence Detection</h4>
          </div>
          <p className="mt-2 text-sm text-zinc-400 font-light max-w-xl">
            Drag the sliders or pick a preset to see how beads tighten into a stable state before implementation begins.
          </p>
        </div>

        {/* PRESETS */}
        <div className="mt-6 sm:mt-0 flex flex-wrap gap-2 p-1.5 bg-black/40 rounded-2xl border border-white/[0.05] shadow-inner">
          <span className="text-[0.6rem] text-white/30 self-center mx-2 uppercase tracking-widest font-bold">Presets</span>
          {([
            { label: "Draft", vals: [0.1, 0.1, 0.15] },
            { label: "Mid", vals: [0.5, 0.45, 0.5] },
            { label: "Ready", vals: [0.8, 0.75, 0.85] },
            { label: "Ship", vals: [0.95, 0.95, 0.98] },
          ] as const).map((preset) => (
            <button
              key={preset.label}
              onClick={() => setValues([...preset.vals])}
              className="rounded-xl border border-transparent px-3 py-1.5 text-xs font-bold transition-all duration-300 hover:bg-white/[0.06] hover:text-white/90 text-white/50 active:scale-95 hover:border-white/10"
            >
              {preset.label}
            </button>
          ))}
        </div>
      </div>

      <div className="relative z-10 grid grid-cols-1 lg:grid-cols-[1.2fr_1fr] gap-8 p-6 sm:p-8">
        
        {/* Sliders Area */}
        <div className="flex flex-col justify-center space-y-8 bg-[#0A0D14] p-6 sm:p-8 rounded-2xl border border-white/[0.04] shadow-inner relative overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />
          
          {CONVERGENCE_SIGNALS.map((signal, idx) => (
            <div key={signal.label} className="relative z-10">
              <div className="flex items-baseline justify-between mb-3">
                <span className="text-sm font-bold text-white/90">{signal.label}</span>
                <span className="text-[0.65rem] text-white/40 uppercase tracking-widest font-bold bg-white/[0.03] px-2 py-0.5 rounded-md border border-white/[0.05]">Weight: {signal.weightLabel}</span>
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
                    className="w-full h-2 rounded-full appearance-none cursor-ew-resize [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:h-5 [&::-webkit-slider-thumb]:w-5 [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-[var(--thumb-color)] [&::-webkit-slider-thumb]:shadow-[0_0_15px_var(--thumb-color)] [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-[#0A0D14] hover:[&::-webkit-slider-thumb]:scale-110 [&::-webkit-slider-thumb]:transition-transform relative z-10"
                    style={{
                      background: `linear-gradient(to right, ${signal.color} ${values[idx] * 100}%, rgba(255,255,255,0.05) ${values[idx] * 100}%)`,
                      // eslint-disable-next-line @typescript-eslint/no-explicit-any
                      ["--thumb-color" as any]: signal.color,
                    }}
                  />
                </div>
                <div className="w-12 text-right text-sm font-mono font-black" style={{ color: signal.color }}>
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
              style={{ backgroundColor: score > 0.8 ? "#34d399" : score > 0.5 ? "#a78bfa" : "#38bdf8" }}
              animate={{ 
                scale: 1 + score * 1.5,
                opacity: score * 0.4 + 0.1
              }}
              transition={{ duration: 0.5 }}
            />
            
            <Target className="absolute h-10 w-10 text-white/5" />

            {/* Particle System */}
            {isInView && !reducedMotion && (
              <motion.div
                className="absolute inset-0 origin-center"
                animate={{ rotate: 360 }}
                transition={{ duration: rotationSpeed, ease: "linear", repeat: Infinity }}
              >
                {particles.map(p => {
                  // Calculate position based on current convergence radius + inherent variance
                  const currentRad = (p.distance * convergenceRadius) + (convergenceRadius * 0.2);
                  const x = center + Math.cos(p.angle) * currentRad;
                  const y = center + Math.sin(p.angle) * currentRad;
                  
                  // Color changes based on how tight the convergence is
                  const color = score > 0.8 ? "#34d399" : score > 0.5 ? "#a78bfa" : "#38bdf8";

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
                      }}
                      animate={{
                        left: `calc(50% + ${x - center}px)`,
                        top: `calc(50% + ${y - center}px)`,
                        backgroundColor: color,
                        boxShadow: `0 0 ${p.size * 2}px ${color}`,
                      }}
                      transition={{ type: "spring", stiffness: 150, damping: 20, mass: 0.8 }}
                    />
                  );
                })}
              </motion.div>
            )}
            
            {/* Fallback for reduced motion */}
            {(reducedMotion || !isInView) && (
              <div className="absolute inset-0 flex items-center justify-center">
                <div 
                  className="rounded-full border-2 border-emerald-500/30 flex items-center justify-center"
                  style={{ width: convergenceRadius * 2, height: convergenceRadius * 2, transition: 'all 0.5s ease-out' }}
                />
              </div>
            )}
          </div>

          {/* Status HUD Footer */}
          <div className="p-5 sm:p-6 bg-white/[0.01] border-t border-white/[0.05] flex flex-col gap-4 backdrop-blur-md relative z-10">
            <div className="flex items-center justify-between">
              <span className="text-[0.65rem] uppercase tracking-widest text-white/40 font-bold">Overall Convergence</span>
              <span className={cn(
                "text-lg font-black tracking-tight",
                score > 0.8 ? "text-emerald-400 drop-shadow-[0_0_10px_rgba(52,211,153,0.5)]" : score > 0.5 ? "text-violet-400 drop-shadow-[0_0_10px_rgba(167,139,250,0.5)]" : "text-sky-400 drop-shadow-[0_0_10px_rgba(56,189,248,0.5)]"
              )}>
                {(score * 100).toFixed(1)}%
              </span>
            </div>

            <div className="h-2 w-full bg-black/40 rounded-full overflow-hidden border border-white/[0.05] shadow-inner">
              <motion.div
                className="h-full bg-gradient-to-r from-sky-400 via-violet-400 to-emerald-400"
                animate={{ width: `${score * 100}%` }}
                transition={{ duration: 0.5, type: "spring", bounce: 0 }}
              />
            </div>

            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 pt-2">
              <span className={cn(
                "text-sm font-bold tracking-tight",
                score > 0.8 ? "text-emerald-400" : score > 0.5 ? "text-violet-400" : "text-sky-400"
              )}>{phase}</span>
              <span className="text-xs text-white/50 font-light">{verdict}</span>
            </div>
          </div>
        </div>

      </div>
    </div>
  );
}
