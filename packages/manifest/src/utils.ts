/**
 * ACFS Manifest Utilities
 * Helper functions for working with manifest data
 */

import type { Manifest, Module, ModuleCategory } from './types.js';

/**
 * Valid module categories (must match ModuleCategory type in types.ts)
 */
const VALID_CATEGORIES = new Set<string>([
  'base',
  'users',
  'filesystem',
  'shell',
  'cli',
  'network',
  'lang',
  'tools',
  'db',
  'cloud',
  'agents',
  'stack',
  'acfs',
]);

/**
 * Check if a string is a valid ModuleCategory
 */
export function isValidCategory(category: string): category is ModuleCategory {
  return VALID_CATEGORIES.has(category);
}

/**
 * Extract the category from a module ID
 * Module IDs follow the pattern: category.name (e.g., "shell.zsh", "lang.bun")
 *
 * @param moduleId - The module ID
 * @returns The category prefix
 * @throws Error if the category extracted is not a valid ModuleCategory
 *
 * @example
 * ```ts
 * getModuleCategory('shell.zsh'); // 'shell'
 * getModuleCategory('lang.bun');  // 'lang'
 * ```
 */
export function getModuleCategory(moduleId: string): ModuleCategory {
  const [category] = moduleId.split('.');
  if (!isValidCategory(category)) {
    throw new Error(
      `Invalid module category '${category}' from module ID '${moduleId}'. ` +
        `Valid categories: ${[...VALID_CATEGORIES].join(', ')}`
    );
  }
  return category;
}

/**
 * Resolve the category for a module, prioritizing the explicit 'category' field.
 * Falls back to ID-derived category if not specified.
 *
 * @param module - The module to resolve
 * @returns The resolved category
 * @throws Error if the category is not valid
 */
export function resolveModuleCategory(module: Module): ModuleCategory {
  if (module.category) {
    if (!isValidCategory(module.category)) {
      throw new Error(
        `Invalid category '${module.category}' for module '${module.id}'. ` +
          `Valid categories: ${[...VALID_CATEGORIES].join(', ')}`
      );
    }
    return module.category;
  }
  return getModuleCategory(module.id);
}

/**
 * Get all modules in a specific category
 *
 * @param manifest - The manifest object
 * @param category - The category to filter by
 * @returns Array of modules in that category
 *
 * @example
 * ```ts
 * const shellModules = getModulesByCategory(manifest, 'shell');
 * ```
 */
export function getModulesByCategory(manifest: Manifest, category: ModuleCategory): Module[] {
  return manifest.modules.filter((module) => resolveModuleCategory(module) === category);
}

/**
 * Get a module by its ID
 *
 * @param manifest - The manifest object
 * @param moduleId - The module ID to find
 * @returns The module or undefined if not found
 */
export function getModuleById(manifest: Manifest, moduleId: string): Module | undefined {
  return manifest.modules.find((module) => module.id === moduleId);
}

/**
 * Get all dependencies of a module (direct only)
 *
 * @param manifest - The manifest object
 * @param moduleId - The module ID
 * @returns Array of dependency modules
 */
export function getModuleDependencies(manifest: Manifest, moduleId: string): Module[] {
  const module = getModuleById(manifest, moduleId);
  if (!module?.dependencies) {
    return [];
  }

  return module.dependencies
    .map((depId) => getModuleById(manifest, depId))
    .filter((m): m is Module => m !== undefined);
}

/**
 * Get all dependencies of a module (transitive/recursive)
 *
 * @param manifest - The manifest object
 * @param moduleId - The module ID
 * @returns Array of all dependency modules (including transitive)
 */
export function getTransitiveDependencies(manifest: Manifest, moduleId: string): Module[] {
  const visited = new Set<string>();
  const result: Module[] = [];

  function collect(id: string): void {
    if (visited.has(id)) return;
    visited.add(id);

    const module = getModuleById(manifest, id);
    if (!module?.dependencies) return;

    for (const depId of module.dependencies) {
      const dep = getModuleById(manifest, depId);
      if (dep && !visited.has(depId)) {
        result.push(dep);
        collect(depId);
      }
    }
  }

  collect(moduleId);
  return result;
}

/**
 * Get modules that depend on a given module
 *
 * @param manifest - The manifest object
 * @param moduleId - The module ID
 * @returns Array of modules that depend on this module
 */
export function getDependents(manifest: Manifest, moduleId: string): Module[] {
  return manifest.modules.filter(
    (module) => module.dependencies?.includes(moduleId)
  );
}

/**
 * Get all unique categories in the manifest
 *
 * @param manifest - The manifest object
 * @returns Array of unique category names
 */
export function getCategories(manifest: Manifest): ModuleCategory[] {
  const categories = new Set<ModuleCategory>();
  for (const module of manifest.modules) {
    categories.add(resolveModuleCategory(module));
  }
  return Array.from(categories);
}

/**
 * Sort modules in installation order (respecting dependencies)
 * Uses topological sort to ensure dependencies come before dependents
 *
 * @param manifest - The manifest object
 * @returns Modules sorted in installation order
 */
export function sortModulesByInstallOrder(manifest: Manifest): Module[] {
  const sorted: Module[] = [];
  const visited = new Set<string>();
  const visiting = new Set<string>(); // For cycle detection

  function visit(moduleId: string): void {
    // console.log(`Visiting ${moduleId}, stack: ${[...visiting].join(' -> ')}`);
    if (visited.has(moduleId)) return;
    if (visiting.has(moduleId)) {
      // Cycle detected, throw error
      throw new Error(`Dependency cycle detected: ${moduleId} depends on itself (directly or indirectly). Stack: ${[...visiting].join(' -> ')} -> ${moduleId}`);
    }

    visiting.add(moduleId);

    const module = getModuleById(manifest, moduleId);
    if (!module) {
      // Module not found (should be caught by validation, but handle gracefully)
      visiting.delete(moduleId);
      return;
    }

    // Visit dependencies first
    if (module.dependencies) {
      for (const depId of module.dependencies) {
        visit(depId);
      }
    }

    visited.add(moduleId);
    visiting.delete(moduleId);
    sorted.push(module);
  }

  // Pre-sort modules by phase to ensure unconnected components are ordered correctly
  const modulesToVisit = [...manifest.modules].sort((a, b) => {
    const phaseA = a.phase ?? 1;
    const phaseB = b.phase ?? 1;
    return phaseA - phaseB;
  });

  for (const module of modulesToVisit) {
    visit(module.id);
  }

  return sorted;
}

/**
 * Group modules by category
 *
 * @param manifest - The manifest object
 * @returns Map of category to modules
 */
export function groupModulesByCategory(manifest: Manifest): Map<ModuleCategory, Module[]> {
  const groups = new Map<ModuleCategory, Module[]>();

  for (const module of manifest.modules) {
    const category = resolveModuleCategory(module);
    const existing = groups.get(category) || [];
    existing.push(module);
    groups.set(category, existing);
  }

  return groups;
}

/**
 * Find modules matching a search query
 *
 * @param manifest - The manifest object
 * @param query - Search query (searches ID and description)
 * @returns Matching modules
 */
export function searchModules(manifest: Manifest, query: string): Module[] {
  const lowerQuery = query.toLowerCase();
  return manifest.modules.filter(
    (module) =>
      module.id.toLowerCase().includes(lowerQuery) ||
      module.description.toLowerCase().includes(lowerQuery)
  );
}

/**
 * Get summary statistics for a manifest
 */
export interface ManifestStats {
  totalModules: number;
  categories: number;
  modulesWithDependencies: number;
  modulesWithNotes: number;
}

/**
 * Get statistics about the manifest
 *
 * @param manifest - The manifest object
 * @returns Statistics object
 */
export function getManifestStats(manifest: Manifest): ManifestStats {
  return {
    totalModules: manifest.modules.length,
    categories: getCategories(manifest).length,
    modulesWithDependencies: manifest.modules.filter((m) => m.dependencies?.length).length,
    modulesWithNotes: manifest.modules.filter((m) => m.notes?.length).length,
  };
}
