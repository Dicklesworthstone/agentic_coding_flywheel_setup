"use client";

import { Repeat } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Hl } from "@/components/complete-guide/guide-components";
import { AnimatePresence, motion, useInView, useReducedMotion } from "@/components/motion";

const EXHIBIT_PANEL_CLASS =
  "my-16 overflow-hidden rounded-[2rem] border border-white/[0.05] bg-[#020408] p-6 sm:rounded-[3rem] sm:p-12 lg:p-16 shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9)]";

/** Node positions are in the diagram's 600 x 380 drawing units. */
const VIEW_W = 600;
const VIEW_H = 380;
const CENTER = { x: 300, y: 220 };

const TRIO_TOOLS = [
  {
    id: "beads",
    label: "Beads",
    sub: "(br)",
    color: "#a78bfa",
    x: 300,
    y: 80,
    labelSide: "top",
    desc: "The task graph records what work exists and what depends on what.",
    without:
      "Agents have no shared list of the work, so they duplicate each other's tasks and miss prerequisites.",
  },
  {
    id: "mail",
    label: "Agent Mail",
    sub: "",
    color: "#FF5500",
    x: 140,
    y: 300,
    labelSide: "bottom",
    desc: "Mail threads and file reservations let many agents work in one repo without editing the same files at once.",
    without:
      "Agents cannot agree on who owns which files or pass details along at a handoff, so merge conflicts and stale assumptions pile up.",
  },
  {
    id: "bv",
    label: "bv",
    sub: "",
    color: "#FFBD2E",
    x: 460,
    y: 300,
    labelSide: "bottom",
    desc: "bv runs graph analysis on the bead graph to rank the work, so agents take the bottlenecks first.",
    without:
      "Agents pick from a flat list, so bottleneck beads stay blocked while agents work on lower-value tasks.",
  },
] as const;

type TrioToolId = (typeof TRIO_TOOLS)[number]["id"];

/** Each edge's label sits outside the triangle, next to the middle of its edge. */
const TRIO_EDGES = [
  {
    from: "beads",
    to: "mail",
    label1: "Bead IDs thread",
    label2: "communication",
    lx: 196,
    ly: 168,
    align: "end",
  },
  {
    from: "beads",
    to: "bv",
    label1: "Dependency graph",
    label2: "drives triage",
    lx: 404,
    ly: 168,
    align: "start",
  },
  {
    from: "mail",
    to: "bv",
    label1: "Reservations inform",
    label2: "availability",
    lx: 300,
    ly: 312,
    align: "center",
  },
] as const;

const TOOL_MAP = new Map(TRIO_TOOLS.map((tool) => [tool.id, tool] as const));

const pct = (value: number, total: number) => `${(value / total) * 100}%`;

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

  const touches = (edge: (typeof TRIO_EDGES)[number], tool: TrioToolId | null) =>
    tool !== null && (edge.from === tool || edge.to === tool);

  return (
    <div ref={ref} className={EXHIBIT_PANEL_CLASS}>
      <div className="flex flex-col gap-8 border-b border-white/[0.05] pb-10 sm:pb-12 lg:flex-row lg:items-start lg:justify-between">
        <div className="max-w-2xl">
          <div className="text-xs font-black uppercase tracking-[0.4em] text-violet-400 flex items-center gap-3">
            <div className="w-8 h-px bg-violet-400/30" />
            Coordination Logic
          </div>
          <h3 className="mt-6 font-serif text-[1.5rem] font-normal leading-[1.12] tracking-[-0.008em] text-white sm:text-[1.875rem]">
            Beads, Agent Mail, and bv each do a job the other two cannot
          </h3>
          <p className="mt-6 text-[1.05rem] leading-relaxed text-zinc-400 font-light sm:mt-8 sm:text-[1.1rem]">
            Hover over a tool to see what it does. Click or tap it to remove it and see{" "}
            <Hl>what the swarm loses without it</Hl>.
          </p>
        </div>

        <div className="flex flex-col items-start lg:items-end gap-6">
          {disabledTool && (
            <motion.button
              type="button"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              onClick={() => setDisabledTool(null)}
              className="flex items-center gap-3 whitespace-nowrap px-6 py-3 rounded-2xl border border-white/10 bg-white/[0.03] text-xs font-black uppercase tracking-[0.2em] text-zinc-300 hover:text-white transition duration-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400/70"
            >
              <Repeat className="h-3 w-3" />
              Restore {TOOL_MAP.get(disabledTool)?.label}
            </motion.button>
          )}
        </div>
      </div>

      <div className="mt-8 sm:mt-12">
        {/* The SVG draws the edges and nodes and scales to the column; labels
            and the tool buttons are HTML on top, so they stay legible (and
            reachable by keyboard) at every width. */}
        <motion.div
          className="relative mx-auto w-full max-w-[640px] py-8 sm:py-10"
          // Reduced motion reveals at once; `initial` stays fixed so the
          // server-rendered hidden state is always animated away.
          initial={{ opacity: 0 }}
          animate={isInView || reducedMotion ? { opacity: 1 } : undefined}
          transition={{ duration: 0.8 }}
        >
          <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_55%,rgba(167,139,250,0.09),transparent_62%)]" />

          <div className="relative w-full" style={{ aspectRatio: `${VIEW_W} / ${VIEW_H}` }}>
            <svg
              viewBox={`0 0 ${VIEW_W} ${VIEW_H}`}
              className="absolute inset-0 h-full w-full"
              aria-hidden="true"
            >
              {TRIO_EDGES.map((edge) => {
                const from = TOOL_MAP.get(edge.from)!;
                const to = TOOL_MAP.get(edge.to)!;
                const isDisabled = touches(edge, disabledTool);
                const isHovered = touches(edge, hoveredTool);
                const mx = (from.x + to.x) / 2;
                const my = (from.y + to.y) / 2;
                const cx = mx + (CENTER.x - mx) * 0.25;
                const cy = my + (CENTER.y - my) * 0.25;

                return (
                  <motion.path
                    key={`${edge.from}-${edge.to}`}
                    d={`M ${from.x} ${from.y} Q ${cx} ${cy} ${to.x} ${to.y}`}
                    fill="none"
                    stroke={isDisabled ? "#ef4444" : "white"}
                    strokeWidth={isHovered && !isDisabled ? 2 : 1.25}
                    strokeDasharray={isDisabled ? "5 5" : isHovered ? "0" : "3 6"}
                    strokeLinecap="round"
                    // Start at the resting value; without it framer warns
                    // "animate strokeOpacity from undefined" and skips the tween.
                    initial={{ strokeOpacity: 0.28 }}
                    animate={{
                      strokeOpacity: isDisabled
                        ? 0.55
                        : hoveredTool
                          ? isHovered
                            ? 0.85
                            : 0.08
                          : 0.28,
                    }}
                    transition={{ duration: 0.4 }}
                  />
                );
              })}

              {TRIO_TOOLS.map((tool) => {
                const isDisabled = disabledTool === tool.id;
                const isHovered = hoveredTool === tool.id;
                const color = isDisabled ? "#ef4444" : tool.color;
                return (
                  <g key={tool.id}>
                    <circle
                      cx={tool.x}
                      cy={tool.y}
                      r={isHovered ? 34 : 26}
                      fill={color}
                      fillOpacity={isHovered ? 0.14 : 0.07}
                      stroke={color}
                      strokeOpacity={isDisabled ? 0.7 : isHovered ? 0.9 : 0.5}
                      strokeWidth="1.5"
                      strokeDasharray={isDisabled ? "4 4" : undefined}
                      style={{ transition: "r 300ms ease, fill-opacity 300ms ease" }}
                    />
                    <motion.circle
                      cx={tool.x}
                      cy={tool.y}
                      r={7}
                      fill={color}
                      fillOpacity={isDisabled ? 0.6 : 1}
                      animate={{ scale: isHovered && !reducedMotion ? [1, 1.35, 1] : 1 }}
                      transition={{ duration: 2, repeat: Infinity }}
                    />
                  </g>
                );
              })}
            </svg>

            {TRIO_EDGES.map((edge) => {
              const isDisabled = touches(edge, disabledTool);
              const isDimmed = hoveredTool !== null && !touches(edge, hoveredTool);
              return (
                <div
                  key={`label-${edge.from}-${edge.to}`}
                  aria-hidden="true"
                  className={`pointer-events-none absolute hidden whitespace-nowrap text-xs font-medium leading-snug transition-opacity duration-300 sm:block ${
                    edge.align === "end"
                      ? "-translate-x-full -translate-y-1/2 text-right"
                      : edge.align === "start"
                        ? "-translate-y-1/2 text-left"
                        : "-translate-x-1/2 text-center"
                  } ${isDisabled ? "text-red-300/70 line-through" : "text-zinc-400"} ${
                    isDimmed ? "opacity-25" : "opacity-100"
                  }`}
                  style={{ left: pct(edge.lx, VIEW_W), top: pct(edge.ly, VIEW_H) }}
                >
                  {edge.label1}
                  <br />
                  {edge.label2}
                </div>
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
                <button
                  key={tool.id}
                  type="button"
                  aria-pressed={isDisabled}
                  aria-label={`Remove ${tool.label}`}
                  onMouseEnter={() => {
                    if (isFinePointer.current && !disabledTool) setHoveredTool(tool.id);
                  }}
                  onMouseLeave={() => {
                    if (isFinePointer.current) setHoveredTool(null);
                  }}
                  onFocus={() => {
                    if (!disabledTool) setHoveredTool(tool.id);
                  }}
                  onBlur={() => setHoveredTool(null)}
                  onClick={() => {
                    setHoveredTool(null);
                    setDisabledTool(isDisabled ? null : tool.id);
                  }}
                  className={`group absolute flex h-14 w-14 -translate-x-1/2 -translate-y-1/2 cursor-crosshair items-center justify-center rounded-full transition-opacity duration-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400/70 sm:h-16 sm:w-16 ${
                    isConnected ? "opacity-100" : "opacity-40"
                  }`}
                  style={{ left: pct(tool.x, VIEW_W), top: pct(tool.y, VIEW_H) }}
                >
                  <span
                    className={`pointer-events-none absolute left-1/2 -translate-x-1/2 whitespace-nowrap text-xs font-black uppercase tracking-[0.14em] sm:tracking-[0.18em] ${
                      tool.labelSide === "top" ? "bottom-full mb-1 sm:mb-2" : "top-full mt-1 sm:mt-2"
                    } ${isDisabled ? "text-red-400 line-through" : ""}`}
                    style={isDisabled ? undefined : { color: isHovered ? "#fff" : tool.color }}
                  >
                    {tool.label}
                    {tool.sub && (
                      <span className="ml-1.5 font-mono text-xs font-medium normal-case tracking-normal text-zinc-400">
                        {tool.sub}
                      </span>
                    )}
                  </span>
                </button>
              );
            })}
          </div>

          <ul className="relative mt-6 space-y-2 sm:hidden">
            {TRIO_EDGES.map((edge) => (
              <li
                key={`list-${edge.from}-${edge.to}`}
                className={`text-[13px] leading-snug ${
                  touches(edge, disabledTool) ? "text-red-300/70 line-through" : "text-zinc-400"
                }`}
              >
                <span className="font-semibold text-zinc-200">
                  {TOOL_MAP.get(edge.from)?.label} and {TOOL_MAP.get(edge.to)?.label}:
                </span>{" "}
                {edge.label1} {edge.label2}
              </li>
            ))}
          </ul>
        </motion.div>

        <div className="mt-8 grid gap-6 md:grid-cols-2 md:items-start">
          <div className="p-7 rounded-[2rem] bg-white/[0.015] border border-white/[0.05] sm:p-8 sm:rounded-[2.5rem]">
            <span className="text-xs font-black text-zinc-500 uppercase tracking-[0.4em]">
              Capability Map
            </span>
            <div className="mt-6 flex flex-col gap-5 sm:mt-8 sm:gap-6">
              {[
                {
                  l: "Agent Mail",
                  t: "Messages and file reservations between agents.",
                  c: "text-[#FF5500]",
                },
                { l: "br", t: "The issue tracker, stored in the repo.", c: "text-violet-400" },
                { l: "bv", t: "Graph analysis that ranks beads for triage.", c: "text-[#FFBD2E]" },
              ].map((item) => (
                <div key={item.l} className="flex flex-col gap-1">
                  <span className={`text-xs font-bold tracking-wide ${item.c}`}>{item.l}</span>
                  <p className="text-sm text-zinc-400 font-light leading-relaxed">{item.t}</p>
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
                className="p-7 rounded-[2rem] bg-[#100505] border border-red-500/15 shadow-inner sm:p-10 sm:rounded-[2.5rem]"
              >
                <span className="text-xs font-black text-red-400 uppercase tracking-[0.4em] block mb-5">
                  What Breaks
                </span>
                <div className="text-lg font-black text-white mb-2">
                  Missing {TOOL_MAP.get(disabledTool)?.label}
                </div>
                <p className="text-[1.05rem] leading-relaxed text-red-100/80 font-light italic">
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
                className="p-7 rounded-[2rem] bg-[#0a0c10] border border-white/[0.06] shadow-inner sm:p-10 sm:rounded-[2.5rem]"
              >
                <div
                  className="text-xs font-black uppercase tracking-[0.4em] block mb-5"
                  style={{ color: TOOL_MAP.get(hoveredTool)?.color }}
                >
                  What It Does
                </div>
                <div className="text-lg font-black text-white mb-2">
                  {TOOL_MAP.get(hoveredTool)?.label}
                </div>
                <p className="text-[1.05rem] leading-relaxed text-zinc-300 font-light italic">
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
                className="p-7 rounded-[2rem] bg-[#0a0c10] border border-white/[0.06] shadow-inner sm:p-10 sm:rounded-[2.5rem]"
              >
                <span className="text-xs font-black text-primary uppercase tracking-[0.4em] block mb-5">
                  How They Fit Together
                </span>
                <p className="text-[1.05rem] leading-relaxed text-zinc-300 font-light italic">
                  The three tools split the coordination work: beads hold the task graph, Agent Mail
                  carries messages and file reservations between agents, and bv ranks what to work
                  on next. Remove any one and the other two cannot do its job.
                </p>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
