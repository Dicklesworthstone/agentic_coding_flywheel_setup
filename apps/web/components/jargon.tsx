"use client";

import React, {
  useState,
  useCallback,
  useRef,
  useEffect,
  useLayoutEffect,
  type ReactNode,
} from "react";
import { motion, AnimatePresence } from "@/components/motion";
import { springs } from "@/components/motion";
import { X, Lightbulb } from "lucide-react";
import { cn } from "@/lib/utils";
import { getJargon, type JargonTerm } from "@/lib/jargon";

interface JargonProps {
  /** The term key to look up in the dictionary */
  term: string;
  /** Optional: override the display text (defaults to term.term) */
  children?: ReactNode;
  /** Optional: additional class names */
  className?: string;
}

/**
 * Jargon component - makes technical terms accessible to beginners.
 *
 * - Desktop: Shows tooltip on hover
 * - Mobile: Shows bottom sheet on tap
 * - Styled with dotted underline to indicate interactivity
 */
export function Jargon({ term, children, className }: JargonProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [isMobile, setIsMobile] = useState(false);
  const [tooltipLayout, setTooltipLayout] = useState<{
    position: "top" | "bottom";
    style: React.CSSProperties;
  }>({ position: "top", style: {} });
  const triggerRef = useRef<HTMLButtonElement>(null);
  const tooltipRef = useRef<HTMLDivElement>(null);
  const closeTimeoutRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const jargonData = getJargon(term);

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
      window.innerWidth - 336
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

  const handleClick = useCallback(() => {
    if (isMobile) {
      setIsOpen(true);
    }
  }, [isMobile]);

  const handleClose = useCallback(() => {
    setIsOpen(false);
  }, []);

  // Handle click outside for mobile
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

    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
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
        className={cn(
          "relative inline cursor-help",
          // Dotted underline with subtle color
          "decoration-primary/40 decoration-dotted decoration-2 underline underline-offset-4",
          // Hover state
          "transition-all hover:decoration-primary hover:text-primary",
          // Focus state for accessibility
          "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background rounded-sm",
          className
        )}
        aria-label={`Learn about ${jargonData.term}`}
        aria-expanded={isOpen}
      >
        {displayText}
      </button>

      {/* Desktop Tooltip */}
      <AnimatePresence>
        {isOpen && !isMobile && (
          <motion.div
            ref={tooltipRef}
            initial={{ opacity: 0, y: tooltipLayout.position === "top" ? 8 : -8, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: tooltipLayout.position === "top" ? 8 : -8, scale: 0.95 }}
            transition={springs.snappy}
            className={cn(
              "fixed z-[100] w-80 max-w-[calc(100vw-2rem)]",
              "rounded-xl border border-border/50 bg-card/95 p-4 shadow-2xl backdrop-blur-xl",
              // Gradient accent line at top
              "before:absolute before:inset-x-0 before:h-1 before:rounded-t-xl before:bg-gradient-to-r before:from-primary/50 before:via-[oklch(0.7_0.2_330/0.5)] before:to-primary/50",
              tooltipLayout.position === "top" ? "before:top-0" : "before:bottom-0 before:rounded-t-none before:rounded-b-xl"
            )}
            style={tooltipLayout.style}
            onMouseEnter={handleMouseEnter}
            onMouseLeave={handleMouseLeave}
          >
            <TooltipContent term={jargonData} />
          </motion.div>
        )}
      </AnimatePresence>

      {/* Mobile Bottom Sheet */}
      <AnimatePresence>
        {isOpen && isMobile && (
          <>
            {/* Backdrop */}
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.2 }}
              className="fixed inset-0 z-[100] bg-black/60 backdrop-blur-sm"
              onClick={handleClose}
              aria-hidden="true"
            />

            {/* Sheet */}
            <motion.div
              ref={tooltipRef}
              initial={{ y: "100%" }}
              animate={{ y: 0 }}
              exit={{ y: "100%" }}
              transition={springs.smooth}
              className="fixed inset-x-0 bottom-0 z-[101] max-h-[80vh] overflow-hidden rounded-t-3xl border-t border-border/50 bg-card/98 shadow-2xl backdrop-blur-xl"
            >
              {/* Handle */}
              <div className="flex justify-center pt-3 pb-1">
                <div className="h-1 w-10 rounded-full bg-muted-foreground/30" />
              </div>

              {/* Close button */}
              <button
                onClick={handleClose}
                className="absolute right-4 top-4 flex h-9 w-9 items-center justify-center rounded-full bg-muted text-muted-foreground transition-colors hover:bg-muted/80 hover:text-foreground"
                aria-label="Close"
              >
                <X className="h-5 w-5" />
              </button>

              {/* Content */}
              <div className="overflow-y-auto px-6 pb-safe pt-2 pb-8">
                <SheetContent term={jargonData} />
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </>
  );
}

/**
 * Desktop tooltip content
 */
function TooltipContent({ term }: { term: JargonTerm }) {
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
      <p className="text-[11px] text-muted-foreground/60">
        Click to learn more
      </p>
    </div>
  );
}

/**
 * Mobile bottom sheet content
 */
function SheetContent({ term }: { term: JargonTerm }) {
  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex items-center gap-3">
        <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br from-primary/20 to-[oklch(0.7_0.2_330/0.2)] shadow-lg">
          <Lightbulb className="h-6 w-6 text-primary" />
        </div>
        <div>
          <h3 className="text-xl font-bold text-foreground">{term.term}</h3>
          <p className="text-sm text-muted-foreground">{term.short.split("—")[0]}</p>
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
