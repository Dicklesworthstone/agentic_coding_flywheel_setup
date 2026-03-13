"use client";

import {
  useRef,
  useState,
  useCallback,
  useEffect,
  type ReactNode,
} from "react";
import { motion, useReducedMotion, useInView, AnimatePresence } from "framer-motion";
import {
  Check,
  Copy,
  ChevronDown,
  Lightbulb,
  AlertTriangle,
  Quote,
  Hash,
  Info,
  X,
  Menu,
} from "lucide-react";
import {
  CodeBlock as SharedCodeBlock,
  type CodeBlockProps as SharedCodeBlockProps,
} from "@/components/ui/code-block";
import { copyTextToClipboard } from "@/lib/utils";

// =============================================================================
// GUIDE SECTION - Anchored sections with gradient headers + scroll reveal
// =============================================================================
interface GuideSectionProps {
  id: string;
  number?: string;
  title: string;
  icon?: ReactNode;
  children: ReactNode;
}

export function GuideSection({
  id,
  number,
  title,
  icon,
  children,
}: GuideSectionProps) {
  const ref = useRef<HTMLElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const rm = prefersReducedMotion ?? false;

  return (
    <motion.section
      ref={ref}
      id={id}
      initial={rm ? {} : { opacity: 0, y: 15 }}
      animate={isInView ? { opacity: 1, y: 0 } : {}}
      transition={rm ? {} : { type: "spring", stiffness: 100, damping: 20 }}
      className="relative scroll-mt-32"
    >
      {/* Section header */}
      <div className="flex items-center gap-4 mb-10 group">
        {number != null && (
          <div className="flex h-10 w-10 sm:h-12 sm:w-12 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-primary/20 to-violet-500/20 border border-primary/30 font-mono text-sm sm:text-base font-bold text-primary shadow-[0_0_20px_-5px_var(--color-primary)] transition-all duration-500 group-hover:shadow-[0_0_30px_-5px_var(--color-primary)] group-hover:scale-105">
            {number}
          </div>
        )}
        {icon && (
          <div className="flex h-10 w-10 sm:h-12 sm:w-12 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-primary/10 to-violet-500/10 border border-white/[0.08] text-primary/80 transition-all duration-500 group-hover:bg-primary/20">
            {icon}
          </div>
        )}
        <h2 className="text-2xl sm:text-3xl md:text-4xl font-bold text-white tracking-tight leading-tight">
          {title}
        </h2>
        <div className="flex-1 h-px bg-gradient-to-r from-primary/30 via-white/10 to-transparent hidden sm:block ml-4" />
      </div>
      <div className="space-y-8 text-white/80">{children}</div>
    </motion.section>
  );
}

// =============================================================================
// SUBSECTION
// =============================================================================
export function SubSection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <div className="mt-12 first:mt-6">
      <h3 className="text-xl sm:text-2xl font-semibold text-white/95 mb-6 flex items-center gap-3">
        <span className="flex items-center justify-center h-6 w-6 rounded-md bg-primary/10 border border-primary/20">
          <Hash className="h-3.5 w-3.5 text-primary" />
        </span>
        {title}
      </h3>
      <div className="space-y-6">{children}</div>
    </div>
  );
}

// =============================================================================
// PARAGRAPH
// =============================================================================
export function P({
  children,
  highlight,
}: {
  children: ReactNode;
  highlight?: boolean;
}) {
  return (
    <p
      className={`text-[0.95rem] sm:text-[1.05rem] leading-[1.7] tracking-[-0.01em] ${
        highlight ? "text-zinc-200 font-medium" : "text-zinc-400"
      }`}
    >
      {children}
    </p>
  );
}

// =============================================================================
// BLOCKQUOTE - Elegant quote blocks with gradient accent
// =============================================================================
export function BlockQuote({ children }: { children: ReactNode }) {
  return (
    <div className="relative rounded-2xl border border-white/[0.05] bg-gradient-to-r from-primary/[0.05] to-transparent p-6 pl-14 sm:pl-16 overflow-hidden shadow-[inset_0_1px_1px_rgba(255,255,255,0.02)]">
      {/* Subtle left accent */}
      <div className="absolute left-0 top-0 bottom-0 w-[4px] bg-gradient-to-b from-primary via-violet-400 to-primary/20 shadow-[0_0_15px_var(--color-primary)]" />
      <Quote className="absolute left-5 sm:left-6 top-6 h-5 w-5 sm:h-6 sm:w-6 text-primary/40" />
      <div className="text-white/80 italic leading-relaxed text-base sm:text-lg font-light tracking-wide">
        {children}
      </div>
    </div>
  );
}

// =============================================================================
// CODE BLOCK - Terminal-style wrapper
// =============================================================================
export function CodeBlock(
  props: Omit<SharedCodeBlockProps, "variant" | "copyable">,
) {
  return <SharedCodeBlock {...props} variant="terminal" copyable />;
}

// =============================================================================
// PROMPT BLOCK - Collapsible prompt display with copy + metadata
// =============================================================================
export function PromptBlock({
  title,
  prompt,
  where,
  whyItWorks,
}: {
  title: string;
  prompt: string;
  where?: string;
  whyItWorks?: string;
}) {
  const [copied, setCopied] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isLong = prompt.length > 400;

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  const handleCopy = useCallback(async () => {
    const ok = await copyTextToClipboard(prompt);
    if (!ok) return;
    setCopied(true);
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => {
      setCopied(false);
      timerRef.current = null;
    }, 2000);
  }, [prompt]);

  // Very simple client-side syntax highlighting for structural keywords
  const highlightPrompt = (text: string) => {
    const keywords = ['Search', 'Review', 'Read', 'Write', 'Fix', 'Create', 'Update', 'Do we have', 'OK', 'Look', 'Execute'];
    let highlighted = text;
    keywords.forEach(kw => {
      const regex = new RegExp(`\\b(${kw})\\b`, 'g');
      highlighted = highlighted.replace(regex, '<span class="text-cyan-400 font-semibold">$1</span>');
    });
    // Highlight bracketed variables like [SKILL] or [TOOL]
    highlighted = highlighted.replace(/(\[[A-Z_]+\])/g, '<span class="text-amber-400">$1</span>');
    return highlighted;
  };

  return (
    <div className="group relative rounded-xl border border-white/10 bg-[#09090b] overflow-hidden shadow-2xl transition-all duration-500 hover:border-white/20 hover:shadow-[0_0_30px_-5px_rgba(34,211,238,0.15)] ring-1 ring-inset ring-white/5">
      {/* Noise Texture */}
      <div className="absolute inset-0 bg-noise opacity-[0.03] pointer-events-none mix-blend-overlay" />
      
      {/* Top bar */}
      <div className="relative flex items-center justify-between px-4 py-3 bg-[#1a1b1e]/80 border-b border-white/10 backdrop-blur-md z-10">
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 rounded-full bg-[#ff5f56] shadow-[inset_0_1px_1px_rgba(255,255,255,0.2)]" />
          <div className="w-3 h-3 rounded-full bg-[#ffbd2e] shadow-[inset_0_1px_1px_rgba(255,255,255,0.2)]" />
          <div className="w-3 h-3 rounded-full bg-[#27c93f] shadow-[inset_0_1px_1px_rgba(255,255,255,0.2)]" />
          <span className="ml-4 text-xs font-mono text-white/50 tracking-wide">{title}</span>
        </div>
        <div className="flex items-center gap-2">
          {isLong && (
            <button
              onClick={() => setExpanded(!expanded)}
              className="opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-1 rounded-full px-2.5 py-1 text-xs text-white/50 hover:bg-white/10 hover:text-white"
            >
              <ChevronDown className={`h-3.5 w-3.5 transition-transform duration-200 ${expanded ? "rotate-180" : ""}`} />
              {expanded ? "Less" : "More"}
            </button>
          )}
          <motion.button
            whileTap={{ scale: 0.95 }}
            onClick={handleCopy}
            className="opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1 text-xs text-white hover:bg-white/20 border border-white/5 shadow-sm"
          >
            {copied ? <Check className="h-3.5 w-3.5 text-green-400" /> : <Copy className="h-3.5 w-3.5" />}
            {copied ? "Copied" : "Copy"}
          </motion.button>
        </div>
      </div>
      {/* Prompt body */}
      <div className={`relative z-10 ${isLong && !expanded ? "max-h-[220px] overflow-hidden" : ""}`}>
        <div 
          className="px-6 py-6 text-[0.9rem] text-[#a1a1aa] whitespace-pre-wrap font-mono leading-[1.7] overflow-x-auto selection:bg-cyan-900/40 selection:text-white"
          dangerouslySetInnerHTML={{ __html: highlightPrompt(prompt) + '<span class="inline-block w-2.5 h-[1.1em] ml-1.5 align-middle bg-cyan-400/80 animate-blink shadow-[0_0_8px_rgba(34,211,238,0.6)]" />' }}
        />
        {isLong && !expanded && (
          <div className="absolute bottom-0 inset-x-0 h-32 bg-gradient-to-t from-[#09090b] via-[#09090b]/80 to-transparent pointer-events-none" />
        )}
      </div>
      {/* Metadata footer */}
      <AnimatePresence>
        {(where || whyItWorks) && (
          <motion.div 
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            className="relative z-10 bg-white/[0.02] border-t border-white/[0.05] p-5 space-y-4"
          >
            {where && (
              <p className="text-xs text-primary/70 font-mono">
                <span className="opacity-60 text-white">Location:</span> {where}
              </p>
            )}
            {whyItWorks && (
              <div className="flex items-start gap-2.5">
                <Lightbulb className="h-4 w-4 text-amber-400 shrink-0 mt-0.5" />
                <p className="text-xs sm:text-sm text-white/70 leading-relaxed">{whyItWorks}</p>
              </div>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// =============================================================================
// DATA TABLE - Responsive with mobile scroll indicator
// =============================================================================
export function DataTable({
  headers,
  rows,
}: {
  headers: string[];
  rows: (string | ReactNode)[][];
}) {
  return (
    <div className="relative group">
      {/* Mobile scroll hint */}
      <div className="absolute right-0 top-0 bottom-0 w-8 bg-gradient-to-l from-[oklch(0.15_0.01_260)] to-transparent pointer-events-none z-10 opacity-100 sm:opacity-0 transition-opacity" />
      <div className="overflow-x-auto rounded-2xl border border-white/[0.08] scrollbar-thin scrollbar-thumb-white/10 scrollbar-track-transparent">
        <table className="w-full text-sm min-w-[500px]">
          <thead>
            <tr className="border-b border-white/[0.08] bg-white/[0.03]">
              {headers.map((h, i) => (
                <th
                  key={i}
                  className="px-3 sm:px-4 py-3 text-left font-semibold text-white/80 text-xs sm:text-sm whitespace-nowrap"
                >
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, ri) => (
              <tr
                key={ri}
                className="border-b border-white/[0.04] last:border-0 transition-colors hover:bg-white/[0.02]"
              >
                {row.map((cell, ci) => (
                  <td key={ci} className="px-3 sm:px-4 py-3 text-white/60 text-xs sm:text-sm">
                    {cell}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// =============================================================================
// PHASE CARD - With subtle hover glow
// =============================================================================
export function PhaseCard({
  phase,
  title,
  description,
  gradient = "from-primary/20 to-violet-500/20",
  children,
}: {
  phase: string;
  title: string;
  description: string;
  gradient?: string;
  children?: ReactNode;
}) {
  return (
    <div
      className="group relative rounded-2xl bg-[#0a0a0c] p-6 sm:p-8 overflow-hidden transition-all duration-500 hover:-translate-y-1 shadow-xl hover:shadow-[0_20px_40px_-15px_rgba(0,0,0,0.5)] border border-white/[0.08] hover:border-primary/30"
    >
      {/* Dynamic Hover Gradient */}
      <div className={`absolute inset-0 opacity-0 group-hover:opacity-10 bg-gradient-to-br ${gradient} transition-opacity duration-500 pointer-events-none`} />
      
      {/* Top subtle highlight */}
      <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-white/20 to-transparent opacity-30 group-hover:opacity-100 transition-opacity duration-500" />

      <div className="relative z-10 flex items-start gap-4 sm:gap-6">
        <div className="flex h-12 w-12 sm:h-14 sm:w-14 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-b from-white/10 to-white/5 border border-white/10 font-mono text-lg sm:text-xl font-bold text-white shadow-[inset_0_1px_1px_rgba(255,255,255,0.2)]">
          {phase}
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-bold text-white text-lg sm:text-xl tracking-tight">{title}</h3>
          <p className="mt-2 text-sm sm:text-base text-white/60 leading-relaxed font-light">{description}</p>
          {children && <div className="mt-5">{children}</div>}
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// TIP BOX - Tips, warnings, info boxes
// =============================================================================
export function TipBox({
  children,
  variant = "tip",
}: {
  children: ReactNode;
  variant?: "tip" | "warning" | "info";
}) {
  const config = {
    tip: {
      icon: <Lightbulb className="h-5 w-5" />,
      gradient: "from-amber-500/10 to-orange-500/5",
      border: "border-amber-500/20",
      iconColor: "text-amber-400",
      title: "Pro Tip",
    },
    warning: {
      icon: <AlertTriangle className="h-5 w-5" />,
      gradient: "from-red-500/10 to-rose-500/5",
      border: "border-red-500/20",
      iconColor: "text-red-400",
      title: "Warning",
    },
    info: {
      icon: <Info className="h-5 w-5" />,
      gradient: "from-primary/10 to-violet-500/5",
      border: "border-primary/20",
      iconColor: "text-primary",
      title: "Key Insight",
    },
  };
  const c = config[variant];

  return (
    <div
      className={`relative rounded-2xl border ${c.border} bg-gradient-to-br ${c.gradient} p-4 sm:p-5 glass-subtle`}
    >
      <div className="flex gap-3 sm:gap-4">
        <div className={`shrink-0 mt-0.5 ${c.iconColor}`}>{c.icon}</div>
        <div className="min-w-0">
          <span
            className={`text-[0.65rem] sm:text-xs font-bold ${c.iconColor} uppercase tracking-wider`}
          >
            {c.title}
          </span>
          <div className="mt-1.5 sm:mt-2 text-white/70 text-xs sm:text-sm leading-relaxed">{children}</div>
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// TOOL PILL - Small badge for tool names
// =============================================================================
export function ToolPill({ children }: { children: ReactNode }) {
  return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-primary/10 border border-primary/20 text-primary text-xs font-mono font-medium whitespace-nowrap">
      {children}
    </span>
  );
}

// =============================================================================
// INLINE CODE
// =============================================================================
export function IC({ children }: { children: ReactNode }) {
  return (
    <code className="px-1.5 py-0.5 rounded-md bg-white/[0.06] border border-white/[0.08] text-emerald-400 text-xs sm:text-sm font-mono break-all">
      {children}
    </code>
  );
}

// =============================================================================
// HIGHLIGHT - Gradient highlighted text
// =============================================================================
export function Hl({ children }: { children: ReactNode }) {
  return (
    <span className="font-semibold bg-gradient-to-r from-primary to-violet-400 bg-clip-text text-transparent">
      {children}
    </span>
  );
}

// =============================================================================
// BULLET LIST
// =============================================================================
export function BulletList({ items }: { items: (string | ReactNode)[] }) {
  return (
    <ul className="space-y-3">
      {items.map((item, i) => (
        <li key={i} className="flex items-start gap-3.5">
          <div className="mt-[0.6rem] h-1.5 w-1.5 rounded-full bg-primary/70 shrink-0 shadow-[0_0_8px_var(--color-primary)]" />
          <span className="text-zinc-400 text-[0.95rem] sm:text-[1.05rem] leading-[1.7] tracking-[-0.01em]">{item}</span>
        </li>
      ))}
    </ul>
  );
}

// =============================================================================
// NUMBERED LIST
// =============================================================================
export function NumberedList({ items }: { items: (string | ReactNode)[] }) {
  return (
    <ol className="space-y-4">
      {items.map((item, i) => (
        <li key={i} className="flex items-start gap-4">
          <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-primary/30 to-violet-500/30 text-[0.65rem] font-bold text-white/90 shadow-[inset_0_1px_1px_rgba(255,255,255,0.2)]">
            {i + 1}
          </span>
          <span className="text-zinc-400 text-[0.95rem] sm:text-[1.05rem] leading-[1.7] tracking-[-0.01em] pt-0.5">{item}</span>
        </li>
      ))}
    </ol>
  );
}

// =============================================================================
// DIVIDER
// =============================================================================
export function Divider() {
  return (
    <div className="my-12 sm:my-16 h-px bg-gradient-to-r from-transparent via-white/10 to-transparent" />
  );
}

// =============================================================================
// STAT CARD - For metrics and numbers
// =============================================================================
export function StatCard({
  value,
  label,
  sublabel,
}: {
  value: string;
  label: string;
  sublabel?: string;
}) {
  return (
    <div className="relative rounded-2xl border border-white/[0.08] bg-white/[0.02] p-4 sm:p-5 text-center backdrop-blur-xl">
      <div className="text-2xl sm:text-3xl font-bold bg-gradient-to-r from-primary to-violet-400 bg-clip-text text-transparent">
        {value}
      </div>
      <div className="mt-1 text-xs sm:text-sm text-white/60 font-medium">{label}</div>
      {sublabel && <div className="mt-0.5 text-[0.65rem] text-white/35">{sublabel}</div>}
    </div>
  );
}

// =============================================================================
// PRINCIPLE CARD - For the 13 key principles
// =============================================================================
export function PrincipleCard({
  number,
  title,
  children,
  gradient,
}: {
  number: string;
  title: string;
  children: ReactNode;
  gradient?: string;
}) {
  const [open, setOpen] = useState(false);
  const hasContent = children != null;

  return (
    <div
      className={`group relative rounded-2xl border border-white/[0.08] bg-[#0a0a0c] overflow-hidden transition-all duration-300 hover:border-white/20 shadow-lg hover:shadow-[0_15px_30px_-15px_rgba(255,255,255,0.05)]`}
    >
      <div className={`absolute inset-0 opacity-0 group-hover:opacity-[0.03] bg-gradient-to-br ${gradient || "from-white to-transparent"} transition-opacity duration-500 pointer-events-none`} />
      
      <button
        onClick={() => hasContent && setOpen(!open)}
        className={`w-full relative z-10 flex items-start gap-4 p-5 sm:p-6 text-left ${hasContent ? "cursor-pointer" : "cursor-default"}`}
        aria-expanded={open}
        disabled={!hasContent}
      >
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-b from-primary/20 to-primary/5 border border-primary/20 font-mono text-sm font-bold text-primary shadow-[inset_0_1px_1px_rgba(255,255,255,0.1)] group-hover:scale-105 group-hover:border-primary/40 transition-all duration-300">
          {number}
        </div>
        <div className="flex-1 min-w-0 flex items-center h-10">
          <h4 className="font-semibold text-white/90 text-base sm:text-lg leading-snug tracking-tight group-hover:text-white transition-colors duration-300">{title}</h4>
        </div>
        {hasContent && (
          <div className="flex h-10 items-center">
            <ChevronDown className={`h-5 w-5 text-white/30 shrink-0 transition-transform duration-300 group-hover:text-white/50 ${open ? "rotate-180" : ""}`} />
          </div>
        )}
      </button>
      <AnimatePresence>
        {open && hasContent && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.3, ease: [0.16, 1, 0.3, 1] }}
            className="overflow-hidden relative z-10"
          >
            <div className="px-5 sm:px-6 pb-5 sm:pb-6 pt-0 text-white/60 text-sm sm:text-[0.95rem] leading-[1.7] border-t border-white/[0.05] mt-0 pt-5 font-light">
              {children}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// =============================================================================
// OPERATOR CARD - For the 8 operators in Section 21
// =============================================================================
export function OperatorCard({
  number,
  name,
  definition,
  trigger,
  failureMode,
  children,
}: {
  number: string;
  name: string;
  definition: string;
  trigger?: string;
  failureMode?: string;
  children?: ReactNode;
}) {
  return (
    <div className="group relative rounded-2xl border border-white/[0.08] bg-[#0a0a0c] p-5 sm:p-6 shadow-lg transition-all duration-300 hover:border-emerald-500/30 hover:shadow-[0_10px_30px_-10px_rgba(16,185,129,0.15)] space-y-4 overflow-hidden">
      <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-emerald-500/20 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-500" />
      
      <div className="relative z-10 flex items-start gap-4">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-b from-emerald-500/20 to-emerald-500/5 border border-emerald-500/30 font-mono text-sm font-bold text-emerald-400 shadow-[inset_0_1px_1px_rgba(255,255,255,0.1)]">
          {number}
        </div>
        <div className="min-w-0">
          <h4 className="font-semibold text-white text-base sm:text-lg tracking-tight">{name}</h4>
          <p className="mt-1.5 text-sm sm:text-[0.95rem] text-white/60 leading-relaxed font-light">{definition}</p>
        </div>
      </div>
      {trigger && (
        <div className="relative z-10 flex items-start gap-3 text-sm text-white/50 pl-[3.5rem]">
          <span className="text-emerald-400/80 font-medium shrink-0 uppercase tracking-wider text-xs mt-0.5">Trigger</span>
          <span className="leading-relaxed">{trigger}</span>
        </div>
      )}
      {failureMode && (
        <div className="relative z-10 flex items-start gap-3 text-sm text-white/50 pl-[3.5rem]">
          <span className="text-red-400/80 font-medium shrink-0 uppercase tracking-wider text-xs mt-0.5">Failure</span>
          <span className="leading-relaxed">{failureMode}</span>
        </div>
      )}
      {children && <div className="relative z-10 pl-[3.5rem] text-sm text-white/60 pt-2 border-t border-white/[0.05] mt-4 font-light leading-relaxed">{children}</div>}
    </div>
  );
}

// =============================================================================
// FLYWHEEL DIAGRAM - SVG visualization with animated flow
// =============================================================================
export function FlywheelDiagram() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-50px" });
  const prefersReducedMotion = useReducedMotion();
  const rm = prefersReducedMotion ?? false;

  const nodes = [
    { id: "human-intent", label: "Human Intent", x: 80, y: 50, color: "#22d3ee" },
    { id: "markdown-plan", label: "Markdown Plan", x: 280, y: 50, color: "#a78bfa" },
    { id: "building-beads", label: "Beads", x: 460, y: 50, color: "#f472b6" },
    { id: "swarm-execution", label: "Swarm Execution", x: 460, y: 180, color: "#34d399" },
    { id: "review-loops", label: "Reviews / Tests", x: 280, y: 180, color: "#fbbf24" },
    { id: "memory-and-knowledge", label: "Memory / QA", x: 80, y: 180, color: "#818cf8" },
  ];

  return (
    <div ref={ref} className="relative flex justify-center py-8 -mx-4 sm:mx-0 group">
      {/* Background glow for the flywheel */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,oklch(0.75_0.18_195/0.1),transparent_60%)] animate-pulse-glow pointer-events-none" />
      
      <svg viewBox="0 0 540 240" className="w-full max-w-xl relative z-10" role="img" aria-label="Flywheel diagram showing the compounding loop from Human Intent through Markdown Plan, Beads, Swarm Execution, Reviews, and Memory">
        <defs>
          <marker id="guide-fwd" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
            <path d="M0,0 L8,3 L0,6" fill="white" opacity="0.5" />
          </marker>
          {/* Animated dash for flow */}
          {!rm && (
            <style>{`
              @keyframes dash-flow { to { stroke-dashoffset: -20; } }
              .flow-line { animation: dash-flow 1.5s linear infinite; }
              .group:hover .flow-line { animation-duration: 0.8s; stroke-opacity: 0.4; }
            `}</style>
          )}
        </defs>
        {/* Connection lines with flow animation */}
        {[
          { x1: 140, y1: 50, x2: 240, y2: 50 },
          { x1: 370, y1: 50, x2: 420, y2: 50 },
          { x1: 460, y1: 80, x2: 460, y2: 150 },
          { x1: 420, y1: 180, x2: 340, y2: 180 },
          { x1: 240, y1: 180, x2: 140, y2: 180 },
          { x1: 80, y1: 150, x2: 80, y2: 80 },
        ].map((line, i) => (
          <line
            key={i}
            {...line}
            stroke="white"
            strokeOpacity="0.2"
            strokeWidth="1.5"
            strokeDasharray="4 4"
            className={`transition-all duration-500 ${rm ? "" : "flow-line"}`}
            markerEnd="url(#guide-fwd)"
          />
        ))}

        {nodes.map((node, i) => (
          <motion.a
            href={`#${node.id}`}
            key={i}
            initial={rm ? {} : { opacity: 0, scale: 0.8 }}
            animate={isInView ? { opacity: 1, scale: 1 } : {}}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            transition={{
              duration: rm ? 0 : 0.4,
              delay: rm ? 0 : i * 0.08,
              type: "spring",
              stiffness: 300,
              damping: 25,
            }}
            className="cursor-pointer outline-none"
          >
            <rect
              x={node.x - 60}
              y={node.y - 18}
              width="120"
              height="36"
              rx="10"
              fill={node.color}
              fillOpacity="0.15"
              stroke={node.color}
              strokeOpacity="0.4"
              strokeWidth="1.5"
              className="transition-all duration-300 hover:fill-opacity-30 hover:stroke-opacity-100"
            />
            <text
              x={node.x}
              y={node.y + 4}
              textAnchor="middle"
              fill="white"
              fontSize="12"
              fontWeight="600"
              opacity="0.9"
              className="pointer-events-none"
            >
              {node.label}
            </text>
          </motion.a>
        ))}
      </svg>
    </div>
  );
}

// =============================================================================
// TABLE OF CONTENTS - Desktop sidebar + mobile drawer
// =============================================================================
interface TocItem {
  id: string;
  label: string;
  number?: string;
}

export function TableOfContents({ items }: { items: TocItem[] }) {
  const [activeId, setActiveId] = useState<string>("");
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setActiveId(entry.target.id);
          }
        }
      },
      // Narrower intersection margin to make the active section more accurate
      { rootMargin: "-15% 0% -80% 0%", threshold: 0 },
    );

    for (const item of items) {
      const el = document.getElementById(item.id);
      if (el) observer.observe(el);
    }
    return () => observer.disconnect();
  }, [items]);

  // Progress calculation
  const activeIndex = items.findIndex(i => i.id === activeId);
  const progress = items.length > 0 ? (Math.max(0, activeIndex) / (items.length - 1)) * 100 : 0;

  const tocContent = (
    <nav className="relative space-y-1" aria-label="Table of contents">
      {/* Progress bar */}
      <div className="mb-4 px-3">
        <div className="flex items-center justify-between text-[0.65rem] text-white/40 mb-1.5 uppercase tracking-wider font-semibold">
          <span>Progress</span>
          <span>{Math.round(progress)}%</span>
        </div>
        <div className="h-1 rounded-full bg-white/[0.06] overflow-hidden">
          <motion.div
            className="h-full rounded-full bg-gradient-to-r from-primary to-violet-500 shadow-glow-sm"
            initial={{ width: 0 }}
            animate={{ width: `${progress}%` }}
            transition={{ duration: 0.3 }}
          />
        </div>
      </div>
      {items.map((item, index) => {
        const isActive = activeId === item.id;
        const isPast = activeIndex > index;

        return (
          <a
            key={item.id}
            href={`#${item.id}`}
            onClick={() => setMobileOpen(false)}
            className={`relative flex items-center gap-3 px-3 py-2 text-[0.8rem] sm:text-sm transition-all duration-300 rounded-lg group ${
              isActive
                ? "text-primary font-medium"
                : isPast
                ? "text-white/30 hover:text-white/50"
                : "text-white/60 hover:text-white/90"
            }`}
          >
            {isActive && (
              <motion.div
                layoutId="toc-indicator"
                className="absolute left-0 w-0.5 h-[60%] bg-primary shadow-[0_0_10px_oklch(0.75_0.18_195)] rounded-r-full"
                transition={{ type: "spring", stiffness: 300, damping: 30 }}
              />
            )}
            
            {/* Hover highlight background */}
            <div className={`absolute inset-0 rounded-lg transition-colors duration-200 ${isActive ? "bg-primary/[0.08]" : "group-hover:bg-white/[0.03]"}`} />

            {item.number != null && (
              <span className={`relative z-10 font-mono text-[0.65rem] w-4 text-center ${isActive ? "opacity-100 text-primary" : "opacity-40"}`}>
                {item.number}
              </span>
            )}
            <span className="relative z-10 truncate">{item.label}</span>
          </a>
        );
      })}
    </nav>
  );

  return (
    <>
      {/* Desktop TOC */}
      <div className="hidden xl:block">
        {tocContent}
      </div>

      {/* Mobile TOC trigger */}
      <div className="xl:hidden fixed bottom-6 right-6 z-50">
        <button
          onClick={() => setMobileOpen(!mobileOpen)}
          className="flex h-12 w-12 items-center justify-center rounded-full bg-primary/90 text-white shadow-lg shadow-primary/30 backdrop-blur-sm transition-transform active:scale-95"
          aria-label="Toggle table of contents"
        >
          {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </div>

      {/* Mobile TOC drawer */}
      <AnimatePresence>
        {mobileOpen && (
          <>
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="fixed inset-0 bg-black/60 backdrop-blur-sm z-40 xl:hidden"
              onClick={() => setMobileOpen(false)}
            />
            <motion.div
              initial={{ x: "100%" }}
              animate={{ x: 0 }}
              exit={{ x: "100%" }}
              transition={{ type: "spring", stiffness: 300, damping: 30 }}
              className="fixed right-0 top-0 bottom-0 w-72 bg-[oklch(0.14_0.01_260)] border-l border-white/[0.08] z-50 xl:hidden overflow-y-auto p-4 pt-6"
            >
              <div className="flex items-center justify-between mb-4">
                <span className="text-xs font-semibold text-white/50 uppercase tracking-wider">Contents</span>
                <button
                  onClick={() => setMobileOpen(false)}
                  className="p-1 rounded-lg hover:bg-white/5 text-white/40"
                  aria-label="Close"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
              {tocContent}
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </>
  );
}
