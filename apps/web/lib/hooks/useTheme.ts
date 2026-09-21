"use client";

/**
 * Theme management hook for dark/light mode toggle.
 *
 * Supports three modes: "dark", "light", "system" (follows OS preference).
 * Persists choice to localStorage. On first visit, defaults to "dark"
 * since this is a developer-focused tool.
 *
 * The actual class toggle happens via an inline <script> in layout.tsx
 * to prevent flash. This hook syncs React state with that script's behavior.
 *
 * @see bd-331g
 */

import { useCallback, useEffect, useSyncExternalStore } from "react";
import { safeGetItem, safeSetItem } from "@/lib/utils";

export type ThemeMode = "dark" | "light" | "system";
export type ResolvedTheme = "dark" | "light";

const STORAGE_KEY = "acfs-theme";

/** Resolve "system" to the actual OS preference. */
function resolveTheme(mode: ThemeMode): ResolvedTheme {
  if (mode === "system") {
    if (typeof window === "undefined") return "dark";
    return window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
  }
  return mode;
}

/** Read the stored theme mode from localStorage. */
function getStoredMode(): ThemeMode {
  const stored = safeGetItem(STORAGE_KEY);
  if (stored === "dark" || stored === "light" || stored === "system") {
    return stored;
  }
  return "dark";
}

/** Apply theme to the document (toggle dark/light classes). */
function applyTheme(resolved: ResolvedTheme): void {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  if (resolved === "dark") {
    root.classList.add("dark");
    root.classList.remove("light");
  } else {
    root.classList.remove("dark");
    root.classList.add("light");
  }
}

// --- External store for useSyncExternalStore ---
type Listener = () => void;
const listeners = new Set<Listener>();

function subscribe(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function notify(): void {
  for (const listener of listeners) listener();
}

function getSnapshot(): ThemeMode {
  return getStoredMode();
}

function getServerSnapshot(): ThemeMode {
  return "dark";
}

/**
 * Hook that provides theme mode and a setter.
 *
 * Returns:
 * - `mode` — the stored preference ("dark" | "light" | "system")
 * - `resolved` — the actual applied theme ("dark" | "light")
 * - `setMode(mode)` — update the theme
 * - `cycle()` — cycle through dark → light → system → dark
 */
export function useTheme() {
  const mode = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  const resolved = resolveTheme(mode);

  const setMode = useCallback((newMode: ThemeMode) => {
    safeSetItem(STORAGE_KEY, newMode);
    applyTheme(resolveTheme(newMode));
    notify();
  }, []);

  const cycle = useCallback(() => {
    const current = getStoredMode();
    const next: ThemeMode = current === "dark" ? "light" : current === "light" ? "system" : "dark";
    setMode(next);
  }, [setMode]);

  // Listen for OS preference changes when in "system" mode
  useEffect(() => {
    const mql = window.matchMedia("(prefers-color-scheme: light)");
    const handler = () => {
      if (getStoredMode() === "system") {
        applyTheme(resolveTheme("system"));
        notify();
      }
    };
    mql.addEventListener("change", handler);
    return () => mql.removeEventListener("change", handler);
  }, []);

  // Sync on mount (in case the inline script and React get out of sync)
  useEffect(() => {
    applyTheme(resolved);
  }, [resolved]);

  return { mode, resolved, setMode, cycle } as const;
}
