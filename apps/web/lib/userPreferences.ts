/**
 * User Preferences Storage
 *
 * Handles localStorage persistence of user choices during the wizard.
 * Uses TanStack Query for React state management with localStorage persistence.
 */

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useState } from "react";
import { safeGetItem, safeGetJSON, safeSetItem, safeSetJSON } from "./utils";
import type { WorkloadId } from "./vpsProviders";

export type OperatingSystem = "mac" | "windows" | "linux";
export type InstallMode = "vibe" | "safe";

export interface VPSReadinessSelection {
  providerId: string;
  planName: string;
  ubuntuVersion: string;
  region: string;
  targetAgents: number;
  workloadId: WorkloadId;
}

const OS_KEY = "agent-flywheel-user-os";
const VPS_IP_KEY = "agent-flywheel-vps-ip";
const INSTALL_MODE_KEY = "agent-flywheel-install-mode";
const SSH_USERNAME_KEY = "agent-flywheel-ssh-username";
export const ACFS_REF_KEY = "agent-flywheel-acfs-ref";
export const CREATE_VPS_CHECKLIST_KEY = "agent-flywheel-create-vps-checklist";
export const VPS_READINESS_SELECTION_KEY = "agent-flywheel-vps-readiness-selection";
const CHECKED_SERVICES_KEY = "agent-flywheel-checked-services";
export const CREATE_VPS_REQUIRED_CHECKLIST_ITEMS = [
  "ubuntu",
  "region",
  "password",
  "created",
] as const;
export type CreateVPSChecklistItemId = typeof CREATE_VPS_REQUIRED_CHECKLIST_ITEMS[number];

const OS_QUERY_KEY = "os";
const VPS_IP_QUERY_KEY = "ip";
const INSTALL_MODE_QUERY_KEY = "mode";
const SSH_USERNAME_QUERY_KEY = "user";
const ACFS_REF_QUERY_KEY = "ref";
const MAX_GIT_REF_LENGTH = 120;
const GIT_REF_SAFE_PATTERN = /^[A-Za-z0-9._/-]+$/;
const SSH_USERNAME_PATTERN = /^[a-z_][a-z0-9._-]*$/;
const USER_PREFERENCES_EVENT = "acfs:user-preferences-updated";
const WORKLOAD_IDS: readonly WorkloadId[] = ["light", "standard", "heavy"];

function normalizeStringList(values: unknown): string[] {
  if (!Array.isArray(values)) {
    return [];
  }

  const validValues = values.filter((value): value is string => typeof value === "string");
  return Array.from(new Set(validValues));
}

function normalizePreferenceString(value: unknown, fallback: string): string {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function normalizeTargetAgents(value: unknown): number {
  const parsedValue = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(parsedValue)) return 10;
  return Math.max(1, Math.floor(parsedValue));
}

function normalizeWorkloadId(value: unknown): WorkloadId {
  return WORKLOAD_IDS.includes(value as WorkloadId) ? (value as WorkloadId) : "standard";
}

function normalizeVPSReadinessSelection(value: unknown): VPSReadinessSelection | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const record = value as Partial<Record<keyof VPSReadinessSelection, unknown>>;
  return {
    providerId: normalizePreferenceString(record.providerId, "other"),
    planName: normalizePreferenceString(record.planName, "custom plan"),
    ubuntuVersion: normalizePreferenceString(record.ubuntuVersion, "25.10"),
    region: normalizePreferenceString(record.region, "not-listed"),
    targetAgents: normalizeTargetAgents(record.targetAgents),
    workloadId: normalizeWorkloadId(record.workloadId),
  };
}

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

function emitUserPreferencesUpdate() {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new Event(USER_PREFERENCES_EVENT));
}

/**
 * Subscribes a TanStack Query to external writes (other tabs, imperative setters).
 * Invalidates the query whenever localStorage or URL params change externally.
 */
function usePreferenceSync(queryKey: readonly string[]) {
  const queryClient = useQueryClient();
  useEffect(() => {
    if (typeof window === "undefined") return;
    const invalidate = () => {
      queryClient.invalidateQueries({ queryKey });
    };
    window.addEventListener(USER_PREFERENCES_EVENT, invalidate);
    window.addEventListener("storage", invalidate);
    window.addEventListener("popstate", invalidate);
    return () => {
      window.removeEventListener(USER_PREFERENCES_EVENT, invalidate);
      window.removeEventListener("storage", invalidate);
      window.removeEventListener("popstate", invalidate);
    };
  }, [queryClient, queryKey]);
}

/**
 * Normalize and validate a git ref used in generated shell commands.
 * Returns null when invalid/empty.
 */
export function normalizeGitRef(ref: string | null | undefined): string | null {
  const value = ref?.trim() ?? "";
  if (!value) return null;
  if (value.length > MAX_GIT_REF_LENGTH) return null;
  if (!GIT_REF_SAFE_PATTERN.test(value)) return null;
  if (value === "@" || value === "." || value === "..") return null;
  if (value.startsWith("-")) return null;
  if (value.startsWith(".")) return null;
  if (value.endsWith(".")) return null;
  if (value.startsWith("/") || value.endsWith("/")) return null;
  if (value.includes("//")) return null;
  if (value.includes("/.")) return null;
  if (value.includes("..")) return null;
  if (value.includes("@{")) return null;
  if (value === ".lock" || value.endsWith(".lock")) return null;
  if (value.split("/").includes("master")) return null;
  return value;
}

export function normalizeSSHUsername(username: string | null | undefined): string | null {
  const value = username?.trim() ?? "";
  if (!value) return null;
  if (!SSH_USERNAME_PATTERN.test(value)) return null;
  if (value === "root") return null;
  return value;
}

// Query keys for TanStack Query
export const userPreferencesKeys = {
  userOS: ["userPreferences", "os"] as const,
  vpsIP: ["userPreferences", "vpsIP"] as const,
  detectedOS: ["userPreferences", "detectedOS"] as const,
  installMode: ["userPreferences", "installMode"] as const,
  sshUsername: ["userPreferences", "sshUsername"] as const,
  acfsRef: ["userPreferences", "acfsRef"] as const,
  createVPSChecklist: ["userPreferences", "createVPSChecklist"] as const,
  vpsReadinessSelection: ["userPreferences", "vpsReadinessSelection"] as const,
  checkedServices: ["userPreferences", "checkedServices"] as const,
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
  if (storedOk || urlOk) {
    emitUserPreferencesUpdate();
  }
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
 * Get the user's VPS IP address from the URL fallback or localStorage.
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
 * Only keeps the IP in the URL when localStorage is unavailable.
 */
export function setVPSIP(ip: string): boolean {
  const normalized = ip.trim();
  if (!isValidIP(normalized)) {
    return false;
  }
  const storedOk = safeSetItem(VPS_IP_KEY, normalized);
  const urlOk = setQueryParam(VPS_IP_QUERY_KEY, storedOk ? null : normalized);
  if (storedOk || urlOk) {
    emitUserPreferencesUpdate();
  }
  return storedOk || urlOk;
}

export function getVPSReadinessSelection(): VPSReadinessSelection | null {
  return normalizeVPSReadinessSelection(safeGetJSON<unknown>(VPS_READINESS_SELECTION_KEY));
}

export function setVPSReadinessSelection(selection: VPSReadinessSelection): boolean {
  const normalized = normalizeVPSReadinessSelection(selection);
  if (!normalized) return false;

  const didPersist = safeSetJSON(VPS_READINESS_SELECTION_KEY, normalized);
  if (didPersist) {
    emitUserPreferencesUpdate();
  }
  return didPersist;
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
// Uses TanStack Query for SSR-safe reactive state backed by localStorage.
// Each hook returns [value, setter, loaded] to match the existing API.

/**
 * Hook to get and set the user's operating system.
 */
export function useUserOS(): [OperatingSystem | null, (os: OperatingSystem) => void, boolean] {
  const queryClient = useQueryClient();
  usePreferenceSync(userPreferencesKeys.userOS);

  const { data, status } = useQuery({
    queryKey: userPreferencesKeys.userOS,
    queryFn: getUserOS,
    staleTime: 0,
    gcTime: Infinity,
  });

  const setOS = useCallback((newOS: OperatingSystem) => {
    if (setUserOS(newOS)) {
      queryClient.setQueryData(userPreferencesKeys.userOS, getUserOS());
    }
  }, [queryClient]);

  return [data ?? null, setOS, status === "success"];
}

/**
 * Hook to get and set the VPS IP address.
 */
export function useVPSIP(): [string | null, (ip: string) => void, boolean] {
  const queryClient = useQueryClient();
  usePreferenceSync(userPreferencesKeys.vpsIP);

  const { data, status } = useQuery({
    queryKey: userPreferencesKeys.vpsIP,
    queryFn: getVPSIP,
    staleTime: 0,
    gcTime: Infinity,
  });

  const setIP = useCallback((newIP: string) => {
    const normalized = newIP.trim();
    if (setVPSIP(normalized)) {
      queryClient.setQueryData(userPreferencesKeys.vpsIP, getVPSIP());
    }
  }, [queryClient]);

  return [data ?? null, setIP, status === "success"];
}

export function useVPSReadinessSelection(): [
  VPSReadinessSelection | null,
  (selection: VPSReadinessSelection) => void,
  boolean,
] {
  const queryClient = useQueryClient();
  usePreferenceSync(userPreferencesKeys.vpsReadinessSelection);

  const { data, status } = useQuery({
    queryKey: userPreferencesKeys.vpsReadinessSelection,
    queryFn: getVPSReadinessSelection,
    staleTime: 0,
    gcTime: Infinity,
  });

  const setReadinessSelection = useCallback((selection: VPSReadinessSelection) => {
    const normalized = normalizeVPSReadinessSelection(selection);
    if (normalized && setVPSReadinessSelection(normalized)) {
      queryClient.setQueryData(userPreferencesKeys.vpsReadinessSelection, normalized);
    }
  }, [queryClient]);

  return [data ?? null, setReadinessSelection, status === "success"];
}

export function getCreateVPSChecklist(): string[] {
  return normalizeStringList(safeGetJSON<unknown[]>(CREATE_VPS_CHECKLIST_KEY));
}

export function isCreateVPSChecklistComplete(items: readonly string[]): boolean {
  const selectedItems = new Set(normalizeStringList(items));
  return CREATE_VPS_REQUIRED_CHECKLIST_ITEMS.every((item) => selectedItems.has(item));
}

export function setCreateVPSChecklist(items: string[]): boolean {
  const didPersist = safeSetJSON(CREATE_VPS_CHECKLIST_KEY, normalizeStringList(items));
  if (didPersist) {
    emitUserPreferencesUpdate();
  }
  return didPersist;
}

export function useCreateVPSChecklist(): [string[], (items: string[]) => void, boolean] {
  const queryClient = useQueryClient();
  usePreferenceSync(userPreferencesKeys.createVPSChecklist);

  const { data, status } = useQuery({
    queryKey: userPreferencesKeys.createVPSChecklist,
    queryFn: getCreateVPSChecklist,
    staleTime: 0,
    gcTime: Infinity,
  });

  const setChecklist = useCallback((items: string[]) => {
    const normalized = normalizeStringList(items);
    // Update the cache even when persistence fails (private browsing,
    // blocked storage): unlike OS/IP/steps there is no URL fallback for the
    // checklist, and dropping the update would leave the checkboxes
    // permanently unchecked and the step impossible to complete.
    setCreateVPSChecklist(normalized);
    queryClient.setQueryData(userPreferencesKeys.createVPSChecklist, normalized);
  }, [queryClient]);

  return [data ?? [], setChecklist, status === "success"];
}

// --- Checked Services (accounts wizard step) ---

export function getCheckedServices(): string[] {
  return normalizeStringList(safeGetJSON<unknown[]>(CHECKED_SERVICES_KEY));
}

export function setCheckedServices(serviceIds: string[]): boolean {
  const didPersist = safeSetJSON(CHECKED_SERVICES_KEY, normalizeStringList(serviceIds));
  if (didPersist) {
    emitUserPreferencesUpdate();
  }
  return didPersist;
}

export function useCheckedServices(): [string[], (serviceId: string) => void, boolean] {
  const queryClient = useQueryClient();
  usePreferenceSync(userPreferencesKeys.checkedServices);

  const { data, status } = useQuery({
    queryKey: userPreferencesKeys.checkedServices,
    queryFn: getCheckedServices,
    staleTime: 0,
    gcTime: Infinity,
  });

  const toggleService = useCallback((serviceId: string) => {
    const currentIds =
      queryClient.getQueryData<string[]>(userPreferencesKeys.checkedServices) ??
      getCheckedServices();
    const currentSet = new Set(currentIds);
    if (currentSet.has(serviceId)) {
      currentSet.delete(serviceId);
    } else {
      currentSet.add(serviceId);
    }
    const newIds = [...currentSet];
    if (setCheckedServices(newIds)) {
      queryClient.setQueryData(userPreferencesKeys.checkedServices, newIds);
    }
  }, [queryClient]);

  return [data ?? [], toggleService, status === "success"];
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

// --- Install Mode ---

export function getInstallMode(): InstallMode {
  const fromQuery = getQueryParam(INSTALL_MODE_QUERY_KEY);
  if (fromQuery === "vibe" || fromQuery === "safe") return fromQuery;
  const stored = safeGetItem(INSTALL_MODE_KEY);
  if (stored === "vibe" || stored === "safe") return stored;
  return "vibe";
}

export function setInstallMode(mode: InstallMode): boolean {
  const storedOk = safeSetItem(INSTALL_MODE_KEY, mode);
  const urlOk = setQueryParam(INSTALL_MODE_QUERY_KEY, mode);
  if (storedOk || urlOk) {
    emitUserPreferencesUpdate();
  }
  return storedOk || urlOk;
}

export function useInstallMode(): [InstallMode, (mode: InstallMode) => void, boolean] {
  const queryClient = useQueryClient();
  usePreferenceSync(userPreferencesKeys.installMode);

  const { data, status } = useQuery({
    queryKey: userPreferencesKeys.installMode,
    queryFn: getInstallMode,
    staleTime: 0,
    gcTime: Infinity,
  });

  const setMode = useCallback((newMode: InstallMode) => {
    if (setInstallMode(newMode)) {
      queryClient.setQueryData(userPreferencesKeys.installMode, getInstallMode());
    }
  }, [queryClient]);

  return [data ?? "vibe", setMode, status === "success"];
}

// --- SSH Username ---

export function getSSHUsername(): string {
  const fromQuery = normalizeSSHUsername(getQueryParam(SSH_USERNAME_QUERY_KEY));
  if (fromQuery) return fromQuery;
  const stored = normalizeSSHUsername(safeGetItem(SSH_USERNAME_KEY));
  if (stored) return stored;
  return "ubuntu";
}

export function setSSHUsername(username: string): boolean {
  const normalized = normalizeSSHUsername(username);
  if (!normalized) return false;
  const storedOk = safeSetItem(SSH_USERNAME_KEY, normalized);
  const urlOk = setQueryParam(SSH_USERNAME_QUERY_KEY, normalized === "ubuntu" ? null : normalized);
  if (storedOk || urlOk) {
    emitUserPreferencesUpdate();
  }
  return storedOk || urlOk;
}

export function useSSHUsername(): [string, (username: string) => void, boolean] {
  const queryClient = useQueryClient();
  usePreferenceSync(userPreferencesKeys.sshUsername);

  const { data, status } = useQuery({
    queryKey: userPreferencesKeys.sshUsername,
    queryFn: getSSHUsername,
    staleTime: 0,
    gcTime: Infinity,
  });

  const setUsername = useCallback((newUsername: string) => {
    if (setSSHUsername(newUsername)) {
      queryClient.setQueryData(userPreferencesKeys.sshUsername, getSSHUsername());
    }
  }, [queryClient]);

  return [data ?? "ubuntu", setUsername, status === "success"];
}

// --- ACFS Ref (git ref pin) ---

export function getACFSRef(): string | null {
  const fromQuery = normalizeGitRef(getQueryParam(ACFS_REF_QUERY_KEY));
  if (fromQuery) return fromQuery;
  return normalizeGitRef(safeGetItem(ACFS_REF_KEY));
}

export function setACFSRef(ref: string | null): boolean {
  const raw = ref?.trim() ?? "";
  if (raw && !normalizeGitRef(raw)) {
    return false;
  }
  const value = raw ? normalizeGitRef(raw) : null;
  const storedOk = value
    ? safeSetItem(ACFS_REF_KEY, value)
    : safeSetItem(ACFS_REF_KEY, "");
  const urlOk = setQueryParam(ACFS_REF_QUERY_KEY, value);
  if (storedOk || urlOk) {
    emitUserPreferencesUpdate();
  }
  return storedOk || urlOk;
}

export function useACFSRef(): [string | null, (ref: string | null) => void, boolean] {
  const queryClient = useQueryClient();
  usePreferenceSync(userPreferencesKeys.acfsRef);

  const { data, status } = useQuery({
    queryKey: userPreferencesKeys.acfsRef,
    queryFn: getACFSRef,
    staleTime: 0,
    gcTime: Infinity,
  });

  const setRef = useCallback((newRef: string | null) => {
    if (setACFSRef(newRef)) {
      queryClient.setQueryData(userPreferencesKeys.acfsRef, getACFSRef());
    }
  }, [queryClient]);

  return [data ?? null, setRef, status === "success"];
}
