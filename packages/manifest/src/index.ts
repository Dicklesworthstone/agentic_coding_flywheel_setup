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
  ModuleAgentMetadata,
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
  ModuleAgentMetadataInput,
  ModuleAgentMetadataOutput,
  ManifestDefaultsInput,
  ManifestDefaultsOutput,
} from './schema.js';

// Export Zod schemas for advanced usage
export {
  ManifestSchema,
  ModuleSchema,
  ModuleAgentMetadataSchema,
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

export { readVerifiedPluginArchive, PluginArchiveError, PLUGIN_ARCHIVE_LIMITS } from './plugin-archive.js';
export type { VerifiedPluginArchive, PluginArchiveErrorCode } from './plugin-archive.js';
export { readReviewedPluginArchive, readPluginReviewRecord, parsePluginTarget, PluginReviewError } from './plugin-review.js';
export type { ReviewedPluginArchive, PluginArchiveTarget, PluginReviewRecord } from './plugin-review.js';
export { loadReviewedPluginPackage } from './plugin-verify.js';

export { buildPluginInstallPlan, PluginPlanError } from './plugin-plan.js';
export type { PluginInstallPlan, PluginInstallAction, PluginPlanInput, PluginPlanTarget } from './plugin-plan.js';
export { loadPluginInstallPlan } from './plugin-install.js';
export type { PluginInstallArguments } from './plugin-install.js';
export { inspectPluginInstallPlan, recoverPluginInstallPlan } from './plugin-runtime.js';
export type { PluginInstallReceipt, PluginInstallInspection, PluginInstallRecovery } from './plugin-runtime.js';

export {
  preparePluginInstallerCache,
  loadPluginInstallerCache,
  executeCachedPluginInstallPlan,
  PluginCacheError,
  PLUGIN_CACHE_LIMITS,
} from './plugin-cache.js';
export type {
  PluginCacheOptions,
  PluginCacheSummary,
  PluginInstallerDownload,
  LoadedPluginInstallerCache,
} from './plugin-cache.js';

export { verifyPluginArchiveBytes } from './plugin-archive.js';
export { buildPluginArchive, pluginArchiveBytes, writePluginArchive, PluginPackError } from './plugin-pack.js';
export type { PluginArchiveBuild, PluginArchivePublication } from './plugin-pack.js';
export { validatePluginArchiveForPublication } from './plugin-pack-cli.js';
export type { PluginPackArguments, PluginPackValidation } from './plugin-pack-cli.js';
