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
  Info,
  Terminal,
  Zap,
} from "lucide-react";
import {
  CodeBlock as SharedCodeBlock,
  type CodeBlockProps as SharedCodeBlockProps,
} from "@/components/ui/code-block";
import { copyTextToClipboard } from "@/lib/utils";

export { FlywheelDiagram } from "./flywheel-diagram";

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
      initial={rm ? {} : { opacity: 0, y: 40 }}
      animate={isInView ? { opacity: 1, y: 0 } : {}}
      transition={rm ? {} : { type: "spring", stiffness: 80, damping: 20, mass: 1 }}
      className="relative scroll-mt-32 pb-24 md:pb-32 w-full"
    >
      {/* Subtle Side Label for desktop */}
      {typeof number === "string" && number !== "" && (
        <div className="absolute -left-32 top-0 hidden xl:flex items-center justify-end w-24 pointer-events-none select-none">
          <span className="text-[8rem] font-black text-white/[0.015] leading-none tracking-tighter">
            {number.padStart(2, '0')}
          </span>
        </div>
      )}

      {/* Section header */}
      <div className="relative mb-16 group">
        <div className="flex flex-col sm:flex-row sm:items-start gap-5 sm:gap-6">
          {typeof number === "string" && number !== "" && (
            <div className="flex h-12 w-12 sm:h-16 sm:w-16 shrink-0 items-center justify-center rounded-[1rem] bg-gradient-to-b from-[#FF5500]/10 to-transparent border border-[#FF5500]/20 font-mono text-2xl sm:text-3xl font-black text-[#FF5500] shadow-[inset_0_1px_1px_rgba(255,255,255,0.1),0_8px_16px_-4px_rgba(0,0,0,0.5)] transition-all duration-500 group-hover:bg-[#FF5500]/20 group-hover:border-[#FF5500]/40 group-hover:shadow-[0_0_30px_rgba(255,85,0,0.3)]">
              <span className="bg-gradient-to-br from-white to-[#FF5500]/80 bg-clip-text text-transparent">{number}</span>
            </div>
          )}

          <div className="flex flex-1 min-w-0 items-start gap-4 sm:gap-5">
            {icon && (
              <div className="mt-1 sm:mt-2 flex h-10 w-10 sm:h-14 sm:w-14 shrink-0 items-center justify-center rounded-[0.85rem] border border-[#FF5500]/20 bg-[#05070a] text-[#FF5500] shadow-[inset_0_1px_1px_rgba(255,255,255,0.05)] transition-all duration-500 group-hover:border-[#FF5500]/40 group-hover:bg-[#FF5500]/10 group-hover:shadow-[0_0_20px_rgba(255,85,0,0.25)] group-hover:scale-105">
                {icon}
              </div>
            )}

            <div className="flex-1 min-w-0">
              {title.startsWith('Phase ') ? (
                <div className="flex flex-col gap-2">
                  <span className="text-[#FF5500]/80 font-mono text-[0.65rem] sm:text-[0.75rem] uppercase tracking-[0.3em] font-bold flex items-center gap-3">
                    <span className="w-8 h-px bg-[#FF5500]/40" />
                    {title.split(':')[0]}
                  </span>
                  <h2 className="text-3xl sm:text-5xl md:text-6xl font-black text-white tracking-tighter leading-[1.1] drop-shadow-lg group-hover:text-zinc-100 transition-colors">
                    {title.split(':').slice(1).join(':').trim()}
                  </h2>
                </div>
              ) : (
                <h2 className="text-3xl sm:text-5xl md:text-6xl font-black text-white tracking-tighter leading-[1.1] pt-0.5 drop-shadow-lg group-hover:text-zinc-100 transition-colors">
                  {title}
                </h2>
              )}
            </div>
          </div>
        </div>

        {/* Minimalist divider */}
        <div className="mt-8 sm:mt-12 h-[1px] w-full bg-gradient-to-r from-white/[0.08] via-white/[0.02] to-transparent relative overflow-hidden">
          <motion.div 
            initial={{ x: "-100%" }}
            animate={isInView ? { x: "200%" } : {}}
            transition={{ duration: 2.5, ease: "easeInOut", repeat: Infinity, repeatDelay: 4 }}
            className="absolute inset-y-0 w-1/4 bg-gradient-to-r from-transparent via-[#FF5500]/40 to-transparent"
          />
        </div>
      </div>
      <div className="space-y-10 sm:space-y-12 max-w-[85ch]">{children}</div>
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
    <div className="mt-20 first:mt-12 group/sub relative">
      <div className="absolute -left-4 sm:-left-8 top-1.5 bottom-0 w-[3px] bg-white/[0.02] group-hover/sub:bg-[#FF5500]/20 transition-colors duration-500 hidden sm:block rounded-full" />
      <h3 className="text-2xl sm:text-3xl font-bold text-white mb-8 flex items-center gap-4 tracking-tight relative">
        <div className="absolute -left-4 sm:-left-8 top-1/2 -translate-y-1/2 w-[3px] h-0 bg-[#FF5500] transition-all duration-500 group-hover/sub:h-full hidden sm:block shadow-[0_0_10px_rgba(255,85,0,0.6)] rounded-full" />
        {title}
      </h3>
      <div className="space-y-6 sm:space-y-8">{children}</div>
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
      className={`text-[1.1rem] sm:text-[1.2rem] leading-[1.8] tracking-[-0.01em] ${
        highlight 
          ? "text-white font-normal bg-gradient-to-r from-[#FF5500]/10 to-transparent p-6 sm:p-8 rounded-2xl border-l-4 border-[#FF5500] shadow-[inset_0_1px_1px_rgba(255,255,255,0.05)]" 
          : "text-zinc-300 font-light"
      }`}
    >
      {children}
    </p>
  );
}

// =============================================================================
// BLOCKQUOTE - Clean typographic quote
// =============================================================================
export function BlockQuote({ children }: { children: ReactNode }) {
  return (
    <div className="relative pl-8 sm:pl-12 py-8 my-12 border-l-4 border-[#FF5500]/40 bg-gradient-to-r from-white/[0.02] to-transparent rounded-r-3xl group/quote hover:border-[#FF5500] transition-colors duration-500">
      <Quote className="absolute left-4 top-8 h-8 w-8 text-[#FF5500]/20 -scale-x-100 pointer-events-none group-hover/quote:text-[#FF5500]/40 transition-colors duration-500" />
      <div className="relative text-white/90 italic leading-[1.8] text-[1.2rem] sm:text-[1.35rem] font-light tracking-tight">
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
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

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
    const escaped = text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const keywords = ['Search', 'Review', 'Read', 'Write', 'Fix', 'Create', 'Update', 'Do we have', 'OK', 'Look', 'Execute'];
    let highlighted = escaped;
    keywords.forEach(kw => {
      const regex = new RegExp(`\\b(${kw})\\b`, 'g');
      highlighted = highlighted.replace(regex, '<span class="text-[#FF5500] font-medium">$1</span>');
    });
    highlighted = highlighted.replace(/(\[[A-Z_]+\])/g, '<span class="text-white/60 font-medium bg-white/10 px-1 rounded">$1</span>');
    return highlighted;
  };

  return (
    <div className="group relative rounded-2xl border border-white/[0.06] bg-[#0A0D14] overflow-hidden transition-all duration-500 hover:border-[#FF5500]/30 my-12 shadow-xl">
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.03] mix-blend-overlay pointer-events-none" />
      
      {/* Top bar — refined metal */}
      <div className="relative flex items-center justify-between px-5 sm:px-6 py-3.5 bg-white/[0.015] border-b border-white/[0.04] z-10 backdrop-blur-md">
        <div className="flex items-center gap-4">
          <div className="flex gap-1.5">
            <div className="w-2.5 h-2.5 rounded-full bg-white/10 group-hover:bg-[#FF5500] transition-colors duration-500 shadow-sm" />
            <div className="w-2.5 h-2.5 rounded-full bg-white/10 group-hover:bg-[#FFBD2E] transition-colors duration-500 shadow-sm" />
            <div className="w-2.5 h-2.5 rounded-full bg-white/10 group-hover:bg-[#FF5500] transition-colors duration-500 shadow-sm" />
          </div>
          <span className="ml-2 text-[0.7rem] font-bold text-white/50 tracking-wider uppercase">{title}</span>
        </div>
        <motion.button
          whileTap={{ scale: 0.95 }}
          onClick={handleCopy}
          className="flex items-center gap-2 rounded-lg bg-white/[0.03] px-3 py-1.5 text-[0.7rem] font-medium text-white/60 hover:bg-white/10 hover:text-white border border-white/[0.04] transition-all duration-200 hover:border-[#FF5500]/30 hover:text-[#FF5500]"
        >
          {copied ? <Check className="h-3.5 w-3.5 text-[#FF5500]" /> : <Copy className="h-3.5 w-3.5" />}
          <span className="hidden sm:inline">{copied ? "Copied" : "Copy"}</span>
        </motion.button>
      </div>

      {/* Prompt body */}
      <div className="relative z-10 p-6 sm:p-8">
        <div
          className="text-[0.95rem] sm:text-[1.05rem] text-zinc-300 whitespace-pre-wrap font-mono font-normal leading-[1.7] overflow-x-auto scrollbar-hide selection:bg-[#FF5500]/20 selection:text-white"
          dangerouslySetInnerHTML={{ __html: highlightPrompt(prompt) }}
        />
      </div>

      {/* Metadata footer — clean & informative */}
      <AnimatePresence>
        {(where || whyItWorks) && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="relative z-10 bg-black/20 border-t border-white/[0.04] p-6 sm:p-8 space-y-6"
          >
            {where && (
              <div className="flex items-start gap-4">
                <div className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-md bg-white/[0.05] border border-white/[0.05]">
                  <Terminal className="h-3 w-3 text-zinc-400" />
                </div>
                <div>
                  <span className="text-[0.65rem] font-bold text-white/30 uppercase tracking-widest block mb-1">Context</span>
                  <p className="text-[0.9rem] text-zinc-400 font-light leading-relaxed">{where}</p>
                </div>
              </div>
            )}
            {whyItWorks && (
              <div className="flex items-start gap-4">
                <div className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-md bg-[#FF5500]/10 border border-[#FF5500]/20">
                  <Lightbulb className="h-3 w-3 text-[#FF5500]" />
                </div>
                <div>
                  <span className="text-[0.65rem] font-bold text-[#FF5500]/50 uppercase tracking-widest block mb-1">Psychology</span>
                  <p className="text-[0.9rem] text-zinc-400 font-light leading-relaxed italic">{whyItWorks}</p>
                </div>
              </div>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// =============================================================================
// DATA TABLE - Premium Minimalist Grid Hybrid
// =============================================================================
export function DataTable({
  headers,
  rows,
}: {
  headers: string[];
  rows: (string | ReactNode)[][];
}) {
  const isDefinitionList = headers.length === 2 || headers.length === 3;

  if (isDefinitionList) {
    return (
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-2 xl:grid-cols-3 gap-6 my-12 relative z-10">
        {rows.map((row, ri) => (
          <div key={ri} className="flex flex-col p-6 sm:p-8 rounded-[2rem] bg-[#05070A] border border-white/[0.04] shadow-2xl relative group/card hover:border-[#FF5500]/30 transition-all duration-500 hover:-translate-y-2 overflow-hidden">
            <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.02] mix-blend-overlay pointer-events-none" />
            <div className="absolute inset-0 bg-gradient-to-br from-[#FF5500]/5 to-transparent opacity-0 group-hover/card:opacity-100 transition-opacity duration-500 pointer-events-none" />
            
            <div className="relative z-10 flex flex-col h-full">
              <div className="text-[0.65rem] font-bold text-[#FF5500]/80 uppercase tracking-[0.2em] mb-3 flex items-center gap-2">
                <div className="w-1.5 h-1.5 rounded-full bg-[#FF5500] shadow-[0_0_8px_rgba(255,85,0,0.6)]" />
                {headers[0]}
              </div>
              <div className="text-xl sm:text-2xl font-black text-white tracking-tight mb-5 group-hover/card:text-[#FF5500] transition-colors leading-[1.15]">
                {row[0]}
              </div>
              
              {headers[1] && row[1] && (
                <div className="mb-6 flex-1">
                  <div className="text-[0.6rem] font-bold text-white/30 uppercase tracking-[0.15em] mb-2">{headers[1]}</div>
                  <div className="text-[1.05rem] text-zinc-300 font-light leading-relaxed">{row[1]}</div>
                </div>
              )}
              
              {headers[2] && row[2] && (
                <div className="mt-auto pt-5 border-t border-white/[0.06]">
                  <div className="text-[0.6rem] font-bold text-white/30 uppercase tracking-[0.15em] mb-2">{headers[2]}</div>
                  <div className="text-[1rem] text-zinc-400 font-medium italic leading-relaxed">{row[2]}</div>
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="relative group my-16">
      <div className="absolute -inset-0.5 bg-gradient-to-r from-[#FF5500]/20 via-violet-500/10 to-transparent rounded-[2rem] blur-xl opacity-0 group-hover:opacity-50 transition-opacity duration-700 pointer-events-none" />
      <div className="relative overflow-x-auto rounded-[2rem] border border-white/[0.05] bg-[#05070a] shadow-2xl transition-all duration-500 group-hover:border-[#FF5500]/30">
        <table className="w-full text-sm min-w-[600px] border-collapse">
          <thead>
            <tr className="border-b border-white/[0.08] bg-white/[0.02]">
              {headers.map((h, i) => (
                <th
                  key={i}
                  className="px-8 py-6 text-left text-[0.7rem] font-black text-[#FF5500] uppercase tracking-[0.2em] whitespace-nowrap"
                >
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-white/[0.03]">
            {rows.map((row, ri) => (
              <tr
                key={ri}
                className="transition-colors duration-300 hover:bg-white/[0.02] hover:bg-gradient-to-r hover:from-[#FF5500]/[0.03] hover:to-transparent group/row"
              >
                {row.map((cell, ci) => (
                  <td key={ci} className="px-8 py-6 text-[1.05rem] font-light text-zinc-300 align-top leading-relaxed">
                    {ci === 0 ? <span className="text-white font-medium group-hover/row:text-[#FF5500] transition-colors">{cell}</span> : cell}
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
  gradient = "from-primary/10 to-violet-500/10",
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
      className="group relative rounded-3xl bg-[#05070a] p-8 sm:p-12 overflow-hidden transition-all duration-700 hover:-translate-y-2 border border-white/[0.04] hover:border-[#FF5500]/30 shadow-2xl"
    >
      {/* Background layer */}
      <div className={`absolute inset-0 opacity-0 group-hover:opacity-100 bg-gradient-to-br ${gradient} transition-opacity duration-1000 pointer-events-none mix-blend-screen`} />
      
      <div className="relative z-10 flex flex-col gap-8">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-6">
          <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-2xl bg-white/[0.02] border border-white/5 font-mono text-2xl font-black text-[#FF5500] shadow-[inset_0_1px_1px_rgba(255,255,255,0.05)] transition-all duration-700 group-hover:scale-110 group-hover:bg-[#FF5500]/10 group-hover:border-[#FF5500]/40 group-hover:shadow-[0_0_30px_rgba(255,85,0,0.3)]">
            {phase}
          </div>
          <div className="h-px flex-1 bg-gradient-to-r from-white/[0.08] to-transparent hidden sm:block" />
          <div className="text-[0.65rem] font-bold text-white/30 uppercase tracking-widest">Step Verification</div>
        </div>

        <div className="max-w-3xl">
          <h3 className="font-bold text-white text-2xl sm:text-3xl tracking-tight mb-4 group-hover:text-[#FF5500] transition-colors duration-500">{title}</h3>
          <p className="text-[1.05rem] sm:text-[1.15rem] text-zinc-400 leading-relaxed font-light">{description}</p>
          {children && <div className="mt-8">{children}</div>}
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// TIP BOX - Refined & Minimalist
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
      color: "text-[#FFBD2E]",
      bg: "bg-[#FFBD2E]/[0.03]",
      border: "border-[#FFBD2E]/10",
      title: "Insight",
      dot: "bg-[#FFBD2E]",
    },
    warning: {
      icon: <AlertTriangle className="h-5 w-5" />,
      color: "text-[#FF5F56]",
      bg: "bg-[#FF5F56]/[0.03]",
      border: "border-[#FF5F56]/10",
      title: "Critical",
      dot: "bg-[#FF5F56]",
    },
    info: {
      icon: <Info className="h-5 w-5" />,
      color: "text-[#FF5500]",
      bg: "bg-[#FF5500]/[0.03]",
      border: "border-[#FF5500]/10",
      title: "Note",
      dot: "bg-[#FF5500]",
    },
  };
  const c = config[variant];

  return (
    <div
      className={`relative rounded-2xl border ${c.border} ${c.bg} p-6 sm:p-8 my-10 overflow-hidden group/tip shadow-lg`}
    >
      <div className="absolute top-0 right-0 p-6 opacity-[0.03] group-hover/tip:opacity-[0.08] transition-opacity duration-700 pointer-events-none group-hover/tip:scale-110">
        {c.icon}
      </div>
      
      <div className="relative z-10 flex flex-col gap-4">
        <div className={`text-[0.7rem] font-bold ${c.color} uppercase tracking-widest flex items-center gap-2.5`}>
          <div className={`w-1.5 h-1.5 rounded-full ${c.dot} shadow-[0_0_8px_currentColor] animate-pulse`} />
          {c.title}
        </div>
        <div className="text-zinc-300 text-[1rem] sm:text-[1.1rem] leading-[1.7] font-light tracking-[-0.01em] [&>strong]:text-white [&>strong]:font-medium">{children}</div>
      </div>
    </div>
  );
}

// =============================================================================
// TOOL PILL - Brutalist
// =============================================================================
export function ToolPill({ children }: { children: ReactNode }) {
  return (
    <span className="inline-flex items-center px-2.5 py-0.5 rounded border border-white/10 bg-white/[0.04] text-[#FF5500] text-[0.8rem] font-medium tracking-wide shadow-sm hover:border-[#FF5500]/40 hover:bg-[#FF5500]/5 transition-all cursor-help relative -top-px">
      {children}
    </span>
  );
}

// =============================================================================
// INLINE CODE
// =============================================================================
export function IC({ children }: { children: ReactNode }) {
  return (
    <code className="px-1.5 py-0.5 rounded bg-white/[0.05] border border-white/10 text-[#FF5500] text-[0.9em] font-mono font-medium relative -top-px mx-0.5">
      {children}
    </code>
  );
}

// =============================================================================
// HIGHLIGHT - Understated
// =============================================================================
export function Hl({ children }: { children: ReactNode }) {
  return (
    <span className="font-medium text-white border-b border-[#FF5500]/40 pb-[1px] relative">
      <span className="absolute inset-x-0 -bottom-px h-px bg-[#FF5500] opacity-0 hover:opacity-100 transition-opacity blur-sm" />
      {children}
    </span>
  );
}

// =============================================================================
// BULLET LIST
// =============================================================================
export function BulletList({ items }: { items: (string | ReactNode)[] }) {
  return (
    <ul className="space-y-3 sm:space-y-4 my-6">
      {items.map((item, i) => (
        <li key={i} className="flex items-start gap-3 sm:gap-4 group">
          <div className="mt-[0.6rem] relative flex items-center justify-center shrink-0">
            <div className="absolute inset-0 bg-[#FF5500]/30 blur-[4px] rounded-full opacity-0 group-hover:opacity-100 transition-opacity duration-300" />
            <div className="h-1.5 w-1.5 rounded-full bg-[#FF5500] group-hover:scale-125 transition-transform duration-300 shadow-[0_0_8px_rgba(255,85,0,0.6)]" />
          </div>
          <span className="text-zinc-300 text-[1.05rem] sm:text-[1.1rem] leading-[1.7] font-light group-hover:text-zinc-100 transition-colors duration-300">{item}</span>
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
    <ol className="space-y-4 sm:space-y-5 my-8">
      {items.map((item, i) => (
        <li key={i} className="flex items-start gap-4 sm:gap-5 group">
          <span className="flex h-7 w-7 sm:h-8 sm:w-8 shrink-0 items-center justify-center rounded-lg bg-white/[0.03] border border-white/10 text-xs sm:text-sm font-bold text-[#FF5500] shadow-[inset_0_1px_1px_rgba(255,255,255,0.05)] transition-all duration-300 group-hover:border-[#FF5500]/40 group-hover:bg-[#FF5500]/5 group-hover:shadow-[0_0_15px_rgba(255,85,0,0.2)] group-hover:-translate-y-0.5">
            {i + 1}
          </span>
          <span className="text-zinc-300 text-[1.05rem] sm:text-[1.1rem] leading-[1.7] font-light pt-0.5 group-hover:text-zinc-100 transition-colors duration-300">{item}</span>
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
    <div className="relative my-20 sm:my-28 flex items-center justify-center">
      <div className="absolute inset-x-0 h-px bg-gradient-to-r from-transparent via-white/[0.08] to-transparent" />
      <div className="absolute inset-x-0 h-px w-1/3 mx-auto bg-gradient-to-r from-transparent via-[#FF5500]/30 to-transparent blur-[1px]" />
      <div className="relative h-1.5 w-1.5 rounded-full bg-[#FF5500] shadow-[0_0_10px_rgba(255,85,0,0.8)]" />
    </div>
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
    <div className="group relative rounded-2xl border border-white/[0.06] bg-[#0A0D14] p-6 sm:p-8 text-center overflow-hidden transition-all duration-500 hover:-translate-y-1 hover:border-[#FF5500]/30 shadow-xl">
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.03] mix-blend-overlay pointer-events-none" />
      <div className="absolute inset-0 bg-gradient-to-b from-[#FF5500]/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-500 pointer-events-none" />
      <div className="relative z-10 text-3xl sm:text-5xl font-black bg-gradient-to-br from-white via-[#FF5500] to-violet-400 bg-clip-text text-transparent tracking-tighter drop-shadow-md group-hover:scale-105 transition-transform duration-500">
        {value}
      </div>
      <div className="relative z-10 mt-3 text-sm sm:text-base text-zinc-300 font-medium tracking-wide uppercase">{label}</div>
      {sublabel && <div className="relative z-10 mt-1.5 text-xs sm:text-sm text-zinc-500 font-light">{sublabel}</div>}
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
  const hasContent = children !== null && children !== undefined && children !== false;

  return (
    <div
      className="group relative rounded-2xl border border-white/[0.06] bg-[#0A0D14] overflow-hidden transition-all duration-500 hover:border-[#FF5500]/30 hover:-translate-y-1 my-6 shadow-xl"
    >
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.03] mix-blend-overlay pointer-events-none" />
      
      {/* Background Texture */}
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.03] mix-blend-overlay pointer-events-none" />
      
      {/* Hover glow overlay */}
      <div className={`absolute inset-0 opacity-0 group-hover:opacity-100 bg-gradient-to-br ${gradient || "from-[#FF5500]/[0.05] to-transparent"} transition-opacity duration-500 pointer-events-none`} />

      <button
        onClick={() => hasContent && setOpen(!open)}
        className={`w-full relative z-10 flex items-start sm:items-center gap-4 sm:gap-6 p-5 sm:p-7 text-left ${hasContent ? "cursor-pointer" : "cursor-default"}`}
        aria-expanded={open}
        disabled={!hasContent}
      >
        <div className="mt-0.5 sm:mt-0 flex h-10 w-10 sm:h-12 sm:w-12 shrink-0 items-center justify-center rounded-xl bg-white/[0.03] border border-white/10 font-mono text-sm sm:text-base font-bold text-[#FF5500] group-hover:scale-105 group-hover:bg-[#FF5500]/10 group-hover:border-[#FF5500]/40 group-hover:shadow-[0_0_20px_rgba(255,85,0,0.2)] transition-all duration-500">
          <span className="bg-gradient-to-br from-white to-[#FF5500]/80 bg-clip-text text-transparent">{number}</span>
        </div>
        <div className="flex-1 min-w-0">
          <h4 className="font-bold text-white text-lg sm:text-xl leading-tight tracking-tight group-hover:text-[#FF5500] transition-colors duration-300 pr-4">{title}</h4>
        </div>
        {hasContent && (
          <div className="flex items-center justify-center h-8 w-8 rounded-full bg-white/[0.03] border border-white/[0.05] group-hover:bg-[#FF5500]/10 group-hover:border-[#FF5500]/20 transition-all duration-300 shrink-0 self-center">
            <ChevronDown className={`h-4 w-4 text-zinc-400 group-hover:text-[#FF5500] transition-transform duration-500 ${open ? "rotate-180" : ""}`} />
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
            <div className="px-5 sm:px-7 pb-6 sm:pb-7 pt-0 text-zinc-300 text-[1rem] sm:text-[1.1rem] leading-[1.7] font-light border-t border-white/[0.04] mt-2 pt-6">
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
    <div className="group relative rounded-2xl border border-white/[0.06] bg-[#0A0D14] p-6 sm:p-8 transition-all duration-500 hover:border-[#FF5500]/40 hover:-translate-y-1 my-8 overflow-hidden shadow-xl">
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.03] mix-blend-overlay pointer-events-none" />
      <div className="absolute inset-0 bg-gradient-to-br from-[#FF5500]/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-500 pointer-events-none" />
      
      {/* Corner glow */}
      <div className="absolute -top-24 -right-24 h-48 w-48 rounded-full bg-[#FF5500]/10 blur-[60px] opacity-0 group-hover:opacity-100 transition-opacity duration-700 pointer-events-none" />

      <div className="relative z-10 flex flex-col sm:flex-row items-start gap-5 sm:gap-6">
        <div className="flex h-10 w-10 sm:h-12 sm:w-12 shrink-0 items-center justify-center rounded-xl bg-[#FF5500]/[0.05] border border-[#FF5500]/20 font-mono text-sm sm:text-base font-bold text-[#FF5500] group-hover:scale-105 group-hover:bg-[#FF5500]/10 group-hover:border-[#FF5500]/40 group-hover:shadow-[0_0_20px_rgba(255,85,0,0.2)] transition-all duration-500">
          <span>{number}</span>
        </div>
        <div className="min-w-0 flex-1">
          <h4 className="font-bold text-white text-lg sm:text-xl tracking-tight mb-1.5 group-hover:text-[#FF5500] transition-colors duration-300">{name}</h4>
          <p className="text-[1rem] sm:text-[1.05rem] text-zinc-300 leading-relaxed font-light">{definition}</p>
        </div>
      </div>
      
      <div className="relative z-10 mt-6 pt-6 border-t border-white/[0.04] space-y-4">
        {trigger && (
          <div className="flex items-start gap-4 bg-[#FF5500]/[0.03] rounded-xl p-4 sm:p-5 border border-[#FF5500]/10">
            <span className="flex items-center justify-center h-6 w-6 rounded-md bg-[#FF5500]/10 text-[#FF5500] shrink-0 mt-0.5">
              <Zap className="h-3 w-3" />
            </span>
            <div>
              <span className="text-[#FF5500]/80 font-bold uppercase tracking-widest text-[0.65rem] block mb-1">Trigger</span>
              <span className="text-zinc-300 text-sm sm:text-[0.95rem] leading-relaxed font-light">{trigger}</span>
            </div>
          </div>
        )}
        {failureMode && (
          <div className="flex items-start gap-4 bg-[#FF5F56]/[0.03] rounded-xl p-4 sm:p-5 border border-[#FF5F56]/10">
            <span className="flex items-center justify-center h-6 w-6 rounded-md bg-[#FF5F56]/10 text-[#FF5F56] shrink-0 mt-0.5">
              <AlertTriangle className="h-3 w-3" />
            </span>
            <div>
              <span className="text-[#FF5F56]/80 font-bold uppercase tracking-widest text-[0.65rem] block mb-1">Failure Mode</span>
              <span className="text-zinc-300 text-sm sm:text-[0.95rem] leading-relaxed font-light">{failureMode}</span>
            </div>
          </div>
        )}
        {children && <div className="text-zinc-400 text-[0.95rem] sm:text-[1rem] font-light leading-relaxed pt-2 px-1">{children}</div>}
      </div>
    </div>
  );
}


// =============================================================================
// TABLE OF CONTENTS - Desktop sidebar + mobile drawer
// =============================================================================
export function TableOfContents({
  items,
}: {
  items: { id: string; label: string; number: string }[];
}) {
  const [activeId, setActiveId] = useState<string>("");

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            setActiveId(entry.target.id);
          }
        });
      },
      { rootMargin: "-15% 0px -80% 0px" }
    );

    items.forEach((item) => {
      const el = document.getElementById(item.id);
      if (el) observer.observe(el);
    });

    return () => observer.disconnect();
  }, [items]);

  const handleClick = (e: React.MouseEvent<HTMLAnchorElement>, id: string) => {
    e.preventDefault();
    const el = document.getElementById(id);
    if (el) {
      el.scrollIntoView({ behavior: "smooth" });
      // Update URL hash without jumping
      window.history.pushState(null, "", `#${id}`);
    }
  };

  return (
    <nav className="relative">
      <div className="absolute left-3 top-0 bottom-0 w-px bg-white/[0.03]" />
      <ul className="space-y-1 relative">
        {items.map((item) => {
          const isActive = activeId === item.id;
          return (
            <li key={item.id} className="relative">
              {isActive && (
                <motion.div
                  layoutId="toc-indicator"
                  className="absolute left-[11px] top-[10px] w-1 h-1 rounded-full bg-primary shadow-[0_0_8px_rgba(var(--primary-rgb),0.8)] z-10"
                  transition={{ type: "spring", stiffness: 300, damping: 30 }}
                />
              )}
              <a
                href={`#${item.id}`}
                onClick={(e) => handleClick(e, item.id)}
                className={`group flex items-center gap-4 py-1.5 pl-8 pr-4 text-[0.8rem] transition-colors ${
                  isActive
                    ? "text-white font-medium"
                    : "text-zinc-500 hover:text-zinc-300 font-light"
                }`}
              >
                <span className={`font-mono text-[0.65rem] ${isActive ? "text-primary font-bold" : "text-zinc-600 group-hover:text-zinc-400"}`}>
                  {item.number.padStart(2, '0')}
                </span>
                <span className="truncate">{item.label}</span>
              </a>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

export * from "./plan-to-beads-viz";
export * from "./swarm-execution-viz";
export * from "./agent-mail-viz";
export * from "./plan-evolution-studio";
export * from "./flywheel-diagram";
export * from "./context-horizon-viz";
export * from "./convergence-viz";
