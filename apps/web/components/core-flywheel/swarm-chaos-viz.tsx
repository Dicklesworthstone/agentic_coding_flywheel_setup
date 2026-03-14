"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  AnimatePresence,
  motion,
  useInView,
  useReducedMotion,
} from "framer-motion";
import { Lock, Play, RotateCcw } from "lucide-react";

/* ------------------------------------------------------------------ */
/*  Constants                                                         */
/* ------------------------------------------------------------------ */

const EXHIBIT_PANEL_CLASS =
  "my-16 overflow-hidden rounded-[1.5rem] sm:rounded-[2rem] lg:rounded-[3rem] border border-white/[0.03] bg-[#020408] p-5 sm:p-12 lg:p-16 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9)]";

const PHASE_DURATION_MS = 2500;
const TOTAL_PHASES = 5;

/* ------------------------------------------------------------------ */
/*  Types                                                             */
/* ------------------------------------------------------------------ */

type TaskState = "ready" | "claimed" | "in-progress" | "done" | "conflicted" | "blocked";

interface TaskDef {
  id: number;
  label: string;
  /** Which tasks must be done before this one can start */
  deps: number[];
  priority: number; // lower = higher priority
}

interface AgentState {
  id: string;
  color: string;
  targetTask: number | null;
  status: string;
}

interface PanelSnapshot {
  agents: AgentState[];
  tasks: Record<number, TaskState>;
  conflicts: number;
  idleBurn: number;
  completed: number;
  statusText: string;
}

interface PhaseNarrative {
  chaos: PanelSnapshot;
  coordinated: PanelSnapshot;
  description: string;
}

/* ------------------------------------------------------------------ */
/*  Task & Agent definitions                                          */
/* ------------------------------------------------------------------ */

const TASKS: TaskDef[] = [
  { id: 1, label: "T1", deps: [], priority: 1 },
  { id: 2, label: "T2", deps: [1], priority: 2 },
  { id: 3, label: "T3", deps: [], priority: 2 },
  { id: 4, label: "T4", deps: [2, 3], priority: 3 },
  { id: 5, label: "T5", deps: [1], priority: 3 },
  { id: 6, label: "T6", deps: [], priority: 4 },
];

const AGENT_COLORS = ["#60a5fa", "#f472b6", "#a78bfa", "#34d399"];

function makeAgents(): AgentState[] {
  return [
    { id: "A1", color: AGENT_COLORS[0], targetTask: null, status: "idle" },
    { id: "A2", color: AGENT_COLORS[1], targetTask: null, status: "idle" },
    { id: "A3", color: AGENT_COLORS[2], targetTask: null, status: "idle" },
    { id: "A4", color: AGENT_COLORS[3], targetTask: null, status: "idle" },
  ];
}

function initTasks(): Record<number, TaskState> {
  return { 1: "ready", 2: "ready", 3: "ready", 4: "ready", 5: "ready", 6: "ready" };
}

/* ------------------------------------------------------------------ */
/*  Phase definitions                                                 */
/* ------------------------------------------------------------------ */

const PHASES: PhaseNarrative[] = [
  {
    // Phase 0: Boot
    chaos: {
      agents: makeAgents().map((a) => ({ ...a, status: "reading codebase..." })),
      tasks: initTasks(),
      conflicts: 0,
      idleBurn: 0,
      completed: 0,
      statusText: "All agents boot up and read the codebase",
    },
    coordinated: {
      agents: makeAgents().map((a) => ({ ...a, status: "reading codebase..." })),
      tasks: initTasks(),
      conflicts: 0,
      idleBurn: 0,
      completed: 0,
      statusText: "All agents boot up and read the codebase",
    },
    description:
      "Four agents spin up in parallel and read the same codebase. Without coordination tools, they have no way to know what the others are doing.",
  },
  {
    // Phase 1: First moves
    chaos: {
      agents: [
        { id: "A1", color: AGENT_COLORS[0], targetTask: 2, status: "grabbing T2" },
        { id: "A2", color: AGENT_COLORS[1], targetTask: 4, status: "grabbing T4" },
        { id: "A3", color: AGENT_COLORS[2], targetTask: 2, status: "grabbing T2" },
        { id: "A4", color: AGENT_COLORS[3], targetTask: 6, status: "grabbing T6" },
      ],
      tasks: { 1: "ready", 2: "conflicted", 3: "ready", 4: "in-progress", 5: "ready", 6: "in-progress" },
      conflicts: 1,
      idleBurn: 0,
      completed: 0,
      statusText: "A1 and A3 both started Task 2 \u2014 merge conflict!",
    },
    coordinated: {
      agents: [
        { id: "A1", color: AGENT_COLORS[0], targetTask: 1, status: "bv: pick T1" },
        { id: "A2", color: AGENT_COLORS[1], targetTask: 3, status: "bv: pick T3" },
        { id: "A3", color: AGENT_COLORS[2], targetTask: 6, status: "bv: pick T6" },
        { id: "A4", color: AGENT_COLORS[3], targetTask: null, status: "waiting (all claimed)" },
      ],
      tasks: { 1: "claimed", 2: "ready", 3: "claimed", 4: "ready", 5: "ready", 6: "claimed" },
      conflicts: 0,
      idleBurn: 0,
      completed: 0,
      statusText: "A1 claimed T1 (highest impact, unblocks 2 others)",
    },
    description:
      "Without the core loop, A1 and A3 both grab Task 2 \u2014 a merge conflict is inevitable. With bv routing, each agent picks the highest-leverage unblocked task and claims it via Agent Mail.",
  },
  {
    // Phase 2: Waste vs. progress
    chaos: {
      agents: [
        { id: "A1", color: AGENT_COLORS[0], targetTask: 2, status: "resolving conflict..." },
        { id: "A2", color: AGENT_COLORS[1], targetTask: 5, status: "BLOCKED on T1" },
        { id: "A3", color: AGENT_COLORS[2], targetTask: 2, status: "resolving conflict..." },
        { id: "A4", color: AGENT_COLORS[3], targetTask: 6, status: "working on T6" },
      ],
      tasks: { 1: "ready", 2: "conflicted", 3: "ready", 4: "ready", 5: "blocked", 6: "in-progress" },
      conflicts: 1,
      idleBurn: 4200,
      completed: 0,
      statusText: "A2 started T5 which depends on T1 \u2014 wasted tokens!",
    },
    coordinated: {
      agents: [
        { id: "A1", color: AGENT_COLORS[0], targetTask: 1, status: "working on T1" },
        { id: "A2", color: AGENT_COLORS[1], targetTask: 3, status: "working on T3" },
        { id: "A3", color: AGENT_COLORS[2], targetTask: 6, status: "working on T6" },
        { id: "A4", color: AGENT_COLORS[3], targetTask: null, status: "waiting (deps blocked)" },
      ],
      tasks: { 1: "in-progress", 2: "ready", 3: "in-progress", 4: "ready", 5: "ready", 6: "in-progress" },
      conflicts: 0,
      idleBurn: 0,
      completed: 0,
      statusText: "A2 working on T3, file reservations prevent collisions",
    },
    description:
      "The chaotic side burns tokens on a blocked task (T5 depends on T1, which nobody started). The coordinated side moves forward. File reservations prevent overlap.",
  },
  {
    // Phase 3: Recovery vs. flow
    chaos: {
      agents: [
        { id: "A1", color: AGENT_COLORS[0], targetTask: 2, status: "finally finishing T2" },
        { id: "A2", color: AGENT_COLORS[1], targetTask: 5, status: "still blocked" },
        { id: "A3", color: AGENT_COLORS[2], targetTask: 1, status: "starting T1 (late)" },
        { id: "A4", color: AGENT_COLORS[3], targetTask: 6, status: "done with T6" },
      ],
      tasks: { 1: "in-progress", 2: "in-progress", 3: "ready", 4: "ready", 5: "blocked", 6: "done" },
      conflicts: 1,
      idleBurn: 8400,
      completed: 1,
      statusText: "A4 finished T6 (low priority) while critical T1 was ignored",
    },
    coordinated: {
      agents: [
        { id: "A1", color: AGENT_COLORS[0], targetTask: 2, status: "bv: T1 done, pick T2" },
        { id: "A2", color: AGENT_COLORS[1], targetTask: 5, status: "bv: pick T5 (unblocked)" },
        { id: "A3", color: AGENT_COLORS[2], targetTask: null, status: "T6 done, waiting" },
        { id: "A4", color: AGENT_COLORS[3], targetTask: 4, status: "bv: pick T4" },
      ],
      tasks: { 1: "done", 2: "claimed", 3: "done", 4: "claimed", 5: "claimed", 6: "done" },
      conflicts: 0,
      idleBurn: 0,
      completed: 3,
      statusText: "A1 finished T1 \u2192 bv routes to T2 (now unblocked)",
    },
    description:
      "On the left, A4 finished a low-priority task while a critical one sat untouched. On the right, closing T1 updated the dependency graph. bv immediately routes agents to newly-unblocked work.",
  },
  {
    // Phase 4: Final tally
    chaos: {
      agents: [
        { id: "A1", color: AGENT_COLORS[0], targetTask: 2, status: "done (T2)" },
        { id: "A2", color: AGENT_COLORS[1], targetTask: 3, status: "starting T3 (late)" },
        { id: "A3", color: AGENT_COLORS[2], targetTask: 1, status: "done (T1)" },
        { id: "A4", color: AGENT_COLORS[3], targetTask: null, status: "idle" },
      ],
      tasks: { 1: "done", 2: "done", 3: "in-progress", 4: "ready", 5: "ready", 6: "done" },
      conflicts: 1,
      idleBurn: 12600,
      completed: 3,
      statusText: "3/6 done. 1 merge conflict, 12.6k wasted tokens",
    },
    coordinated: {
      agents: [
        { id: "A1", color: AGENT_COLORS[0], targetTask: 2, status: "done (T2)" },
        { id: "A2", color: AGENT_COLORS[1], targetTask: 5, status: "done (T5)" },
        { id: "A3", color: AGENT_COLORS[2], targetTask: null, status: "idle" },
        { id: "A4", color: AGENT_COLORS[3], targetTask: 4, status: "finishing T4" },
      ],
      tasks: { 1: "done", 2: "done", 3: "done", 4: "in-progress", 5: "done", 6: "done" },
      conflicts: 0,
      idleBurn: 0,
      completed: 5,
      statusText: "5/6 done, 0 conflicts, 0 wasted tokens. T4 finishing now",
    },
    description:
      "Same agents, same tasks, same time. Without the core loop: 3 completed, 1 merge conflict, 1 blocked task, thousands of wasted tokens. With it: 5 completed, zero conflicts, zero waste.",
  },
];

/* ------------------------------------------------------------------ */
/*  Task state colors                                                 */
/* ------------------------------------------------------------------ */

const TASK_STATE_COLORS: Record<TaskState, { bg: string; border: string; text: string }> = {
  ready: { bg: "bg-white/[0.06]", border: "border-white/[0.12]", text: "text-white/60" },
  claimed: { bg: "bg-amber-500/[0.12]", border: "border-amber-500/30", text: "text-amber-400" },
  "in-progress": { bg: "bg-blue-500/[0.12]", border: "border-blue-500/30", text: "text-blue-400" },
  done: { bg: "bg-emerald-500/[0.15]", border: "border-emerald-500/30", text: "text-emerald-400" },
  conflicted: { bg: "bg-red-500/[0.15]", border: "border-red-500/30", text: "text-red-400" },
  blocked: { bg: "bg-orange-500/[0.08]", border: "border-orange-500/20", text: "text-orange-400/60" },
};

/* ------------------------------------------------------------------ */
/*  Sub-components                                                    */
/* ------------------------------------------------------------------ */

function TaskBox({
  task,
  state,
  isConflicted,
  isBlocked,
  showLock,
  reducedMotion,
}: {
  task: TaskDef;
  state: TaskState;
  isConflicted: boolean;
  isBlocked: boolean;
  showLock: boolean;
  reducedMotion: boolean;
}) {
  const colors = TASK_STATE_COLORS[state];

  return (
    <motion.div
      className={`relative flex items-center justify-center rounded-lg border px-3 py-2 text-xs font-bold ${colors.bg} ${colors.border} ${colors.text}`}
      animate={
        isConflicted && !reducedMotion
          ? { scale: [1, 1.08, 1], borderColor: ["#ef444480", "#ef4444", "#ef444480"] }
          : { scale: 1 }
      }
      transition={
        isConflicted && !reducedMotion
          ? { duration: 0.6, repeat: Infinity }
          : { duration: 0.3 }
      }
    >
      {task.label}
      {showLock && (
        <Lock size={10} className="ml-1 text-emerald-400/70" />
      )}
      {isConflicted && (
        <motion.span
          className="absolute -top-2 -right-2 rounded-full bg-red-500 px-1.5 py-0.5 text-[9px] font-black text-white"
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ type: "spring", stiffness: 400, damping: 15 }}
        >
          CONFLICT
        </motion.span>
      )}
      {isBlocked && (
        <motion.span
          className="absolute -top-2 -right-2 rounded-full bg-orange-500 px-1.5 py-0.5 text-[9px] font-black text-white"
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ type: "spring", stiffness: 400, damping: 15 }}
        >
          BLOCKED
        </motion.span>
      )}
    </motion.div>
  );
}

function AgentDot({
  agent,
  taskIndex,
  reducedMotion,
}: {
  agent: AgentState;
  taskIndex: number | null;
  reducedMotion: boolean;
}) {
  return (
    <motion.div
      className="flex items-center gap-2"
      layout={!reducedMotion}
      transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
    >
      <motion.div
        className="h-3 w-3 rounded-full shrink-0"
        style={{ backgroundColor: agent.color }}
        animate={
          agent.status.includes("conflict") || agent.status.includes("BLOCKED")
            ? { opacity: [1, 0.4, 1] }
            : { opacity: 1 }
        }
        transition={
          agent.status.includes("conflict") || agent.status.includes("BLOCKED")
            ? { duration: 0.8, repeat: Infinity }
            : { duration: 0.3 }
        }
      />
      <span className="text-[10px] font-bold text-white/70">{agent.id}</span>
      {taskIndex !== null && (
        <motion.span
          className="text-[10px] text-white/30"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
        >
          {`\u2192 T${taskIndex}`}
        </motion.span>
      )}
    </motion.div>
  );
}

function DependencyArrows({ reducedMotion }: { reducedMotion: boolean }) {
  // Simple visual representation of task dependencies
  const arrows: { from: string; to: string }[] = [
    { from: "T1", to: "T2" },
    { from: "T1", to: "T5" },
    { from: "T2", to: "T4" },
    { from: "T3", to: "T4" },
  ];

  return (
    <div className="flex flex-wrap gap-x-3 gap-y-1 mt-2">
      {arrows.map((arrow) => (
        <motion.span
          key={`${arrow.from}-${arrow.to}`}
          className="text-[9px] font-mono text-emerald-500/40"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: reducedMotion ? 0 : 0.5 }}
        >
          {arrow.from} {"\u2192"} {arrow.to}
        </motion.span>
      ))}
    </div>
  );
}

function MetricBar({
  label,
  value,
  isBad,
}: {
  label: string;
  value: string;
  isBad?: boolean;
}) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-[10px] font-bold uppercase tracking-widest text-white/30">
        {label}
      </span>
      <span
        className={`text-xs font-black tabular-nums ${
          isBad ? "text-red-400" : "text-emerald-400"
        }`}
      >
        {value}
      </span>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Panel component                                                   */
/* ------------------------------------------------------------------ */

function SimPanel({
  variant,
  snapshot,
  phase,
  reducedMotion,
}: {
  variant: "chaos" | "coordinated";
  snapshot: PanelSnapshot;
  phase: number;
  reducedMotion: boolean;
}) {
  const isChaos = variant === "chaos";
  const dotColor = isChaos ? "bg-red-500/60" : "bg-emerald-500/60";
  const borderColor = isChaos ? "border-red-500/20" : "border-emerald-500/20";
  const labelColor = isChaos ? "text-red-400" : "text-emerald-400";
  const title = isChaos ? "Without the Core Loop" : "With the Core Loop";

  return (
    <div
      className={`rounded-2xl border p-5 sm:p-6 ${borderColor}`}
      style={{ background: isChaos ? "#0a0204" : "#020a06" }}
    >
      {/* Panel header */}
      <div className="flex items-center gap-2 mb-4">
        <div className={`h-3 w-3 rounded-full ${dotColor}`} />
        <span className={`text-xs font-black uppercase tracking-[0.15em] ${labelColor}`}>
          {title}
        </span>
      </div>

      {/* Status text */}
      <AnimatePresence mode="wait">
        <motion.p
          key={`status-${phase}`}
          initial={{ opacity: 0, y: 6 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -6 }}
          transition={{ duration: reducedMotion ? 0 : 0.3 }}
          className={`text-xs leading-relaxed mb-5 min-h-[2rem] ${
            isChaos ? "text-red-300/70" : "text-emerald-300/70"
          }`}
        >
          {snapshot.statusText}
        </motion.p>
      </AnimatePresence>

      {/* Agents row */}
      <div className="mb-4">
        <p className="text-[9px] font-bold uppercase tracking-[0.2em] text-white/20 mb-2">
          Agents
        </p>
        <div className="grid grid-cols-2 gap-2">
          {snapshot.agents.map((agent) => (
            <div key={agent.id} className="flex flex-col gap-0.5">
              <AgentDot
                agent={agent}
                taskIndex={agent.targetTask}
                reducedMotion={reducedMotion}
              />
              <span className="ml-5 text-[9px] text-white/25 truncate">
                {agent.status}
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* Tasks row */}
      <div className="mb-4">
        <p className="text-[9px] font-bold uppercase tracking-[0.2em] text-white/20 mb-2">
          Tasks
        </p>
        <div className="grid grid-cols-3 gap-2">
          {TASKS.map((task) => {
            const state = snapshot.tasks[task.id];
            return (
              <TaskBox
                key={task.id}
                task={task}
                state={state}
                isConflicted={state === "conflicted"}
                isBlocked={state === "blocked"}
                showLock={!isChaos && (state === "claimed" || state === "in-progress")}
                reducedMotion={reducedMotion}
              />
            );
          })}
        </div>
        {/* Dependency arrows only on the coordinated side */}
        {!isChaos && <DependencyArrows reducedMotion={reducedMotion} />}
      </div>

      {/* Metrics */}
      <div className="rounded-xl border border-white/[0.05] bg-white/[0.02] p-3 space-y-1.5">
        <MetricBar
          label="Conflicts"
          value={String(snapshot.conflicts)}
          isBad={snapshot.conflicts > 0}
        />
        <MetricBar
          label="Idle Burn"
          value={snapshot.idleBurn > 0 ? `${(snapshot.idleBurn / 1000).toFixed(1)}k tokens` : "0"}
          isBad={snapshot.idleBurn > 0}
        />
        <MetricBar
          label="Completed"
          value={`${snapshot.completed}/6`}
          isBad={false}
        />
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Main exported component                                           */
/* ------------------------------------------------------------------ */

export function SwarmChaosViz() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });
  const prefersReducedMotion = useReducedMotion();
  const rm = prefersReducedMotion ?? false;

  const [phase, setPhase] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);

  const clearTimers = useCallback(() => {
    timersRef.current.forEach(clearTimeout);
    timersRef.current = [];
  }, []);

  const reset = useCallback(() => {
    clearTimers();
    setPhase(0);
    setIsPlaying(false);
  }, [clearTimers]);

  const play = useCallback(() => {
    if (isPlaying) return;
    reset();
    setIsPlaying(true);

    const newTimers: ReturnType<typeof setTimeout>[] = [];
    for (let i = 1; i < TOTAL_PHASES; i++) {
      const t = setTimeout(() => {
        setPhase(i);
        if (i === TOTAL_PHASES - 1) {
          setIsPlaying(false);
        }
      }, PHASE_DURATION_MS * i);
      newTimers.push(t);
    }
    timersRef.current = newTimers;
  }, [isPlaying, reset]);

  useEffect(() => () => clearTimers(), [clearTimers]);

  /* Keyboard navigation — only when this viz is in the viewport */
  useEffect(() => {
    if (!isInView) return;
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === " ") {
        e.preventDefault();
        if (!isPlaying) play();
      } else if (e.key === "r" || e.key === "R") {
        e.preventDefault();
        reset();
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isInView, isPlaying, play, reset]);

  const currentPhase = PHASES[phase];
  const isDone = phase === TOTAL_PHASES - 1 && !isPlaying;

  return (
    <div ref={ref} className={EXHIBIT_PANEL_CLASS + " relative group/viz"}>
      {/* Background texture */}
      <div className="absolute inset-0 bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-[0.02] mix-blend-overlay pointer-events-none" />

      {/* Header */}
      <div className="relative z-10 border-b border-white/[0.04] pb-10 flex flex-col gap-4">
        <div className="text-[0.65rem] font-bold uppercase tracking-widest text-[#FF5500]/80 flex items-center gap-3">
          <span className="w-1.5 h-1.5 rounded-full bg-[#FF5500] animate-pulse shadow-[0_0_8px_rgba(255,85,0,0.8)]" />
          Interactive Comparison
        </div>
        <h4 className="text-3xl font-black tracking-tight text-white sm:text-4xl leading-[1.15] drop-shadow-lg">
          Why the tools matter
        </h4>
        <p className="text-[1.05rem] leading-relaxed text-zinc-400 font-light max-w-2xl">
          Four agents, six tasks, side by side. One side uses the core
          loop, the other does not. Press Start.
        </p>
      </div>

      {/* Dual panels */}
      <motion.div
        className="relative z-10 mt-10 grid grid-cols-1 lg:grid-cols-2 gap-6"
        initial={{ opacity: 0, y: 20 }}
        animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
        transition={{ duration: rm ? 0 : 0.6 }}
      >
        <SimPanel
          variant="chaos"
          snapshot={currentPhase.chaos}
          phase={phase}
          reducedMotion={rm}
        />
        <SimPanel
          variant="coordinated"
          snapshot={currentPhase.coordinated}
          phase={phase}
          reducedMotion={rm}
        />
      </motion.div>

      {/* Narrative description */}
      <div className="relative z-10 mt-8 min-h-[3rem]">
        <AnimatePresence mode="wait">
          <motion.p
            key={`narrative-${phase}`}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={{ duration: rm ? 0 : 0.4 }}
            className="text-sm leading-relaxed text-zinc-400 text-center max-w-2xl mx-auto"
          >
            {currentPhase.description}
          </motion.p>
        </AnimatePresence>
      </div>

      {/* Phase indicator */}
      <div className="relative z-10 mt-6 flex items-center justify-center gap-2">
        <span className="text-[0.6rem] font-bold uppercase tracking-[0.3em] text-white/20 mr-2">
          Phase
        </span>
        {PHASES.map((_, index) => (
          <div
            key={index}
            className="p-0.5"
          >
            <motion.div
              className="rounded-full"
              style={{
                width: index === phase ? 20 : 8,
                height: 8,
                backgroundColor:
                  index === phase
                    ? "#FF5500"
                    : index < phase
                      ? "#FF550044"
                      : "rgba(255,255,255,0.1)",
                boxShadow:
                  index === phase ? "0 0 10px rgba(255,85,0,0.6)" : "none",
              }}
              layout
              transition={
                rm
                  ? { duration: 0 }
                  : { type: "spring", stiffness: 200, damping: 25 }
              }
            />
          </div>
        ))}
      </div>

      {/* Controls */}
      <div className="relative z-10 mt-8 flex justify-center gap-3">
        <button
          type="button"
          onClick={play}
          disabled={isPlaying}
          className="flex items-center gap-2 rounded-xl px-6 py-2.5 text-sm font-bold text-white transition-all hover:scale-[1.02] active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-40"
          style={{ background: "#FF5500" }}
        >
          <Play size={14} />
          {isDone ? "Replay Simulation" : "Start Simulation"}
        </button>
        <button
          type="button"
          onClick={reset}
          className="flex items-center gap-2 rounded-xl border border-white/10 bg-white/[0.02] px-6 py-2.5 text-sm font-medium text-slate-300 transition-all hover:bg-white/[0.05] hover:border-white/15"
        >
          <RotateCcw size={14} />
          Reset
        </button>
      </div>
    </div>
  );
}
