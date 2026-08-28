/**
 * Design Tokens - Centralized design system constants
 *
 * Extracted from the polished landing page to ensure consistency
 * across the Learning Hub and other pages.
 *
 * Uses OKLCH color space for perceptually uniform colors.
 */

// =============================================================================
// COLOR TOKENS
// =============================================================================

/**
 * Semantic color tokens using OKLCH color space.
 * Format: oklch(lightness chroma hue)
 */
export const colors = {
  // Primary accent colors
  cyan: "oklch(0.75 0.18 195)",
  pink: "oklch(0.7 0.2 330)",
  purple: "oklch(0.65 0.18 290)",

  // Semantic colors
  success: "oklch(0.72 0.19 145)",
  warning: "oklch(0.78 0.16 75)",
  error: "oklch(0.65 0.22 25)",
  info: "oklch(0.75 0.18 195)",

  // Gradient tool colors (from flywheel tools)
  sky: "from-sky-400 to-blue-500",
  violet: "from-violet-400 to-purple-500",
  rose: "from-rose-400 to-red-500",
  emerald: "from-emerald-400 to-teal-500",
  amber: "from-amber-400 to-orange-500",
  yellow: "from-yellow-400 to-amber-500",
  fuchsia: "from-pink-400 to-fuchsia-500",
} as const;

/**
 * Gradient glow colors for hover effects
 */
export const glowColors = {
  cyan: "bg-[oklch(0.75_0.18_195)]",
  pink: "bg-[oklch(0.7_0.2_330)]",
  success: "bg-[oklch(0.72_0.19_145)]",
  warning: "bg-[oklch(0.78_0.16_75)]",
  error: "bg-[oklch(0.65_0.22_25)]",
  purple: "bg-[oklch(0.65_0.18_290)]",
} as const;

// =============================================================================
// SHADOW TOKENS
// =============================================================================

/**
 * Premium shadow presets
 */
export const shadows = {
  /** Card hover shadow - subtle cyan glow */
  cardHover: "0 20px 40px -12px oklch(0.75 0.18 195 / 0.15)",
  /** Lifted card shadow */
  cardLifted: "0 25px 50px -12px oklch(0.75 0.18 195 / 0.2)",
  /** Glow effect for primary elements */
  primaryGlow: "0 0 40px -8px oklch(0.75 0.18 195 / 0.3)",
  /** Subtle shadow for floating elements */
  float: "0 8px 24px -4px rgba(0, 0, 0, 0.15)",
} as const;

// =============================================================================
// SPACING TOKENS
// =============================================================================

/**
 * Section spacing presets
 */
export const sectionSpacing = {
  /** Standard section padding */
  py: "py-24",
  /** Compact section padding */
  pyCompact: "py-16",
  /** Large section padding */
  pyLarge: "py-32",
  /** Standard horizontal padding */
  px: "px-6",
  /** Max width container */
  maxWidth: "max-w-7xl",
  /** Narrow max width for text-heavy sections */
  maxWidthNarrow: "max-w-4xl",
} as const;

// =============================================================================
// BORDER RADIUS TOKENS
// =============================================================================

/**
 * Border radius presets
 */
export const radius = {
  /** Cards and containers */
  card: "rounded-2xl",
  /** Smaller cards */
  cardSm: "rounded-xl",
  /** Inner elements */
  inner: "rounded-lg",
  /** Badges and pills */
  full: "rounded-full",
} as const;

// =============================================================================
// TYPOGRAPHY TOKENS
// =============================================================================

/**
 * Section header typography
 */
export const typography = {
  /** Section label (uppercase, small, min 12px for accessibility) */
  sectionLabel: "text-xs font-bold uppercase tracking-[0.25em] text-primary",
  /** Section heading */
  sectionHeading: "font-mono text-3xl font-bold tracking-tight",
  /** Large section heading */
  sectionHeadingLg: "font-mono text-3xl sm:text-4xl font-bold tracking-tight",
  /** Section description */
  sectionDescription: "mx-auto max-w-2xl text-muted-foreground",
} as const;

/**
 * Display typography - fluid values for hero sections (used in CSS variables)
 */
export const displayTypography = {
  /** Font sizes using CSS clamp for fluid scaling */
  fontSize: {
    "5xl": "clamp(3rem, 2.5rem + 2.5vw, 5rem)",
    "6xl": "clamp(3.5rem, 3rem + 3vw, 6rem)",
  },
  /** Letter spacing for large display text */
  tracking: {
    "5xl": "-0.035em",
    "6xl": "-0.04em",
  },
  /** Line heights for large display text */
  leading: {
    "5xl": 1.05,
    "6xl": 1,
  },
  /** Tailwind utility classes for display text */
  classes: {
    "5xl": "text-display-5xl",
    "6xl": "text-display-6xl",
  },
} as const;

// =============================================================================
// ANIMATION CLASSES
// =============================================================================

/**
 * Tailwind animation classes
 */
export const animations = {
  /** Pulse glow for floating orbs */
  pulseGlow: "animate-pulse-glow",
  /** Shimmer effect for buttons */
  shimmer: "animate-shimmer",
} as const;

// =============================================================================
// CARD VARIANT CLASSES
// =============================================================================

/**
 * Card style variants
 */
export const cardStyles = {
  /** Base card with glass effect */
  base: "overflow-hidden rounded-2xl border border-border/50 bg-card/50 backdrop-blur-sm transition duration-300",
  /** Hoverable card */
  hoverable: "overflow-hidden rounded-2xl border border-border/50 bg-card/50 backdrop-blur-sm transition duration-300 hover:border-primary/30",
  /** Feature card with glow */
  feature: "group relative overflow-hidden rounded-2xl border border-border/50 bg-card/50 p-6 backdrop-blur-sm transition duration-300 hover:border-primary/30",
} as const;

// =============================================================================
// BACKGROUND EFFECT CLASSES
// =============================================================================

/**
 * Background effects
 */
export const backgrounds = {
  /** Floating orb - cyan (top-left) */
  orbCyan: "pointer-events-none absolute left-1/4 top-1/4 h-96 w-96 rounded-full bg-[oklch(0.75_0.18_195/0.1)] blur-[100px] hidden sm:block sm:animate-pulse-glow",
  /** Floating orb - pink (bottom-right) */
  orbPink: "pointer-events-none absolute right-1/4 bottom-1/4 h-80 w-80 rounded-full bg-[oklch(0.7_0.2_330/0.08)] blur-[80px] hidden sm:block sm:animate-pulse-glow",
  /** Section orb - left positioned */
  orbLeft: "pointer-events-none absolute -left-40 top-1/4 h-80 w-80 rounded-full bg-[oklch(0.75_0.18_195/0.08)] blur-[100px]",
  /** Section orb - right positioned */
  orbRight: "pointer-events-none absolute -right-40 bottom-1/4 h-80 w-80 rounded-full bg-[oklch(0.7_0.2_330/0.08)] blur-[100px]",
  /** Grid pattern overlay */
  gridPattern: "bg-grid-pattern opacity-30",
  /** Hero gradient */
  heroGradient: "bg-gradient-hero",
} as const;

// =============================================================================
// SECTION DIVIDER CLASSES
// =============================================================================

/**
 * Decorative divider elements
 */
export const dividers = {
  /** Gradient line - left side */
  gradientLeft: "h-px w-8 bg-gradient-to-r from-transparent via-primary/50 to-transparent",
  /** Gradient line - right side */
  gradientRight: "h-px w-8 bg-gradient-to-l from-transparent via-primary/50 to-transparent",
  /** Section border */
  sectionBorder: "border-t border-border/30",
} as const;

// =============================================================================
// ICON CONTAINER CLASSES
// =============================================================================

/**
 * Icon container presets
 */
export const iconContainers = {
  /** Primary icon container */
  primary: "inline-flex rounded-xl bg-primary/10 p-3 text-primary",
  /** Gradient icon container */
  gradient: (color: string) => `inline-flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br ${color}`,
} as const;

// =============================================================================
// BADGE CLASSES
// =============================================================================

/**
 * Badge style presets
 */
export const badges = {
  /** Primary badge (rounded-full) */
  primary: "inline-flex items-center gap-2 rounded-full border border-primary/30 bg-primary/10 px-4 py-1.5 text-sm text-primary",
  /** Subtle badge */
  subtle: "inline-flex items-center rounded-full border border-border/50 bg-card/50 px-3 py-1.5 text-sm font-medium transition hover:scale-105 hover:border-primary/30",
} as const;

// =============================================================================
// TOOL BRAND COLORS
// =============================================================================

/**
 * Brand colors for specific tools (used in ToolBadge components)
 */
export const toolColors = {
  claudeCode: "oklch(0.78 0.16 75)",
  codexCli: "oklch(0.72 0.19 145)",
  geminiCli: "oklch(0.75 0.18 195)",
  bun: "oklch(0.78 0.16 75)",
  rust: "oklch(0.65 0.22 25)",
  go: "oklch(0.75 0.18 195)",
  tmux: "oklch(0.72 0.19 145)",
  zsh: "oklch(0.7 0.2 330)",
} as const;

// =============================================================================
// GRID GAPS
// =============================================================================

/**
 * Grid gap presets
 */
export const gridGaps = {
  /** Small gap (1rem) */
  sm: "gap-4",
  /** Medium gap (1.5rem) */
  md: "gap-6",
  /** Large gap (3rem) */
  lg: "gap-12",
  /** Extra large gap (4rem) */
  xl: "gap-16",
} as const;

// =============================================================================
// FRAMER MOTION SPRINGS
// =============================================================================

/**
 * Framer Motion spring configurations for consistent animations
 */
export const springs = {
  /** Smooth spring for general animations */
  smooth: {
    type: "spring" as const,
    stiffness: 100,
    damping: 20,
    mass: 1,
  },
  /** Bouncy spring for playful interactions */
  bouncy: {
    type: "spring" as const,
    stiffness: 400,
    damping: 25,
    mass: 0.8,
  },
  /** Stiff spring for snappy feedback */
  stiff: {
    type: "spring" as const,
    stiffness: 500,
    damping: 30,
    mass: 0.5,
  },
} as const;

/**
 * Stagger animation helper - calculates delay for list item animations
 * @param index - The index of the item in the list
 * @param baseDelay - Base delay between items (default 0.1s)
 * @param maxDelay - Maximum delay cap to prevent excessive delays in long lists (default 0.5s)
 */
export function staggerDelay(index: number, baseDelay = 0.1, maxDelay = 0.5): number {
  return Math.min(index * baseDelay, maxDelay);
}

/**
 * Framer Motion animation variants
 */
export const motionVariants = {
  /** Fade up animation */
  fadeUp: {
    hidden: { opacity: 0, y: 20 },
    visible: { opacity: 1, y: 0 },
  },
  /** Fade in animation */
  fadeIn: {
    hidden: { opacity: 0 },
    visible: { opacity: 1 },
  },
  /** Scale up animation */
  scaleUp: {
    hidden: { opacity: 0, scale: 0.95 },
    visible: { opacity: 1, scale: 1 },
  },
  /** Stagger container */
  staggerContainer: {
    hidden: { opacity: 0 },
    visible: {
      opacity: 1,
      transition: { staggerChildren: 0.1 },
    },
  },
} as const;

// =============================================================================
// TRANSITIONS
// =============================================================================

/**
 * Transition class presets
 */
export const transitions = {
  /** Standard all-properties transition */
  all: "transition duration-300",
  /** Fast all-properties transition */
  fast: "transition duration-150",
  /** Opacity transition */
  opacity: "transition-opacity duration-300",
  /** Transform transition */
  transform: "transition-transform duration-300",
  /** Colors transition */
  colors: "transition-colors duration-200",
} as const;
