"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import { motion, AnimatePresence, useReducedMotion, useInView } from "framer-motion";

// =============================================================================
// DATA
// =============================================================================

const AGENT_NAMES = ["ScarletCave", "BlueLake", "CoralBadger", "JadePeak", "AmberFox", "IvoryOwl"];
const AGENT_COLORS = ["#ef4444", "#3b82f6", "#f97316", "#10b981", "#f59e0b", "#8b5cf6"];

const BEAD_TITLES = [
  "br-101: Upload pipeline",
  "br-102: Search index",
  "br-103: Admin dashboard",
  "br-104: Auth model",
  "br-105: E2E tests",
  "br-106: API layer",
  "br-107: Export wizard",
  "br-108: Notification system",
];

interface SimAgent {
  id: string;
  name: string;
  color: string;
  alive: boolean;
  currentBead: number | null;
  progress: number;
  justCompleted: boolean; // transient flash state
}

interface SimBead {
  id: number;
  title: string;
  status: "unclaimed" | "in_progress" | "completed" | "orphaned";
  assignedTo: string | null;
}

interface SimState {
  agents: SimAgent[];
  beads: SimBead[];
  log: string[];
  killed: number;
  recovered: number;
  completed: number;
}

function createInitialState(): SimState {
  const agents: SimAgent[] = AGENT_NAMES.map((name, i) => ({
    id: `agent-${i}`,
    name,
    color: AGENT_COLORS[i],
    alive: true,
    currentBead: i < BEAD_TITLES.length ? i : null,
    progress: Math.floor(Math.random() * 40) + 10,
    justCompleted: false,
  }));

  const beads: SimBead[] = BEAD_TITLES.map((title, i) => ({
    id: i,
    title,
    status: i < AGENT_NAMES.length ? "in_progress" as const : "unclaimed" as const,
    assignedTo: i < AGENT_NAMES.length ? AGENT_NAMES[i] : null,
  }));

  return { agents, beads, log: ["Swarm initialized. All agents working."], killed: 0, recovered: 0, completed: 0 };
}

/** Pure function: advance simulation by one tick. */
function tick(state: SimState): SimState {
  const agents = state.agents.map(a => ({ ...a, justCompleted: false }));
  const beads = state.beads.map(b => ({ ...b }));
  const log = [...state.log];
  let { killed, recovered, completed } = state;

  // 1. Mark orphaned beads (assigned to dead agents)
  for (const bead of beads) {
    if (
      bead.status === "in_progress" &&
      bead.assignedTo !== null &&
      !agents.some(a => a.alive && a.name === bead.assignedTo)
    ) {
      bead.status = "orphaned";
    }
  }

  // 2. Advance progress for alive agents with assigned beads
  for (const agent of agents) {
    if (agent.alive && agent.currentBead !== null) {
      agent.progress = Math.min(100, agent.progress + Math.random() * 4 + 1);
    }
  }

  // 3. Handle completions
  for (const agent of agents) {
    if (!agent.alive || agent.currentBead === null || agent.progress < 100) continue;

    const beadId = agent.currentBead;
    const bead = beads.find(b => b.id === beadId);
    if (bead) {
      bead.status = "completed";
      bead.assignedTo = null;
    }
    completed++;
    agent.justCompleted = true;
    log.unshift(`${agent.name} completed ${BEAD_TITLES[beadId]}.`);

    // Claim next unclaimed bead
    const nextBead = beads.find(b => b.status === "unclaimed");
    if (nextBead) {
      nextBead.status = "in_progress";
      nextBead.assignedTo = agent.name;
      agent.currentBead = nextBead.id;
      agent.progress = 0;
      log.unshift(`${agent.name} claimed ${nextBead.title}.`);
    } else {
      agent.currentBead = null;
      agent.progress = 0;
    }
  }

  // 4. Assign idle alive agents to orphaned or unclaimed beads
  for (const agent of agents) {
    if (!agent.alive || agent.currentBead !== null) continue;

    // Orphaned beads first (recovery)
    const orphan = beads.find(b => b.status === "orphaned");
    if (orphan) {
      orphan.status = "in_progress";
      orphan.assignedTo = agent.name;
      agent.currentBead = orphan.id;
      agent.progress = 20;
      recovered++;
      log.unshift(`${agent.name} recovered orphaned ${orphan.title}.`);
      continue;
    }

    // Then unclaimed
    const unclaimed = beads.find(b => b.status === "unclaimed");
    if (unclaimed) {
      unclaimed.status = "in_progress";
      unclaimed.assignedTo = agent.name;
      agent.currentBead = unclaimed.id;
      agent.progress = 0;
      log.unshift(`${agent.name} claimed ${unclaimed.title}.`);
    }
  }

  return { agents, beads, log: log.slice(0, 8), killed, recovered, completed };
}

// =============================================================================
// COMPONENT
// =============================================================================

export function CrashRecoveryViz() {
  const containerRef = useRef<HTMLDivElement>(null);
  const isInView = useInView(containerRef, { once: true, margin: "-200px" });
  const prefersReducedMotion = useReducedMotion();
  const rm = prefersReducedMotion ?? false;

  const [state, setState] = useState<SimState>(createInitialState);
  const [selectedAgent, setSelectedAgent] = useState<string | null>(null);

  // Simulation loop gated by visibility
  useEffect(() => {
    if (!isInView) return;

    const interval = setInterval(() => {
      setState(prev => tick(prev));
    }, 200);

    return () => clearInterval(interval);
  }, [isInView]);

  // Mobile: auto-dismiss selection after 900ms
  useEffect(() => {
    if (!selectedAgent) return;
    const timer = setTimeout(() => setSelectedAgent(null), 900);
    return () => clearTimeout(timer);
  }, [selectedAgent]);

  const handleAgentClick = useCallback((agentId: string) => {
    const isTouchDevice = typeof window !== "undefined" && "ontouchstart" in window;

    if (isTouchDevice && selectedAgent !== agentId) {
      // First tap: select (show kill overlay)
      setSelectedAgent(agentId);
      return;
    }

    // Second tap on mobile, or any click on desktop: kill
    setState(prev => {
      const agent = prev.agents.find(a => a.id === agentId);
      if (!agent || !agent.alive) return prev;

      const agents = prev.agents.map(a =>
        a.id === agentId ? { ...a, alive: false, currentBead: null, progress: 0 } : { ...a }
      );
      const log = [`${agent.name} crashed! Bead remains in_progress...`, ...prev.log].slice(0, 8);

      return { ...prev, agents, log, killed: prev.killed + 1 };
    });
    setSelectedAgent(null);
  }, [selectedAgent]);

  const reset = useCallback(() => {
    setState(createInitialState());
    setSelectedAgent(null);
  }, []);

  const { agents, beads, log, killed, recovered, completed } = state;
  const aliveCount = agents.filter(a => a.alive).length;
  const orphanedCount = beads.filter(b => b.status === "orphaned").length;

  const springTransition = rm
    ? { duration: 0 }
    : { type: "spring" as const, stiffness: 200, damping: 30 };

  return (
    <div ref={containerRef} className="relative my-16 overflow-hidden rounded-2xl border border-white/[0.06] bg-[#0A0D14] shadow-xl">
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.03] mix-blend-overlay pointer-events-none" />

      {/* Header */}
      <div className="relative z-10 border-b border-white/[0.04] px-5 py-5 sm:px-8">
        <div className="flex items-center justify-between flex-wrap gap-4">
          <div>
            <h4 className="text-lg font-bold text-white tracking-tight">Fungible Agent Crash Recovery</h4>
            <p className="mt-1 text-sm text-zinc-400">
              <span className="hidden sm:inline">Click any agent to kill it. Watch the swarm self-heal.</span>
              <span className="sm:hidden">Tap an agent, then tap again to kill it.</span>
            </p>
          </div>
          <button
            onClick={reset}
            className="rounded-lg border border-white/10 bg-white/[0.03] px-4 py-2.5 text-xs font-semibold text-zinc-300 hover:bg-white/[0.08] hover:border-[#FF5500]/30 active:scale-95 transition-all min-h-[44px]"
          >
            Reset Swarm
          </button>
        </div>

        {/* Metrics */}
        <div className="mt-4 flex flex-wrap gap-x-5 gap-y-2 text-xs">
          <div className="flex items-center gap-2">
            <div className="h-2 w-2 rounded-full bg-emerald-500 shadow-[0_0_6px_rgba(16,185,129,0.6)]" />
            <span className="text-zinc-400">Alive: <span className="text-white font-bold">{aliveCount}/{agents.length}</span></span>
          </div>
          <div className="flex items-center gap-2">
            <div className="h-2 w-2 rounded-full bg-red-500 shadow-[0_0_6px_rgba(239,68,68,0.6)]" />
            <span className="text-zinc-400">Killed: <span className="text-white font-bold">{killed}</span></span>
          </div>
          {orphanedCount > 0 && (
            <div className="flex items-center gap-2">
              <div className="h-2 w-2 rounded-full bg-orange-500 animate-pulse shadow-[0_0_6px_rgba(249,115,22,0.6)]" />
              <span className="text-orange-400 font-semibold">Orphaned: {orphanedCount}</span>
            </div>
          )}
          <div className="flex items-center gap-2">
            <div className="h-2 w-2 rounded-full bg-amber-500 shadow-[0_0_6px_rgba(245,158,11,0.6)]" />
            <span className="text-zinc-400">Recovered: <span className="text-white font-bold">{recovered}</span></span>
          </div>
          <div className="flex items-center gap-2">
            <div className="h-2 w-2 rounded-full bg-sky-500 shadow-[0_0_6px_rgba(14,165,233,0.6)]" />
            <span className="text-zinc-400">Completed: <span className="text-white font-bold">{completed}</span></span>
          </div>
        </div>
      </div>

      {/* Agent grid + log */}
      <div className="relative z-10 grid gap-0 lg:grid-cols-[1fr_280px]">
        {/* Agents */}
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3 p-5 sm:p-8">
          {agents.map(agent => {
            const isSelected = selectedAgent === agent.id;
            const showKillOverlay = agent.alive && (isSelected);

            return (
              <motion.button
                key={agent.id}
                onClick={() => handleAgentClick(agent.id)}
                disabled={!agent.alive}
                aria-label={agent.alive ? `Kill agent ${agent.name}` : `Agent ${agent.name} is crashed`}
                className={`relative rounded-xl border p-4 text-left transition-colors min-h-[44px] ${
                  agent.alive
                    ? agent.justCompleted
                      ? "border-emerald-500/30 bg-emerald-500/[0.05] cursor-pointer group"
                      : "border-white/10 bg-white/[0.02] hover:border-[#FF5500]/30 hover:bg-white/[0.05] cursor-pointer group"
                    : "border-red-500/20 bg-red-500/[0.03] cursor-not-allowed"
                }`}
                animate={{ opacity: agent.alive ? 1 : 0.4 }}
                transition={springTransition}
              >
                {/* Agent name + status dot */}
                <div className="flex items-center gap-2 mb-3">
                  <div
                    className={`h-3 w-3 rounded-full shrink-0 ${agent.alive && !rm ? "animate-pulse" : ""}`}
                    style={{
                      backgroundColor: agent.alive ? agent.color : "#666",
                      boxShadow: agent.alive ? `0 0 8px ${agent.color}60` : "none",
                    }}
                  />
                  <span className="text-xs font-bold text-white truncate">{agent.name}</span>
                </div>

                {/* Current work */}
                {agent.alive && agent.currentBead !== null ? (
                  <div>
                    <div className="text-[10px] text-zinc-500 mb-1.5 truncate">{BEAD_TITLES[agent.currentBead]}</div>
                    <div className="h-1.5 w-full rounded-full bg-white/10 overflow-hidden">
                      <motion.div
                        className="h-full rounded-full"
                        style={{ backgroundColor: agent.color }}
                        animate={{ width: `${agent.progress}%` }}
                        transition={springTransition}
                      />
                    </div>
                    <div className="text-[10px] text-zinc-500 mt-1 text-right">{Math.floor(agent.progress)}%</div>
                  </div>
                ) : agent.alive ? (
                  <div className="text-[10px] text-zinc-500 italic">Idle, scanning for work...</div>
                ) : (
                  <div className="text-[10px] text-red-400 font-medium">CRASHED</div>
                )}

                {/* Kill overlay: desktop hover OR mobile tap-to-select */}
                {agent.alive && (
                  <div className={`absolute inset-0 rounded-xl flex items-center justify-center transition-opacity bg-red-500/10 border border-red-500/20 ${
                    showKillOverlay ? "opacity-100" : "opacity-0 group-hover:opacity-100"
                  }`}>
                    <span className="text-xs font-bold text-red-400">
                      {isSelected ? "Tap Again to Kill" : "Click to Kill"}
                    </span>
                  </div>
                )}
              </motion.button>
            );
          })}
        </div>

        {/* Event log */}
        <div className="border-t lg:border-t-0 lg:border-l border-white/[0.04] p-5 sm:p-6 bg-black/20">
          <div className="text-[10px] font-bold text-[#FF5500]/60 uppercase tracking-[0.2em] mb-3">Event Log</div>
          <div className="space-y-2" role="log" aria-live="polite">
            <AnimatePresence mode="popLayout" initial={false}>
              {log.map((entry, i) => (
                <motion.div
                  key={`${entry}-${log.length}-${i}`}
                  initial={rm ? {} : { opacity: 0, x: 10 }}
                  animate={{ opacity: Math.max(0.3, 1 - Math.log(i + 1) * 0.25), x: 0 }}
                  exit={rm ? {} : { opacity: 0, x: -10 }}
                  transition={springTransition}
                  className={`text-[11px] leading-relaxed ${
                    entry.includes("crashed") ? "text-red-400" :
                    entry.includes("recovered") ? "text-amber-400" :
                    entry.includes("completed") ? "text-emerald-400" :
                    entry.includes("claimed") ? "text-sky-400" :
                    "text-zinc-500"
                  }`}
                >
                  {entry}
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        </div>
      </div>

      {/* Takeaway */}
      <div className="relative z-10 border-t border-white/[0.04] px-5 py-4 sm:px-8 bg-black/20">
        <p className="text-xs text-zinc-400 leading-relaxed">
          {killed === 0
            ? "Every agent is fungible. Kill any of them to see the swarm self-heal without downtime or data loss."
            : aliveCount === 0
            ? `All ${killed} agents killed. In a real swarm, you would spin up replacements with ntm add PROJECT --cc=1 and they would immediately pick up the orphaned beads. Hit Reset to try again.`
            : recovered > 0
            ? `${killed} agent${killed > 1 ? "s" : ""} killed, ${recovered} bead${recovered > 1 ? "s" : ""} recovered. The swarm continues. No bottlenecks, no single points of failure. Like RaptorQ fountain codes: any agent catches any bead in any order.`
            : orphanedCount > 0
            ? `${killed} agent${killed > 1 ? "s" : ""} killed. ${orphanedCount} orphaned bead${orphanedCount > 1 ? "s" : ""} waiting for recovery. Watch the next idle agent pick ${orphanedCount > 1 ? "them" : "it"} up.`
            : `${killed} agent${killed > 1 ? "s" : ""} killed. The orphaned bead will be picked up by the next idle agent. No ringleader needed.`
          }
        </p>
      </div>
    </div>
  );
}
