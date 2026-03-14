"use client";

import { useState, useRef } from "react";
import {
  motion,
  AnimatePresence,
  useInView,
  useReducedMotion,
  LayoutGroup,
} from "framer-motion";
import {
  AlertTriangle,
  CheckCircle2,
  FileText,
  GitBranch,
} from "lucide-react";
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
      "The weak version names a topic. The strong version scopes the actual requirement, the constraint, and the testing obligation.",
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
      "The weak version names a topic. The strong version carries context, task scope, a concrete definition of done, and the testing plan.",
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
  const displayCount = isWeak
    ? lines.length
    : lines.filter((l) => l.trim()).length;

  return (
    <div
      className={cn(
        "rounded-2xl border p-5 sm:p-6 relative overflow-hidden group-scanline",
        isWeak
          ? "border-red-500/20 bg-red-950/[0.15]"
          : "bg-emerald-950/[0.15] animate-border-rotate",
        /* #11: strong side gets the rotating conic-gradient border; fallback for browsers without @property */
        !isWeak && "border-emerald-500/20",
      )}
    >
      {/* Glow effect on strong side */}
      {!isWeak && (
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(16,185,129,0.08),transparent_70%)] pointer-events-none" />
      )}

      {/* #3 (weak watermark): "Missing context" watermark behind thin weak content */}
      {isWeak && lines.length <= 2 && (
        <div
          className="absolute inset-0 flex items-center justify-center pointer-events-none select-none z-0"
          aria-hidden="true"
        >
          <span
            className="text-red-400 text-4xl sm:text-5xl font-black uppercase tracking-widest"
            style={{
              opacity: 0.04,
              transform: "rotate(-12deg)",
              whiteSpace: "nowrap",
            }}
          >
            Missing context
          </span>
        </div>
      )}

      {/* #3: macOS-style window dots */}
      <div className="flex items-center gap-1.5 mb-3 relative z-10">
        <span
          className={cn(
            "w-2.5 h-2.5 rounded-full",
            isWeak ? "bg-red-500/60" : "bg-emerald-500/60",
          )}
        />
        <span
          className={cn(
            "w-2.5 h-2.5 rounded-full",
            isWeak ? "bg-red-500/35" : "bg-emerald-500/35",
          )}
        />
        <span
          className={cn(
            "w-2.5 h-2.5 rounded-full",
            isWeak ? "bg-red-500/20" : "bg-emerald-500/20",
          )}
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
            "text-[0.65rem] font-bold uppercase tracking-widest",
            isWeak ? "text-red-400" : "text-emerald-400",
          )}
        >
          {isWeak ? "Weak" : "Strong"}
        </span>
        <span
          className={cn(
            "ml-auto rounded-full px-2.5 py-0.5 text-[0.6rem] font-bold uppercase tracking-widest border tabular-nums",
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
          "rounded-xl border p-4 font-mono text-[13px] leading-snug relative z-10 overflow-x-auto",
          isWeak
            ? "border-red-500/10 bg-black/40"
            : "border-emerald-500/10 bg-black/40",
        )}
      >
        {lines.map((line, i) => (
          <motion.div
            key={`${tabKey}-${i}`}
            initial={
              reducedMotion
                ? false
                : {
                    opacity: 0,
                    x: isWeak ? -8 : 8,
                    ...(!isWeak
                      ? { backgroundColor: "rgba(16,185,129,0.05)" }
                      : {}),
                  }
            }
            animate={
              isInView
                ? {
                    opacity: 1,
                    x: 0,
                    ...(!isWeak
                      ? { backgroundColor: "rgba(16,185,129,0)" }
                      : {}),
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
                isWeak ? "text-red-500/30" : "text-emerald-500/30",
              )}
            >
              {i + 1}
            </span>
            <span
              className={cn(
                "whitespace-pre-wrap",
                isWeak ? "text-red-200/70" : "text-emerald-200/80",
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
        <div className="mt-3 flex items-center gap-2 text-[0.6rem] font-bold uppercase tracking-widest text-red-400/60 relative z-10">
          <span className="w-1.5 h-1.5 rounded-full bg-red-500/40" />
          No scope, no constraints, no tests
        </div>
      )}
    </div>
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
    <div className="flex flex-row flex-wrap lg:flex-col items-center justify-center gap-3 py-4 lg:py-0 lg:px-5 relative">
      {/* #2 (connecting lines): subtle horizontal connector lines on desktop */}
      <div className="hidden lg:block absolute top-1/2 -translate-y-1/2 -left-4 w-4 border-t border-dashed border-red-500/15 pointer-events-none" />
      <div className="hidden lg:block absolute top-1/2 -translate-y-1/2 -right-4 w-4 border-t border-dashed border-emerald-500/15 pointer-events-none" />

      {/* #6: Column headers on desktop */}
      <div className="hidden lg:flex items-center gap-2 mb-1 w-full justify-center">
        <span className="text-[0.55rem] font-bold uppercase tracking-widest text-white/20 w-5 text-center">
          Weak
        </span>
        <span className="text-[0.6rem] font-bold uppercase tracking-widest text-white/30">
          Quality
        </span>
        <span className="text-[0.55rem] font-bold uppercase tracking-widest text-white/20 w-5 text-center">
          Strong
        </span>
      </div>
      {/* #7: AnimatePresence keyed on tabKey to pulse metrics on tab change */}
      <AnimatePresence mode="wait">
        <motion.div
          key={tabKey}
          initial={reducedMotion ? false : { opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={reducedMotion ? undefined : { opacity: 0, scale: 0.95 }}
          transition={{ type: "spring", stiffness: 300, damping: 25 }}
          className="flex flex-row flex-wrap lg:flex-col items-center justify-center gap-3"
        >
          {metrics.map((metric, i) => (
            <motion.div
              key={metric.label}
              initial={reducedMotion ? false : { opacity: 0, scale: 0.9 }}
              animate={isInView ? { opacity: 1, scale: 1 } : undefined}
              transition={{
                delay: reducedMotion ? 0 : 0.2 + i * 0.08,
                type: "spring",
                stiffness: 260,
                damping: 22,
              }}
              className="relative flex items-center gap-2 rounded-xl border border-white/[0.06] bg-white/[0.02] px-3 py-2 min-w-0"
            >
              {/* Connecting dots on each metric row (desktop only) */}
              <span className="hidden lg:block absolute -left-[18px] w-1.5 h-1.5 rounded-full bg-red-500/20" />
              <span className="hidden lg:block absolute -right-[18px] w-1.5 h-1.5 rounded-full bg-emerald-500/20" />
              <span className="text-red-400 text-sm shrink-0">
                {metric.weak ? "\u2705" : "\u274C"}
              </span>
              <span className="text-[0.65rem] font-bold text-white/50 tracking-wide whitespace-nowrap">
                {metric.label}
              </span>
              <span className="text-emerald-400 text-sm shrink-0">
                {metric.strong ? "\u2705" : "\u274C"}
              </span>
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
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.02] mix-blend-overlay pointer-events-none rounded-[inherit]" />

      {/* HEADER */}
      <div className="relative z-10 flex flex-col gap-6 sm:flex-row sm:items-center sm:justify-between mb-8 sm:mb-10">
        <div>
          <div className="text-[0.65rem] font-bold uppercase tracking-widest text-[#FF5500]/70 mb-2 flex items-center gap-2">
            <span className="w-1.5 h-1.5 rounded-full bg-[#FF5500] animate-pulse shadow-[0_0_8px_rgba(255,85,0,0.8)]" />
            Interactive Comparison
          </div>
          <div className="flex items-center gap-3">
            <span className="flex h-8 w-8 items-center justify-center rounded-xl bg-[#FF5500]/10 text-[#FF5500] border border-[#FF5500]/20 shadow-inner">
              <GitBranch className="h-4 w-4" />
            </span>
            <h4 className="text-xl sm:text-2xl font-black text-white tracking-tight">
              Weak vs. Strong Artifacts
            </h4>
          </div>
          <p className="mt-2 text-sm text-zinc-400 font-light max-w-xl">
            A weak artifact names a topic. A strong one carries scope,
            constraints, and a test plan. See the difference.
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
                  "relative z-10 px-5 py-3 sm:py-2.5 rounded-xl text-sm sm:text-sm font-bold tracking-wide transition-colors duration-300 flex items-center gap-2 min-h-[48px] sm:min-h-[44px]",
                  activeTab === tab
                    ? "text-[#FF5500]"
                    : "text-white/40 hover:text-white/80",
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
                    "relative z-10 transition-all duration-300",
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
          {/* Split view: side-by-side on lg, stacked on mobile */}
          {/* #8: On mobile, metrics appear as a horizontal row BETWEEN the stacked panels */}
          <div className="grid gap-4 lg:gap-0 lg:grid-cols-[1fr_auto_1fr] lg:items-start">
            {/* Weak side */}
            <TerminalBlock
              lines={example.weakContent}
              variant="weak"
              reducedMotion={reducedMotion}
              isInView={isInView}
              tabKey={activeTab}
            />

            {/* Quality metrics — on mobile this sits between the two panels naturally via grid order */}
            <QualityMetrics
              metrics={example.metrics}
              reducedMotion={reducedMotion}
              isInView={isInView}
              tabKey={activeTab}
            />

            {/* Strong side */}
            <div className="relative">
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
          initial={reducedMotion ? false : { opacity: 0, y: 16, scale: 0.98 }}
          animate={isInView ? { opacity: 1, y: 0, scale: 1 } : undefined}
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
          <div className="relative z-10 flex items-center gap-2 text-[0.65rem] font-bold uppercase tracking-widest text-[#FFBD2E]">
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
