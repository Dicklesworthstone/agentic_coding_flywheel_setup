/**
 * ACFS Manifest Schema
 * Zod schema definitions for validating manifest files
 */

import { z } from 'zod';
import { DISTRO_FAMILIES, MODULE_CATEGORIES } from './types.js';

// The manifest is executable configuration. Keep authored object boundaries
// strict so a misspelled field cannot be silently stripped before generation.

/**
 * Schema for manifest defaults
 */
export const ManifestDefaultsSchema = z
  .strictObject({
    user: z
      .string()
      .min(1, 'User cannot be empty')
      .refine((s) => s.trim().length > 0, 'User cannot be only whitespace'),
    workspace_root: z
      .string()
      .min(1, 'Workspace root cannot be empty')
      .refine((s) => s.trim().length > 0, 'Workspace root cannot be only whitespace'),
    mode: z.enum(['vibe', 'safe']).default('vibe'),
  });

/**
 * Schema for a single module
 */
const RunAsSchema = z.enum(['target_user', 'root', 'current']);
const ModuleCategorySchema = z.enum(MODULE_CATEGORIES);
const DistroFamilySchema = z.enum(DISTRO_FAMILIES);
const ShellCommandSchema = z
  .string()
  .min(1, 'Shell command cannot be empty')
  .refine((command) => command.trim().length > 0, 'Shell command cannot be only whitespace');

/**
 * Allowlist of verified installer runners.
 * SECURITY: Only allow known-safe shell interpreters to prevent command injection.
 * Expand only if there is a concrete, vetted need.
 */
const VerifiedInstallerRunnerSchema = z.enum(['bash', 'sh'], {
  error: 'verified_installer.runner must be "bash" or "sh" (security: runner allowlist)',
});

function isAllowedVerifiedInstallerEnv(tool: string, entry: string): boolean {
  if (tool === 'atuin') return entry === 'ATUIN_NO_MODIFY_PATH=1';
  if (tool === 'mcp_agent_mail') {
    return entry === 'AM_INSTALL_SKIP_MCP_SETUP=1'
      || entry === 'AM_INSTALL_SKIP_REMOTE_HTTP_READINESS=1';
  }
  if (tool === 'grok') return entry === 'GROK_BIN_DIR=$TARGET_HOME/.local/bin';
  if (tool === 'ru' || tool === 's2p') return entry === 'RU_NON_INTERACTIVE=1';
  if (tool === 'cass') {
    return entry === 'TMPDIR=$TARGET_HOME/.cache/acfs/installer-tmp/cass.XXXXXX';
  }
  return false;
}

const VerifiedInstallerSchema = z
  .strictObject({
    tool: z
      .string()
      .min(1, 'Verified installer tool cannot be empty')
      .regex(
        /^[a-z][a-z0-9_]*$/,
        'Tool name must be lowercase alphanumeric with underscores (e.g., "bun", "claude", "mcp_agent_mail")'
      ),
    // Optional canonical URL for drift detection against checksums.yaml.
    // SECURITY: require HTTPS because these installers are downloaded and executed.
    url: z
      .string()
      .url('verified_installer.url must be a valid URL')
      .refine(
        (value) => value.startsWith('https://'),
        'verified_installer.url must use https://'
      )
      .optional(),
    fallback_url: z
      .string()
      .url('verified_installer.fallback_url must be a valid URL')
      .refine(
        (value) => value.startsWith('https://'),
        'verified_installer.fallback_url must use https://'
      )
      .optional(),
    runner: VerifiedInstallerRunnerSchema,
    env: z
      .array(
        z
          .string()
          .max(240, 'Verified installer env entries must be at most 240 characters')
          .regex(
            /^[A-Za-z_][A-Za-z0-9_]*=.*$/,
            'Verified installer env entries must be KEY=value assignments'
          )
      )
      .superRefine((entries, context) => {
        const names = new Set<string>();
        entries.forEach((entry, index) => {
          const name = entry.slice(0, entry.indexOf('='));
          if (names.has(name)) {
            context.addIssue({
              code: 'custom',
              path: [index],
              message: `Duplicate verified installer env variable: ${name}`,
            });
          }
          names.add(name);
        });
      })
      .default([]),
    args: z
      .array(z.string().max(1024, 'Verified installer args must be at most 1024 characters'))
      .max(128, 'Verified installer args must contain at most 128 entries')
      .superRefine((args, context) => {
        const separatorIndex = args.indexOf('--');
        if (separatorIndex > 0) {
          context.addIssue({
            code: 'custom',
            path: [separatorIndex - 1],
            message: 'Runner options are forbidden; when present, "--" must be the first arg',
          });
        }
      })
      .default([]),
  })
  .superRefine((installer, context) => {
    installer.env.forEach((entry, index) => {
      if (!isAllowedVerifiedInstallerEnv(installer.tool, entry)) {
        context.addIssue({
          code: 'custom',
          path: ['env', index],
          message: 'Verified installer env entry is not allowed for this tool',
        });
      }
    });
  })
  .refine((installer) => installer.fallback_url === undefined, {
    path: ['fallback_url'],
    message:
      'verified_installer.fallback_url is unsupported. Verified installers fail closed; remove fallback_url.',
  });

const ModulePluginProvenanceSchema = z.strictObject({
  packageId: z
    .string()
    .regex(
      /^[a-z][a-z0-9_.-]*$/,
      'Plugin package ID must use lowercase letters, digits, dots, underscores, or hyphens'
    ),
  version: z
    .string()
    .min(1, 'Plugin version cannot be empty')
    .refine((value) => value.trim().length > 0, 'Plugin version cannot be only whitespace')
    .refine(
      (value) => !/[\u0000-\u001f\u007f]/u.test(value),
      'Plugin version cannot contain control characters'
    ),
  pluginSha256: z
    .string()
    .regex(/^[a-f0-9]{64}$/i, 'Plugin package SHA-256 must contain 64 hexadecimal characters'),
  sourceRef: z
    .string()
    .min(1, 'Plugin source ref cannot be empty')
    .refine((value) => value.trim().length > 0, 'Plugin source ref cannot be only whitespace'),
  sourceCommit: z
    .string()
    .regex(/^[a-f0-9]{40}$/i, 'Plugin source commit must contain 40 hexadecimal characters'),
});

function isSafeModuleHref(value: string): boolean {
  if (/^\/(?!\/)[a-z0-9/_-]*$/.test(value)) return true;
  if (/[\s\\]/.test(value)) return false;

  try {
    const url = new URL(value);
    return (url.protocol === 'https:' || url.protocol === 'http:')
      && url.hostname.length > 0
      && url.username.length === 0
      && url.password.length === 0;
  } catch {
    return false;
  }
}

/**
 * Schema for module web metadata.
 * All fields are optional; the entire `web` block is optional on a module.
 * Constraints prevent unsafe content (no raw HTML, validated hex colors, bounded lengths).
 */
export const ModuleWebMetadataSchema = z
  .strictObject({
    display_name: z
      .string()
      .min(1, 'display_name cannot be empty')
      .max(100, 'display_name must be at most 100 characters')
      .optional(),
    short_name: z
      .string()
      .min(1, 'short_name cannot be empty')
      .max(30, 'short_name must be at most 30 characters')
      .optional(),
    tagline: z
      .string()
      .min(1, 'tagline cannot be empty')
      .max(200, 'tagline must be at most 200 characters')
      .optional(),
    short_desc: z
      .string()
      .min(1, 'short_desc cannot be empty')
      .max(500, 'short_desc must be at most 500 characters')
      .optional(),
    icon: z
      .string()
      .min(1, 'icon cannot be empty')
      .max(50, 'icon must be at most 50 characters')
      .regex(
        /^[a-z][a-z0-9-]*$/,
        'icon must be a lowercase kebab-case Lucide icon name (e.g., "mail", "terminal-square")'
      )
      .optional(),
    // SECURITY: Restrict color to hex format to prevent CSS injection
    color: z
      .string()
      .regex(
        /^#[0-9a-fA-F]{6}$/,
        'color must be a 6-digit hex code (e.g., "#3B82F6")'
      )
      .optional(),
    category_label: z
      .string()
      .min(1, 'category_label cannot be empty')
      .max(50, 'category_label must be at most 50 characters')
      .optional(),
    href: z
      .string()
      .refine(
        isSafeModuleHref,
        'href must be an absolute path (e.g., "/tools/agent-mail") or a full URL (e.g., "https://github.com/...")'
      )
      .optional(),
    features: z.array(z.string().min(1).max(200)).max(20).optional(),
    tech_stack: z.array(z.string().min(1).max(50)).max(20).optional(),
    use_cases: z.array(z.string().min(1).max(300)).max(20).optional(),
    language: z
      .string()
      .min(1, 'language cannot be empty')
      .max(30, 'language must be at most 30 characters')
      .optional(),
    stars: z.number().int().min(0).optional(),
    cli_name: z
      .string()
      .min(1, 'cli_name cannot be empty')
      .max(30, 'cli_name must be at most 30 characters')
      .regex(
        /^[a-z][a-z0-9_-]*$/,
        'cli_name must be lowercase alphanumeric with hyphens/underscores'
      )
      .optional(),
    cli_aliases: z
      .array(z.string().min(1).max(30))
      .max(10)
      .optional(),
    command_example: z
      .string()
      .min(1, 'command_example cannot be empty')
      .max(200, 'command_example must be at most 200 characters')
      .optional(),
    lesson_slug: z
      .string()
      .min(1, 'lesson_slug cannot be empty')
      .max(100, 'lesson_slug must be at most 100 characters')
      .regex(
        /^[a-z][a-z0-9-]*$/,
        'lesson_slug must be lowercase kebab-case (e.g., "getting-started")'
      )
      .optional(),
    tldr_snippet: z
      .string()
      .min(1, 'tldr_snippet cannot be empty')
      .max(500, 'tldr_snippet must be at most 500 characters')
      .optional(),
    visible: z.boolean().default(true),
  });

export const ModuleSchema = z
  .strictObject({
    id: z
      .string()
      .min(1, 'Module ID cannot be empty')
      .regex(
        /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/,
        'Module ID must be lowercase with dots (e.g., "shell.zsh", "lang.bun")'
      ),
    description: z
      .string()
      .min(1, 'Description cannot be empty')
      .refine((s) => s.trim().length > 0, 'Description cannot be only whitespace')
      .refine(
        (s) => !/[\n\r\t]/.test(s),
        'Description must be single-line with no tabs (newlines break generated bash scripts; tabs corrupt the tab-delimited doctor check records)'
      ),

    // SECURITY: Category is used in generated script filenames (install_<category>.sh)
    // and function names (install_<category>). Must be validated to prevent path traversal
    // or command injection in generated scripts.
    category: ModuleCategorySchema.optional(),

    // Execution context
    run_as: RunAsSchema.default('target_user'),

    // Verified installer reference
    verified_installer: VerifiedInstallerSchema.optional(),

    // Distro families this module applies to (#385). Absent means "every
    // family", which is the case for all but a handful of modules whose
    // upstream installer is package-manager specific. Both install.sh and the
    // generated doctor checks read this, so a module that is skipped by design
    // is reported as SKIP rather than warned about with a fix that would skip
    // it again.
    families: z
      .array(DistroFamilySchema)
      .min(1, 'families cannot be an empty list; omit the key to mean "all families"')
      .refine(
        (families) => new Set(families).size === families.length,
        'families cannot contain duplicates'
      )
      .optional(),

    // Installation behavior
    optional: z.boolean().default(false),
    enabled_by_default: z.boolean().default(true),
    installed_check: z
      .strictObject({
        run_as: RunAsSchema.default('target_user'),
        command: z
          .string()
          .min(1, 'Installed check command cannot be empty')
          .refine((s) => s.trim().length > 0, 'Installed check command cannot be only whitespace'),
      })
      .optional(),
    pre_install_check: z
      .strictObject({
        run_as: RunAsSchema.default('target_user'),
        command: z
          .string()
          .min(1, 'Pre-install check command cannot be empty')
          .refine((s) => s.trim().length > 0, 'Pre-install check command cannot be only whitespace'),
        skip_message: z
          .string()
          .min(1, 'Pre-install check skip_message cannot be empty')
          .refine((s) => s.trim().length > 0, 'Pre-install check skip_message cannot be only whitespace'),
      })
      .optional(),
    generated: z.boolean().default(true),

    phase: z.number().int().min(1).max(10).optional(),

    // Install steps are shell strings (executed via run_as_*_shell).
    // Allow empty when verified_installer is provided.
    install: z.array(ShellCommandSchema).default([]),
    verify: z.array(ShellCommandSchema).min(1, 'At least one verify command required'),
    dependencies: z.array(z.string()).optional(),
    notes: z.array(z.string()).optional(),
    post_install_message: z
      .string()
      .min(1, 'post_install_message cannot be empty')
      .refine(
        (s) => s.trim().length > 0,
        'post_install_message cannot be only whitespace'
      )
      .optional(),
    tags: z.array(z.string()).optional(),
    docs_url: z.string().url().optional(),
    aliases: z.array(z.string()).optional(),
    web: ModuleWebMetadataSchema.optional(),
    plugin: ModulePluginProvenanceSchema.optional(),
  })
  .refine(
    (module) =>
      module.generated === false ||
      module.verified_installer !== undefined ||
      module.install.length > 0,
    {
      message:
        'Module must define verified_installer or install commands (or set generated: false).',
    }
  )
  .refine(
    (module) => module.verified_installer === undefined || module.run_as === 'target_user',
    {
      path: ['run_as'],
      message: 'Modules with verified_installer must run as target_user through the clean runner boundary.',
    }
  )
  .superRefine((module, context) => {
    const idCategory = module.id.split('.', 1)[0];
    if (module.category === undefined
      && !MODULE_CATEGORIES.some((category) => category === idCategory)) {
      context.addIssue({
        code: 'custom',
        path: ['id'],
        message: `Module ID without an explicit category must begin with a canonical category (${MODULE_CATEGORIES.join(', ')})`,
      });
    }
  });

/**
 * Schema for the complete manifest
 */
export const ManifestSchema = z
  .strictObject({
    version: z.number().int().positive('Version must be a positive integer'),
    name: z
      .string()
      .min(1, 'Name cannot be empty')
      .refine((s) => s.trim().length > 0, 'Name cannot be only whitespace'),
    id: z
      .string()
      .min(1, 'ID cannot be empty')
      .regex(/^[a-z][a-z0-9_]*$/, 'ID must be lowercase alphanumeric with underscores'),
    defaults: ManifestDefaultsSchema,
    modules: z.array(ModuleSchema).min(1, 'At least one module required'),
  });

/**
 * Type inference from schemas
 */
export type ManifestDefaultsInput = z.input<typeof ManifestDefaultsSchema>;
export type ManifestDefaultsOutput = z.output<typeof ManifestDefaultsSchema>;

export type ModuleInput = z.input<typeof ModuleSchema>;
export type ModuleOutput = z.output<typeof ModuleSchema>;

export type ModuleWebMetadataInput = z.input<typeof ModuleWebMetadataSchema>;
export type ModuleWebMetadataOutput = z.output<typeof ModuleWebMetadataSchema>;

export type ManifestInput = z.input<typeof ManifestSchema>;
export type ManifestOutput = z.output<typeof ManifestSchema>;
