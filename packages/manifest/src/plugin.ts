import { closeSync, constants, fstatSync, openSync, readSync } from 'node:fs';
import { isIP } from 'node:net';
import { TextDecoder, types as utilTypes } from 'node:util';
import { z } from 'zod';
import { ModuleWebMetadataSchema } from './schema.js';
import type { InstallerChecksumEntry } from './validate.js';
import {
  MODULE_CATEGORIES,
  type Manifest,
  type Module,
  type ModuleCategory,
  type RunAs,
} from './types.js';
import { isValidCategory, toGeneratedFunctionName } from './utils.js';

const PLUGIN_SCHEMA = 'acfs.plugin-package.v1';
const SUPPORTED_SCHEMA_VERSION = 1;
export const MAX_PLUGIN_MANIFEST_BYTES = 1_048_576;
export const MAX_PLUGIN_JSON_NESTING_DEPTH = 64;
export const MAX_PLUGIN_JSON_NODES = 50_000;
const SHA256_HEX_PATTERN = /^[a-f0-9]{64}$/i;
const VERIFIED_INSTALLER_TOOL_PATTERN = /^[a-z][a-z0-9_]*$/;
const ENV_ASSIGNMENT_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*=.*$/;
const COMMAND_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._+-]*$/;
const MODULE_ID_PATTERN =
  /^plugin\.([a-z][a-z0-9_]*)\.[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/;
const PACKAGE_ID_PATTERN = /^[a-z][a-z0-9_.-]*$/;
const ALLOWED_RUNNERS = new Set(['bash', 'sh']);
const ALLOWED_INSTALL_KINDS = new Set([
  'verified_installer',
  'release_artifact',
  'copy_asset',
  'manual_step',
]);
// The normalized Module type can currently execute only checksum-bound
// installers. Keep reserved declarative kinds fail-closed until their archive
// and copy/manual executors exist; otherwise they normalize to empty installs.
const IMPLEMENTED_INSTALL_KINDS = new Set(['verified_installer']);
// Package authors declare the capabilities they use, but they do not get to
// downgrade ACFS policy. These capabilities always require an external review
// record even if a package incorrectly places them in its `allowed` bucket.
const INTRINSICALLY_REVIEW_REQUIRED_CAPABILITIES = new Set([
  'root_run_as',
  'cross_plugin_dependency',
]);
const ALLOWED_CATEGORIES = new Set<ModuleCategory>(MODULE_CATEGORIES);
const ALLOWED_TOP_LEVEL_FIELDS = new Set([
  'schema',
  'schemaVersion',
  'packageId',
  'displayName',
  'version',
  'description',
  'publisher',
  'license',
  'docsUrl',
  'provenance',
  'targets',
  'capabilities',
  'modules',
  'offline',
  'extensions',
]);
const SECRET_FIELD_NAMES = new Set([
  'token',
  'apikey',
  'secret',
  'password',
  'passphrase',
  'privatekey',
  'clientsecret',
  'refreshtoken',
  'accesstoken',
  'cookie',
  'session',
  'vaultroottoken',
  'sshprivatekey',
]);
const SECRET_FIELD_WORD_SEQUENCES: readonly (readonly string[])[] = [
  ['api', 'key'],
  ['private', 'key'],
  ['pass', 'phrase'],
];
const SECRET_VALUE_PATTERNS: readonly RegExp[] = [
  /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/i,
  /(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]{20,}/,
  /sk-[A-Za-z0-9_-]{20,}/,
  /(?:hvs|hvb|hvr)\.[A-Za-z0-9_-]{20,}/i,
  /(?:glpat-|sbp_|shpat_|xox[baprs]-|npm_|sk_(?:live|test)_|rk_(?:live|test)_)[A-Za-z0-9_-]{16,}/i,
  /\bAKIA[A-Z0-9]{16}\b/,
  /\bAIza[0-9A-Za-z_-]{30,}\b/,
  /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/,
  /Bearer [A-Za-z0-9._~+/-]{12,}/i,
];
const DISALLOWED_INSTALL_FIELDS = new Set([
  'command',
  'commands',
  'shell',
  'script',
  'inlineScript',
  'inline_script',
  'heredoc',
  'eval',
]);

const NonBlankStringSchema = z.string().min(1).refine((value) => value.trim().length > 0, {
  message: 'String cannot be only whitespace',
});
const HttpsUrlSchema = z.string().url().refine((value) => {
  try {
    return new URL(value).protocol === 'https:';
  } catch {
    return false;
  }
}, {
  message: 'URL must use https://',
});
const CanonicalUtcTimestampSchema = NonBlankStringSchema.refine((value) => {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return false;

  const canonical = parsed.toISOString();
  return value === canonical || value === canonical.replace('.000Z', 'Z');
}, {
  message: 'Timestamp must be a canonical UTC ISO-8601 value',
});
const PluginVerifyCheckSchema = z.strictObject({
  kind: z.literal('command_exists'),
  command: z.string().regex(
    COMMAND_NAME_PATTERN,
    'command_exists command must be a bare executable name'
  ),
});

const PluginInstallSchema = z.object({ kind: NonBlankStringSchema }).passthrough();

const PluginTargetSchema = z
  .object({
    os: NonBlankStringSchema,
    versions: z.array(NonBlankStringSchema).min(1),
    arch: z.array(NonBlankStringSchema).min(1),
    libc: z.array(NonBlankStringSchema).min(1),
  })
  .passthrough();

const PluginWebMetadataSchema = ModuleWebMetadataSchema.superRefine((metadata, context) => {
  if (metadata.href !== undefined && !metadata.href.startsWith('/')) {
    try {
      if (new URL(metadata.href).protocol !== 'https:') {
        context.addIssue({
          code: 'custom',
          path: ['href'],
          message: 'External plugin web href must use https://',
        });
      }
    } catch {
      context.addIssue({
        code: 'custom',
        path: ['href'],
        message: 'External plugin web href must be a valid HTTPS URL',
      });
    }
  }
});

const PluginModuleSchema = z
  .object({
    id: NonBlankStringSchema,
    description: NonBlankStringSchema.refine((value) => !/[\r\n\t]/.test(value), {
      message: 'Description must be single-line with no tabs',
    }),
    category: NonBlankStringSchema,
    phase: z.number().int().min(1).max(10),
    run_as: z.enum(['target_user', 'root', 'current']),
    optional: z.boolean(),
    enabled_by_default: z.boolean(),
    dependencies: z.array(NonBlankStringSchema).optional(),
    install: PluginInstallSchema,
    verify: z.array(PluginVerifyCheckSchema).min(1),
    docs_url: HttpsUrlSchema,
    web: PluginWebMetadataSchema.optional(),
  })
  .passthrough();

const PluginPackageSchema = z
  .object({
    schema: z.string(),
    schemaVersion: z.number().int(),
    packageId: z.string().regex(PACKAGE_ID_PATTERN),
    displayName: NonBlankStringSchema,
    version: NonBlankStringSchema,
    description: NonBlankStringSchema,
    publisher: z
      .object({
        name: NonBlankStringSchema,
        contactUrl: HttpsUrlSchema,
        sourceUrl: HttpsUrlSchema,
      })
      .passthrough(),
    license: NonBlankStringSchema,
    docsUrl: HttpsUrlSchema.optional(),
    provenance: z
      .object({
        generatedAt: CanonicalUtcTimestampSchema,
        sourceRef: NonBlankStringSchema,
        sourceCommit: z.string().regex(/^[a-f0-9]{40}$/i),
        acfsManifestVersion: z.number().int().positive(),
      })
      .passthrough(),
    targets: z.array(PluginTargetSchema).min(1),
    capabilities: z
      .object({
        allowed: z.array(NonBlankStringSchema),
        reviewRequired: z.array(NonBlankStringSchema),
        disallowed: z.array(NonBlankStringSchema),
      })
      .passthrough(),
    modules: z.array(PluginModuleSchema).min(1),
    offline: z
      .object({
        bundlingPolicy: z.enum(['bundled', 'metadata_only', 'live_required', 'prohibited']),
        liveAuthRequired: z.boolean(),
        providerInteractionRequired: z.boolean(),
      })
      .passthrough(),
    extensions: z.record(z.string(), z.unknown()).optional(),
  })
  .passthrough();

export type PluginPackage = z.output<typeof PluginPackageSchema>;
export type PluginModule = PluginPackage['modules'][number];

export type PluginDiagnosticCode =
  | 'plugin_schema_unsupported'
  | 'plugin_missing_required_field'
  | 'plugin_unknown_top_level_field'
  | 'plugin_archive_layout_invalid'
  | 'plugin_package_hash_mismatch'
  | 'plugin_target_unsupported'
  | 'plugin_module_id_invalid'
  | 'plugin_module_collision'
  | 'plugin_generated_function_collision'
  | 'plugin_dependency_invalid'
  | 'plugin_capability_undeclared'
  | 'plugin_review_required'
  | 'plugin_disallowed_behavior'
  | 'plugin_verified_installer_checksum_required'
  | 'plugin_artifact_hash_required'
  | 'plugin_secret_material_refused'
  | 'plugin_offline_policy_incompatible';

export type PluginDiagnosticSeverity = 'error' | 'review_required' | 'warning';

export interface PluginDiagnostic {
  code: PluginDiagnosticCode;
  message: string;
  path: string;
  severity: PluginDiagnosticSeverity;
  moduleId?: string;
  context?: Record<string, unknown>;
}

export interface PluginValidationTarget {
  os: string;
  version: string;
  arch: string;
  libc: string;
}

export interface PluginValidationOptions {
  firstPartyManifest: Manifest;
  installers?: Record<string, InstallerChecksumEntry>;
  target?: PluginValidationTarget;
  existingPluginModuleIds?: Iterable<string>;
  /** SHA-256 calculated from the exact compressed package bytes being validated. */
  packageSha256?: string;
  /** Independently trusted package SHA-256 from a profile, pack, or review record. */
  expectedPackageSha256?: string;
}

export interface PluginValidationResult {
  valid: boolean;
  diagnostics: PluginDiagnostic[];
  package?: PluginPackage;
  manifestModules: Module[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function addDiagnostic(
  diagnostics: PluginDiagnostic[],
  diagnostic: PluginDiagnostic
): void {
  const redactString = (value: string): string =>
    containsSecretLikeValue(value) ? '<redacted>' : value;
  const redactContextValue = (value: unknown): unknown => {
    if (typeof value === 'string') return redactString(value);
    if (Array.isArray(value)) return value.map(redactContextValue);
    if (isRecord(value)) {
      return Object.fromEntries(
        Object.entries(value).map(([key, child]) => [redactString(key), redactContextValue(child)])
      );
    }
    return value;
  };

  diagnostics.push({
    ...diagnostic,
    message: redactString(diagnostic.message),
    path: redactString(diagnostic.path),
    moduleId: diagnostic.moduleId ? redactString(diagnostic.moduleId) : undefined,
    context: diagnostic.context
      ? (redactContextValue(diagnostic.context) as Record<string, unknown>)
      : undefined,
  });
}

function inspectPluginInputStructure(
  input: unknown,
  diagnostics: PluginDiagnostic[]
): boolean {
  const pending: Array<{ value: unknown; path: string; depth: number }> = [
    { value: input, path: '<root>', depth: 0 },
  ];
  const seen = new WeakSet<object>();
  let nodes = 0;
  let stringBytes = 0;

  const refuse = (message: string, path: string): false => {
    addDiagnostic(diagnostics, {
      code: 'plugin_disallowed_behavior',
      message,
      path,
      severity: 'error',
    });
    return false;
  };

  try {
    while (pending.length > 0) {
      const candidate = pending.pop()!;
      nodes++;
      if (nodes > MAX_PLUGIN_JSON_NODES) {
        return refuse(
          `Plugin manifest exceeds the maximum JSON node count of ${MAX_PLUGIN_JSON_NODES}`,
          '<root>'
        );
      }
      if (candidate.depth > MAX_PLUGIN_JSON_NESTING_DEPTH) {
        return refuse(
          `Plugin manifest exceeds the maximum JSON nesting depth of ${MAX_PLUGIN_JSON_NESTING_DEPTH}`,
          candidate.path
        );
      }

      if (typeof candidate.value === 'string') {
        stringBytes += Buffer.byteLength(candidate.value, 'utf8');
        if (stringBytes > MAX_PLUGIN_MANIFEST_BYTES) {
          return refuse('Plugin manifest string content exceeds the accepted size budget', '<root>');
        }
        continue;
      }
      if (candidate.value === null || typeof candidate.value === 'boolean') continue;
      if (typeof candidate.value === 'number') {
        if (!Number.isFinite(candidate.value)) {
          return refuse('Plugin manifest numbers must be finite JSON values', candidate.path);
        }
        continue;
      }
      if (typeof candidate.value !== 'object') {
        return refuse('Plugin manifest must contain only JSON-compatible values', candidate.path);
      }
      if (utilTypes.isProxy(candidate.value)) {
        return refuse('Plugin manifest must not contain Proxy objects', candidate.path);
      }
      if (seen.has(candidate.value)) {
        return refuse(
          'Plugin manifest must not contain repeated or cyclic object references',
          candidate.path
        );
      }
      seen.add(candidate.value);

      const arrayValue = Array.isArray(candidate.value);
      if (arrayValue && candidate.value.length > MAX_PLUGIN_JSON_NODES) {
        return refuse(
          `Plugin manifest array exceeds the maximum item count of ${MAX_PLUGIN_JSON_NODES}`,
          candidate.path
        );
      }
      const prototype = Object.getPrototypeOf(candidate.value);
      if (arrayValue && prototype !== Array.prototype) {
        return refuse('Plugin manifest must contain only standard JSON arrays', candidate.path);
      }
      if (!arrayValue && prototype !== Object.prototype && prototype !== null) {
        return refuse('Plugin manifest must contain only plain JSON objects', candidate.path);
      }

      const descriptors = Object.getOwnPropertyDescriptors(candidate.value);
      let arrayItemCount = 0;
      for (const key of Reflect.ownKeys(descriptors)) {
        if (typeof key !== 'string') {
          return refuse('Plugin manifest must not contain symbol-keyed properties', candidate.path);
        }
        stringBytes += Buffer.byteLength(key, 'utf8');
        if (stringBytes > MAX_PLUGIN_MANIFEST_BYTES) {
          return refuse('Plugin manifest string content exceeds the accepted size budget', '<root>');
        }
        if (arrayValue && key === 'length') continue;
        if (arrayValue && !/^(?:0|[1-9][0-9]*)$/.test(key)) {
          return refuse('Plugin manifest arrays must not contain named properties', candidate.path);
        }
        if (arrayValue) arrayItemCount++;

        const descriptor = descriptors[key];
        const childPath = candidate.path === '<root>'
          ? key
          : arrayValue
            ? `${candidate.path}[${key}]`
            : `${candidate.path}.${key}`;
        if (!descriptor.enumerable) {
          return refuse('Plugin manifest must not contain hidden properties', childPath);
        }
        if (!('value' in descriptor)) {
          return refuse('Plugin manifest must not contain accessor properties', childPath);
        }
        pending.push({
          value: descriptor.value,
          path: childPath,
          depth: candidate.depth + 1,
        });
      }
      if (arrayValue && arrayItemCount !== candidate.value.length) {
        return refuse('Plugin manifest must not contain sparse arrays', candidate.path);
      }
    }
  } catch {
    return refuse('Plugin manifest structure could not be inspected safely', '<root>');
  }

  return true;
}

function normalizeSecretFieldName(name: string): string {
  return name.replace(/[^A-Za-z0-9]/g, '').toLowerCase();
}

function identifierWords(name: string): string[] {
  return name
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .split(/[^A-Za-z0-9]+/)
    .map((word) => word.toLowerCase())
    .filter(Boolean);
}

function containsWordSequence(words: readonly string[], sequence: readonly string[]): boolean {
  if (sequence.length === 0 || sequence.length > words.length) return false;
  return words.some((_, index) =>
    index + sequence.length <= words.length
    && sequence.every((word, offset) => words[index + offset] === word)
  );
}

function isSecretFieldName(name: string): boolean {
  const normalized = normalizeSecretFieldName(name);
  if (SECRET_FIELD_NAMES.has(normalized)) return true;

  const words = identifierWords(name);

  return words.some((word) => SECRET_FIELD_NAMES.has(word))
    || SECRET_FIELD_WORD_SEQUENCES.some((sequence) => containsWordSequence(words, sequence));
}

function packageSlug(packageId: string): string {
  return packageId
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function diagnosticPath(path: PropertyKey[]): string {
  if (path.length === 0) return '<root>';

  return path
    .map((part) => (typeof part === 'number' ? `[${part}]` : String(part)))
    .join('.')
    .replace(/\.\[/g, '[');
}

function stringField(record: Record<string, unknown>, key: string): string | undefined {
  const value = record[key];
  return typeof value === 'string' ? value : undefined;
}

function stringArrayField(record: Record<string, unknown>, key: string): string[] | undefined {
  const value = record[key];
  if (!Array.isArray(value)) return undefined;
  if (!value.every((entry) => typeof entry === 'string')) return undefined;
  return [...value];
}

function isHttpsUrl(value: string | undefined): value is string {
  if (!value) return false;
  try {
    return new URL(value).protocol === 'https:';
  } catch {
    return false;
  }
}

function isSafeRelativePath(value: string | undefined): value is string {
  if (!value) return false;
  if (value.startsWith('/') || value.includes('\0') || value.includes('\\')) return false;
  return !value.split('/').some((part) => part === '' || part === '.' || part === '..');
}

function containsIpLiteral(value: string): boolean {
  const trimmed = value.trim().replace(/^\[|\]$/g, '');
  if (isIP(trimmed) !== 0) return true;

  const ipv4Candidates = value.match(/(?:\d{1,3}\.){3}\d{1,3}/g) ?? [];
  if (ipv4Candidates.some((candidate) => isIP(candidate) === 4)) return true;

  return value
    .split(/[^0-9A-Fa-f:.]+/)
    .map((candidate) => candidate.replace(/^\.+|\.+$/g, ''))
    .some((candidate) => candidate.includes(':') && isIP(candidate) === 6);
}

function containsSecretLikeValue(value: string): boolean {
  if (SECRET_VALUE_PATTERNS.some((pattern) => pattern.test(value))) return true;
  if (containsIpLiteral(value)) return true;
  try {
    const parsedUrl = new URL(value);
    if (
      (parsedUrl.protocol === 'https:' || parsedUrl.protocol === 'http:') &&
      (parsedUrl.username.length > 0 || parsedUrl.password.length > 0)
    ) {
      return true;
    }
  } catch {
    // Non-URL strings continue through the remaining detectors.
  }
  return false;
}

/**
 * JSON.parse accepts duplicate object keys and silently keeps the last value.
 * That is unsafe for a reviewed manifest because a human, a signer, and a
 * consumer can otherwise disagree about which declaration is authoritative.
 * This scanner runs only after JSON.parse has proved the syntax, so it needs to
 * identify object-key boundaries rather than duplicate the JSON validator.
 */
type JsonManifestInspection = 'duplicate_key' | 'nesting_limit' | undefined;

function inspectJsonManifestStructure(text: string): JsonManifestInspection {
  let offset = 0;

  const skipWhitespace = (): void => {
    while (
      offset < text.length &&
      (text[offset] === ' ' ||
        text[offset] === '\n' ||
        text[offset] === '\r' ||
        text[offset] === '\t')
    ) {
      offset++;
    }
  };

  const readString = (): string => {
    const start = offset;
    offset++;
    while (offset < text.length) {
      const character = text[offset++];
      if (character === '\\') {
        offset++;
      } else if (character === '"') {
        return JSON.parse(text.slice(start, offset)) as string;
      }
    }
    return '';
  };

  const skipPrimitive = (): void => {
    while (offset < text.length) {
      const character = text[offset];
      if (
        character === ',' ||
        character === ']' ||
        character === '}' ||
        character === ' ' ||
        character === '\n' ||
        character === '\r' ||
        character === '\t'
      ) {
        return;
      }
      offset++;
    }
  };

  function readValue(depth: number): JsonManifestInspection {
    if (depth > MAX_PLUGIN_JSON_NESTING_DEPTH) return 'nesting_limit';
    skipWhitespace();
    if (text[offset] === '{') return readObject(depth);
    if (text[offset] === '[') return readArray(depth);
    if (text[offset] === '"') {
      readString();
      return undefined;
    }
    skipPrimitive();
    return undefined;
  }

  function readObject(depth: number): JsonManifestInspection {
    offset++;
    skipWhitespace();
    if (text[offset] === '}') {
      offset++;
      return undefined;
    }

    const keys = new Set<string>();
    while (offset < text.length) {
      const key = readString();
      if (keys.has(key)) return 'duplicate_key';
      keys.add(key);

      skipWhitespace();
      offset++;
      const nestedInspection = readValue(depth + 1);
      if (nestedInspection) return nestedInspection;
      skipWhitespace();
      if (text[offset] === '}') {
        offset++;
        return undefined;
      }
      offset++;
      skipWhitespace();
    }
    return undefined;
  }

  function readArray(depth: number): JsonManifestInspection {
    offset++;
    skipWhitespace();
    if (text[offset] === ']') {
      offset++;
      return undefined;
    }

    while (offset < text.length) {
      const nestedInspection = readValue(depth + 1);
      if (nestedInspection) return nestedInspection;
      skipWhitespace();
      if (text[offset] === ']') {
        offset++;
        return undefined;
      }
      offset++;
      skipWhitespace();
    }
    return undefined;
  }

  return readValue(0);
}

function scanSecretMaterial(
  value: unknown,
  diagnostics: PluginDiagnostic[],
  path: string
): void {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => {
      scanSecretMaterial(entry, diagnostics, `${path}[${index}]`);
    });
    return;
  }

  if (isRecord(value)) {
    for (const [key, child] of Object.entries(value)) {
      const childPath = path ? `${path}.${key}` : key;
      if (
        isSecretFieldName(key)
        || containsSecretLikeValue(key)
      ) {
        addDiagnostic(diagnostics, {
          code: 'plugin_secret_material_refused',
          message: `Plugin field "${childPath}" is forbidden because plugins are not credential stores`,
          path: childPath,
          severity: 'error',
          context: { value: '<redacted>' },
        });
      }
      scanSecretMaterial(child, diagnostics, childPath);
    }
    return;
  }

  if (typeof value === 'string' && containsSecretLikeValue(value)) {
    const valuePath = path || '<root>';
    addDiagnostic(diagnostics, {
      code: 'plugin_secret_material_refused',
      message: `Plugin value at "${valuePath}" looks like secret or host-specific material`,
      path: valuePath,
      severity: 'error',
      context: { value: '<redacted>' },
    });
  }
}

function validateTopLevelFields(input: unknown, diagnostics: PluginDiagnostic[]): void {
  if (!isRecord(input)) return;

  for (const key of Object.keys(input)) {
    if (!ALLOWED_TOP_LEVEL_FIELDS.has(key)) {
      addDiagnostic(diagnostics, {
        code: 'plugin_unknown_top_level_field',
        message: `Unknown top-level plugin field "${key}" must move under extensions`,
        path: key,
        severity: 'error',
      });
    }
  }
}

function addSchemaDiagnostics(input: unknown, diagnostics: PluginDiagnostic[]): PluginPackage | undefined {
  const parsed = PluginPackageSchema.safeParse(input);
  if (!parsed.success) {
    for (const issue of parsed.error.issues) {
      const path = diagnosticPath(issue.path);
      addDiagnostic(diagnostics, {
        code: 'plugin_missing_required_field',
        message: issue.message,
        path,
        severity: 'error',
      });
    }
    return undefined;
  }

  const plugin = parsed.data;
  if (plugin.schema !== PLUGIN_SCHEMA || plugin.schemaVersion !== SUPPORTED_SCHEMA_VERSION) {
    addDiagnostic(diagnostics, {
      code: 'plugin_schema_unsupported',
      message: `Unsupported plugin schema ${plugin.schema}@${plugin.schemaVersion}`,
      path: 'schema',
      severity: 'error',
      context: {
        supportedSchema: PLUGIN_SCHEMA,
        supportedSchemaVersion: SUPPORTED_SCHEMA_VERSION,
      },
    });
  }

  return plugin;
}

function hashPrefix(value: string | undefined): string {
  if (!value) return '<missing>';
  if (!SHA256_HEX_PATTERN.test(value)) return '<invalid>';
  return value.slice(0, 12).toLowerCase();
}

function validatePackageHash(
  options: PluginValidationOptions,
  diagnostics: PluginDiagnostic[]
): void {
  const packageSha256 = options.packageSha256;
  const expectedPackageSha256 = options.expectedPackageSha256;
  const packageHashValid =
    typeof packageSha256 === 'string' && SHA256_HEX_PATTERN.test(packageSha256);
  const expectedHashValid =
    typeof expectedPackageSha256 === 'string' && SHA256_HEX_PATTERN.test(expectedPackageSha256);

  if (
    packageHashValid &&
    expectedHashValid &&
    packageSha256.toLowerCase() === expectedPackageSha256.toLowerCase()
  ) {
    return;
  }

  addDiagnostic(diagnostics, {
    code: 'plugin_package_hash_mismatch',
    message:
      'Plugin package SHA-256 is missing, malformed, or does not match the independently trusted digest',
    path: '<package>',
    severity: 'error',
    context: {
      packageSha256Prefix: hashPrefix(packageSha256),
      expectedPackageSha256Prefix: hashPrefix(expectedPackageSha256),
    },
  });
}

function validateProvenance(
  plugin: PluginPackage,
  manifest: Manifest,
  diagnostics: PluginDiagnostic[]
): void {
  if (plugin.provenance.acfsManifestVersion === manifest.version) return;

  addDiagnostic(diagnostics, {
    code: 'plugin_schema_unsupported',
    message:
      `Plugin package "${plugin.packageId}" targets ACFS manifest version ` +
      `${plugin.provenance.acfsManifestVersion}, but this manifest is version ${manifest.version}`,
    path: 'provenance.acfsManifestVersion',
    severity: 'error',
    context: {
      pluginManifestVersion: plugin.provenance.acfsManifestVersion,
      acfsManifestVersion: manifest.version,
    },
  });
}

function targetMatches(plugin: PluginPackage, target: PluginValidationTarget): boolean {
  return plugin.targets.some((candidate) => {
    return (
      candidate.os === target.os &&
      candidate.versions.includes(target.version) &&
      candidate.arch.includes(target.arch) &&
      candidate.libc.includes(target.libc)
    );
  });
}

function declaredCapabilitySet(plugin: PluginPackage): Set<string> {
  return new Set([
    ...plugin.capabilities.allowed,
    ...plugin.capabilities.reviewRequired,
    ...plugin.capabilities.disallowed,
  ]);
}

function validateCapabilityUse(
  plugin: PluginPackage,
  module: PluginModule,
  capability: string,
  diagnostics: PluginDiagnostic[],
  path: string
): void {
  const declared = declaredCapabilitySet(plugin);
  if (!declared.has(capability)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_capability_undeclared',
      message: `Plugin module "${module.id}" uses undeclared capability "${capability}"`,
      path,
      severity: 'error',
      moduleId: module.id,
      context: { capability },
    });
    return;
  }

  if (plugin.capabilities.disallowed.includes(capability)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_disallowed_behavior',
      message: `Plugin module "${module.id}" requested disallowed capability "${capability}"`,
      path,
      severity: 'error',
      moduleId: module.id,
      context: { capability },
    });
    return;
  }

  if (
    INTRINSICALLY_REVIEW_REQUIRED_CAPABILITIES.has(capability) ||
    plugin.capabilities.reviewRequired.includes(capability)
  ) {
    addDiagnostic(diagnostics, {
      code: 'plugin_review_required',
      message: `Plugin module "${module.id}" requires maintainer review for "${capability}"`,
      path,
      severity: 'review_required',
      moduleId: module.id,
      context: { capability },
    });
  }
}

function scanDisallowedInstallFields(
  value: unknown,
  path: string,
  moduleId: string,
  diagnostics: PluginDiagnostic[]
): void {
  const pending: Array<{ value: unknown; path: string }> = [{ value, path }];
  const seen = new WeakSet<object>();

  while (pending.length > 0) {
    const candidate = pending.pop()!;
    if (Array.isArray(candidate.value)) {
      if (seen.has(candidate.value)) continue;
      seen.add(candidate.value);
      candidate.value.forEach((child, index) => {
        pending.push({ value: child, path: `${candidate.path}[${index}]` });
      });
      continue;
    }
    if (!isRecord(candidate.value)) continue;
    if (seen.has(candidate.value)) continue;
    seen.add(candidate.value);

    for (const [key, child] of Object.entries(candidate.value)) {
      const childPath = `${candidate.path}.${key}`;
      if (DISALLOWED_INSTALL_FIELDS.has(key)) {
        addDiagnostic(diagnostics, {
          code: 'plugin_disallowed_behavior',
          message: `Plugin module "${moduleId}" uses forbidden executable install field "${key}"`,
          path: childPath,
          severity: 'error',
          moduleId,
          context: { field: key },
        });
      }
      pending.push({ value: child, path: childPath });
    }
  }
}

function validateInstallFields(
  plugin: PluginPackage,
  module: PluginModule,
  moduleIndex: number,
  installers: Record<string, InstallerChecksumEntry>,
  diagnostics: PluginDiagnostic[]
): void {
  const install = module.install as Record<string, unknown>;
  const path = `modules[${moduleIndex}].install`;
  const kind = module.install.kind;

  scanDisallowedInstallFields(install, path, module.id, diagnostics);

  if (!ALLOWED_INSTALL_KINDS.has(kind)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_disallowed_behavior',
      message: `Plugin module "${module.id}" uses unsupported install kind "${kind}"`,
      path: `${path}.kind`,
      severity: 'error',
      moduleId: module.id,
      context: { kind },
    });
    return;
  }

  validateCapabilityUse(plugin, module, kind, diagnostics, `${path}.kind`);

  if (!IMPLEMENTED_INSTALL_KINDS.has(kind)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_disallowed_behavior',
      message: `Plugin module "${module.id}" uses install kind "${kind}", whose executor is not implemented`,
      path: `${path}.kind`,
      severity: 'error',
      moduleId: module.id,
      context: { kind },
    });
  }

  switch (kind) {
    case 'verified_installer':
      validateVerifiedInstallerInstall(module, moduleIndex, installers, diagnostics);
      return;
    case 'release_artifact':
      validateReleaseArtifactInstall(module, moduleIndex, diagnostics);
      return;
    case 'copy_asset':
      validateCopyAssetInstall(module, moduleIndex, diagnostics);
      return;
    case 'manual_step':
      validateManualStepInstall(module, moduleIndex, diagnostics);
      return;
  }
}

function validateVerifiedInstallerInstall(
  module: PluginModule,
  moduleIndex: number,
  installers: Record<string, InstallerChecksumEntry>,
  diagnostics: PluginDiagnostic[]
): void {
  const install = module.install as Record<string, unknown>;
  const path = `modules[${moduleIndex}].install`;
  const tool = stringField(install, 'tool');
  const url = stringField(install, 'url');
  const runner = stringField(install, 'runner');
  const env = install.env;
  const args = install.args;

  if (!tool || !VERIFIED_INSTALLER_TOOL_PATTERN.test(tool)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_missing_required_field',
      message: `Plugin module "${module.id}" verified installer tool must be a lowercase checksum key`,
      path: `${path}.tool`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (!isHttpsUrl(url)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_disallowed_behavior',
      message: `Plugin module "${module.id}" verified installer URL must use https://`,
      path: `${path}.url`,
      severity: 'error',
      moduleId: module.id,
      context: { url: url ?? '<missing>' },
    });
  }

  if (!runner || !ALLOWED_RUNNERS.has(runner)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_disallowed_behavior',
      message: `Plugin module "${module.id}" verified installer runner must be bash or sh`,
      path: `${path}.runner`,
      severity: 'error',
      moduleId: module.id,
      context: { runner: runner ?? '<missing>', allowedRunners: Array.from(ALLOWED_RUNNERS) },
    });
  }

  if (
    env !== undefined &&
    (!Array.isArray(env) ||
      !env.every((entry) => typeof entry === 'string' && ENV_ASSIGNMENT_PATTERN.test(entry)))
  ) {
    addDiagnostic(diagnostics, {
      code: 'plugin_missing_required_field',
      message: `Plugin module "${module.id}" verified installer env must contain only KEY=value strings`,
      path: `${path}.env`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (Array.isArray(env) && env.length > 0) {
    addDiagnostic(diagnostics, {
      code: 'plugin_disallowed_behavior',
      message: `Plugin module "${module.id}" cannot set verified installer environment variables in v1`,
      path: `${path}.env`,
      severity: 'error',
      moduleId: module.id,
      context: { reason: 'shell startup environment can bypass the verified installer file' },
    });
  }

  if (
    args !== undefined &&
    (!Array.isArray(args) || !args.every((entry) => typeof entry === 'string'))
  ) {
    addDiagnostic(diagnostics, {
      code: 'plugin_missing_required_field',
      message: `Plugin module "${module.id}" verified installer args must be an array of strings`,
      path: `${path}.args`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (
    Array.isArray(args) &&
    args.every((entry) => typeof entry === 'string') &&
    args.includes('--')
  ) {
    addDiagnostic(diagnostics, {
      code: 'plugin_disallowed_behavior',
      message: `Plugin module "${module.id}" cannot pass runner options to a verified installer`,
      path: `${path}.args`,
      severity: 'error',
      moduleId: module.id,
      context: { reason: 'plugin arguments must be passed only after the verified installer file' },
    });
  }

  if (install.fallback_url !== undefined) {
    addDiagnostic(diagnostics, {
      code: 'plugin_disallowed_behavior',
      message: `Plugin module "${module.id}" cannot use verified_installer.fallback_url`,
      path: `${path}.fallback_url`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (!tool || !url) return;

  const entry = installers[tool];
  if (!entry?.url || !entry?.sha256) {
    addDiagnostic(diagnostics, {
      code: 'plugin_verified_installer_checksum_required',
      message: `checksums.yaml is missing a complete installer entry for "${tool}"`,
      path,
      severity: 'error',
      moduleId: module.id,
      context: { tool, hasUrl: Boolean(entry?.url), hasSha256: Boolean(entry?.sha256) },
    });
    return;
  }

  if (!SHA256_HEX_PATTERN.test(entry.sha256)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_verified_installer_checksum_required',
      message: `checksums.yaml has an invalid sha256 for "${tool}"`,
      path,
      severity: 'error',
      moduleId: module.id,
      context: { tool, sha256: entry.sha256 },
    });
    return;
  }

  if (entry.url !== url) {
    addDiagnostic(diagnostics, {
      code: 'plugin_verified_installer_checksum_required',
      message: `Plugin module "${module.id}" verified installer URL does not match checksums.yaml`,
      path: `${path}.url`,
      severity: 'error',
      moduleId: module.id,
      context: { tool, manifestUrl: url, checksumsUrl: entry.url },
    });
  }
}

function validateReleaseArtifactInstall(
  module: PluginModule,
  moduleIndex: number,
  diagnostics: PluginDiagnostic[]
): void {
  const install = module.install as Record<string, unknown>;
  const path = `modules[${moduleIndex}].install`;
  const url = stringField(install, 'url');
  const sha256 = stringField(install, 'sha256');
  const assetId = stringField(install, 'assetId');
  const targetPath = stringField(install, 'targetPath');
  const mode = stringField(install, 'mode');

  if (!isHttpsUrl(url)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_disallowed_behavior',
      message: `Plugin module "${module.id}" release artifact URL must use https://`,
      path: `${path}.url`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (!sha256 || !SHA256_HEX_PATTERN.test(sha256)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_artifact_hash_required',
      message: `Plugin module "${module.id}" release artifact requires a valid sha256`,
      path: `${path}.sha256`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (!assetId?.trim()) {
    addDiagnostic(diagnostics, {
      code: 'plugin_missing_required_field',
      message: `Plugin module "${module.id}" release artifact requires assetId`,
      path: `${path}.assetId`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (!isSafeRelativePath(targetPath)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_archive_layout_invalid',
      message: `Plugin module "${module.id}" release artifact targetPath must stay relative`,
      path: `${path}.targetPath`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (!mode?.trim()) {
    addDiagnostic(diagnostics, {
      code: 'plugin_missing_required_field',
      message: `Plugin module "${module.id}" release artifact requires mode`,
      path: `${path}.mode`,
      severity: 'error',
      moduleId: module.id,
    });
  }
}

function validateCopyAssetInstall(
  module: PluginModule,
  moduleIndex: number,
  diagnostics: PluginDiagnostic[]
): void {
  const install = module.install as Record<string, unknown>;
  const path = `modules[${moduleIndex}].install`;
  const assetId = stringField(install, 'assetId');
  const sourcePath = stringField(install, 'sourcePath');
  const targetPath = stringField(install, 'targetPath');
  const mode = stringField(install, 'mode');

  if (!assetId?.trim()) {
    addDiagnostic(diagnostics, {
      code: 'plugin_missing_required_field',
      message: `Plugin module "${module.id}" copy_asset requires assetId`,
      path: `${path}.assetId`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (!isSafeRelativePath(sourcePath)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_archive_layout_invalid',
      message: `Plugin module "${module.id}" copy_asset sourcePath must stay relative`,
      path: `${path}.sourcePath`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (!isSafeRelativePath(targetPath)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_archive_layout_invalid',
      message: `Plugin module "${module.id}" copy_asset targetPath must stay relative`,
      path: `${path}.targetPath`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (!mode?.trim()) {
    addDiagnostic(diagnostics, {
      code: 'plugin_missing_required_field',
      message: `Plugin module "${module.id}" copy_asset requires mode`,
      path: `${path}.mode`,
      severity: 'error',
      moduleId: module.id,
    });
  }
}

function validateManualStepInstall(
  module: PluginModule,
  moduleIndex: number,
  diagnostics: PluginDiagnostic[]
): void {
  const install = module.install as Record<string, unknown>;
  const path = `modules[${moduleIndex}].install`;
  const summary = stringField(install, 'summary');
  const docsUrl = stringField(install, 'docs_url');
  const blocking = install.blocking;

  if (!summary) {
    addDiagnostic(diagnostics, {
      code: 'plugin_missing_required_field',
      message: `Plugin module "${module.id}" manual_step requires summary`,
      path: `${path}.summary`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (!isHttpsUrl(docsUrl)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_missing_required_field',
      message: `Plugin module "${module.id}" manual_step requires docs_url`,
      path: `${path}.docs_url`,
      severity: 'error',
      moduleId: module.id,
    });
  }

  if (typeof blocking !== 'boolean') {
    addDiagnostic(diagnostics, {
      code: 'plugin_missing_required_field',
      message: `Plugin module "${module.id}" manual_step requires boolean blocking`,
      path: `${path}.blocking`,
      severity: 'error',
      moduleId: module.id,
    });
  }
}

function validateModuleIds(
  plugin: PluginPackage,
  options: PluginValidationOptions,
  diagnostics: PluginDiagnostic[]
): void {
  const slug = packageSlug(plugin.packageId);
  const seen = new Set<string>();
  const firstPartyIds = new Set(options.firstPartyManifest.modules.map((module) => module.id));
  const existingPluginIds = new Set(options.existingPluginModuleIds ?? []);

  plugin.modules.forEach((module, index) => {
    const path = `modules[${index}].id`;
    const match = MODULE_ID_PATTERN.exec(module.id);
    if (!match || match[1] !== slug) {
      addDiagnostic(diagnostics, {
        code: 'plugin_module_id_invalid',
        message: `Plugin module "${module.id}" must use the plugin.${slug}. namespace`,
        path,
        severity: 'error',
        moduleId: module.id,
        context: { expectedPrefix: `plugin.${slug}.` },
      });
    }

    if (seen.has(module.id) || firstPartyIds.has(module.id) || existingPluginIds.has(module.id)) {
      addDiagnostic(diagnostics, {
        code: 'plugin_module_collision',
        message: `Plugin module "${module.id}" collides with an existing module ID`,
        path,
        severity: 'error',
        moduleId: module.id,
      });
    }
    seen.add(module.id);
  });
}

function validateCategories(plugin: PluginPackage, diagnostics: PluginDiagnostic[]): void {
  plugin.modules.forEach((module, index) => {
    if (!isValidCategory(module.category)) {
      addDiagnostic(diagnostics, {
        code: 'plugin_missing_required_field',
        message: `Plugin module "${module.id}" category "${module.category}" is not a known ACFS category`,
        path: `modules[${index}].category`,
        severity: 'error',
        moduleId: module.id,
        context: { allowedCategories: Array.from(ALLOWED_CATEGORIES).sort() },
      });
    }
  });
}

function validateDependencies(
  plugin: PluginPackage,
  options: PluginValidationOptions,
  diagnostics: PluginDiagnostic[]
): void {
  const firstParty = new Map(options.firstPartyManifest.modules.map((module) => [module.id, module]));
  const own = new Map(plugin.modules.map((module) => [module.id, module]));
  const existingPluginIds = new Set(options.existingPluginModuleIds ?? []);

  plugin.modules.forEach((module, moduleIndex) => {
    for (const dependencyId of module.dependencies ?? []) {
      const path = `modules[${moduleIndex}].dependencies`;
      if (own.has(dependencyId) || firstParty.has(dependencyId)) {
        validateDependencyPhase(module, dependencyId, firstParty, own, diagnostics, path);
        continue;
      }

      if (dependencyId.startsWith('plugin.') && existingPluginIds.has(dependencyId)) {
        validateCapabilityUse(plugin, module, 'cross_plugin_dependency', diagnostics, path);
        continue;
      }

      addDiagnostic(diagnostics, {
        code: 'plugin_dependency_invalid',
        message: `Plugin module "${module.id}" depends on missing module "${dependencyId}"`,
        path,
        severity: 'error',
        moduleId: module.id,
        context: { missingDependency: dependencyId },
      });
    }
  });

  detectPluginDependencyCycles(plugin, diagnostics);
}

function validateDependencyPhase(
  module: PluginModule,
  dependencyId: string,
  firstParty: Map<string, Module>,
  own: Map<string, PluginModule>,
  diagnostics: PluginDiagnostic[],
  path: string
): void {
  const dependency = firstParty.get(dependencyId) ?? own.get(dependencyId);
  const dependencyPhase = dependency?.phase ?? 1;
  if (dependencyPhase > module.phase) {
    addDiagnostic(diagnostics, {
      code: 'plugin_dependency_invalid',
      message: `Plugin module "${module.id}" depends on "${dependencyId}" in a later phase`,
      path,
      severity: 'error',
      moduleId: module.id,
      context: { dependencyId, modulePhase: module.phase, dependencyPhase },
    });
  }
}

function detectPluginDependencyCycles(
  plugin: PluginPackage,
  diagnostics: PluginDiagnostic[]
): void {
  const own = new Map(plugin.modules.map((module) => [module.id, module]));
  const visiting = new Set<string>();
  const visited = new Set<string>();
  const reported = new Set<string>();

  function visit(moduleId: string, path: string[]): void {
    if (visiting.has(moduleId)) {
      const cycleStart = path.indexOf(moduleId);
      const cyclePath = [...path.slice(cycleStart), moduleId];
      const cycleKey = [...new Set(cyclePath)].sort().join(',');
      if (!reported.has(cycleKey)) {
        reported.add(cycleKey);
        addDiagnostic(diagnostics, {
          code: 'plugin_dependency_invalid',
          message: `Plugin dependency cycle detected: ${cyclePath.join(' -> ')}`,
          path: 'modules.dependencies',
          severity: 'error',
          moduleId,
          context: { cyclePath },
        });
      }
      return;
    }

    if (visited.has(moduleId)) return;

    const module = own.get(moduleId);
    if (!module) return;

    visiting.add(moduleId);
    for (const dependencyId of module.dependencies ?? []) {
      if (own.has(dependencyId)) {
        visit(dependencyId, [...path, moduleId]);
      }
    }
    visiting.delete(moduleId);
    visited.add(moduleId);
  }

  for (const module of plugin.modules) {
    visit(module.id, []);
  }
}

function validateGeneratedFunctionCollisions(
  plugin: PluginPackage,
  options: PluginValidationOptions,
  diagnostics: PluginDiagnostic[]
): void {
  const functionOwners = new Map<string, string>();

  for (const module of options.firstPartyManifest.modules) {
    if (module.generated === false) {
      continue;
    }
    functionOwners.set(toGeneratedFunctionName(module.id), module.id);
  }
  for (const moduleId of options.existingPluginModuleIds ?? []) {
    const functionName = toGeneratedFunctionName(moduleId);
    if (!functionOwners.has(functionName)) {
      functionOwners.set(functionName, moduleId);
    }
  }

  plugin.modules.forEach((module, index) => {
    if (module.install.kind !== 'verified_installer') {
      return;
    }
    const functionName = toGeneratedFunctionName(module.id);
    const existingOwner = functionOwners.get(functionName);
    if (existingOwner) {
      addDiagnostic(diagnostics, {
        code: 'plugin_generated_function_collision',
        message: `Plugin module "${module.id}" generates function "${functionName}" which collides with "${existingOwner}"`,
        path: `modules[${index}].id`,
        severity: 'error',
        moduleId: module.id,
        context: { functionName, collidingModule: existingOwner },
      });
    }
    functionOwners.set(functionName, module.id);
  });
}

function validateReviewRequiredCapabilities(
  plugin: PluginPackage,
  diagnostics: PluginDiagnostic[]
): void {
  plugin.modules.forEach((module, index) => {
    if (module.run_as === 'root' || module.run_as === 'current') {
      validateCapabilityUse(plugin, module, 'root_run_as', diagnostics, `modules[${index}].run_as`);
    }
  });
}

function validateTarget(
  plugin: PluginPackage,
  target: PluginValidationTarget | undefined,
  diagnostics: PluginDiagnostic[]
): void {
  if (!target) {
    addDiagnostic(diagnostics, {
      code: 'plugin_target_unsupported',
      message: 'Plugin validation requires an explicit target OS, version, architecture, and libc',
      path: '<validation-target>',
      severity: 'error',
    });
    return;
  }
  if (targetMatches(plugin, target)) return;

  addDiagnostic(diagnostics, {
    code: 'plugin_target_unsupported',
    message: `Plugin package "${plugin.packageId}" does not support ${target.os} ${target.version} ${target.arch} ${target.libc}`,
    path: 'targets',
    severity: 'error',
    context: { ...target },
  });
}

function validateOfflinePolicy(plugin: PluginPackage, diagnostics: PluginDiagnostic[]): void {
  if (plugin.offline.bundlingPolicy === 'bundled') return;

  for (const module of plugin.modules) {
    if (!module.optional && plugin.offline.bundlingPolicy === 'prohibited') {
      addDiagnostic(diagnostics, {
        code: 'plugin_offline_policy_incompatible',
        message: `Required plugin module "${module.id}" cannot be fully offline when bundling is prohibited`,
        path: 'offline.bundlingPolicy',
        severity: 'error',
        moduleId: module.id,
      });
    }
  }
}

function validateModules(
  plugin: PluginPackage,
  options: PluginValidationOptions,
  diagnostics: PluginDiagnostic[]
): void {
  const installers = options.installers ?? {};

  validateModuleIds(plugin, options, diagnostics);
  validateCategories(plugin, diagnostics);
  validateDependencies(plugin, options, diagnostics);
  validateGeneratedFunctionCollisions(plugin, options, diagnostics);
  validateReviewRequiredCapabilities(plugin, diagnostics);

  plugin.modules.forEach((module, index) => {
    validateCapabilityUse(plugin, module, 'doctor_check', diagnostics, `modules[${index}].verify`);
    if (module.web !== undefined) {
      validateCapabilityUse(plugin, module, 'web_metadata', diagnostics, `modules[${index}].web`);
    }
    validateInstallFields(plugin, module, index, installers, diagnostics);
  });
}

function toManifestModule(
  plugin: PluginPackage,
  module: PluginModule,
  packageSha256: string
): Module {
  if (!isValidCategory(module.category)) {
    throw new Error(
      `Plugin module "${module.id}" has invalid category "${module.category}" after validation`
    );
  }
  const install = module.install as Record<string, unknown>;
  const kind = module.install.kind;
  const verifiedInstaller =
    kind === 'verified_installer'
      ? {
          tool: stringField(install, 'tool') ?? '',
          url: stringField(install, 'url'),
          runner: (stringField(install, 'runner') ?? 'bash') as 'bash' | 'sh',
          env: stringArrayField(install, 'env') ?? [],
          args: stringArrayField(install, 'args') ?? [],
        }
      : undefined;

  return {
    id: module.id,
    description: module.description,
    category: module.category,
    run_as: module.run_as as RunAs,
    verified_installer: verifiedInstaller,
    optional: module.optional,
    enabled_by_default: module.enabled_by_default,
    generated: kind === 'verified_installer',
    phase: module.phase,
    install: [],
    verify: module.verify.map(
      (check) => `command -v -- ${check.command} >/dev/null 2>&1`
    ),
    dependencies: module.dependencies ? [...module.dependencies] : undefined,
    docs_url: module.docs_url,
    web: module.web,
    plugin: {
      packageId: plugin.packageId,
      version: plugin.version,
      pluginSha256: packageSha256.toLowerCase(),
      sourceRef: plugin.provenance.sourceRef,
      sourceCommit: plugin.provenance.sourceCommit,
    },
  };
}

export function validatePluginPackage(
  input: unknown,
  options: PluginValidationOptions
): PluginValidationResult {
  const diagnostics: PluginDiagnostic[] = [];
  const manifestModules: Module[] = [];
  // An arbitrary Iterable may be a one-shot generator. Snapshot it once so ID,
  // dependency, and generated-function checks all see the same loaded plugins.
  const validationOptions: PluginValidationOptions = {
    ...options,
    existingPluginModuleIds: [...(options.existingPluginModuleIds ?? [])],
  };

  if (!inspectPluginInputStructure(input, diagnostics)) {
    return { valid: false, diagnostics, manifestModules };
  }

  validateTopLevelFields(input, diagnostics);
  scanSecretMaterial(input, diagnostics, '');

  if (!isRecord(input)) {
    addDiagnostic(diagnostics, {
      code: 'plugin_missing_required_field',
      message: 'Plugin package must be a JSON object',
      path: '<root>',
      severity: 'error',
    });
    return { valid: false, diagnostics, manifestModules };
  }

  const plugin = addSchemaDiagnostics(input, diagnostics);
  if (!plugin) {
    return { valid: false, diagnostics, manifestModules };
  }

  validatePackageHash(validationOptions, diagnostics);
  validateProvenance(plugin, validationOptions.firstPartyManifest, diagnostics);
  validateTarget(plugin, validationOptions.target, diagnostics);
  validateModules(plugin, validationOptions, diagnostics);
  validateOfflinePolicy(plugin, diagnostics);

  const valid = diagnostics.every((diagnostic) => diagnostic.severity === 'warning');
  if (valid) {
    manifestModules.push(
      ...plugin.modules.map((module) =>
        toManifestModule(plugin, module, validationOptions.packageSha256!)
      )
    );
  }

  return {
    valid,
    diagnostics,
    // Invalid packages may contain the exact secret material or host-specific
    // values that produced a refusal. Do not hand the parsed payload back to a
    // caller that might serialize the validation result or retain it in logs.
    package: valid ? plugin : undefined,
    manifestModules,
  };
}

export function formatPluginDiagnostics(result: PluginValidationResult): string {
  if (result.valid) {
    return 'Plugin validation passed';
  }

  const lines = ['Plugin validation failed:', ''];
  for (const diagnostic of result.diagnostics) {
    const moduleLabel = diagnostic.moduleId ? ` ${diagnostic.moduleId}` : '';
    lines.push(
      `  [${diagnostic.code}]${moduleLabel} ${diagnostic.path}: ${diagnostic.message}`
    );
  }
  lines.push('');
  lines.push(`Total: ${result.diagnostics.length} diagnostic(s)`);
  return lines.join('\n');
}

/**
 * Safely read and validate an already-extracted plugin manifest from disk.
 * The caller remains responsible for calculating the compressed package hash
 * and supplying both that value and its independently trusted expected digest.
 */
export function loadPluginManifestFromFile(
  filePath: string,
  options: PluginValidationOptions
): PluginValidationResult {
  if (!filePath.endsWith('.json')) {
    return {
      valid: false,
      diagnostics: [
        {
          code: 'plugin_archive_layout_invalid',
          message: 'Plugin manifests must use the JSON-only .json format',
          path: '<file>',
          severity: 'error',
        },
      ],
      manifestModules: [],
    };
  }

  let fd: number | undefined;
  let fileBytes: Buffer;
  try {
    fd = openSync(filePath, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.nlink !== 1) {
      return {
        valid: false,
        diagnostics: [
          {
            code: 'plugin_missing_required_field',
            message: 'Plugin manifest is not a single-link regular file',
            path: '<file>',
            severity: 'error',
          },
        ],
        manifestModules: [],
      };
    }
    if (stat.size > MAX_PLUGIN_MANIFEST_BYTES) {
      return {
        valid: false,
        diagnostics: [
          {
            code: 'plugin_disallowed_behavior',
            message: 'Plugin manifest exceeds the maximum accepted byte size',
            path: '<file>',
            severity: 'error',
            context: {
              sizeBytes: stat.size,
              maximumBytes: MAX_PLUGIN_MANIFEST_BYTES,
            },
          },
        ],
        manifestModules: [],
      };
    }

    // Bound the read itself as well as the pre-read metadata check. A regular
    // file can grow after fstat(), so read at most one byte beyond the limit
    // and fail closed if that sentinel byte exists.
    const boundedBuffer = Buffer.alloc(MAX_PLUGIN_MANIFEST_BYTES + 1);
    let bytesRead = 0;
    while (bytesRead < boundedBuffer.length) {
      const count = readSync(
        fd,
        boundedBuffer,
        bytesRead,
        boundedBuffer.length - bytesRead,
        null
      );
      if (count === 0) break;
      bytesRead += count;
    }
    if (bytesRead > MAX_PLUGIN_MANIFEST_BYTES) {
      return {
        valid: false,
        diagnostics: [
          {
            code: 'plugin_disallowed_behavior',
            message: 'Plugin manifest exceeds the maximum accepted byte size',
            path: '<file>',
            severity: 'error',
            context: {
              sizeBytes: bytesRead,
              maximumBytes: MAX_PLUGIN_MANIFEST_BYTES,
            },
          },
        ],
        manifestModules: [],
      };
    }
    fileBytes = boundedBuffer.subarray(0, bytesRead);
  } catch {
    return {
      valid: false,
      diagnostics: [
        {
          code: 'plugin_missing_required_field',
          message: 'Plugin manifest could not be opened safely',
          path: '<file>',
          severity: 'error',
        },
      ],
      manifestModules: [],
    };
  } finally {
    if (fd !== undefined) closeSync(fd);
  }

  let text: string;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(fileBytes);
  } catch {
    return {
      valid: false,
      diagnostics: [
        {
          code: 'plugin_disallowed_behavior',
          message: 'Plugin manifest must contain valid UTF-8 JSON bytes',
          path: '<root>',
          severity: 'error',
        },
      ],
      manifestModules: [],
    };
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return {
      valid: false,
      diagnostics: [
        {
          code: 'plugin_missing_required_field',
          message: 'Plugin manifest contains invalid JSON syntax',
          path: '<root>',
          severity: 'error',
        },
      ],
      manifestModules: [],
    };
  }

  const structureInspection = inspectJsonManifestStructure(text);
  if (structureInspection) {
    return {
      valid: false,
      diagnostics: [
        {
          code: 'plugin_disallowed_behavior',
          message:
            structureInspection === 'duplicate_key'
              ? 'Plugin manifest contains ambiguous duplicate object keys'
              : `Plugin manifest exceeds the maximum JSON nesting depth of ${MAX_PLUGIN_JSON_NESTING_DEPTH}`,
          path: '<root>',
          severity: 'error',
        },
      ],
      manifestModules: [],
    };
  }

  return validatePluginPackage(parsed, options);
}

/**
 * Merges validated plugin modules into a first-party manifest.
 * Throws an Error if any plugin result is invalid.
 */
export function mergeValidatedPlugins(
  firstPartyManifest: Manifest,
  pluginResults: readonly PluginValidationResult[]
): Manifest {
  const allModules = [...firstPartyManifest.modules];

  for (const result of pluginResults) {
    if (!result.valid) {
      throw new Error(`Cannot merge invalid plugin: ${formatPluginDiagnostics(result)}`);
    }
    allModules.push(...result.manifestModules);
  }

  return {
    ...firstPartyManifest,
    modules: allModules,
  };
}
