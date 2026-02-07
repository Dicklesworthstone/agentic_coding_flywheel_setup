"use client";

import { useState, type ReactNode } from "react";
import { motion } from "@/components/motion";
import {
  Check,
  Copy,
  Lightbulb,
  AlertTriangle,
  ChevronRight,
  Sparkles,
  Zap,
} from "lucide-react";
import {
  CodeBlock as SharedCodeBlock,
  type CodeBlockProps as SharedCodeBlockProps,
} from "@/components/ui/code-block";

// =============================================================================
// SECTION COMPONENT - Beautiful section dividers with gradient headers
// =============================================================================
interface SectionProps {
  title: string;
  icon?: ReactNode;
  children: ReactNode;
  delay?: number;
}

export function Section({ title, icon, children, delay = 0 }: SectionProps) {
  return (
    <motion.section
      initial={{ opacity: 0, y: 30 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.6, delay }}
      className="relative mb-16"
    >
      {/* Section header with gradient line */}
      <div className="flex items-center gap-4 mb-8">
        {icon && (
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-primary/20 to-violet-500/20 border border-primary/30 text-primary">
            {icon}
          </div>
        )}
        <h2 className="text-2xl md:text-3xl font-bold text-white tracking-tight">
          {title}
        </h2>
        <div className="flex-1 h-px bg-gradient-to-r from-white/20 to-transparent" />
      </div>
      <div className="space-y-6">{children}</div>
    </motion.section>
  );
}

// =============================================================================
// PARAGRAPH - Beautifully styled text
// =============================================================================
interface ParagraphProps {
  children: ReactNode;
  highlight?: boolean;
}

export function Paragraph({ children, highlight }: ParagraphProps) {
  return (
    <p
      className={`text-lg leading-relaxed ${
        highlight ? "text-white/80" : "text-white/60"
      }`}
    >
      {children}
    </p>
  );
}

// =============================================================================
// CODE BLOCK - Re-exported from shared ui/code-block
// =============================================================================
export function CodeBlock(
  props: Omit<SharedCodeBlockProps, "variant" | "copyable">,
) {
  return <SharedCodeBlock {...props} variant="terminal" copyable />;
}

// =============================================================================
// INLINE CODE - Small code snippets
// =============================================================================
export function InlineCode({ children }: { children: ReactNode }) {
  return (
    <code className="px-2 py-1 rounded-lg bg-primary/10 border border-primary/20 text-primary text-sm font-mono font-medium">
      {children}
    </code>
  );
}

// =============================================================================
// FEATURE CARD - Highlight key features/tools
// =============================================================================
interface FeatureCardProps {
  icon: ReactNode;
  title: string;
  description: string;
  gradient?: string;
}

export function FeatureCard({
  icon,
  title,
  description,
  gradient = "from-primary/20 to-violet-500/20",
}: FeatureCardProps) {
  return (
    <motion.div
      whileHover={{ y: -4, scale: 1.02 }}
      className="group relative rounded-2xl border border-white/[0.08] bg-white/[0.02] p-6 backdrop-blur-xl transition-all duration-500 hover:border-white/[0.15] hover:bg-white/[0.04]"
    >
      {/* Gradient overlay on hover */}
      <div
        className={`absolute inset-0 rounded-2xl bg-gradient-to-br ${gradient} opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 transition-opacity duration-500`}
      />

      <div className="relative flex items-start gap-4">
        <div
          className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br ${gradient} border border-white/10 text-white`}
        >
          {icon}
        </div>
        <div>
          <h3 className="font-bold text-white mb-1">{title}</h3>
          <p className="text-sm text-white/50">{description}</p>
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// FEATURE GRID - Grid of feature cards
// =============================================================================
export function FeatureGrid({ children }: { children: ReactNode }) {
  return (
    <div className="grid gap-4 sm:grid-cols-2">{children}</div>
  );
}

// =============================================================================
// TIP BOX - Helpful tips with icon
// =============================================================================
interface TipBoxProps {
  children: ReactNode;
  variant?: "tip" | "warning" | "info";
}

export function TipBox({ children, variant = "tip" }: TipBoxProps) {
  const config = {
    tip: {
      icon: <Lightbulb className="h-5 w-5" />,
      gradient: "from-amber-500/20 to-orange-500/20",
      border: "border-amber-500/30",
      iconColor: "text-amber-400",
      title: "Pro Tip",
    },
    warning: {
      icon: <AlertTriangle className="h-5 w-5" />,
      gradient: "from-red-500/20 to-rose-500/20",
      border: "border-red-500/30",
      iconColor: "text-red-400",
      title: "Warning",
    },
    info: {
      icon: <Sparkles className="h-5 w-5" />,
      gradient: "from-primary/20 to-violet-500/20",
      border: "border-primary/30",
      iconColor: "text-primary",
      title: "Note",
    },
  };

  const c = config[variant];

  return (
    <div
      className={`relative rounded-2xl border ${c.border} bg-gradient-to-br ${c.gradient} p-5 backdrop-blur-xl`}
    >
      <div className="flex gap-4">
        <div className={`shrink-0 ${c.iconColor}`}>{c.icon}</div>
        <div>
          <span className={`text-sm font-bold ${c.iconColor} uppercase tracking-wider`}>
            {c.title}
          </span>
          <div className="mt-2 text-white/70">{children}</div>
        </div>
      </div>
    </div>
  );
}

// =============================================================================
// COMMAND LIST - Interactive list of commands
// =============================================================================
interface Command {
  command: string;
  description: string;
}

interface CommandListProps {
  commands: Command[];
}

export function CommandList({ commands }: CommandListProps) {
  const [copiedIndex, setCopiedIndex] = useState<number | null>(null);

  const handleCopy = async (command: string, index: number) => {
    try {
      await navigator.clipboard.writeText(command);
      setCopiedIndex(index);
      setTimeout(() => setCopiedIndex(null), 2000);
    } catch {
      // Clipboard access denied - silently fail
    }
  };

  return (
    <div className="space-y-3">
      {commands.map((cmd, i) => (
        <motion.div
          key={i}
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: i * 0.1 }}
          className="group flex items-center gap-4 rounded-xl border border-white/[0.08] bg-white/[0.02] p-4 transition-all duration-300 hover:border-white/[0.15] hover:bg-white/[0.04]"
        >
          <button
            type="button"
            onClick={() => handleCopy(cmd.command, i)}
            className="flex items-center gap-2 px-3 py-2 rounded-lg bg-black/40 border border-white/[0.08] font-mono text-sm text-emerald-400 transition-all duration-300 hover:bg-black/60 hover:border-emerald-500/30"
          >
            <span className="text-white/50">$</span>
            <span>{cmd.command}</span>
            {copiedIndex === i ? (
              <Check className="h-4 w-4 text-emerald-400" />
            ) : (
              <Copy className="h-4 w-4 text-white/50 opacity-0 group-hover:opacity-100 transition-opacity" />
            )}
          </button>
          <span className="text-white/50 text-sm">{cmd.description}</span>
        </motion.div>
      ))}
    </div>
  );
}

// =============================================================================
// STEP LIST - Numbered steps with visual indicators
// =============================================================================
interface Step {
  title: string;
  description?: string;
}

interface StepListProps {
  steps: Step[];
}

export function StepList({ steps }: StepListProps) {
  return (
    <div className="relative space-y-6">
      {/* Connecting line */}
      <div className="absolute left-5 top-10 bottom-10 w-px bg-gradient-to-b from-primary/50 via-white/10 to-emerald-500/50" />

      {steps.map((step, i) => (
        <motion.div
          key={i}
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: i * 0.15 }}
          className="relative flex items-start gap-5 pl-2"
        >
          <div className="relative z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-primary to-violet-500 text-white text-sm font-bold shadow-lg shadow-primary/30">
            {i + 1}
          </div>
          <div className="pt-1">
            <h4 className="font-semibold text-white">{step.title}</h4>
            {step.description && (
              <p className="mt-1 text-white/50 text-sm">{step.description}</p>
            )}
          </div>
        </motion.div>
      ))}
    </div>
  );
}

// =============================================================================
// DIAGRAM - Visual architecture diagram
// =============================================================================
interface DiagramBoxProps {
  label: string;
  sublabel?: string;
  icon?: ReactNode;
  gradient?: string;
}

export function DiagramBox({
  label,
  sublabel,
  icon,
  gradient = "from-primary/20 to-violet-500/20",
}: DiagramBoxProps) {
  return (
    <div
      className={`relative flex flex-col items-center justify-center rounded-2xl border border-white/[0.1] bg-gradient-to-br ${gradient} p-4 backdrop-blur-xl text-center`}
    >
      {icon && <div className="text-white mb-2">{icon}</div>}
      <span className="font-bold text-white text-sm">{label}</span>
      {sublabel && (
        <span className="text-xs text-white/50 mt-1">{sublabel}</span>
      )}
    </div>
  );
}

export function DiagramArrow({ direction = "right" }: { direction?: "right" | "down" }) {
  return (
    <div className={`flex items-center justify-center ${direction === "down" ? "py-2" : "px-2"}`}>
      <ChevronRight
        className={`h-6 w-6 text-white/50 ${direction === "down" ? "rotate-90" : ""}`}
      />
    </div>
  );
}

// =============================================================================
// HIGHLIGHT TEXT - Gradient highlighted text
// =============================================================================
export function Highlight({ children }: { children: ReactNode }) {
  return (
    <span className="font-semibold bg-gradient-to-r from-primary to-violet-400 bg-clip-text text-transparent">
      {children}
    </span>
  );
}

// =============================================================================
// BULLET LIST - Styled bullet points
// =============================================================================
interface BulletListProps {
  items: (string | ReactNode)[];
}

export function BulletList({ items }: BulletListProps) {
  return (
    <ul className="space-y-3">
      {items.map((item, i) => (
        <motion.li
          key={i}
          initial={{ opacity: 0, x: -10 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: i * 0.1 }}
          className="flex items-start gap-3"
        >
          <div className="mt-2 h-1.5 w-1.5 rounded-full bg-primary shrink-0" />
          <span className="text-white/70">{item}</span>
        </motion.li>
      ))}
    </ul>
  );
}

// =============================================================================
// DIVIDER - Section divider
// =============================================================================
export function Divider() {
  return (
    <div className="my-12 h-px bg-gradient-to-r from-transparent via-white/10 to-transparent" />
  );
}

// =============================================================================
// GOAL BANNER - Lesson goal display
// =============================================================================
interface GoalBannerProps {
  children: ReactNode;
}

export function GoalBanner({ children }: GoalBannerProps) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      className="relative mb-12 rounded-2xl border border-primary/30 bg-gradient-to-br from-primary/10 via-primary/5 to-violet-500/10 p-6 backdrop-blur-xl overflow-hidden"
    >
      {/* Decorative glow */}
      <div className="absolute -top-20 -right-20 w-40 h-40 bg-primary/30 rounded-full blur-3xl" />

      <div className="relative flex items-center gap-4">
        <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br from-primary to-violet-500 shadow-lg shadow-primary/30">
          <Zap className="h-6 w-6 text-white" />
        </div>
        <div>
          <span className="text-xs font-bold text-primary uppercase tracking-wider">
            Goal
          </span>
          <p className="text-lg text-white font-medium">{children}</p>
        </div>
      </div>
    </motion.div>
  );
}
