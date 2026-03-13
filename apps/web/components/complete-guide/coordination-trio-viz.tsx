"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useInView, useReducedMotion } from "framer-motion";
import { Repeat } from "lucide-react";
import { Hl } from "@/components/complete-guide/guide-components";

const EXHIBIT_PANEL_CLASS =
  "my-16 overflow-hidden rounded-[3rem] border border-white/[0.03] bg-[#020408] p-8 sm:p-12 lg:p-16 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9)]";

const TRIO_TOOLS = [
  {
    id: "beads",
    label: "Beads",
    sub: "(br)",
    color: "#a78bfa",
    x: 300,
    y: 80,
    desc: "The task graph is the system memory for what work exists and what depends on what.",
    without:
      "Agents have no canonical work inventory. They improvise, duplicate effort, and miss hidden prerequisites.",
  },
  {
    id: "mail",
    label: "Agent Mail",
    sub: "",
    color: "#22d3ee",
    x: 140,
    y: 300,
    desc: "Mail threads and file reservations let many agents coordinate without smashing into each other.",
    without:
      "Agents cannot negotiate ownership or handoff details. Merge conflicts and stale assumptions multiply.",
  },
  {
    id: "bv",
    label: "bv",
    sub: "",
    color: "#34d399",
    x: 460,
    y: 300,
    desc: "Graph analysis turns the bead graph into a prioritization compass instead of a flat backlog.",
    without:
      "The swarm loses its sense of leverage. Bottlenecks remain blocked while agents work on lower-value tasks.",
  },
] as const;

type TrioToolId = (typeof TRIO_TOOLS)[number]["id"];

const TRIO_EDGES = [
  { from: "beads", to: "mail", label1: "Bead IDs thread", label2: "communication" },
  { from: "beads", to: "bv", label1: "Dependency graph", label2: "drives triage" },
  { from: "mail", to: "bv", label1: "Reservations inform", label2: "availability" },
] as const;

const TOOL_MAP = new Map(TRIO_TOOLS.map((tool) => [tool.id, tool] as const));

export function CoordinationTrioViz() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;
  const [hoveredTool, setHoveredTool] = useState<TrioToolId | null>(null);
  const [disabledTool, setDisabledTool] = useState<TrioToolId | null>(null);
  const isFinePointer = useRef(false);

  useEffect(() => {
    isFinePointer.current = window.matchMedia("(hover: hover) and (pointer: fine)").matches;
  }, []);

  return (
    <div ref={ref} className={EXHIBIT_PANEL_CLASS}>
      <div className="flex flex-col gap-10 border-b border-white/[0.03] pb-12 lg:flex-row lg:items-start lg:justify-between">
        <div className="max-w-2xl">
          <div className="text-[0.65rem] font-black uppercase tracking-[0.4em] text-violet-400 opacity-60 flex items-center gap-3">
            <div className="w-8 h-px bg-violet-400/30" />
            Coordination Logic
          </div>
          <h4 className="mt-6 text-3xl font-black tracking-[-0.04em] text-white sm:text-4xl lg:text-5xl leading-[1.1]">
            Beads, Agent Mail, and bv are a single machine
          </h4>
          <p className="mt-8 text-[1.1rem] leading-relaxed text-zinc-400 font-extralight opacity-80">
            Hover or tap to inspect each piece. Click again to remove it and
            watch the system lose a capability it cannot replace. 
            This is the <Hl>Coordination Triangle</Hl>.
          </p>
        </div>

        <div className="flex flex-col items-start lg:items-end gap-6">
          {disabledTool && (
            <motion.button
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              onClick={() => setDisabledTool(null)}
              className="flex items-center gap-3 px-6 py-3 rounded-2xl border border-white/10 bg-white/[0.02] text-[0.7rem] font-black uppercase tracking-[0.2em] text-white/60 hover:text-white transition-all duration-500"
            >
              <Repeat className="h-3 w-3" />
              Restore Machine
            </motion.button>
          )}
        </div>
      </div>

      <div className="mt-16 grid gap-12 xl:grid-cols-[1.2fr_0.8fr] items-center">
        <div className="relative aspect-square sm:aspect-video xl:aspect-square flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(167,139,250,0.05),transparent_70%)]" />
          
          <motion.svg
            viewBox="0 0 600 380"
            className="relative z-10 w-full h-full max-h-[500px]"
            initial={reducedMotion ? false : { opacity: 0 }}
            animate={isInView ? { opacity: 1 } : undefined}
            transition={{ duration: 0.8 }}
          >
            {TRIO_EDGES.map((edge) => {
              const from = TOOL_MAP.get(edge.from)!;
              const to = TOOL_MAP.get(edge.to)!;
              const isDisabled = disabledTool === edge.from || disabledTool === edge.to;
              const isHovered =
                hoveredTool !== null && (edge.from === hoveredTool || edge.to === hoveredTool);
              const mx = (from.x + to.x) / 2;
              const my = (from.y + to.y) / 2;
              const cx = mx + (300 - mx) * 0.25;
              const cy = my + (220 - my) * 0.25;

              return (
                <g key={`${edge.from}-${edge.to}`}>
                  <motion.path
                    d={`M ${from.x} ${from.y} Q ${cx} ${cy} ${to.x} ${to.y}`}
                    fill="none"
                    stroke={isDisabled ? "#ef4444" : isHovered ? "white" : "white"}
                    strokeWidth={isHovered ? 2 : 1}
                    strokeDasharray={isDisabled ? "4 4" : isHovered ? "0" : "2 6"}
                    animate={{
                      strokeOpacity: isDisabled ? 0.1 : hoveredTool ? (isHovered ? 0.8 : 0.05) : 0.1,
                    }}
                    transition={{ duration: 0.4 }}
                  />
                </g>
              );
            })}

            {TRIO_TOOLS.map((tool) => {
              const isDisabled = disabledTool === tool.id;
              const isHovered = hoveredTool === tool.id;
              const isConnected =
                hoveredTool === null ||
                hoveredTool === tool.id ||
                TRIO_EDGES.some(
                  (edge) =>
                    (edge.from === hoveredTool && edge.to === tool.id) ||
                    (edge.to === hoveredTool && edge.from === tool.id),
                );

              return (
                <motion.g
                  key={tool.id}
                  onMouseEnter={() => {
                    if (isFinePointer.current && !disabledTool) setHoveredTool(tool.id);
                  }}
                  onMouseLeave={() => {
                    if (isFinePointer.current) setHoveredTool(null);
                  }}
                  onClick={() => {
                    setDisabledTool(disabledTool === tool.id ? null : tool.id);
                  }}
                  animate={{ opacity: isDisabled ? 0.2 : isConnected ? 1 : 0.1 }}
                  className="cursor-crosshair outline-none"
                >
                  <circle cx={tool.x} cy={tool.y} r={60} fill="transparent" />
                  
                  {/* Point core */}
                  <motion.circle
                    cx={tool.x}
                    cy={tool.y}
                    r={isHovered ? 10 : 6}
                    fill={isDisabled ? "#ef4444" : isHovered ? tool.color : "white"}
                    fillOpacity={isHovered ? 1 : 0.2}
                    animate={{ scale: isHovered ? [1, 1.4, 1] : 1 }}
                    transition={{ duration: 2, repeat: Infinity }}
                  />
                  
                  {/* Outer rings */}
                  <motion.circle
                    cx={tool.x}
                    cy={tool.y}
                    r={isHovered ? 36 : 24}
                    fill="none"
                    stroke={tool.color}
                    strokeOpacity={isHovered ? 0.4 : 0}
                    strokeWidth="1"
                  />

                  <text
                    x={tool.x}
                    y={tool.y - 25}
                    textAnchor="middle"
                    className={`text-[12px] font-black uppercase tracking-[0.2em] transition-all duration-500 ${isHovered ? "fill-white" : "fill-white/20"}`}
                  >
                    {tool.label}
                  </text>
                </motion.g>
              );
            })}
          </motion.svg>
        </div>

        <div className="flex flex-col gap-8">
          <div className="p-8 rounded-[2.5rem] bg-white/[0.01] border border-white/[0.03]">
            <span className="text-[0.6rem] font-black text-white/20 uppercase tracking-[0.4em]">Capability Map</span>
            <div className="mt-8 flex flex-col gap-6">
              {[
                { l: "Beads", t: "The canonical memory of pending work.", c: "text-violet-400" },
                { l: "Agent Mail", t: "The high-bandwidth negotiation layer.", c: "text-cyan-400" },
                { l: "bv", t: "The graph-theory compass for triage.", c: "text-emerald-400" },
              ].map((item, i) => (
                <div key={i} className="flex flex-col gap-1">
                  <span className={`text-[0.7rem] font-bold tracking-wide ${item.c} opacity-80`}>{item.l}</span>
                  <p className="text-sm text-zinc-400 font-extralight leading-relaxed">{item.t}</p>
                </div>
              ))}
            </div>
          </div>

          <AnimatePresence mode="wait">
            {disabledTool ? (
              <motion.div
                key={`disabled-${disabledTool}`}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -20 }}
                transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
                className="p-10 rounded-[2.5rem] bg-[#100505] border border-red-500/10 shadow-inner"
              >
                <span className="text-[0.6rem] font-black text-red-500/60 uppercase tracking-[0.5em] block mb-6">Failure Mode Analysis</span>
                <div className="text-lg font-black text-white mb-2">
                  Missing {TOOL_MAP.get(disabledTool)?.label}
                </div>
                <p className="text-[1.1rem] leading-relaxed text-red-200/60 font-extralight italic">
                  {TOOL_MAP.get(disabledTool)?.without}
                </p>
              </motion.div>
            ) : hoveredTool ? (
              <motion.div
                key={`hovered-${hoveredTool}`}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -20 }}
                transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
                className="p-10 rounded-[2.5rem] bg-[#0a0c10] border border-white/[0.05] shadow-inner"
              >
                <div
                  className="text-[0.6rem] font-black uppercase tracking-[0.5em] block mb-6 opacity-60"
                  style={{ color: TOOL_MAP.get(hoveredTool)?.color }}
                >
                  Component Analysis
                </div>
                <div className="text-lg font-black text-white mb-2">
                  {TOOL_MAP.get(hoveredTool)?.label}
                </div>
                <p className="text-[1.1rem] leading-relaxed text-zinc-300 font-extralight italic">
                  {TOOL_MAP.get(hoveredTool)?.desc}
                </p>
              </motion.div>
            ) : (
              <motion.div
                key="default"
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -20 }}
                transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
                className="p-10 rounded-[2.5rem] bg-[#0a0c10] border border-white/[0.05] shadow-inner"
              >
                <span className="text-[0.6rem] font-black text-primary/60 uppercase tracking-[0.5em] block mb-6">System Architecture</span>
                <p className="text-[1.1rem] leading-relaxed text-zinc-300 font-extralight italic">
                  The trio is not three nice-to-have tools. It is one operating
                  system split into memory, communication, and leverage
                  analysis. Remove any side of the triangle and the swarm loses
                  determinism.
                </p>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
