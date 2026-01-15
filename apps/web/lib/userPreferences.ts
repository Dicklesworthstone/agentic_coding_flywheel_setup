/**
 * User Preferences Storage
 *
 * Handles localStorage persistence of user choices during the wizard.
 * Uses TanStack Query for React state management with localStorage persistence.
 */

import { useQuery } from "@tanstack/react-query";
import { useCallback, useEffect, useState } from "react";
import { safeGetItem, safeSetItem } from "./utils";

export type OperatingSystem = "mac" | "windows" | "linux";

const OS_KEY = "agent-flywheel-user-os";
const VPS_IP_KEY = "agent-flywheel-vps-ip";
const OS_QUERY_KEY = "os";
const VPS_IP_QUERY_KEY = "ip";

function getQueryParam(key: string): string | null {
  if (typeof window === "undefined") return null;
  try {
    return new URLSearchParams(window.location.search).get(key);
  } catch {
    return null;
  }
}

function setQueryParam(key: string, value: string | null): boolean {
  if (typeof window === "undefined") return false;
  try {
    const url = new URL(window.location.href);
    if (value === null || value === "") {
      url.searchParams.delete(key);
    } else {
      url.searchParams.set(key, value);
    }
    window.history.replaceState(window.history.state, "", url.toString());
    return true;
  } catch {
    return false;
  }
}

// Query keys for TanStack Query
export const userPreferencesKeys = {
  userOS: ["userPreferences", "os"] as const,
  vpsIP: ["userPreferences", "vpsIP"] as const,
  detectedOS: ["userPreferences", "detectedOS"] as const,
};

/**
 * Get the user's selected operating system from localStorage.
 */
export function getUserOS(): OperatingSystem | null {
  const fromQuery = getQueryParam(OS_QUERY_KEY);
  if (fromQuery === "mac" || fromQuery === "windows" || fromQuery === "linux") {
    return fromQuery;
  }
  const stored = safeGetItem(OS_KEY);
  if (stored === "mac" || stored === "windows" || stored === "linux") {
    return stored;
  }
  return null;
}

/**
 * Save the user's operating system selection to localStorage.
 */
export function setUserOS(os: OperatingSystem): boolean {
  const storedOk = safeSetItem(OS_KEY, os);
  const urlOk = setQueryParam(OS_QUERY_KEY, os);
  return storedOk || urlOk;
}

/**
 * Detect the user's OS from the browser's user agent.
 * Returns null if detection fails or on server-side.
 */
export function detectOS(): OperatingSystem | null {
  if (typeof window === "undefined") return null;

  const ua = navigator.userAgent.toLowerCase();

  // If the user is on a phone/tablet, we can't reliably infer the OS of the
  // computer they'll use for the terminal/VPS steps. Force an explicit choice.
  if (ua.includes("iphone") || ua.includes("ipad") || ua.includes("ipod") || ua.includes("android")) {
    return null;
  }

  if (ua.includes("win")) return "windows";

  // Detect Linux before Mac to avoid false positives
  if (ua.includes("linux") && !ua.includes("android")) return "linux";

  // Avoid mis-detecting iOS user agents that contain "like Mac OS X".
  if (ua.includes("mac") && !ua.includes("like mac os x")) return "mac";
  return null;
}

/**
 * Get the user's VPS IP address from localStorage.
 */
export function getVPSIP(): string | null {
  const fromQuery = getQueryParam(VPS_IP_QUERY_KEY);
  if (fromQuery && isValidIP(fromQuery)) {
    return fromQuery.trim();
  }

  const stored = safeGetItem(VPS_IP_KEY);
  if (stored && isValidIP(stored)) {
    return stored.trim();
  }

  return null;
}

/**
 * Save the user's VPS IP address to localStorage.
 * Only saves if the IP is valid to prevent storing malformed data.
 * Returns true if saved successfully, false otherwise.
 */
export function setVPSIP(ip: string): boolean {
  const normalized = ip.trim();
  if (!isValidIP(normalized)) {
    return false;
  }
  const storedOk = safeSetItem(VPS_IP_KEY, normalized);
  const urlOk = setQueryParam(VPS_IP_QUERY_KEY, normalized);
  return storedOk || urlOk;
}

/**
 * Validate an IP address (IPv4 or IPv6).
 *
 * For VPS addresses intended for remote SSH connections, zone IDs (like %eth0)
 * are rejected since they only make sense for local link-local addresses.
 */
export function isValidIP(ip: string): boolean {
  const normalized = ip.trim();

  // IPv4 validation
  const ipv4Pattern = /^(\d{1,3}\.){3}\d{1,3}$/;
  if (ipv4Pattern.test(normalized)) {
    const parts = normalized.split(".");
    return parts.every((part) => {
      const num = parseInt(part, 10);
      return num >= 0 && num <= 255;
    });
  }

  // Reject IPv6 addresses with zone IDs (e.g., %eth0, %br-abc123)
  // Zone IDs are only meaningful for link-local addresses on local interfaces,
  // not for remote VPS connections over the internet.
  if (normalized.includes("%")) {
    return false;
  }

  // IPv6 validation (full, compressed, and mixed formats)
  // Matches: 2001:db8::1, ::1, 2001:db8:85a3::8a2e:370:7334, etc.
  const ipv6Pattern = /^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|::(ffff(:0{1,4})?:)?((25[0-5]|(2[0-4]|1?[0-9])?[0-9])\.){3}(25[0-5]|(2[0-4]|1?[0-9])?[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1?[0-9])?[0-9])\.){3}(25[0-5]|(2[0-4]|1?[0-9])?[0-9]))$/;

  return ipv6Pattern.test(normalized);
}

// --- React Hooks for User Preferences ---
// Using local state + effects for SSR-safe localStorage access.
// Also provides a `loaded` boolean so callers can avoid redirect races.

/**
 * Hook to get and set the user's operating system.
 * Uses SSR-safe localStorage loading + an explicit `loaded` flag.
 */
export function useUserOS(): [OperatingSystem | null, (os: OperatingSystem) => void, boolean] {
  const [userOSState, setUserOSState] = useState<{
    os: OperatingSystem | null;
    loaded: boolean;
  }>({ os: null, loaded: false });

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- localStorage access must happen after mount (SSR-safe)
    setUserOSState({ os: getUserOS(), loaded: true });
  }, []);

  const setOS = useCallback((newOS: OperatingSystem) => {
    // Only update React state if storage operation succeeds
    if (setUserOS(newOS)) {
      setUserOSState({ os: newOS, loaded: true });
    }
  }, []);

  return [userOSState.os, setOS, userOSState.loaded];
}

/**
 * Hook to get and set the VPS IP address.
 * Uses SSR-safe localStorage loading + an explicit `loaded` flag.
 */
export function useVPSIP(): [string | null, (ip: string) => void, boolean] {
  const [vpsIPState, setVpsIPState] = useState<{
    ip: string | null;
    loaded: boolean;
  }>({ ip: null, loaded: false });

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- localStorage access must happen after mount (SSR-safe)
    setVpsIPState({ ip: getVPSIP(), loaded: true });
  }, []);

  const setIP = useCallback((newIP: string) => {
    const normalized = newIP.trim();
    if (setVPSIP(normalized)) {
      setVpsIPState({ ip: normalized, loaded: true });
    }
  }, []);

  return [vpsIPState.ip, setIP, vpsIPState.loaded];
}

/**
 * Hook to get the detected OS (from user agent).
 * Only runs on client side.
 */
export function useDetectedOS(): OperatingSystem | null {
  const { data: detectedOS } = useQuery({
    queryKey: userPreferencesKeys.detectedOS,
    queryFn: detectOS,
    staleTime: Infinity,
    gcTime: Infinity,
  });

  return detectedOS ?? null;
}

/**
 * Hook to track if the component is mounted (client-side hydrated).
 * Returns true on client, false on server.
 */
export function useMounted(): boolean {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- hydration detection
    setMounted(true);
  }, []);

  return mounted;
}
