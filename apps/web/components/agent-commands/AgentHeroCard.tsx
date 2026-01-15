"use client";

import { useState, useRef, useEffect } from "react";
import { Copy, Check, ChevronDown, Terminal } from "lucide-react";
import { motion, AnimatePresence, springs } from "@/components/motion";
import { cn } from "@/lib/utils";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";

export type AgentType = "claude" | "codex" | "gemini";

export interface AgentInfo {
  id: AgentType;
  name: string;
  command: string;
  aliases: string[];
  description: string;
  model: string;
  icon: string;
  examples: Array<{
    command: string;
    description: string;
  }>;
  tips: string[];
}

/**
 * Agent personality configurations with distinct visual identities
 */
export const agentPersonalities: Record<
  AgentType,
  {
    gradient: string;
    glowColor: string;
    bgGlow: string;
    borderHover: string;
    tagline: string;
  }
> = {
  claude: {
    gradient: "from-orange-400 via-amber-400 to-orange-500",
    glowColor: "oklch(0.78 0.16 75)",
    bgGlow: "bg-[oklch(0.78_0.16_75/0.15)]",
    borderHover: "hover:border-[oklch(0.78_0.16_75/0.5)]",
    tagline: "Deep reasoning & architecture",
  },
  codex: {
    gradient: "from-emerald-400 via-teal-400 to-emerald-500",
    glowColor: "oklch(0.72 0.19 145)",
    bgGlow: "bg-[oklch(0.72_0.19_145/0.15)]",
    borderHover: "hover:border-[oklch(0.72_0.19_145/0.5)]",
    tagline: "Structured & precise",
  },
  gemini: {
    gradient: "from-blue-400 via-indigo-400 to-blue-500",
    glowColor: "oklch(0.75 0.18 195)",
    bgGlow: "bg-[oklch(0.75_0.18_195/0.15)]",
    borderHover: "hover:border-[oklch(0.75_0.18_195/0.5)]",
    tagline: "Large context exploration",
  },
};

interface AgentHeroCardProps {
  agent: AgentInfo;
  isExpanded: boolean;
  onToggle: () => void;
  index: number;
  onKeyboardFocus?: (focused: boolean) => void;
}

export function AgentHeroCard({
  agent,
  isExpanded,
  onToggle,
  index,
  onKeyboardFocus,
}: AgentHeroCardProps) {
  const [copiedAlias, setCopiedAlias] = useState<string | null>(null);
  const [isHovered, setIsHovered] = useState(false);
  const cardRef = useRef<HTMLDivElement>(null);
  const personality = agentPersonalities[agent.id];
  const prefersReducedMotion = useReducedMotion();

  // Handle keyboard number navigation
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Only respond when no input is focused
      if (
        document.activeElement?.tagName === "INPUT" ||
        document.activeElement?.tagName === "TEXTAREA"
      ) {
        return;
      }

      const keyNum = parseInt(e.key);
      if (keyNum === index + 1 && keyNum >= 1 && keyNum <= 3) {
        cardRef.current?.focus();
        onKeyboardFocus?.(true);
        if (!isExpanded) {
          onToggle();
        }
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [index, isExpanded, onToggle, onKeyboardFocus]);

  const handleCopy = async (text: string, e: React.MouseEvent) => {
    e.stopPropagation();
    try {
      await navigator.clipboard.writeText(text);
      setCopiedAlias(text);
      setTimeout(() => setCopiedAlias(null), 2000);
    } catch {
      const textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand("copy");
      document.body.removeChild(textarea);
      setCopiedAlias(text);
      setTimeout(() => setCopiedAlias(null), 2000);
    }
  };

  return (
    <motion.div
      ref={cardRef}
      tabIndex={0}
      role="button"
      aria-expanded={isExpanded}
      aria-label={`${agent.name} agent card. Press Enter to ${isExpanded ? "collapse" : "expand"}.`}
      className={cn(
        "group relative cursor-pointer overflow-hidden rounded-2xl",
        "border border-white/[0.08] bg-white/[0.02] backdrop-blur-xl",
        "outline-none ring-offset-2 ring-offset-background",
        "focus-visible:ring-2 focus-visible:ring-primary",
        "transition-all duration-300",
        "hover:border-white/[0.15] hover:bg-white/[0.04] hover:shadow-lg hover:shadow-primary/10"
      )}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      onClick={onToggle}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onToggle();
        }
        if (e.key === "Escape" && isExpanded) {
          onToggle();
        }
      }}
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ ...springs.smooth, delay: index * 0.1 }}
      whileHover={{ y: -4 }}
    >
      {/* Glow effect on hover */}
      <motion.div
        className={cn(
          "pointer-events-none absolute -inset-px rounded-2xl opacity-0 blur-2xl transition-opacity duration-500",
          personality.bgGlow
        )}
        animate={{ opacity: isHovered ? 0.6 : 0 }}
      />

      {/* Decorative corner glow */}
      <div className={cn(
        "absolute -top-10 -right-10 w-32 h-32 rounded-full blur-3xl opacity-0 transition-opacity duration-500",
        personality.bgGlow,
        isHovered && "opacity-40"
      )} />

      {/* Gradient header */}
      <div
        className={cn(
          "relative flex items-center gap-4 p-5",
          "bg-gradient-to-r",
          personality.gradient
        )}
      >
        {/* Agent icon with animated ring */}
        <motion.div
          className="relative"
          animate={isHovered ? { scale: 1.1, rotate: 5 } : { scale: 1, rotate: 0 }}
          transition={springs.snappy}
        >
          <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-white/20 text-2xl font-bold text-white backdrop-blur-sm shadow-lg shadow-white/10">
            {agent.icon}
          </div>
          {/* Animated ring - pulses on hover (respects reduced motion) */}
          {isHovered && !prefersReducedMotion && (
            <motion.div
              className="absolute -inset-1.5 rounded-2xl border-2 border-white/50"
              initial={{ scale: 1, opacity: 0.8 }}
              animate={{ scale: 1.2, opacity: 0 }}
              transition={{ duration: 1, repeat: Infinity, ease: "easeOut" }}
            />
          )}
        </motion.div>

        {/* Agent info */}
        <div className="min-w-0 flex-1">
          <h3 className="text-xl font-bold text-white">{agent.name}</h3>
          <p className="text-sm text-white/80">{personality.tagline}</p>
        </div>

        {/* Quick alias + expand indicator */}
        <div className="hidden items-center gap-3 sm:flex">
          {/* Primary alias badge */}
          <motion.button
            type="button"
            onClick={(e) => handleCopy(agent.aliases[0] || agent.command, e)}
            className={cn(
              "flex items-center gap-2 rounded-lg px-3 py-2",
              "bg-white/20 backdrop-blur-sm",
              "font-mono text-sm text-white",
              "hover:bg-white/30 transition-colors"
            )}
            whileTap={{ scale: 0.95 }}
          >
            <Terminal className="h-3.5 w-3.5" />
            {agent.aliases[0] || agent.command}
            <AnimatePresence mode="wait">
              {copiedAlias === (agent.aliases[0] || agent.command) ? (
                <motion.span
                  key="check"
                  initial={{ scale: 0, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  exit={{ scale: 0, opacity: 0 }}
                  transition={springs.snappy}
                >
                  <Check className="h-3.5 w-3.5 text-white" />
                </motion.span>
              ) : (
                <motion.span
                  key="copy"
                  initial={{ scale: 0, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  exit={{ scale: 0, opacity: 0 }}
                  transition={springs.snappy}
                >
                  <Copy className="h-3.5 w-3.5 text-white/60" />
                </motion.span>
              )}
            </AnimatePresence>
          </motion.button>

          {/* Expand indicator */}
          <motion.div
            className="flex h-8 w-8 items-center justify-center rounded-full bg-white/20"
            animate={{ rotate: isExpanded ? 180 : 0 }}
            transition={springs.snappy}
          >
            <ChevronDown className="h-4 w-4 text-white" />
          </motion.div>
        </div>

        {/* Mobile expand indicator */}
        <motion.div
          className="flex h-8 w-8 items-center justify-center rounded-full bg-white/20 sm:hidden"
          animate={{ rotate: isExpanded ? 180 : 0 }}
          transition={springs.snappy}
        >
          <ChevronDown className="h-4 w-4 text-white" />
        </motion.div>
      </div>

      {/* Collapsed preview - model info */}
      <AnimatePresence>
        {!isExpanded && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            transition={springs.smooth}
            className="overflow-hidden"
          >
            <div className="flex items-center justify-between border-t border-white/[0.06] px-5 py-3 bg-black/20">
              <span className="text-sm text-white/60">
                {agent.model}
              </span>
              <div className="flex items-center gap-2 text-sm text-white/40">
                <span>{agent.examples.length} commands</span>
                <span className="text-white/20">·</span>
                <span>{agent.tips.length} tips</span>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Keyboard shortcut hint */}
      <div className="absolute bottom-2 right-2 hidden opacity-0 transition-opacity group-focus-visible:opacity-100 lg:block">
        <kbd className="rounded bg-background/80 px-1.5 py-0.5 font-mono text-xs text-muted-foreground">
          {index + 1}
        </kbd>
      </div>
    </motion.div>
  );
}
