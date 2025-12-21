/**
 * ACFS Manifest Validation
 * Validates manifest dependencies, cycles, and phase ordering
 *
 * Related: bead mjt.3.2
 */

import type { Manifest, Module } from './types.js';

// ============================================================
// Validation Result Types
// ============================================================

export interface ValidationError {
  /** Error code for programmatic handling */
  code: 'MISSING_DEPENDENCY' | 'DEPENDENCY_CYCLE' | 'PHASE_VIOLATION';
  /** Human-readable error message */
  message: string;
  /** Module ID where the error was detected */
  moduleId: string;
  /** Additional context (e.g., cycle path, missing dep ID) */
  context: Record<string, unknown>;
}

export interface ValidationResult {
  /** True if manifest passes all validations */
  valid: boolean;
  /** Array of validation errors (empty if valid) */
  errors: ValidationError[];
}

// ============================================================
// Dependency Existence Check
// ============================================================

/**
 * Validates that all module dependencies reference existing modules.
 *
 * @param manifest - The manifest to validate
 * @returns Array of errors for missing dependencies
 *
 * @example
 * ```ts
 * const errors = validateDependencyExistence(manifest);
 * if (errors.length > 0) {
 *   console.error('Missing dependencies:', errors);
 * }
 * ```
 */
export function validateDependencyExistence(manifest: Manifest): ValidationError[] {
  const errors: ValidationError[] = [];
  const moduleIds = new Set(manifest.modules.map((m) => m.id));

  for (const module of manifest.modules) {
    if (!module.dependencies) continue;

    for (const depId of module.dependencies) {
      if (!moduleIds.has(depId)) {
        errors.push({
          code: 'MISSING_DEPENDENCY',
          message: `Module "${module.id}" depends on "${depId}" which does not exist`,
          moduleId: module.id,
          context: {
            missingDependency: depId,
            availableModules: Array.from(moduleIds).sort(),
          },
        });
      }
    }
  }

  return errors;
}

// ============================================================
// Cycle Detection
// ============================================================

/**
 * Detects cycles in module dependencies using DFS.
 * Reports the full cycle path for debugging.
 *
 * @param manifest - The manifest to validate
 * @returns Array of errors for detected cycles
 *
 * @example
 * ```ts
 * const errors = detectDependencyCycles(manifest);
 * if (errors.length > 0) {
 *   // errors[0].context.cyclePath = ['a', 'b', 'c', 'a']
 *   console.error('Dependency cycle detected:', errors[0].context.cyclePath);
 * }
 * ```
 */
export function detectDependencyCycles(manifest: Manifest): ValidationError[] {
  const errors: ValidationError[] = [];
  const moduleMap = new Map(manifest.modules.map((m) => [m.id, m]));
  const visited = new Set<string>();
  const reportedCycles = new Set<string>(); // Avoid duplicate cycle reports

  function dfs(moduleId: string, path: string[]): boolean {
    // Check if we've found a cycle
    const cycleStart = path.indexOf(moduleId);
    if (cycleStart !== -1) {
      // Extract just the cycle portion
      const cyclePath = [...path.slice(cycleStart), moduleId];
      const cycleKey = cyclePath.sort().join(',');

      if (!reportedCycles.has(cycleKey)) {
        reportedCycles.add(cycleKey);
        errors.push({
          code: 'DEPENDENCY_CYCLE',
          message: `Dependency cycle detected: ${cyclePath.join(' → ')}`,
          moduleId: cyclePath[0],
          context: {
            cyclePath,
            cycleLength: cyclePath.length - 1,
          },
        });
      }
      return true;
    }

    // Skip if already fully processed
    if (visited.has(moduleId)) {
      return false;
    }

    const module = moduleMap.get(moduleId);
    if (!module || !module.dependencies) {
      visited.add(moduleId);
      return false;
    }

    // Recurse into dependencies
    for (const depId of module.dependencies) {
      if (dfs(depId, [...path, moduleId])) {
        // Cycle found, but continue to find other cycles
      }
    }

    visited.add(moduleId);
    return false;
  }

  // Start DFS from each module
  for (const module of manifest.modules) {
    if (!visited.has(module.id)) {
      dfs(module.id, []);
    }
  }

  return errors;
}

// ============================================================
// Phase Ordering Validation
// ============================================================

/**
 * Get the phase of a module (defaults to 1 if not specified)
 */
function getModulePhase(module: Module): number {
  return module.phase ?? 1;
}

/**
 * Validates that dependencies are in the same or earlier phase.
 * A module in phase N cannot depend on a module in phase N+1 or later.
 *
 * @param manifest - The manifest to validate
 * @returns Array of errors for phase ordering violations
 *
 * @example
 * ```ts
 * // If module "shell.zsh" (phase 2) depends on "agent.claude" (phase 5),
 * // this will return an error because phase 5 > phase 2.
 * const errors = validatePhaseOrdering(manifest);
 * ```
 */
export function validatePhaseOrdering(manifest: Manifest): ValidationError[] {
  const errors: ValidationError[] = [];
  const moduleMap = new Map(manifest.modules.map((m) => [m.id, m]));

  for (const module of manifest.modules) {
    if (!module.dependencies) continue;

    const modulePhase = getModulePhase(module);

    for (const depId of module.dependencies) {
      const dep = moduleMap.get(depId);
      if (!dep) continue; // Missing dependency is caught by existence check

      const depPhase = getModulePhase(dep);

      if (depPhase > modulePhase) {
        errors.push({
          code: 'PHASE_VIOLATION',
          message: `Module "${module.id}" (phase ${modulePhase}) depends on "${depId}" (phase ${depPhase}) - dependencies must be same or earlier phase`,
          moduleId: module.id,
          context: {
            modulePhase,
            dependencyId: depId,
            dependencyPhase: depPhase,
          },
        });
      }
    }
  }

  return errors;
}

// ============================================================
// Combined Validation
// ============================================================

/**
 * Runs all manifest validations and returns a combined result.
 * Validations are run in order:
 * 1. Dependency existence (fast-fail on missing refs)
 * 2. Cycle detection (DAG requirement)
 * 3. Phase ordering (execution plan feasibility)
 *
 * @param manifest - The manifest to validate
 * @returns ValidationResult with all errors
 *
 * @example
 * ```ts
 * const result = validateManifest(manifest);
 * if (!result.valid) {
 *   console.error('Validation failed:');
 *   for (const error of result.errors) {
 *     console.error(`  [${error.code}] ${error.message}`);
 *   }
 *   process.exit(1);
 * }
 * ```
 */
export function validateManifest(manifest: Manifest): ValidationResult {
  const errors: ValidationError[] = [];

  // 1. Check dependency existence first (other checks assume deps exist)
  errors.push(...validateDependencyExistence(manifest));

  // 2. Check for cycles (only if deps exist, to avoid confusing errors)
  if (errors.length === 0) {
    errors.push(...detectDependencyCycles(manifest));
  }

  // 3. Check phase ordering (only if no cycles, since cycles confuse ordering)
  if (errors.length === 0) {
    errors.push(...validatePhaseOrdering(manifest));
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Formats validation errors for human-readable output.
 *
 * @param result - The validation result
 * @returns Formatted string for console output
 */
export function formatValidationErrors(result: ValidationResult): string {
  if (result.valid) {
    return '✓ Manifest validation passed';
  }

  const lines: string[] = ['✗ Manifest validation failed:', ''];

  for (const error of result.errors) {
    lines.push(`  [${error.code}] ${error.message}`);

    // Add contextual hints based on error type
    switch (error.code) {
      case 'MISSING_DEPENDENCY':
        lines.push(`    → Check spelling or add the missing module`);
        break;
      case 'DEPENDENCY_CYCLE':
        lines.push(`    → Remove one dependency to break the cycle`);
        break;
      case 'PHASE_VIOLATION':
        lines.push(`    → Move dependency to earlier phase or move module to later phase`);
        break;
    }
    lines.push('');
  }

  lines.push(`Total: ${result.errors.length} error(s)`);
  return lines.join('\n');
}
