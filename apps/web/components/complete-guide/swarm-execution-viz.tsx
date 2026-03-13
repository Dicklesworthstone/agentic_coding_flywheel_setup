"use client";

import { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Users, AlertTriangle, CheckCircle2, Play, RotateCcw } from "lucide-react";
import { cn } from "@/lib/utils";

const AGENT_COUNT = 4;
const BEAD_COUNT = 6;

type SimState = "idle" | "running_herd" | "running_staggered" | "finished";

export function SwarmExecutionViz() {
  const [state, setState] = useState<SimState>("idle");
  const [mode, setMode] = useState<"herd" | "staggered">("staggered");
  const [agentProgress, setAgentProgress] = useState<number[]>(Array(AGENT_COUNT).fill(0));
  const [beadClaims, setBeadClaims] = useState<(number | "collision" | null)[]>(Array(BEAD_COUNT).fill(null));
  const timerRef = useRef<NodeJS.Timeout | null>(null);
  const progressRef = useRef<number[]>(Array(AGENT_COUNT).fill(0));
  const ref = useRef<HTMLDivElement>(null);

  // Cleanup timers on unmount
  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  const runSimulation = (simMode: "herd" | "staggered") => {
    if (timerRef.current) clearTimeout(timerRef.current);
    setMode(simMode);
    setState(simMode === "herd" ? "running_herd" : "running_staggered");
    progressRef.current = Array(AGENT_COUNT).fill(0);
    setAgentProgress(Array(AGENT_COUNT).fill(0));
    setBeadClaims(Array(BEAD_COUNT).fill(null));

    let step = 0;
    
    const tick = () => {
      step++;
      
      setAgentProgress(prev => {
        const next = [...prev];
        if (simMode === "herd") {
          for (let i=0; i<AGENT_COUNT; i++) {
             next[i] = Math.min(100, next[i] + Math.random() * 15 + 10);
          }
        } else {
          for (let i=0; i<AGENT_COUNT; i++) {
             if (step > i * 4) {
               next[i] = Math.min(100, next[i] + Math.random() * 15 + 10);
             }
          }
        }
        progressRef.current = next;
        return next;
      });

      // Claim logic — runs separately to avoid nested setState
      setBeadClaims(prevClaims => {
        const newClaims = [...prevClaims];

        if (simMode === "herd") {
          if (step === 2) {
            newClaims[0] = "collision";
          } else if (step === 4) {
            newClaims[1] = "collision";
          }
        } else {
          // Staggered: agents claim available beads cleanly
          const prog = progressRef.current;
          for (let i = 0; i < AGENT_COUNT; i++) {
            if (prog[i] > 20 && !newClaims.includes(i)) {
              const freeIdx = newClaims.indexOf(null);
              if (freeIdx !== -1) newClaims[freeIdx] = i;
            }
          }
        }
        return newClaims;
      });

      if (step < 20) {
        timerRef.current = setTimeout(tick, 400);
      } else {
        setState("finished");
      }
    };

    timerRef.current = setTimeout(tick, 400);
  };

  const handleReset = () => {
    if (timerRef.current) clearTimeout(timerRef.current);
    setState("idle");
    setAgentProgress(Array(AGENT_COUNT).fill(0));
    setBeadClaims(Array(BEAD_COUNT).fill(null));
  };

  const isRunning = state === "running_herd" || state === "running_staggered";

  return (
    <div ref={ref} className="my-10 rounded-2xl border border-white/[0.08] bg-[#0a0a0c] shadow-2xl glass-subtle overflow-hidden">
      
      {/* HEADER */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between p-5 border-b border-white/[0.05] bg-white/[0.01]">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="flex h-6 w-6 items-center justify-center rounded-md bg-emerald-500/20 text-emerald-400">
              <Users className="h-3.5 w-3.5" />
            </span>
            <h4 className="text-sm font-semibold text-white/90">Interactive: Staggered Starts vs. Thundering Herd</h4>
          </div>
          <p className="text-xs text-white/50">Watch how agent initialization timing affects lock contention.</p>
        </div>

        {/* CONTROLS */}
        <div className="mt-4 sm:mt-0 flex items-center gap-2 bg-black/40 p-1.5 rounded-xl border border-white/[0.05]">
          <button 
            onClick={() => runSimulation("staggered")}
            disabled={isRunning}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg hover:bg-emerald-500/20 hover:text-emerald-400 text-white/70 transition-colors disabled:opacity-50 text-xs font-medium"
          >
            <Play className="h-3.5 w-3.5" />
            Staggered
          </button>
          
          <button 
            onClick={() => runSimulation("herd")}
            disabled={isRunning}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg hover:bg-red-500/20 hover:text-red-400 text-white/70 transition-colors disabled:opacity-50 text-xs font-medium"
          >
            <Play className="h-3.5 w-3.5" />
            Herd
          </button>

          <div className="h-4 w-px bg-white/10 mx-1" />
          
          <button
            onClick={handleReset}
            aria-label="Reset simulation"
            className="flex items-center justify-center h-8 w-8 rounded-lg hover:bg-white/10 text-white/70 transition-colors"
          >
            <RotateCcw className="h-4 w-4" />
          </button>
        </div>
      </div>

      {/* CANVAS */}
      <div className="p-6 relative bg-[radial-gradient(ellipse_at_top,rgba(16,185,129,0.05),transparent_60%)]">
        
        {/* Status Overlay */}
        <AnimatePresence mode="popLayout">
          {state === "finished" && (
            <motion.div 
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0 }}
              className="absolute top-4 right-4 z-20"
            >
              {mode === "staggered" ? (
                <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs font-medium backdrop-blur-md shadow-[0_0_15px_rgba(16,185,129,0.15)]">
                  <CheckCircle2 className="h-4 w-4" /> Seamless Claims
                </div>
              ) : (
                <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-red-500/10 border border-red-500/20 text-red-400 text-xs font-medium backdrop-blur-md shadow-[0_0_15px_rgba(239,68,68,0.15)]">
                  <AlertTriangle className="h-4 w-4" /> Contention Detected
                </div>
              )}
            </motion.div>
          )}
        </AnimatePresence>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          
          {/* AGENTS LIST */}
          <div className="space-y-4">
            <h5 className="text-xs font-mono text-white/40 mb-2 uppercase tracking-wider">Agent Swarm</h5>
            {Array(AGENT_COUNT).fill(0).map((_, i) => (
              <div key={`agent-${i}`} className="relative bg-black/40 border border-white/5 rounded-xl p-3 flex items-center gap-4 overflow-hidden">
                <div className="absolute top-0 left-0 bottom-0 bg-white/[0.02]" style={{ width: `${agentProgress[i]}%`, transition: 'width 0.3s ease-out' }} />
                
                <div className={cn(
                  "h-8 w-8 rounded-lg flex items-center justify-center font-mono text-xs border relative z-10 transition-colors duration-300",
                  agentProgress[i] > 0 
                    ? "bg-primary/20 border-primary/50 text-primary shadow-[0_0_10px_rgba(34,211,238,0.2)]" 
                    : "bg-white/5 border-white/10 text-white/30"
                )}>
                  A{i+1}
                </div>
                
                <div className="flex-1 relative z-10">
                  <div className="flex justify-between text-xs mb-1.5">
                    <span className="text-white/70">
                      {agentProgress[i] === 0 ? "Pending start..." 
                        : agentProgress[i] < 20 ? "Initializing (AGENTS.md)..."
                        : "Executing..."}
                    </span>
                  </div>
                  <div className="h-1.5 w-full bg-white/5 rounded-full overflow-hidden">
                    <div 
                      className={cn(
                        "h-full rounded-full transition-all duration-300",
                        mode === "herd" && state === "finished" ? "bg-red-500" : "bg-primary"
                      )}
                      style={{ width: `${agentProgress[i]}%` }}
                    />
                  </div>
                </div>
              </div>
            ))}
          </div>

          {/* BEADS LIST */}
          <div>
            <h5 className="text-xs font-mono text-white/40 mb-2 uppercase tracking-wider">Ready Beads (Queue)</h5>
            <div className="grid grid-cols-2 gap-3">
              {beadClaims.map((claim, i) => {
                const isCollision = claim === "collision";
                const isClaimed = typeof claim === "number";
                
                return (
                  <motion.div 
                    key={`bead-${i}`}
                    className={cn(
                      "p-3 rounded-xl border flex flex-col gap-2 transition-colors duration-300 relative overflow-hidden",
                      isCollision ? "bg-red-500/10 border-red-500/40" 
                        : isClaimed ? "bg-emerald-500/10 border-emerald-500/40"
                        : "bg-[#1a1b1e] border-white/[0.05]"
                    )}
                    animate={isCollision ? { x: [-2, 2, -2, 2, 0] } : {}}
                    transition={{ duration: 0.4 }}
                  >
                    {isCollision && (
                      <div className="absolute inset-0 bg-red-500/5 animate-pulse" />
                    )}
                    
                    <div className="flex justify-between items-center relative z-10">
                      <span className="font-mono text-xs text-white/60">br-{100 + i}</span>
                      {isCollision ? (
                        <AlertTriangle className="h-3.5 w-3.5 text-red-400" />
                      ) : isClaimed ? (
                        <div className="h-5 w-5 rounded bg-emerald-500/20 flex items-center justify-center text-[10px] font-mono font-bold text-emerald-400">
                          A{claim + 1}
                        </div>
                      ) : (
                        <div className="h-1.5 w-1.5 rounded-full bg-white/20" />
                      )}
                    </div>
                    
                    <div className="text-[10px] text-white/40 relative z-10">
                      {isCollision ? (
                        <span className="text-red-400 font-medium">Race condition (Lock failed)</span>
                      ) : isClaimed ? (
                        <span className="text-emerald-400 font-medium">Claimed & Locked</span>
                      ) : (
                        "Available"
                      )}
                    </div>
                  </motion.div>
                );
              })}
            </div>
          </div>

        </div>
      </div>
    </div>
  );
}
