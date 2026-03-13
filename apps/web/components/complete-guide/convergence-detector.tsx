"use client";

import { useCallback, useRef, useState } from "react";
import { motion, useInView, useReducedMotion } from "framer-motion";

const EXHIBIT_PANEL_CLASS =
  "my-8 overflow-hidden rounded-[28px] border border-white/[0.12] bg-[radial-gradient(circle_at_top,rgba(52,211,153,0.12),transparent_42%),linear-gradient(180deg,rgba(15,23,42,0.96),rgba(2,6,23,0.96))] p-5 sm:p-6 lg:p-7 backdrop-blur-xl shadow-[0_35px_90px_-40px_rgba(2,6,23,0.95),inset_0_1px_1px_rgba(255,255,255,0.08)]";

function getConvergencePhase(score: number) {
  if (score < 0.3) {
    return {
      label: "Major Fixes",
      color: "#ef4444",
      desc: "Wild swings and structural rewrites still dominate the conversation.",
    };
  }

  if (score < 0.55) {
    return {
      label: "Architecture",
      color: "#f59e0b",
      desc: "Boundaries are improving, but the system is still shedding big assumptions.",
    };
  }

  if (score < 0.75) {
    return {
      label: "Refinement",
      color: "#22d3ee",
      desc: "The big shape is stable; most changes are now edge cases and coverage gains.",
    };
  }

  return {
    label: "Polishing",
    color: "#34d399",
    desc: "The draft is converging and fresh passes mostly confirm, not overturn, prior work.",
  };
}

function getConvergenceVerdict(score: number) {
  if (score < 0.5) return "Keep polishing. You are still discovering meaningful shape changes.";
  if (score < 0.75) return "Close, but not there yet. Watch for oscillation and repeated re-openings.";
  if (score < 0.9) return "The plan is ready to hand off into implementation with high confidence.";
  return "Diminishing returns have started. Another polishing round is unlikely to move the architecture.";
}

const CONVERGENCE_SIGNALS = [
  { label: "Output Size Shrinking", weight: 0.35, weightLabel: "35%", color: "#38bdf8" },
  { label: "Change Velocity Slowing", weight: 0.35, weightLabel: "35%", color: "#a78bfa" },
  { label: "Content Similarity Rising", weight: 0.3, weightLabel: "30%", color: "#34d399" },
] as const;

const PRESETS = [
  { label: "Early Draft", values: [0.1, 0.1, 0.16] },
  { label: "Mid Polish", values: [0.5, 0.45, 0.5] },
  { label: "Nearly Ready", values: [0.82, 0.76, 0.86] },
  { label: "Ship It", values: [0.95, 0.95, 0.98] },
] as const;

export function ConvergenceDetector() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;
  const [values, setValues] = useState([0.3, 0.2, 0.4]);

  const score = values[0] * 0.35 + values[1] * 0.35 + values[2] * 0.3;
  const phase = getConvergencePhase(score);

  const updateSignal = useCallback((idx: number, nextValue: number) => {
    setValues((current) => {
      const next = [...current];
      next[idx] = nextValue;
      return next;
    });
  }, []);

  return (
    <div ref={ref} className={EXHIBIT_PANEL_CLASS}>
      <div className="flex flex-col gap-4 border-b border-white/10 pb-5 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <div className="text-[0.65rem] font-semibold uppercase tracking-[0.28em] text-emerald-300/70">
            Interactive Exhibit
          </div>
          <h4 className="mt-2 text-xl font-black tracking-[-0.03em] text-white sm:text-2xl">
            Convergence is measurable, not a vibe
          </h4>
          <p className="mt-2 max-w-2xl text-sm leading-relaxed text-white/60">
            Drag the signals or jump to a preset. The methodology only moves to
            code when refinement has clearly stopped changing the architecture.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <span className="text-[10px] uppercase tracking-[0.22em] text-white/35">
            Presets
          </span>
          {PRESETS.map((preset) => (
            <button
              key={preset.label}
              onClick={() => setValues([...preset.values])}
              className="min-h-[44px] rounded-full border border-white/10 bg-white/[0.04] px-4 py-2 text-xs font-semibold text-white/62 transition-colors hover:border-white/18 hover:bg-white/[0.08] hover:text-white"
            >
              {preset.label}
            </button>
          ))}
        </div>
      </div>

      <div className="mt-6 grid gap-6 xl:grid-cols-[1.08fr_0.92fr]">
        <div className="grid gap-4 md:grid-cols-3 xl:grid-cols-1">
          {CONVERGENCE_SIGNALS.map((signal, index) => (
            <motion.div
              key={signal.label}
              initial={reducedMotion ? false : { opacity: 0, y: 16 }}
              animate={isInView ? { opacity: 1, y: 0 } : undefined}
              transition={{
                type: "spring",
                stiffness: 220,
                damping: 24,
                delay: reducedMotion ? 0 : index * 0.08,
              }}
              className="rounded-[24px] border border-white/10 bg-white/[0.03] p-4"
            >
              <div className="flex items-baseline justify-between gap-3">
                <div className="text-sm font-semibold text-white/78">{signal.label}</div>
                <div className="text-[10px] uppercase tracking-[0.2em] text-white/35">
                  {signal.weightLabel}
                </div>
              </div>

              <input
                type="range"
                min={0}
                max={1}
                step={0.01}
                value={values[index]}
                onChange={(event) => updateSignal(index, Number(event.target.value))}
                aria-label={signal.label}
                aria-valuetext={`${(values[index] * 100).toFixed(0)} percent`}
                className="mt-5 h-2 w-full cursor-pointer appearance-none rounded-full bg-slate-800 [&::-webkit-slider-thumb]:h-5 [&::-webkit-slider-thumb]:w-5 [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-white/70 [&::-webkit-slider-thumb]:[background-color:var(--thumb-color)] [&::-moz-range-thumb]:h-5 [&::-moz-range-thumb]:w-5 [&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:border-2 [&::-moz-range-thumb]:border-white/70 [&::-moz-range-thumb]:[background-color:var(--thumb-color)]"
                style={{
                  background: `linear-gradient(to right, ${signal.color} ${values[index] * 100}%, #1e293b ${values[index] * 100}%)`,
                  ...({ "--thumb-color": signal.color } as React.CSSProperties),
                }}
              />

              <div className="mt-4 flex items-center justify-between gap-4">
                <div className="text-[10px] uppercase tracking-[0.2em] text-white/35">
                  Signal strength
                </div>
                <div className="text-sm font-black tabular-nums" style={{ color: signal.color }}>
                  {(values[index] * 100).toFixed(0)}%
                </div>
              </div>
            </motion.div>
          ))}
        </div>

        <motion.div
          initial={reducedMotion ? false : { opacity: 0, scale: 0.92 }}
          animate={isInView ? { opacity: 1, scale: 1 } : undefined}
          transition={{ type: "spring", stiffness: 200, damping: 24, delay: reducedMotion ? 0 : 0.18 }}
          className="rounded-[28px] border border-white/10 bg-slate-950/65 p-5"
        >
          <div className="flex flex-col gap-6 lg:flex-row lg:items-center">
            <div className="relative mx-auto h-40 w-40 shrink-0">
              <svg viewBox="0 0 120 120" className="h-full w-full -rotate-90">
                <circle cx="60" cy="60" r="48" fill="none" stroke="#1e293b" strokeWidth="10" />
                <motion.circle
                  cx="60"
                  cy="60"
                  r="48"
                  fill="none"
                  stroke={phase.color}
                  strokeWidth="10"
                  strokeLinecap="round"
                  initial={false}
                  animate={{ strokeDasharray: `${score * 302} 302` }}
                  transition={{ type: "spring", stiffness: 120, damping: 20 }}
                />
              </svg>
              <div className="absolute inset-0 flex flex-col items-center justify-center">
                <div className="text-[0.65rem] font-semibold uppercase tracking-[0.24em] text-white/35">
                  score
                </div>
                <div className="mt-1 text-4xl font-black tabular-nums" style={{ color: phase.color }}>
                  {(score * 100).toFixed(0)}
                </div>
              </div>
            </div>

            <div className="min-w-0 flex-1">
              <div className="text-[0.65rem] font-semibold uppercase tracking-[0.22em] text-white/35">
                Current phase
              </div>
              <div className="mt-2 text-2xl font-black tracking-[-0.03em]" style={{ color: phase.color }}>
                {phase.label}
              </div>
              <p className="mt-2 text-sm leading-relaxed text-white/62">{phase.desc}</p>
              <p className="mt-4 rounded-2xl border border-white/8 bg-white/[0.03] px-4 py-3 text-sm leading-relaxed text-white/70">
                {getConvergenceVerdict(score)}
              </p>
            </div>
          </div>

          <div className="mt-6">
            <div className="h-3 overflow-hidden rounded-full border border-white/10 bg-white/[0.04]">
              <motion.div
                className="h-full bg-[linear-gradient(90deg,#ef4444_0%,#f59e0b_35%,#22d3ee_70%,#34d399_100%)]"
                initial={reducedMotion ? false : { width: 0 }}
                animate={{ width: `${score * 100}%` }}
                transition={{ duration: 0.45 }}
              />
            </div>
            <div className="mt-2 flex justify-between px-1 text-[10px] uppercase tracking-[0.16em] text-white/30">
              <span>Major fixes</span>
              <span>Architecture</span>
              <span>Refinement</span>
              <span>Polishing</span>
            </div>
          </div>
        </motion.div>
      </div>
    </div>
  );
}
