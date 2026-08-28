"use client";

import { useRef, useState, useEffect } from "react";
import { motion, useReducedMotion, useInView, AnimatePresence } from "@/components/motion";
import { Cog, Zap, GitBranch, ArrowDown, Sparkles } from "lucide-react";
import { cn } from "@/lib/utils";
import { tldrPageData } from "@/lib/tldr-content";

// =============================================================================
// TYPES
// =============================================================================

interface TldrHeroProps {
  className?: string;
  id?: string;
}

// =============================================================================
// ANIMATED STAT COMPONENT - Enhanced with glassmorphism
// =============================================================================

function AnimatedStat({
  label,
  value,
  index,
  reducedMotion,
  isInView,
}: {
  label: string;
  value: string;
  index: number;
  reducedMotion: boolean;
  isInView: boolean;
}) {
  return (
    <motion.div
      initial={reducedMotion ? {} : { opacity: 0, y: 20, scale: 0.9 }}
      animate={isInView ? { opacity: 1, y: 0, scale: 1 } : {}}
      transition={{
        duration: reducedMotion ? 0 : 0.5,
        delay: reducedMotion ? 0 : 0.3 + index * 0.1,
        type: "spring",
        stiffness: 100,
      }}
      className="group relative text-center"
    >
      {/* Glassmorphism card */}
      <div className="relative rounded-2xl border border-white/10 bg-white/5 px-4 py-3 backdrop-blur-sm transition duration-300 hover:border-white/20 hover:bg-white/10 sm:px-6 sm:py-4">
        {/* Subtle glow on hover */}
        <div className="pointer-events-none absolute -inset-px rounded-2xl bg-gradient-to-b from-primary/20 to-transparent opacity-0 transition-opacity duration-300 group-hover:opacity-100" />

        {/* Value with gradient */}
        <div className="relative text-2xl font-bold sm:text-3xl md:text-4xl">
          <span className="bg-gradient-to-r from-white via-white to-white/80 bg-clip-text text-transparent">
            {value}
          </span>
        </div>

        {/* Label */}
        <div className="relative mt-1 text-xs font-medium uppercase tracking-wider text-muted-foreground">
          {label}
        </div>
      </div>
    </motion.div>
  );
}

// =============================================================================
// FLOATING ICON COMPONENT - Enhanced with depth and glow
// =============================================================================

function FloatingIcon({
  icon: Icon,
  className,
  delay = 0,
  reducedMotion,
  floatDirection = "up",
}: {
  icon: React.ComponentType<{ className?: string }>;
  className?: string;
  delay?: number;
  reducedMotion: boolean;
  floatDirection?: "up" | "down" | "left" | "right";
}) {
  const floatAnimations = {
    up: { y: [0, -10, 0] },
    down: { y: [0, 10, 0] },
    left: { x: [0, -10, 0] },
    right: { x: [0, 10, 0] },
  };

  return (
    <motion.div
      initial={reducedMotion ? {} : { opacity: 0, scale: 0.5 }}
      animate={{
        opacity: 1,
        scale: 1,
        ...(reducedMotion ? {} : floatAnimations[floatDirection]),
      }}
      transition={{
        opacity: { duration: reducedMotion ? 0 : 0.6, delay: reducedMotion ? 0 : delay },
        scale: { duration: reducedMotion ? 0 : 0.6, delay: reducedMotion ? 0 : delay },
        y: { duration: 4, repeat: Infinity, ease: "easeInOut" },
        x: { duration: 4, repeat: Infinity, ease: "easeInOut" },
      }}
      className={cn(
        "absolute flex items-center justify-center rounded-2xl bg-gradient-to-br p-3 shadow-2xl",
        "ring-1 ring-white/10",
        className
      )}
      style={{
        boxShadow: "0 20px 50px -12px rgba(0, 0, 0, 0.5), inset 0 1px 1px rgba(255, 255, 255, 0.1)",
      }}
    >
      <Icon className="h-6 w-6 text-white drop-shadow-lg" />
      {/* Inner glow */}
      <div className="pointer-events-none absolute inset-0 rounded-2xl bg-gradient-to-t from-transparent to-white/20" />
    </motion.div>
  );
}

// =============================================================================
// GRADIENT TEXT SHIMMER EFFECT
// =============================================================================

function ShimmerText({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <span className={cn("relative inline-block", className)}>
      <span className="bg-gradient-to-r from-primary via-primary/80 to-accent bg-clip-text text-transparent">
        {children}
      </span>
      {/* Shimmer overlay */}
      <span
        className="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 to-transparent bg-clip-text text-transparent animate-shimmer"
        style={{
          backgroundSize: "200% 100%",
          animation: "shimmer 3s linear infinite",
        }}
        aria-hidden="true"
      >
        {children}
      </span>
    </span>
  );
}

// =============================================================================
// ANIMATED SCROLL INDICATOR
// =============================================================================

function ScrollIndicator({ reducedMotion }: { reducedMotion: boolean }) {
  return (
    <motion.div
      initial={reducedMotion ? {} : { opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={reducedMotion ? {} : { opacity: 0, y: 20 }}
      transition={{ duration: reducedMotion ? 0 : 0.5, delay: reducedMotion ? 0 : 0.6 }}
      className="mt-16 flex justify-center"
    >
      <motion.div
        animate={reducedMotion ? {} : { y: [0, 8, 0] }}
        transition={{
          duration: 2,
          repeat: Infinity,
          ease: "easeInOut",
        }}
        className="group flex cursor-pointer flex-col items-center gap-2 text-muted-foreground transition-colors hover:text-white"
        onClick={() => {
          window.scrollTo({ top: window.innerHeight * 0.8, behavior: "smooth" });
        }}
      >
        <span className="text-xs font-medium uppercase tracking-wider">
          Scroll to explore
        </span>
        {/* Animated arrow container */}
        <div className="relative flex h-10 w-6 items-center justify-center rounded-full border border-white/20 bg-white/5 backdrop-blur-sm transition-colors group-hover:border-white/40 group-hover:bg-white/10">
          <motion.div
            animate={reducedMotion ? {} : { y: [0, 4, 0] }}
            transition={{
              duration: 1.5,
              repeat: Infinity,
              ease: "easeInOut",
            }}
          >
            <ArrowDown className="h-4 w-4" />
          </motion.div>
        </div>
      </motion.div>
    </motion.div>
  );
}

// =============================================================================
// MAIN COMPONENT
// =============================================================================

export function TldrHero({ className, id }: TldrHeroProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const isInView = useInView(containerRef, { once: true, margin: "-100px" });
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;
  const [hasScrolled, setHasScrolled] = useState(false);

  // Hide scroll indicator after user scrolls
  useEffect(() => {
    const handleScroll = () => {
      if (window.scrollY > 50) {
        setHasScrolled(true);
      }
    };

    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  const { hero } = tldrPageData;

  return (
    <section
      id={id}
      ref={containerRef}
      className={cn("relative overflow-hidden py-16 md:py-32", className)}
    >
      {/* CSS for shimmer animation */}
      <style jsx global>{`
        @keyframes shimmer {
          0% { background-position: 200% 0; }
          100% { background-position: -200% 0; }
        }
        .animate-shimmer {
          animation: shimmer 3s linear infinite;
        }
      `}</style>

      {/* Background layers */}
      <div className="pointer-events-none absolute inset-0">
        {/* Primary gradient */}
        <div className="absolute inset-0 bg-gradient-to-b from-primary/10 via-transparent to-transparent" />

        {/* Radial glow from center */}
        <div className="absolute left-1/2 top-1/4 h-[500px] w-[800px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-primary/10 blur-[120px]" />

        {/* Secondary accent glow */}
        <div className="absolute right-1/4 top-1/3 h-[300px] w-[400px] rounded-full bg-accent/5 blur-[100px]" />
      </div>

      {/* Decorative grid - subtle dot pattern */}
      <div
        className="pointer-events-none absolute inset-0 hidden sm:block"
        style={{
          backgroundImage: `radial-gradient(circle, rgba(255,255,255,0.03) 1px, transparent 1px)`,
          backgroundSize: "32px 32px",
        }}
      />

      {/* Floating icons - enhanced positioning and effects */}
      <div className="pointer-events-none absolute inset-0 hidden md:block" aria-hidden="true">
        <FloatingIcon
          icon={Cog}
          className="left-[10%] top-[20%] from-primary to-primary/60"
          delay={0.8}
          reducedMotion={reducedMotion}
          floatDirection="up"
        />
        <FloatingIcon
          icon={Zap}
          className="right-[15%] top-[25%] from-accent to-accent/60"
          delay={1.0}
          reducedMotion={reducedMotion}
          floatDirection="down"
        />
        <FloatingIcon
          icon={GitBranch}
          className="bottom-[30%] left-[12%] from-success to-success/60"
          delay={1.2}
          reducedMotion={reducedMotion}
          floatDirection="right"
        />
        <FloatingIcon
          icon={Sparkles}
          className="bottom-[35%] right-[10%] from-violet-500 to-purple-600"
          delay={1.4}
          reducedMotion={reducedMotion}
          floatDirection="left"
        />
      </div>

      <div className="container relative mx-auto px-4">
        <div className="mx-auto max-w-3xl text-center">
          {/* Badge - enhanced with glow */}
          <motion.div
            initial={reducedMotion ? {} : { opacity: 0, y: -10, scale: 0.9 }}
            animate={isInView ? { opacity: 1, y: 0, scale: 1 } : {}}
            transition={{ duration: reducedMotion ? 0 : 0.4, type: "spring" }}
            className="inline-flex items-center gap-2 rounded-full bg-primary/10 px-4 py-1.5 text-sm font-medium text-primary ring-1 ring-inset ring-primary/20 backdrop-blur-sm"
            style={{
              boxShadow: "0 0 30px -5px rgba(var(--primary-rgb, 139, 92, 246), 0.3)",
            }}
          >
            <Cog className="h-4 w-4" />
            <span>Open Source Ecosystem</span>
          </motion.div>

          {/* Title - enhanced typography */}
          <motion.h1
            initial={reducedMotion ? {} : { opacity: 0, y: 20 }}
            animate={isInView ? { opacity: 1, y: 0 } : {}}
            transition={{ duration: reducedMotion ? 0 : 0.5, delay: reducedMotion ? 0 : 0.1 }}
            className="mt-6 text-3xl font-bold tracking-tight text-white sm:text-4xl md:text-6xl"
          >
            {hero.title}
            <ShimmerText className="block">
              {hero.subtitle}
            </ShimmerText>
          </motion.h1>

          {/* Description - enhanced readability */}
          <motion.p
            initial={reducedMotion ? {} : { opacity: 0, y: 20 }}
            animate={isInView ? { opacity: 1, y: 0 } : {}}
            transition={{ duration: reducedMotion ? 0 : 0.5, delay: reducedMotion ? 0 : 0.2 }}
            className="mt-4 text-base leading-relaxed text-muted-foreground/90 sm:mt-6 sm:text-lg md:text-xl"
          >
            {hero.description}
          </motion.p>

          {/* Stats - enhanced with glassmorphism cards */}
          <motion.div
            initial={reducedMotion ? {} : { opacity: 0 }}
            animate={isInView ? { opacity: 1 } : {}}
            transition={{ duration: reducedMotion ? 0 : 0.5, delay: reducedMotion ? 0 : 0.3 }}
            className="mt-8 flex flex-wrap items-center justify-center gap-3 sm:mt-12 sm:gap-4 md:gap-6"
          >
            {hero.stats.map((stat, i) => (
              <AnimatedStat
                key={stat.label}
                label={stat.label}
                value={stat.value}
                index={i}
                reducedMotion={reducedMotion}
                isInView={isInView}
              />
            ))}
          </motion.div>

          {/* Scroll indicator - enhanced design */}
          <AnimatePresence>
            {!hasScrolled && (
              <ScrollIndicator reducedMotion={reducedMotion} />
            )}
          </AnimatePresence>
        </div>
      </div>
    </section>
  );
}

export default TldrHero;
