/**
 * @acfs/manifest
 * TypeScript library for parsing and working with ACFS manifest files
 */

// Export types
export type {
  Manifest,
  ManifestDefaults,
  Module,
  ModuleCategory,
  ValidationResult,
  ValidationError,
  ValidationWarning,
  ParseResult,
  ParseError,
} from './types.js';

// Export schema types (inferred from Zod)
export type {
  ManifestInput,
  ManifestOutput,
  ModuleInput,
  ModuleOutput,
  ManifestDefaultsInput,
  ManifestDefaultsOutput,
} from './schema.js';

// Export Zod schemas for advanced usage
export {
  ManifestSchema,
  ModuleSchema,
  ManifestDefaultsSchema,
} from './schema.js';

// Export parser functions
export {
  parseManifestFile,
  parseManifestString,
  validateManifest,
} from './parser.js';

// Export utility functions
export {
  getModuleCategory,
  getModulesByCategory,
  getModuleById,
  getModuleDependencies,
  getTransitiveDependencies,
  getDependents,
  getCategories,
  sortModulesByInstallOrder,
  groupModulesByCategory,
  searchModules,
  getManifestStats,
} from './utils.js';

// Export stats interface
export type { ManifestStats } from './utils.js';

// Export advanced validation API (bead mjt.3.2)
export {
  validateDependencyExistence,
  detectDependencyCycles,
  validatePhaseOrdering,
  validateManifest as validateManifestAdvanced,
  formatValidationErrors,
} from './validate.js';

export type {
  ValidationError as AdvancedValidationError,
  ValidationResult as AdvancedValidationResult,
} from './validate.js';
