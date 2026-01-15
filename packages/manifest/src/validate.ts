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
  code:
    | 'MISSING_DEPENDENCY'
    | 'DEPENDENCY_CYCLE'
    | 'PHASE_VIOLATION'
    | 'FUNCTION_NAME_COLLISION'
    | 'RESERVED_NAME_COLLISION'
    | 'INVALID_VERIFIED_INSTALLER_RUNNER';
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
      // Create sorted key for deduplication WITHOUT mutating cyclePath
      const cycleKey = [...cyclePath].sort().join(',');

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
// Function Name Generation (mirrors generate.ts)
// ============================================================

/**
 * Convert module ID to generated bash function name.
 * Must stay in sync with generate.ts toFunctionName()
 */
function toFunctionName(moduleId: string): string {
  return `install_${moduleId.replace(/\./g, '_')}`;
}

// ============================================================
// Reserved Names
// ============================================================

/**
 * Reserved function names that must not be used by generated module functions.
 * Includes orchestrator functions, category install functions, and common shell patterns.
 */
const RESERVED_FUNCTION_NAMES = new Set([
  // Orchestrator functions from generated install_all.sh
  'install_all',

  // Category install functions (generated from manifest categories)
  'install_base',
  'install_lang',
  'install_tools',
  'install_agents',
  'install_cloud',
  'install_stack',
  'install_acfs',
  'install_shell',
  'install_cli',
  'install_db',
  'install_users',
  'install_filesystem',
  'install_network',

  // Doctor/manifest check functions
  'run_manifest_checks',

  // Logging functions (from logging.sh)
  'log_step',
  'log_section',
  'log_success',
  'log_error',
  'log_warn',
  'log_info',

  // Security functions (from security.sh)
  'acfs_security_init',
  'load_checksums',
  'get_checksum',
  'verify_checksum',

  // Contract functions (from contract.sh)
  'acfs_require_contract',

  // State functions (from state.sh)
  'state_tool_done',
  'state_tool_skip',
  'state_tool_failed',
  'record_skipped_tool',

  // Core install.sh functions
  'install_asset',
  'install_checksums_yaml',
  'install_gum_early',
  'install_cli_tools',
  'install_languages',
  'install_agents_phase',
  'install_cloud_db',
  'install_stack_phase',

  // Common shell builtins/functions that should never be shadowed
  'main',
  'usage',
  'help',
  'init',
  'setup',
  'cleanup',
  'run',
  'exec',
  'exit',
  'test',
  'true',
  'false',
]);

// ============================================================
// Function Name Collision Detection
// ============================================================

/**
 * Validates that generated function names are unique across all modules.
 * Two modules must not produce the same bash function name.
 *
 * @param manifest - The manifest to validate
 * @returns Array of errors for function name collisions
 *
 * @example
 * ```ts
 * // If both "lang.bun" and "lang-bun" exist, they'd both generate
 * // "install_lang_bun" - this function catches that collision.
 * const errors = validateFunctionNameUniqueness(manifest);
 * ```
 */
export function validateFunctionNameUniqueness(manifest: Manifest): ValidationError[] {
  const errors: ValidationError[] = [];
  const functionToModules = new Map<string, string[]>();

  // Build map of function name -> module IDs
  for (const module of manifest.modules) {
    const funcName = toFunctionName(module.id);
    const existing = functionToModules.get(funcName);
    if (existing) {
      existing.push(module.id);
    } else {
      functionToModules.set(funcName, [module.id]);
    }
  }

  // Report collisions
  for (const [funcName, moduleIds] of functionToModules) {
    if (moduleIds.length > 1) {
      // Report error on the second (and subsequent) modules
      for (let i = 1; i < moduleIds.length; i++) {
        const moduleId = moduleIds[i];
        const firstModuleId = moduleIds[0];
        errors.push({
          code: 'FUNCTION_NAME_COLLISION',
          message: `Module "${moduleId}" generates function "${funcName}" which collides with "${firstModuleId}"`,
          moduleId,
          context: {
            functionName: funcName,
            collidingModules: moduleIds,
            suggestion: `Rename module to avoid collision. Consider using a different category prefix or more specific naming.`,
          },
        });
      }
    }
  }

  return errors;
}

/**
 * Validates that generated function names do not collide with reserved orchestrator names.
 *
 * @param manifest - The manifest to validate
 * @returns Array of errors for reserved name collisions
 *
 * @example
 * ```ts
 * // A module named "all" would generate "install_all" which is reserved.
 * const errors = validateReservedNames(manifest);
 * ```
 */
export function validateReservedNames(manifest: Manifest): ValidationError[] {
  const errors: ValidationError[] = [];

  for (const module of manifest.modules) {
    const funcName = toFunctionName(module.id);

    if (RESERVED_FUNCTION_NAMES.has(funcName)) {
      errors.push({
        code: 'RESERVED_NAME_COLLISION',
        message: `Module "${module.id}" generates function "${funcName}" which is a reserved orchestrator name`,
        moduleId: module.id,
        context: {
          functionName: funcName,
          reservedNames: Array.from(RESERVED_FUNCTION_NAMES).filter((n) =>
            n.startsWith('install_')
          ),
          suggestion: `Rename the module. Reserved names include: ${Array.from(RESERVED_FUNCTION_NAMES)
            .filter((n) => n.startsWith('install_'))
            .join(', ')}`,
        },
      });
    }
  }

  return errors;
}

// ============================================================
// Verified Installer Security Validation
// ============================================================

/**
 * Allowlist of valid runners for verified installers.
 * SECURITY: Only allow known-safe shell interpreters.
 * This is a belt-and-suspenders check - schema.ts also validates this.
 */
const ALLOWED_VERIFIED_INSTALLER_RUNNERS = new Set(['bash', 'sh']);

/**
 * Validates that verified_installer.runner is in the security allowlist.
 * This is a defense-in-depth check in addition to schema validation.
 *
 * @param manifest - The manifest to validate
 * @returns Array of errors for invalid runners
 *
 * @example
 * ```ts
 * // If a module has verified_installer.runner: 'python', this returns an error
 * const errors = validateVerifiedInstallerRunner(manifest);
 * ```
 */
export function validateVerifiedInstallerRunner(manifest: Manifest): ValidationError[] {
  const errors: ValidationError[] = [];

  for (const module of manifest.modules) {
    if (!module.verified_installer) continue;

    const runner = module.verified_installer.runner;
    if (!ALLOWED_VERIFIED_INSTALLER_RUNNERS.has(runner)) {
      errors.push({
        code: 'INVALID_VERIFIED_INSTALLER_RUNNER',
        message: `Module "${module.id}" has invalid verified_installer.runner "${runner}" - only "bash" or "sh" allowed`,
        moduleId: module.id,
        context: {
          runner,
          allowedRunners: Array.from(ALLOWED_VERIFIED_INSTALLER_RUNNERS),
          tool: module.verified_installer.tool,
        },
      });
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
 * 4. Function name uniqueness (no collisions in generated bash)
 * 5. Reserved name validation (no collisions with orchestrator)
 * 6. Verified installer runner allowlist (security)
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

  // 4. Check for function name collisions (can run independently)
  errors.push(...validateFunctionNameUniqueness(manifest));

  // 5. Check for reserved name collisions (can run independently)
  errors.push(...validateReservedNames(manifest));

  // 6. Check verified installer runners are in allowlist (security)
  errors.push(...validateVerifiedInstallerRunner(manifest));

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
      case 'FUNCTION_NAME_COLLISION':
        lines.push(`    → Rename one of the colliding modules to use a different ID`);
        if (error.context.suggestion) {
          lines.push(`    → ${error.context.suggestion}`);
        }
        break;
      case 'RESERVED_NAME_COLLISION':
        lines.push(`    → Rename the module to avoid the reserved function name`);
        if (error.context.suggestion) {
          lines.push(`    → ${error.context.suggestion}`);
        }
        break;
      case 'INVALID_VERIFIED_INSTALLER_RUNNER':
        lines.push(`    → SECURITY: Only "bash" or "sh" are allowed as runners`);
        lines.push(`    → Change verified_installer.runner to "bash" or "sh"`);
        break;
    }
    lines.push('');
  }

  lines.push(`Total: ${result.errors.length} error(s)`);
  return lines.join('\n');
}
