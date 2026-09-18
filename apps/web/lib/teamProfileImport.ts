/** Local-file ingestion and explicit approval for the canonical team-profile diff. */
import {
  buildTeamProfileImportDiff,
  type TeamProfileImportCurrentState,
  type TeamProfileImportDiff,
} from "./commandBuilder";
import { manifestProvenance } from "./generated/manifest-modules";

export const TEAM_PROFILE_FILE_LIMIT = 256 * 1024;
const MAX_DEPTH = 32;
const MAX_NODES = 16_384;

export interface TeamProfileReviewContext {
  current: TeamProfileImportCurrentState;
  /** Kept in memory only; approval is not transferable to another VPS. */
  targetHost: string;
}
export interface TeamProfileFileReview {
  readonly sourceSha256: string;
  /** The executable command is deliberately absent until explicit approval. */
  readonly diff: TeamProfileImportDiff;
}
export interface ApprovedTeamProfileCommand {
  readonly sourceSha256: string;
  readonly command: string;
}
export class TeamProfileImportError extends Error {
  constructor(public readonly code: string, message: string,
    public readonly findingCodes: readonly string[] = []) {
    super(message);
    this.name = "TeamProfileImportError";
  }
}
interface RetainedReview {
  source: unknown;
  context: string;
  validatedDiff: string;
}
const reviews = new WeakMap<TeamProfileFileReview, RetainedReview>();
function refuse(code: string, message: string): never {
  throw new TeamProfileImportError(code, message);
}
function freeze<T>(value: T): T {
  if (value && typeof value === "object") {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
}
function contextKey(context: TeamProfileReviewContext): string {
  const current = context?.current;
  if (!current || !["x86_64", "aarch64"].includes(current.architecture ?? "")
      || typeof current.ubuntuVersion !== "string" || !/^\d{2}\.\d{2}$/.test(current.ubuntuVersion)
      || typeof context.targetHost !== "string" || !context.targetHost.length
      || context.targetHost.length > 256 || /[\x00-\x20\x7f]/.test(context.targetHost)) {
    return refuse("team_profile_context_required", "Choose a target host, Ubuntu image and architecture before reviewing a profile.");
  }
  // Includes the current catalogue identity so an approval cannot outlive trust
  // metadata changes. No host value, query string or imported file is persisted.
  return JSON.stringify([manifestProvenance, context.targetHost, current]);
}

/** JSON.parse validates grammar; this bounded scan additionally rejects duplicate decoded keys. */
function parseProfile(bytes: Uint8Array): unknown {
  let text: string;
  let value: unknown;
  try {
    text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
    value = JSON.parse(text);
  } catch {
    return refuse("team_profile_file_invalid", "Choose a UTF-8 JSON profile, not an archive or malformed document.");
  }
  let offset = 0;
  let nodes = 0;
  const whitespace = (): void => {
    while (/[\t\n\r ]/.test(text[offset] ?? "x")) offset++;
  };
  const string = (): string => {
    const start = offset++;
    while (offset < text.length) {
      const char = text[offset++];
      if (char === "\\") offset++;
      else if (char === '"') return JSON.parse(text.slice(start, offset)) as string;
    }
    return refuse("team_profile_file_invalid", "Profile contains an invalid JSON string.");
  };
  const scan = (depth: number): void => {
    if (depth > MAX_DEPTH || ++nodes > MAX_NODES) {
      refuse("team_profile_file_invalid", "Profile exceeds its nesting or node budget.");
    }
    whitespace();
    const char = text[offset];
    if (char === "{" || char === "[") {
      const object = char === "{";
      const end = object ? "}" : "]";
      const keys = new Set<string>();
      offset++; whitespace();
      if (text[offset] === end) { offset++; return; }
      while (offset < text.length) {
        if (object) {
          const key = string();
          if (keys.has(key)) refuse("team_profile_file_invalid", "Profile contains duplicate JSON keys.");
          keys.add(key); whitespace(); offset++;
        }
        scan(depth + 1); whitespace();
        if (text[offset++] === end) return;
        whitespace();
      }
    } else if (char === '"') string();
    else {
      const start = offset;
      while (offset < text.length && !/[\t\n\r ,}\]]/.test(text[offset]!)) offset++;
      const primitive = text.slice(start, offset);
      if (/^-?[0-9]/.test(primitive) && !Number.isFinite(Number(primitive))) {
        refuse("team_profile_file_invalid", "Profile numbers must be finite.");
      }
    }
  };
  scan(0);
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    refuse("team_profile_file_invalid", "A team profile must be one JSON object.");
  }
  return freeze(value);
}

function validatedDiff(source: unknown, current: TeamProfileImportCurrentState): TeamProfileImportDiff {
  let diff: TeamProfileImportDiff;
  try { diff = buildTeamProfileImportDiff(source, current); }
  catch { return refuse("team_profile_review_blocked", "Canonical profile validation could not complete. No command is available."); }
  if (diff.schema !== "acfs.team-profile-import-diff.v1" || diff.dryRun !== true || !diff.ok
      || !diff.profile || diff.findings.length || !diff.skips.allowed
      || !diff.installerCommand.command) {
    // Never echo untrusted field names, source values, parser text or filenames.
    const codes = [...new Set(diff.findings.map((finding) => finding.code))]
      .filter((code) => /^team_profile_[a-z_]{1,64}$/.test(code));
    throw new TeamProfileImportError("team_profile_review_blocked",
      "Profile refused. Resolve its compatibility, selection, provenance or credential findings before trying again.", codes);
  }
  return diff;
}

/** No upload, preference mutation, provider action, or installer execution. */
export async function reviewTeamProfileFile(
  file: Pick<Blob, "size" | "slice">,
  context: TeamProfileReviewContext,
): Promise<TeamProfileFileReview> {
  const boundContext = contextKey(context);
  const current = structuredClone(context.current);
  if (!file || !Number.isSafeInteger(file.size) || file.size < 1 || file.size > TEAM_PROFILE_FILE_LIMIT) {
    return refuse("team_profile_file_invalid", "Select one nonempty team-profile JSON file no larger than 256 KiB.");
  }
  let bytes: Uint8Array;
  try {
    bytes = new Uint8Array(await file.slice(0, TEAM_PROFILE_FILE_LIMIT + 1).arrayBuffer());
  } catch { return refuse("team_profile_read_failed", "The selected profile could not be read locally."); }
  if (bytes.byteLength !== file.size || bytes.byteLength > TEAM_PROFILE_FILE_LIMIT) {
    return refuse("team_profile_file_invalid", "The selected file changed or exceeds its byte budget.");
  }
  const source = parseProfile(bytes);
  let digest: ArrayBuffer;
  try { digest = await globalThis.crypto.subtle.digest("SHA-256", bytes); }
  catch { return refuse("team_profile_hash_unavailable", "Secure browser hashing is required to bind the reviewed file."); }
  const sourceSha256 = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  const diff = validatedDiff(source, current);
  const preview = structuredClone(diff);
  preview.installerCommand.command = null;
  const review = freeze({ sourceSha256, diff: preview });
  reviews.set(review, { source, context: boundContext, validatedDiff: JSON.stringify(diff) });
  return review;
}

/** A copied/deserialized review or changed target is not an approval candidate. */
export function teamProfileReviewMatches(review: TeamProfileFileReview | null,
  context: TeamProfileReviewContext | null): boolean {
  if (!review || !context) return false;
  const retained = reviews.get(review);
  try { return retained !== undefined && retained.context === contextKey(context); }
  catch { return false; }
}

/** Revalidate at the moment of approval; never accept an imported command string. */
export function approveTeamProfileReview(review: TeamProfileFileReview,
  context: TeamProfileReviewContext, confirmed: boolean): ApprovedTeamProfileCommand {
  if (confirmed !== true) return refuse("team_profile_confirmation_required", "Review the changes and explicitly approve generating this command.");
  if (!teamProfileReviewMatches(review, context)) {
    return refuse("team_profile_review_changed", "The target or wizard settings changed. Read and review the profile again.");
  }
  const retained = reviews.get(review)!;
  const diff = validatedDiff(retained.source, context.current);
  if (JSON.stringify(diff) !== retained.validatedDiff) {
    return refuse("team_profile_review_changed", "The canonical plan changed. Read and review the profile again.");
  }
  return Object.freeze({ sourceSha256: review.sourceSha256, command: diff.installerCommand.command! });
}
