"use client";

import { useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "framer-motion";
import { ArrowRight, Boxes, CheckCircle2, FileText, ShieldAlert, AlertOctagon, AlertTriangle, Zap } from "lucide-react";
import { cn } from "@/lib/utils";

const EXHIBIT_PANEL_CLASS =
  "my-12 overflow-hidden rounded-3xl border border-white/[0.06] bg-[#05070a] shadow-2xl relative group/viz";

type TranslationMode = "thin" | "rich";
type ConceptId = "upload" | "search" | "admin" | "tests";
type TranslationBeadId = "br-101" | "br-102" | "br-103";

type PlanConcept = {
  id: ConceptId;
  label: string;
  color: string;
  insight: string;
  planLine: string;
  mapsTo: readonly TranslationBeadId[];
};

type BeadDetail = {
  label: string;
  value: string;
  concepts: readonly ConceptId[];
};

type TranslationBead = {
  id: TranslationBeadId;
  title: string;
  color: string;
  dependsOn: readonly TranslationBeadId[];
  coverage: readonly ConceptId[];
  thinSummary: string;
  thinRisk: string;
  richDetails: readonly BeadDetail[];
};

const PLAN_TO_BEAD_CONCEPTS: readonly PlanConcept[] = [
  {
    id: "upload",
    label: "Upload workflow",
    color: "#22d3ee",
    insight: "Chunking, parser retries, telemetry, and failure surfacing all need to survive the translation.",
    planLine:
      "Users can upload large PDFs, recover from parser failures, and see when ingestion stalls.",
    mapsTo: ["br-101", "br-103"],
  },
  {
    id: "search",
    label: "Search behavior",
    color: "#a78bfa",
    insight: "Ranking rules, typo tolerance, empty states, and query explanations cannot be left implicit.",
    planLine:
      "Search needs ranking, typo tolerance, filters, and clear explanations for why a result matched.",
    mapsTo: ["br-102"],
  },
  {
    id: "admin",
    label: "Operator controls",
    color: "#34d399",
    insight: "Admins need recovery affordances, auditability, and visibility into degraded ingestion paths.",
    planLine:
      "Operators need to inspect stuck jobs, requeue safely, and understand blast radius before touching data.",
    mapsTo: ["br-102", "br-103"],
  },
  {
    id: "tests",
    label: "Verification",
    color: "#f59e0b",
    insight: "Happy path, edge cases, and failure fixtures have to be part of the bead, not an afterthought.",
    planLine:
      "Every workflow ships with unit tests, end-to-end coverage, and detailed logs for postmortems.",
    mapsTo: ["br-101", "br-102", "br-103"],
  },
] as const;

const TRANSLATED_BEADS: readonly TranslationBead[] = [
  {
    id: "br-101",
    title: "Upload and Parse Pipeline",
    color: "#22d3ee",
    dependsOn: [],
    coverage: ["upload", "tests"],
    thinSummary: "Build upload flow",
    thinRisk: "Fresh agents still have to guess retry policy, file constraints, and observability.",
    richDetails: [
      {
        label: "Outcome",
        value: "Validate uploads, chunk large files, parse them, and emit ingestion telemetry.",
        concepts: ["upload"],
      },
      {
        label: "Acceptance",
        value: "Reject malware, cap retries, persist parse status, and record timing for every stage.",
        concepts: ["upload", "tests"],
      },
      {
        label: "Tests",
        value: "Fixture matrix for malformed PDFs, retry exhaustion, and upload resume edge cases.",
        concepts: ["tests"],
      },
    ],
  },
  {
    id: "br-102",
    title: "Search Index and Query UX",
    color: "#a78bfa",
    dependsOn: ["br-101"],
    coverage: ["search", "admin", "tests"],
    thinSummary: "Implement search",
    thinRisk: "Query semantics, ranking behavior, and operator-facing debug detail are underspecified.",
    richDetails: [
      {
        label: "Outcome",
        value: "Index parsed documents, support ranked retrieval, and explain match reasons in the UI.",
        concepts: ["search"],
      },
      {
        label: "Admin hooks",
        value: "Expose index freshness, failed document counts, and reindex controls for operators.",
        concepts: ["admin"],
      },
      {
        label: "Tests",
        value: "Coverage for typo tolerance, empty result states, filter combinations, and stale index warnings.",
        concepts: ["tests"],
      },
    ],
  },
  {
    id: "br-103",
    title: "Ingestion Failure Dashboard",
    color: "#34d399",
    dependsOn: ["br-101"],
    coverage: ["upload", "admin", "tests"],
    thinSummary: "Add admin dashboard",
    thinRisk: "Without context, a dashboard becomes decoration instead of an operational recovery surface.",
    richDetails: [
      {
        label: "Outcome",
        value: "Surface failed ingestions, stalled jobs, and per-file parse diagnostics in one operational view.",
        concepts: ["upload", "admin"],
      },
      {
        label: "Recovery path",
        value: "Allow safe requeue actions with audit trails and blast-radius summaries before retry.",
        concepts: ["admin"],
      },
      {
        label: "Tests",
        value: "E2E coverage for retry, audit logging, and incorrect operator input during incident handling.",
        concepts: ["tests"],
      },
    ],
  },
] as const;

const MODE_COPY: Record<
  TranslationMode,
  {
    label: string;
    description: string;
    readiness: number;
    guesswork: string;
    takeaway: string;
  }
> = {
  thin: {
    label: "Thin beads",
    description: "Titles survive, but the real operational nuance falls on the floor.",
    readiness: 46,
    guesswork: "High guesswork",
    takeaway: "Fresh agents still have to rediscover critical requirements during implementation.",
  },
  rich: {
    label: "Context-rich beads",
    description: "Each bead carries the why, what, failure modes, and verification plan needed to execute.",
    readiness: 94,
    guesswork: "Low guesswork",
    takeaway: "Fresh agents can execute without improvising architecture or silently dropping intent.",
  },
};

export function PlanToBeadsViz() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;
  const [mode, setMode] = useState<TranslationMode>("rich");
  const [selectedConceptId, setSelectedConceptId] = useState<ConceptId>("upload");

  const selectedConcept =
    PLAN_TO_BEAD_CONCEPTS.find((concept) => concept.id === selectedConceptId) ??
    PLAN_TO_BEAD_CONCEPTS[0];
  const highlightedBeads = new Set<TranslationBeadId>(selectedConcept.mapsTo);
  const readinessScore = MODE_COPY[mode].readiness;
  const ambiguityCount = mode === "rich" ? 1 : 6;

  return (
    <div ref={ref} className={EXHIBIT_PANEL_CLASS}>
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.02] mix-blend-overlay pointer-events-none" />
      
      <div className="relative z-10 flex flex-col gap-6 border-b border-white/[0.04] bg-white/[0.01] p-6 sm:p-8 backdrop-blur-md lg:flex-row lg:items-center lg:justify-between">
        <div>
          <div className="text-[0.65rem] font-bold uppercase tracking-widest text-primary/70 mb-2 flex items-center gap-2">
            <span className="w-1.5 h-1.5 rounded-full bg-primary animate-pulse shadow-[0_0_8px_rgba(var(--primary-rgb),0.8)]" />
            Interactive Exhibit
          </div>
          <h4 className="text-xl font-black tracking-tight text-white sm:text-2xl">
            A plan is only useful once it becomes executable memory
          </h4>
          <p className="mt-2 max-w-2xl text-sm leading-relaxed text-zinc-400 font-light">
            Pick a concept from the plan, then compare what survives into a thin
            bead versus a context-rich bead. The gap is the source of most
            swarm confusion.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2 rounded-2xl border border-white/[0.05] bg-black/40 p-1.5 shadow-inner">
          {(["thin", "rich"] as const).map((nextMode) => (
            <button
              key={nextMode}
              type="button"
              aria-pressed={mode === nextMode}
              onClick={() => setMode(nextMode)}
              className={cn(
                "min-h-[44px] rounded-xl px-5 py-2 text-xs font-bold transition-all duration-500",
                mode === nextMode
                  ? "bg-primary text-black shadow-[0_0_20px_rgba(var(--primary-rgb),0.3)]"
                  : "text-white/40 hover:bg-white/[0.03] hover:text-white/80",
              )}
            >
              {MODE_COPY[nextMode].label}
            </button>
          ))}
        </div>
      </div>

      <div className="relative z-10 mt-2 grid gap-6 p-6 sm:p-8 xl:grid-cols-[0.95fr_1.05fr]">
        <div className="space-y-6">
          <div className="rounded-2xl border border-white/[0.05] bg-[#0A0D14] p-6 shadow-lg relative overflow-hidden">
            <div className="absolute inset-0 bg-gradient-to-br from-white/[0.01] to-transparent pointer-events-none" />
            <div className="relative z-10 flex items-center gap-2 text-[0.65rem] font-bold uppercase tracking-widest text-white/40">
              <FileText className="h-3.5 w-3.5" />
              Human Plan
            </div>

            <div className="relative z-10 mt-6 space-y-3">
              {PLAN_TO_BEAD_CONCEPTS.map((concept, index) => {
                const isSelected = concept.id === selectedConceptId;
                return (
                  <motion.button
                    key={concept.id}
                    type="button"
                    aria-pressed={isSelected}
                    onClick={() => setSelectedConceptId(concept.id)}
                    initial={reducedMotion ? false : { opacity: 0, y: 16 }}
                    animate={isInView ? { opacity: 1, y: 0 } : undefined}
                    transition={{
                      type: "spring",
                      stiffness: 220,
                      damping: 24,
                      delay: reducedMotion ? 0 : index * 0.06,
                    }}
                    className={cn(
                      "w-full rounded-xl border p-4 text-left transition-all duration-300 relative overflow-hidden group/btn",
                      isSelected
                        ? "border-primary/30 bg-primary/5 shadow-[0_0_20px_rgba(var(--primary-rgb),0.1)]"
                        : "border-white/[0.04] bg-white/[0.01] hover:border-white/[0.1] hover:bg-white/[0.03]",
                    )}
                  >
                    <div className="flex items-start justify-between gap-4 relative z-10">
                      <div>
                        <div
                          className="text-[0.65rem] font-bold uppercase tracking-widest flex items-center gap-2"
                          style={{ color: concept.color }}
                        >
                          <span className="w-1 h-1 rounded-full" style={{ backgroundColor: concept.color }} />
                          Concept {index + 1}
                        </div>
                        <div className="mt-1.5 text-base font-bold tracking-tight text-white group-hover/btn:text-primary transition-colors">
                          {concept.label}
                        </div>
                      </div>
                      <div
                        className="rounded-full px-3 py-1 text-[0.65rem] font-bold uppercase tracking-widest flex items-center gap-1"
                        style={{
                          color: concept.color,
                          backgroundColor: `${concept.color}15`,
                          border: `1px solid ${concept.color}30`,
                        }}
                      >
                        {concept.mapsTo.length} bead{concept.mapsTo.length > 1 ? "s" : ""}
                      </div>
                    </div>
                    <p className="mt-3 text-sm leading-relaxed text-zinc-400 font-light relative z-10">{concept.planLine}</p>
                  </motion.button>
                );
              })}
            </div>
          </div>

          <motion.div
            initial={reducedMotion ? false : { opacity: 0, y: 16 }}
            animate={isInView ? { opacity: 1, y: 0 } : undefined}
            transition={{ type: "spring", stiffness: 220, damping: 24, delay: reducedMotion ? 0 : 0.18 }}
            className="rounded-2xl border p-6 relative overflow-hidden shadow-xl"
            style={{
              borderColor: `${selectedConcept.color}30`,
              backgroundColor: `${selectedConcept.color}0A`,
            }}
          >
            <div className="absolute top-0 right-0 w-32 h-32 blur-[40px] opacity-20 pointer-events-none" style={{ backgroundColor: selectedConcept.color }} />
            <div className="relative z-10 text-[0.65rem] font-bold uppercase tracking-widest" style={{ color: selectedConcept.color }}>
              Selected Concept Insight
            </div>
            <div className="relative z-10 mt-3 text-xl font-black tracking-tight text-white">
              {selectedConcept.label}
            </div>
            <p className="relative z-10 mt-3 text-sm leading-relaxed text-zinc-300 font-light">
              {selectedConcept.insight}
            </p>
            <div className="relative z-10 mt-5 inline-flex items-center gap-2 rounded-xl border bg-[#05070A]/80 px-4 py-2.5 text-[0.65rem] font-bold uppercase tracking-widest backdrop-blur-sm shadow-inner" style={{ color: selectedConcept.color, borderColor: `${selectedConcept.color}20` }}>
              <Boxes className="h-4 w-4" />
              Flows into {selectedConcept.mapsTo.join(" & ")}
            </div>
          </motion.div>
        </div>

        <div className="relative rounded-2xl border border-white/[0.05] bg-[#0A0D14] p-6 shadow-lg overflow-hidden">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top_right,rgba(34,211,238,0.05),transparent_50%),radial-gradient(ellipse_at_bottom_left,rgba(167,139,250,0.05),transparent_50%)] pointer-events-none" />

          <div className="relative z-10 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
            <div>
              <div className="text-[0.65rem] font-bold uppercase tracking-widest text-white/40">
                Translation Output
              </div>
              <div className="mt-1 text-lg font-black tracking-tight text-white">
                {MODE_COPY[mode].label}
              </div>
            </div>
            <div className={cn(
              "inline-flex items-center gap-2 rounded-xl border bg-black/40 px-4 py-2.5 text-[0.65rem] font-bold uppercase tracking-widest shadow-inner",
              mode === "rich" ? "border-primary/20 text-primary" : "border-[#FF5F56]/20 text-[#FF5F56]"
            )}>
              {mode === "rich" ? <CheckCircle2 className="h-4 w-4" /> : <AlertOctagon className="h-4 w-4" />}
              {MODE_COPY[mode].guesswork}
            </div>
          </div>

          <div className="relative z-10 mt-8 space-y-4">
            {TRANSLATED_BEADS.map((bead, index) => {
              const isHighlighted = highlightedBeads.has(bead.id);
              return (
                <div key={bead.id}>
                  <motion.article
                    initial={reducedMotion ? false : { opacity: 0, x: 18 }}
                    animate={isInView ? { opacity: 1, x: 0 } : undefined}
                    transition={{
                      type: "spring",
                      stiffness: 220,
                      damping: 24,
                      delay: reducedMotion ? 0 : index * 0.08,
                    }}
                    className={cn(
                      "rounded-xl border p-5 transition-all duration-500",
                      isHighlighted
                        ? "border-primary/30 bg-primary/5 shadow-[0_0_20px_rgba(var(--primary-rgb),0.1)]"
                        : "border-white/[0.04] bg-white/[0.01]",
                    )}
                  >
                    <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                      <div>
                        <div
                          className="text-[0.65rem] font-bold uppercase tracking-widest flex items-center gap-2"
                          style={{ color: bead.color }}
                        >
                          <span className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: bead.color }} />
                          {bead.id}
                        </div>
                        <div className="mt-1.5 text-lg font-bold tracking-tight text-white">
                          {bead.title}
                        </div>
                      </div>

                      <div className="flex flex-wrap gap-2">
                        {bead.dependsOn.length > 0 ? (
                          bead.dependsOn.map((dependency) => (
                            <span
                              key={dependency}
                              className="rounded-full border border-white/10 bg-white/[0.03] px-3 py-1 text-[0.65rem] font-bold uppercase tracking-widest text-white/50"
                            >
                              deps: {dependency}
                            </span>
                          ))
                        ) : (
                          <span className="rounded-full border border-[#27C93F]/20 bg-[#27C93F]/10 px-3 py-1 text-[0.65rem] font-bold uppercase tracking-widest text-[#27C93F]">
                            root bead
                          </span>
                        )}
                        {isHighlighted && (
                          <span
                            className="rounded-full px-3 py-1 text-[0.65rem] font-bold uppercase tracking-widest"
                            style={{
                              color: bead.color,
                              backgroundColor: `${bead.color}15`,
                              border: `1px solid ${bead.color}30`,
                            }}
                          >
                            carries concept
                          </span>
                        )}
                      </div>
                    </div>

                    <AnimatePresence mode="wait">
                      {mode === "thin" ? (
                        <motion.div
                          key="thin"
                          initial={{ opacity: 0, y: 8 }}
                          animate={{ opacity: 1, y: 0 }}
                          exit={{ opacity: 0, y: -8 }}
                          className="mt-5 space-y-3"
                        >
                          <div className="rounded-lg border border-white/[0.05] bg-white/[0.02] px-4 py-3 text-sm text-zinc-400 font-light">
                            {bead.thinSummary}
                          </div>
                          <div className="rounded-lg border border-[#FF5F56]/20 bg-[#FF5F56]/10 px-4 py-3 text-sm leading-relaxed text-[#FF5F56] font-medium flex items-start gap-3">
                            <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
                            {bead.thinRisk}
                          </div>
                        </motion.div>
                      ) : (
                        <motion.div
                          key="rich"
                          initial={{ opacity: 0, y: 8 }}
                          animate={{ opacity: 1, y: 0 }}
                          exit={{ opacity: 0, y: -8 }}
                          className="mt-5 space-y-3"
                        >
                          {bead.richDetails.map((detail) => {
                            const detailHighlighted = detail.concepts.includes(selectedConceptId);
                            return (
                              <div
                                key={`${bead.id}-${detail.label}`}
                                className={cn(
                                  "rounded-lg border px-4 py-3 transition-colors duration-300",
                                  detailHighlighted
                                    ? "border-primary/30 bg-primary/5"
                                    : "border-white/[0.04] bg-white/[0.01]",
                                )}
                              >
                                <div className="flex items-start gap-3">
                                  <div
                                    className="mt-1 h-2 w-2 shrink-0 rounded-full"
                                    style={{ backgroundColor: detailHighlighted ? bead.color : "rgba(255,255,255,0.2)" }}
                                  />
                                  <div>
                                    <div className="text-[0.65rem] font-bold uppercase tracking-widest text-white/40 mb-1">
                                      {detail.label}
                                    </div>
                                    <div className="text-sm leading-relaxed text-zinc-300 font-light">
                                      {detail.value}
                                    </div>
                                  </div>
                                </div>
                              </div>
                            );
                          })}
                        </motion.div>
                      )}
                    </AnimatePresence>
                  </motion.article>

                  {index < TRANSLATED_BEADS.length - 1 && (
                    <div className="flex items-center justify-center py-3">
                      <div className="h-6 w-px bg-white/[0.08]" />
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <div className="relative z-10 p-6 sm:p-8 pt-0 grid gap-5 md:grid-cols-3">
        <div className="rounded-2xl border border-white/[0.05] bg-[#0A0D14] p-5 shadow-lg group">
          <div className="text-[0.65rem] font-bold uppercase tracking-widest text-white/40 group-hover:text-white/60 transition-colors">
            Execution Readiness
          </div>
          <div className={cn("mt-3 text-4xl font-black tracking-tighter transition-colors duration-500", mode === "rich" ? "text-[#27C93F]" : "text-[#FFBD2E]")}>
            {readinessScore}%
          </div>
          <p className="mt-2 text-sm leading-relaxed text-zinc-400 font-light">
            {MODE_COPY[mode].description}
          </p>
        </div>

        <div className="rounded-2xl border border-white/[0.05] bg-[#0A0D14] p-5 shadow-lg group">
          <div className="text-[0.65rem] font-bold uppercase tracking-widest text-white/40 group-hover:text-white/60 transition-colors">
            Unanswered Questions
          </div>
          <div className={cn("mt-3 text-4xl font-black tracking-tighter transition-colors duration-500", mode === "rich" ? "text-white" : "text-[#FF5F56]")}>
            {ambiguityCount}
          </div>
          <p className="mt-2 text-sm leading-relaxed text-zinc-400 font-light">
            {mode === "rich"
              ? "Most architecture has already been decided upstream."
              : "Missing context must be rediscovered during implementation."}
          </p>
        </div>

        <div className="rounded-2xl border border-[#27C93F]/20 bg-[#27C93F]/5 p-5 shadow-lg relative overflow-hidden group">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(39,201,63,0.1),transparent_50%)] pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity duration-500" />
          <div className="relative z-10 flex items-center gap-2 text-[0.65rem] font-bold uppercase tracking-widest text-[#27C93F]">
            <CheckCircle2 className="h-3.5 w-3.5" />
            The Takeaway
          </div>
          <p className="relative z-10 mt-3 text-sm leading-relaxed text-zinc-300 font-medium">
            {MODE_COPY[mode].takeaway}
          </p>
          <div className="relative z-10 mt-4 inline-flex items-center gap-2 rounded-xl border border-[#27C93F]/30 bg-[#27C93F]/10 px-3 py-2 text-[0.65rem] font-bold uppercase tracking-widest text-[#27C93F]">
            <Zap className="h-3.5 w-3.5" />
            Impacts {selectedConcept.mapsTo.length} bead{selectedConcept.mapsTo.length > 1 ? "s" : ""}
          </div>
        </div>
      </div>
    </div>
  );
}
