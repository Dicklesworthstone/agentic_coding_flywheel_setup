import {
  manifestModules,
  manifestSelectionProfiles,
  type ManifestModuleMetadata,
  type ManifestSelectionProfile,
  type ManifestSelectionProfileId,
} from "./generated/manifest-modules";

export type ModuleSelectionProfileId = ManifestSelectionProfileId;

export interface ModuleSelectionInput {
  profile?: ModuleSelectionProfileId;
  onlyModules?: string[];
  onlyPhases?: string[];
  skipModules?: string[];
  skipTags?: string[];
  skipCategories?: string[];
  noDeps?: boolean;
}

export interface ModulePlanEntry {
  id: string;
  description: string;
  category: string;
  phase: number;
  reason: string;
}

export interface ModuleExclusionEntry {
  id: string;
  reason: string;
}

export interface ModuleSelectionPlan {
  ok: boolean;
  profile?: ModuleSelectionProfileId;
  included: ModulePlanEntry[];
  excluded: ModuleExclusionEntry[];
  warnings: string[];
  errors: string[];
  selectedCount: number;
  availableCount: number;
}

interface NormalizedSelection {
  profile?: ManifestSelectionProfile;
  onlyModules: string[];
  onlyPhases: string[];
  skipModules: string[];
  skipTags: string[];
  skipCategories: string[];
  errors: string[];
}

const PHASE_ALIASES: Record<string, string> = {
  base: "1",
  base_deps: "1",
  system: "1",
  user_setup: "2",
  user: "2",
  users: "2",
  filesystem: "3",
  fs: "3",
  shell_setup: "4",
  shell: "4",
  cli_tools: "5",
  cli: "5",
  languages: "6",
  language: "6",
  lang: "6",
  agents: "7",
  agent: "7",
  cloud_db: "8",
  "cloud-db": "8",
  stack: "9",
  finalize: "10",
  final: "10",
};

function nonEmpty(values: string[] | undefined): string[] {
  return (values ?? []).filter((value) => value.length > 0);
}

function normalizePhase(phase: string): string {
  const lower = phase.toLowerCase();
  if (/^[0-9]+$/.test(lower)) return lower;
  return PHASE_ALIASES[lower] ?? phase;
}

function moduleEntry(moduleMetadata: ManifestModuleMetadata, reason: string): ModulePlanEntry {
  return {
    id: moduleMetadata.id,
    description: moduleMetadata.description,
    category: moduleMetadata.category,
    phase: moduleMetadata.phase,
    reason,
  };
}

function normalizeSelection(
  input: ModuleSelectionInput,
  profiles: ManifestSelectionProfile[],
): NormalizedSelection {
  const errors: string[] = [];
  const profile = input.profile
    ? profiles.find((candidate) => candidate.id === input.profile)
    : undefined;

  if (input.profile && !profile) {
    errors.push(`Unknown selection profile: ${input.profile}`);
  }

  const explicitOnlyModules = nonEmpty(input.onlyModules);
  const explicitOnlyPhases = nonEmpty(input.onlyPhases).map(normalizePhase);
  const profileOnlyModules = profile?.onlyModules ?? [];
  const profileOnlyPhases = profile?.onlyPhases.map(normalizePhase) ?? [];
  const profileHasSelectors = profileOnlyModules.length > 0 || profileOnlyPhases.length > 0;
  const explicitHasSelectors = explicitOnlyModules.length > 0 || explicitOnlyPhases.length > 0;

  if (profileHasSelectors && explicitHasSelectors) {
    errors.push(
      `Selection error: profile ${profile?.id ?? input.profile} cannot be combined with explicit --only or --only-phase selectors.`,
    );
  }

  return {
    profile,
    onlyModules: profileHasSelectors ? [...profileOnlyModules] : explicitOnlyModules,
    onlyPhases: profileHasSelectors ? [...profileOnlyPhases] : explicitOnlyPhases,
    skipModules: nonEmpty(input.skipModules),
    skipTags: nonEmpty(input.skipTags),
    skipCategories: nonEmpty(input.skipCategories),
    errors,
  };
}

export function resolveModuleSelection(
  input: ModuleSelectionInput = {},
  modules: ManifestModuleMetadata[] = manifestModules,
  profiles: ManifestSelectionProfile[] = manifestSelectionProfiles,
): ModuleSelectionPlan {
  const normalized = normalizeSelection(input, profiles);
  const warnings: string[] = [];
  const errors = [...normalized.errors];
  const moduleById = new Map(modules.map((moduleMetadata) => [moduleMetadata.id, moduleMetadata]));
  const phaseSet = new Set(modules.map((moduleMetadata) => String(moduleMetadata.phase)));

  const desired = new Map<string, string>();
  const skipped = new Map<string, string>();
  const excluded = new Map<string, string>();

  if (errors.length === 0) {
    if (normalized.onlyModules.length > 0) {
      for (const moduleId of normalized.onlyModules) {
        if (!moduleById.has(moduleId)) {
          errors.push(`Unknown module id in --only: ${moduleId}`);
        } else {
          desired.set(moduleId, normalized.profile ? `profile ${normalized.profile.id}` : "explicitly requested");
        }
      }
    } else if (normalized.onlyPhases.length > 0) {
      for (const phase of normalized.onlyPhases) {
        if (!phaseSet.has(phase)) {
          errors.push(`Unknown phase in --only-phase: ${phase}`);
        }
      }
      if (errors.length === 0) {
        const selectedPhases = new Set(normalized.onlyPhases);
        for (const moduleMetadata of modules) {
          if (selectedPhases.has(String(moduleMetadata.phase))) {
            desired.set(
              moduleMetadata.id,
              normalized.profile ? `profile ${normalized.profile.id}` : `phase ${moduleMetadata.phase}`,
            );
          }
        }
      }
    } else {
      for (const moduleMetadata of modules) {
        if (moduleMetadata.enabledByDefault) {
          desired.set(moduleMetadata.id, "default");
        } else {
          excluded.set(moduleMetadata.id, "disabled by default");
        }
      }
    }
  }

  if (errors.length === 0) {
    for (const moduleId of normalized.skipModules) {
      if (!moduleById.has(moduleId)) {
        errors.push(`Unknown module id in --skip: ${moduleId}`);
      } else {
        skipped.set(moduleId, "explicitly skipped");
      }
    }
  }

  if (errors.length === 0) {
    for (const tag of normalized.skipTags) {
      for (const moduleMetadata of modules) {
        if (moduleMetadata.tags.includes(tag) && !skipped.has(moduleMetadata.id)) {
          skipped.set(moduleMetadata.id, `skipped tag ${tag}`);
        }
      }
    }

    for (const category of normalized.skipCategories) {
      for (const moduleMetadata of modules) {
        if (moduleMetadata.category === category && !skipped.has(moduleMetadata.id)) {
          skipped.set(moduleMetadata.id, `skipped category ${category}`);
        }
      }
    }

    if (normalized.onlyModules.length > 0) {
      for (const moduleId of normalized.onlyModules) {
        const skipReason = skipped.get(moduleId);
        if (skipReason) {
          errors.push(`Selection error: ${moduleId} was requested with --only and excluded by ${skipReason}`);
        }
      }
    }
  }

  if (errors.length === 0) {
    for (const [moduleId, reason] of skipped) {
      if (desired.has(moduleId)) {
        desired.delete(moduleId);
      }
      excluded.set(moduleId, reason);
    }
  }

  function findSkippedDependency(
    moduleId: string,
    path: string[],
    visited: Set<string>,
  ): { skippedModule: string; chain: string[] } | null {
    const moduleMetadata = moduleById.get(moduleId);
    if (!moduleMetadata) return null;

    for (const depId of moduleMetadata.dependencies) {
      if (skipped.has(depId)) {
        return { skippedModule: depId, chain: [...path, depId] };
      }
      if (visited.has(depId)) continue;
      visited.add(depId);
      const found = findSkippedDependency(depId, [...path, depId], visited);
      if (found) return found;
    }

    return null;
  }

  if (errors.length === 0 && input.noDeps !== true) {
    for (const moduleId of desired.keys()) {
      const found = findSkippedDependency(moduleId, [moduleId], new Set([moduleId]));
      if (found) {
        errors.push(`Selection error: ${moduleId} depends on skipped ${found.skippedModule}`);
        errors.push(`Dependency chain: ${found.chain.join(" -> ")}`);
        errors.push(`Remove --skip ${found.skippedModule} or omit ${moduleId}.`);
        break;
      }
    }
  }

  if (errors.length === 0) {
    if (input.noDeps === true) {
      warnings.push("WARNING: --no-deps disables dependency closure; install may be incomplete.");
    } else {
      const queue = modules
        .filter((moduleMetadata) => desired.has(moduleMetadata.id))
        .map((moduleMetadata) => moduleMetadata.id);
      for (let index = 0; index < queue.length; index += 1) {
        const currentId = queue[index];
        const current = moduleById.get(currentId);
        if (!current) continue;

        for (const depId of current.dependencies) {
          if (skipped.has(depId)) {
            errors.push(`Selection error: ${currentId} depends on skipped ${depId}`);
            errors.push(`Remove --skip ${depId} or add --no-deps if debugging.`);
            break;
          }

          const dep = moduleById.get(depId);
          if (!dep) {
            errors.push(`Manifest error: ${currentId} depends on unknown module ${depId}`);
            break;
          }

          if (!desired.has(depId)) {
            desired.set(depId, `dependency of ${currentId}`);
            queue.push(depId);
          }
        }

        if (errors.length > 0) break;
      }
    }
  }

  const included = errors.length === 0
    ? modules
        .filter((moduleMetadata) => desired.has(moduleMetadata.id))
        .map((moduleMetadata) => moduleEntry(moduleMetadata, desired.get(moduleMetadata.id) ?? "included"))
    : [];

  if (errors.length === 0) {
    for (const moduleMetadata of modules) {
      if (desired.has(moduleMetadata.id) || excluded.has(moduleMetadata.id)) continue;
      if (normalized.onlyModules.length > 0) {
        excluded.set(moduleMetadata.id, "not selected");
      } else if (normalized.onlyPhases.length > 0) {
        excluded.set(moduleMetadata.id, "filtered by phase");
      } else {
        excluded.set(moduleMetadata.id, "not selected");
      }
    }
  }

  return {
    ok: errors.length === 0,
    profile: normalized.profile?.id,
    included,
    excluded: modules
      .filter((moduleMetadata) => excluded.has(moduleMetadata.id))
      .map((moduleMetadata) => ({
        id: moduleMetadata.id,
        reason: excluded.get(moduleMetadata.id) ?? "not selected",
      })),
    warnings,
    errors,
    selectedCount: included.length,
    availableCount: modules.length,
  };
}

function quoteInstallArg(value: string): string {
  return `"${value.replace(/["\\$`]/g, "\\$&")}"`;
}

export function buildInstallSelectorArgs(input: ModuleSelectionInput = {}): string[] {
  if (nonEmpty(input.skipTags).length > 0 || nonEmpty(input.skipCategories).length > 0) {
    throw new Error("Tag and category skip selectors cannot be serialized to installer CLI arguments yet.");
  }

  const plan = resolveModuleSelection(input);
  if (!plan.ok) {
    throw new Error(plan.errors.join("\n"));
  }

  const normalized = normalizeSelection(input, manifestSelectionProfiles);
  const args: string[] = [];
  const profileHasSelectors = Boolean(
    normalized.profile
      && (normalized.profile.onlyModules.length > 0 || normalized.profile.onlyPhases.length > 0),
  );

  if (normalized.profile && profileHasSelectors) {
    args.push("--profile", quoteInstallArg(normalized.profile.id));
  } else {
    for (const moduleId of normalized.onlyModules) {
      args.push("--only", quoteInstallArg(moduleId));
    }
    for (const phase of normalized.onlyPhases) {
      args.push("--only-phase", quoteInstallArg(phase));
    }
  }

  for (const moduleId of normalized.skipModules) {
    args.push("--skip", quoteInstallArg(moduleId));
  }
  if (input.noDeps === true) {
    args.push("--no-deps");
  }

  return args;
}

export function formatModuleSelectionPlan(plan: ModuleSelectionPlan): string {
  if (!plan.ok) {
    return [
      "ACFS Module Selection Plan",
      "Status: error",
      ...plan.errors.map((error) => `Error: ${error}`),
    ].join("\n");
  }

  const lines = [
    "ACFS Module Selection Plan",
    `Selected modules: ${plan.selectedCount} of ${plan.availableCount} available`,
  ];

  if (plan.profile) {
    lines.push(`Profile: ${plan.profile}`);
  }
  for (const warning of plan.warnings) {
    lines.push(`Warning: ${warning}`);
  }

  lines.push("Execution order:");
  plan.included.forEach((entry, index) => {
    lines.push(`  ${String(index + 1).padStart(2, " ")}. [Phase ${entry.phase}] ${entry.id} (${entry.reason})`);
  });

  return lines.join("\n");
}
