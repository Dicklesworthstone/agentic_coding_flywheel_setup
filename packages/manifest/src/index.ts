/**
 * @acfs/manifest
 * TypeScript library for parsing and working with ACFS manifest files
 */

// Export parser functions
export {
  parseManifestFile,
  parseManifestString,
  validateManifest,
} from "./parser.js";
export type {
  PluginDiagnostic,
  PluginDiagnosticCode,
  PluginDiagnosticSeverity,
  PluginModule,
  PluginPackage,
  PluginValidationOptions,
  PluginValidationResult,
  PluginValidationTarget,
} from "./plugin.js";
export {
  formatPluginDiagnostics,
  loadPluginManifestFromFile,
  mergeValidatedPlugins,
  validatePluginPackage,
} from "./plugin.js";
export type { PluginArchiveErrorCode, VerifiedPluginArchive } from "./plugin-archive.js";
export {
  PLUGIN_ARCHIVE_LIMITS,
  PluginArchiveError,
  readVerifiedPluginArchive,
  verifyPluginArchiveBytes,
} from "./plugin-archive.js";
export type {
  LoadedPluginInstallerCache,
  PluginCacheOptions,
  PluginCacheSummary,
  PluginInstallerDownload,
} from "./plugin-cache.js";
export {
  executeCachedPluginInstallPlan,
  loadPluginInstallerCache,
  PLUGIN_CACHE_LIMITS,
  PluginCacheError,
  preparePluginInstallerCache,
} from "./plugin-cache.js";
export type { PluginInstallArguments } from "./plugin-install.js";
export { loadPluginInstallPlan } from "./plugin-install.js";
export type { PluginArchiveBuild, PluginArchivePublication } from "./plugin-pack.js";
export {
  buildPluginArchive,
  PluginPackError,
  pluginArchiveBytes,
  writePluginArchive,
} from "./plugin-pack.js";
export type { PluginPackArguments, PluginPackValidation } from "./plugin-pack-cli.js";
export { validatePluginArchiveForPublication } from "./plugin-pack-cli.js";
export type {
  PluginInstallAction,
  PluginInstallPlan,
  PluginPlanInput,
  PluginPlanTarget,
} from "./plugin-plan.js";
export { buildPluginInstallPlan, PluginPlanError } from "./plugin-plan.js";
export type {
  PluginArchiveTarget,
  PluginReviewRecord,
  ReviewedPluginArchive,
} from "./plugin-review.js";
export {
  PluginReviewError,
  parsePluginTarget,
  readPluginReviewRecord,
  readReviewedPluginArchive,
} from "./plugin-review.js";
export type {
  PluginInstallInspection,
  PluginInstallReceipt,
  PluginInstallRecovery,
} from "./plugin-runtime.js";
export { inspectPluginInstallPlan, recoverPluginInstallPlan } from "./plugin-runtime.js";
export { loadReviewedPluginPackage } from "./plugin-verify.js";
// Export schema types (inferred from Zod)
export type {
  ManifestDefaultsInput,
  ManifestDefaultsOutput,
  ManifestInput,
  ManifestOutput,
  ModuleAgentMetadataInput,
  ModuleAgentMetadataOutput,
  ModuleInput,
  ModuleOutput,
  ModuleWebMetadataInput,
  ModuleWebMetadataOutput,
} from "./schema.js";
// Export Zod schemas for advanced usage
export {
  ManifestDefaultsSchema,
  ManifestSchema,
  ModuleAgentMetadataSchema,
  ModuleSchema,
  ModuleWebMetadataSchema,
} from "./schema.js";
export type {
  Manifest,
  ManifestDefaults,
  Module,
  ModuleAgentMetadata,
  ModuleCategory,
  ModuleWebMetadata,
  ParseError,
  ParseResult,
  ValidationError,
  ValidationResult,
  ValidationWarning,
} from "./types.js";
// Export runtime category authority and types
export { MODULE_CATEGORIES } from "./types.js";
// Export stats interface
export type { ManifestStats } from "./utils.js";
// Export utility functions
export {
  getCategories,
  getDependents,
  getManifestStats,
  getModuleById,
  getModuleCategory,
  getModuleDependencies,
  getModulesByCategory,
  getTransitiveDependencies,
  groupModulesByCategory,
  isValidCategory,
  resolveModuleCategory,
  searchModules,
  sortModulesByInstallOrder,
  toGeneratedFunctionName,
} from "./utils.js";
export type {
  ValidationError as AdvancedValidationError,
  ValidationResult as AdvancedValidationResult,
} from "./validate.js";
// Export advanced validation API (bead mjt.3.2)
export {
  detectDependencyCycles,
  formatValidationErrors,
  validateDependencyExistence,
  validateManifest as validateManifestAdvanced,
  validatePhaseOrdering,
} from "./validate.js";
