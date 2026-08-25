import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import {
  containsIPAddress,
  looksLikeOpaqueCredential,
  normalizeGitRef,
  normalizeSSHUsername,
} from "./inputValidation"
import { manifestSelectionProfiles } from "./generated/manifest-modules"

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

const SENSITIVE_QUERY_KEYS = new Set([
  "accesstoken",
  "apikey",
  "code",
  "credential",
  "host",
  "hostname",
  "ip",
  "password",
  "privatekey",
  "refreshtoken",
  "secret",
  "token",
  "vpsip",
]);
const SENSITIVE_PATH_VALUE_KEYS = new Set([
  "accesstoken",
  "apikey",
  "credential",
  "password",
  "privatekey",
  "refreshtoken",
  "secret",
  "token",
  "vpsip",
]);
const CAMPAIGN_QUERY_KEYS = new Set([
  "utm_campaign",
  "utm_content",
  "utm_medium",
  "utm_source",
  "utm_term",
]);
const SAFE_PROFILE_QUERY_VALUES = new Set(
  manifestSelectionProfiles.filter((profile) => !profile.mode).map((profile) => profile.id),
);

function normalizedQueryKey(key: string): string {
  return key.replace(/[^a-z0-9]/gi, "").toLowerCase();
}

function queryValueContainsHost(value: string): boolean {
  return containsIPAddress(value);
}

function queryValueContainsCredential(
  value: string,
  allowGitObjectId = false,
): boolean {
  if (/-----begin [a-z ]*private key-----/i.test(value)) return true;
  if (/\bbearer\s+\S+/i.test(value)) return true;
  if (looksLikeOpaqueCredential(value, allowGitObjectId)) return true;
  try {
    const parsed = new URL(value);
    if ((parsed.protocol === "http:" || parsed.protocol === "https:")
      && (parsed.username.length > 0 || parsed.password.length > 0)) {
      return true;
    }
  } catch {
    // Non-URL query values are validated by their field-specific grammar below.
  }
  return false;
}

function urlPayloadContainsSensitiveState(value: string): boolean {
  let decoded = value;
  for (let pass = 0; pass < 4; pass += 1) {
    if (!/%[0-9A-Fa-f]{2}/.test(decoded)) break;
    try {
      const next = decodeURIComponent(decoded);
      if (next === decoded) break;
      decoded = next;
    } catch {
      return true;
    }
  }
  // More deeply nested escapes remain recoverable by a downstream consumer;
  // do not call them safe merely because our bounded decoder stopped first.
  if (/%[0-9A-Fa-f]{2}/.test(decoded)) return true;
  if (containsIPAddress(decoded)) return true;
  if (/-----begin [a-z ]*private key-----/i.test(decoded)) return true;
  if (/\bbearer\s+\S+/i.test(decoded)) return true;

  const segments = decoded
    .split(/[\/#?&;]/)
    .filter(Boolean);
  for (let index = 0; index < segments.length; index += 1) {
    const segment = segments[index];
    const assignmentIndex = segment.indexOf("=");
    if (
      assignmentIndex > 0
      && SENSITIVE_QUERY_KEYS.has(normalizedQueryKey(segment.slice(0, assignmentIndex)))
    ) return true;
    if (
      SENSITIVE_PATH_VALUE_KEYS.has(normalizedQueryKey(segment))
      && index + 1 < segments.length
    ) return true;
    if (looksLikeOpaqueCredential(segment)) return true;
  }
  return false;
}

function isSafeQueryEntry(key: string, value: string): boolean {
  if (SENSITIVE_QUERY_KEYS.has(normalizedQueryKey(key))) return false;
  if (
    queryValueContainsHost(value)
    || queryValueContainsCredential(value, key === "ref")
  ) return false;

  switch (key) {
    case "os":
      return value === "mac" || value === "windows" || value === "linux";
    case "mode":
      return value === "vibe" || value === "safe";
    case "profile":
      return SAFE_PROFILE_QUERY_VALUES.has(value);
    case "user":
      return normalizeSSHUsername(value) === value;
    case "ref":
      return normalizeGitRef(value) === value;
    case "steps":
      return value.length <= 80 && /^(?:[1-9][0-9]?)(?:,[1-9][0-9]?)*$/.test(value);
    case "from":
      return value === "verify-key-connection" || value === "launch-onboarding";
    default:
      return CAMPAIGN_QUERY_KEYS.has(key)
        && value.length <= 120
        && /^[A-Za-z0-9 ._~/-]*$/.test(value);
  }
}

/** Return true when a query string carries host or credential material. */
export function queryContainsSensitiveState(search: string): boolean {
  const params = new URLSearchParams(search);
  return Array.from(params.entries()).some(([key, value]) => !isSafeQueryEntry(key, value));
}

/** Project a query string onto the validated fields that navigation may propagate. */
export function stripSensitiveQueryState(search: string): string {
  const params = new URLSearchParams(search);
  const safeParams = new URLSearchParams();
  for (const [key, value] of params.entries()) {
    if (isSafeQueryEntry(key, value)) {
      safeParams.append(key, value);
    }
  }
  return safeParams.toString();
}

/** Detect sensitive material anywhere a browser or vendor can observe it. */
export function urlContainsSensitiveState(
  value: string | URL,
  base?: string | URL,
): boolean {
  try {
    const parsed = typeof base === "undefined"
      ? new URL(value.toString())
      : new URL(value.toString(), base);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return true;
    if (parsed.username || parsed.password) return true;
    return containsIPAddress(parsed.hostname)
      || queryContainsSensitiveState(parsed.search)
      || urlPayloadContainsSensitiveState(parsed.pathname)
      || urlPayloadContainsSensitiveState(parsed.hash);
  } catch {
    return true;
  }
}

/**
 * Sanitize a same-origin History API destination before it reaches the address
 * bar. Cross-origin and already-safe destinations are returned unchanged.
 */
export interface SanitizedNavigation {
  value: string | null | undefined;
  sensitiveStateDetected: boolean;
  sensitiveStateRemoved: boolean;
}

/**
 * Snapshot and classify a History API destination with exactly one coercion.
 * Returning the original URL-like object would let a stateful `toString()`
 * produce different bytes during validation and native History processing.
 */
export function inspectSensitiveNavigationUrl(
  value: string | URL | null | undefined,
  currentHref: string,
): SanitizedNavigation {
  if (value === null || typeof value === "undefined") {
    const current = inspectSensitiveNavigationUrl(currentHref, currentHref);
    if (current.sensitiveStateRemoved) return current;
    return {
      value,
      sensitiveStateDetected: current.sensitiveStateDetected,
      sensitiveStateRemoved: false,
    };
  }

  // Deliberately outside the URL parse try/catch: native History also exposes
  // coercion failures, and retrying a hostile object would create a TOCTOU gap.
  const runtimeValue: unknown = value;
  if (typeof runtimeValue === "symbol") {
    throw new TypeError("History URL cannot be a Symbol");
  }
  const serialized = typeof runtimeValue === "string"
    ? runtimeValue
    : String(runtimeValue);
  try {
    const current = new URL(currentHref);
    const candidate = new URL(serialized, current);
    if (candidate.origin !== current.origin) {
      return {
        value: serialized,
        sensitiveStateDetected: urlContainsSensitiveState(candidate),
        sensitiveStateRemoved: false,
      };
    }

    const sensitiveQuery = queryContainsSensitiveState(candidate.search);
    const sensitivePath = urlPayloadContainsSensitiveState(candidate.pathname);
    const sensitiveHash = urlPayloadContainsSensitiveState(candidate.hash);
    const sensitiveCredentials = Boolean(candidate.username) || Boolean(candidate.password);
    const sensitiveHost = containsIPAddress(candidate.hostname);
    if (sensitiveQuery) candidate.search = stripSensitiveQueryState(candidate.search);
    if (sensitivePath) candidate.pathname = "/";
    if (sensitiveHash) candidate.hash = "";
    if (sensitiveCredentials) {
      candidate.username = "";
      candidate.password = "";
    }

    const sensitiveStateRemoved = sensitiveQuery
      || sensitivePath
      || sensitiveHash
      || sensitiveCredentials;
    return {
      value: sensitiveStateRemoved ? candidate.toString() : serialized,
      sensitiveStateDetected: sensitiveHost || sensitiveStateRemoved,
      sensitiveStateRemoved,
    };
  } catch {
    // Preserve native History semantics for syntactically invalid destinations,
    // but pass the already-coerced snapshot rather than touching the object again.
    return {
      value: serialized,
      sensitiveStateDetected: true,
      sensitiveStateRemoved: false,
    };
  }
}

export function sanitizeSensitiveNavigationUrl(
  value: string | URL | null | undefined,
  currentHref: string,
): string | null | undefined {
  return inspectSensitiveNavigationUrl(value, currentHref).value;
}

/** Wizard documents can render operator hosts and must not share a runtime with recorders. */
export function isPrivateWizardPath(pathname: string): boolean {
  return pathname === "/wizard" || pathname.startsWith("/wizard/");
}

/** Validate both queued-event and live browser URLs before a vendor send. */
export function vendorEventIsPrivacySafe(eventUrl: string, liveHref: string): boolean {
  try {
    const live = new URL(liveHref);
    const event = new URL(eventUrl, live);
    return event.origin === live.origin
      && !urlContainsSensitiveState(event)
      && !urlContainsSensitiveState(live)
      && !isPrivateWizardPath(event.pathname)
      && !isPrivateWizardPath(live.pathname);
  } catch {
    return false;
  }
}

/**
 * Append non-sensitive current URL state to a path.
 * Host addresses and credential fields never belong in navigation URLs.
 */
export function withCurrentSearch(path: string): string {
  if (typeof window === "undefined") return path;
  try {
    const current = new URL(window.location.href);
    const inspected = inspectSensitiveNavigationUrl(path, current.href);
    if (typeof inspected.value !== "string") return path;
    const destination = new URL(inspected.value, current);
    if (destination.origin !== current.origin) return inspected.value;

    const merged = new URLSearchParams(stripSensitiveQueryState(current.search));
    const explicit = new URLSearchParams(stripSensitiveQueryState(destination.search));
    for (const [key, value] of explicit.entries()) {
      merged.delete(key);
      merged.append(key, value);
    }
    destination.search = merged.toString();
    return `${destination.pathname}${destination.search}${destination.hash}`;
  } catch {
    return path;
  }
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

/**
 * Copy text to the clipboard with a DOM fallback for browsers where the
 * async clipboard API is unavailable or blocked.
 */
export async function copyTextToClipboard(text: string): Promise<boolean> {
  if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text)
      return true
    } catch {
      // Fall through to the DOM-based fallback below.
    }
  }

  if (typeof document === "undefined") {
    return false
  }

  const textarea = document.createElement("textarea")
  textarea.value = text
  textarea.setAttribute("readonly", "")
  textarea.style.position = "fixed"
  textarea.style.top = "0"
  textarea.style.left = "-9999px"
  textarea.style.opacity = "0"
  document.body.appendChild(textarea)

  try {
    textarea.focus()
    textarea.select()
    textarea.setSelectionRange(0, textarea.value.length)
    return document.execCommand("copy")
  } catch {
    return false
  } finally {
    document.body.removeChild(textarea)
  }
}

/**
 * Returns true when a keyboard event target is an interactive control.
 * Global shortcuts should not fire while the user is focused inside real UI controls.
 */
export function isInteractiveKeyboardTarget(target: EventTarget | null): boolean {
  if (!(target instanceof Element)) {
    return false;
  }

  if (
    target instanceof HTMLInputElement ||
    target instanceof HTMLTextAreaElement ||
    target instanceof HTMLSelectElement ||
    target instanceof HTMLButtonElement ||
    target instanceof HTMLAnchorElement
  ) {
    return true;
  }

  if (target instanceof HTMLElement && target.isContentEditable) {
    return true;
  }

  return target.closest(
    'button, a, input, textarea, select, summary, [role="button"], [role="link"], [role="menuitem"], [contenteditable="true"]'
  ) !== null;
}
