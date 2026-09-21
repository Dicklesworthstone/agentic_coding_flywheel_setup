"use client";

import { motion, springs } from "@/components/motion";
import { useScrollReveal } from "@/lib/hooks/useScrollReveal";
import { cn } from "@/lib/utils";

interface SectionContainerProps {
  children: React.ReactNode;
  className?: string;
  /** Add top border separator */
  withBorder?: boolean;
  /** Subtle background tint */
  withBackground?: boolean;
  /** Include floating orb decorations */
  withOrbs?: boolean;
  /** Which orbs to show */
  orbVariant?: "default" | "success" | "centered";
  /** Max width variant */
  maxWidth?: "default" | "narrow" | "wide";
  /** Animate on scroll */
  animate?: boolean;
  /** Section ID for navigation */
  id?: string;
}

/**
 * SectionContainer - Consistent section wrapper with padding, max-width, and optional effects.
 *
 * Provides consistent spacing and optional decorative elements like:
 * - Top border separator
 * - Background tint
 * - Floating gradient orbs
 * - Scroll-triggered fade-in animation
 */
export function SectionContainer({
  children,
  className,
  withBorder = false,
  withBackground = false,
  withOrbs = false,
  orbVariant = "default",
  maxWidth = "default",
  animate = true,
  id,
}: SectionContainerProps) {
  const { ref, isInView } = useScrollReveal({ threshold: 0.1 });

  const maxWidthClasses = {
    default: "max-w-7xl",
    narrow: "max-w-4xl",
    wide: "max-w-[90rem]",
  };

  const orbClasses = {
    default: (
      <>
        <div className="pointer-events-none absolute -left-40 top-1/4 h-80 w-80 rounded-full bg-[oklch(0.75_0.18_195/0.08)] blur-[100px]" />
        <div className="pointer-events-none absolute -right-40 bottom-1/4 h-80 w-80 rounded-full bg-[oklch(0.7_0.2_330/0.08)] blur-[100px]" />
      </>
    ),
    success: (
      <>
        <div className="pointer-events-none absolute -left-40 top-1/2 h-80 w-80 -translate-y-1/2 rounded-full bg-[oklch(0.72_0.19_145/0.08)] blur-[100px]" />
        <div className="pointer-events-none absolute -right-40 top-1/2 h-80 w-80 -translate-y-1/2 rounded-full bg-[oklch(0.65_0.22_25/0.08)] blur-[100px]" />
      </>
    ),
    centered: (
      <>
        <div className="pointer-events-none absolute left-1/2 top-1/2 h-96 w-96 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[oklch(0.75_0.18_195/0.06)] blur-[120px]" />
      </>
    ),
  };

  const content = (
    <div className={cn("mx-auto px-6 relative", maxWidthClasses[maxWidth])}>{children}</div>
  );

  return (
    <section
      ref={ref as React.RefObject<HTMLElement>}
      id={id}
      className={cn(
        "py-24 relative overflow-hidden",
        withBorder && "border-t border-border/30",
        withBackground && "bg-card/20",
        className,
      )}
    >
      {withOrbs && orbClasses[orbVariant]}

      {animate ? (
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
          transition={springs.smooth}
        >
          {content}
        </motion.div>
      ) : (
        content
      )}
    </section>
  );
}
