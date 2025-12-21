/**
 * ACFS Manifest Parser
 * Parses and validates YAML manifest files
 */

import { readFileSync, existsSync } from 'node:fs';
import { parse as parseYaml, YAMLParseError } from 'yaml';
import { ZodError } from 'zod';
import { ManifestSchema } from './schema.js';
import type {
  Manifest,
  ParseResult,
  ValidationResult,
  ValidationError,
  ValidationWarning,
} from './types.js';

/**
 * Parse a YAML manifest file from a path
 *
 * @param yamlPath - Path to the YAML manifest file
 * @returns Parse result with manifest data or error
 *
 * @example
 * ```ts
 * const result = parseManifestFile('./acfs.manifest.yaml');
 * if (result.success) {
 *   console.log(result.data.modules.length);
 * }
 * ```
 */
export function parseManifestFile(yamlPath: string): ParseResult<Manifest> {
  // Check file exists
  if (!existsSync(yamlPath)) {
    return {
      success: false,
      error: {
        message: `Manifest file not found: ${yamlPath}`,
      },
    };
  }

  // Read file
  let content: string;
  try {
    content = readFileSync(yamlPath, 'utf-8');
  } catch (err) {
    return {
      success: false,
      error: {
        message: `Failed to read manifest file: ${err instanceof Error ? err.message : String(err)}`,
      },
    };
  }

  return parseManifestString(content);
}

/**
 * Parse a YAML manifest from a string
 *
 * @param yamlContent - YAML content as a string
 * @returns Parse result with manifest data or error
 *
 * @example
 * ```ts
 * const yaml = `
 * version: 1
 * name: test
 * id: test
 * defaults:
 *   user: ubuntu
 *   workspace_root: /data/projects
 *   mode: vibe
 * modules:
 *   - id: base.system
 *     description: Base packages
 *     install:
 *       - sudo apt-get update -y
 *     verify:
 *       - curl --version
 * `;
 * const result = parseManifestString(yaml);
 * ```
 */
export function parseManifestString(yamlContent: string): ParseResult<Manifest> {
  // Parse YAML
  let parsed: unknown;
  try {
    parsed = parseYaml(yamlContent);
  } catch (err) {
    if (err instanceof YAMLParseError) {
      return {
        success: false,
        error: {
          message: `YAML parse error: ${err.message}`,
          line: err.linePos?.[0]?.line,
          column: err.linePos?.[0]?.col,
        },
      };
    }
    return {
      success: false,
      error: {
        message: `YAML parse error: ${err instanceof Error ? err.message : String(err)}`,
      },
    };
  }

  // Validate with Zod
  const validation = ManifestSchema.safeParse(parsed);

  if (!validation.success) {
    return {
      success: false,
      error: {
        message: formatZodError(validation.error),
      },
    };
  }

  return {
    success: true,
    data: validation.data as Manifest,
  };
}

/**
 * Validate a manifest object (already parsed)
 *
 * @param manifest - Manifest object to validate
 * @returns Validation result with errors and warnings
 */
export function validateManifest(manifest: unknown): ValidationResult {
  const errors: ValidationError[] = [];
  const warnings: ValidationWarning[] = [];

  // Schema validation
  const schemaResult = ManifestSchema.safeParse(manifest);

  if (!schemaResult.success) {
    for (const issue of schemaResult.error.issues) {
      errors.push({
        path: issue.path.join('.'),
        message: issue.message,
        value: undefined,
      });
    }
    return { valid: false, errors, warnings };
  }

  const data = schemaResult.data as Manifest;

  // Check for duplicate module IDs
  const seenIds = new Set<string>();
  for (const module of data.modules) {
    if (seenIds.has(module.id)) {
      errors.push({
        path: `modules`,
        message: `Duplicate module ID: ${module.id}`,
        value: module.id,
      });
    }
    seenIds.add(module.id);
  }

  // Check for missing dependencies
  const moduleIds = new Set(data.modules.map((m) => m.id));
  for (const module of data.modules) {
    if (module.dependencies) {
      for (const dep of module.dependencies) {
        if (!moduleIds.has(dep)) {
          errors.push({
            path: `modules.${module.id}.dependencies`,
            message: `Unknown dependency: ${dep}`,
            value: dep,
          });
        }
      }
    }
  }

  // Check for dependency cycles
  const cycleErrors = detectDependencyCycles(data.modules);
  errors.push(...cycleErrors);

  // Check for phase ordering violations (deps must be same or earlier phase)
  // Related: bead mjt.3.2
  const phaseErrors = validatePhaseOrdering(data.modules);
  errors.push(...phaseErrors);

  // Warnings for modules with install steps that look like descriptions
  for (const module of data.modules) {
    if (module.install.length === 0) {
      continue;
    }
    const hasRealInstall = module.install.some(
      (cmd) => !cmd.startsWith('"') && !cmd.includes('Ensure') && !cmd.includes('Install ')
    );
    if (!hasRealInstall) {
      warnings.push({
        path: `modules.${module.id}.install`,
        message: 'Install commands appear to be descriptions, not actual commands',
      });
    }
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings,
  };
}

/**
 * Detect dependency cycles in modules
 */
function detectDependencyCycles(modules: Manifest['modules']): ValidationError[] {
  const errors: ValidationError[] = [];
  const moduleMap = new Map(modules.map((m) => [m.id, m]));

  function hasCycle(moduleId: string, visited: Set<string>, path: string[]): string[] | null {
    if (visited.has(moduleId)) {
      const cycleStart = path.indexOf(moduleId);
      return path.slice(cycleStart);
    }

    const module = moduleMap.get(moduleId);
    if (!module || !module.dependencies) {
      return null;
    }

    visited.add(moduleId);
    path.push(moduleId);

    for (const dep of module.dependencies) {
      const cycle = hasCycle(dep, visited, path);
      if (cycle) {
        return cycle;
      }
    }

    visited.delete(moduleId);
    path.pop();
    return null;
  }

  for (const module of modules) {
    const cycle = hasCycle(module.id, new Set(), []);
    if (cycle) {
      errors.push({
        path: `modules.${module.id}.dependencies`,
        message: `Dependency cycle detected: ${cycle.join(' -> ')} -> ${cycle[0]}`,
      });
      break; // Only report first cycle found
    }
  }

  return errors;
}

/**
 * Validate phase ordering: dependencies must be in same or earlier phase
 * Related: bead mjt.3.2
 */
function validatePhaseOrdering(modules: Manifest['modules']): ValidationError[] {
  const errors: ValidationError[] = [];
  const moduleMap = new Map(modules.map((m) => [m.id, m]));

  for (const module of modules) {
    if (!module.dependencies) continue;

    const modulePhase = module.phase ?? 1;

    for (const depId of module.dependencies) {
      const dep = moduleMap.get(depId);
      if (!dep) continue; // Missing dependency is caught by existence check

      const depPhase = dep.phase ?? 1;

      if (depPhase > modulePhase) {
        errors.push({
          path: `modules.${module.id}.dependencies`,
          message: `Phase violation: "${module.id}" (phase ${modulePhase}) depends on "${depId}" (phase ${depPhase}). Dependencies must be in same or earlier phase.`,
          value: depId,
        });
      }
    }
  }

  return errors;
}

/**
 * Format a Zod error into a readable message
 */
function formatZodError(error: ZodError): string {
  const messages = error.issues.map((issue) => {
    const path = issue.path.join('.');
    return path ? `${path}: ${issue.message}` : issue.message;
  });
  return messages.join('; ');
}
