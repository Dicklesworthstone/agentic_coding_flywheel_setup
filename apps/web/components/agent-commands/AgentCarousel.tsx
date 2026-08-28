"use client";

import { useState, useRef, useEffect } from "react";
import { useDrag } from "@use-gesture/react";
import { motion, springs, AnimatePresence } from "@/components/motion";
import { cn } from "@/lib/utils";
import type { AgentInfo } from "./AgentHeroCard";
import { agentPersonalities } from "./AgentHeroCard";

interface AgentCarouselProps {
  agents: AgentInfo[];
  currentIndex: number;
  onIndexChange: (index: number) => void;
  children: (agent: AgentInfo, index: number) => React.ReactNode;
}

export function AgentCarousel({
  agents,
  currentIndex,
  onIndexChange,
  children,
}: AgentCarouselProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [containerWidth, setContainerWidth] = useState(0);
  const [isDragging, setIsDragging] = useState(false);

  // Measure container width
  useEffect(() => {
    const measure = () => {
      if (containerRef.current) {
        setContainerWidth(containerRef.current.offsetWidth);
      }
    };
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, []);

  // Swipe gesture handler
  const bind = useDrag(
    ({ active, movement: [mx], velocity: [vx] }) => {
      setIsDragging(active);

      if (!active) {
        // Determine if we should change slides
        const threshold = containerWidth * 0.2;
        const velocityThreshold = 0.5;
        const swipedFarEnough = Math.abs(mx) > threshold;
        const swipedFastEnough = Math.abs(vx) > velocityThreshold;

        if (swipedFarEnough || swipedFastEnough) {
          // Positive mx = swiped right = go to previous
          if (mx > 0 && currentIndex > 0) {
            onIndexChange(currentIndex - 1);
          // Negative mx = swiped left = go to next
          } else if (mx < 0 && currentIndex < agents.length - 1) {
            onIndexChange(currentIndex + 1);
          }
        }
      }
    },
    {
      axis: "x",
      filterTaps: true,
      rubberband: true,
    }
  );

  // Keyboard navigation
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Ignore when input is focused (prevents conflict with search input cursor navigation)
      if (
        document.activeElement?.tagName === "INPUT" ||
        document.activeElement?.tagName === "TEXTAREA"
      ) {
        return;
      }

      if (e.key === "ArrowLeft" && currentIndex > 0) {
        onIndexChange(currentIndex - 1);
      } else if (e.key === "ArrowRight" && currentIndex < agents.length - 1) {
        onIndexChange(currentIndex + 1);
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [currentIndex, agents.length, onIndexChange]);

  return (
    <div className="relative">
      {/* Carousel container */}
      <div
        ref={containerRef}
        className="overflow-hidden"
        {...bind()}
        style={{ touchAction: "pan-y" }}
      >
        <motion.div
          className="flex"
          animate={{
            x: -currentIndex * containerWidth,
          }}
          transition={isDragging ? { type: "tween", duration: 0 } : springs.smooth}
        >
          {agents.map((agent, index) => (
            <div
              key={agent.id}
              className="w-full flex-shrink-0 px-1"
              style={{ width: containerWidth || "100%" }}
            >
              {children(agent, index)}
            </div>
          ))}
        </motion.div>
      </div>

      {/* Dot indicators */}
      <div className="mt-6 flex items-center justify-center gap-2">
        {agents.map((agent, index) => {
          const personality = agentPersonalities[agent.id];
          const isActive = index === currentIndex;

          return (
            <button
              key={agent.id}
              type="button"
              onClick={() => onIndexChange(index)}
              aria-label={`Go to ${agent.name}`}
              className={cn(
                "relative h-2.5 rounded-full transition-[width] duration-300",
                "min-w-[44px] min-h-[44px] flex items-center justify-center", // Touch target
                isActive ? "w-8" : "w-2.5"
              )}
            >
              <motion.div
                className={cn(
                  "h-2.5 rounded-full",
                  isActive ? "w-8" : "w-2.5"
                )}
                style={{
                  backgroundColor: isActive
                    ? personality.glowColor
                    : "oklch(0.5 0 0 / 0.3)",
                }}
                layoutId={`dot-${agent.id}`}
                transition={springs.snappy}
              />
              {isActive && (
                <motion.div
                  className="absolute inset-0 -z-10 rounded-full opacity-30 blur-md"
                  style={{ backgroundColor: personality.glowColor }}
                  initial={{ scale: 0.8, opacity: 0 }}
                  animate={{ scale: 1.5, opacity: 0.3 }}
                  transition={springs.smooth}
                />
              )}
            </button>
          );
        })}
      </div>

      {/* Agent name indicator */}
      <AnimatePresence mode="wait">
        <motion.div
          key={currentIndex}
          className="mt-3 text-center"
          initial={{ opacity: 0, y: 5 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -5 }}
          transition={springs.snappy}
        >
          <span className="text-sm font-medium text-muted-foreground">
            {agents[currentIndex]?.name}
          </span>
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
