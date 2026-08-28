"use client";

import * as React from "react";
import { AnimatePresence, motion as m } from "@/components/motion";
import { cn } from "@/lib/utils";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";
import {
  AlertCircle,
  AlertTriangle,
  CheckCircle2,
  Info,
  Sparkles,
  X,
  type LucideIcon,
} from "lucide-react";

type AlertVariant = "info" | "success" | "warning" | "error" | "tip" | "magic";

interface AlertCardProps {
  variant?: AlertVariant;
  icon?: LucideIcon;
  title?: string;
  children: React.ReactNode;
  className?: string;
  /** Whether the alert can be dismissed */
  dismissible?: boolean;
  /** Callback when dismissed */
  onDismiss?: () => void;
  /** Auto-dismiss after this many milliseconds (0 = no auto-dismiss) */
  autoDismissMs?: number;
  /** Whether to show countdown progress bar when auto-dismissing */
  showProgress?: boolean;
}

const variantStyles: Record<
  AlertVariant,
  { container: string; icon: string; title: string; defaultIcon: LucideIcon }
> = {
  // Colours go through the theme tokens (text-green, border-amber/30, …) so
  // the light theme gets its re-tuned, darker accents instead of the dark-only
  // oklch literals that sat at ~1.5:1 on a white card.
  info: {
    container: "border-primary/30 bg-primary/10",
    icon: "text-primary",
    title: "text-primary",
    defaultIcon: Info,
  },
  success: {
    container: "border-green/30 bg-green/10",
    icon: "text-green",
    title: "text-green",
    defaultIcon: CheckCircle2,
  },
  warning: {
    container: "border-amber/30 bg-amber/10",
    icon: "text-amber",
    title: "text-amber",
    defaultIcon: AlertTriangle,
  },
  error: {
    container: "border-destructive/30 bg-destructive/10",
    icon: "text-destructive",
    title: "text-destructive",
    defaultIcon: AlertCircle,
  },
  tip: {
    container: "border-magenta/30 bg-magenta/10",
    icon: "text-magenta",
    title: "text-magenta",
    defaultIcon: Info,
  },
  magic: {
    container:
      "border-primary/30 bg-primary/[0.08] shadow-sm shadow-primary/10",
    icon: "text-primary",
    title: "text-primary",
    defaultIcon: Sparkles,
  },
};

/**
 * A premium alert card component with consistent OKLCH design system styling.
 * Use for info boxes, success messages, warnings, and tips in wizard pages.
 */
export function AlertCard({
  variant = "info",
  icon,
  title,
  children,
  className,
  dismissible = false,
  onDismiss,
  autoDismissMs = 0,
  showProgress = false,
}: AlertCardProps) {
  const styles = variantStyles[variant];
  const IconComponent = icon || styles.defaultIcon;
  const prefersReducedMotion = useReducedMotion();
  const [dismissed, setDismissed] = React.useState(false);

  const handleDismiss = React.useCallback(() => {
    if (dismissed) return;
    setDismissed(true);
    onDismiss?.();
  }, [dismissed, onDismiss]);

  React.useEffect(() => {
    if (!autoDismissMs || autoDismissMs <= 0 || dismissed) return;
    const timeout = window.setTimeout(() => {
      handleDismiss();
    }, autoDismissMs);
    return () => window.clearTimeout(timeout);
  }, [autoDismissMs, dismissed, handleDismiss]);

  const showProgressBar = showProgress && autoDismissMs > 0;

  return (
    <AnimatePresence>
      {!dismissed && (
        <m.div
          className={cn(
            "relative rounded-xl border p-4 backdrop-blur-sm transition",
            styles.container,
            className
          )}
          initial={prefersReducedMotion ? {} : { opacity: 0, y: -8, scale: 0.98 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={prefersReducedMotion ? {} : { opacity: 0, y: -8, scale: 0.98 }}
          transition={prefersReducedMotion ? { duration: 0 } : { duration: 0.2 }}
        >
          {dismissible && (
            <button
              onClick={handleDismiss}
              className={cn(
                "absolute right-3 top-3 flex h-11 w-11 items-center justify-center",
                "rounded-lg text-current/60 transition-colors",
                "hover:bg-current/10 hover:text-current",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              )}
              aria-label="Dismiss alert"
            >
              <X className="h-4 w-4" />
            </button>
          )}

          {showProgressBar && (
            <div
              className={cn(
                "pointer-events-none absolute inset-x-0 bottom-0 h-1 overflow-hidden rounded-b-xl",
                styles.icon
              )}
            >
              <div className="absolute inset-0 bg-current/15" />
              <m.div
                className="h-full bg-current/45"
                initial={{ width: "100%" }}
                animate={{ width: "0%" }}
                transition={
                  prefersReducedMotion
                    ? { duration: 0 }
                    : { duration: autoDismissMs / 1000, ease: "linear" }
                }
              />
            </div>
          )}

          <div className="flex gap-3">
            <IconComponent
              className={cn("mt-0.5 h-5 w-5 shrink-0", styles.icon)}
            />
            <div className="min-w-0 flex-1 space-y-1">
              {title && (
                <p className={cn("font-medium", styles.title)}>{title}</p>
              )}
              <div className="text-sm text-muted-foreground">{children}</div>
            </div>
          </div>
        </m.div>
      )}
    </AnimatePresence>
  );
}

/**
 * A code output preview card, like showing expected terminal output.
 */
export function OutputPreview({
  title,
  children,
  className,
}: {
  title?: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "rounded-xl border border-green/30 bg-green/10 p-4 backdrop-blur-sm",
        className
      )}
    >
      {title && (
        <div className="mb-3 flex items-center gap-2">
          <CheckCircle2 className="h-5 w-5 text-green" />
          <span className="font-medium text-green">
            {title}
          </span>
        </div>
      )}
      {/* The terminal box is a deliberate dark island: it keeps its near-black
          background in the light theme, so it opts into the `dark` token set
          (globals.css `.light .dark`) and re-resolves `color`; otherwise the
          token-coloured children (text-muted-foreground / text-foreground)
          would render light-theme dark text on a dark box. */}
      <div
        className="dark overflow-x-auto rounded-lg bg-[oklch(0.08_0.015_260)] p-3 font-mono text-sm text-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring"
        tabIndex={0}
      >
        {children}
      </div>
    </div>
  );
}

/**
 * A collapsible details section with premium styling.
 */
export function DetailsSection({
  summary,
  children,
  className,
  defaultOpen = false,
}: {
  summary: string;
  children: React.ReactNode;
  className?: string;
  defaultOpen?: boolean;
}) {
  return (
    <details
      className={cn(
        "group rounded-xl border border-border/50 bg-card/50 backdrop-blur-sm transition",
        "hover:border-primary/20",
        className
      )}
      open={defaultOpen}
    >
      <summary className="flex cursor-pointer items-center justify-between px-4 py-3 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground [&::-webkit-details-marker]:hidden">
        <span>{summary}</span>
        <svg
          className="h-4 w-4 shrink-0 text-muted-foreground transition-transform duration-200 group-open:rotate-180"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M19 9l-7 7-7-7"
          />
        </svg>
      </summary>
      <div className="border-t border-border/30 px-4 py-3">{children}</div>
    </details>
  );
}
