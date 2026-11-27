"use client";

import { LayoutGroup } from "framer-motion";
import { AlertTriangle, CheckCircle2, FileText, GitBranch, XCircle } from "lucide-react";
import { useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "@/components/motion";
import { cn } from "@/lib/utils";

/* -------------------------------------------------------------------------- */
/*  Constants                                                                  */
/* -------------------------------------------------------------------------- */

const EXHIBIT_PANEL_CLASS =
  "my-16 overflow-hidden rounded-[1.5rem] sm:rounded-[2rem] lg:rounded-[3rem] border border-white/[0.03] bg-[#020408] p-5 sm:p-12 lg:p-16 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9)]";

type TabId = "plan" | "bead";

type QualityMetric = {
  label: string;
  weak: boolean;
  strong: boolean;
};

type ExampleData = {
  tab: TabId;
  title: string;
  weakContent: string[];
  strongContent: string[];
  metrics: QualityMetric[];
  insight: string;
};

const EXAMPLES: Record<TabId, ExampleData> = {
  plan: {
    tab: "plan",
    title: "Plan Bullet",
    weakContent: ["- Add auth"],
    strongContent: [
      "- Internal-only auth gates every note and note-metadata surface.",
      "- Unauthorized users must never see content, filenames, tags, or timestamps.",
      "- Admin review routes require explicit permission checks and should be",
      "  covered by e2e tests for allowed and denied access.",
    ],
    metrics: [
      { label: "Scope", weak: false, strong: true },
      { label: "Constraints", weak: false, strong: true },
      { label: "Tests", weak: false, strong: true },
    ],
    insight:
      "“Add auth” names a topic. The strong version says what auth must gate, what unauthorized users must never see, and which e2e tests prove it.",
  },
  bead: {
    tab: "bead",
    title: "Bead",
    weakContent: ["br-204: Improve search"],
    strongContent: [
      "br-204: Search result filtering and sorting",
      "",
      "Context:",
      "The search index exists, but users still cannot filter by tag",
      "or date or choose relevance vs recency sorting.",
      "",
      "Depends on:",
      "- br-201: search index and query path (closed)",
      "",
      "Task:",
      "Implement filter controls plus sort selection and connect",
      "them to the existing query path.",
      "",
      "Definition of done:",
      "- tag filter works",
      "- date filter works",
      "- relevance and recency sort both work",
      "- empty states remain intelligible",
      "",
      "Tests:",
      "- unit coverage for query-parameter mapping",
      "- e2e coverage for filter and sort behavior",
    ],
    metrics: [
      { label: "Context", weak: false, strong: true },
      { label: "Dependencies", weak: false, strong: true },
      { label: "Done Criteria", weak: false, strong: true },
      { label: "Tests", weak: false, strong: true },
    ],
    insight:
      "“Improve search” names a topic. The strong version gives the context, the bead it depends on, the task, a definition of done, and the tests.",
  },
};

/* -------------------------------------------------------------------------- */
/*  Sub-components                                                             */
/* -------------------------------------------------------------------------- */

function TerminalBlock({
  lines,
  variant,
  reducedMotion,
  isInView,
  tabKey,
}: {
  lines: string[];
  variant: "weak" | "strong";
  reducedMotion: boolean;
  isInView: boolean;
  tabKey: string;
}) {
  const isWeak = variant === "weak";

  /* Line count display */
  const displayCount = isWeak ? lines.length : lines.filter((l) => l.trim()).length;

  return (
    <div
      className={cn(
        // Both cards stretch to the taller one on desktop, so the weak card's
        // empty terminal fills the space instead of leaving a dead area.
        "flex h-full flex-col rounded-2xl border p-5 sm:p-6 relative overflow-hidden group-scanline",
        isWeak
          ? "border-red-500/20 bg-red-950/[0.15]"
          : "border-emerald-500/30 bg-emerald-950/[0.15] shadow-[0_0_0_1px_rgba(16,185,129,0.06),0_0_40px_-12px_rgba(16,185,129,0.35)]",
      )}
    >
      {/* Glow effect on strong side */}
      {!isWeak && (
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(16,185,129,0.08),transparent_70%)] pointer-events-none" />
      )}

      {/* #3: macOS-style window dots */}
      <div className="flex items-center gap-1.5 mb-3 relative z-10">
        <span
          className={cn("w-2.5 h-2.5 rounded-full", isWeak ? "bg-red-500/60" : "bg-emerald-500/60")}
        />
        <span
          className={cn("w-2.5 h-2.5 rounded-full", isWeak ? "bg-red-500/35" : "bg-emerald-500/35")}
        />
        <span
          className={cn("w-2.5 h-2.5 rounded-full", isWeak ? "bg-red-500/20" : "bg-emerald-500/20")}
        />
      </div>

      {/* Header bar */}
      <div className="flex items-center gap-2 mb-4 relative z-10">
        {isWeak ? (
          <AlertTriangle className="h-4 w-4 text-red-400" />
        ) : (
          <CheckCircle2 className="h-4 w-4 text-emerald-400" />
        )}
        <span
          className={cn(
            "text-xs font-bold uppercase tracking-widest",
            isWeak ? "text-red-400" : "text-emerald-400",
          )}
        >
          {isWeak ? "Weak" : "Strong"}
        </span>
        <span
          className={cn(
            "ml-auto rounded-full px-2.5 py-0.5 text-xs font-bold uppercase tracking-widest border tabular-nums",
            isWeak
              ? "border-red-500/20 bg-red-500/10 text-red-400"
              : "border-emerald-500/20 bg-emerald-500/10 text-emerald-400",
          )}
        >
          {isWeak
            ? `${lines.length} line${lines.length > 1 ? "s" : ""}`
            : `${displayCount} line${displayCount !== 1 ? "s" : ""}`}
        </span>
      </div>

      {/* Terminal content — #4: leading-snug for tighter code display */}
      <div
        className={cn(
          "flex-1 rounded-xl border p-4 font-mono text-[13px] leading-snug relative z-10 overflow-x-auto",
          isWeak ? "border-red-500/10 bg-black/40" : "border-emerald-500/10 bg-black/40",
        )}
      >
        {lines.map((line, i) => (
          <motion.div
            key={`${tabKey}-${i}`}
            // Reduced motion reveals at once; `initial` stays fixed so the
            // server-rendered hidden state is always animated away.
            initial={{
              opacity: 0,
              x: isWeak ? -8 : 8,
              ...(!isWeak ? { backgroundColor: "rgba(16,185,129,0.05)" } : {}),
            }}
            animate={
              isInView || reducedMotion
                ? {
                    opacity: 1,
                    x: 0,
                    ...(!isWeak ? { backgroundColor: "rgba(16,185,129,0)" } : {}),
                  }
                : undefined
            }
            transition={{
              delay: reducedMotion ? 0 : i * 0.05,
              type: "spring",
              stiffness: 260,
              damping: 24,
              ...(!isWeak
                ? {
                    backgroundColor: {
                      delay: reducedMotion ? 0 : i * 0.05,
                      duration: 0.6,
                    },
                  }
                : {}),
            }}
            className={cn(
              "flex gap-3 py-px rounded-sm",
              !isWeak && "shadow-[0_0_0_0_rgba(16,185,129,0)]",
            )}
            style={
              !isWeak && !reducedMotion
                ? {
                    boxShadow: `0 0 6px rgba(16,185,129,${isInView ? 0 : 0.12})`,
                  }
                : undefined
            }
          >
            <span
              className={cn(
                "select-none tabular-nums shrink-0 w-5 text-right",
                isWeak ? "text-red-400/50" : "text-emerald-400/50",
              )}
            >
              {i + 1}
            </span>
            <span
              className={cn(
                "min-w-0 whitespace-pre-wrap break-words",
                isWeak ? "text-red-200/80" : "text-emerald-200/85",
              )}
            >
              {line || "\u00A0"}
            </span>
          </motion.div>
        ))}

        {/* #5: Scanline sweep effect on hover */}
        <div className="scanline-effect absolute inset-0 pointer-events-none opacity-30 bg-gradient-to-b from-transparent via-white/[0.04] to-transparent h-[25%]" />
      </div>

      {/* Sparse/dense indicator for weak side */}
      {isWeak && lines.length <= 2 && (
        <div className="mt-3 flex items-center gap-2 text-xs font-bold uppercase tracking-widest text-red-400/80 relative z-10">
          <span className="w-1.5 h-1.5 rounded-full bg-red-500/40" />
          Only names a topic
        </div>
      )}
    </div>
  );
}

/** A check (present) or a cross (missing), colored by meaning, not by side. */
function MetricMark({ present }: { present: boolean }) {
  return present ? (
    <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-400" aria-hidden="true" />
  ) : (
    <XCircle className="h-4 w-4 shrink-0 text-red-400" aria-hidden="true" />
  );
}

function QualityMetrics({
  metrics,
  reducedMotion,
  isInView,
  tabKey,
}: {
  metrics: QualityMetric[];
  reducedMotion: boolean;
  isInView: boolean;
  tabKey: string;
}) {
  return (
    <div className="relative flex flex-col items-center gap-3 py-2 lg:items-stretch lg:py-0">
      {/* #6: Column headers on desktop. The chips below stretch to the same
          width, so "Weak" sits over the left marks and "Strong" over the right. */}
      <div
        className="hidden lg:flex items-center justify-between gap-3 px-3 text-xs font-bold uppercase tracking-widest"
        aria-hidden="true"
      >
        <span className="text-red-400/80">Weak</span>
        <span className="text-zinc-400">Quality</span>
        <span className="text-emerald-400/80">Strong</span>
      </div>
      {/* #7: AnimatePresence keyed on tabKey to pulse metrics on tab change */}
      <AnimatePresence mode="wait">
        <motion.div
          key={tabKey}
          initial={reducedMotion ? false : { opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={reducedMotion ? undefined : { opacity: 0, scale: 0.95 }}
          transition={{ type: "spring", stiffness: 300, damping: 25 }}
          className="flex flex-row flex-wrap items-center justify-center gap-3 lg:flex-col lg:items-stretch lg:gap-2.5"
        >
          {metrics.map((metric, i) => (
            <motion.div
              key={metric.label}
              // Reduced motion reveals at once; `initial` stays fixed so the
              // server-rendered hidden state is always animated away.
              initial={{ opacity: 0, scale: 0.9 }}
              animate={isInView || reducedMotion ? { opacity: 1, scale: 1 } : undefined}
              transition={{
                delay: reducedMotion ? 0 : 0.2 + i * 0.08,
                type: "spring",
                stiffness: 260,
                damping: 22,
              }}
              className="relative flex items-center gap-2 rounded-xl border border-white/[0.08] bg-white/[0.03] px-3 py-2 min-w-0"
            >
              <MetricMark present={metric.weak} />
              <span className="flex-1 text-center text-xs font-bold text-zinc-300 tracking-wide whitespace-nowrap">
                {metric.label}
                <span className="sr-only">
                  {`: ${metric.weak ? "present" : "missing"} in the weak version, ${metric.strong ? "present" : "missing"} in the strong version`}
                </span>
              </span>
              <MetricMark present={metric.strong} />
            </motion.div>
          ))}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/*  Main component                                                             */
/* -------------------------------------------------------------------------- */

export function BeadComparisonViz() {
  const [activeTab, setActiveTab] = useState<TabId>("plan");
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;

  const example = EXAMPLES[activeTab];

  return (
    <div ref={ref} className={cn(EXHIBIT_PANEL_CLASS, "relative group/viz")}>
      {/* Noise texture overlay */}
      <div className="absolute inset-0 noise-overlay opacity-[0.02] mix-blend-overlay pointer-events-none rounded-[inherit]" />

      {/* HEADER */}
      <div className="relative z-10 flex flex-col gap-6 sm:flex-row sm:items-center sm:justify-between mb-8 sm:mb-10">
        <div>
          <div className="text-xs font-bold uppercase tracking-widest text-[#FF5500] mb-2 flex items-center gap-2">
            <span className="w-1.5 h-1.5 rounded-full bg-[#FF5500]" />
            Interactive Comparison
          </div>
          <div className="flex items-center gap-3">
            <span className="flex h-8 w-8 items-center justify-center rounded-xl bg-[#FF5500]/10 text-[#FF5500] border border-[#FF5500]/20 shadow-inner">
              <GitBranch className="h-4 w-4" />
            </span>
            <h3 className="font-serif text-[1.5rem] font-normal leading-[1.12] tracking-[-0.008em] text-white sm:text-[1.875rem]">
              Weak vs. Strong Artifacts
            </h3>
          </div>
          <p className="mt-2 text-sm text-zinc-400 font-light max-w-xl">
            A weak artifact names a topic. A strong one carries scope, constraints, and a test plan.
            Switch between a plan bullet and a bead to compare them.
          </p>
        </div>

        {/* TAB CONTROLS — #1: sliding pill indicator, #2: larger icon on active, #10: bigger touch targets on mobile */}
        <LayoutGroup>
          <div className="relative flex p-1 bg-black/40 rounded-2xl border border-white/[0.05] shadow-inner shrink-0">
            {(["plan", "bead"] as const).map((tab) => (
              <button
                key={tab}
                type="button"
                aria-pressed={activeTab === tab}
                onClick={() => setActiveTab(tab)}
                className={cn(
                  "relative z-10 px-5 py-3 sm:py-2.5 rounded-xl text-sm sm:text-sm font-bold tracking-wide transition-colors duration-300 flex items-center gap-2 min-h-[48px] sm:min-h-[44px] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/60",
                  activeTab === tab ? "text-[#FF5500]" : "text-zinc-400 hover:text-white/80",
                )}
              >
                {/* #1: Sliding pill behind active tab */}
                {activeTab === tab && (
                  <motion.div
                    layoutId="tab-indicator"
                    className="absolute inset-0 bg-[#FF5500]/10 border border-[#FF5500]/20 rounded-xl"
                    transition={{ type: "spring", stiffness: 380, damping: 30 }}
                  />
                )}
                {/* #2: Icon is h-4 w-4 on active, h-3.5 w-3.5 otherwise */}
                <FileText
                  className={cn(
                    "relative z-10 transition-[width,height] duration-300",
                    activeTab === tab ? "h-4 w-4" : "h-3.5 w-3.5",
                  )}
                />
                <span className="relative z-10">{EXAMPLES[tab].title}</span>
              </button>
            ))}
          </div>
        </LayoutGroup>
      </div>

      {/* COMPARISON VIEW — #13: will-change-transform for smoother transitions, #4: scale punch on transition */}
      <AnimatePresence mode="wait">
        <motion.div
          key={activeTab}
          initial={reducedMotion ? false : { opacity: 0, y: 12, scale: 0.98 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={reducedMotion ? undefined : { opacity: 0, y: -12, scale: 0.98 }}
          transition={{ type: "spring", stiffness: 300, damping: 30 }}
          className="relative z-10 will-change-transform"
        >
          {/* Split view. Stacked on mobile: weak, quality checklist, strong.
              On lg the weak card and the checklist share the left column so
              the strong card gets the wider right column (its lines wrap far
              less), and both columns stretch to the same height, so there is
              no dead area under the shorter side. */}
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] lg:items-stretch lg:gap-6">
            <div className="flex flex-col gap-4 lg:gap-6">
              {/* Weak side */}
              <div className="lg:flex-1">
                <TerminalBlock
                  lines={example.weakContent}
                  variant="weak"
                  reducedMotion={reducedMotion}
                  isInView={isInView}
                  tabKey={activeTab}
                />
              </div>

              {/* Quality metrics: between the panels on mobile, under the weak card on lg */}
              <QualityMetrics
                metrics={example.metrics}
                reducedMotion={reducedMotion}
                isInView={isInView}
                tabKey={activeTab}
              />
            </div>

            {/* Strong side */}
            <div className="relative h-full">
              {/* Glow behind the strong card */}
              <div className="absolute -inset-2 bg-[radial-gradient(ellipse_at_center,rgba(16,185,129,0.06),transparent_70%)] rounded-3xl pointer-events-none blur-xl" />
              <TerminalBlock
                lines={example.strongContent}
                variant="strong"
                reducedMotion={reducedMotion}
                isInView={isInView}
                tabKey={activeTab}
              />
            </div>
          </div>
        </motion.div>
      </AnimatePresence>

      {/* INSIGHT FOOTER — #12: entrance animation with delay after comparison content, #4: scale punch */}
      <AnimatePresence mode="wait">
        <motion.div
          key={`insight-${activeTab}`}
          initial={{ opacity: 0, y: 16, scale: 0.98 }}
          animate={isInView || reducedMotion ? { opacity: 1, y: 0, scale: 1 } : undefined}
          exit={reducedMotion ? undefined : { opacity: 0, y: 8, scale: 0.98 }}
          transition={{
            type: "spring",
            stiffness: 220,
            damping: 24,
            delay: reducedMotion ? 0 : 0.35,
          }}
          className="relative z-10 mt-8 sm:mt-10 rounded-2xl border border-[#FFBD2E]/20 bg-[#FFBD2E]/[0.04] p-5 sm:p-6 shadow-lg overflow-hidden"
        >
          <div className="absolute top-0 right-0 w-40 h-40 blur-[60px] opacity-15 pointer-events-none bg-[#FFBD2E]" />
          <div className="relative z-10 flex items-center gap-2 text-xs font-bold uppercase tracking-widest text-[#FFBD2E]">
            <motion.span
              key={`icon-spin-${activeTab}`}
              initial={reducedMotion ? false : { rotate: 0 }}
              animate={{ rotate: 360 }}
              transition={{ duration: 0.6, ease: "easeInOut" }}
              className="inline-flex"
            >
              <CheckCircle2 className="h-3.5 w-3.5" />
            </motion.span>
            The Takeaway
          </div>
          <motion.p
            initial={reducedMotion ? false : { opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{
              type: "spring",
              stiffness: 220,
              damping: 24,
              delay: reducedMotion ? 0 : 0.5,
            }}
            className="relative z-10 mt-3 text-sm sm:text-base leading-relaxed text-zinc-300 font-light"
          >
            {example.insight}
          </motion.p>
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
