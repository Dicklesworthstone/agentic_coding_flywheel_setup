/**
 * ACFS Manifest Types
 * Type definitions for the acfs.manifest.yaml schema
 */

/**
 * Default configuration for ACFS installation
 */
export interface ManifestDefaults {
  /** Target user for installation (default: ubuntu) */
  user: string;
  /** Root directory for projects workspace */
  workspace_root: string;
  /** Installation mode (vibe = passwordless sudo, full permissions) */
  mode: 'vibe' | 'safe';
}

/**
 * Execution context for module commands
 */
export type RunAs = 'target_user' | 'root' | 'current';

/**
 * Canonical module categories. This runtime tuple is shared by schema and
 * generator utilities so authored manifests cannot pass one category policy
 * and then fail under another.
 */
export const MODULE_CATEGORIES = [
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
] as const;

export type ModuleCategory = (typeof MODULE_CATEGORIES)[number];

/**
 * Distro families ACFS distinguishes at install time (#385).
 *
 * These are exactly the values `install.sh` assigns to `ACFS_DISTRO_FAMILY`:
 * `arch` for ID=arch, ID=omarchy, or an ID_LIKE containing arch, and `ubuntu`
 * for everything else (the apt-based default). A module may narrow itself to a
 * subset via its `families` key; omitting the key means every family.
 */
export const DISTRO_FAMILIES = ['ubuntu', 'arch'] as const;

export type DistroFamily = (typeof DISTRO_FAMILIES)[number];

/**
 * Allowed runners for verified installers.
 * SECURITY: Only allow known-safe shell interpreters to prevent command injection.
 */
export type VerifiedInstallerRunner = 'bash' | 'sh';

/**
 * Verified upstream installer reference (curl|bash)
 */
export interface VerifiedInstaller {
  /** Tool key in checksums.yaml */
  tool: string;
  /** Optional canonical installer URL; validated against checksums.yaml when provided */
  url?: string;
  /** Unsupported legacy field kept only so the parser can reject it explicitly */
  fallback_url?: string;
  /** Executable runner (must be bash or sh) */
  runner: VerifiedInstallerRunner;
  /** Optional environment variable assignments (KEY=value) for the runner */
  env?: string[];
  /** Optional additional args for runner */
  args?: string[];
}

/**
 * Installed check command (run_as-aware)
 */
export interface InstalledCheck {
  /** Execution context for the check */
  run_as: RunAs;
  /** Command to determine installed status */
  command: string;
}

/**
 * Optional pre-install check that can skip a module before running installers.
 */
export interface PreInstallCheck {
  /** Execution context for the check */
  run_as: RunAs;
  /** Command that must succeed before installation continues */
  command: string;
  /** Message recorded when the check fails and the module is skipped */
  skip_message: string;
}

/**
 * Web-facing metadata for a module.
 * Used to generate website content (tool pages, TL;DR cards, command references).
 * All fields are optional; omitting the entire `web` block means the module
 * has no web presence. If `web` is present but `visible` is false, the module
 * is excluded from generated web content.
 */
export interface ModuleWebMetadata {
  /** Human-readable display name (e.g., "MCP Agent Mail") */
  display_name?: string;
  /** Short name for compact UI contexts (e.g., "Agent Mail") */
  short_name?: string;
  /** One-line tagline for hero/card display */
  tagline?: string;
  /** Short description for cards and summaries */
  short_desc?: string;
  /** Lucide icon name (e.g., "mail", "terminal") */
  icon?: string;
  /** Hex color for branding (e.g., "#3B82F6") */
  color?: string;
  /** Web category label for grouping (e.g., "AI Agent", "Dev Tool") */
  category_label?: string;
  /** URL path for the tool's detail page (e.g., "/tools/agent-mail") */
  href?: string;
  /** Key features list */
  features?: string[];
  /** Technology stack (e.g., ["Rust", "SQLite"]) */
  tech_stack?: string[];
  /** Use case descriptions */
  use_cases?: string[];
  /** Primary programming language */
  language?: string;
  /** GitHub stars count */
  stars?: number;
  /** CLI command name (e.g., "br") */
  cli_name?: string;
  /** CLI command aliases */
  cli_aliases?: string[];
  /** CLI usage example (e.g., "br ready --json") */
  command_example?: string;
  /** Associated lesson slug for linking to onboarding content */
  lesson_slug?: string;
  /** TL;DR snippet for the summary page */
  tldr_snippet?: string;
  /** Whether to show on the website (defaults to true when web block is present) */
  visible?: boolean;
}

/**
 * Provenance for modules supplied by a validated ACFS plugin package.
 */
export interface ModulePluginProvenance {
  /** Plugin package identifier */
  packageId: string;
  /** Plugin package version */
  version: string;
  /** SHA256 of the plugin package archive */
  pluginSha256: string;
  /** Source ref recorded by the plugin package */
  sourceRef: string;
  /** Source commit recorded by the plugin package */
  sourceCommit: string;
}

/**
 * A single module in the manifest
 * Modules represent installable tools, packages, or configurations
 */
export interface Module {
  /** Unique identifier for the module (e.g., "shell.zsh", "lang.bun") */
  id: string;
  /** Human-readable description of what this module provides */
  description: string;
  /** Optional category grouping for generated layout */
  category?: ModuleCategory;
  /** Execution context for install/verify steps */
  run_as: RunAs;
  /** Verified upstream installer reference */
  verified_installer?: VerifiedInstaller;
  /** Controls whether install failures are warnings */
  optional: boolean;
  /** Controls default selection when filtering */
  enabled_by_default: boolean;
  /** Installed check used for skip-if-present logic */
  installed_check?: InstalledCheck;
  /** Optional guard run before verified installers / install steps */
  pre_install_check?: PreInstallCheck;
  /** Skip generation if orchestration-only */
  generated: boolean;
  /** Phase number for ordering (1-10) */
  phase?: number;
  /** Installation commands to run (shell commands or descriptions) */
  install: string[];
  /** Verification commands to check if installation succeeded */
  verify: string[];
  /** Optional notes about the module */
  notes?: string[];
  /** Optional user-facing message printed after the module finishes installing */
  post_install_message?: string;
  /**
   * Distro families this module applies to (#385). Omitted means all of them;
   * a narrowed list makes both the installer's skip and doctor's expectations
   * derive from one declaration instead of from hand-written installer logic.
   */
  families?: DistroFamily[];
  /** Optional tags for higher-level selection */
  tags?: string[];
  /** Optional documentation URL */
  docs_url?: string;
  /** Module IDs this module depends on */
  dependencies?: string[];
  /** Optional aliases this module creates */
  aliases?: string[];
  /** Optional web-facing metadata for website content generation */
  web?: ModuleWebMetadata;
  /** Present only for modules supplied by validated plugin packages */
  plugin?: ModulePluginProvenance;
}

/**
 * The complete ACFS manifest
 */
export interface Manifest {
  /** Schema version number */
  version: number;
  /** Project name */
  name: string;
  /** Short identifier */
  id: string;
  /** Default configuration values */
  defaults: ManifestDefaults;
  /** List of all modules */
  modules: Module[];
}

/**
 * Result of manifest validation
 */
export interface ValidationResult {
  /** Whether the manifest is valid */
  valid: boolean;
  /** Validation errors (if any) */
  errors: ValidationError[];
  /** Validation warnings (non-fatal issues) */
  warnings: ValidationWarning[];
}

/**
 * A validation error
 */
export interface ValidationError {
  /** Path to the invalid field */
  path: string;
  /** Error message */
  message: string;
  /** The invalid value (if available) */
  value?: unknown;
}

/**
 * A validation warning
 */
export interface ValidationWarning {
  /** Path to the field with the warning */
  path: string;
  /** Warning message */
  message: string;
}

/**
 * Parse result from YAML parsing
 */
export interface ParseResult<T> {
  /** Whether parsing succeeded */
  success: boolean;
  /** Parsed data (if successful) */
  data?: T;
  /** Parse error (if failed) */
  error?: ParseError;
}

/**
 * A parsing error
 */
export interface ParseError {
  /** Error message */
  message: string;
  /** Line number (if available) */
  line?: number;
  /** Column number (if available) */
  column?: number;
}
