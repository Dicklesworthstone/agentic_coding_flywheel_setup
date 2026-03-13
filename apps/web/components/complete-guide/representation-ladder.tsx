"use client";

import { useCallback, useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "framer-motion";
import { Bug, Repeat } from "lucide-react";
import { Hl } from "@/components/complete-guide/guide-components";

const EXHIBIT_PANEL_CLASS =
  "my-16 overflow-hidden rounded-[3rem] border border-white/[0.03] bg-[#020408] p-8 sm:p-12 lg:p-16 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9)]";

const LADDER_LAYERS = [
  {
    id: "plan",
    label: "Plan Space",
    color: "#22d3ee",
    width: 95,
    cost: "1x",
    desc: "Fix the prose, rethink the architecture, and keep the blast radius confined to reasoning.",
  },
  {
    id: "bead",
    label: "Bead Space",
    color: "#a78bfa",
    width: 70,
    cost: "5x",
    desc: "Revise boundaries, dependencies, and acceptance criteria across executable work packets.",
  },
  {
    id: "code",
    label: "Code Space",
    color: "#f97316",
    width: 45,
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
      <div className="flex flex-col gap-10 border-b border-white/[0.03] pb-12 lg:flex-row lg:items-start lg:justify-between">
        <div className="max-w-2xl">
          <div className="text-[0.65rem] font-black uppercase tracking-[0.4em] text-cyan-400 opacity-60 flex items-center gap-3">
            <div className="w-8 h-px bg-cyan-400/30" />
            Failure Economics
          </div>
          <h4 className="mt-6 text-3xl font-black tracking-[-0.04em] text-white sm:text-4xl lg:text-5xl leading-[1.1]">
            Where you catch the bug determines the rework bill
          </h4>
          <p className="mt-8 text-[1.1rem] leading-relaxed text-zinc-400 font-extralight opacity-80">
            Inject the same mistake at different layers. The deeper it lands,
            the more downstream structure has already hardened around it. 
            This is the <Hl>Law of Rework Escalation</Hl>.
          </p>
        </div>

        <div className="flex flex-col items-start lg:items-end gap-6">
          {bugLevel !== null && (
            <motion.button
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              onClick={handleReset}
              className="flex items-center gap-3 px-6 py-3 rounded-2xl border border-white/10 bg-white/[0.02] text-[0.7rem] font-black uppercase tracking-[0.2em] text-white/60 hover:text-white transition-all duration-500"
            >
              <Repeat className="h-3 w-3" />
              Reset Simulation
            </motion.button>
          )}
        </div>
      </div>

      <div className="mt-16 grid gap-12 lg:grid-cols-[1.2fr_0.8fr] items-center">
        <div className="flex flex-col gap-6">
          {LADDER_LAYERS.map((layer, index) => {
            const isBugSource = bugLevel === index;
            const isCascade = bugLevel !== null && index > bugLevel;

            return (
              <motion.div
                key={layer.id}
                initial={reducedMotion ? false : { opacity: 0, x: -40 }}
                animate={isInView ? { opacity: 1, x: 0 } : undefined}
                transition={{
                  type: "spring",
                  stiffness: 100,
                  damping: 25,
                  delay: reducedMotion ? 0 : index * 0.15,
                }}
                className="group/layer flex items-center gap-6"
              >
                <div className="flex-1">
                  <div 
                    className="relative rounded-3xl border transition-all duration-700 overflow-hidden"
                    style={{
                      width: `${layer.width}%`,
                      height: '90px',
                      borderColor: isBugSource 
                        ? '#ef4444' 
                        : isCascade 
                          ? '#f59e0b' 
                          : 'rgba(255,255,255,0.03)',
                      background: isBugSource 
                        ? 'rgba(239, 68, 68, 0.05)' 
                        : isCascade 
                          ? 'rgba(245, 158, 11, 0.05)' 
                          : 'rgba(255,255,255,0.01)'
                    }}
                  >
                    <div className="absolute inset-0 bg-grid-pattern opacity-[0.02]" />
                    
                    <div className="relative h-full flex items-center justify-between px-8">
                      <div className="flex flex-col gap-1">
                        <div className="flex items-center gap-3">
                          <span className={`text-[0.65rem] font-black uppercase tracking-[0.2em] ${isBugSource ? 'text-red-400' : isCascade ? 'text-amber-400' : 'text-white/20'}`}>
                            {layer.id} layer
                          </span>
                          {isBugSource && <div className="w-1.5 h-1.5 rounded-full bg-red-500 animate-ping" />}
                        </div>
                        <span className={`text-xl font-black tracking-tight ${isBugSource ? 'text-red-400' : isCascade ? 'text-amber-400' : 'text-white'}`}>
                          {layer.label}
                        </span>
                      </div>

                      <div className="text-right">
                        <span className="text-[0.6rem] font-black text-white/20 uppercase tracking-[0.3em]">Price</span>
                        <div className={`text-3xl font-black tracking-tighter ${isBugSource ? 'text-red-400' : isCascade ? 'text-amber-400' : 'text-white/40'}`}>
                          {layer.cost}
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <div className="w-48 shrink-0">
                  <AnimatePresence mode="wait">
                    {bugLevel === null ? (
                      <motion.button
                        key="inject"
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        exit={{ opacity: 0 }}
                        onClick={() => handleBugClick(index)}
                        className="w-full flex items-center justify-center gap-3 px-5 py-3 rounded-2xl border border-white/5 bg-white/[0.02] text-[0.65rem] font-black uppercase tracking-[0.1em] text-white/40 hover:bg-red-500/10 hover:border-red-500/20 hover:text-red-400 transition-all duration-500"
                      >
                        <Bug className="h-3.5 w-3.5" />
                        Inject Leak
                      </motion.button>
                    ) : isBugSource ? (
                      <motion.div
                        key="source"
                        initial={{ opacity: 0, scale: 0.9 }}
                        animate={{ opacity: 1, scale: 1 }}
                        className="text-red-400 text-[0.65rem] font-black uppercase tracking-[0.2em] text-center"
                      >
                        Epicenter
                      </motion.div>
                    ) : isCascade ? (
                      <motion.div
                        key="cascade"
                        initial={{ opacity: 0, scale: 0.9 }}
                        animate={{ opacity: 1, scale: 1 }}
                        className="text-amber-400 text-[0.65rem] font-black uppercase tracking-[0.2em] text-center"
                      >
                        Impacted
                      </motion.div>
                    ) : null}
                  </AnimatePresence>
                </div>
              </motion.div>
            );
          })}
        </div>

        <div className="flex flex-col gap-8">
          <div className="p-8 rounded-[2.5rem] bg-white/[0.01] border border-white/[0.03]">
            <span className="text-[0.6rem] font-black text-white/20 uppercase tracking-[0.4em]">Rework Intuition</span>
            <div className="mt-8 flex flex-col gap-6">
              {[
                { l: "Plan Space", t: "Fixes are pure reasoning. Zero code churn." },
                { l: "Bead Space", t: "Fixes rewrite orchestration. High coordination cost." },
                { l: "Code Space", t: "Fixes pay the double-tax: implementation + cleanup." },
              ].map((item, i) => (
                <div key={i} className="flex flex-col gap-1">
                  <span className="text-[0.7rem] font-bold text-white/40 tracking-wide">{item.l}</span>
                  <p className="text-sm text-zinc-400 font-extralight leading-relaxed">{item.t}</p>
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
              className="p-10 rounded-[2.5rem] bg-[#0a0c10] border border-white/[0.05] shadow-inner"
            >
              <span className="text-[0.6rem] font-black text-primary/60 uppercase tracking-[0.5em] block mb-6">Strategic Takeaway</span>
              <p className="text-[1.1rem] leading-relaxed text-zinc-300 font-extralight italic">
                {bugLevel === null &&
                  "Planning earns its keep because it is the cheapest layer for global reasoning. Press 'Inject' on any layer to visualize the cost cascade."}
                {bugLevel === 0 &&
                  "Architectural shift at the prose layer. Nothing downstream has solidified. The project remains liquid and extremely cheap to pivot."}
                {bugLevel === 1 &&
                  "Expensive pivot. Executable memory is now misaligned. Task boundaries, dependency edges, and priorities must be manually re-validated."}
                {bugLevel === 2 &&
                  "Catastrophic failure. The system has already paid to embody the mistake in binary. Every line of code written must now be un-written and re-verified."}
              </p>
            </motion.div>
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
