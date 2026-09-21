"use client";

import { motion, springs } from "@/components/motion";
import { cn } from "@/lib/utils";

interface SectionHeaderProps {
  /** Small uppercase label above the heading */
  label?: string;
  /** Main heading text */
  heading: string;
  /** Description text below the heading */
  description?: React.ReactNode;
  /** Center align (default) or left align */
  align?: "center" | "left";
  /** Heading size */
  size?: "default" | "large";
  /** Additional class names */
  className?: string;
  /** Whether to animate (requires parent to control isInView) */
  animate?: boolean;
  /** For controlled animation */
  isInView?: boolean;
}

/**
 * SectionHeader - Premium section header with optional label, heading, and description.
 *
 * Follows the landing page pattern with:
 * - Gradient divider lines flanking the label
 * - Uppercase tracking label in primary color
 * - Mono font bold heading
 * - Muted description with constrained width
 */
export function SectionHeader({
  label,
  heading,
  description,
  align = "center",
  size = "default",
  className,
  animate = false,
  isInView = true,
}: SectionHeaderProps) {
  const content = (
    <div className={cn("mb-12", align === "center" && "text-center", className)}>
      {/* Label with gradient dividers */}
      {label && (
        <div className={cn("mb-4 flex items-center gap-3", align === "center" && "justify-center")}>
          <div className="h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
          <span className="text-xs font-bold uppercase tracking-[0.25em] text-primary">
            {label}
          </span>
          <div className="h-px w-8 bg-gradient-to-l from-transparent via-primary/50 to-transparent" />
        </div>
      )}

      {/* Heading */}
      <h2
        className={cn(
          "mb-4 font-mono font-bold tracking-tight",
          size === "default" && "text-3xl",
          size === "large" && "text-3xl sm:text-4xl",
        )}
      >
        {heading}
      </h2>

      {/* Description */}
      {description && (
        <p className={cn("text-muted-foreground", align === "center" && "mx-auto max-w-2xl")}>
          {description}
        </p>
      )}
    </div>
  );

  if (animate) {
    return (
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 20 }}
        transition={springs.smooth}
      >
        {content}
      </motion.div>
    );
  }

  return content;
}
