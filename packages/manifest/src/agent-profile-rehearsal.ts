#!/usr/bin/env bun
/** Opt-in isolated-profile startup checks. Never activates global credentials. */
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { accessSync, constants, statSync, lstatSync, openSync, fstatSync, writeFileSync, fsyncSync, closeSync, mkdtempSync, realpathSync } from "node:fs";
import { userInfo } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const PROVIDERS = ["claude", "codex", "gemini", "agy"] as const;
export type Provider = (typeof PROVIDERS)[number];
type Outcome = "ok" | "exit_nonzero" | "spawn_failed" | "timeout" | "output_limit" | "cancelled" | "signaled" | "lingering_processes";
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
  cwd?: string;
  requireQuiescence?: boolean;
}
export interface Selection { provider: Provider; name: string; ref: string }
export interface RehearsalPlan { selections: readonly Selection[]; timeoutMs: number }
export interface Check {
  id: "profile_status" | "isolated_version" | "native_auth_status" | "live_model" | "profile_status_after";
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
  nativeAuth: NativeAuthState;
  liveModel?: {
    requestedModel: string;
    status: "planned" | "not_attempted" | "verified" | "unconfirmed";
    attempts: number;
  };
  checks: Check[];
  nextAction: string;
}
export interface RehearsalReport {
  schema: "acfs.agent-profile-rehearsal.v1";
  generatedAt: string;
  executed: boolean;
  status: "planned" | "pass" | "fail" | "warn" | "cancelled";
  scope: "isolated-cli-startup-and-local-auth" | "isolated-cli-and-live-model";
  // A CLI response cannot independently attest which account authenticated.
  liveAuthenticationVerified: false;
  globalActivationRequested: false;
  // null means an attempt occurred but delivery cannot be established.
  modelPromptSent: boolean | null;
  liveModelPolicy?: {
    timeoutMs: number;
    maximumCliAttempts: number;
    automaticRetries: false;
    mayIncurCharges: true;
    responseVerified: boolean;
  };
  nativeAuthRequested: boolean;
  nativeAuthRequired: boolean;
  profiles: ProfileResult[];
  redaction: { rawOutputIncluded: false; profileNamesIncluded: false };
}
export class RehearsalError extends Error {
  constructor(public readonly code: string) { super(code); this.name = "RehearsalError"; }
}
const refuse = (code: string): never => { throw new RehearsalError(code); };
const MAX_BYTES = 64 * 1024;

export interface LiveModelPlan {
  models: Readonly<Partial<Record<Provider, string>>>;
  timeoutMs: number;
}

/** Live checks are a separate opt-in: every selected provider needs a model. */
export function buildLiveModelPlan(plan: RehearsalPlan, selectors: readonly string[] = [], timeoutSeconds?: number): LiveModelPlan | undefined {
  if (!Array.isArray(selectors) || selectors.length > PROVIDERS.length) refuse("invalid_live_model_selection");
  if (!selectors.length) {
    if (timeoutSeconds !== undefined) refuse("live_timeout_requires_live_model");
    return undefined;
  }
  const timeout = timeoutSeconds ?? 60;
  if (!Number.isInteger(timeout) || timeout < 1 || timeout > 120) refuse("live_timeout_must_be_1_to_120_seconds");
  const models: Partial<Record<Provider, string>> = {};
  const selected = new Set(plan.selections.map((s) => s.provider));
  for (const selector of selectors) {
    const match = typeof selector === "string" && /^(claude):([A-Za-z0-9][A-Za-z0-9._-]{0,127})$/.exec(selector);
    if (!match) return refuse("unsupported_or_invalid_live_model");
    const provider = match[1] as Provider;
    if (models[provider]) refuse("duplicate_live_model");
    if (!selected.has(provider)) refuse("live_model_without_selected_profile");
    models[provider] = match[2]!;
  }
  if ([...selected].some((provider) => !models[provider])) refuse("live_model_required_for_every_selected_provider");
  return Object.freeze({ models: Object.freeze(models), timeoutMs: timeout * 1000 });
}

/** Fixed input only; never include a repository, profile name, or auth material. */
export function liveModelArgs(provider: Provider, model: string, challenge: string): string[] {
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(model) || !/^ACFS_LIVE_[a-f0-9]{32}$/.test(challenge))
    refuse("invalid_live_probe_request");
  if (provider !== "claude") refuse("unsupported_live_provider");
  // --bare deliberately is NOT used: it disables OAuth subscription login.
  // --safe-mode preserves authentication while suppressing custom context.
  // The remaining flags explicitly disable tools, MCP and ordinary hooks.
  return ["--print", "--safe-mode", "--output-format", "json", "--model", model,
    "--max-turns", "1", "--max-budget-usd", "0.25", "--no-session-persistence",
    "--tools", "", "--disallowedTools", "*", "--permission-mode", "dontAsk",
    "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
    "--setting-sources", "", "--settings", '{"disableAllHooks":true}',
    "--disable-slash-commands", "--system-prompt",
    "This is a connectivity check. Return only the exact token in the user message. Do not use tools.",
    challenge];
}

/** Accept a completed turn with this invocation's challenge, never a banner. */
export function liveModelResponseMatches(provider: Provider, result: ProbeResult, challenge: string): boolean {
  if (provider !== "claude" || result.outcome !== "ok" || result.exitCode !== 0 ||
      !/^ACFS_LIVE_[a-f0-9]{32}$/.test(challenge) || result.stdout.length + result.stderr.length > MAX_BYTES) return false;
  const value = uniqueJsonObject(result.stdout);
  return value?.type === "result" && value.subtype === "success" && value.is_error === false &&
    value.num_turns === 1 && typeof value.result === "string" && value.result.trim() === challenge &&
    Array.isArray(value.permission_denials) && value.permission_denials.length === 0;
}

function liveWorkspace(): string {
  // Do not use caller-controlled TMPDIR, HOME, cwd, or an existing project.
  const root = realpathSync("/tmp");
  const info = lstatSync(root);
  if (!info.isDirectory() || info.uid !== 0 || ((info.mode & 0o022) !== 0 && (info.mode & 0o1000) === 0))
    refuse("unsafe_live_workspace_parent");
  // mkdtemp reserves a new mode-0700 directory. Retain it after an uncertain
  // process outcome; never recursively delete files a provider may have made.
  return mkdtempSync(join(root, "acfs-live-rehearsal-"));
}

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
      cwd: request.cwd ?? "/", env: request.env, stdio: ["ignore", "pipe", "pipe"], detached: true, shell: false,
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
      if (request.requireQuiescence && child.pid) {
        try {
          process.kill(-child.pid, 0);
          // Closing both pipes is not proof that a background child exited.
          outcome ??= "lingering_processes";
          try { process.kill(-child.pid, "SIGKILL"); } catch { /* Already gone. */ }
        } catch (error) {
          if ((error as NodeJS.ErrnoException).code !== "ESRCH") outcome ??= "lingering_processes";
        }
      }
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
export type NativeAuthState = "not_requested" | "not_checked" | "present" | "missing" | "unknown" | "unsupported";
export function nativeAuthArgs(provider: Provider): string[] | null {
  // These are status subcommands, never the interactive login flow. Claude
  // emits JSON by default; Codex emits its status on stderr, not stdout.
  if (provider === "claude") return ["auth", "status"];
  if (provider === "codex") return ["login", "status"];
  return null; // Never guess flags for an unverified provider protocol.
}
function uniqueJsonObject(bytes: Buffer): Record<string, unknown> | null {
  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    const parsed: unknown = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
    // JSON.parse accepts duplicate keys. Inspect string/punctuation tokens after
    // syntax validation, decoding escaped keys before comparing each object's
    // key set. Nested objects have independent sets; string values are not keys.
    const tokens = /"(?:\\.|[^"\\])*"|[{}\[\]:,]/g;
    const stack: (Set<string> | null)[] = [];
    let token: RegExpExecArray | null;
    while ((token = tokens.exec(text))) {
      const value = token[0];
      if (value === "{") stack.push(new Set());
      else if (value === "[") stack.push(null);
      else if (value === "}" || value === "]") stack.pop();
      else if (value.startsWith('"') && /^\s*:/.test(text.slice(tokens.lastIndex))) {
        const keys = stack.at(-1);
        const key = JSON.parse(value) as string;
        if (!keys || keys.has(key)) return null;
        keys.add(key);
      }
    }
    return parsed as Record<string, unknown>;
  } catch { return null; }
}
export function parseNativeAuth(provider: Provider, result: ProbeResult): NativeAuthState {
  if (!nativeAuthArgs(provider)) return "unsupported";
  if (result.outcome !== "ok" && result.outcome !== "exit_nonzero") return "unknown";
  if (provider === "claude") {
    const parsed = uniqueJsonObject(result.stdout);
    if (parsed?.loggedIn === true && result.exitCode === 0) return "present";
    if (parsed?.loggedIn === false && result.exitCode === 1) return "missing";
    return "unknown";
  }
  let text: string;
  try {
    const decoder = new TextDecoder("utf-8", { fatal: true });
    if (decoder.decode(result.stdout).trim() !== "") return "unknown";
    text = decoder.decode(result.stderr).trim();
  } catch { return "unknown"; }
  if (text === "Not logged in" && result.exitCode === 1) return "missing";
  if (result.exitCode !== 0) return "unknown";
  if (/^Logged in using (ChatGPT|access token|personal access token|workload identity|Amazon Bedrock API key|Amazon Bedrock AWS access keys)$/.test(text) ||
      /^Logged in using an API key - [^\x00-\x1f\x7f]{1,256}$/.test(text)) return "present";
  return "unknown";
}

/** Preflight before probes, then recheck at publication. Never overwrite evidence. */
export function preflightEvidencePath(path: string): string {
  if (!path || /[\x00-\x1f\x7f]/.test(path)) refuse("invalid_evidence_path");
  const target = resolve(path);
  const uid = process.getuid?.();
  if (uid === undefined) refuse("posix_host_required");
  const parent = dirname(target);
  let current = "/";
  for (const part of parent.split("/").filter(Boolean)) {
    current = join(current, part);
    const info = lstatSync(current);
    const stickyRoot = info.uid === 0 && (info.mode & 0o1000) !== 0;
    if (!info.isDirectory() || info.isSymbolicLink() || (info.uid !== 0 && info.uid !== uid) ||
        ((info.mode & 0o022) !== 0 && !stickyRoot)) refuse("unsafe_evidence_directory");
  }
  const info = lstatSync(parent);
  if (info.uid !== uid || (info.mode & 0o022) !== 0) refuse("evidence_parent_must_be_private");
  try { lstatSync(target); } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return target;
    return refuse("evidence_path_unavailable");
  }
  return refuse("evidence_already_exists");
}
export function writeRehearsalEvidence(path: string, report: RehearsalReport): void {
  const target = preflightEvidencePath(path);
  const bytes = Buffer.from(JSON.stringify(report, null, 2) + "\n");
  if (bytes.length > 64 * 1024) refuse("evidence_size_limit");
  let fd: number;
  try { fd = openSync(target, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600); }
  catch { return refuse("evidence_create_failed"); }
  try {
    const info = fstatSync(fd);
    if (!info.isFile() || info.nlink !== 1 || info.uid !== process.getuid!() || (info.mode & 0o077) !== 0)
      refuse("evidence_file_unsafe");
    writeFileSync(fd, bytes);
    fsyncSync(fd);
  } finally { closeSync(fd); }
}

export interface RehearsalOptions {
  execute?: boolean;
  nativeAuth?: boolean;
  requireNativeAuth?: boolean;
  liveModels?: readonly string[];
  liveTimeoutSeconds?: number;
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
  const live = buildLiveModelPlan(checked, options.liveModels, options.liveTimeoutSeconds);
  const report: RehearsalReport = {
    schema: "acfs.agent-profile-rehearsal.v1", generatedAt: new Date().toISOString(),
    executed: options.execute === true, status: "planned", scope: live ? "isolated-cli-and-live-model" : "isolated-cli-startup-and-local-auth",
    liveAuthenticationVerified: false, globalActivationRequested: false, modelPromptSent: false,
    nativeAuthRequested: options.nativeAuth === true || options.requireNativeAuth === true,
    nativeAuthRequired: options.requireNativeAuth === true,
    ...(live ? { liveModelPolicy: { timeoutMs: live.timeoutMs, maximumCliAttempts: checked.selections.length,
      automaticRetries: false as const, mayIncurCharges: true as const, responseVerified: false } } : {}),
    profiles: checked.selections.map((s) => ({
      provider: s.provider, profileRef: s.ref, status: "planned", localAuthPresent: null,
      version: null, nativeAuth: options.nativeAuth || options.requireNativeAuth ? "not_checked" : "not_requested", checks: [],
      ...(live ? { liveModel: { requestedModel: live.models[s.provider]!, status: "planned" as const, attempts: 0 } } : {}),
      nextAction: live ? "Pass --run to permit one live model CLI attempt per profile. This may consume quota or incur charges." :
        "Pass --run to execute these local checks; no model prompt will be sent.",
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
  let liveStopped = false;
  for (let index = 0; index < checked.selections.length; index++) {
    const selection = checked.selections[index]!;
    const profile = report.profiles[index]!;
    if (profile.liveModel) profile.liveModel.status = "not_attempted";
    if (cancelled || options.signal?.aborted) {
      cancelled = true; profile.status = "warn"; profile.nextAction = "Rehearsal cancelled; this profile was not checked.";
      continue;
    }
    if (liveStopped) {
      profile.status = "warn";
      profile.nextAction = "A prior live check was unconfirmed. Later profiles were not run; inspect before making another paid attempt.";
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
    if (report.nativeAuthRequested) {
      const args = nativeAuthArgs(selection.provider);
      if (!args) {
        profile.nativeAuth = "unsupported";
        profile.checks.push({ id: "native_auth_status", status: report.nativeAuthRequired ? "fail" : "skipped",
          code: "native_status_unavailable", exitCode: null });
      } else {
        const native = await probe("native_auth_status", ["exec", selection.provider, selection.name, "--", ...args]);
        profile.nativeAuth = parseNativeAuth(selection.provider, native);
        const check = profile.checks.at(-1)!;
        if (profile.nativeAuth === "present") Object.assign(check, { status: "pass", code: "native_auth_present" });
        else if (profile.nativeAuth === "missing") Object.assign(check, { status: "fail", code: "native_auth_missing" });
        else if (native.outcome === "ok" || native.outcome === "exit_nonzero")
          Object.assign(check, { status: report.nativeAuthRequired ? "fail" : "warn", code: "native_status_unrecognized" });
        if (cancelled) continue;
      }
    }
    if (live && profile.liveModel) {
      // Do not turn an unknown/failed local check into paid authentication
      // discovery. All requested local prerequisites must positively pass.
      if (!profile.version || profile.checks.some((c) => c.status !== "pass")) {
        profile.checks.push({ id: "live_model", status: "fail", code: "live_prerequisite_not_confirmed", exitCode: null });
        liveStopped = true;
      } else if (options.signal?.aborted) {
        cancelled = true;
        continue;
      } else {
        const challenge = `ACFS_LIVE_${randomBytes(16).toString("hex")}`;
        const args = ["exec", selection.provider, selection.name, "--",
          ...liveModelArgs(selection.provider, live.models[selection.provider]!, challenge)];
        const cwd = liveWorkspace();
        profile.liveModel.attempts = 1;
        profile.liveModel.status = "unconfirmed";
        if (report.modelPromptSent === false) report.modelPromptSent = null;
        let result: ProbeResult;
        try {
          result = await deps.run({ binary, args, env, cwd, timeoutMs: live.timeoutMs,
            signal: options.signal, requireQuiescence: true });
        } catch {
          result = { outcome: "spawn_failed", exitCode: null, stdout: Buffer.alloc(0), stderr: Buffer.alloc(0) };
        }
        cancelled ||= result.outcome === "cancelled" || options.signal?.aborted === true;
        const verified = !cancelled && liveModelResponseMatches(selection.provider, result, challenge);
        profile.liveModel.status = verified ? "verified" : "unconfirmed";
        if (verified) report.modelPromptSent = true;
        profile.checks.push({ id: "live_model", status: verified ? "pass" : "fail",
          code: verified ? "live_response_verified" : result.outcome === "ok" ? "live_response_unrecognized" : `live_${result.outcome}`,
          exitCode: result.exitCode });
        liveStopped = !verified;
        if (cancelled) continue;
      }
    }
    const after = await probe("profile_status_after", statusArgs);
    const finalState = parseProfileStatus(after, selection);
    if (!finalState || !finalState.loggedIn || finalState.locked) {
      if (after.outcome === "ok") Object.assign(profile.checks.at(-1)!, { status: "fail", code: "profile_state_not_confirmed_after_execution" });
      profile.nextAction = "Inspect the isolated profile after execution. ACFS did not restore credentials, unlock it, or retry.";
      continue;
    }
    profile.status = profile.checks.some((c) => c.status === "fail") ? "fail" :
      profile.checks.some((c) => c.status === "warn") ? "warn" : "pass";
    profile.nextAction = profile.liveModel?.status === "verified" ?
      "The isolated CLI completed the live challenge. This is one response, not account identity, future quota, or sustained swarm-capacity certification." :
      profile.liveModel ? "Live response not verified. Inspect local checks and provider access before retrying; ACFS did not retry or rotate accounts." :
      profile.nativeAuth === "missing" ? AUTH_GUIDANCE :
      profile.nativeAuth === "unknown" ? "Native authentication status was not recognized. Inspect the provider locally; no login or retry was attempted." :
      profile.nativeAuth === "unsupported" && report.nativeAuthRequired ? "No verified native status protocol is available for this provider; the required check did not pass." :
      "Local profile and isolated CLI startup checked. Server-side authentication, token validity, quota, and model execution are NOT verified.";
  }
  report.status = cancelled ? "cancelled" : report.profiles.some((p) => p.status === "fail") ? "fail" :
    report.profiles.some((p) => p.status !== "pass") ? "warn" : "pass";
  if (report.liveModelPolicy) report.liveModelPolicy.responseVerified = !cancelled &&
    report.profiles.every((p) => p.liveModel?.status === "verified" && p.status === "pass");
  return report;
}

export function formatRehearsal(report: RehearsalReport): string {
  const lines = ["ACFS isolated agent profile rehearsal", `Status: ${report.status}`, "Profile references follow --profile argument order; names and raw output are omitted."];
  for (const profile of report.profiles) {
    lines.push(`${profile.profileRef} (${profile.provider}): ${profile.status}`);
    if (report.nativeAuthRequested) lines.push(`  native authentication status: ${profile.nativeAuth}`);
    if (profile.liveModel) lines.push(`  live model (${profile.liveModel.requestedModel}): ${profile.liveModel.status}; CLI attempts=${profile.liveModel.attempts}`);
    for (const check of profile.checks) lines.push(`  ${check.id}: ${check.status} (${check.code})`);
    lines.push(`  ${profile.nextAction}`);
  }
  lines.push(report.liveModelPolicy ?
    "Live checks may incur charges. No global activation was requested; raw responses are withheld. A timeout does not prove no request was billed." :
    "No global activation or model prompt was requested. CAAM/provider commands may update their own local metadata.");
  return lines.join("\n");
}
export const REHEARSAL_HELP = `Usage: scripts/agent-readiness-audit.sh --rehearse --profile PROVIDER:NAME [--profile ...] [--run] [--native-auth] [--require-native-auth] [--output FILE] [--json] [--timeout SECONDS]

Default: plan only. --run explicitly permits local CAAM status and isolated CLI
--version checks (1-8 profiles; per-command timeout 1-30 seconds, default 10).
Providers: claude, codex, gemini, agy. Use ISOLATED profiles from caam profile ls,
not vault-only profiles from caam ls. Busy profiles are never unlocked.

CAAM exec owns isolation and locks. No activate, login, refresh,
quota rotation or task dispatch is requested. API-key environment overrides are
removed. Local files/CLI startup do not prove live authentication or token validity.
--live-model claude:MODEL explicitly selects a live check (repeat per provider).
Without --run it only previews. With --run it may consume quota/incur charges:
one fixed random challenge per profile, no ACFS retries, fresh private workspace,
tools/MCP/hooks disabled via CLI flags, and no session persistence requested.
Every selected provider needs an explicit supported model. Live support: claude.
--live-timeout SECONDS bounds each live attempt (1-120, default 60), independently
of --timeout. Claude also receives a 1-turn limit and a $0.25 CLI budget guard;
neither wall time nor the CLI's estimated budget is a guaranteed billing cap.
The first unconfirmed live attempt stops later profiles. Reports omit challenge
and response text. Workspaces are retained; no provider files are deleted.
Trusted CAAM/provider binaries and managed host policy remain part of the trust
boundary. CLI restrictions are not an OS sandbox or proof of account identity.
Use recent Claude Code with --safe-mode; unsupported flags fail without fallback.
--native-auth adds Claude auth status / Codex login status through CAAM exec.
--require-native-auth also rejects unsupported or unrecognized native status.
These are LOCAL provider checks, not proof of server token validity or quota.
--output FILE saves the redacted JSON to a NEW mode-0600 file in an existing,
user-owned directory. Existing files and symlinked paths are refused. This
explicit export also works in plan mode; it never writes raw command output.
Raw output, account names and paths are omitted from reports.

Example: --rehearse --profile claude:work --profile codex:review --run --json`;
export async function rehearsalMain(args: string[]): Promise<number> {
  let json = false;
  let completed: RehearsalReport | undefined;
  try {
    let execute = false;
    let nativeAuth = false;
    let requireNativeAuth = false;
    const liveModels: string[] = [];
    let liveTimeoutSeconds: number | undefined;
    let output: string | undefined;
    let timeout = 10;
    const selections: string[] = [];
    for (let i = 0; i < args.length; i++) {
      switch (args[i]) {
        case "--help": case "-h": console.log(REHEARSAL_HELP); return 0;
        case "--json": json = true; break;
        case "--run": execute = true; break;
        case "--native-auth": nativeAuth = true; break;
        case "--require-native-auth": nativeAuth = true; requireNativeAuth = true; break;
        case "--live-model": liveModels.push(args[++i] ?? ""); break;
        case "--live-timeout": {
          const value = args[++i] ?? "";
          if (liveTimeoutSeconds !== undefined || !/^[1-9][0-9]{0,2}$/.test(value)) refuse("live_timeout_must_be_1_to_120_seconds");
          liveTimeoutSeconds = Number(value); break;
        }
        case "--output":
          if (output !== undefined || !args[i + 1] || args[i + 1]!.startsWith("--")) refuse("invalid_evidence_path");
          output = args[++i]!; break;
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
    buildLiveModelPlan(plan, liveModels, liveTimeoutSeconds);
    if (output !== undefined) output = preflightEvidencePath(output);
    const controller = new AbortController();
    const stop = (): void => controller.abort();
    process.on("SIGINT", stop); process.on("SIGTERM", stop); process.on("SIGHUP", stop);
    try {
      const report = await rehearseProfiles(plan, { execute, nativeAuth, requireNativeAuth, liveModels, liveTimeoutSeconds, signal: controller.signal });
      completed = report;
      if (output !== undefined) writeRehearsalEvidence(output, report);
      console.log(json ? JSON.stringify(report, null, 2) : formatRehearsal(report));
      return report.status === "cancelled" ? 130 : report.status === "planned" || report.status === "pass" ? 0 : 1;
    } finally { process.off("SIGINT", stop); process.off("SIGTERM", stop); process.off("SIGHUP", stop); }
  } catch (error) {
    const code = error instanceof RehearsalError ? error.code : "rehearsal_failed";
    if (json || args.includes("--json")) console.log(JSON.stringify({ schema: "acfs.agent-profile-rehearsal.error.v1", code, report: completed }));
    else {
      if (completed) console.log(formatRehearsal(completed));
      console.error(`Rehearsal refused: ${code}. Run with --help for usage.`);
    }
    return 2;
  }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  rehearsalMain(process.argv.slice(2)).then((code) => { process.exitCode = code; });
}