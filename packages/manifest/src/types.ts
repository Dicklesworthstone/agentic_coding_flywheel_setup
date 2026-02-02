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
  /** Executable runner (must be bash or sh) */
  runner: VerifiedInstallerRunner;
  /** Optional additional args for runner */
  args?: string[];
  /** If true, run installer in detached tmux session (prevents blocking) */
  run_in_tmux?: boolean;
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
 * A single module in the manifest
 * Modules represent installable tools, packages, or configurations
 */
export interface Module {
  /** Unique identifier for the module (e.g., "shell.zsh", "lang.bun") */
  id: string;
  /** Human-readable description of what this module provides */
  description: string;
  /** Optional category grouping for generated layout */
  category?: string;
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
 * Module category derived from module ID prefix
 */
export type ModuleCategory =
  | 'base'
  | 'users'
  | 'filesystem'
  | 'shell'
  | 'cli'
  | 'network'
  | 'lang'
  | 'tools'
  | 'db'
  | 'cloud'
  | 'agents'
  | 'stack'
  | 'acfs';

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
