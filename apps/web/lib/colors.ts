/**
 * Centralized color mapping for Tailwind gradient classes.
 * Used to extract Hex/RGB values for canvas drawing, SVG gradients, and dynamic styles.
 */

export interface ColorDefinition {
  from: string;
  to: string;
  primary: string; // The dominant color (usually 'from')
  rgb: string; // "R, G, B" for CSS variable usage
}

export const TAILWIND_GRADIENTS: Record<string, ColorDefinition> = {
  // Flywheel Tools
  "from-sky-500 to-blue-600": {
    from: "#0ea5e9",
    to: "#2563eb",
    primary: "#0ea5e9",
    rgb: "56, 189, 248", // sky-400 equivalent for glows
  },
  "from-amber-500 to-orange-600": {
    from: "#f59e0b",
    to: "#ea580c",
    primary: "#f59e0b",
    rgb: "251, 191, 36", // amber-400
  },
  "from-violet-500 to-purple-600": {
    from: "#8b5cf6",
    to: "#9333ea",
    primary: "#8b5cf6",
    rgb: "139, 92, 246", // violet-500
  },
  "from-emerald-500 to-teal-600": {
    from: "#10b981",
    to: "#0d9488",
    primary: "#10b981",
    rgb: "52, 211, 153", // emerald-400
  },
  "from-rose-500 to-red-600": {
    from: "#f43f5e",
    to: "#dc2626",
    primary: "#f43f5e",
    rgb: "244, 63, 94", // rose-500
  },
  "from-pink-500 to-fuchsia-600": {
    from: "#ec4899",
    to: "#c026d3",
    primary: "#ec4899",
    rgb: "236, 72, 153", // pink-500
  },
  "from-cyan-500 to-sky-600": {
    from: "#06b6d4",
    to: "#0284c7",
    primary: "#06b6d4",
    rgb: "34, 211, 238", // cyan-400
  },

  // Extra gradients
  "from-red-500 to-rose-600": {
    from: "#ef4444",
    to: "#e11d48",
    primary: "#ef4444",
    rgb: "239, 68, 68",
  },
  "from-slate-500 to-gray-600": {
    from: "#64748b",
    to: "#4b5563",
    primary: "#64748b",
    rgb: "100, 116, 139",
  },
  "from-blue-500 to-indigo-600": {
    from: "#3b82f6",
    to: "#4f46e5",
    primary: "#3b82f6",
    rgb: "59, 130, 246",
  },
  "from-green-500 to-emerald-600": {
    from: "#22c55e",
    to: "#059669",
    primary: "#22c55e",
    rgb: "34, 197, 94",
  },
  "from-orange-500 to-amber-600": {
    from: "#f97316",
    to: "#d97706",
    primary: "#f97316",
    rgb: "249, 115, 22",
  },
  "from-purple-500 to-violet-600": {
    from: "#a855f7",
    to: "#7c3aed",
    primary: "#a855f7",
    rgb: "168, 85, 247",
  },
};

const DEFAULT_COLOR: ColorDefinition = {
  from: "#8b5cf6",
  to: "#9333ea",
  primary: "#8b5cf6",
  rgb: "139, 92, 246",
};

/**
 * Get color definition for a Tailwind gradient class string.
 * Falls back to violet if not found.
 */
export function getColorDefinition(colorClass: string): ColorDefinition {
  // Try exact match
  if (TAILWIND_GRADIENTS[colorClass]) {
    return TAILWIND_GRADIENTS[colorClass];
  }

  // Try partial match (e.g. if class has extra spaces or slightly different format)
  const key = Object.keys(TAILWIND_GRADIENTS).find(k => colorClass.includes(k.split(" ")[0].replace("from-", "")));

  return key ? TAILWIND_GRADIENTS[key] : DEFAULT_COLOR;
}
