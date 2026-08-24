"use client";

import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "@/components/motion";
import { List, X } from "lucide-react";

export function FloatingHUD({
  items,
}: {
  items: { id: string; label: string; number: string }[];
}) {
  const [activeId, setActiveId] = useState<string>("");
  const [isOpen, setIsOpen] = useState(false);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const handleScroll = () => {
      const totalHeight = document.documentElement.scrollHeight - window.innerHeight;
      setProgress(Math.min(100, Math.max(0, (window.scrollY / totalHeight) * 100)));
    };

    window.addEventListener("scroll", handleScroll);
    handleScroll();
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            setActiveId(entry.target.id);
          }
        });
      },
      { rootMargin: "-15% 0px -80% 0px" }
    );

    items.forEach((item) => {
      const el = document.getElementById(item.id);
      if (el) observer.observe(el);
    });

    return () => observer.disconnect();
  }, [items]);

  const activeItem = items.find((item) => item.id === activeId) || items[0];

  const handleClick = (e: React.MouseEvent<HTMLAnchorElement>, id: string) => {
    e.preventDefault();
    const el = document.getElementById(id);
    if (el) {
      el.scrollIntoView({ behavior: "smooth" });
      window.history.pushState(null, "", `#${id}`);
      setIsOpen(false);
    }
  };

  return (
    <>
      <div className="fixed bottom-8 left-1/2 -translate-x-1/2 z-[100] flex items-center gap-4">
        <button
          onClick={() => setIsOpen(!isOpen)}
          className="group relative flex items-center gap-4 rounded-full bg-black/80 backdrop-blur-xl border border-white/10 px-6 py-3 shadow-[0_20px_40px_rgba(0,0,0,0.8),inset_0_1px_1px_rgba(255,255,255,0.05)] hover:border-[#FF5500]/50 transition-all duration-500"
        >
          <div className="absolute inset-0 rounded-full bg-gradient-to-r from-transparent via-[#FF5500]/10 to-transparent opacity-0 group-hover:opacity-100 transition-opacity" />
          
          <div className="relative w-5 h-5">
            <svg className="w-full h-full -rotate-90 transform" viewBox="0 0 24 24">
              <circle
                className="text-white/10"
                strokeWidth="2"
                stroke="currentColor"
                fill="transparent"
                r="10"
                cx="12"
                cy="12"
              />
              <circle
                className="text-[#FF5500] transition-all duration-150 ease-out"
                strokeWidth="2"
                strokeDasharray={62.8}
                strokeDashoffset={62.8 - (62.8 * progress) / 100}
                strokeLinecap="round"
                stroke="currentColor"
                fill="transparent"
                r="10"
                cx="12"
                cy="12"
              />
            </svg>
            <List className="absolute inset-0 m-auto h-2.5 w-2.5 text-white" />
          </div>

          <div className="flex flex-col items-start text-left">
            <span className="text-[0.55rem] font-bold uppercase tracking-[0.2em] text-white/40">
              Section {activeItem?.number?.padStart(2, '0')}
            </span>
            <span className="text-[0.8rem] font-bold text-white tracking-tight">
              {activeItem?.label || "Introduction"}
            </span>
          </div>
        </button>
      </div>

      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ opacity: 0, y: 20, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 20, scale: 0.95 }}
            transition={{ type: "spring", stiffness: 300, damping: 30 }}
            className="fixed bottom-24 left-1/2 -translate-x-1/2 w-[90vw] max-w-[400px] z-[90] rounded-3xl bg-[#05070A]/95 backdrop-blur-2xl border border-white/10 shadow-[0_40px_80px_rgba(0,0,0,0.9)] p-6 overflow-hidden flex flex-col max-h-[60vh]"
          >
            <div className="flex items-center justify-between mb-6 pb-4 border-b border-white/5 shrink-0">
              <span className="text-[0.65rem] font-bold uppercase tracking-widest text-[#FF5500]">Table of Contents</span>
              <button onClick={() => setIsOpen(false)} className="text-white/40 hover:text-white transition-colors">
                <X className="h-5 w-5" />
              </button>
            </div>
            
            <div className="overflow-y-auto scrollbar-hide flex-1 px-2 -mx-2">
              <ul className="space-y-1">
                {items.map((item) => {
                  const isActive = activeId === item.id;
                  return (
                    <li key={item.id}>
                      <a
                        href={`#${item.id}`}
                        onClick={(e) => handleClick(e, item.id)}
                        className={`group flex items-center gap-4 py-2.5 px-3 rounded-lg transition-colors ${
                          isActive
                            ? "bg-[#FF5500]/10 text-white"
                            : "text-zinc-400 hover:bg-white/[0.03] hover:text-zinc-200"
                        }`}
                      >
                        <span className={`font-mono text-[0.65rem] ${isActive ? "text-[#FF5500] font-bold" : "text-white/30"}`}>
                          {item.number.padStart(2, '0')}
                        </span>
                        <span className="text-sm font-medium tracking-tight truncate">{item.label}</span>
                      </a>
                    </li>
                  );
                })}
              </ul>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}