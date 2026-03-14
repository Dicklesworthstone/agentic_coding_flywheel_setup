"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { motion, AnimatePresence, useReducedMotion, useInView } from "framer-motion";

// =============================================================================
// DATA
// =============================================================================

interface Layer {
  id: number;
  title: string;
  tagline: string;
  description: string;
  input: string;
  output: string;
  mechanism: string;
  skillQuality: number;
  exampleInsight: string;
  color: string;
}

const LAYERS: Layer[] = [
  {
    id: 1,
    title: "Agent Feedback Forms",
    tagline: "Start here. No infrastructure needed.",
    description: "After an agent finishes using a tool in a real project, ask it to fill out a structured feedback survey. Feed that feedback to another agent working on the tool itself.",
    input: "One agent's opinion after using a tool",
    output: "Immediate, targeted fixes to the tool",
    mechanism: "Agent A uses tool, rates it 0-100 on multiple dimensions, suggests changes. Agent B working on the tool implements the fixes.",
    skillQuality: 35,
    exampleInsight: "\"The --format flag is confusing. 8 out of 10 agents passed json when they meant jsonl.\"",
    color: "#3b82f6",
  },
  {
    id: 2,
    title: "CASS-Powered Refinement",
    tagline: "Requires session logging.",
    description: "Instead of relying on one agent's opinion, mine session logs to find systematic patterns across many agents. 15 agents struggling with the same flag proves the flag is the problem, not the agents.",
    input: "10+ real sessions of tool usage via CASS",
    output: "Skill rewrite that fixes every discovered failure pattern",
    mechanism: "Search CASS for clarifying questions, repeated mistakes, creative workarounds, and outright failures. Feed findings to a fresh agent that rewrites the skill.",
    skillQuality: 62,
    exampleInsight: "\"Agents asked 'do you mean X or Y?' 23 times across 47 sessions. The skill's Step 3 is ambiguous.\"",
    color: "#f59e0b",
  },
  {
    id: 3,
    title: "Skills That Generate Work",
    tagline: "The system proposes its own improvements.",
    description: "The idea-wizard skill examines a project and generates improvement ideas. The optimization skill finds bottlenecks. These skills create new beads, which agents implement, which improve the tools, which make the skills more effective.",
    input: "Current project state + existing bead graph",
    output: "New beads for the highest-leverage improvements",
    mechanism: "The human curates which generated ideas are worth pursuing. The system decides what to work on next.",
    skillQuality: 84,
    exampleInsight: "\"Idea-wizard generated 30 improvement ideas, winnowed to 5. The top pick (cache-oblivious indexing) improved throughput 4.2x.\"",
    color: "#10b981",
  },
  {
    id: 4,
    title: "Skills Bundled With Installers",
    tagline: "The skill improves before the user ever sees it.",
    description: "Every tool you ship includes a pre-optimized skill baked into its installer. The skill was refined through multiple CASS cycles before shipping. New users immediately benefit from all previous refinement.",
    input: "Accumulated CASS data from all previous users",
    output: "A skill so refined that agents use the tool correctly on first contact",
    mechanism: "The installer adds the skill automatically. The agent reads it and never hits the failure modes that plagued early adopters.",
    skillQuality: 96,
    exampleInsight: "\"Zero clarifying questions in 50 new-user sessions. Every agent used --format correctly because the skill now has an explicit example.\"",
    color: "#8b5cf6",
  },
];

// =============================================================================
// COMPONENT
// =============================================================================

export function RecursiveImprovementViz() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const rm = prefersReducedMotion ?? false;

  const [activeLayer, setActiveLayer] = useState(0);
  const layer = LAYERS[activeLayer];

  // Keyboard navigation
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (!ref.current?.contains(document.activeElement) && document.activeElement !== ref.current) return;
      if (e.key === "ArrowRight") setActiveLayer(prev => Math.min(prev + 1, LAYERS.length - 1));
      if (e.key === "ArrowLeft") setActiveLayer(prev => Math.max(prev - 1, 0));
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);

  const goNext = useCallback(() => setActiveLayer(prev => Math.min(prev + 1, LAYERS.length - 1)), []);
  const goPrev = useCallback(() => setActiveLayer(prev => Math.max(prev - 1, 0)), []);

  const springTransition = rm
    ? { duration: 0 }
    : { type: "spring" as const, stiffness: 300, damping: 30 };

  return (
    <div ref={ref} tabIndex={0} className="relative my-16 overflow-hidden rounded-2xl border border-white/[0.06] bg-[#0A0D14] shadow-xl outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/40">
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.03] mix-blend-overlay pointer-events-none" />

      {/* Header */}
      <div className="relative z-10 border-b border-white/[0.04] px-5 py-5 sm:px-8">
        <h4 className="text-lg font-bold text-white tracking-tight">The Four Layers of Recursive Improvement</h4>
        <p className="mt-1 text-sm text-zinc-400">Each layer amplifies the next. Start at Layer 1, not Layer 4.</p>
      </div>

      {/* Desktop tabs */}
      <div className="relative z-10 border-b border-white/[0.04] px-5 sm:px-8 hidden sm:block">
        <div className="flex gap-1 -mb-px" role="tablist" aria-label="Improvement layers">
          {LAYERS.map((l, i) => (
            <button
              key={l.id}
              role="tab"
              aria-selected={i === activeLayer}
              aria-controls={`layer-panel-${l.id}`}
              onClick={() => setActiveLayer(i)}
              className={`relative shrink-0 px-4 py-3 text-xs font-semibold transition-colors ${
                i === activeLayer ? "text-white" : "text-zinc-500 hover:text-zinc-300"
              }`}
            >
              <span className="relative z-10 flex items-center gap-2">
                <span
                  className="flex h-5 w-5 items-center justify-center rounded-md text-[10px] font-black transition-all"
                  style={{
                    backgroundColor: i === activeLayer ? `${l.color}20` : "transparent",
                    color: i === activeLayer ? l.color : "inherit",
                    border: `1px solid ${i === activeLayer ? `${l.color}40` : "transparent"}`,
                  }}
                >
                  {i + 1}
                </span>
                {l.title}
              </span>
              {i === activeLayer && (
                <motion.div
                  layoutId="recursive-tab-indicator"
                  className="absolute bottom-0 left-0 right-0 h-[2px] rounded-full"
                  style={{
                    backgroundColor: l.color,
                    boxShadow: `0 0 12px -2px ${l.color}60`,
                  }}
                  transition={{ type: "spring", stiffness: 400, damping: 35 }}
                />
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Mobile stepper (replaces horizontal tabs) */}
      <div className="relative z-10 border-b border-white/[0.04] px-5 py-3 sm:hidden">
        <div className="flex items-center justify-between gap-3">
          <button
            onClick={goPrev}
            disabled={activeLayer === 0}
            aria-label="Previous layer"
            className="flex h-10 w-10 items-center justify-center rounded-lg border border-white/10 bg-white/[0.03] text-zinc-400 disabled:opacity-30 active:scale-95 transition-all min-h-[44px] min-w-[44px]"
          >
            &larr;
          </button>
          <div className="flex-1 text-center">
            <div className="text-xs font-bold" style={{ color: layer.color }}>Layer {activeLayer + 1} of {LAYERS.length}</div>
            <div className="text-[11px] text-zinc-400 truncate mt-0.5">{layer.title}</div>
          </div>
          <button
            onClick={goNext}
            disabled={activeLayer === LAYERS.length - 1}
            aria-label="Next layer"
            className="flex h-10 w-10 items-center justify-center rounded-lg border border-white/10 bg-white/[0.03] text-zinc-400 disabled:opacity-30 active:scale-95 transition-all min-h-[44px] min-w-[44px]"
          >
            &rarr;
          </button>
        </div>
        {/* Step dots */}
        <div className="flex justify-center gap-2 mt-2.5">
          {LAYERS.map((l, i) => (
            <button
              key={l.id}
              onClick={() => setActiveLayer(i)}
              aria-label={`Go to layer ${i + 1}`}
              className="h-2 w-2 rounded-full transition-all min-h-[44px] min-w-[44px] flex items-center justify-center"
            >
              <div
                className="h-2 w-2 rounded-full transition-all"
                style={{
                  backgroundColor: i === activeLayer ? l.color : "rgba(255,255,255,0.1)",
                  boxShadow: i === activeLayer ? `0 0 8px ${l.color}60` : "none",
                  transform: i === activeLayer ? "scale(1.5)" : "scale(1)",
                }}
              />
            </button>
          ))}
        </div>
      </div>

      {/* Layer content */}
      {isInView && (
        <div className="relative z-10 p-5 sm:p-8" id={`layer-panel-${layer.id}`} role="tabpanel">
          <AnimatePresence mode="wait">
            <motion.div
              key={layer.id}
              initial={rm ? {} : { opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={rm ? {} : { opacity: 0, y: -12 }}
              transition={springTransition}
            >
              {/* Title + tagline */}
              <div className="mb-6">
                <div className="flex items-center gap-3 mb-2">
                  <div
                    className="flex h-8 w-8 items-center justify-center rounded-lg text-sm font-black"
                    style={{
                      backgroundColor: `${layer.color}15`,
                      color: layer.color,
                      border: `1px solid ${layer.color}30`,
                      boxShadow: `0 0 16px -4px ${layer.color}30`,
                    }}
                  >
                    {activeLayer + 1}
                  </div>
                  <h5 className="text-lg sm:text-xl font-bold text-white tracking-tight">{layer.title}</h5>
                </div>
                <p className="text-sm font-medium" style={{ color: layer.color }}>{layer.tagline}</p>
              </div>

              {/* Description */}
              <p className="text-sm text-zinc-300 leading-relaxed mb-6">{layer.description}</p>

              {/* Input, Mechanism, Output flow */}
              <div className="grid gap-3 sm:grid-cols-3 mb-6">
                {[
                  { label: "Input", text: layer.input, labelColor: "text-zinc-500" },
                  { label: "Mechanism", text: layer.mechanism, labelColor: "" },
                  { label: "Output", text: layer.output, labelColor: "text-emerald-500/60" },
                ].map((card, ci) => (
                  <div
                    key={card.label}
                    className="rounded-xl border border-white/[0.06] p-4 relative backdrop-blur-sm"
                    style={{ backgroundColor: "rgba(255,255,255,0.02)" }}
                  >
                    <div
                      className={`text-[10px] font-bold uppercase tracking-[0.15em] mb-2 ${card.labelColor}`}
                      style={ci === 1 ? { color: `${layer.color}80` } : undefined}
                    >
                      {card.label}
                    </div>
                    <p className="text-xs text-zinc-300 leading-relaxed">{card.text}</p>
                    {/* Desktop arrows between cards */}
                    {ci === 1 && (
                      <>
                        <div className="hidden sm:flex absolute -left-3 top-1/2 -translate-y-1/2 h-5 w-5 items-center justify-center rounded-full bg-[#0A0D14] border border-white/10 text-zinc-600 text-[10px]">&rarr;</div>
                        <div className="hidden sm:flex absolute -right-3 top-1/2 -translate-y-1/2 h-5 w-5 items-center justify-center rounded-full bg-[#0A0D14] border border-white/10 text-zinc-600 text-[10px]">&rarr;</div>
                      </>
                    )}
                  </div>
                ))}
              </div>

              {/* Quality meter */}
              <div className="mb-6">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-semibold text-zinc-400">Skill Quality After This Layer</span>
                  <motion.span
                    className="text-sm font-black tabular-nums"
                    style={{ color: layer.color }}
                    key={`quality-${layer.id}`}
                    initial={rm ? {} : { scale: 1.3, opacity: 0 }}
                    animate={{ scale: 1, opacity: 1 }}
                    transition={springTransition}
                  >
                    {layer.skillQuality}%
                  </motion.span>
                </div>
                <div className="h-2.5 w-full rounded-full bg-white/[0.06] overflow-hidden">
                  <motion.div
                    className="h-full rounded-full"
                    style={{
                      backgroundColor: layer.color,
                      boxShadow: `0 0 12px ${layer.color}40`,
                    }}
                    initial={rm ? { width: `${layer.skillQuality}%` } : { width: 0 }}
                    animate={{ width: `${layer.skillQuality}%` }}
                    transition={rm ? { duration: 0 } : { type: "spring", stiffness: 80, damping: 18, delay: 0.15 }}
                  />
                </div>
                <div className="flex justify-between mt-1.5 text-[10px] text-zinc-600">
                  <span>Unrefined skill</span>
                  <span>Production-grade</span>
                </div>
              </div>

              {/* Example insight with glass surface */}
              <div
                className="rounded-xl border border-white/[0.06] p-4 backdrop-blur-sm"
                style={{ backgroundColor: "rgba(0,0,0,0.3)" }}
              >
                <div className="text-[10px] font-bold text-zinc-500 uppercase tracking-[0.15em] mb-2">Example Finding</div>
                <p className="text-xs text-zinc-300 italic leading-relaxed">{layer.exampleInsight}</p>
              </div>
            </motion.div>
          </AnimatePresence>
        </div>
      )}

      {/* Footer takeaway */}
      <div className="relative z-10 border-t border-white/[0.04] px-5 py-4 sm:px-8 bg-black/20">
        <p className="text-xs text-zinc-400 leading-relaxed">
          {activeLayer === 0
            ? "Layer 1 requires zero infrastructure. You can do this today, right now, with any tool and two agent sessions."
            : activeLayer === 1
            ? "Layer 2 reveals patterns no single agent would notice from its own experience alone. 15 agents struggling with the same flag proves the flag is the problem."
            : activeLayer === 2
            ? "At Layer 3, the system is not just refining how it works but actively deciding what to work on next. The human curates rather than directs."
            : "At Layer 4, new users never hit the failure modes that plagued early adopters. The improvement is invisible, baked into the installer."
          }
        </p>
      </div>
    </div>
  );
}
