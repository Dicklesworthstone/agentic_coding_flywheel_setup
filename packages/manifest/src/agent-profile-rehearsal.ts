#!/usr/bin/env bun
/** Opt-in isolated-profile startup checks. Never activates global credentials. */
import { spawn } from "node:child_process";
import { accessSync, constants, statSync } from "node:fs";
import { userInfo } from "node:os";
import { isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const PROVIDERS = ["claude", "codex", "gemini", "agy"] as const;
export type Provider = (typeof PROVIDERS)[number];
type Outcome = "ok" | "exit_nonzero" | "spawn_failed" | "timeout" | "output_limit" | "cancelled" | "signaled";
export interface ProbeResult {
  outcome: Outcome;
  exitCode: number | null;
  stdout: Buffer;
  stderr: Buffer;
}
export interface ProbeRequest {
  binary: string;
  args: string[];
  env: NodeJS.ProcessEnv;
  timeoutMs: number;
  signal?: AbortSignal;
}
export interface Selection { provider: Provider; name: string; ref: string }
export interface RehearsalPlan { selections: readonly Selection[]; timeoutMs: number }
export interface Check {
  id: "profile_status" | "isolated_version" | "profile_status_after";
  status: "pass" | "fail" | "warn" | "skipped";
  code: string;
  exitCode: number | null;
}
export interface ProfileResult {
  provider: Provider;
  profileRef: string;
  status: "planned" | "pass" | "fail" | "warn";
  localAuthPresent: boolean | null;
  version: string | null;
  checks: Check[];
  nextAction: string;
}
export interface RehearsalReport {
  schema: "acfs.agent-profile-rehearsal.v1";
  generatedAt: string;
  executed: boolean;
  status: "planned" | "pass" | "fail" | "warn" | "cancelled";
  scope: "isolated-cli-startup-and-local-auth";
  liveAuthenticationVerified: false;
  globalActivationRequested: false;
  modelPromptSent: false;
  profiles: ProfileResult[];
  redaction: { rawOutputIncluded: false; profileNamesIncluded: false };
}
export class RehearsalError extends Error {
  constructor(public readonly code: string) { super(code); this.name = "RehearsalError"; }
}
const refuse = (code: string): never => { throw new RehearsalError(code); };
const MAX_BYTES = 64 * 1024;

export function buildRehearsalPlan(selectors: readonly string[], timeoutSeconds = 10): RehearsalPlan {
  if (!Array.isArray(selectors) || selectors.length < 1 || selectors.length > 8)
    refuse("select_one_to_eight_profiles");
  if (!Number.isInteger(timeoutSeconds) || timeoutSeconds < 1 || timeoutSeconds > 30)
    refuse("timeout_must_be_1_to_30_seconds");
  const seen = new Set<string>();
  const selections = selectors.map((selector, i) => {
    if (typeof selector !== "string") return refuse("invalid_profile_selector");
    const match = /^(claude|codex|gemini|agy):([a-zA-Z0-9_][a-zA-Z0-9_.@+-]{0,127})$/.exec(selector);
    if (!match || match[2] === "." || match[2] === "..") return refuse("invalid_profile_selector");
    if (seen.has(selector)) return refuse("duplicate_profile_selector");
    seen.add(selector);
    return Object.freeze({ provider: match[1] as Provider, name: match[2]!, ref: `profile-${i + 1}` });
  });
  return Object.freeze({ selections: Object.freeze(selections), timeoutMs: timeoutSeconds * 1000 });
}

/** Do not let inherited API keys, provider homes or runtime hooks bypass isolation. */
export function rehearsalEnvironment(env: NodeJS.ProcessEnv, home: string): NodeJS.ProcessEnv {
  if (!isAbsolute(home) || /[\x00-\x1f\x7f]/.test(home)) refuse("invalid_account_home");
  const path = (env.PATH ?? "").split(":").filter((p) => isAbsolute(p) && !/[\x00-\x1f\x7f]/.test(p));
  const result: NodeJS.ProcessEnv = {
    HOME: home, PATH: path.join(":"), LANG: "C.UTF-8", LC_ALL: "C.UTF-8",
    TERM: "dumb", NO_COLOR: "1",
  };
  for (const key of ["CAAM_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"]) {
    const value = env[key];
    if (value !== undefined) {
      if (!isAbsolute(value) || /[\x00-\x1f\x7f]/.test(value)) refuse("invalid_profile_store_environment");
      result[key] = value;
    }
  }
  return result;
}
function findCaam(env: NodeJS.ProcessEnv): string {
  for (const directory of (env.PATH ?? "").split(":")) {
    if (!isAbsolute(directory)) continue;
    const path = join(directory, "caam");
    try {
      if (!statSync(path).isFile()) continue;
      accessSync(path, constants.X_OK);
      return path;
    } catch { /* Continue through the target user's absolute PATH entries. */ }
  }
  return refuse("caam_not_found");
}

/** Bound both streams together, never inherit a terminal, and reap our process group. */
export function runBoundedProbe(request: ProbeRequest): Promise<ProbeResult> {
  return new Promise((resolveResult) => {
    if (request.signal?.aborted) {
      resolveResult({ outcome: "cancelled", exitCode: null, stdout: Buffer.alloc(0), stderr: Buffer.alloc(0) });
      return;
    }
    const child = spawn(request.binary, request.args, {
      cwd: "/", env: request.env, stdio: ["ignore", "pipe", "pipe"], detached: true, shell: false,
    });
    let outcome: Outcome | null = null;
    let exitCode: number | null = null;
    let count = 0;
    let settled = false;
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];
    let fallback: ReturnType<typeof setTimeout> | undefined;
    const finish = (): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (fallback) clearTimeout(fallback);
      request.signal?.removeEventListener("abort", abort);
      resolveResult({
        outcome: outcome ?? (exitCode === 0 ? "ok" : "exit_nonzero"), exitCode,
        stdout: outcome ? Buffer.alloc(0) : Buffer.concat(stdout),
        stderr: outcome ? Buffer.alloc(0) : Buffer.concat(stderr),
      });
    };
    const stop = (reason: Outcome): void => {
      if (settled || outcome) return;
      outcome = reason;
      if (child.pid) {
        try { process.kill(-child.pid, "SIGKILL"); } catch { /* Already gone. */ }
      }
      // A descendant that changes session could retain a pipe after its parent
      // exits. Never let that defeat the deadline or retain unbounded output.
      fallback = setTimeout(() => {
        child.stdout.destroy(); child.stderr.destroy(); child.unref(); finish();
      }, 250);
    };
    const receive = (chunks: Buffer[], chunk: Buffer): void => {
      if (settled || outcome) return;
      count += chunk.length;
      if (count > MAX_BYTES) stop("output_limit");
      else chunks.push(chunk);
    };
    child.stdout.on("data", (chunk: Buffer) => receive(stdout, chunk));
    child.stderr.on("data", (chunk: Buffer) => receive(stderr, chunk));
    child.on("error", () => { outcome = "spawn_failed"; finish(); });
    child.on("close", (code, signal) => {
      exitCode = code;
      if (signal && !outcome) outcome = "signaled";
      finish();
    });
    const abort = (): void => stop("cancelled");
    const timer = setTimeout(() => stop("timeout"), request.timeoutMs);
    request.signal?.addEventListener("abort", abort, { once: true });
    if (request.signal?.aborted) abort();
  });
}

/** CAAM's isolated status command has no JSON mode. Accept only its fixed header. */
export function parseProfileStatus(result: ProbeResult, selection: Selection): { loggedIn: boolean; locked: boolean } | null {
  if (result.outcome !== "ok") return null;
  let text: string;
  try { text = new TextDecoder("utf-8", { fatal: true }).decode(result.stdout); } catch { return null; }
  const lines = text.replace(/\r\n/g, "\n").trimEnd().split("\n");
  if (lines[0] !== `Profile: ${selection.provider}/${selection.name}` ||
      !/^  Path: \/[^\x00-\x1f\x7f]+$/.test(lines[1] ?? "") ||
      !/^  Auth mode: (oauth|api-key)$/.test(lines[2] ?? "") ||
      !/^  Logged in: (true|false)$/.test(lines[3] ?? "") ||
      !/^  Locked: (true|false)$/.test(lines[4] ?? "") ||
      lines.slice(5).some((line) => !/^  (Account|Description|Browser): [^\x00-\x1f\x7f]*$/.test(line))) return null;
  return { loggedIn: lines[3] === "  Logged in: true", locked: lines[4] === "  Locked: true" };
}
function safeVersion(result: ProbeResult): string | null {
  if (result.outcome !== "ok") return null;
  // Only numeric version components leave the private capture, never arbitrary
  // banners, prerelease strings, profile names, emails, or diagnostic snippets.
  const match = /(?:^|\s|v)(\d{1,4}\.\d{1,4}\.\d{1,4})(?=\s|$|[-+(])/.exec(result.stdout.toString("utf8"));
  return match?.[1] ?? null;
}
export interface RehearsalOptions {
  execute?: boolean;
  signal?: AbortSignal;
  env?: NodeJS.ProcessEnv;
}
/** Trusted library/test ports only; the CLI cannot override user identity or the runner. */
export interface RehearsalPorts {
  uid(): number;
  euid(): number;
  home(): string;
  findCaam(env: NodeJS.ProcessEnv): string;
  run(request: ProbeRequest): Promise<ProbeResult>;
}
const ports: RehearsalPorts = {
  uid: () => process.getuid!(), euid: () => process.geteuid!(),
  home: () => userInfo().homedir, findCaam, run: runBoundedProbe,
};
const AUTH_GUIDANCE = "Inspect this isolated profile locally; sign in with the provider's own login flow. No login or global activation was attempted.";

export async function rehearseProfiles(plan: RehearsalPlan, options: RehearsalOptions = {}, deps = ports): Promise<RehearsalReport> {
  // Revalidate caller-created plans as well as CLI-created plans.
  const checked = buildRehearsalPlan(plan.selections.map((s) => `${s.provider}:${s.name}`), plan.timeoutMs / 1000);
  const report: RehearsalReport = {
    schema: "acfs.agent-profile-rehearsal.v1", generatedAt: new Date().toISOString(),
    executed: options.execute === true, status: "planned", scope: "isolated-cli-startup-and-local-auth",
    liveAuthenticationVerified: false, globalActivationRequested: false, modelPromptSent: false,
    profiles: checked.selections.map((s) => ({
      provider: s.provider, profileRef: s.ref, status: "planned", localAuthPresent: null,
      version: null, checks: [], nextAction: "Pass --run to execute these local checks; no model prompt will be sent.",
    })),
    redaction: { rawOutputIncluded: false, profileNamesIncluded: false },
  };
  if (!options.execute) return report;
  if ((process.platform !== "linux" && process.platform !== "darwin") || !process.getuid)
    refuse("posix_host_required");
  if (deps.uid() === 0 || deps.euid() !== deps.uid() || options.env?.SUDO_USER || process.env.SUDO_USER)
    refuse("run_as_target_user_without_sudo");
  const env = rehearsalEnvironment(options.env ?? process.env, deps.home());
  const binary = deps.findCaam(env);
  let cancelled = false;
  for (let index = 0; index < checked.selections.length; index++) {
    const selection = checked.selections[index]!;
    const profile = report.profiles[index]!;
    if (cancelled || options.signal?.aborted) {
      cancelled = true; profile.status = "warn"; profile.nextAction = "Rehearsal cancelled; this profile was not checked.";
      continue;
    }
    profile.status = "fail";
    profile.nextAction = AUTH_GUIDANCE;
    const probe = async (id: Check["id"], args: string[]): Promise<ProbeResult> => {
      const result = await deps.run({ binary, args, env, timeoutMs: checked.timeoutMs, signal: options.signal });
      cancelled ||= result.outcome === "cancelled";
      profile.checks.push({ id, status: result.outcome === "ok" ? "pass" : "fail", code: result.outcome, exitCode: result.exitCode });
      return result;
    };
    const statusArgs = ["profile", "status", selection.provider, selection.name];
    const before = await probe("profile_status", statusArgs);
    const state = parseProfileStatus(before, selection);
    if (!state) {
      if (before.outcome === "ok") Object.assign(profile.checks.at(-1)!, { status: "warn", code: "unrecognized_profile_status" });
      profile.status = before.outcome === "ok" ? "warn" : "fail";
      continue;
    }
    profile.localAuthPresent = state.loggedIn;
    if (state.locked || !state.loggedIn) {
      Object.assign(profile.checks.at(-1)!, { status: "fail", code: state.locked ? "profile_locked" : "local_auth_missing" });
      if (state.locked) profile.nextAction = "Profile is busy. Finish its existing session; no lock was removed or bypassed.";
      continue;
    }
    const version = await probe("isolated_version", ["exec", selection.provider, selection.name, "--", "--version"]);
    if (version.outcome !== "ok") continue;
    profile.version = safeVersion(version);
    if (!profile.version) Object.assign(profile.checks.at(-1)!, { status: "warn", code: "version_not_recognized" });
    const after = await probe("profile_status_after", statusArgs);
    const finalState = parseProfileStatus(after, selection);
    if (!finalState || !finalState.loggedIn || finalState.locked) {
      if (after.outcome === "ok") Object.assign(profile.checks.at(-1)!, { status: "fail", code: "profile_state_not_confirmed_after_execution" });
      profile.nextAction = "Inspect the isolated profile after execution. ACFS did not restore credentials, unlock it, or retry.";
      continue;
    }
    profile.status = profile.version ? "pass" : "warn";
    profile.nextAction = "Local profile and isolated CLI startup checked. Server-side authentication, token validity, quota, and model execution are NOT verified.";
  }
  report.status = cancelled ? "cancelled" : report.profiles.some((p) => p.status === "fail") ? "fail" :
    report.profiles.some((p) => p.status !== "pass") ? "warn" : "pass";
  return report;
}

export function formatRehearsal(report: RehearsalReport): string {
  const lines = ["ACFS isolated agent profile rehearsal", `Status: ${report.status}`, "Profile references follow --profile argument order; names and raw output are omitted."];
  for (const profile of report.profiles) {
    lines.push(`${profile.profileRef} (${profile.provider}): ${profile.status}`);
    for (const check of profile.checks) lines.push(`  ${check.id}: ${check.status} (${check.code})`);
    lines.push(`  ${profile.nextAction}`);
  }
  lines.push("No global activation or model prompt was requested. CAAM/provider commands may update their own local metadata.");
  return lines.join("\n");
}
export const REHEARSAL_HELP = `Usage: scripts/agent-readiness-audit.sh --rehearse --profile PROVIDER:NAME [--profile ...] [--run] [--json] [--timeout SECONDS]

Default: plan only. --run explicitly permits local CAAM status and isolated CLI
--version checks (1-8 profiles; per-command timeout 1-30 seconds, default 10).
Providers: claude, codex, gemini, agy. Use ISOLATED profiles from caam profile ls,
not vault-only profiles from caam ls. Busy profiles are never unlocked.

CAAM exec owns isolation and locks. No activate, login, refresh, model prompt,
quota rotation or task dispatch is requested. API-key environment overrides are
removed. Local files/CLI startup do not prove live authentication or token validity.
Raw output, account names and paths are omitted from reports.

Example: --rehearse --profile claude:work --profile codex:review --run --json`;
export async function rehearsalMain(args: string[]): Promise<number> {
  let json = false;
  try {
    let execute = false;
    let timeout = 10;
    const selections: string[] = [];
    for (let i = 0; i < args.length; i++) {
      switch (args[i]) {
        case "--help": case "-h": console.log(REHEARSAL_HELP); return 0;
        case "--json": json = true; break;
        case "--run": execute = true; break;
        case "--profile": selections.push(args[++i] ?? ""); break;
        case "--timeout": {
          const value = args[++i] ?? "";
          if (!/^[1-9][0-9]?$/.test(value)) refuse("timeout_must_be_1_to_30_seconds");
          timeout = Number(value); break;
        }
        default: refuse("unknown_rehearsal_option");
      }
    }
    const plan = buildRehearsalPlan(selections, timeout);
    const controller = new AbortController();
    const stop = (): void => controller.abort();
    process.on("SIGINT", stop); process.on("SIGTERM", stop);
    try {
      const report = await rehearseProfiles(plan, { execute, signal: controller.signal });
      console.log(json ? JSON.stringify(report, null, 2) : formatRehearsal(report));
      return report.status === "cancelled" ? 130 : report.status === "planned" || report.status === "pass" ? 0 : 1;
    } finally { process.off("SIGINT", stop); process.off("SIGTERM", stop); }
  } catch (error) {
    const code = error instanceof RehearsalError ? error.code : "rehearsal_failed";
    if (json || args.includes("--json")) console.log(JSON.stringify({ schema: "acfs.agent-profile-rehearsal.error.v1", code }));
    else console.error(`Rehearsal refused: ${code}. Run with --help for usage.`);
    return 2;
  }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  rehearsalMain(process.argv.slice(2)).then((code) => { process.exitCode = code; });
}
