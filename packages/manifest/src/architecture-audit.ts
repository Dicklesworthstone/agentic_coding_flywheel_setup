#!/usr/bin/env bun
/** Inspect selected ACFS module executables without launching them. (bd-wqrgy) */
import { accessSync, constants, statSync } from "node:fs";
import { delimiter, dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { inspectBinary, normalizeArchitecture, type BinaryArchitectureResult,
  type LinuxArchitecture } from "./binary-architecture.js";

export interface ArchitectureCatalogue {
  modules: readonly { id: string; optional: boolean; enabledByDefault: boolean }[];
  commands: readonly { moduleId: string; cliName: string }[];
  provenance: { acfsVersion: string; manifestSha256: string; checksumsYamlSha256: string };
}
export interface ArchitectureAuditOptions {
  target: LinuxArchitecture;
  home: string;
  only?: readonly string[];
  binaries?: ReadonlyMap<string, string>;
  pathEntries?: readonly string[];
}
export interface ModuleArchitectureEvidence {
  moduleId: string;
  command: string | null;
  optional: boolean;
  enabledByDefault: boolean;
  source: "explicit_artifact" | "local_lookup" | "no_command_metadata";
  path: string | null;
  result: BinaryArchitectureResult;
}
export interface ArchitectureAuditReport {
  schema: "acfs.architecture-audit.v1";
  target: LinuxArchitecture;
  host: { platform: string; architecture: string; loaderChecks: boolean };
  provenance: ArchitectureCatalogue["provenance"];
  status: "compatible_headers" | "blocked" | "incomplete";
  exitCode: 0 | 1 | 3;
  summary: Record<BinaryArchitectureResult["status"], number>;
  modules: ModuleArchitectureEvidence[];
  policy: { executesCandidates: false; installsModules: false; certifiesReleases: false;
    checksCpuExtensions: false; checksSharedLibraries: false; checksFunctionality: false };
}

const ID = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/;
const COMMAND = /^[A-Za-z0-9][A-Za-z0-9._+-]*$/;
class ArchitectureAuditError extends Error {}
function requireValue(condition: unknown, message: string): asserts condition {
  if (!condition) throw new ArchitectureAuditError(message);
}
function validateCatalogue(catalogue: ArchitectureCatalogue): void {
  requireValue(Array.isArray(catalogue.modules) && catalogue.modules.length > 0
    && catalogue.modules.length <= 2048, "Invalid generated module catalogue.");
  const ids = new Set<string>();
  for (const module of catalogue.modules) {
    requireValue(module && typeof module.id === "string" && ID.test(module.id) && !ids.has(module.id)
      && typeof module.optional === "boolean" && typeof module.enabledByDefault === "boolean",
    "Invalid or duplicate generated module identity.");
    ids.add(module.id);
  }
  requireValue(Array.isArray(catalogue.commands) && catalogue.commands.length <= 2048,
    "Invalid generated command catalogue.");
  const commands = new Set<string>();
  for (const command of catalogue.commands) {
    requireValue(command && ids.has(command.moduleId) && !commands.has(command.moduleId)
      && typeof command.cliName === "string" && COMMAND.test(command.cliName),
    "Invalid, unknown or duplicate module command metadata.");
    commands.add(command.moduleId);
  }
  requireValue(catalogue.provenance && typeof catalogue.provenance.acfsVersion === "string"
    && /^[a-f0-9]{64}$/.test(catalogue.provenance.manifestSha256)
    && /^[a-f0-9]{64}$/.test(catalogue.provenance.checksumsYamlSha256), "Missing catalogue provenance.");
}
function displayPath(path: string, home: string): string {
  const root = resolve(home);
  const value = resolve(path);
  if (value === root) return "$HOME";
  return value.startsWith(root + "/") ? "$HOME/" + value.slice(root.length + 1) : value;
}
function findExecutable(command: string, dirs: readonly string[]): string | undefined {
  for (const dir of dirs) {
    const candidate = join(dir, command);
    try {
      if (!statSync(candidate).isFile()) continue;
      accessSync(candidate, constants.X_OK);
      return candidate;
    } catch { /* An absent or non-executable candidate is not a PATH executable. */ }
  }
  return undefined;
}

export function buildArchitectureAudit(
  catalogue: ArchitectureCatalogue, options: ArchitectureAuditOptions,
): ArchitectureAuditReport {
  validateCatalogue(catalogue);
  const target = normalizeArchitecture(options.target);
  requireValue(target, "Target must be x86_64 or aarch64 (amd64/arm64 aliases accepted).");
  requireValue(typeof options.home === "string" && options.home.length > 0, "A home directory is required.");
  const byId = new Map(catalogue.modules.map(module => [module.id, module]));
  const binaries = options.binaries ?? new Map<string, string>();
  // Explicit artifacts imply exactly that scope unless --only is supplied.
  // A typo never silently changes the request into a whole-host audit.
  const selected = options.only?.length ? [...new Set(options.only)]
    : binaries.size ? [...binaries.keys()] : catalogue.modules.map(module => module.id);
  requireValue(selected.length > 0 && selected.length <= 2048, "Select at least one module.");
  for (const id of selected) requireValue(byId.has(id), `Unknown module: ${JSON.stringify(id)}`);
  for (const [id, path] of binaries) {
    requireValue(selected.includes(id), `Artifact supplied outside the selected scope: ${JSON.stringify(id)}`);
    requireValue(typeof path === "string" && path.length > 0 && !/[\x00-\x1f\x7f]/.test(path),
      "Artifact paths must be nonempty and control-free.");
  }
  // Mirrors the readiness auditor's managed-bin precedence. Report the first
  // executable even when it is incompatible; never hide it with a later copy.
  const dirs = [...new Set([join(options.home, ".local/bin"), join(options.home, ".bun/bin"),
    join(options.home, ".cargo/bin"), ...(options.pathEntries ?? (process.env.PATH ?? "").split(delimiter))]
    .filter(path => path && isAbsolute(path)).map(path => resolve(path)))];
  const commandById = new Map(catalogue.commands.map(command => [command.moduleId, command.cliName]));
  const loaderChecks = process.platform === "linux" && normalizeArchitecture(process.arch) === target;
  const modules: ModuleArchitectureEvidence[] = selected.map(id => {
    const module = byId.get(id)!;
    const command = commandById.get(id) ?? null;
    const explicit = binaries.get(id);
    const candidate = explicit !== undefined ? resolve(explicit) : command ? findExecutable(command, dirs) : undefined;
    const result: BinaryArchitectureResult = candidate ? inspectBinary(candidate, { target, checkHostInterpreter: loaderChecks })
      : { target, format: "other", interpreterChecked: false, status: command ? "missing" : "unknown",
          code: command ? "binary_missing" : "module_has_no_cli_metadata",
          detail: command ? "No executable found in managed bins or the selected PATH."
            : "No single CLI is declared for this module; architecture support is not inferred." };
    return { moduleId: id, command, optional: module.optional, enabledByDefault: module.enabledByDefault,
      source: explicit !== undefined ? "explicit_artifact" : command ? "local_lookup" : "no_command_metadata",
      path: candidate ? displayPath(candidate, options.home) : null, result };
  });
  const summary = { compatible: 0, incompatible: 0, unknown: 0, missing: 0, unreadable: 0 };
  for (const module of modules) summary[module.result.status]++;
  const blocked = summary.incompatible + summary.missing + summary.unreadable > 0;
  return { schema: "acfs.architecture-audit.v1", target,
    host: { platform: process.platform, architecture: process.arch, loaderChecks },
    provenance: { ...catalogue.provenance },
    status: blocked ? "blocked" : summary.unknown ? "incomplete" : "compatible_headers",
    exitCode: blocked ? 1 : summary.unknown ? 3 : 0, summary, modules,
    policy: { executesCandidates: false, installsModules: false, certifiesReleases: false,
      checksCpuExtensions: false, checksSharedLibraries: false, checksFunctionality: false } };
}

export const ARCHITECTURE_USAGE = `ACFS module architecture audit (read-only)
Usage: bun run architecture:audit -- [--arch x86_64|aarch64] [--only MODULE]
       [--binary MODULE=PATH] [--home PATH] [--path PATH] [--json]

--only is repeatable and accepts comma-separated module IDs.
--binary is repeatable; inspect downloaded artifacts without executing them.
Artifacts imply their own scope unless --only explicitly selects a larger set.
With neither flag, audit all canonical modules; modules without CLI metadata
and script wrappers are UNKNOWN, not architecture-certified.
--path replaces ambient PATH; managed home bin directories are still searched.
--arch defaults to this Linux host. Cross-target inspection requires --arch.
Exit 0: matching ELF headers; 1: missing/incompatible/unreadable; 2: usage/error;
3: incomplete (wrappers or missing metadata). No CPU/libc/functionality proof.
`;

export function runArchitectureAudit(args: string[], catalogue: ArchitectureCatalogue): { output: string; exitCode: number } {
  const only: string[] = [];
  const binaries = new Map<string, string>();
  let arch = process.platform === "linux" ? normalizeArchitecture(process.arch) : undefined;
  let home = process.env.HOME ?? process.cwd();
  let pathEntries: string[] | undefined;
  let json = false;
  for (let i = 0; i < args.length; i++) {
    const flag = args[i];
    if (flag === "--") continue;
    if (flag === "--help" || flag === "-h") return { output: ARCHITECTURE_USAGE, exitCode: 0 };
    if (flag === "--json") { json = true; continue; }
    requireValue(["--arch", "--only", "--binary", "--home", "--path"].includes(flag),
      `Unknown option: ${JSON.stringify(flag)}`);
    const value = args[++i];
    requireValue(typeof value === "string" && !value.startsWith("--") && (value.length > 0 || flag === "--path"),
      `Missing value for ${flag}.`);
    if (flag === "--arch") {
      arch = normalizeArchitecture(value);
      requireValue(arch, "Unsupported architecture; use x86_64 or aarch64.");
    } else if (flag === "--home") {
      home = resolve(value);
    } else if (flag === "--path") {
      pathEntries = value.split(delimiter).filter(Boolean);
      requireValue(pathEntries.every(path => isAbsolute(path)), "--path entries must be absolute directories.");
    } else if (flag === "--only") {
      const ids = value.split(",");
      requireValue(ids.every(id => ID.test(id)), "--only requires exact, nonempty module IDs.");
      only.push(...ids);
    } else {
      const index = value.indexOf("=");
      const id = value.slice(0, index);
      requireValue(index > 0 && ID.test(id) && index < value.length - 1 && !binaries.has(id),
        "--binary requires one unique MODULE=PATH binding per module.");
      binaries.set(id, value.slice(index + 1));
    }
  }
  requireValue(arch, "Use --arch on a non-Linux or unsupported host.");
  const report = buildArchitectureAudit(catalogue, { target: arch, home, only, binaries, pathEntries });
  const output = json ? JSON.stringify(report, null, 2) + "\n"
    : [`ACFS architecture audit: ${report.target} (${report.status})`,
      ...report.modules.map(row => `${row.result.status.toUpperCase()} ${row.moduleId}: ${row.result.code}`
        + (row.path ? ` (${JSON.stringify(row.path)})` : "")),
      "Header evidence only: no candidate execution, install, CPU/libc or functional certification.", ""].join("\n");
  return { output, exitCode: report.exitCode };
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length === 1 && (args[0] === "--help" || args[0] === "-h")) {
    process.stdout.write(ARCHITECTURE_USAGE);
    return;
  }
  // These are canonical generator outputs from this trusted checkout, not an
  // independently maintained architecture catalogue or user-supplied script.
  const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
  const modulesUrl = pathToFileURL(join(root, "apps/web/lib/generated/manifest-modules.ts")).href;
  const commandsUrl = pathToFileURL(join(root, "apps/web/lib/generated/manifest-commands.ts")).href;
  const metadata = await import(modulesUrl);
  const commands = await import(commandsUrl);
  const result = runArchitectureAudit(args, { modules: metadata.manifestModules,
    commands: commands.manifestCommands, provenance: metadata.manifestProvenance });
  process.stdout.write(result.output);
  process.exitCode = result.exitCode;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error: unknown) => {
    console.error(error instanceof ArchitectureAuditError ? error.message
      : "Architecture audit failed. Check arguments and the complete checkout; run --help.");
    process.exitCode = 2;
  });
}
