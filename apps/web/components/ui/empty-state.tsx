"use client";

import { cn } from "@/lib/utils";
import { motion, springs } from "@/components/motion";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";
import type { LucideIcon } from "lucide-react";

interface EmptyStateProps {
  /** Icon to display */
  icon: LucideIcon;
  /** Main title */
  title: string;
  /** Description text */
  description: string;
  /** Optional action button/element */
  action?: React.ReactNode;
  /** Variant for different contexts */
  variant?: "default" | "compact" | "inline";
  /** Additional className */
  className?: string;
}

/**
 * EmptyState - A premium empty state component for when there's no content.
 *
 * Used for:
 * - Zero search results
 * - Empty lists/grids
 * - No data states
 * - First-time user experience
 */
export function EmptyState({
  icon: Icon,
  title,
  description,
  action,
  variant = "default",
  className,
}: EmptyStateProps) {
  const prefersReducedMotion = useReducedMotion();
  const reducedMotion = prefersReducedMotion ?? false;

  const variantStyles = {
    default: "py-16",
    compact: "py-10",
    inline: "py-6",
  };

  const iconSizes = {
    default: "h-16 w-16",
    compact: "h-12 w-12",
    inline: "h-10 w-10",
  };

  const iconContainerSizes = {
    default: "h-20 w-20",
    compact: "h-16 w-16",
    inline: "h-12 w-12",
  };

  return (
    <motion.div
      className={cn(
        "flex flex-col items-center justify-center text-center",
        variantStyles[variant],
        className
      )}
      initial={reducedMotion ? {} : { opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={reducedMotion ? { duration: 0 } : springs.smooth}
    >
      {/* Icon container with subtle gradient background */}
      <motion.div
        className={cn(
          "mb-4 flex items-center justify-center rounded-2xl",
          "bg-gradient-to-br from-muted/80 to-muted/40",
          "shadow-inner",
          iconContainerSizes[variant]
        )}
        initial={reducedMotion ? {} : { scale: 0.9 }}
        animate={{ scale: 1 }}
        transition={reducedMotion ? { duration: 0 } : { ...springs.snappy, delay: 0.1 }}
      >
        <Icon
          className={cn(
            "text-muted-foreground/60",
            iconSizes[variant]
          )}
          strokeWidth={1.5}
        />
      </motion.div>

      {/* Title */}
      <motion.h3
        className={cn(
          "font-semibold text-foreground",
          variant === "default" && "text-lg",
          variant === "compact" && "text-base",
          variant === "inline" && "text-sm"
        )}
        initial={reducedMotion ? {} : { opacity: 0, y: 5 }}
        animate={{ opacity: 1, y: 0 }}
        transition={reducedMotion ? { duration: 0 } : { ...springs.smooth, delay: 0.15 }}
      >
        {title}
      </motion.h3>

      {/* Description */}
      <motion.p
        className={cn(
          "mt-2 max-w-sm text-muted-foreground",
          variant === "default" && "text-sm",
          variant === "compact" && "text-sm",
          variant === "inline" && "text-xs"
        )}
        initial={reducedMotion ? {} : { opacity: 0, y: 5 }}
        animate={{ opacity: 1, y: 0 }}
        transition={reducedMotion ? { duration: 0 } : { ...springs.smooth, delay: 0.2 }}
      >
        {description}
      </motion.p>

      {/* Action */}
      {action && (
        <motion.div
          className="mt-6"
          initial={reducedMotion ? {} : { opacity: 0, y: 5 }}
          animate={{ opacity: 1, y: 0 }}
          transition={reducedMotion ? { duration: 0 } : { ...springs.smooth, delay: 0.25 }}
        >
          {action}
        </motion.div>
      )}
    </motion.div>
  );
}
