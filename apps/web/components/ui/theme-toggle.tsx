"use client";

/**
 * ThemeToggle — Cycles between dark, light, and system theme modes.
 *
 * Shows a sun/moon/monitor icon depending on the current mode.
 * Click to cycle: dark → light → system → dark.
 *
 * @see bd-331g
 */

import { Moon, Sun, Monitor } from "lucide-react";
import { useTheme, type ThemeMode } from "@/lib/hooks/useTheme";
import { cn } from "@/lib/utils";

const MODE_CONFIG: Record<ThemeMode, { icon: typeof Moon; label: string }> = {
  dark: { icon: Moon, label: "Dark mode (click for light)" },
  light: { icon: Sun, label: "Light mode (click for system)" },
  system: { icon: Monitor, label: "System theme (click for dark)" },
};

interface ThemeToggleProps {
  className?: string;
}

export function ThemeToggle({ className }: ThemeToggleProps) {
  const { mode, cycle } = useTheme();
  const { icon: Icon, label } = MODE_CONFIG[mode];

  return (
    <button
      type="button"
      onClick={cycle}
      className={cn(
        // 44px touch target for Apple HIG compliance
        "flex h-11 w-11 items-center justify-center rounded-xl",
        "text-muted-foreground transition-all duration-200",
        "hover:bg-muted hover:text-foreground hover:scale-105",
        "active:scale-95",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
        className
      )}
      aria-label={label}
      title={label}
    >
      <Icon className="h-5 w-5" />
    </button>
  );
}
