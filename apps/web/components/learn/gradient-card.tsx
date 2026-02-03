"use client";

import { cn } from "@/lib/utils";
import { motion } from "@/components/motion";
import { springs, fadeUp } from "@/components/motion";
import { staggerDelay } from "@/lib/hooks/useScrollReveal";
import type { LucideIcon } from "lucide-react";

type GradientVariant = "cyan" | "pink" | "success" | "warning" | "error" | "purple" | "sky" | "violet" | "rose" | "emerald" | "amber";

interface GradientCardProps {
  children: React.ReactNode;
  className?: string;
  /** Gradient color for hover glow */
  variant?: GradientVariant;
  /** Stagger animation index */
  index?: number;
  /** Enable hover lift animation */
  hoverable?: boolean;
  /** Click handler */
  onClick?: () => void;
}

interface FeatureCardProps {
  icon: React.ReactNode;
  title: string;
  description: React.ReactNode;
  /** Gradient variant for the glow effect */
  variant?: GradientVariant;
  /** Stagger animation index */
  index?: number;
  /** Additional class names */
  className?: string;
}

interface IconCardProps {
  icon: LucideIcon;
  title: string;
  description: string;
  detail?: string;
  /** Tailwind gradient classes (e.g., "from-sky-400 to-blue-500") */
  gradient: string;
  /** Stagger animation index */
  index?: number;
  /** Additional class names */
  className?: string;
}

/**
 * Gradient color map for glow effects
 */
const gradientGlowColors: Record<GradientVariant, string> = {
  cyan: "bg-[oklch(0.75_0.18_195)]",
  pink: "bg-[oklch(0.7_0.2_330)]",
  success: "bg-[oklch(0.72_0.19_145)]",
  warning: "bg-[oklch(0.78_0.16_75)]",
  error: "bg-[oklch(0.65_0.22_25)]",
  purple: "bg-[oklch(0.65_0.18_290)]",
  sky: "bg-gradient-to-br from-sky-400 to-blue-500",
  violet: "bg-gradient-to-br from-violet-400 to-purple-500",
  rose: "bg-gradient-to-br from-rose-400 to-red-500",
  emerald: "bg-gradient-to-br from-emerald-400 to-teal-500",
  amber: "bg-gradient-to-br from-amber-400 to-orange-500",
};

/**
 * GradientCard - Base card with hover glow effect.
 *
 * A premium card component with:
 * - Glass-morphism background
 * - Gradient glow on hover
 * - Lift animation on hover
 * - Optional stagger animation for lists
 */
export function GradientCard({
  children,
  className,
  variant = "cyan",
  index = 0,
  hoverable = true,
  onClick,
}: GradientCardProps) {
  return (
    <motion.div
      className={cn(
        "group relative overflow-hidden rounded-2xl border border-border/50 bg-card/50 p-6 backdrop-blur-sm",
        // Layered shadows for depth - Stripe-style elevation
        "shadow-[0_2px_4px_rgba(0,0,0,0.08),0_4px_12px_rgba(0,0,0,0.08)]",
        // Smooth transition for all hover states
        "transition-[border-color,background,transform] duration-300 ease-out",
        hoverable && "hover:border-primary/30 hover:bg-card/70 active:scale-[0.98]",
        onClick && "cursor-pointer",
        className
      )}
      variants={fadeUp}
      whileHover={
        hoverable
          ? {
              y: -6,
              boxShadow: "0 12px 24px -8px oklch(0.75 0.18 195 / 0.2), 0 4px 12px -4px rgba(0,0,0,0.15)"
            }
          : undefined
      }
      transition={{ ...springs.snappy, delay: staggerDelay(index, 0.08) }}
      onClick={onClick}
    >
      {/* Gradient glow on hover - enhanced with larger spread */}
      <motion.div
        className={cn(
          "pointer-events-none absolute -right-24 -top-24 h-48 w-48 rounded-full blur-3xl",
          gradientGlowColors[variant]
        )}
        initial={{ opacity: 0, scale: 0.8 }}
        whileHover={{ opacity: 0.35, scale: 1 }}
        transition={springs.smooth}
      />

      {/* Subtle inner glow for premium feel */}
      <div className="pointer-events-none absolute inset-0 rounded-2xl opacity-0 transition-opacity duration-300 group-hover:opacity-100 bg-gradient-to-br from-white/[0.02] via-transparent to-transparent" />

      <div className="relative z-10">{children}</div>
    </motion.div>
  );
}

/**
 * FeatureCard - Card with icon, title, and description.
 *
 * Follows the landing page feature card pattern.
 */
export function FeatureCard({
  icon,
  title,
  description,
  variant = "cyan",
  index = 0,
  className,
}: FeatureCardProps) {
  return (
    <GradientCard variant={variant} index={index} className={className}>
      <motion.div
        className="mb-4 inline-flex rounded-xl bg-primary/10 p-3 text-primary"
        whileHover={{ scale: 1.1, rotate: 5 }}
        transition={springs.snappy}
      >
        {icon}
      </motion.div>
      <h3 className="mb-2 text-lg font-semibold tracking-tight">{title}</h3>
      <p className="text-sm leading-relaxed text-muted-foreground">
        {description}
      </p>
    </GradientCard>
  );
}

/**
 * IconCard - Card with gradient icon container, title, description, and optional detail.
 *
 * Used for pricing cards, feature highlights, etc.
 */
export function IconCard({
  icon: Icon,
  title,
  description,
  detail,
  gradient,
  index = 0,
  className,
}: IconCardProps) {
  return (
    <motion.div
      className={cn(
        "group relative overflow-hidden rounded-2xl border border-border/50 bg-card/50 p-6 backdrop-blur-sm transition-all duration-300 hover:border-primary/30",
        className
      )}
      variants={fadeUp}
      transition={{ delay: staggerDelay(index, 0.1) }}
      whileHover={{
        y: -4,
        boxShadow: "0 20px 40px -12px oklch(0.75 0.18 195 / 0.15)",
      }}
    >
      {/* Gradient glow on hover */}
      <motion.div
        className={cn(
          "pointer-events-none absolute -right-20 -top-20 h-40 w-40 rounded-full bg-gradient-to-br blur-3xl opacity-0 group-hover:opacity-20 transition-opacity",
          gradient
        )}
      />

      <div className="relative">
        {/* Gradient icon container */}
        <div
          className={cn(
            "mb-4 inline-flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br",
            gradient
          )}
        >
          <Icon className="h-6 w-6 text-white" />
        </div>

        <h3 className="mb-2 text-lg font-semibold">{title}</h3>
        <p className="mb-3 text-sm leading-relaxed text-muted-foreground">
          {description}
        </p>

        {detail && (
          <p className="text-xs text-muted-foreground/70 italic">{detail}</p>
        )}
      </div>
    </motion.div>
  );
}
