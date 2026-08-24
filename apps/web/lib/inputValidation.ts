const MAX_GIT_REF_LENGTH = 120;
const MAX_SSH_USERNAME_LENGTH = 32;
const GIT_REF_SAFE_PATTERN = /^[A-Za-z0-9._/-]+$/;
const SSH_USERNAME_PATTERN = /^[a-z_][a-z0-9._-]*$/;

function shannonEntropy(value: string): number {
  if (value.length === 0) return 0;
  const counts = new Map<string, number>();
  for (const character of value) {
    counts.set(character, (counts.get(character) ?? 0) + 1);
  }
  let entropy = 0;
  for (const count of counts.values()) {
    const probability = count / value.length;
    entropy -= probability * Math.log2(probability);
  }
  return entropy;
}

/** Detect known or high-entropy credential material accepted by Git-ref grammar. */
export function looksLikeOpaqueCredential(
  value: string,
  allowGitObjectId = false,
): boolean {
  // Public abbreviated/full SHA-1 and full SHA-256 object IDs are legitimate refs.
  if (allowGitObjectId && /^(?:[a-f0-9]{7,40}|[a-f0-9]{64})$/i.test(value)) {
    return false;
  }

  if (/(?:^|[^A-Za-z0-9])(?:hvs|hvb|hvr)\.[A-Za-z0-9_-]{20,}(?:$|[^A-Za-z0-9_-])/i.test(value)) {
    return true;
  }
  if (/(?:^|[^A-Za-z0-9])(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]{20,}(?:$|[^A-Za-z0-9_])/.test(value)) {
    return true;
  }
  if (/(?:^|[^A-Za-z0-9])sk-(?:proj-)?[A-Za-z0-9_-]{20,}(?:$|[^A-Za-z0-9_-])/.test(value)) {
    return true;
  }
  if (/(?:^|[^A-Za-z0-9])npm_[A-Za-z0-9]{36,}(?:$|[^A-Za-z0-9])/i.test(value)) {
    return true;
  }
  if (/(?:^|[^A-Za-z0-9])(?:glpat-|sbp_|shpat_|xox[baprs]-|sk_(?:live|test)_|rk_(?:live|test)_)[A-Za-z0-9_-]{16,}/i.test(value)) {
    return true;
  }
  if (/\bAKIA[A-Z0-9]{16}\b/.test(value) || /\bAIza[0-9A-Za-z_-]{30,}\b/.test(value)) {
    return true;
  }
  if (/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/.test(value)) {
    return true;
  }

  const slashSegments = value.split("/");
  const credentialCandidates = slashSegments.length > 1
    ? [...slashSegments, slashSegments.join("")]
    : slashSegments;
  for (const segment of credentialCandidates) {
    if (segment.length < 32 || !/^[A-Za-z0-9+_.=-]+$/.test(segment)) continue;
    const compact = segment.replace(/[+_.=-]/g, "");
    if (compact.length < 28 || !/[A-Za-z]/.test(compact)) {
      continue;
    }
    const digitCount = (compact.match(/\d/g) ?? []).length;
    const hasMixedCase = /[a-z]/.test(compact) && /[A-Z]/.test(compact);
    const separatorCount = segment.length - compact.length;

    // Long, lowercase issue slugs are ordinary refs, not credentials. Opaque
    // alphabetic values still fail closed when their mixed case and entropy
    // make them token-like.
    if (separatorCount >= 2 && !hasMixedCase && digitCount / compact.length < 0.2) {
      continue;
    }
    const uniqueCharacters = new Set(compact).size;
    const entropy = shannonEntropy(compact);
    const separatorFreeAlphabeticToken = separatorCount === 0
      && /^[A-Za-z]+$/.test(compact)
      && compact.length >= 40
      && uniqueCharacters >= 14
      && entropy >= 4;
    if (digitCount === 0 && !hasMixedCase && !separatorFreeAlphabeticToken) continue;
    if (uniqueCharacters >= 12 && entropy >= 3.75) {
      return true;
    }
  }
  return false;
}

/** Normalize a git ref before embedding it in generated shell commands. */
export function normalizeGitRef(ref: string | null | undefined): string | null {
  const value = ref?.trim() ?? "";
  if (!value) return null;
  if (value.length > MAX_GIT_REF_LENGTH) return null;
  if (looksLikeOpaqueCredential(value, true)) return null;
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

export function normalizeSSHUsername(
  username: string | null | undefined,
): string | null {
  const value = username?.trim() ?? "";
  if (!value) return null;
  if (value.length > MAX_SSH_USERNAME_LENGTH) return null;
  if (looksLikeOpaqueCredential(value)) return null;
  if (!SSH_USERNAME_PATTERN.test(value)) return null;
  if (value === "root") return null;
  return value;
}

/**
 * Validate an IPv4 or IPv6 address intended for a remote VPS connection.
 * Zone IDs are local-interface identifiers and are intentionally rejected.
 */
export function isValidIP(ip: string): boolean {
  const normalized = ip.trim();

  const ipv4Pattern = /^(\d{1,3}\.){3}\d{1,3}$/;
  if (ipv4Pattern.test(normalized)) {
    return normalized.split(".").every((part) => {
      const value = Number.parseInt(part, 10);
      return value >= 0 && value <= 255;
    });
  }

  if (normalized.includes("%")) {
    return false;
  }

  const ipv6Pattern = /^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|::(ffff(:0{1,4})?:)?((25[0-5]|(2[0-4]|1?[0-9])?[0-9])\.){3}(25[0-5]|(2[0-4]|1?[0-9])?[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1?[0-9])?[0-9])\.){3}(25[0-5]|(2[0-4]|1?[0-9])?[0-9]))$/;

  return ipv6Pattern.test(normalized);
}

/**
 * Detect an IPv4 or IPv6 literal embedded in otherwise free-form text.
 *
 * Privacy boundaries need this stronger predicate than `isValidIP`: values such
 * as `server 203.0.113.7` and `host=[2001:db8::7]` are not themselves IP
 * addresses, but still disclose one when copied into a support artifact or URL.
 */
export function containsIPAddress(value: string): boolean {
  const trimmed = value.trim().replace(/^\[|\]$/g, "");
  if (isValidIP(trimmed)) return true;

  const ipv4Candidates = value.match(/(?:\d{1,3}\.){3}\d{1,3}/g) ?? [];
  if (ipv4Candidates.some((candidate) => isValidIP(candidate))) return true;

  return value
    .split(/[^0-9A-Fa-f:.]+/)
    .map((candidate) => candidate.replace(/^\.+|\.+$/g, ""))
    .some((candidate) => candidate.includes(":") && isValidIP(candidate));
}
