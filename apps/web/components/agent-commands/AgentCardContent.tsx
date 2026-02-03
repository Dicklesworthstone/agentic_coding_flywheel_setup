"use client";

import { useState } from "react";
import { Copy, Check, Terminal, Sparkles, Code2 } from "lucide-react";
import { motion, AnimatePresence, springs, useReducedMotion } from "@/components/motion";
import { CommandCard } from "@/components/command-card";
import { cn } from "@/lib/utils";
import type { AgentInfo } from "./AgentHeroCard";
import { agentPersonalities } from "./AgentHeroCard";

type TabId = "examples" | "tips" | "aliases";

interface Tab {
  id: TabId;
  label: string;
  icon: React.ReactNode;
}

const tabs: Tab[] = [
  { id: "examples", label: "Commands", icon: <Code2 className="h-4 w-4" /> },
  { id: "tips", label: "Tips", icon: <Sparkles className="h-4 w-4" /> },
  { id: "aliases", label: "Aliases", icon: <Terminal className="h-4 w-4" /> },
];

interface AgentCardContentProps {
  agent: AgentInfo;
  isExpanded: boolean;
}

export function AgentCardContent({ agent, isExpanded }: AgentCardContentProps) {
  const [activeTab, setActiveTab] = useState<TabId>("examples");
  const [copiedAlias, setCopiedAlias] = useState<string | null>(null);
  const personality = agentPersonalities[agent.id];
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;

  const handleCopy = async (text: string) => {
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
    <AnimatePresence>
      {isExpanded && (
        <motion.div
          initial={reducedMotion ? { opacity: 0 } : { opacity: 0, height: 0 }}
          animate={reducedMotion ? { opacity: 1 } : { opacity: 1, height: "auto" }}
          exit={reducedMotion ? { opacity: 0 } : { opacity: 0, height: 0 }}
          transition={reducedMotion ? { duration: 0 } : springs.smooth}
          className="overflow-hidden"
        >
          <div className="border-t border-white/[0.06] bg-black/20">
            {/* Tab navigation */}
            <div className="flex border-b border-white/[0.06]">
              {tabs.map((tab) => (
                <button
                  key={tab.id}
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    setActiveTab(tab.id);
                  }}
                  className={cn(
                    "flex flex-1 items-center justify-center gap-2 px-4 py-3",
                    "text-sm font-medium transition-all duration-300",
                    "min-h-[48px]", // Touch target
                    activeTab === tab.id
                      ? "border-b-2 border-primary text-white bg-white/[0.02]"
                      : "text-white/50 hover:text-white/80 hover:bg-white/[0.02]"
                  )}
                >
                  {tab.icon}
                  <span className="hidden sm:inline">{tab.label}</span>
                </button>
              ))}
            </div>

            {/* Tab content */}
            <div className="p-5" onClick={(e) => e.stopPropagation()}>
              <AnimatePresence mode="wait">
                {activeTab === "examples" && (
                  <motion.div
                    key="examples"
                    initial={reducedMotion ? {} : { opacity: 0, x: -10 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={reducedMotion ? {} : { opacity: 0, x: 10 }}
                    transition={reducedMotion ? { duration: 0 } : springs.snappy}
                    className="space-y-3"
                  >
                    {agent.examples.map((example, i) => (
                      <motion.div
                        key={i}
                        initial={reducedMotion ? {} : { opacity: 0, y: 10 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={reducedMotion ? { duration: 0 } : { ...springs.smooth, delay: i * 0.05 }}
                      >
                        <CommandCard
                          command={example.command}
                          description={example.description}
                        />
                      </motion.div>
                    ))}
                  </motion.div>
                )}

                {activeTab === "tips" && (
                  <motion.div
                    key="tips"
                    initial={reducedMotion ? {} : { opacity: 0, x: -10 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={reducedMotion ? {} : { opacity: 0, x: 10 }}
                    transition={reducedMotion ? { duration: 0 } : springs.snappy}
                  >
                    <ul className="space-y-3">
                      {agent.tips.map((tip, i) => (
                        <motion.li
                          key={i}
                          className="group/tip flex items-start gap-3 rounded-xl border border-white/[0.06] bg-white/[0.02] p-4 transition-all duration-300 hover:border-primary/30 hover:bg-white/[0.04]"
                          initial={reducedMotion ? {} : { opacity: 0, y: 10 }}
                          animate={{ opacity: 1, y: 0 }}
                          whileHover={reducedMotion ? {} : { x: 4, scale: 1.01 }}
                          transition={reducedMotion ? { duration: 0 } : { ...springs.smooth, delay: i * 0.05 }}
                        >
                          <div
                            className={cn(
                              "mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg group-hover/tip:scale-110 transition-transform duration-300",
                              personality.bgGlow
                            )}
                          >
                            <Sparkles className="h-3.5 w-3.5 text-primary" />
                          </div>
                          <span className="text-sm text-white/60 group-hover/tip:text-white/80 transition-colors">
                            {tip}
                          </span>
                        </motion.li>
                      ))}
                    </ul>
                  </motion.div>
                )}

                {activeTab === "aliases" && (
                  <motion.div
                    key="aliases"
                    initial={reducedMotion ? {} : { opacity: 0, x: -10 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={reducedMotion ? {} : { opacity: 0, x: 10 }}
                    transition={reducedMotion ? { duration: 0 } : springs.snappy}
                  >
                    <p className="mb-4 text-sm text-white/50">
                      All these commands launch {agent.name}. Copy and paste into
                      your terminal.
                    </p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {[agent.command, ...agent.aliases].map((alias, i) => (
                        <motion.button
                          key={alias}
                          type="button"
                          onClick={() => handleCopy(alias)}
                          className={cn(
                            "group/alias flex items-center justify-between gap-3 rounded-xl border p-4",
                            "min-h-[56px] transition-all duration-300",
                            copiedAlias === alias
                              ? "border-emerald-500/50 bg-emerald-500/10"
                              : "border-white/[0.06] bg-white/[0.02] hover:border-primary/40 hover:bg-white/[0.04]"
                          )}
                          initial={reducedMotion ? {} : { opacity: 0, y: 10 }}
                          animate={{ opacity: 1, y: 0 }}
                          whileHover={reducedMotion ? {} : { x: 4, scale: 1.02 }}
                          transition={reducedMotion ? { duration: 0 } : { ...springs.smooth, delay: i * 0.05 }}
                          whileTap={reducedMotion ? {} : { scale: 0.98 }}
                        >
                          <div className="flex items-center gap-3">
                            <Terminal className="h-4 w-4 text-white/60 group-hover/alias:text-primary transition-colors" />
                            <code className="font-mono text-base text-white/80">{alias}</code>
                          </div>
                          <AnimatePresence mode="wait">
                            {copiedAlias === alias ? (
                              <motion.div
                                key="check"
                                initial={{ scale: 0 }}
                                animate={{ scale: 1 }}
                                exit={{ scale: 0 }}
                                className="flex items-center gap-1 text-emerald-400"
                              >
                                <Check className="h-4 w-4" />
                                <span className="text-xs font-medium">
                                  Copied!
                                </span>
                              </motion.div>
                            ) : (
                              <motion.div
                                key="copy"
                                initial={{ scale: 0 }}
                                animate={{ scale: 1 }}
                                exit={{ scale: 0 }}
                                className="flex items-center gap-1 text-white/60 opacity-0 transition-opacity group-hover/alias:opacity-100"
                              >
                                <Copy className="h-4 w-4" />
                                <span className="hidden text-xs sm:inline">
                                  Copy
                                </span>
                              </motion.div>
                            )}
                          </AnimatePresence>
                        </motion.button>
                      ))}
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
