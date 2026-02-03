"use client";

import {
  useState,
  useCallback,
  useRef,
  useEffect,
  useLayoutEffect,
  type CSSProperties,
  type ReactNode,
} from "react";
import Link from "next/link";
import { createPortal } from "react-dom";
import { motion, AnimatePresence, springs } from "@/components/motion";
import { X, Lightbulb } from "lucide-react";
import { cn } from "@/lib/utils";
import { getJargon, type JargonTerm } from "@/lib/jargon";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";

interface JargonProps {
  /** The term key to look up in the dictionary */
  term: string;
  /** Optional: override the display text (defaults to term.term) */
  children?: ReactNode;
  /** Optional: additional class names */
  className?: string;
  /**
   * When true, applies gradient text styling to match h1/h2 gradient headings.
   * Use this when Jargon is placed inside a heading with `text-transparent bg-clip-text` gradient.
   */
  gradientHeading?: boolean;
}

/**
 * Jargon component - makes technical terms accessible to beginners.
 *
 * - Desktop: Shows tooltip on hover
 * - Mobile: Shows bottom sheet on tap
 * - Styled with dotted underline to indicate interactivity
 */
export function Jargon({ term, children, className, gradientHeading }: JargonProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [isMobile, setIsMobile] = useState(false);
  const [tooltipLayout, setTooltipLayout] = useState<{
    position: "top" | "bottom";
    style: CSSProperties;
  }>({ position: "top", style: {} });
  const triggerRef = useRef<HTMLButtonElement>(null);
  const tooltipRef = useRef<HTMLDivElement>(null);
  const closeTimeoutRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const prefersReducedMotion = useReducedMotion();

  const termKey = term.toLowerCase().replace(/[\s_]+/g, "-");
  const jargonData = getJargon(termKey);

  // Check if we can use portals (client-side only)
  const canUsePortal = typeof document !== "undefined";

  useEffect(() => {
    return () => {
      if (closeTimeoutRef.current) {
        clearTimeout(closeTimeoutRef.current);
      }
    };
  }, []);

  // Detect mobile on mount
  useEffect(() => {
    const checkMobile = () => {
      setIsMobile(window.matchMedia("(max-width: 768px)").matches);
    };
    checkMobile();
    window.addEventListener("resize", checkMobile);
    return () => window.removeEventListener("resize", checkMobile);
  }, []);

  // Calculate tooltip position and style to avoid viewport edges
  // useLayoutEffect is correct here as we're measuring DOM elements
  useLayoutEffect(() => {
    if (!isOpen || !triggerRef.current || isMobile) return;

    const rect = triggerRef.current.getBoundingClientRect();
    const offsetWidth = triggerRef.current.offsetWidth;

    // If near top of viewport, show below
    const position: "top" | "bottom" = rect.top < 200 ? "bottom" : "top";

    // Calculate left position (centered on trigger, clamped to viewport)
    const left = Math.min(
      Math.max(16, rect.left - 140 + offsetWidth / 2),
      Math.max(16, window.innerWidth - 336)
    );

    // Calculate vertical position
    const verticalStyle = position === "top"
      ? { bottom: window.innerHeight - rect.top + 8 }
      : { top: rect.bottom + 8 };

    setTooltipLayout({ position, style: { left, ...verticalStyle } });
  }, [isOpen, isMobile]);

  // Lock body scroll when mobile sheet is open
  useEffect(() => {
    if (isOpen && isMobile) {
      const scrollY = window.scrollY;
      document.body.style.position = "fixed";
      document.body.style.top = `-${scrollY}px`;
      document.body.style.width = "100%";
      return () => {
        document.body.style.position = "";
        document.body.style.top = "";
        document.body.style.width = "";
        window.scrollTo(0, scrollY);
      };
    }
  }, [isOpen, isMobile]);

  const handleMouseEnter = useCallback(() => {
    if (isMobile) return;
    if (closeTimeoutRef.current) {
      clearTimeout(closeTimeoutRef.current);
    }
    setIsOpen(true);
  }, [isMobile]);

  const handleMouseLeave = useCallback(() => {
    if (isMobile) return;
    closeTimeoutRef.current = setTimeout(() => {
      setIsOpen(false);
    }, 150);
  }, [isMobile]);

  const handleFocus = useCallback(() => {
    if (isMobile) return;
    if (closeTimeoutRef.current) {
      clearTimeout(closeTimeoutRef.current);
    }
    setIsOpen(true);
  }, [isMobile]);

  const handleBlur = useCallback((e: React.FocusEvent) => {
    if (isMobile) return;
    if (closeTimeoutRef.current) {
      clearTimeout(closeTimeoutRef.current);
    }
    // Check if focus is moving to an element inside the tooltip
    // If so, don't close immediately - let the user interact with tooltip links
    const relatedTarget = e.relatedTarget as Node | null;
    if (relatedTarget && tooltipRef.current?.contains(relatedTarget)) {
      return;
    }
    // Use a small delay to allow focus to settle (same as mouse leave)
    closeTimeoutRef.current = setTimeout(() => {
      setIsOpen(false);
    }, 150);
  }, [isMobile]);

  const handleClick = useCallback(() => {
    // Always open on click - supports both mobile tap and desktop keyboard activation
    setIsOpen(true);
  }, []);

  const handleClose = useCallback(() => {
    setIsOpen(false);
  }, []);

  // Handle click outside and escape key for mobile
  useEffect(() => {
    if (!isOpen || !isMobile) return;

    const handleClickOutside = (e: MouseEvent) => {
      const target = e.target as Node;
      if (
        triggerRef.current &&
        !triggerRef.current.contains(target) &&
        tooltipRef.current &&
        !tooltipRef.current.contains(target)
      ) {
        setIsOpen(false);
      }
    };

    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === "Escape") setIsOpen(false);
    };

    document.addEventListener("mousedown", handleClickOutside);
    document.addEventListener("keydown", handleEscape);
    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
      document.removeEventListener("keydown", handleEscape);
    };
  }, [isOpen, isMobile]);

  if (!jargonData) {
    // If term not found, just render children without styling
    return <>{children || term}</>;
  }

  const displayText = children || jargonData.term;

  return (
    <>
      {/* Trigger */}
      <button
        ref={triggerRef}
        type="button"
        onClick={handleClick}
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
        onFocus={handleFocus}
        onBlur={handleBlur}
        className={cn(
          "relative inline cursor-help",
          // Subtle dotted underline - very gentle visual hint
          "decoration-[1.5px] underline underline-offset-[3px]",
          "decoration-primary/30 decoration-dotted",
          // Hover/active state - slightly more visible
          "transition-colors duration-150",
          "hover:decoration-primary/60 hover:text-primary/90",
          // Focus state for accessibility
          "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background rounded-sm",
          // Gradient heading mode: applies gradient text styling to match surrounding h1/h2
          gradientHeading && "bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-transparent",
          className
        )}
        aria-label={`Learn about ${jargonData.term}`}
        aria-expanded={isOpen}
      >
        {displayText}
      </button>

      {/* Desktop Tooltip - rendered via portal to escape stacking contexts */}
      {canUsePortal && createPortal(
        <AnimatePresence>
          {isOpen && !isMobile && (
            <motion.div
              ref={tooltipRef}
              initial={
                prefersReducedMotion
                  ? { opacity: 0 }
                  : { opacity: 0, y: tooltipLayout.position === "top" ? 8 : -8, scale: 0.95 }
              }
              animate={prefersReducedMotion ? { opacity: 1 } : { opacity: 1, y: 0, scale: 1 }}
              exit={
                prefersReducedMotion
                  ? { opacity: 0 }
                  : { opacity: 0, y: tooltipLayout.position === "top" ? 8 : -8, scale: 0.95 }
              }
              transition={prefersReducedMotion ? { duration: 0.12 } : springs.snappy}
              className={cn(
                "fixed z-[9999] w-80 max-w-[calc(100vw-2rem)]",
                "rounded-xl border border-border/50 bg-card/95 p-4 shadow-2xl backdrop-blur-xl",
                // Gradient accent line at top
                "before:absolute before:inset-x-0 before:h-1 before:rounded-t-xl before:bg-gradient-to-r before:from-primary/50 before:via-[oklch(0.7_0.2_330/0.5)] before:to-primary/50",
                tooltipLayout.position === "top" ? "before:top-0" : "before:bottom-0 before:rounded-t-none before:rounded-b-xl"
              )}
              style={tooltipLayout.style}
              onMouseEnter={handleMouseEnter}
              onMouseLeave={handleMouseLeave}
              onBlur={(e: React.FocusEvent) => {
                // Close tooltip when focus leaves it entirely (not moving to trigger)
                const relatedTarget = e.relatedTarget as Node | null;
                if (relatedTarget && triggerRef.current?.contains(relatedTarget)) {
                  return;
                }
                if (relatedTarget && tooltipRef.current?.contains(relatedTarget)) {
                  return;
                }
                closeTimeoutRef.current = setTimeout(() => {
                  setIsOpen(false);
                }, 150);
              }}
            >
              <TooltipContent term={jargonData} termKey={termKey} />
            </motion.div>
          )}
        </AnimatePresence>,
        document.body
      )}

      {/* Mobile Bottom Sheet - rendered via portal to escape stacking contexts */}
      {canUsePortal && createPortal(
        <AnimatePresence>
          {isOpen && isMobile && (
            <>
              {/* Backdrop */}
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={prefersReducedMotion ? { duration: 0.12 } : { duration: 0.2 }}
                className="fixed inset-0 z-[9998] bg-black/60 backdrop-blur-sm"
                onClick={handleClose}
                aria-hidden="true"
              />

              {/* Sheet */}
              <motion.div
                ref={tooltipRef}
                role="dialog"
                aria-modal="true"
                aria-labelledby={`jargon-sheet-title-${termKey}`}
                initial={prefersReducedMotion ? { opacity: 0 } : { y: "100%" }}
                animate={prefersReducedMotion ? { opacity: 1 } : { y: 0 }}
                exit={prefersReducedMotion ? { opacity: 0 } : { y: "100%" }}
                transition={prefersReducedMotion ? { duration: 0.12 } : springs.smooth}
                className="fixed inset-x-0 bottom-0 z-[9999] flex max-h-[80vh] flex-col rounded-t-3xl border-t border-border/50 bg-card/98 shadow-2xl backdrop-blur-xl"
              >
                {/* Handle */}
                <div className="flex shrink-0 justify-center pt-3 pb-1">
                  <div className="h-1 w-10 rounded-full bg-muted-foreground/30" />
                </div>

                {/* Close button */}
                <button
                  onClick={handleClose}
                  className="absolute right-4 top-4 flex h-11 w-11 items-center justify-center rounded-full bg-muted text-muted-foreground transition-colors hover:bg-muted/80 hover:text-foreground"
                  aria-label="Close"
                >
                  <X className="h-5 w-5" />
                </button>

                {/* Content - iOS needs overscroll-contain and touch-action for proper scrolling */}
                <div
                  className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-6 pt-2 pb-[calc(2rem+env(safe-area-inset-bottom,0px))]"
                  style={{ WebkitOverflowScrolling: 'touch' }}
                >
                  <SheetContent term={jargonData} termKey={termKey} />
                </div>
              </motion.div>
            </>
          )}
        </AnimatePresence>,
        document.body
      )}
    </>
  );
}

/**
 * Desktop tooltip content
 */
function TooltipContent({ term, termKey }: { term: JargonTerm; termKey: string }) {
  const glossaryHref = `/glossary#${encodeURIComponent(termKey)}`;

  return (
    <div className="space-y-2">
      {/* Term header */}
      <div className="flex items-center gap-2">
        <div className="flex h-6 w-6 items-center justify-center rounded-lg bg-primary/20 text-primary">
          <Lightbulb className="h-3.5 w-3.5" />
        </div>
        <span className="font-semibold text-foreground">{term.term}</span>
      </div>

      {/* Short definition */}
      <p className="text-sm leading-relaxed text-muted-foreground">
        {term.short}
      </p>

      {/* Analogy if available */}
      {term.analogy && (
        <div className="rounded-lg bg-primary/5 px-3 py-2 text-xs text-muted-foreground">
          <span className="font-medium text-primary">Think of it like:</span>{" "}
          {term.analogy}
        </div>
      )}

      {/* Tap for more hint */}
      <p className="text-xs text-muted-foreground/60">
        Hover or focus to learn more
      </p>

      <Link
        href={glossaryHref}
        className={cn(
          "inline-block text-xs font-medium text-primary underline-offset-4 hover:underline",
          "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background rounded-sm"
        )}
      >
        Open in glossary →
      </Link>
    </div>
  );
}

/**
 * Mobile bottom sheet content
 */
function SheetContent({ term, termKey }: { term: JargonTerm; termKey: string }) {
  const glossaryHref = `/glossary#${encodeURIComponent(termKey)}`;

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex items-center gap-3">
        <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br from-primary/20 to-[oklch(0.7_0.2_330/0.2)] shadow-lg">
          <Lightbulb className="h-6 w-6 text-primary" />
        </div>
        <div>
          <h3 id={`jargon-sheet-title-${termKey}`} className="text-xl font-bold text-foreground">{term.term}</h3>
          <p className="text-sm text-muted-foreground line-clamp-2">
            {term.short}
          </p>
        </div>
      </div>

      {/* Full explanation */}
      <div className="space-y-4">
        <div>
          <h4 className="mb-2 text-xs font-bold uppercase tracking-wider text-muted-foreground">
            What is it?
          </h4>
          <p className="text-sm leading-relaxed text-foreground">
            {term.long}
          </p>
        </div>

        {/* Why we use it */}
        {term.why && (
          <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/5 p-4">
            <p className="mb-1 text-xs font-bold uppercase tracking-wider text-emerald-600 dark:text-emerald-400">
              Why we use it
            </p>
            <p className="text-sm leading-relaxed text-foreground">
              {term.why}
            </p>
          </div>
        )}

        {/* Analogy */}
        {term.analogy && (
          <div className="rounded-xl border border-primary/20 bg-primary/5 p-4">
            <p className="mb-1 text-xs font-bold uppercase tracking-wider text-primary">
              Think of it like...
            </p>
            <p className="text-sm leading-relaxed text-foreground">
              {term.analogy}
            </p>
          </div>
        )}

        {/* Related terms */}
        {term.related && term.related.length > 0 && (
          <div>
            <h4 className="mb-2 text-xs font-bold uppercase tracking-wider text-muted-foreground">
              Related Terms
            </h4>
            <div className="flex flex-wrap gap-2">
              {term.related.map((relatedTerm) => (
                <span
                  key={relatedTerm}
                  className="rounded-full border border-border/50 bg-muted/50 px-3 py-1 text-xs font-medium text-muted-foreground"
                >
                  {relatedTerm}
                </span>
              ))}
            </div>
          </div>
        )}

        <div className="pt-2">
          <Link
            href={glossaryHref}
            className={cn(
              "inline-block text-sm font-medium text-primary underline-offset-4 hover:underline",
              "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background rounded-sm"
            )}
          >
            View in glossary →
          </Link>
        </div>
      </div>
    </div>
  );
}

/**
 * Convenience component for inline jargon that matches surrounding text style
 */
export function JargonInline({ term, children, className }: JargonProps) {
  return (
    <Jargon term={term} className={cn("font-normal", className)}>
      {children}
    </Jargon>
  );
}
