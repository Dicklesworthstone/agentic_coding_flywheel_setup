"use client";

import { useEffect, useRef, useState } from "react";
import { Check, Terminal } from "lucide-react";
import { motion, AnimatePresence, springs } from "@/components/motion";
import { cn, copyTextToClipboard } from "@/lib/utils";
import type { AgentType } from "./AgentHeroCard";

interface QuickCommand {
  alias: string;
  agentType: AgentType;
  label: string;
  /** Simple two-color gradient for the icon button */
  iconGradient: string;
}

export const quickCommands: QuickCommand[] = [
  { alias: "cc", agentType: "claude", label: "Claude", iconGradient: "from-orange-400 to-amber-500" },
  { alias: "cod", agentType: "codex", label: "Codex", iconGradient: "from-emerald-400 to-teal-500" },
  { alias: "agy", agentType: "antigravity", label: "Antigravity", iconGradient: "from-blue-400 to-purple-500" },
  // Legacy shortcut: Gemini CLI retired 2026-06-18; ACFS maps gmi to locked agy.
  { alias: "gmi", agentType: "gemini", label: "Gemini (legacy)", iconGradient: "from-blue-400 to-indigo-500" },
];

export function QuickAccessBar() {
  const [copiedAlias, setCopiedAlias] = useState<string | null>(null);
  const copyResetTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (copyResetTimerRef.current) {
        clearTimeout(copyResetTimerRef.current);
      }
    };
  }, []);

  const handleCopy = async (command: QuickCommand, e: React.MouseEvent) => {
    e.stopPropagation();

    const copiedOk = await copyTextToClipboard(command.alias);
    if (!copiedOk) {
      return;
    }

    setCopiedAlias(command.alias);

    // Trigger haptic feedback on mobile if available
    if (navigator.vibrate) {
      navigator.vibrate(10);
    }

    if (copyResetTimerRef.current) {
      clearTimeout(copyResetTimerRef.current);
    }
    copyResetTimerRef.current = setTimeout(() => {
      setCopiedAlias(null);
      copyResetTimerRef.current = null;
    }, 2000);
  };

  return (
    <motion.div
      className={cn(
        "fixed inset-x-0 bottom-0 z-50",
        "border-t border-white/[0.08] bg-black/80 backdrop-blur-xl",
        "pb-safe px-4 pt-3"
      )}
      initial={{ y: 100, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={springs.smooth}
    >
      <div className="mx-auto flex max-w-md items-center justify-around gap-2">
        {quickCommands.map((command) => {
          const isCopied = copiedAlias === command.alias;

          return (
            <motion.button
              key={command.alias}
              type="button"
              onClick={(e) => handleCopy(command, e)}
              className={cn(
                "group relative flex flex-1 flex-col items-center gap-1.5 rounded-xl p-3",
                "min-h-[64px] transition-all duration-300",
                isCopied
                  ? "bg-emerald-500/20 border border-emerald-500/30"
                  : "bg-white/[0.02] border border-white/[0.06] active:bg-white/[0.05]"
              )}
              whileTap={{ scale: 0.95 }}
            >
              {/* Glow effect when copied */}
              <AnimatePresence>
                {isCopied && (
                  <motion.div
                    className="absolute inset-0 -z-10 rounded-xl bg-emerald-500/30 blur-xl"
                    initial={{ opacity: 0, scale: 0.8 }}
                    animate={{ opacity: 1, scale: 1.3 }}
                    exit={{ opacity: 0, scale: 0.8 }}
                    transition={springs.smooth}
                  />
                )}
              </AnimatePresence>

              {/* Icon with agent color accent */}
              <div
                className={cn(
                  "flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br",
                  command.iconGradient
                )}
              >
                <AnimatePresence mode="wait">
                  {isCopied ? (
                    <motion.div
                      key="check"
                      initial={{ scale: 0, rotate: -90 }}
                      animate={{ scale: 1, rotate: 0 }}
                      exit={{ scale: 0, rotate: 90 }}
                      transition={springs.snappy}
                    >
                      <Check className="h-4 w-4 text-white" />
                    </motion.div>
                  ) : (
                    <motion.div
                      key="terminal"
                      initial={{ scale: 0 }}
                      animate={{ scale: 1 }}
                      exit={{ scale: 0 }}
                      transition={springs.snappy}
                    >
                      <Terminal className="h-4 w-4 text-white" />
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>

              {/* Command alias */}
              <code className="font-mono text-xs font-medium text-white/80">
                {command.alias}
              </code>

              {/* Copied indicator */}
              <AnimatePresence>
                {isCopied && (
                  <motion.span
                    className="absolute -top-1 right-0 rounded-full bg-emerald-500 px-1.5 py-0.5 text-xs font-bold text-white shadow-lg shadow-emerald-500/30"
                    initial={{ scale: 0, y: 10 }}
                    animate={{ scale: 1, y: 0 }}
                    exit={{ scale: 0, y: -10 }}
                    transition={springs.snappy}
                  >
                    Copied!
                  </motion.span>
                )}
              </AnimatePresence>
            </motion.button>
          );
        })}
      </div>

      {/* Hint text */}
      <p className="mt-2 text-center text-xs text-white/60">
        Tap to copy command
      </p>
    </motion.div>
  );
}
