import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/**
 * Safe localStorage access utilities.
 * Handles cases where localStorage is unavailable (SSR, private browsing, quota exceeded).
 */

/**
 * Safely get an item from localStorage.
 * Returns null if localStorage is unavailable or the key doesn't exist.
 */
export function safeGetItem(key: string): string | null {
  if (typeof window === "undefined") return null;
  try {
    return localStorage.getItem(key);
  } catch {
    // localStorage unavailable (private browsing, quota exceeded, etc.)
    return null;
  }
}

/**
 * Safely set an item in localStorage.
 * Silently fails if localStorage is unavailable.
 */
export function safeSetItem(key: string, value: string): boolean {
  if (typeof window === "undefined") return false;
  try {
    localStorage.setItem(key, value);
    return true;
  } catch {
    // localStorage unavailable or quota exceeded
    return false;
  }
}

/**
 * Append the current URL query string to a path.
 * Useful for preserving wizard state when localStorage is unavailable.
 */
export function withCurrentSearch(path: string): string {
  if (typeof window === "undefined") return path;
  const search = window.location.search;
  if (!search) return path;
  return path.includes("?") ? `${path}&${search.slice(1)}` : `${path}${search}`;
}

/**
 * Safely remove an item from localStorage.
 */
export function safeRemoveItem(key: string): boolean {
  if (typeof window === "undefined") return false;
  try {
    localStorage.removeItem(key);
    return true;
  } catch {
    return false;
  }
}

/**
 * Safely parse JSON from localStorage.
 * Returns null if parsing fails or value doesn't exist.
 */
export function safeGetJSON<T>(key: string): T | null {
  const value = safeGetItem(key);
  if (!value) return null;
  try {
    return JSON.parse(value) as T;
  } catch {
    // Invalid JSON
    return null;
  }
}

/**
 * Safely store JSON in localStorage.
 */
export function safeSetJSON(key: string, value: unknown): boolean {
  try {
    return safeSetItem(key, JSON.stringify(value));
  } catch {
    // JSON.stringify failed (circular reference, etc.)
    return false;
  }
}
