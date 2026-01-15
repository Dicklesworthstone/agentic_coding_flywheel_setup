/**
 * ACFS Manifest Parser
 * Parses and validates YAML manifest files
 */

import { readFileSync, existsSync } from 'node:fs';
import { parse as parseYaml, YAMLParseError } from 'yaml';
import { ZodError } from 'zod';
import { ManifestSchema } from './schema.js';
import { detectDependencyCycles as detectDependencyCyclesValidate } from './validate.js';
import type {
  Manifest,
  ParseResult,
  ValidationResult,
  ValidationError,
  ValidationWarning,
} from './types.js';

function unwrapOptionalQuotes(value: string): string {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1).trim();
  }
  return trimmed;
}

function looksLikeDescriptionSentence(value: string): boolean {
  const prefixes = [
    'Install ',
    'Ensure ',
    'Configure ',
    'Set up ',
    'Setup ',
    'Create ',
    'Write ',
    'Copy ',
    'Add ',
    'Remove ',
    'Link ',
    'Enable ',
    'Disable ',
    'Restart ',
    'Start ',
    'Stop ',
    'Open ',
    'Select ',
    'Choose ',
    'Run ',
  ];

  return prefixes.some((p) => value.startsWith(p));
}

function looksLikeDescriptionOnlyInstallEntry(raw: string): boolean {
  if (raw.includes('\n')) return false;

  const unquoted = unwrapOptionalQuotes(raw);
  if (!unquoted) return false;
  if (/^(TODO|NOTE):/i.test(unquoted)) return true;
  if (looksLikeDescriptionSentence(unquoted)) return true;
  // Back-compat: a literal leading quote in the string indicates a description-only entry.
  if (raw.trimStart().startsWith('"')) return true;
  return false;
}

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

  // Check for dependency cycles (using consolidated implementation from validate.ts)
  const cycleResults = detectDependencyCyclesValidate(data);
  for (const e of cycleResults) {
    errors.push({
      path: `modules.${e.moduleId}.dependencies`,
      message: e.message,
    });
  }

  // Check for phase ordering violations (deps must be same or earlier phase)
  // Related: bead mjt.3.2
  const phaseErrors = validatePhaseOrdering(data.modules);
  errors.push(...phaseErrors);

  // Warnings for modules with install steps that look like descriptions
  for (const module of data.modules) {
    if (module.install.length === 0) {
      continue;
    }
    const hasRealInstall = module.install.some((cmd) => !looksLikeDescriptionOnlyInstallEntry(cmd));
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
