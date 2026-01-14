/**
 * Shared utilities for OG image generation
 *
 * Provides reusable constants, types, and helper functions for consistent
 * Open Graph and Twitter card images across all pages.
 */

// Image dimensions
export const OG_SIZE = { width: 1200, height: 630 };
export const TWITTER_SIZE = { width: 1200, height: 600 };

// Section color themes
export const SECTION_COLORS = {
  home: {
    primary: "#22d3ee", // cyan
    secondary: "#a855f7", // purple
    tertiary: "#f472b6", // pink
  },
  wizard: {
    primary: "#f59e0b", // amber
    secondary: "#fb923c", // orange
    tertiary: "#fbbf24", // yellow
  },
  tldr: {
    primary: "#22d3ee", // cyan
    secondary: "#a855f7", // purple
    tertiary: "#f472b6", // pink
  },
  learn: {
    primary: "#22d3ee", // cyan
    secondary: "#a855f7", // purple
    tertiary: "#f472b6", // pink
  },
  flywheel: {
    primary: "#a855f7", // purple
    secondary: "#22d3ee", // cyan
    tertiary: "#f472b6", // pink
  },
  glossary: {
    primary: "#0ea5e9", // sky
    secondary: "#22d3ee", // cyan
    tertiary: "#06b6d4", // teal
  },
  troubleshooting: {
    primary: "#facc15", // yellow
    secondary: "#f59e0b", // amber
    tertiary: "#fb923c", // orange
  },
  docs: {
    primary: "#6366f1", // indigo
    secondary: "#3b82f6", // blue
    tertiary: "#8b5cf6", // violet
  },
  security: {
    primary: "#6366f1", // indigo
    secondary: "#22c55e", // green
    tertiary: "#10b981", // emerald
  },
} as const;

// Lesson category colors
export const LESSON_COLORS: Record<string, string> = {
  welcome: "#22d3ee", // cyan
  linux: "#22d3ee", // cyan
  ssh: "#a855f7", // purple
  tmux: "#f472b6", // pink
  git: "#22c55e", // green
  github: "#22c55e", // green
  agent: "#f59e0b", // orange
  ntm: "#3b82f6", // blue
  flywheel: "#ec4899", // pink
  update: "#14b8a6", // teal
  ubs: "#ef4444", // red
  mail: "#8b5cf6", // violet
  cass: "#22d3ee", // cyan
  cm: "#d946ef", // fuchsia
  beads: "#10b981", // emerald
  slb: "#f59e0b", // amber
  dcg: "#ef4444", // red
  ru: "#6366f1", // indigo
  case: "#8b5cf6", // violet
  default: "#22d3ee", // cyan
};

// Get color for a lesson based on its slug
export function getLessonColor(slug: string): string {
  // Check for direct match
  if (LESSON_COLORS[slug]) {
    return LESSON_COLORS[slug];
  }

  // Check for partial matches
  for (const [key, color] of Object.entries(LESSON_COLORS)) {
    if (slug.includes(key)) {
      return color;
    }
  }

  return LESSON_COLORS.default;
}

// Tool colors based on gradient from tool-data.tsx
export const TOOL_COLORS: Record<string, { primary: string; secondary: string }> = {
  "claude-code": { primary: "#fb923c", secondary: "#f59e0b" },
  "codex-cli": { primary: "#34d399", secondary: "#10b981" },
  "gemini-cli": { primary: "#6366f1", secondary: "#3b82f6" },
  ntm: { primary: "#38bdf8", secondary: "#0ea5e9" },
  beads: { primary: "#34d399", secondary: "#10b981" },
  "agent-mail": { primary: "#8b5cf6", secondary: "#a855f7" },
  ubs: { primary: "#f43f5e", secondary: "#ef4444" },
  cass: { primary: "#22d3ee", secondary: "#06b6d4" },
  cm: { primary: "#d946ef", secondary: "#c026d3" },
  caam: { primary: "#fb923c", secondary: "#f59e0b" },
  slb: { primary: "#fbbf24", secondary: "#f59e0b" },
  dcg: { primary: "#f43f5e", secondary: "#ef4444" },
  ru: { primary: "#6366f1", secondary: "#3b82f6" },
};

// Common background gradient
export const DARK_GRADIENT =
  "linear-gradient(145deg, #0a0a12 0%, #0f1419 40%, #0d1117 70%, #0a0a12 100%)";

// Grid pattern SVG (URL encoded)
export const GRID_PATTERN = (color: string = "#22d3ee") =>
  `url("data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='${encodeURIComponent(color)}' stroke-width='0.5'%3E%3Cpath d='M0 20h40M20 0v40'/%3E%3C/g%3E%3C/svg%3E")`;

// Generate gradient accent line colors
export function getAccentGradient(
  colors: { primary: string; secondary: string; tertiary: string }
): string {
  return `linear-gradient(90deg, transparent 0%, ${colors.primary} 25%, ${colors.secondary} 50%, ${colors.tertiary} 75%, transparent 100%)`;
}

// Generate orb radial gradient
export function getOrbGradient(color: string, opacity: number = 0.15): string {
  // Convert hex to rgba
  const r = parseInt(color.slice(1, 3), 16);
  const g = parseInt(color.slice(3, 5), 16);
  const b = parseInt(color.slice(5, 7), 16);
  return `radial-gradient(circle, rgba(${r},${g},${b},${opacity}) 0%, transparent 60%)`;
}
