const MAX_GIT_REF_LENGTH = 120;
const GIT_REF_SAFE_PATTERN = /^[A-Za-z0-9._/-]+$/;
const SSH_USERNAME_PATTERN = /^[a-z_][a-z0-9._-]*$/;

/** Normalize a git ref before embedding it in generated shell commands. */
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

export function normalizeSSHUsername(
  username: string | null | undefined,
): string | null {
  const value = username?.trim() ?? "";
  if (!value) return null;
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
