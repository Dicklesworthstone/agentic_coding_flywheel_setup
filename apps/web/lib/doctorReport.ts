/** Local, read-only interpretation of the JSON emitted by acfs doctor --json. */
export const DOCTOR_REPORT_MAX_BYTES = 1024 * 1024;
const MAX_CHECKS = 4096;
const MAX_MODULES = 1024;
const DAY_MS = 24 * 60 * 60 * 1000;
const MODULE_ID = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/;
const CHECK_ID = /^[a-z][a-z0-9_]*(?:\.[a-z0-9_]+)*$/;
const HASH = /^[a-f0-9]{64}$/;

export type DoctorReportStatus = "pass" | "warn" | "fail" | "skip" | "timeout";
export type DoctorReportModuleStatus = DoctorReportStatus | "unreported";
export interface DoctorReportCounts {
  pass: number; warn: number; fail: number; skip: number; timeout: number;
}
export interface DoctorReportContext {
  /** Context is trusted wizard state, not fields copied from the report. */
  host: string;
  username: string;
  mode: "safe" | "vibe";
  installerCommand: string;
  manifestSha256: string;
  checksumsYamlSha256: string;
  selectedModuleIds: readonly string[];
  knownModuleIds: readonly string[];
}
export interface DoctorReportReview {
  readonly schema: "acfs.doctor-report-review.v1";
  readonly sourceSha256: string;
  readonly sourceBytes: number;
  readonly reportedAt: string;
  readonly freshnessAtRead: "recent" | "stale" | "future";
  readonly userMatches: boolean;
  readonly modeMatches: boolean;
  /** The report does not carry a host, selection or canonical-file attestation. */
  readonly hostVerified: false;
  readonly installationVerified: false;
  readonly reportedOS: { readonly id: string; readonly version: string };
  readonly totals: Readonly<DoctorReportCounts>;
  readonly modules: readonly {
    readonly id: string;
    readonly status: DoctorReportModuleStatus;
    readonly checkCount: number;
    readonly counts: Readonly<DoctorReportCounts>;
  }[];
  readonly outsideSelection: Readonly<DoctorReportCounts>;
  readonly unmapped: Readonly<DoctorReportCounts>;
  readonly needsAttention: boolean;
}
export class DoctorReportError extends Error {
  constructor(public readonly code: string, message: string) {
    super(message);
    this.name = "DoctorReportError";
  }
}
function refuse(code: string, message: string): never {
  throw new DoctorReportError(code, message);
}
function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function freeze<T>(value: T): T {
  if (value && typeof value === "object") {
    Object.values(value).forEach(freeze);
    Object.freeze(value);
  }
  return value;
}
function counts(): DoctorReportCounts { return { pass: 0, warn: 0, fail: 0, skip: 0, timeout: 0 }; }
function total(value: DoctorReportCounts): number { return Object.values(value).reduce((a, b) => a + b, 0); }
function moduleIds(value: readonly string[]): string[] {
  if (!Array.isArray(value) || value.length > MAX_MODULES
      || Array.from(value).some((id) => typeof id !== "string" || id.length > 160 || !MODULE_ID.test(id))
      || new Set(value).size !== value.length) {
    return refuse("doctor_context_invalid", "The current module catalogue or selection cannot be compared safely.");
  }
  return [...value].sort();
}
function contextKey(context: DoctorReportContext): string {
  if (!context || typeof context.host !== "string" || !context.host || context.host.length > 256
      || /[\x00-\x20\x7f]/.test(context.host)
      || typeof context.username !== "string" || !/^[a-z_][a-z0-9._-]{0,63}$/.test(context.username)
      || !["safe", "vibe"].includes(context.mode)
      || typeof context.installerCommand !== "string" || !context.installerCommand.trim()
      || context.installerCommand.length > 65536 || context.installerCommand.includes("\0")
      || !HASH.test(context.manifestSha256) || !HASH.test(context.checksumsYamlSha256)) {
    return refuse("doctor_context_invalid", "A current host, account, installation and catalogue identity are required.");
  }
  const selected = moduleIds(context.selectedModuleIds);
  const known = moduleIds(context.knownModuleIds);
  const catalogue = new Set(known);
  if (!selected.length || selected.some((id) => !catalogue.has(id))) {
    return refuse("doctor_context_invalid", "The current selection is empty or contains unknown modules.");
  }
  return JSON.stringify([context.host, context.username, context.mode, context.installerCommand,
    context.manifestSha256, context.checksumsYamlSha256, selected, known]);
}

/** Reject duplicate decoded keys: JSON.parse alone silently discards earlier failures. */
function parseJson(bytes: Uint8Array): unknown {
  let text: string;
  let parsed: unknown;
  try {
    text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
    parsed = JSON.parse(text);
  } catch { return refuse("doctor_report_invalid", "Choose a UTF-8 JSON doctor report without terminal output or a byte-order mark."); }
  let offset = 0;
  let nodes = 0;
  const whitespace = (): void => { while (/[\t\n\r ]/.test(text[offset] ?? "x")) offset++; };
  const string = (): string => {
    const start = offset++;
    while (offset < text.length) {
      const char = text[offset++];
      if (char === "\\") offset++;
      else if (char === '"') return JSON.parse(text.slice(start, offset)) as string;
    }
    return refuse("doctor_report_invalid", "The doctor report contains an incomplete string.");
  };
  const value = (depth: number): void => {
    if (depth > 32 || ++nodes > 100_000) refuse("doctor_report_invalid", "The report exceeds its nesting or node budget.");
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
          if (keys.has(key)) refuse("doctor_report_invalid", "The report contains duplicate JSON keys.");
          keys.add(key); whitespace(); offset++;
        }
        value(depth + 1); whitespace();
        if (text[offset++] === end) return;
        whitespace();
      }
    } else if (char === '"') string();
    else {
      const start = offset;
      while (offset < text.length && !/[\t\n\r ,}\]]/.test(text[offset]!)) offset++;
      const primitive = text.slice(start, offset);
      if (/^-?[0-9]/.test(primitive) && !Number.isFinite(Number(primitive))) {
        refuse("doctor_report_invalid", "The report contains a non-finite number.");
      }
    }
  };
  value(0);
  return parsed;
}

/** date -Iseconds emits an offset, not necessarily Z. Check calendar validity too. */
function timestamp(value: unknown): number {
  if (typeof value !== "string") return refuse("doctor_report_invalid", "The report timestamp is missing or invalid.");
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{3}))?(Z|([+-])(\d{2}):(\d{2}))$/.exec(value);
  const epoch = Date.parse(value);
  if (!match || !Number.isFinite(epoch) || Number(match[5] ?? 0) > 23 || Number(match[6] ?? 0) > 59) {
    return refuse("doctor_report_invalid", "The report timestamp is missing or invalid.");
  }
  const offset = (Number(match[5] ?? 0) * 60 + Number(match[6] ?? 0)) * 60000 * (match[4] === "-" ? -1 : 1);
  const local = new Date(epoch + offset).toISOString();
  if (local !== `${match[1]}.${match[2] ?? "000"}Z`) {
    return refuse("doctor_report_invalid", "The report timestamp contains an invalid calendar date.");
  }
  return epoch;
}

// Explicit aliases used by scripts/lib/doctor.sh. Never infer ownership from a
// report's label, details or suggested fix. Unknown/aggregate checks stay separate.
const CHECK_MODULES: Readonly<Record<string, string>> = Object.freeze({
  "tool.bun": "lang.bun", "tool.uv": "lang.uv", "tool.cargo": "lang.rust", "tool.go": "lang.go",
  "tool.tmux": "cli.modern", "tool.rg": "cli.modern", "tool.gh": "cli.modern",
  "tool.git_lfs": "cli.modern", "tool.rsync": "cli.modern", "tool.strace": "cli.modern",
  "tool.lsof": "cli.modern", "tool.dig": "cli.modern", "tool.nc": "cli.modern",
  "shell.fzf": "cli.modern", "shell.direnv": "cli.modern",
  "agent.claude": "agents.claude", "agent.codex": "agents.codex", "agent.antigravity": "agents.antigravity",
  "shell.ohmyzsh": "shell.omz", "shell.p10k": "shell.p10k",
});
function owner(id: string, known: ReadonlySet<string>): string | null {
  if (known.has(id)) return id;
  const generated = /^(.*)\.[1-9][0-9]*$/.exec(id)?.[1];
  if (generated && known.has(generated)) return generated;
  const alias = Object.hasOwn(CHECK_MODULES, id) ? CHECK_MODULES[id] : undefined;
  return alias && known.has(alias) ? alias : null;
}
function moduleStatus(value: DoctorReportCounts): DoctorReportModuleStatus {
  if (value.fail) return "fail";
  if (value.timeout) return "timeout";
  if (value.warn) return "warn";
  if (value.skip) return "skip";
  return value.pass ? "pass" : "unreported";
}
const bindings = new WeakMap<DoctorReportReview, string>();

/**
 * Only sanitized statuses and canonical module IDs leave this function.
 * Report labels, details, suggested shell fixes and reported usernames are not
 * retained in public state, rendered, exported, uploaded or executed.
 */
export async function reviewDoctorReportFile(
  file: Pick<Blob, "size" | "slice">,
  context: DoctorReportContext,
  now = Date.now(),
): Promise<DoctorReportReview> {
  const boundContext = contextKey(context);
  const selected = [...context.selectedModuleIds];
  const known = new Set(context.knownModuleIds);
  const username = context.username;
  const mode = context.mode;
  if (!Number.isFinite(now) || !file || !Number.isSafeInteger(file.size)
      || file.size < 1 || file.size > DOCTOR_REPORT_MAX_BYTES) {
    return refuse("doctor_report_invalid", "Select one nonempty doctor JSON report no larger than 1 MiB.");
  }
  let bytes: Uint8Array;
  try { bytes = new Uint8Array(await file.slice(0, DOCTOR_REPORT_MAX_BYTES + 1).arrayBuffer()); }
  catch { return refuse("doctor_report_unreadable", "The doctor report could not be read locally."); }
  if (bytes.length !== file.size || bytes.length > DOCTOR_REPORT_MAX_BYTES) {
    return refuse("doctor_report_invalid", "The report changed or exceeds its byte budget.");
  }
  const report = parseJson(bytes);
  if (!record(report) || typeof report.acfs_version !== "string"
      || !/^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$/.test(report.acfs_version)
      || !["vibe", "safe"].includes(report.mode as string) || typeof report.deep_mode !== "boolean"
      || typeof report.user !== "string" || report.user.length > 256
      || !record(report.os) || typeof report.os.id !== "string" || !/^[a-z][a-z0-9_-]{0,31}$/.test(report.os.id)
      || typeof report.os.version !== "string" || !/^(?:[0-9]{1,4}(?:\.[0-9]{1,4}){0,2}|unknown)$/.test(report.os.version)
      || !Array.isArray(report.checks) || !report.checks.length || report.checks.length > MAX_CHECKS
      || !record(report.summary)) {
    return refuse("doctor_report_invalid", "The file does not match the supported acfs doctor --json report shape.");
  }
  const reportedAt = timestamp(report.timestamp);
  const totals = counts();
  const outsideSelection = counts();
  const unmapped = counts();
  const modules = new Map(selected.map((id) => [id, counts()]));
  const seen = new Set<string>();
  for (const check of report.checks) {
    if (!record(check) || typeof check.id !== "string" || check.id.length > 200 || !CHECK_ID.test(check.id)
        || !["pass", "warn", "fail", "skip", "timeout"].includes(check.status as string)
        || seen.has(check.id) || typeof check.label !== "string" || typeof check.details !== "string"
        || (check.fix !== null && typeof check.fix !== "string")) {
      return refuse("doctor_report_invalid", "Report checks have an invalid shape, status, or duplicate identity.");
    }
    seen.add(check.id);
    const status = check.status as DoctorReportStatus;
    totals[status]++;
    const module = owner(check.id, known);
    const destination = module ? modules.get(module) ?? outsideSelection : unmapped;
    destination[status]++;
  }
  // The producer counts timeouts as WARN, while this review displays them separately.
  for (const key of ["pass", "warn", "fail", "skip"] as const) {
    const expected = totals[key] + (key === "warn" ? totals.timeout : 0);
    if (!Number.isSafeInteger(report.summary[key]) || report.summary[key] !== expected) {
      return refuse("doctor_report_inconsistent", "The report summary disagrees with its individual checks. Capture a fresh complete report.");
    }
  }
  let digest: ArrayBuffer;
  try { digest = await globalThis.crypto.subtle.digest("SHA-256", bytes); }
  catch { return refuse("doctor_report_hash_unavailable", "Secure browser hashing is required to identify the report bytes."); }
  const sourceSha256 = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  const freshnessAtRead = reportedAt > now + 5 * 60_000 ? "future" : now - reportedAt > DAY_MS ? "stale" : "recent";
  const rows = selected.map((id) => {
    const count = modules.get(id)!;
    return { id, status: moduleStatus(count), checkCount: total(count), counts: count };
  });
  const review: DoctorReportReview = freeze({
    schema: "acfs.doctor-report-review.v1", sourceSha256, sourceBytes: bytes.length,
    reportedAt: new Date(reportedAt).toISOString(), freshnessAtRead,
    userMatches: report.user === username, modeMatches: report.mode === mode,
    hostVerified: false, installationVerified: false,
    reportedOS: { id: report.os.id, version: report.os.version }, totals, modules: rows, outsideSelection, unmapped,
    needsAttention: rows.some((row) => row.status !== "pass") || Boolean(totals.fail || totals.warn || totals.timeout)
      || report.user !== username || report.mode !== mode || freshnessAtRead !== "recent",
  });
  bindings.set(review, boundContext);
  return review;
}

/** Copied results and results for an old host/selection are not current reviews. */
export function doctorReportMatches(review: DoctorReportReview | null, context: DoctorReportContext | null): boolean {
  if (!review || !context) return false;
  try { return bindings.get(review) === contextKey(context); } catch { return false; }
}
