"use client";

import { m, AnimatePresence, useReducedMotion, useInView, type Variants } from "framer-motion";

/**
 * Spring configurations optimized for Stripe/Linear-style subtle, professional feel.
 * High damping = minimal overshoot. Lower stiffness = smoother feel.
 */
export const springs = {
  /** Default for most interactions - smooth and professional */
  smooth: { type: "spring", stiffness: 200, damping: 25 } as const,
  /** Quick feedback for buttons and small elements */
  snappy: { type: "spring", stiffness: 400, damping: 35 } as const,
  /** Slow, elegant transitions for page/modal reveals */
  gentle: { type: "spring", stiffness: 100, damping: 20 } as const,
  /** Very responsive, near-instant */
  quick: { type: "spring", stiffness: 500, damping: 40 } as const,
} as const;

/**
 * Easing curves for non-spring animations
 */
export const easings = {
  /** Smooth deceleration (ease-out) */
  out: [0.22, 1, 0.36, 1] as const,
  /** Smooth acceleration (ease-in) */
  in: [0.4, 0, 1, 1] as const,
  /** Smooth both (ease-in-out) */
  inOut: [0.4, 0, 0.2, 1] as const,
} as const;

/**
 * Animation variant presets
 */

/** Fade up from below - great for scroll reveals */
export const fadeUp: Variants = {
  hidden: {
    opacity: 0,
    y: 24,
  },
  visible: {
    opacity: 1,
    y: 0,
    transition: springs.smooth,
  },
  exit: {
    opacity: 0,
    y: -12,
    transition: { duration: 0.2 },
  },
};

/** Fade in with subtle scale */
export const fadeScale: Variants = {
  hidden: {
    opacity: 0,
    scale: 0.96,
  },
  visible: {
    opacity: 1,
    scale: 1,
    transition: springs.smooth,
  },
  exit: {
    opacity: 0,
    scale: 0.98,
    transition: { duration: 0.15 },
  },
};

/** Slide in from left */
export const slideLeft: Variants = {
  hidden: {
    opacity: 0,
    x: -24,
  },
  visible: {
    opacity: 1,
    x: 0,
    transition: springs.smooth,
  },
  exit: {
    opacity: 0,
    x: 24,
    transition: { duration: 0.15 },
  },
};

/** Slide in from right */
export const slideRight: Variants = {
  hidden: {
    opacity: 0,
    x: 24,
  },
  visible: {
    opacity: 1,
    x: 0,
    transition: springs.smooth,
  },
  exit: {
    opacity: 0,
    x: -24,
    transition: { duration: 0.15 },
  },
};

/** Container with staggered children - use on parent element */
export const staggerContainer: Variants = {
  hidden: {},
  visible: {
    transition: {
      staggerChildren: 0.06,
      delayChildren: 0.1,
    },
  },
};

/** Faster stagger for lists */
export const staggerFast: Variants = {
  hidden: {},
  visible: {
    transition: {
      staggerChildren: 0.04,
      delayChildren: 0.05,
    },
  },
};

/** Slower stagger for hero sections */
export const staggerSlow: Variants = {
  hidden: {},
  visible: {
    transition: {
      staggerChildren: 0.1,
      delayChildren: 0.2,
    },
  },
};

// =============================================================================
// MODAL & SHEET ENTRANCE VARIANTS
// =============================================================================

/** Modal entrance - scale and fade from center (dialogs, popups) */
export const modalEntrance: Variants = {
  hidden: {
    opacity: 0,
    scale: 0.95,
    y: 10,
  },
  visible: {
    opacity: 1,
    scale: 1,
    y: 0,
    transition: springs.smooth,
  },
  exit: {
    opacity: 0,
    scale: 0.98,
    y: 5,
    transition: { duration: 0.15 },
  },
};

/** Bottom sheet entrance - slide from bottom with spring physics */
export const sheetEntrance: Variants = {
  hidden: {
    y: "100%",
    opacity: 0.8,
  },
  visible: {
    y: 0,
    opacity: 1,
    transition: {
      type: "spring",
      stiffness: 300,
      damping: 30,
    },
  },
  exit: {
    y: "100%",
    opacity: 0.8,
    transition: { duration: 0.2 },
  },
};

// =============================================================================
// PREMIUM SCROLL REVEAL VARIANTS
// =============================================================================

/** Fade up with blur effect - premium reveal for hero sections */
export const fadeUpBlur: Variants = {
  hidden: {
    opacity: 0,
    y: 30,
    filter: "blur(10px)",
  },
  visible: {
    opacity: 1,
    y: 0,
    filter: "blur(0px)",
    transition: springs.smooth,
  },
  exit: {
    opacity: 0,
    y: -15,
    filter: "blur(5px)",
    transition: { duration: 0.2 },
  },
};

/** Scale up entrance - great for badges, pills, and small UI elements */
export const scaleUp: Variants = {
  hidden: {
    opacity: 0,
    scale: 0.8,
  },
  visible: {
    opacity: 1,
    scale: 1,
    transition: springs.snappy,
  },
  exit: {
    opacity: 0,
    scale: 0.9,
    transition: { duration: 0.1 },
  },
};

// =============================================================================
// ADDITIONAL STAGGER VARIANTS
// =============================================================================

/** Micro stagger for pill/tag lists - very quick succession */
export const staggerMicro: Variants = {
  hidden: {},
  visible: {
    transition: {
      staggerChildren: 0.02,
      delayChildren: 0,
    },
  },
};

/** Cascade stagger for dashboard cards - elegant delayed reveal */
export const staggerCascade: Variants = {
  hidden: {},
  visible: {
    transition: {
      staggerChildren: 0.08,
      delayChildren: 0.15,
      staggerDirection: 1,
    },
  },
};

// =============================================================================
// PRESENCE ANIMATION HELPERS
// =============================================================================

/** Motion props type for presence animations */
export interface PresenceMotionProps {
  initial: "hidden" | false;
  animate: "visible";
  exit?: "exit";
  variants: Variants;
}

/**
 * Get animation props that respect reduced motion preference.
 * Use this to conditionally apply animations based on user preferences.
 *
 * @param variants - The animation variants to use
 * @param prefersReducedMotion - Whether user prefers reduced motion
 * @returns Motion props object ready to spread onto a motion component
 *
 * @example
 * ```tsx
 * const prefersReducedMotion = useReducedMotion();
 * return (
 *   <motion.div {...getPresenceProps(modalEntrance, prefersReducedMotion ?? false)}>
 *     {children}
 *   </motion.div>
 * );
 * ```
 */
export function getPresenceProps(
  variants: Variants,
  prefersReducedMotion: boolean
): PresenceMotionProps {
  if (prefersReducedMotion) {
    return {
      initial: false,
      animate: "visible",
      variants,
    };
  }
  return {
    initial: "hidden",
    animate: "visible",
    exit: "exit",
    variants,
  };
}

/**
 * Button/interactive element hover and tap props
 * Use with spread: {...buttonMotion}
 */
export const buttonMotion = {
  whileHover: { scale: 1.02 },
  whileTap: { scale: 0.98 },
  transition: springs.snappy,
} as const;

/** Subtle card hover */
export const cardMotion = {
  whileHover: { y: -4 },
  transition: springs.smooth,
} as const;

/** List item hover */
export const listItemMotion = {
  whileHover: { x: 4 },
  transition: springs.snappy,
} as const;

/**
 * Reduced motion safe wrapper
 * Returns empty object if user prefers reduced motion
 */
export function getMotionProps(
  props: Record<string, unknown>,
  prefersReducedMotion: boolean
): Record<string, unknown> {
  if (prefersReducedMotion) {
    return {};
  }
  return props;
}

/**
 * Type-safe motion component exports
 * Using `m` components for LazyMotion compatibility
 */
export const MotionDiv = m.div;
export const MotionSpan = m.span;
export const MotionSection = m.section;
export const MotionNav = m.nav;
export const MotionButton = m.button;
export const MotionA = m.a;
export const MotionUl = m.ul;
export const MotionLi = m.li;
export const MotionHeader = m.header;
export const MotionFooter = m.footer;
export const MotionArticle = m.article;
export const MotionAside = m.aside;
export const MotionMain = m.main;
export const MotionP = m.p;
export const MotionH1 = m.h1;
export const MotionH2 = m.h2;
export const MotionH3 = m.h3;
export const MotionH4 = m.h4;

// Re-export `m` as `motion` for backwards compatibility with LazyMotion strict mode
// This allows existing code using `motion.div` etc. to work without changes
// `m` is the LazyMotion-compatible component. The root MotionProvider mounts
// <LazyMotion strict>, so importing the full `motion` from "framer-motion"
// throws in dev and bundles the full animation runtime; always import
// `motion` from here instead.
export { m as motion, AnimatePresence, useReducedMotion, useInView };
export type { Variants };
