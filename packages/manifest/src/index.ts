/**
 * @acfs/manifest
 * TypeScript library for parsing and working with ACFS manifest files
 */

// Export runtime category authority and types
export { MODULE_CATEGORIES } from './types.js';
export type {
  Manifest,
  ManifestDefaults,
  Module,
  ModuleWebMetadata,
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
  ModuleWebMetadataInput,
  ModuleWebMetadataOutput,
  ManifestDefaultsInput,
  ManifestDefaultsOutput,
} from './schema.js';

// Export Zod schemas for advanced usage
export {
  ManifestSchema,
  ModuleSchema,
  ModuleWebMetadataSchema,
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
  isValidCategory,
  toGeneratedFunctionName,
  getModuleCategory,
  resolveModuleCategory,
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

export {
  validatePluginPackage,
  formatPluginDiagnostics,
  loadPluginManifestFromFile,
  mergeValidatedPlugins,
} from './plugin.js';

export type {
  PluginDiagnostic,
  PluginDiagnosticCode,
  PluginDiagnosticSeverity,
  PluginModule,
  PluginPackage,
  PluginValidationOptions,
  PluginValidationResult,
  PluginValidationTarget,
} from './plugin.js';
