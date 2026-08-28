"use client";

import { useState, useRef } from "react";
import { motion, AnimatePresence, useInView } from "@/components/motion";
import { Mail, Zap, XOctagon, CheckCircle2 } from "lucide-react";
import { cn } from "@/lib/utils";

type Mode = "broadcast" | "agentmail";

export function AgentMailViz() {
  const [mode, setMode] = useState<Mode>("agentmail");
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });

  const agents = [
    { id: 1, x: 20, y: 20, color: "#FF5500", name: "A1 (UI)" },
    { id: 2, x: 80, y: 20, color: "#A1A1AA", name: "A2 (DB)" },
    { id: 3, x: 20, y: 80, color: "#71717A", name: "A3 (API)" },
    { id: 4, x: 80, y: 80, color: "#52525B", name: "A4 (Tests)" }
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

  // Targeted lines for Agent Mail
  const directLines = [
    { from: agents[0], to: agents[2], active: true, msg: "Need /api/users" },
    { from: agents[1], to: agents[2], active: true, msg: "Schema updated" },
  ];

  return (
    <div ref={ref} className="my-12 rounded-3xl border border-white/[0.06] bg-[#05070a] shadow-2xl overflow-hidden flex flex-col group/viz relative">
      <div className="absolute inset-0 noise-overlay opacity-[0.02] mix-blend-overlay pointer-events-none" />
      
      {/* HEADER */}
      <div className="relative z-10 flex flex-col sm:flex-row items-start sm:items-center justify-between p-6 sm:p-8 border-b border-white/[0.04] bg-white/[0.01] backdrop-blur-md">
        <div>
          <div className="text-[0.65rem] font-bold text-white/30 uppercase tracking-widest mb-2 flex items-center gap-2">
            <span className={cn("w-1.5 h-1.5 rounded-full animate-pulse", mode === "broadcast" ? "bg-[#FF5F56]" : "bg-[#FF5500]")} />
            Interactive Visualization
          </div>
          <div className="flex items-center gap-3">
            <span className={cn(
              "flex h-8 w-8 items-center justify-center rounded-xl transition duration-500 shadow-inner",
              mode === "broadcast" ? "bg-[#FF5F56]/10 text-[#FF5F56] border border-[#FF5F56]/20" : "bg-[#FF5500]/10 text-[#FF5500] border border-[#FF5500]/20"
            )}>
              <Mail className="h-4 w-4" />
            </span>
            <h4 className="text-xl sm:text-2xl font-black text-white tracking-tight">Broadcast vs. Point-to-Point</h4>
          </div>
          <p className="mt-2 text-sm text-zinc-400 font-light max-w-xl">
            {mode === "broadcast" 
              ? "Broadcast spam burns context window with O(N²) irrelevant messages. Agents drown in noise." 
              : "Agent Mail uses targeted delivery and advisory locks to stay efficient. O(1) noise."}
          </p>
        </div>

        {/* CONTROLS */}
        <div className="mt-6 sm:mt-0 flex p-1 bg-black/40 rounded-2xl border border-white/[0.05] shadow-inner">
          <button 
            onClick={() => setMode("broadcast")}
            className={cn(
              "px-4 py-2 sm:py-2.5 rounded-xl text-xs sm:text-sm font-bold tracking-wide transition duration-500 flex items-center gap-2",
              mode === "broadcast" ? "bg-[#FF5F56]/10 text-[#FF5F56] shadow-sm border border-[#FF5F56]/20" : "text-white/40 hover:text-white/80 border border-transparent"
            )}
          >
            <XOctagon className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            Broadcast
          </button>
          <button 
            onClick={() => setMode("agentmail")}
            className={cn(
              "px-4 py-2 sm:py-2.5 rounded-xl text-xs sm:text-sm font-bold tracking-wide transition duration-500 flex items-center gap-2",
              mode === "agentmail" ? "bg-[#FF5500]/10 text-[#FF5500] shadow-sm border border-[#FF5500]/20" : "text-white/40 hover:text-white/80 border border-transparent"
            )}
          >
            <CheckCircle2 className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            Agent Mail
          </button>
        </div>
      </div>

      {/* CANVAS */}
      <div className="relative flex-1 min-h-[450px] bg-[#020408] flex items-center justify-center p-8 overflow-hidden">
        <div className={cn(
          "absolute inset-0 transition-opacity duration-1000 opacity-20",
          mode === "broadcast" ? "bg-[radial-gradient(ellipse_at_center,rgba(255,95,86,0.15),transparent_70%)]" : "bg-[radial-gradient(ellipse_at_center,rgba(255,85,0,0.15),transparent_70%)]"
        )} />
        
        {/* State Indicators */}
        <div className="absolute top-6 left-6 z-20 pointer-events-none">
          <AnimatePresence mode="wait">
            {mode === "broadcast" ? (
               <motion.div key="broadcast" initial={{ opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 10 }} className="flex flex-col gap-2">
                 <span className="text-xs font-bold uppercase tracking-widest text-[#FF5F56] bg-[#FF5F56]/10 px-3 py-1.5 rounded-lg border border-[#FF5F56]/20 shadow-[0_0_15px_rgba(255,95,86,0.15)] flex items-center gap-2"><Zap className="h-3 w-3" /> O(N²) Messages</span>
                 <span className="text-xs font-bold uppercase tracking-widest text-[#FF5F56] bg-[#FF5F56]/10 px-3 py-1.5 rounded-lg border border-[#FF5F56]/20 shadow-[0_0_15px_rgba(255,95,86,0.15)] flex items-center gap-2"><Zap className="h-3 w-3" /> High Token Burn</span>
                 <span className="text-xs font-bold uppercase tracking-widest text-[#FF5F56] bg-[#FF5F56]/10 px-3 py-1.5 rounded-lg border border-[#FF5F56]/20 shadow-[0_0_15px_rgba(255,95,86,0.15)] flex items-center gap-2"><Zap className="h-3 w-3" /> Context Dilution</span>
               </motion.div>
            ) : (
               <motion.div key="agentmail" initial={{ opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 10 }} className="flex flex-col gap-2">
                 <span className="text-xs font-bold uppercase tracking-widest text-[#FF5500] bg-[#FF5500]/10 px-3 py-1.5 rounded-lg border border-[#FF5500]/20 shadow-[0_0_15px_rgba(255,85,0,0.15)] flex items-center gap-2"><CheckCircle2 className="h-3 w-3" /> O(1) Messages</span>
                 <span className="text-xs font-bold uppercase tracking-widest text-[#FFBD2E] bg-[#FFBD2E]/10 px-3 py-1.5 rounded-lg border border-[#FFBD2E]/20 shadow-[0_0_15px_rgba(255,189,46,0.15)] flex items-center gap-2"><CheckCircle2 className="h-3 w-3" /> Advisory Locks</span>
                 <span className="text-xs font-bold uppercase tracking-widest text-[#FF5500] bg-[#FF5500]/10 px-3 py-1.5 rounded-lg border border-[#FF5500]/20 shadow-[0_0_15px_rgba(255,85,0,0.15)] flex items-center gap-2"><CheckCircle2 className="h-3 w-3" /> High SNR</span>
               </motion.div>
            )}
          </AnimatePresence>
        </div>

        <div className="relative w-full max-w-lg aspect-square">
          {/* SVG Connection Lines */}
          <svg className="absolute inset-0 w-full h-full pointer-events-none overflow-visible">
            <defs>
              <filter id="glow">
                <feGaussianBlur stdDeviation="3" result="coloredBlur"/>
                <feMerge>
                  <feMergeNode in="coloredBlur"/>
                  <feMergeNode in="SourceGraphic"/>
                </feMerge>
              </filter>
            </defs>

            <AnimatePresence>
              {mode === "broadcast" ? (
                // Broadcast Lines
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
                      strokeDashoffset: { duration: 0.8, repeat: Infinity, ease: "linear" }
                    }}
                    filter="url(#glow)"
                  />
                ))
              ) : (
                // Targeted Lines
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
                        strokeDashoffset: { duration: 1.5, repeat: Infinity, ease: "linear" }
                      }}
                      filter="url(#glow)"
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
                ))
              )}
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
                boxShadow: `0 0 30px ${agent.color}15, inset 0 0 20px ${agent.color}10`
              }}
            >
              <div 
                className="w-3 h-3 rounded-full mb-1"
                style={{ 
                  backgroundColor: agent.color,
                  boxShadow: `0 0 10px ${agent.color}`
                }} 
              />
              <span className="text-[10px] font-bold text-white tracking-widest">{agent.name}</span>
            </motion.div>
          ))}

          {/* Messages for Agent Mail mode */}
          <AnimatePresence>
            {mode === "agentmail" && directLines.map((line, i) => (
              <motion.div
                key={`msg-${i}`}
                initial={{ opacity: 0, scale: 0.5 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.5 }}
                transition={{ delay: 0.3 + i * 0.2, type: "spring", stiffness: 300, damping: 20 }}
                className="absolute z-20 bg-[#FF5500]/10 border border-[#FF5500]/30 text-[#FF5500] text-[10px] px-3 py-1.5 rounded-full font-medium whitespace-nowrap shadow-[0_0_15px_rgba(255,85,0,0.2)] backdrop-blur-md"
                style={{
                  left: `${(line.from.x + line.to.x) / 2}%`,
                  top: `${(line.from.y + line.to.y) / 2}%`,
                  transform: 'translate(-50%, -50%)'
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
