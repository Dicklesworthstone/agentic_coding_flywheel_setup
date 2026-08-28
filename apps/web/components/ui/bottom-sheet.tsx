"use client";

import { useEffect, useCallback, useSyncExternalStore, useRef } from "react";
import { createPortal } from "react-dom";
import { motion as m, AnimatePresence } from "@/components/motion";
import { useDragControls, type PanInfo } from "framer-motion";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";
import { useReducedMotion } from "@/lib/hooks/useReducedMotion";

// Subscribe function for useSyncExternalStore (no-op since we don't need updates)
const emptySubscribe = () => () => {};
// Snapshot functions for client/server detection
const getClientSnapshot = () => true;
const getServerSnapshot = () => false;

// Spring config matching our motion module's smooth spring
const smoothSpring = { type: "spring" as const, stiffness: 200, damping: 25 };

// Elements that can receive keyboard focus inside the sheet (focus trap)
const FOCUSABLE_SELECTOR = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  '[tabindex]:not([tabindex="-1"])',
].join(",");

interface BottomSheetProps {
  /** Whether the sheet is open */
  open: boolean;
  /** Callback when sheet should close */
  onClose: () => void;
  /** Title for accessibility (aria-label) */
  title: string;
  /** Content to render inside the sheet */
  children: React.ReactNode;
  /**
   * Maximum height. When omitted the sheet uses `80dvh` with an `80vh`
   * fallback for browsers without dynamic-viewport units (iOS Safari's
   * toolbar otherwise pushes the handle and close button under the URL bar).
   */
  maxHeight?: string;
  /** Whether to show the drag handle */
  showHandle?: boolean;
  /** Whether to close on backdrop click (default: true) */
  closeOnBackdrop?: boolean;
  /** Whether to enable swipe-to-close (default: true) */
  swipeable?: boolean;
  /** Additional className for the sheet container */
  className?: string;
}

/**
 * Mobile-optimized bottom sheet component.
 *
 * Features:
 * - Swipe-to-close gesture (drag down > 200px or velocity > 500)
 * - Escape key dismissal
 * - Backdrop click dismissal (configurable)
 * - Body scroll lock when open
 * - Safe area padding for notched devices
 * - Reduced motion fallback (opacity instead of slide)
 * - 44px close button touch target
 * - Tab focus contained inside the sheet while open (Escape closes)
 * - ARIA attributes for accessibility
 */
export function BottomSheet({
  open,
  onClose,
  title,
  children,
  maxHeight,
  showHandle = true,
  closeOnBackdrop = true,
  swipeable = true,
  className,
}: BottomSheetProps) {
  const prefersReducedMotion = useReducedMotion();
  const dragControls = useDragControls();
  const sheetRef = useRef<HTMLDivElement>(null);
  const previousActiveElement = useRef<HTMLElement | null>(null);

  // Client-side only mounting for portal (avoids setState in effect)
  const isClient = useSyncExternalStore(
    emptySubscribe,
    getClientSnapshot,
    getServerSnapshot
  );

  // Focus management: move focus to sheet when open, restore when closed
  useEffect(() => {
    if (open) {
      // Store the currently focused element to restore later (only if it's an HTMLElement)
      const activeEl = document.activeElement;
      if (activeEl instanceof HTMLElement) {
        previousActiveElement.current = activeEl;
      }
      // Focus the sheet after a short delay to allow animation to start
      const timer = setTimeout(() => {
        sheetRef.current?.focus();
      }, 50);
      return () => clearTimeout(timer);
    } else if (previousActiveElement.current) {
      // Restore focus to the previously focused element (if still in DOM)
      try {
        if (document.body.contains(previousActiveElement.current)) {
          previousActiveElement.current.focus();
        }
      } catch {
        // Element may have been removed, ignore
      }
      previousActiveElement.current = null;
    }
  }, [open]);

  // Escape key handling
  useEffect(() => {
    if (!open) return;
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", handleEscape);
    return () => document.removeEventListener("keydown", handleEscape);
  }, [open, onClose]);

  // Lock body scroll when open
  useEffect(() => {
    if (open) {
      const originalOverflow = document.body.style.overflow;
      document.body.style.overflow = "hidden";
      return () => {
        document.body.style.overflow = originalOverflow;
      };
    }
  }, [open]);

  // Swipe to close handler
  const handleDragEnd = useCallback(
    (_event: MouseEvent | TouchEvent | PointerEvent, info: PanInfo) => {
      // Close if velocity is high enough or offset is large enough
      if (info.velocity.y > 500 || info.offset.y > 200) {
        onClose();
      }
    },
    [onClose]
  );

  // Contain Tab focus inside the dialog while it is open. The backdrop is
  // not `inert`, so without this a keyboard user tabs straight out of the
  // sheet into the page behind it. Escape (handled above) is the way out.
  const handleKeyDown = useCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key !== "Tab") return;
    const sheet = sheetRef.current;
    if (!sheet) return;

    const focusable = Array.from(
      sheet.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)
    ).filter((el) => el.getAttribute("aria-hidden") !== "true");

    if (focusable.length === 0) {
      // Nothing to move to: keep focus on the sheet itself
      e.preventDefault();
      return;
    }

    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    const active = document.activeElement;
    const activeInsideSheet = active instanceof Node && sheet.contains(active);

    if (e.shiftKey) {
      if (active === first || active === sheet || !activeInsideSheet) {
        e.preventDefault();
        last.focus();
      }
    } else if (active === last || !activeInsideSheet) {
      e.preventDefault();
      first.focus();
    }
  }, []);

  // Don't render on server (portal requires document.body)
  if (!isClient) return null;

  return createPortal(
    <AnimatePresence>
      {open && (
        <>
          {/* Backdrop */}
          <m.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={prefersReducedMotion ? { duration: 0.1 } : { duration: 0.2 }}
            className="fixed inset-0 z-40 bg-black/60 backdrop-blur-sm"
            onClick={closeOnBackdrop ? onClose : undefined}
            aria-hidden="true"
          />

          {/* Sheet */}
          <m.div
            ref={sheetRef}
            role="dialog"
            aria-modal="true"
            aria-label={title}
            tabIndex={-1}
            drag={swipeable && !prefersReducedMotion ? "y" : false}
            dragControls={dragControls}
            dragListener={!showHandle}
            // `bottom: 0` matters: framer only springs back to constraints
            // that exist, so without it a sub-threshold swipe released into
            // free downward inertia and left the sheet displaced.
            dragConstraints={{ top: 0, bottom: 0 }}
            dragElastic={{ top: 0, bottom: 0.5 }}
            onDragEnd={handleDragEnd}
            onKeyDown={handleKeyDown}
            initial={prefersReducedMotion ? { opacity: 0 } : { y: "100%" }}
            animate={prefersReducedMotion ? { opacity: 1 } : { y: 0 }}
            exit={prefersReducedMotion ? { opacity: 0 } : { y: "100%" }}
            transition={prefersReducedMotion ? { duration: 0.1 } : smoothSpring}
            className={cn(
              "fixed inset-x-0 bottom-0 z-50 flex flex-col",
              "rounded-t-3xl border-t border-border/50",
              "bg-card/98 shadow-2xl backdrop-blur-xl",
              // Legacy + dynamic viewport pair: 80vh everywhere, upgraded to
              // 80dvh where the unit is supported. An explicit `maxHeight`
              // prop (inline style) overrides both.
              !maxHeight && "max-h-[80vh] supports-[height:80dvh]:max-h-[80dvh]",
              className
            )}
            style={maxHeight ? { maxHeight } : undefined}
          >
            {/* Drag handle: the whole header strip (56px, the band the close
                button sits in) is the drag surface, not just the 4px bar.
                Content below keeps native scrolling. */}
            {showHandle && (
              <div
                className={cn(
                  "flex min-h-14 shrink-0 justify-center pt-3",
                  swipeable && !prefersReducedMotion
                    ? "cursor-grab touch-none active:cursor-grabbing"
                    : "cursor-default"
                )}
                onPointerDown={(e) => {
                  if (swipeable && !prefersReducedMotion) {
                    dragControls.start(e);
                  }
                }}
              >
                <div className="h-1 w-10 rounded-full bg-muted-foreground/30" />
              </div>
            )}

            {/* Close button - 44px touch target */}
            <button
              type="button"
              onClick={onClose}
              className={cn(
                "absolute right-4 top-4 z-10",
                "flex h-11 w-11 items-center justify-center",
                "rounded-full bg-muted text-muted-foreground",
                "transition-colors hover:bg-muted/80 hover:text-foreground",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              )}
              aria-label="Close"
            >
              <X className="h-5 w-5" />
            </button>

            {/* Content - scrollable with safe area padding */}
            <div
              className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-6 pb-safe pt-2"
              style={{ WebkitOverflowScrolling: "touch" }}
            >
              {children}
            </div>
          </m.div>
        </>
      )}
    </AnimatePresence>,
    document.body
  );
}
