"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ChevronUp, List } from "lucide-react";

const NAV_ITEMS = [
  { id: "why", label: "Why", number: "01" },
  { id: "terms", label: "Five Terms", number: "02" },
  { id: "core-loop", label: "Core Loop", number: "03" },
  { id: "three-tools", label: "Three Tools", number: "04" },
  { id: "artifact-ladder", label: "Artifacts", number: "05" },
  { id: "example", label: "Example", number: "06" },
  { id: "operating-rhythm", label: "Rhythm", number: "07" },
  { id: "operator", label: "Human's Job", number: "08" },
  { id: "failure-modes", label: "Failures", number: "09" },
  { id: "what-it-feels-like", label: "The Feeling", number: "10" },
  { id: "helpers", label: "Helpers", number: "11" },
  { id: "getting-started", label: "Start", number: "12" },
] as const;

export function QuickNav() {
  const [activeId, setActiveId] = useState("");
  const [visible, setVisible] = useState(false);
  const [progress, setProgress] = useState(0);
  const [mobileOpen, setMobileOpen] = useState(false);
  const ticking = useRef(false);

  useEffect(() => {
    const handleScroll = () => {
      if (ticking.current) return;
      ticking.current = true;
      requestAnimationFrame(() => {
        const scrollY = window.scrollY;
        setVisible(scrollY > 600);

        // Reading progress
        const docHeight = document.documentElement.scrollHeight - window.innerHeight;
        setProgress(docHeight > 0 ? Math.min(scrollY / docHeight, 1) : 0);

        ticking.current = false;
      });
    };

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setActiveId(entry.target.id);
          }
        }
      },
      { rootMargin: "-20% 0px -75% 0px" },
    );

    for (const item of NAV_ITEMS) {
      const el = document.getElementById(item.id);
      if (el) observer.observe(el);
    }

    window.addEventListener("scroll", handleScroll, { passive: true });
    handleScroll();

    return () => {
      observer.disconnect();
      window.removeEventListener("scroll", handleScroll);
    };
  }, []);

  const handleClick = useCallback((id: string) => {
    const el = document.getElementById(id);
    if (el) {
      el.scrollIntoView({ behavior: "smooth" });
      window.history.pushState(null, "", `#${id}`);
      setMobileOpen(false);
    }
  }, []);

  const activeIndex = NAV_ITEMS.findIndex((item) => item.id === activeId);
  const activeLabel = activeIndex >= 0 ? NAV_ITEMS[activeIndex].label : "";

  return (
    <>
      {/* ================================================================= */}
      {/* READING PROGRESS BAR — fixed top, always visible after hero       */}
      {/* ================================================================= */}
      <AnimatePresence>
        {visible && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed top-0 left-0 right-0 z-[60] h-[2px] pointer-events-none"
          >
            <motion.div
              className="h-full bg-gradient-to-r from-[#FF5500] to-[#FFBD2E]"
              style={{ width: `${progress * 100}%` }}
              transition={{ duration: 0.1, ease: "linear" }}
            />
          </motion.div>
        )}
      </AnimatePresence>

      {/* ================================================================= */}
      {/* DESKTOP SIDEBAR — xl+ only                                        */}
      {/* ================================================================= */}
      <AnimatePresence>
        {visible && (
          <motion.nav
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: 20 }}
            transition={{ duration: 0.3, ease: [0.16, 1, 0.3, 1] }}
            className="fixed right-6 top-1/2 -translate-y-1/2 z-50 hidden xl:flex flex-col gap-1"
            aria-label="Quick navigation"
          >
            <div className="rounded-2xl border border-white/[0.04] bg-[#020408]/80 backdrop-blur-xl p-2.5 shadow-2xl">
              {NAV_ITEMS.map((item) => {
                const isActive = activeId === item.id;
                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => handleClick(item.id)}
                    title={`${item.number}. ${item.label}`}
                    className="group relative flex items-center gap-2 px-2.5 py-1.5 rounded-lg transition-all duration-300 w-full text-left"
                  >
                    {isActive && (
                      <motion.div
                        layoutId="quicknav-active"
                        className="absolute inset-0 rounded-lg bg-[#FF5500]/10 border border-[#FF5500]/20"
                        transition={{ type: "spring", stiffness: 380, damping: 30 }}
                      />
                    )}
                    <div
                      className="relative z-10 w-1.5 h-1.5 rounded-full transition-all duration-300 shrink-0"
                      style={{
                        backgroundColor: isActive ? "#FF5500" : "rgba(255,255,255,0.15)",
                        boxShadow: isActive ? "0 0 8px rgba(255,85,0,0.6)" : "none",
                      }}
                    />
                    <span
                      className="relative z-10 text-[0.6rem] font-bold tracking-wide transition-colors duration-300 whitespace-nowrap"
                      style={{ color: isActive ? "#FF5500" : "rgba(255,255,255,0.25)" }}
                    >
                      {item.label}
                    </span>
                  </button>
                );
              })}
            </div>
          </motion.nav>
        )}
      </AnimatePresence>

      {/* ================================================================= */}
      {/* MOBILE BOTTOM BAR — below xl only                                 */}
      {/* ================================================================= */}
      <AnimatePresence>
        {visible && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 20 }}
            transition={{ duration: 0.3, ease: [0.16, 1, 0.3, 1] }}
            className="fixed bottom-0 left-0 right-0 z-50 xl:hidden"
          >
            {/* Expanded TOC drawer */}
            <AnimatePresence>
              {mobileOpen && (
                <motion.div
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: 20 }}
                  transition={{ duration: 0.25, ease: [0.16, 1, 0.3, 1] }}
                  className="mx-4 mb-2 rounded-2xl border border-white/[0.06] bg-[#020408]/95 backdrop-blur-xl p-4 shadow-2xl max-h-[60vh] overflow-y-auto"
                >
                  <div className="grid grid-cols-3 sm:grid-cols-4 gap-2">
                    {NAV_ITEMS.map((item) => {
                      const isActive = activeId === item.id;
                      return (
                        <button
                          key={item.id}
                          type="button"
                          onClick={() => handleClick(item.id)}
                          className={`px-3 py-2.5 rounded-xl text-[0.65rem] font-bold tracking-wide transition-all duration-300 text-left ${
                            isActive
                              ? "bg-[#FF5500]/10 text-[#FF5500] border border-[#FF5500]/20"
                              : "text-white/40 hover:text-white/60 border border-transparent hover:bg-white/[0.03]"
                          }`}
                        >
                          <span className="block text-[0.55rem] font-mono opacity-50 mb-0.5">{item.number}</span>
                          {item.label}
                        </button>
                      );
                    })}
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            {/* Bottom bar */}
            <div className="flex items-center gap-3 px-4 py-3 bg-[#020408]/95 backdrop-blur-xl border-t border-white/[0.06] safe-bottom">
              {/* Section indicator */}
              <button
                type="button"
                onClick={() => setMobileOpen((prev) => !prev)}
                className="flex items-center gap-2.5 flex-1 min-w-0"
              >
                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-[#FF5500]/10 border border-[#FF5500]/20">
                  {mobileOpen ? (
                    <ChevronUp className="h-3.5 w-3.5 text-[#FF5500]" />
                  ) : (
                    <List className="h-3.5 w-3.5 text-[#FF5500]" />
                  )}
                </div>
                <div className="flex flex-col min-w-0">
                  <span className="text-[0.55rem] font-bold uppercase tracking-widest text-white/30">
                    Section {activeIndex >= 0 ? activeIndex + 1 : "–"} of {NAV_ITEMS.length}
                  </span>
                  <span className="text-xs font-bold text-white truncate">
                    {activeLabel || "Core Flywheel"}
                  </span>
                </div>
              </button>

              {/* Mini progress dots */}
              <div className="flex items-center gap-1 shrink-0">
                {NAV_ITEMS.map((item, i) => (
                  <div
                    key={item.id}
                    className="w-1.5 h-1.5 rounded-full transition-all duration-300"
                    style={{
                      backgroundColor: i === activeIndex
                        ? "#FF5500"
                        : i < activeIndex
                          ? "rgba(255,85,0,0.3)"
                          : "rgba(255,255,255,0.1)",
                    }}
                  />
                ))}
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}
