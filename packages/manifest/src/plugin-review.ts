/** External review and target binding for an archive; never an activation grant. */
import {
  parsePluginJsonBytes,
  readPluginInputFile,
  readVerifiedPluginArchive,
  type VerifiedPluginArchive,
} from "./plugin-archive.js";

export interface PluginArchiveTarget {
  os: string;
  version: string;
  arch: string;
  libc: string;
}
export interface PluginReviewRecord {
  schema: "acfs.plugin-review.v1";
  packageId: string;
  version: string;
  sourceCommit: string;
  packageSha256: string;
  reviewer: string;
  reviewedAt: string;
  expiresAt: string;
  target: PluginArchiveTarget;
  approvedCapabilities: string[];
}
export interface ReviewedPluginArchive extends VerifiedPluginArchive {
  /** Independently supplied by the external review, not inferred from manifest bytes. */
  expectedPackageSha256: string;
}
export class PluginReviewError extends Error {
  constructor(
    public readonly code: "plugin_review_required" | "plugin_target_unsupported",
    message: string,
  ) {
    super(message);
    this.name = "PluginReviewError";
  }
}
const TARGET_KEYS = ["arch", "libc", "os", "version"];
const REVIEW_KEYS = [
  "approvedCapabilities",
  "expiresAt",
  "packageId",
  "packageSha256",
  "reviewedAt",
  "reviewer",
  "schema",
  "sourceCommit",
  "target",
  "version",
];
const BASELINE_CAPABILITIES = new Set(["verified_installer", "doctor_check", "web_metadata"]);

function refuse(message: string): never {
  throw new PluginReviewError("plugin_review_required", message);
}
function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function safeText(value: unknown, limit: number): value is string {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= limit &&
    value.trim() === value &&
    !/[\x00-\x1f\x7f]/.test(value)
  );
}
function targetValid(value: unknown): value is PluginArchiveTarget {
  return (
    record(value) &&
    Object.keys(value).sort().join(",") === TARGET_KEYS.join(",") &&
    TARGET_KEYS.every(
      (key) =>
        typeof value[key] === "string" && /^[a-z0-9][a-z0-9_.-]{0,63}$/.test(value[key] as string),
    )
  );
}
function sameTarget(a: PluginArchiveTarget, b: PluginArchiveTarget): boolean {
  return a.os === b.os && a.version === b.version && a.arch === b.arch && a.libc === b.libc;
}
function canonicalTime(value: unknown): number {
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value)
  ) {
    return refuse("Review timestamps must be canonical UTC ISO-8601 values");
  }
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return refuse("Review timestamp is invalid");
  const iso = new Date(timestamp).toISOString();
  if (value !== iso && value !== iso.replace(".000Z", "Z"))
    return refuse("Review timestamp is not canonical");
  return timestamp;
}

export function parsePluginTarget(value: string): PluginArchiveTarget {
  const [os, version, arch, libc, ...extra] = value.split("/");
  const target = { os, version, arch, libc };
  if (extra.length !== 0 || !targetValid(target)) {
    throw new PluginReviewError("plugin_target_unsupported", "Target must be os/version/arch/libc");
  }
  return target;
}

/** The operator, not the package author, must select this trusted local record. */
export function readPluginReviewRecord(reviewPath: string, now = Date.now()): PluginReviewRecord {
  let input: unknown;
  try {
    input = parsePluginJsonBytes(readPluginInputFile(reviewPath, 64 * 1024));
  } catch {
    return refuse("External review record is missing, unsafe, oversized, or invalid JSON");
  }
  if (
    !record(input) ||
    Object.keys(input).sort().join(",") !== REVIEW_KEYS.join(",") ||
    input.schema !== "acfs.plugin-review.v1" ||
    typeof input.packageId !== "string" ||
    !/^[a-z][a-z0-9_.-]{0,127}$/.test(input.packageId) ||
    !safeText(input.version, 128) ||
    !safeText(input.reviewer, 200) ||
    typeof input.packageSha256 !== "string" ||
    !/^[a-f0-9]{64}$/i.test(input.packageSha256) ||
    typeof input.sourceCommit !== "string" ||
    !/^[a-f0-9]{40}$/i.test(input.sourceCommit) ||
    !targetValid(input.target) ||
    !Array.isArray(input.approvedCapabilities) ||
    input.approvedCapabilities.length === 0 ||
    !input.approvedCapabilities.every(
      (cap) => typeof cap === "string" && BASELINE_CAPABILITIES.has(cap),
    ) ||
    new Set(input.approvedCapabilities).size !== input.approvedCapabilities.length
  ) {
    return refuse("External review record has an unsupported shape or capability approval");
  }
  const reviewedAt = canonicalTime(input.reviewedAt);
  const expiresAt = canonicalTime(input.expiresAt);
  if (!Number.isFinite(now) || reviewedAt > now || expiresAt <= now || expiresAt <= reviewedAt) {
    return refuse("External review is expired, future-dated, or has an invalid validity interval");
  }
  return {
    schema: "acfs.plugin-review.v1",
    packageId: input.packageId,
    version: input.version,
    sourceCommit: input.sourceCommit.toLowerCase(),
    packageSha256: input.packageSha256.toLowerCase(),
    reviewer: input.reviewer,
    reviewedAt: input.reviewedAt as string,
    expiresAt: input.expiresAt as string,
    target: { ...input.target },
    approvedCapabilities: [...input.approvedCapabilities] as string[],
  };
}

/**
 * Review selection, digest, identity, target, and baseline capability checks are
 * all mandatory. The returned manifest STILL requires canonical schema, graph,
 * checksum, and capability validation. No review can unlock elevated execution.
 */
export function readReviewedPluginArchive(
  archivePath: string,
  reviewPath: string,
  target: PluginArchiveTarget,
  now = Date.now(),
): ReviewedPluginArchive {
  if (!targetValid(target)) {
    throw new PluginReviewError(
      "plugin_target_unsupported",
      "An explicit valid target is required",
    );
  }
  const review = readPluginReviewRecord(reviewPath, now);
  if (!sameTarget(target, review.target)) {
    throw new PluginReviewError(
      "plugin_target_unsupported",
      "Requested target differs from the external review",
    );
  }
  const archive = readVerifiedPluginArchive(archivePath, review.packageSha256);
  const manifest = archive.manifest;
  if (
    !record(manifest) ||
    !record(manifest.provenance) ||
    manifest.packageId !== review.packageId ||
    manifest.version !== review.version ||
    typeof manifest.provenance.sourceCommit !== "string" ||
    manifest.provenance.sourceCommit.toLowerCase() !== review.sourceCommit
  ) {
    return refuse("Package identity, version, or source commit differs from its external review");
  }
  if (
    !Array.isArray(manifest.targets) ||
    !manifest.targets.some(
      (candidate) =>
        record(candidate) &&
        candidate.os === target.os &&
        Array.isArray(candidate.versions) &&
        candidate.versions.includes(target.version) &&
        Array.isArray(candidate.arch) &&
        candidate.arch.includes(target.arch) &&
        Array.isArray(candidate.libc) &&
        candidate.libc.includes(target.libc),
    )
  ) {
    throw new PluginReviewError(
      "plugin_target_unsupported",
      "Package does not declare the complete requested target tuple",
    );
  }
  if (
    !record(manifest.capabilities) ||
    !Array.isArray(manifest.capabilities.allowed) ||
    !manifest.capabilities.allowed.every(
      (capability) =>
        typeof capability === "string" && review.approvedCapabilities.includes(capability),
    )
  ) {
    return refuse("Package requests capabilities not approved in the external review");
  }
  return { ...archive, expectedPackageSha256: review.packageSha256 };
}
