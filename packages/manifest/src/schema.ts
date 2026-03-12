/**
 * ACFS Manifest Schema
 * Zod schema definitions for validating manifest files
 */

import { z } from 'zod';

/**
 * Schema for manifest defaults
 */
export const ManifestDefaultsSchema = z.object({
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

/**
 * Allowlist of verified installer runners.
 * SECURITY: Only allow known-safe shell interpreters to prevent command injection.
 * Expand only if there is a concrete, vetted need.
 */
const VerifiedInstallerRunnerSchema = z.enum(['bash', 'sh'], {
  error: 'verified_installer.runner must be "bash" or "sh" (security: runner allowlist)',
});

/**
 * Schema for module web metadata.
 * All fields are optional; the entire `web` block is optional on a module.
 * Constraints prevent unsafe content (no raw HTML, validated hex colors, bounded lengths).
 */
export const ModuleWebMetadataSchema = z
  .object({
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
      .regex(
        /^(\/[a-z0-9/_-]*|https?:\/\/.+)$/,
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
  .object({
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
      .refine((s) => s.trim().length > 0, 'Description cannot be only whitespace'),

    // SECURITY: Category is used in generated script filenames (install_<category>.sh)
    // and function names (install_<category>). Must be validated to prevent path traversal
    // or command injection in generated scripts.
    category: z
      .string()
      .regex(
        /^[a-z][a-z0-9_]*$/,
        'Category must be lowercase alphanumeric with underscores (e.g., "shell", "lang_tools")'
      )
      .optional(),

    // Execution context
    run_as: RunAsSchema.default('target_user'),

    // Verified installer reference
    verified_installer: z
      .object({
        tool: z
          .string()
          .min(1, 'Verified installer tool cannot be empty')
          .regex(
            /^[a-z][a-z0-9_]*$/,
            'Tool name must be lowercase alphanumeric with underscores (e.g., "bun", "claude", "mcp_agent_mail")'
          ),
        runner: VerifiedInstallerRunnerSchema,
        env: z
          .array(
            z
              .string()
              .regex(
                /^[A-Za-z_][A-Za-z0-9_]*=.*$/,
                'Verified installer env entries must be KEY=value assignments'
              )
          )
          .default([]),
        args: z.array(z.string()).default([]),
        // Run installer in detached tmux session (prevents blocking for long-running services)
        run_in_tmux: z.boolean().default(false),
      })
      .optional(),

    // Installation behavior
    optional: z.boolean().default(false),
    enabled_by_default: z.boolean().default(true),
    installed_check: z
      .object({
        run_as: RunAsSchema.default('target_user'),
        command: z
          .string()
          .min(1, 'Installed check command cannot be empty')
          .refine((s) => s.trim().length > 0, 'Installed check command cannot be only whitespace'),
      })
      .optional(),
    generated: z.boolean().default(true),

    phase: z.number().int().min(1).max(10).optional(),

    // Install steps are shell strings (executed via run_as_*_shell).
    // Allow empty when verified_installer is provided.
    install: z.array(z.string()).default([]),
    verify: z.array(z.string()).min(1, 'At least one verify command required'),
    dependencies: z.array(z.string()).optional(),
    notes: z.array(z.string()).optional(),
    tags: z.array(z.string()).optional(),
    docs_url: z.string().url().optional(),
    aliases: z.array(z.string()).optional(),
    web: ModuleWebMetadataSchema.optional(),
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
  );

/**
 * Schema for the complete manifest
 */
export const ManifestSchema = z.object({
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
