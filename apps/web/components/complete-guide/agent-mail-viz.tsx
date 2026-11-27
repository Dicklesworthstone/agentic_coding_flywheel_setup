"use client";

import { CheckCircle2, Mail, XOctagon, Zap } from "lucide-react";
import { useId, useRef, useState } from "react";
import { AnimatePresence, motion, useInView } from "@/components/motion";
import { cn } from "@/lib/utils";

type Mode = "broadcast" | "agentmail";

const MODE_BADGES: Record<Mode, { label: string; color: string; rgb: string }[]> = {
  broadcast: [
    { label: "O(N²) Messages", color: "#FF5F56", rgb: "255,95,86" },
    { label: "High Token Burn", color: "#FF5F56", rgb: "255,95,86" },
    { label: "Context Dilution", color: "#FF5F56", rgb: "255,95,86" },
  ],
  agentmail: [
    { label: "O(1) Messages", color: "#FF5500", rgb: "255,85,0" },
    { label: "Advisory Locks", color: "#FFBD2E", rgb: "255,189,46" },
    { label: "High SNR", color: "#FF5500", rgb: "255,85,0" },
  ],
};

export function AgentMailViz() {
  const [mode, setMode] = useState<Mode>("agentmail");
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });
  // A page-unique filter id: a bare id="glow" would resolve to whichever
  // element with that id comes first in the document.
  const glowId = `agent-mail-glow-${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;

  const agents = [
    { id: 1, x: 20, y: 20, color: "#FF5500", name: "A1 (UI)" },
    { id: 2, x: 80, y: 20, color: "#A1A1AA", name: "A2 (DB)" },
    { id: 3, x: 20, y: 80, color: "#71717A", name: "A3 (API)" },
    { id: 4, x: 80, y: 80, color: "#52525B", name: "A4 (Tests)" },
  ];

  // Draw lines between all nodes for broadcast
  const broadcastLines = [];
  for (let i = 0; i < agents.length; i++) {
    for (let j = 0; j < agents.length; j++) {
      if (i !== j) {
        broadcastLines.push({ from: agents[i], to: agents[j] });
      }
    }
  }

  // Targeted lines for Agent Mail. `at` is how far along the path (0 = sender,
  // 1 = recipient) the message pill sits; the two values keep the pills on
  // their own lines without overlapping each other on a phone.
  const directLines = [
    { from: agents[0], to: agents[2], msg: "Need /api/users", at: 0.56 },
    { from: agents[1], to: agents[2], msg: "Schema updated", at: 0.38 },
  ];

  return (
    <div
      ref={ref}
      className="my-12 rounded-3xl border border-white/[0.06] bg-[#05070a] shadow-2xl overflow-hidden flex flex-col group/viz relative"
    >
      <div className="absolute inset-0 noise-overlay opacity-[0.02] mix-blend-overlay pointer-events-none" />

      {/* HEADER */}
      <div className="relative z-10 flex flex-col lg:flex-row items-start lg:items-center justify-between gap-6 p-6 sm:p-8 border-b border-white/[0.04] bg-white/[0.01] backdrop-blur-md">
        <div className="min-w-0">
          <div className="text-xs font-bold text-zinc-500 uppercase tracking-widest mb-2 flex items-center gap-2">
            <span
              className={cn(
                "w-1.5 h-1.5 rounded-full",
                mode === "broadcast" ? "bg-[#FF5F56]" : "bg-[#FF5500]",
              )}
            />
            Interactive Visualization
          </div>
          <div className="flex items-center gap-3">
            <span
              className={cn(
                "flex h-8 w-8 items-center justify-center rounded-xl transition duration-500 shadow-inner",
                mode === "broadcast"
                  ? "bg-[#FF5F56]/10 text-[#FF5F56] border border-[#FF5F56]/20"
                  : "bg-[#FF5500]/10 text-[#FF5500] border border-[#FF5500]/20",
              )}
            >
              <Mail className="h-4 w-4" />
            </span>
            <h4 className="font-serif text-[1.5rem] font-normal leading-[1.12] tracking-[-0.008em] text-white sm:text-[1.875rem]">
              Broadcast vs. Point-to-Point
            </h4>
          </div>
          <p className="mt-2 text-sm text-zinc-400 font-light max-w-xl">
            {mode === "broadcast"
              ? "Broadcast sends every message to every agent, so traffic grows as O(N²) and most of what lands in each context window is irrelevant."
              : "Agent Mail sends each message only to the agents it concerns and uses advisory locks, so the noise each agent sees stays constant as the swarm grows."}
          </p>
        </div>

        {/* CONTROLS */}
        <div className="flex shrink-0 p-1 bg-black/40 rounded-2xl border border-white/[0.05] shadow-inner">
          <button
            type="button"
            aria-pressed={mode === "broadcast"}
            onClick={() => setMode("broadcast")}
            className={cn(
              "px-4 py-2 sm:py-2.5 rounded-xl text-xs sm:text-sm font-bold tracking-wide whitespace-nowrap transition duration-500 flex items-center gap-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/60",
              mode === "broadcast"
                ? "bg-[#FF5F56]/10 text-[#FF5F56] shadow-sm border border-[#FF5F56]/20"
                : "text-zinc-400 hover:text-zinc-100 border border-transparent",
            )}
          >
            <XOctagon className="h-3.5 w-3.5 shrink-0 sm:h-4 sm:w-4" />
            Broadcast
          </button>
          <button
            type="button"
            aria-pressed={mode === "agentmail"}
            onClick={() => setMode("agentmail")}
            className={cn(
              "px-4 py-2 sm:py-2.5 rounded-xl text-xs sm:text-sm font-bold tracking-wide whitespace-nowrap transition duration-500 flex items-center gap-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF5500]/60",
              mode === "agentmail"
                ? "bg-[#FF5500]/10 text-[#FF5500] shadow-sm border border-[#FF5500]/20"
                : "text-zinc-400 hover:text-zinc-100 border border-transparent",
            )}
          >
            <CheckCircle2 className="h-3.5 w-3.5 shrink-0 sm:h-4 sm:w-4" />
            Agent Mail
          </button>
        </div>
      </div>

      {/* CANVAS */}
      <div className="@container relative flex-1 min-h-[450px] bg-[#020408] flex flex-col items-center justify-center p-6 sm:p-8 overflow-hidden">
        <div
          className={cn(
            "absolute inset-0 transition-opacity duration-1000 opacity-20",
            mode === "broadcast"
              ? "bg-[radial-gradient(ellipse_at_center,rgba(255,95,86,0.15),transparent_70%)]"
              : "bg-[radial-gradient(ellipse_at_center,rgba(255,85,0,0.15),transparent_70%)]",
          )}
        />

        {/* State Indicators. In a narrow canvas they sit in a row above the
            diagram; only a wide canvas has room beside agent A1 for the
            stacked corner column. Both sets share one grid cell and cross-fade,
            so switching modes never shifts the diagram. */}
        <div className="relative z-20 mb-6 grid w-full pointer-events-none @min-[50rem]:absolute @min-[50rem]:top-6 @min-[50rem]:left-6 @min-[50rem]:mb-0 @min-[50rem]:w-auto">
          {(Object.keys(MODE_BADGES) as Mode[]).map((badgeMode) => {
            const active = mode === badgeMode;
            const Icon = badgeMode === "broadcast" ? Zap : CheckCircle2;
            return (
              <motion.div
                key={badgeMode}
                aria-hidden={!active}
                initial={false}
                animate={{ opacity: active ? 1 : 0, y: active ? 0 : -8 }}
                transition={{ duration: 0.3 }}
                className="[grid-area:1/1] flex flex-wrap content-start items-start gap-1.5 @min-[50rem]:flex-col @min-[50rem]:gap-2"
              >
                {MODE_BADGES[badgeMode].map((badge) => (
                  <span
                    key={badge.label}
                    className="text-xs font-bold uppercase tracking-wide px-2.5 py-1 rounded-lg border flex items-center gap-1.5 whitespace-nowrap @min-[50rem]:tracking-widest @min-[50rem]:px-3 @min-[50rem]:py-1.5 @min-[50rem]:gap-2"
                    style={{
                      color: badge.color,
                      backgroundColor: `rgba(${badge.rgb},0.1)`,
                      borderColor: `rgba(${badge.rgb},0.2)`,
                      boxShadow: `0 0 15px rgba(${badge.rgb},0.15)`,
                    }}
                  >
                    <Icon className="h-3 w-3 shrink-0" /> {badge.label}
                  </span>
                ))}
              </motion.div>
            );
          })}
        </div>

        <div className="relative w-full max-w-lg aspect-square">
          {/* SVG Connection Lines */}
          <svg className="absolute inset-0 w-full h-full pointer-events-none overflow-visible">
            <defs>
              {/* userSpaceOnUse: with the default objectBoundingBox units a
                  vertical or horizontal line has a zero-width box, so the
                  filter region collapses and the line is not drawn at all. */}
              <filter
                id={glowId}
                filterUnits="userSpaceOnUse"
                x="-10%"
                y="-10%"
                width="120%"
                height="120%"
              >
                <feGaussianBlur stdDeviation="3" result="coloredBlur" />
                <feMerge>
                  <feMergeNode in="coloredBlur" />
                  <feMergeNode in="SourceGraphic" />
                </feMerge>
              </filter>
            </defs>

            <AnimatePresence>
              {mode === "broadcast"
                ? // Broadcast Lines
                  broadcastLines.map((line, i) => (
                    <motion.line
                      key={`bc-${i}`}
                      x1={`${line.from.x}%`}
                      y1={`${line.from.y}%`}
                      x2={`${line.to.x}%`}
                      y2={`${line.to.y}%`}
                      stroke="#FF5F56"
                      strokeWidth="2"
                      strokeDasharray="4 8"
                      initial={{ opacity: 0, strokeDashoffset: 24 }}
                      animate={{ opacity: 0.5, strokeDashoffset: 0 }}
                      exit={{ opacity: 0 }}
                      transition={{
                        opacity: { duration: 0.5 },
                        strokeDashoffset: { duration: 0.8, repeat: Infinity, ease: "linear" },
                      }}
                      filter={`url(#${glowId})`}
                    />
                  ))
                : // Targeted Lines
                  directLines.map((line, i) => (
                    <g key={`dl-${i}`}>
                      <motion.line
                        x1={`${line.from.x}%`}
                        y1={`${line.from.y}%`}
                        x2={`${line.to.x}%`}
                        y2={`${line.to.y}%`}
                        stroke="#FF5500"
                        strokeWidth="2"
                        strokeDasharray="6 6"
                        initial={{ opacity: 0, strokeDashoffset: 20 }}
                        animate={{ opacity: 0.8, strokeDashoffset: 0 }}
                        exit={{ opacity: 0 }}
                        transition={{
                          opacity: { duration: 0.5 },
                          strokeDashoffset: { duration: 1.5, repeat: Infinity, ease: "linear" },
                        }}
                        filter={`url(#${glowId})`}
                      />
                      <motion.circle
                        cx={`${line.to.x}%`}
                        cy={`${line.to.y}%`}
                        r="4"
                        fill="#FF5500"
                        initial={{ opacity: 0, scale: 0 }}
                        animate={{ opacity: [0, 1, 0], scale: [1, 2, 3] }}
                        transition={{ duration: 1.5, repeat: Infinity, delay: i * 0.5 }}
                      />
                    </g>
                  ))}
            </AnimatePresence>
          </svg>

          {/* Agent Nodes */}
          {agents.map((agent, i) => (
            <motion.div
              key={agent.id}
              initial={{ scale: 0.8, opacity: 0 }}
              animate={isInView ? { scale: 1, opacity: 1 } : undefined}
              transition={{ delay: i * 0.1, type: "spring", stiffness: 200, damping: 20 }}
              className="absolute w-20 h-20 -ml-10 -mt-10 rounded-2xl flex flex-col items-center justify-center gap-1 border bg-[#05070a] shadow-2xl z-10 backdrop-blur-xl"
              style={{
                left: `${agent.x}%`,
                top: `${agent.y}%`,
                borderColor: `${agent.color}40`,
                boxShadow: `0 0 30px ${agent.color}15, inset 0 0 20px ${agent.color}10`,
              }}
            >
              <div
                className="w-3 h-3 rounded-full mb-1"
                style={{
                  backgroundColor: agent.color,
                  boxShadow: `0 0 10px ${agent.color}`,
                }}
              />
              <span className="text-xs font-bold text-white tracking-widest">{agent.name}</span>
            </motion.div>
          ))}

          {/* Messages for Agent Mail mode */}
          <AnimatePresence>
            {mode === "agentmail" &&
              directLines.map((line, i) => (
                <motion.div
                  key={`msg-${i}`}
                  initial={{ opacity: 0, scale: 0.5 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.5 }}
                  transition={{ delay: 0.3 + i * 0.2, type: "spring", stiffness: 300, damping: 20 }}
                  className="absolute z-20 bg-[#140a05] border border-[#FF5500]/40 text-[#FF7A33] text-xs px-3 py-1.5 rounded-full font-medium whitespace-nowrap shadow-[0_0_15px_rgba(255,85,0,0.2)]"
                  // Centre the pill on its point of the path. The offset goes
                  // through motion's x/y: a CSS `transform` here would be
                  // overwritten by the scale animation, which is what left the
                  // pills hanging off to the right of their lines.
                  style={{
                    left: `${line.from.x + (line.to.x - line.from.x) * line.at}%`,
                    top: `${line.from.y + (line.to.y - line.from.y) * line.at}%`,
                    x: "-50%",
                    y: "-50%",
                  }}
                >
                  {line.msg}
                </motion.div>
              ))}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
