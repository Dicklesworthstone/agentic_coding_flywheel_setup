"use client";

import { Bug, Repeat } from "lucide-react";
import { useCallback, useRef, useState } from "react";
import { Hl } from "@/components/complete-guide/guide-components";
import { AnimatePresence, motion, useInView, useReducedMotion } from "@/components/motion";

const EXHIBIT_PANEL_CLASS =
  "my-16 overflow-hidden rounded-[2rem] sm:rounded-[3rem] border border-white/[0.03] bg-[#020408] p-6 sm:p-12 lg:p-16 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9)]";

const LADDER_LAYERS = [
  {
    id: "plan",
    label: "Plan Space",
    color: "#FFFFFF",
    cost: "1x",
    desc: "Fix the prose, rethink the architecture, and keep the blast radius confined to reasoning.",
  },
  {
    id: "bead",
    label: "Bead Space",
    color: "#FFBD2E",
    cost: "5x",
    desc: "Revise boundaries, dependencies, and acceptance criteria across executable work packets.",
  },
  {
    id: "code",
    label: "Code Space",
    color: "#FF5500",
    cost: "25x",
    desc: "Rewrite implementation, fix tests, debug regressions, and pay the price of already-made commitments.",
  },
] as const;

export function RepresentationLadder() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;
  const [bugLevel, setBugLevel] = useState<number | null>(null);

  const handleBugClick = useCallback((level: number) => setBugLevel(level), []);
  const handleReset = useCallback(() => setBugLevel(null), []);

  return (
    <div ref={ref} className={EXHIBIT_PANEL_CLASS}>
      <div className="flex flex-col gap-8 border-b border-white/[0.05] pb-10 sm:gap-10 sm:pb-12 lg:flex-row lg:items-start lg:justify-between">
        <div className="max-w-2xl">
          <div className="text-xs font-black uppercase tracking-[0.4em] text-[#FF5500] opacity-90 flex items-center gap-3">
            <div className="w-8 h-px bg-[#FF5500]/30" />
            Rework Cost
          </div>
          <h4 className="mt-6 font-serif text-[1.5rem] font-normal leading-[1.12] tracking-[-0.008em] text-white sm:text-[1.875rem]">
            Where you catch the bug determines the rework bill
          </h4>
          <p className="mt-6 text-[1.1rem] leading-relaxed text-zinc-400 font-light sm:mt-8">
            Inject the same mistake at each layer in turn. The later the layer, the more work has
            already been built on the mistake, and <Hl>the more of it you have to redo</Hl>.
          </p>
        </div>

        <div className="flex flex-col items-start lg:items-end gap-6">
          {bugLevel !== null && (
            <motion.button
              type="button"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              onClick={handleReset}
              className="flex items-center gap-3 px-6 py-3 rounded-2xl border border-white/10 bg-white/[0.02] text-xs font-black uppercase tracking-[0.2em] text-zinc-300 hover:text-white transition duration-500 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-[#FF5500]/60"
            >
              <Repeat className="h-3 w-3" />
              Reset Simulation
            </motion.button>
          )}
        </div>
      </div>

      {/* The ladder takes the full width so each layer's name and price sit
          on one line (side by side with the notes, the cards were too narrow
          and "Plan Space" broke over two lines); the notes follow below. */}
      <div className="mt-10 flex flex-col gap-10 sm:mt-14 sm:gap-12">
        <div className="flex flex-col gap-5 sm:gap-6">
          {LADDER_LAYERS.map((layer, index) => {
            const isBugSource = bugLevel === index;
            // Catching the mistake at a layer means every earlier layer already
            // carries it. Later layers have not been built yet, so nothing there
            // is affected (a plan-layer catch touches only the plan).
            const isCascade = bugLevel !== null && index < bugLevel;

            return (
              <motion.div
                key={layer.id}
                // Never flip `initial` to false after hydration: the server
                // already rendered the hidden state, and framer then leaves
                // it hidden. Reduced motion reveals at once instead.
                initial={{ opacity: 0, x: -20 }}
                animate={isInView || reducedMotion ? { opacity: 1, x: 0 } : undefined}
                transition={{
                  type: "spring",
                  stiffness: 100,
                  damping: 25,
                  delay: reducedMotion ? 0 : index * 0.15,
                }}
                className="group/layer flex flex-col sm:flex-row gap-3 sm:gap-6 items-stretch sm:items-center"
              >
                <div className="flex-1 min-w-0 w-full">
                  <div
                    className="relative rounded-3xl border transition duration-700 overflow-hidden h-full"
                    style={{
                      borderColor: isBugSource
                        ? "#FF5500"
                        : isCascade
                          ? "#FFBD2E"
                          : "rgba(255,255,255,0.06)",
                      background: isBugSource
                        ? "rgba(255, 85, 0, 0.05)"
                        : isCascade
                          ? "rgba(255, 189, 46, 0.05)"
                          : "rgba(255,255,255,0.01)",
                    }}
                  >
                    <div className="absolute inset-0 noise-overlay opacity-[0.02] mix-blend-overlay pointer-events-none" />

                    <div className="relative z-10 flex flex-row items-center justify-between px-5 py-4 gap-4 h-full sm:px-6 sm:py-5">
                      <div className="flex min-w-0 items-center gap-3">
                        <span
                          className={`whitespace-nowrap text-xl font-bold tracking-tight transition-colors ${isBugSource ? "text-[#FF5500]" : isCascade ? "text-[#FFBD2E]" : "text-white"}`}
                        >
                          {layer.label}
                        </span>
                        {isBugSource && (
                          <div className="w-1.5 h-1.5 shrink-0 rounded-full bg-[#FF5500] animate-ping" />
                        )}
                      </div>
                      <div className="shrink-0 text-right">
                        <span className="text-xs font-black uppercase tracking-[0.3em] text-zinc-500 block mb-1">
                          Price
                        </span>
                        <div
                          className={`text-3xl font-black tracking-tighter tabular-nums transition-colors ${isBugSource ? "text-[#FF5500]" : isCascade ? "text-[#FFBD2E]" : "text-zinc-400"}`}
                        >
                          {layer.cost}
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <div className="w-full sm:w-48 shrink-0 flex items-center justify-center">
                  <AnimatePresence mode="wait">
                    {bugLevel === null ? (
                      <motion.button
                        key="inject"
                        type="button"
                        aria-label={`Inject bug in ${layer.label}`}
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        exit={{ opacity: 0 }}
                        onClick={() => handleBugClick(index)}
                        className="w-full flex items-center justify-center gap-3 px-5 py-3 rounded-2xl border border-white/10 bg-white/[0.02] text-xs font-black uppercase tracking-[0.1em] text-zinc-300 hover:bg-[#FF5500]/10 hover:border-[#FF5500]/20 hover:text-[#FF5500] transition duration-500 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-[#FF5500]/60"
                      >
                        <Bug className="h-3.5 w-3.5" />
                        Inject Bug
                      </motion.button>
                    ) : isBugSource ? (
                      <motion.div
                        key="source"
                        initial={{ opacity: 0, scale: 0.9 }}
                        animate={{ opacity: 1, scale: 1 }}
                        className="text-[#FF5500] text-xs font-black uppercase tracking-[0.2em] text-center"
                      >
                        Bug Here
                      </motion.div>
                    ) : isCascade ? (
                      <motion.div
                        key="cascade"
                        initial={{ opacity: 0, scale: 0.9 }}
                        animate={{ opacity: 1, scale: 1 }}
                        className="text-[#FFBD2E] text-xs font-black uppercase tracking-[0.2em] text-center"
                      >
                        Affected
                      </motion.div>
                    ) : null}
                  </AnimatePresence>
                </div>
              </motion.div>
            );
          })}
        </div>

        <div className="grid gap-6 sm:gap-8 lg:grid-cols-2">
          <div className="p-6 sm:p-8 rounded-[2rem] sm:rounded-[2.5rem] bg-white/[0.01] border border-white/[0.05]">
            <span className="text-xs font-black text-zinc-400 uppercase tracking-[0.4em]">
              Cost of a Fix
            </span>
            <div className="mt-6 flex flex-col gap-5 sm:mt-8 sm:gap-6">
              {[
                { l: "Plan Space", t: "A fix is an edit to the plan. No code changes." },
                { l: "Bead Space", t: "A fix means rewriting beads and their dependencies, which costs coordination time." },
                { l: "Code Space", t: "A fix costs twice: you write the new code and clean up the old." },
              ].map((item, i) => (
                <div key={i} className="flex flex-col gap-1">
                  <span className="text-xs font-bold text-zinc-300 tracking-wide">
                    {item.l}
                  </span>
                  <p className="text-sm text-zinc-400 font-light leading-relaxed">{item.t}</p>
                </div>
              ))}
            </div>
          </div>

          <AnimatePresence mode="wait">
            <motion.div
              key={bugLevel ?? "default"}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
              transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
              className="p-6 sm:p-10 rounded-[2rem] sm:rounded-[2.5rem] bg-white/[0.01] border border-white/[0.05] shadow-inner"
            >
              <span className="text-xs font-black text-[#FF5500] uppercase tracking-[0.5em] block mb-6">
                Takeaway
              </span>
              <p className="text-[1.1rem] leading-relaxed text-zinc-300 font-light italic">
                {bugLevel === null &&
                  "The plan is the cheapest place to reason about the whole system. Press Inject Bug on any layer to see what a fix there costs."}
                {bugLevel === 0 &&
                  "Caught in the plan. No beads or code have been built on the mistake yet, so the fix is an edit to the prose."}
                {bugLevel === 1 &&
                  "Caught in the beads. The beads now encode the mistake, so task boundaries, dependency edges, and priorities all have to be checked again by hand."}
                {bugLevel === 2 &&
                  "Caught in the code. Agents have already implemented the mistake, so the code built on it has to be rewritten and tested again."}
              </p>
            </motion.div>
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
