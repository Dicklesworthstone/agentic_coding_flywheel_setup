"use client";

import { useState, useRef } from "react";
import { motion, useInView, useReducedMotion, AnimatePresence } from "framer-motion";
import { BrainCircuit, FileCode2, ScrollText, AlertOctagon, CheckCircle2 } from "lucide-react";
import { cn } from "@/lib/utils";

export function ContextHorizonViz() {
  const [scale, setScale] = useState(20); // 0 to 100
  const ref = useRef<HTMLDivElement>(null);
  
  const isInView = useInView(ref, { once: false, margin: "-50px" });
  const prefersReducedMotion = useReducedMotion();
  const rm = prefersReducedMotion ?? false;

  // Math models for sizes (arbitrary visual units)
  const tokenHorizon = 300; // Fixed visual height of context window limit
  
  // Plan grows logarithmically (abstractions scale well)
  const planSize = Math.max(40, Math.log10(scale + 1) * 80);
  
  // Code grows exponentially (implementation details explode)
  const codeSize = Math.max(40, (scale * scale) / 15 + 40);

  const isCodeBlowingHorizon = codeSize > tokenHorizon;

  return (
    <div ref={ref} className="my-10 rounded-2xl border border-white/[0.08] bg-[#0a0a0c] shadow-2xl glass-subtle overflow-hidden flex flex-col">
      {/* HEADER */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between p-5 border-b border-white/[0.05] bg-white/[0.01]">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="flex h-6 w-6 items-center justify-center rounded-md bg-amber-500/20 text-amber-400">
              <BrainCircuit className="h-3.5 w-3.5" />
            </span>
            <h4 className="text-sm font-semibold text-white/90">Interactive: The Context Horizon</h4>
          </div>
          <p className="text-xs text-white/50">Why reasoning in plan-space dominates reasoning in code-space as projects scale.</p>
        </div>

        {/* SLIDER CONTROL */}
        <div className="mt-4 sm:mt-0 flex flex-col gap-2 bg-[#020408] p-4 rounded-xl border border-white/[0.05] min-w-[200px] sm:min-w-[240px] shadow-inner">
          <div className="flex justify-between text-[0.65rem] font-bold uppercase tracking-widest text-white/40">
            <span>Prototype</span>
            <span>Production</span>
          </div>
          <div className="relative group/slider mt-1">
            <input
              type="range"
              min="0"
              max="100"
              value={scale}
              onChange={(e) => setScale(parseInt(e.target.value, 10))}
              className="w-full h-2 rounded-full appearance-none cursor-ew-resize [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:h-5 [&::-webkit-slider-thumb]:w-5 [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-[#FFBD2E] [&::-webkit-slider-thumb]:shadow-[0_0_15px_rgba(255,189,46,0.8)] [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-[#020408] [&::-webkit-slider-thumb]:transition-transform hover:[&::-webkit-slider-thumb]:scale-110 relative z-10"
              style={{
                background: `linear-gradient(to right, rgba(255,189,46,0.6) ${scale}%, rgba(255,255,255,0.05) ${scale}%)`
              }}
            />
          </div>
        </div>
      </div>

      {/* CANVAS */}
      <div className="relative w-full h-[450px] bg-[#020408] flex items-end justify-center gap-12 sm:gap-32 p-8 overflow-hidden">
        
        {/* Token Horizon Line */}
        <div className="absolute top-[120px] left-0 right-0 border-t-2 border-dashed border-[#FF5F56]/40 z-0">
          <div className="absolute right-4 -top-3.5 bg-[#020408] px-3 py-0.5 rounded-full border border-[#FF5F56]/20 text-[0.65rem] font-mono font-bold text-[#FF5F56] tracking-widest uppercase flex items-center gap-1.5 shadow-[0_0_10px_rgba(255,95,86,0.2)]">
            <AlertOctagon className="h-3 w-3" />
            Token Limit Horizon
          </div>
          <div className="absolute inset-0 h-[120px] bg-gradient-to-b from-[#FF5F56]/10 to-transparent pointer-events-none" />
        </div>

        {/* Grid Background */}
        <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.02)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.02)_1px,transparent_1px)] bg-[size:24px_24px] pointer-events-none" />

        {/* Plan Container */}
        <div className="relative flex flex-col items-center justify-end h-full z-10 w-28 sm:w-40">
          <motion.div
            className="w-full bg-gradient-to-t from-violet-500/10 to-violet-500/5 border-t border-l border-r border-violet-500/30 rounded-t-2xl relative overflow-hidden flex items-end justify-center pb-6 shadow-[0_0_40px_rgba(167,139,250,0.15)] backdrop-blur-sm"
            animate={isInView ? { height: planSize } : undefined}
            transition={rm ? { duration: 0 } : { type: "spring", stiffness: 150, damping: 20, mass: 0.8 }}
          >
            <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-violet-400 to-transparent opacity-50" />
            <ScrollText className="h-10 w-10 text-violet-400 relative z-10 opacity-90 drop-shadow-[0_0_10px_rgba(167,139,250,0.5)]" />
          </motion.div>
          <div className="mt-5 text-center">
            <div className="text-xs sm:text-sm font-black text-white tracking-widest uppercase">Plan Space</div>
            <div className="text-[0.65rem] sm:text-xs text-[#27C93F] font-mono mt-1.5 flex items-center justify-center gap-1.5 bg-[#27C93F]/10 rounded-full px-2 py-0.5 border border-[#27C93F]/20">
              <CheckCircle2 className="h-3 w-3" /> Context Safe
            </div>
          </div>
        </div>

        {/* Code Container */}
        <div className="relative flex flex-col items-center justify-end h-full z-10 w-28 sm:w-40">
          <motion.div 
            className={cn(
              "w-full rounded-t-2xl relative overflow-hidden flex items-end justify-center pb-6 transition-all duration-500 border-t border-l border-r backdrop-blur-sm",
              isCodeBlowingHorizon 
                ? "bg-gradient-to-t from-[#FF5F56]/10 to-[#FF5F56]/5 border-[#FF5F56]/40 shadow-[0_0_50px_rgba(255,95,86,0.25)]" 
                : "bg-gradient-to-t from-cyan-500/10 to-cyan-500/5 border-cyan-500/30 shadow-[0_0_40px_rgba(34,211,238,0.15)]"
            )}
            animate={isInView ? { height: codeSize } : undefined}
            transition={rm ? { duration: 0 } : { type: "spring", stiffness: 150, damping: 20, mass: 0.8 }}
          >
            <div className={cn(
              "absolute inset-x-0 top-0 h-px opacity-50 transition-colors duration-500",
              isCodeBlowingHorizon ? "bg-gradient-to-r from-transparent via-[#FF5F56] to-transparent" : "bg-gradient-to-r from-transparent via-cyan-400 to-transparent"
            )} />

            {/* Warning overlay when exceeding context */}
            <AnimatePresence>
              {isCodeBlowingHorizon && (
                <motion.div 
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="absolute inset-0 bg-[url('data:image/svg+xml;base64,PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnIHdpZHRoPSc4JyBoZWlnaHQ9JzgnPgo8cmVjdCB3aWR0aD0nOCcgaGVpZ2h0PSc4JyBmaWxsPScjZmZmJyBmaWxsLW9wYWNpdHk9JzAuMDInLz4KPHBhdGggZD0nTTAgMEw4IDhaTTAgOEw4IDBaJyBzdHJva2U9JyNlZjQ0NDQnIHN0cm9rZS13aWR0aD0nMC41JyBzdHJva2Utb3BhY2l0eT0nMC4zJy8+Cjwvc3ZnPg==')] pointer-events-none"
                />
              )}
            </AnimatePresence>
            
            <FileCode2 className={cn(
              "h-10 w-10 relative z-10 transition-all duration-500 opacity-90",
              isCodeBlowingHorizon ? "text-[#FF5F56] drop-shadow-[0_0_10px_rgba(255,95,86,0.5)]" : "text-cyan-400 drop-shadow-[0_0_10px_rgba(34,211,238,0.5)]"
            )} />
          </motion.div>
          
          <div className="mt-5 text-center">
            <div className="text-xs sm:text-sm font-black text-white tracking-widest uppercase">Code Space</div>
            <div className={cn(
              "text-[0.65rem] sm:text-xs font-mono mt-1.5 flex items-center justify-center gap-1.5 rounded-full px-2 py-0.5 border transition-colors duration-500",
              isCodeBlowingHorizon ? "text-[#FF5F56] bg-[#FF5F56]/10 border-[#FF5F56]/20" : "text-cyan-400 bg-cyan-400/10 border-cyan-400/20"
            )}>
              {isCodeBlowingHorizon ? (
                <><AlertOctagon className="h-3 w-3" /> Truncated</>
              ) : (
                <><CheckCircle2 className="h-3 w-3" /> In context</>
              )}
            </div>
          </div>
        </div>

      </div>
    </div>
  );
}
