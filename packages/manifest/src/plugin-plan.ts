/** Deterministic, explicit selection for reviewed target-user plugin installs. */
import { createHash } from "node:crypto";

export interface PluginPlanTarget {
  os: string;
  version: string;
  arch: string;
  libc: string;
}
export interface PluginPlanProvenance {
  packageId: string;
  version: string;
  sourceCommit: string;
  pluginSha256: string;
}
/** Structural subset of the canonical Module; callers must validate it first. */
export interface PlannablePluginModule {
  id: string;
  phase?: number;
  run_as: string;
  enabled_by_default: boolean;
  dependencies?: string[];
  install: string[];
  verify: string[];
  plugin?: PluginPlanProvenance;
  verified_installer?: {
    tool: string;
    url?: string;
    runner: string;
    args?: string[];
    env?: string[];
    fallback_url?: string;
  };
}
export interface PluginPlanPrerequisite {
  id: string;
  phase?: number;
  dependencies?: string[];
  verify: string[];
}
export interface PluginInstallAction {
  id: string;
  installer: { tool: string; url: string; sha256: string; runner: "bash" | "sh"; args: string[] };
  verify: string[];
}
export interface PluginInstallPlan {
  schema: "acfs.plugin-install-plan.v1";
  package: PluginPlanProvenance;
  target: PluginPlanTarget;
  trust: { manifestSha256: string; checksumsSha256: string };
  requested: string[];
  skipped: string[];
  dependencyIds: string[];
  prerequisites: Array<{ id: string; verify: string[] }>;
  actions: PluginInstallAction[];
  planSha256: string;
}
export interface PluginPlanInput {
  modules: readonly PlannablePluginModule[];
  firstPartyModules: readonly PluginPlanPrerequisite[];
  installers: Record<string, { url: string; sha256: string }>;
  target: PluginPlanTarget;
  trust: PluginInstallPlan["trust"];
  only: readonly string[];
  skip?: readonly string[];
}
export class PluginPlanError extends Error {
  readonly code = "plugin_install_plan_invalid";
  constructor(message: string) {
    super(message);
    this.name = "PluginPlanError";
  }
}
const ID = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/;
const HEX = /^[a-f0-9]{64}$/i;
const LIMIT = 1024;
function refuse(message: string): never {
  throw new PluginPlanError(message);
}
function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}
function selections(value: readonly string[], label: string): string[] {
  if (
    !Array.isArray(value) ||
    value.length > LIMIT ||
    value.some((id) => typeof id !== "string" || !ID.test(id))
  ) {
    return refuse(`${label} must be a bounded array of exact module IDs`);
  }
  if (new Set(value).size !== value.length) return refuse(`${label} contains duplicate module IDs`);
  return [...value].sort(compare);
}
function frozen<T>(value: T): T {
  if (value && typeof value === "object") {
    for (const child of Object.values(value)) frozen(child);
    Object.freeze(value);
  }
  return value;
}

/** Plans are data, not authority. The CLI reloads archive/review/trust on every run. */
export function buildPluginInstallPlan(input: PluginPlanInput): PluginInstallPlan {
  const requested = selections(input.only, "--only");
  const skipped = selections(input.skip ?? [], "--skip");
  if (requested.length === 0) refuse("Select at least one plugin module explicitly with --only");
  if (!input.modules.length || input.modules.length + input.firstPartyModules.length > LIMIT) {
    refuse("Plugin graph is empty or exceeds its module budget");
  }
  if (!HEX.test(input.trust.manifestSha256) || !HEX.test(input.trust.checksumsSha256)) {
    refuse("Canonical manifest and checksum digests are required");
  }
  if (
    Object.keys(input.target).sort().join(",") !== "arch,libc,os,version" ||
    Object.values(input.target).some(
      (part) => typeof part !== "string" || !/^[a-z0-9][a-z0-9_.-]{0,63}$/.test(part),
    )
  ) {
    refuse("An explicit complete target tuple is required");
  }
  const plugins = new Map(input.modules.map((module) => [module.id, module]));
  const firstParty = new Map(input.firstPartyModules.map((module) => [module.id, module]));
  if (
    plugins.size !== input.modules.length ||
    firstParty.size !== input.firstPartyModules.length ||
    [...plugins.keys()].some((id) => firstParty.has(id))
  )
    refuse("Duplicate module IDs in the merged graph");
  for (const module of [...input.firstPartyModules, ...input.modules]) {
    if (
      !ID.test(module.id) ||
      !Number.isInteger(module.phase ?? 1) ||
      (module.phase ?? 1) < 1 ||
      (module.phase ?? 1) > 10
    )
      refuse("Invalid module identity or phase");
    selections(module.dependencies ?? [], "Dependencies");
  }
  for (const id of [...requested, ...skipped]) {
    if (!plugins.has(id)) refuse("Selections must name modules in this reviewed plugin package");
  }
  const excluded = new Set(skipped);
  const visiting = new Set<string>();
  const visited = new Set<string>();
  const ordered: string[] = [];
  const phase = (id: string): number => (plugins.get(id) ?? firstParty.get(id))?.phase ?? 1;
  const order = (a: string, b: string): number => phase(a) - phase(b) || compare(a, b);
  const visit = (id: string): void => {
    if (excluded.has(id)) refuse("A requested module or required dependency is explicitly skipped");
    if (visiting.has(id)) refuse("Dependency cycle in the selected plugin graph");
    if (visited.has(id)) return;
    const module = plugins.get(id) ?? firstParty.get(id);
    if (!module) return refuse("A selected module has an unknown dependency");
    visiting.add(id);
    for (const dependency of [...(module.dependencies ?? [])].sort(order)) {
      if (firstParty.has(id) && plugins.has(dependency))
        refuse("First-party prerequisites cannot depend on plugin modules");
      if (phase(dependency) > phase(id))
        refuse("A dependency executes in a later phase than its dependent");
      visit(dependency);
    }
    visiting.delete(id);
    visited.add(id);
    ordered.push(id);
  };
  [...requested].sort(order).forEach(visit);

  const provenance = input.modules[0]!.plugin;
  if (
    !provenance ||
    !/^[a-z][a-z0-9_.-]{0,127}$/.test(provenance.packageId) ||
    !HEX.test(provenance.pluginSha256) ||
    !/^[a-f0-9]{40}$/i.test(provenance.sourceCommit) ||
    !provenance.version ||
    /[\x00-\x1f\x7f]/.test(provenance.version)
  ) {
    return refuse("Reviewed package provenance is missing or malformed");
  }
  const slug = provenance.packageId.replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  const actions: PluginInstallAction[] = [];
  const prerequisites: PluginInstallPlan["prerequisites"] = [];
  for (const id of ordered) {
    const module = plugins.get(id);
    if (!module) {
      const dependency = firstParty.get(id)!;
      if (
        !Array.isArray(dependency.verify) ||
        !dependency.verify.length ||
        dependency.verify.some(
          (check) => typeof check !== "string" || !check.trim() || check.includes("\0"),
        )
      ) {
        refuse("First-party prerequisite has no usable verification checks");
      }
      prerequisites.push({ id, verify: [...dependency.verify] });
      continue;
    }
    if (
      !id.startsWith(`plugin.${slug}.`) ||
      !module.plugin ||
      module.plugin.packageId !== provenance.packageId ||
      module.plugin.version !== provenance.version ||
      module.plugin.sourceCommit.toLowerCase() !== provenance.sourceCommit.toLowerCase() ||
      module.plugin.pluginSha256.toLowerCase() !== provenance.pluginSha256.toLowerCase()
    ) {
      refuse("All plugin modules must belong to one reviewed package snapshot");
    }
    if (
      module.run_as !== "target_user" ||
      module.enabled_by_default ||
      module.install.length !== 0
    ) {
      refuse("Only explicitly selected target-user verified installers are executable");
    }
    const installer = module.verified_installer;
    const trusted =
      installer && Object.hasOwn(input.installers, installer.tool)
        ? input.installers[installer.tool]
        : undefined;
    if (
      !installer ||
      !/^[a-z][a-z0-9_]*$/.test(installer.tool) ||
      !trusted ||
      !HEX.test(trusted.sha256) ||
      trusted.url !== installer.url ||
      !["bash", "sh"].includes(installer.runner) ||
      (installer.env?.length ?? 0) !== 0 ||
      installer.fallback_url !== undefined
    )
      refuse("Installer is not bound to canonical checksums and an allowed runner");
    let url: URL;
    try {
      url = new URL(trusted.url);
    } catch {
      return refuse("Installer URL is invalid");
    }
    if (url.protocol !== "https:" || url.username || url.password || url.hash)
      refuse("Installer URL must be credential-free HTTPS");
    const args = installer.args ?? [];
    if (
      !Array.isArray(args) ||
      args.length > 128 ||
      args.some(
        (arg) =>
          typeof arg !== "string" ||
          arg === "--" ||
          arg.length > 4096 ||
          /[\x00-\x1f\x7f]/.test(arg),
      )
    )
      refuse("Installer arguments are invalid");
    if (!Array.isArray(module.verify) || !module.verify.length)
      refuse("Plugin module has no verification checks");
    const verify = module.verify.map((check) => {
      const match = /^command -v -- ([A-Za-z0-9][A-Za-z0-9._+-]*) >\/dev\/null 2>&1$/.exec(check);
      if (!match)
        return refuse("Plugin verification must be a canonical executable-existence check");
      return match[1]!;
    });
    actions.push({
      id,
      installer: {
        tool: installer.tool,
        url: trusted.url,
        sha256: trusted.sha256.toLowerCase(),
        runner: installer.runner as "bash" | "sh",
        args: [...args],
      },
      verify,
    });
  }
  const payload = {
    schema: "acfs.plugin-install-plan.v1" as const,
    package: {
      packageId: provenance.packageId,
      version: provenance.version,
      sourceCommit: provenance.sourceCommit.toLowerCase(),
      pluginSha256: provenance.pluginSha256.toLowerCase(),
    },
    target: {
      os: input.target.os,
      version: input.target.version,
      arch: input.target.arch,
      libc: input.target.libc,
    },
    trust: {
      manifestSha256: input.trust.manifestSha256.toLowerCase(),
      checksumsSha256: input.trust.checksumsSha256.toLowerCase(),
    },
    requested,
    skipped,
    dependencyIds: ordered.filter((id) => !requested.includes(id)),
    prerequisites,
    actions,
  };
  const planSha256 = createHash("sha256").update(JSON.stringify(payload)).digest("hex");
  return frozen({ ...payload, planSha256 });
}
