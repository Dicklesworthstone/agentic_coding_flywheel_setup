"use client";

import React, { useRef, useState, useCallback } from "react";
import { motion, useInView, useReducedMotion } from "framer-motion";
import { CheckCircle2 } from "lucide-react";
import { COMPLETE_GUIDE_MODELS } from "@/lib/complete-guide";
import { cn } from "@/lib/utils";

const EXHIBIT_PANEL_CLASS =
  "my-12 overflow-hidden rounded-3xl border border-white/[0.06] bg-[#05070a] shadow-2xl relative group/viz transition-all duration-500 hover:border-primary/20";

type PlanDimensionId =
  | "architecture"
  | "workflow"
  | "edgeCases"
  | "novelty"
  | "execution";
type PlanModelId = "gpt" | "claude" | "gemini" | "grok";

const PLAN_DIMENSIONS = [
  { id: "architecture", label: "Architecture" },
  { id: "workflow", label: "Workflow coverage" },
  { id: "edgeCases", label: "Failure modes" },
  { id: "novelty", label: "Novel ideas" },
  { id: "execution", label: "Execution readiness" },
] as const satisfies ReadonlyArray<{ id: PlanDimensionId; label: string }>;

const PLAN_MODEL_DATA = [
  {
    id: "gpt",
    label: COMPLETE_GUIDE_MODELS.primaryPlanner,
    color: "#FF5500",
    role: "Global arbiter",
    strengths: ["System-wide coherence", "Best-of-all-worlds synthesis"],
    blindSpot: "Can over-smooth contradictions instead of solving them.",
    contributions: { execution: 60, workflow: 70, architecture: 90, edgeCases: 65, novelty: 65 },
  },
  {
    id: "claude",
    label: COMPLETE_GUIDE_MODELS.claudePlanner,
    color: "#a78bfa",
    role: "Implementation realist",
    strengths: ["Execution detail", "Sharp structural edits"],
    blindSpot: "Sometimes deletes context it considers 'obvious'.",
    contributions: { execution: 95, workflow: 75, architecture: 80, edgeCases: 70, novelty: 60 },
  },
  {
    id: "gemini",
    label: COMPLETE_GUIDE_MODELS.googlePlanner,
    color: "#FFBD2E",
    role: "Coverage expander",
    strengths: ["Alternative framings", "Missed edge cases"],
    blindSpot: "Can drift off-topic if intent isn't rigorously anchored.",
    contributions: { execution: 70, workflow: 95, architecture: 65, edgeCases: 80, novelty: 75 },
  },
  {
    id: "grok",
    label: COMPLETE_GUIDE_MODELS.xaiPlanner,
    color: "#FFFFFF",
    role: "Assumption stress-test",
    strengths: ["Counterintuitive options", "Pressure-testing assumptions"],
    blindSpot: "Prone to suggesting overly clever, non-standard solutions.",
    contributions: { execution: 65, workflow: 80, architecture: 75, edgeCases: 95, novelty: 90 },
  },
] as const;

const PLAN_REFINEMENT_LABELS = [
  "Raw merge",
  "First integration",
  "Revision pressure",
  "Fresh-eyes polish",
  "Converged draft",
] as const;

export function PlanEvolutionStudio() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;
  const [enabledModels, setEnabledModels] = useState<Record<PlanModelId, boolean>>({
    gpt: true,
    claude: true,
    gemini: true,
    grok: true,
  });
  const [refinementRound, setRefinementRound] = useState(2);

  const selectedModels = PLAN_MODEL_DATA.filter((model) => enabledModels[model.id]);
  const dimensionScores = PLAN_DIMENSIONS.map((dimension) => {
    const bestSelectedContribution = selectedModels.reduce(
      (maxValue, model) => Math.max(maxValue, model.contributions[dimension.id]),
      0,
    );
    const diversityBonus = selectedModels.length > 1 ? (selectedModels.length - 1) * 4 : 0;
    const roundBonus = refinementRound * 5;
    return {
      ...dimension,
      value: Math.min(100, bestSelectedContribution + diversityBonus + roundBonus),
    };
  });
  const totalScore = Math.round(
    dimensionScores.reduce((sum, score) => sum + score.value, 0) /
      dimensionScores.length,
  );
  const missingNotes = PLAN_MODEL_DATA.filter((model) => !enabledModels[model.id]).map(
    (model) => model.blindSpot,
  );

  const toggleModel = useCallback((modelId: PlanModelId) => {
    setEnabledModels((current) => {
      const activeCount = Object.values(current).filter(Boolean).length;
      if (current[modelId] && activeCount === 1) {
        return current;
      }
      return { ...current, [modelId]: !current[modelId] };
    });
  }, []);

  return (
    <div ref={ref} className={EXHIBIT_PANEL_CLASS}>
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.02] mix-blend-overlay pointer-events-none" />
      <div className="absolute top-0 right-0 w-[600px] h-[600px] bg-[radial-gradient(circle_at_top_right,rgba(34,211,238,0.03),transparent_70%)] pointer-events-none" />

      <div className="relative z-10 flex flex-col gap-6 border-b border-white/[0.04] bg-white/[0.01] p-6 sm:p-8 backdrop-blur-md lg:flex-row lg:items-end lg:justify-between">
        <div>
          <div className="text-[0.65rem] font-bold uppercase tracking-widest text-[#FF5500]/80 flex items-center gap-2 mb-2">
            <span className="w-1.5 h-1.5 rounded-full bg-[#FF5500] animate-pulse shadow-[0_0_8px_rgba(255,85,0,0.8)]" />
            Interactive Studio
          </div>
          <h4 className="text-xl font-black tracking-tight text-white sm:text-2xl">
            Best-of-all-worlds synthesis
          </h4>
          <p className="mt-2 max-w-2xl text-sm leading-relaxed text-zinc-400 font-light">
            Toggle proposal plans on and off, then drag the refinement dial.
            The point is not “many models” in the abstract; it is that
            complementary strengths plus fresh-round revision produce a plan
            that is harder to surprise later.
          </p>
        </div>

        <label className="block rounded-2xl border border-white/[0.05] bg-[#0A0D14] px-5 py-4 shadow-inner min-w-[280px]">
          <div className="flex items-center justify-between gap-6 text-[0.65rem] font-bold uppercase tracking-widest text-white/40">
            <span>Refinement round</span>
            <span className="text-white/80">{PLAN_REFINEMENT_LABELS[refinementRound]}</span>
          </div>
          <div className="relative mt-4 group/slider">
            <input
              type="range"
              min={0}
              max={4}
              step={1}
              value={refinementRound}
              onChange={(event) => setRefinementRound(Number(event.target.value))}
              aria-label="Refinement round"
              className="h-2 w-full cursor-ew-resize appearance-none rounded-full bg-white/10 [&::-webkit-slider-thumb]:h-5 [&::-webkit-slider-thumb]:w-5 [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-[#0A0D14] [&::-webkit-slider-thumb]:bg-[#FF5500] [&::-webkit-slider-thumb]:shadow-[0_0_15px_rgba(255,85,0,0.6)] hover:[&::-webkit-slider-thumb]:scale-110 [&::-webkit-slider-thumb]:transition-transform relative z-10"
              style={{
                background: `linear-gradient(to right, rgba(255,85,0,0.5) ${(refinementRound / 4) * 100}%, rgba(255,255,255,0.05) ${(refinementRound / 4) * 100}%)`
              }}
            />
          </div>
        </label>
      </div>

      <div className="relative z-10 mt-2 grid gap-6 p-6 sm:p-8 xl:grid-cols-[1.05fr_0.95fr]">
        <div className="grid gap-5 sm:grid-cols-2">
          {PLAN_MODEL_DATA.map((model, index) => {
            const enabled = enabledModels[model.id];
            return (
              <motion.button
                key={model.id}
                type="button"
                aria-pressed={enabled}
                onClick={() => toggleModel(model.id)}
                initial={reducedMotion ? false : { opacity: 0, y: 18 }}
                animate={isInView ? { opacity: 1, y: 0 } : undefined}
                transition={{
                  type: "spring",
                  stiffness: 220,
                  damping: 22,
                  delay: reducedMotion ? 0 : index * 0.06,
                }}
                className={cn(
                  "rounded-2xl border p-5 text-left transition-all duration-300 relative overflow-hidden group/model",
                  enabled
                    ? "border-white/[0.08] bg-white/[0.02] shadow-lg"
                    : "border-white/[0.03] bg-transparent opacity-50 hover:opacity-80"
                )}
                style={{
                  boxShadow: enabled ? `inset 0 1px 1px rgba(255,255,255,0.05), 0 0 30px ${model.color}0A` : undefined
                }}
              >
                {enabled && (
                  <div className="absolute inset-0 bg-gradient-to-br opacity-10 pointer-events-none transition-opacity duration-500 group-hover/model:opacity-20" style={{ backgroundImage: `linear-gradient(to bottom right, ${model.color}40, transparent)` }} />
                )}
                <div className="flex items-start justify-between gap-4 relative z-10">
                  <div>
                    <div
                      className="text-[0.65rem] font-bold uppercase tracking-widest flex items-center gap-2"
                      style={{ color: model.color }}
                    >
                      {enabled && <span className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: model.color }} />}
                      {model.role}
                    </div>
                    <div className="mt-1.5 text-lg font-black tracking-tight text-white group-hover/model:text-white transition-colors">
                      {model.label}
                    </div>
                  </div>
                  <div
                    className={cn(
                      "rounded-full px-3 py-1 text-[0.65rem] font-bold uppercase tracking-widest transition-colors",
                      enabled ? "text-white" : "text-white/40"
                    )}
                    style={{
                      backgroundColor: enabled ? `${model.color}15` : "rgba(255,255,255,0.02)",
                      border: `1px solid ${enabled ? `${model.color}30` : "rgba(255,255,255,0.05)"}`,
                    }}
                  >
                    {enabled ? "Included" : "Muted"}
                  </div>
                </div>

                <div className="mt-5 flex flex-wrap gap-2 relative z-10">
                  {model.strengths.map((strength) => (
                    <span
                      key={strength}
                      className="rounded-lg border px-3 py-1.5 text-[0.7rem] font-medium text-white/70"
                      style={{ borderColor: enabled ? `${model.color}20` : "rgba(255,255,255,0.05)", backgroundColor: enabled ? `${model.color}0A` : "transparent" }}
                    >
                      {strength}
                    </span>
                  ))}
                </div>
              </motion.button>
            );
          })}
        </div>

        <div className="space-y-5">
          <div className="rounded-2xl border border-white/[0.05] bg-[#0A0D14] p-6 shadow-lg">
            <div className="flex items-center justify-between gap-4">
              <div>
                <div className="text-[0.65rem] font-bold uppercase tracking-widest text-white/40">
                  Hybrid Plan Quality
                </div>
                <div className="mt-1 text-4xl font-black tracking-tighter text-white drop-shadow-md">
                  {totalScore}%
                </div>
              </div>
              <div className="rounded-xl border border-[#FF5500]/20 bg-[#FF5500]/10 px-5 py-3 text-right shadow-inner">
                <div className="text-[0.65rem] font-bold uppercase tracking-widest text-[#FF5500]/70">
                  Active Inputs
                </div>
                <div className="mt-1 text-2xl font-black text-[#FF5500]">
                  {selectedModels.length}
                </div>
              </div>
            </div>

            <div className="relative mt-8 h-56 overflow-hidden rounded-2xl border border-white/[0.04] bg-[#020408] shadow-inner">
              <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(34,211,238,0.1),transparent_60%)] pointer-events-none" />
              
              {[0, 1, 2].map((sheetLayer) => (
                <motion.div
                  key={`sheet-${sheetLayer}`}
                  className="absolute left-6 right-6 rounded-2xl border border-white/[0.05] bg-[#0A0D14] shadow-md"
                  style={{
                    top: `${26 + sheetLayer * 12}px`,
                    bottom: `${24 - sheetLayer * 2}px`,
                    transform: `translateX(${sheetLayer * 8}px)`,
                    opacity: 0.24 + sheetLayer * 0.18,
                  }}
                  initial={false}
                  animate={{ rotate: sheetLayer === 2 ? (refinementRound - 2) * 0.45 : 0 }}
                  transition={{ type: "spring", stiffness: 160, damping: 18 }}
                />
              ))}

              <motion.div
                className="absolute inset-[20px] rounded-2xl border border-white/[0.08] bg-[#0A0D14] p-5 shadow-xl backdrop-blur-md"
                initial={false}
                animate={{ y: [12, 6, 0, -2, -4][refinementRound] }}
                transition={{ type: "spring", stiffness: 180, damping: 20 }}
              >
                <div className="flex flex-wrap gap-2">
                  {selectedModels.map((model) => (
                    <span
                      key={model.id}
                      className="rounded-full px-2.5 py-1 text-[0.6rem] font-bold uppercase tracking-widest text-white shadow-sm"
                      style={{ backgroundColor: `${model.color}15`, border: `1px solid ${model.color}30` }}
                    >
                      {model.label}
                    </span>
                  ))}
                </div>

                <div className="mt-6 space-y-3">
                  {Array.from({ length: 6 }, (_, lineIndex) => (
                    <motion.div
                      key={`line-${lineIndex}`}
                      className="h-1.5 rounded-full bg-white/10"
                      initial={false}
                      animate={{
                        width: `${82 - lineIndex * 8 + refinementRound * 3}%`,
                        opacity: lineIndex === 0 ? 1 : 0.4 + refinementRound * 0.1,
                      }}
                      transition={{ type: "spring", stiffness: 150, damping: 18 }}
                    />
                  ))}
                </div>

                <div className="mt-6 rounded-xl border border-[#FF5500]/20 bg-[#FF5500]/10 px-4 py-3 text-sm leading-relaxed text-[#FF5500] font-medium">
                  Round {refinementRound + 1}:{" "}
                  <span className="font-light text-[#FF5500]/80">
                    {refinementRound < 2
                      ? "The plan is still absorbing strengths and closing obvious gaps."
                      : refinementRound < 4
                        ? "Fresh rounds are sanding down contradictions and exposing edge cases."
                        : "You are now near the point where improvements are incremental."}
                  </span>
                </div>
              </motion.div>
            </div>
          </div>

          <div className="rounded-2xl border border-white/[0.05] bg-[#0A0D14] p-6 shadow-lg">
            <div className="text-[0.65rem] font-bold uppercase tracking-widest text-white/40 mb-5">
              What the hybrid gains
            </div>
            <div className="space-y-4">
              {dimensionScores.map((dimension) => (
                <div key={dimension.id}>
                  <div className="mb-1.5 flex items-center justify-between text-xs font-bold text-white/60 uppercase tracking-wide">
                    <span>{dimension.label}</span>
                    <span className="font-mono text-white/90">{dimension.value}%</span>
                  </div>
                  <div className="h-2 rounded-full bg-[#020408] border border-white/[0.04] shadow-inner overflow-hidden">
                    <motion.div
                      className="h-full bg-gradient-to-r from-[#FF5500] via-zinc-400 to-[#FFBD2E] shadow-[0_0_10px_rgba(255,85,0,0.5)]"
                      initial={reducedMotion ? { width: `${dimension.value}%` } : { width: 0 }}
                      animate={{ width: `${dimension.value}%` }}
                      transition={{ duration: 0.75, type: "spring", bounce: 0 }}
                    />
                  </div>
                </div>
              ))}
            </div>

            <div className="mt-6 rounded-xl border border-white/[0.05] bg-[#020408] p-5 shadow-inner">
              <div className="text-[0.65rem] font-bold uppercase tracking-widest text-white/30 mb-3">
                If you mute a proposal
              </div>
              <div className="space-y-2 text-sm leading-relaxed text-zinc-400 font-light">
                {missingNotes.length > 0 ? (
                  missingNotes.map((note) => <p key={note} className="flex items-start gap-2"><span className="text-[#FF5F56] mt-0.5">•</span>{note}</p>)
                ) : (
                  <p className="flex items-center gap-2 text-[#27C93F] font-medium">
                    <CheckCircle2 className="h-4 w-4" /> All proposal sources are active. Best-of-all-worlds.
                  </p>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
