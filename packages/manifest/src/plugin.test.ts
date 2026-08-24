import { describe, expect, test } from 'bun:test';
import { mkdtempSync, readFileSync, truncateSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import {
  formatPluginDiagnostics,
  loadPluginManifestFromFile,
  MAX_PLUGIN_JSON_NESTING_DEPTH,
  MAX_PLUGIN_JSON_NODES,
  MAX_PLUGIN_MANIFEST_BYTES,
  mergeValidatedPlugins,
  validatePluginPackage,
  type PluginValidationOptions,
} from './plugin.js';
import {
  generateCategoryScript,
  generateDoctorChecks,
  generateManifestIndex,
  generateWebModules,
  generateWebTools,
  generateWebCommands,
  collectPluginInputPaths,
  enforcePluginActivationBoundary,
  PLUGIN_ACTIVATION_UNAVAILABLE_MESSAGE,
} from './generate.js';
import { ModuleSchema } from './schema.js';
import type { Manifest } from './types.js';

const CHECKSUM = 'a'.repeat(64);
const INSTALLER_URL = 'https://example.com/install.sh';

function firstPartyManifest(): Manifest {
  return {
    version: 1,
    name: 'ACFS Test Manifest',
    id: 'acfs',
    defaults: {
      user: 'ubuntu',
      workspace_root: '/data/projects',
      mode: 'vibe',
    },
    modules: [
      {
        id: 'base.system',
        description: 'Base system',
        category: 'base',
        phase: 1,
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
        install: ['echo base'],
        verify: ['true'],
      },
      {
        id: 'lang.bun',
        description: 'Bun runtime',
        category: 'lang',
        phase: 6,
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        generated: true,
        install: ['echo bun'],
        verify: ['bun --version'],
      },
    ],
  };
}

function validationOptions(overrides: Partial<PluginValidationOptions> = {}): PluginValidationOptions {
  return {
    firstPartyManifest: firstPartyManifest(),
    installers: {
      example_tools: {
        url: INSTALLER_URL,
        sha256: CHECKSUM,
      },
    },
    target: {
      os: 'ubuntu',
      version: '25.10',
      arch: 'x86_64',
      libc: 'glibc',
    },
    packageSha256: CHECKSUM,
    expectedPackageSha256: CHECKSUM,
    ...overrides,
  };
}

function validPlugin(): Record<string, unknown> {
  return {
    schema: 'acfs.plugin-package.v1',
    schemaVersion: 1,
    packageId: 'example.tools',
    displayName: 'Example Tools',
    version: '1.2.3',
    description: 'Installable ACFS modules for Example Tools.',
    publisher: {
      name: 'Example Maintainers',
      contactUrl: 'https://example.com/security',
      sourceUrl: 'https://github.com/example/acfs-plugin-example',
    },
    license: 'Apache-2.0',
    docsUrl: 'https://example.com/acfs-plugin-example',
    provenance: {
      generatedAt: '2026-05-08T00:00:00Z',
      sourceRef: 'main',
      sourceCommit: '0123456789abcdef0123456789abcdef01234567',
      acfsManifestVersion: 1,
    },
    targets: [
      {
        os: 'ubuntu',
        versions: ['25.10'],
        arch: ['x86_64'],
        libc: ['glibc'],
      },
    ],
    capabilities: {
      allowed: ['verified_installer', 'doctor_check'],
      reviewRequired: ['root_run_as', 'cross_plugin_dependency'],
      disallowed: ['arbitrary_shell', 'secret_values'],
    },
    modules: [
      {
        id: 'plugin.example_tools.cli',
        description: 'Example command-line tool.',
        category: 'tools',
        phase: 6,
        run_as: 'target_user',
        optional: false,
        enabled_by_default: true,
        dependencies: ['lang.bun'],
        install: {
          kind: 'verified_installer',
          tool: 'example_tools',
          url: INSTALLER_URL,
          runner: 'bash',
          args: [],
          env: [],
        },
        verify: [{ kind: 'command_exists', command: 'example' }],
        docs_url: 'https://example.com/acfs-plugin-example/cli',
      },
    ],
    offline: {
      bundlingPolicy: 'metadata_only',
      liveAuthRequired: false,
      providerInteractionRequired: false,
    },
    extensions: {},
  };
}

function diagnosticCodes(plugin: Record<string, unknown>, options = validationOptions()): string[] {
  return validatePluginPackage(plugin, options).diagnostics.map((diagnostic) => diagnostic.code);
}

describe('validatePluginPackage', () => {
  test('accepts a valid verified-installer plugin and returns normalized modules', () => {
    const result = validatePluginPackage(validPlugin(), validationOptions());

    expect(result.valid).toBe(true);
    expect(result.diagnostics).toHaveLength(0);
    expect(result.manifestModules).toHaveLength(1);
    expect(result.manifestModules[0].id).toBe('plugin.example_tools.cli');
    expect(result.manifestModules[0].verified_installer?.tool).toBe('example_tools');
    expect(result.manifestModules[0].verified_installer?.url).toBe(INSTALLER_URL);
    expect(result.manifestModules[0].verify).toEqual([
      'command -v -- example >/dev/null 2>&1',
    ]);
    expect(result.manifestModules[0].plugin).toEqual({
      packageId: 'example.tools',
      version: '1.2.3',
      pluginSha256: CHECKSUM,
      sourceRef: 'main',
      sourceCommit: '0123456789abcdef0123456789abcdef01234567',
    });
    expect(ModuleSchema.safeParse(result.manifestModules[0]).success).toBe(true);
  });

  test('rejects unsupported schema versions', () => {
    const plugin = validPlugin();
    plugin.schemaVersion = 99;

    expect(diagnosticCodes(plugin)).toContain('plugin_schema_unsupported');
  });

  test('rejects packages authored for a different ACFS manifest version', () => {
    const plugin = validPlugin();
    const provenance = plugin.provenance as Record<string, unknown>;
    provenance.acfsManifestVersion = 2;

    expect(validatePluginPackage(plugin, validationOptions()).diagnostics).toContainEqual(
      expect.objectContaining({
        code: 'plugin_schema_unsupported',
        path: 'provenance.acfsManifestVersion',
      })
    );
  });

  test('rejects malformed provenance timestamps', () => {
    const plugin = validPlugin();
    const provenance = plugin.provenance as Record<string, unknown>;
    provenance.generatedAt = '2026-05-08 00:00:00';

    expect(validatePluginPackage(plugin, validationOptions()).diagnostics).toContainEqual(
      expect.objectContaining({
        code: 'plugin_missing_required_field',
        path: 'provenance.generatedAt',
      })
    );
  });

  test('rejects non-HTTPS plugin documentation URLs before web normalization', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = { ...modules[0], docs_url: 'javascript:alert(1)' };

    const result = validatePluginPackage(plugin, validationOptions());
    expect(result.valid).toBe(false);
    expect(result.manifestModules).toHaveLength(0);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_missing_required_field',
      path: 'modules[0].docs_url',
    }));
  });

  test('rejects non-HTTPS external plugin web links', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      web: { href: 'http://example.com/plugin' },
    };

    const result = validatePluginPackage(plugin, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_missing_required_field',
      path: 'modules[0].web.href',
    }));
  });

  test('rejects scheme-relative plugin web links', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      web: { href: '//attacker' },
    };

    const result = validatePluginPackage(plugin, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_missing_required_field',
      path: 'modules[0].web.href',
    }));
  });

  test('rejects a package when no independently trusted archive hash is supplied', () => {
    const result = validatePluginPackage(
      validPlugin(),
      validationOptions({ expectedPackageSha256: undefined })
    );

    expect(result.valid).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_package_hash_mismatch',
      path: '<package>',
      context: expect.objectContaining({ expectedPackageSha256Prefix: '<missing>' }),
    }));
    expect(result.manifestModules).toHaveLength(0);
  });

  test('rejects an archive hash mismatch without exposing full hashes', () => {
    const actualHash = 'b'.repeat(64);
    const result = validatePluginPackage(
      validPlugin(),
      validationOptions({ packageSha256: actualHash })
    );

    expect(result.valid).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_package_hash_mismatch',
      context: {
        packageSha256Prefix: actualHash.slice(0, 12),
        expectedPackageSha256Prefix: CHECKSUM.slice(0, 12),
      },
    }));
    expect(formatPluginDiagnostics(result)).not.toContain(actualHash);
    expect(formatPluginDiagnostics(result)).not.toContain(CHECKSUM);
  });

  test('detects duplicate plugin module IDs', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules.push(structuredClone(modules[0]));

    expect(diagnosticCodes(plugin)).toContain('plugin_module_collision');
  });

  test('detects first-party module ID collisions', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = { ...modules[0], id: 'lang.bun' };

    const codes = diagnosticCodes(plugin);
    expect(codes).toContain('plugin_module_collision');
    expect(codes).toContain('plugin_generated_function_collision');
  });

  test('does not claim a function collision with orchestration-owned modules', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = { ...modules[0], id: 'lang.bun' };
    const manifest = firstPartyManifest();
    const bun = manifest.modules.find((module) => module.id === 'lang.bun');
    if (!bun) throw new Error('test fixture missing lang.bun');
    bun.generated = false;

    const codes = diagnosticCodes(plugin, validationOptions({ firstPartyManifest: manifest }));
    expect(codes).toContain('plugin_module_collision');
    expect(codes).not.toContain('plugin_generated_function_collision');
  });

  test('detects generated function collisions with already loaded plugins', () => {
    const result = validatePluginPackage(
      validPlugin(),
      validationOptions({ existingPluginModuleIds: ['plugin.example.tools.cli'] })
    );

    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_generated_function_collision',
      moduleId: 'plugin.example_tools.cli',
    }));
  });

  test('rejects categories outside the shared canonical category set', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = { ...modules[0], category: 'tooling' };

    expect(diagnosticCodes(plugin)).toContain('plugin_missing_required_field');
  });

  test('reuses one-shot existing plugin iterables across all validation passes', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = { ...modules[0], dependencies: ['plugin.other.dep'] };
    const existingPluginIds = (function* () {
      yield 'plugin.other.dep';
    })();

    const result = validatePluginPackage(
      plugin,
      validationOptions({ existingPluginModuleIds: existingPluginIds })
    );

    expect(result.diagnostics.some((diagnostic) =>
      diagnostic.code === 'plugin_dependency_invalid'
    )).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_review_required',
      path: 'modules[0].dependencies',
    }));
  });

  test('rejects missing verified-installer checksum entries', () => {
    const result = validatePluginPackage(
      validPlugin(),
      validationOptions({ installers: {} })
    );

    expect(result.valid).toBe(false);
    expect(result.diagnostics[0].code).toBe('plugin_verified_installer_checksum_required');
    expect(formatPluginDiagnostics(result)).toContain(
      'plugin_verified_installer_checksum_required'
    );
  });

  test('rejects verified-installer URL drift from checksums.yaml', () => {
    const result = validatePluginPackage(
      validPlugin(),
      validationOptions({
        installers: {
          example_tools: {
            url: 'https://example.com/other-install.sh',
            sha256: CHECKSUM,
          },
        },
      })
    );

    expect(result.valid).toBe(false);
    expect(result.diagnostics.some((diagnostic) => diagnostic.code === 'plugin_verified_installer_checksum_required')).toBe(true);
  });

  test('rejects unsupported verified-installer runners', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      install: {
        ...((modules[0].install as Record<string, unknown>) ?? {}),
        runner: 'python',
      },
    };

    expect(diagnosticCodes(plugin)).toContain('plugin_disallowed_behavior');
  });

  test('rejects malformed verified-installer arrays instead of silently dropping them', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      install: {
        ...((modules[0].install as Record<string, unknown>) ?? {}),
        env: [42],
        args: '--yes',
      },
    };

    const invalidPaths = validatePluginPackage(plugin, validationOptions()).diagnostics
      .filter((diagnostic) => diagnostic.code === 'plugin_missing_required_field')
      .map((diagnostic) => diagnostic.path);
    expect(invalidPaths).toContain('modules[0].install.env');
    expect(invalidPaths).toContain('modules[0].install.args');
  });

  test('rejects environment variables that could bypass the verified installer file', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      install: {
        ...((modules[0].install as Record<string, unknown>) ?? {}),
        env: ['BASH_ENV=/tmp/unreviewed-startup'],
      },
    };

    expect(validatePluginPackage(plugin, validationOptions()).diagnostics).toContainEqual(
      expect.objectContaining({
        code: 'plugin_disallowed_behavior',
        path: 'modules[0].install.env',
      })
    );
  });

  test('rejects the runner-option delimiter that can execute before the verified file', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      install: {
        ...((modules[0].install as Record<string, unknown>) ?? {}),
        args: ['-c', 'echo unverified', '--'],
      },
    };

    expect(validatePluginPackage(plugin, validationOptions()).diagnostics).toContainEqual(
      expect.objectContaining({
        code: 'plugin_disallowed_behavior',
        path: 'modules[0].install.args',
      })
    );
  });

  test('rejects raw verification shell commands', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = { ...modules[0], verify: ['example --version'] };

    expect(validatePluginPackage(plugin, validationOptions()).diagnostics).toContainEqual(
      expect.objectContaining({
        code: 'plugin_missing_required_field',
        path: 'modules[0].verify[0]',
      })
    );
  });

  test('rejects shell syntax in declarative command-existence checks', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      verify: [{ kind: 'command_exists', command: 'example;false' }],
    };

    expect(validatePluginPackage(plugin, validationOptions()).diagnostics).toContainEqual(
      expect.objectContaining({
        code: 'plugin_missing_required_field',
        path: 'modules[0].verify[0].command',
      })
    );
  });

  test('requires doctor_check capability for module verification commands', () => {
    const plugin = validPlugin();
    plugin.capabilities = {
      allowed: ['verified_installer'],
      reviewRequired: ['root_run_as', 'cross_plugin_dependency'],
      disallowed: ['arbitrary_shell', 'secret_values'],
    };

    expect(diagnosticCodes(plugin)).toContain('plugin_capability_undeclared');
  });

  test('requires web_metadata capability when a module supplies web metadata', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      web: { display_name: 'Example CLI' },
    };

    expect(diagnosticCodes(plugin)).toContain('plugin_capability_undeclared');
  });

  test('rejects dependency on missing modules', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = { ...modules[0], dependencies: ['missing.module'] };

    expect(diagnosticCodes(plugin)).toContain('plugin_dependency_invalid');
  });

  test('rejects unsupported target platforms', () => {
    const result = validatePluginPackage(
      validPlugin(),
      validationOptions({
        target: {
          os: 'ubuntu',
          version: '25.10',
          arch: 'aarch64',
          libc: 'glibc',
        },
      })
    );

    expect(result.valid).toBe(false);
    expect(result.diagnostics[0].code).toBe('plugin_target_unsupported');
  });

  test('fails closed when the validation target is omitted', () => {
    const result = validatePluginPackage(
      validPlugin(),
      validationOptions({ target: undefined })
    );

    expect(result.valid).toBe(false);
    expect(result.manifestModules).toHaveLength(0);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_target_unsupported',
      path: '<validation-target>',
    }));
  });

  test('rejects disallowed executable install fields', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      install: {
        kind: 'verified_installer',
        tool: 'example_tools',
        url: INSTALLER_URL,
        runner: 'bash',
        command: 'curl https://example.com/install.sh | bash',
      },
    };

    expect(diagnosticCodes(plugin)).toContain('plugin_disallowed_behavior');
  });

  test('rejects executable fields hidden inside nested install metadata', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      install: {
        kind: 'verified_installer',
        tool: 'example_tools',
        url: INSTALLER_URL,
        runner: 'bash',
        extensions: {
          payload: {
            command: 'ignored-but-executable-shaped',
          },
        },
      },
    };

    expect(validatePluginPackage(plugin, validationOptions()).diagnostics).toContainEqual(
      expect.objectContaining({
        code: 'plugin_disallowed_behavior',
        path: 'modules[0].install.extensions.payload.command',
      })
    );
  });

  test('rejects non-normalized plugin artifact target paths', () => {
    const plugin = validPlugin();
    plugin.capabilities = {
      allowed: ['release_artifact', 'doctor_check'],
      reviewRequired: ['root_run_as', 'cross_plugin_dependency'],
      disallowed: ['arbitrary_shell', 'secret_values'],
    };
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      install: {
        kind: 'release_artifact',
        url: 'https://example.com/tool.tar.gz',
        sha256: CHECKSUM,
        assetId: 'example-linux-x86_64',
        targetPath: 'bin/./example',
        mode: 'executable',
      },
    };

    expect(diagnosticCodes(plugin)).toContain('plugin_archive_layout_invalid');
  });

  test('refuses release artifacts until their executor is implemented', () => {
    const plugin = validPlugin();
    plugin.capabilities = {
      allowed: ['release_artifact', 'doctor_check'],
      reviewRequired: ['root_run_as', 'cross_plugin_dependency'],
      disallowed: ['arbitrary_shell', 'secret_values'],
    };
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      install: {
        kind: 'release_artifact',
        url: 'https://example.com/tool.tar.gz',
        sha256: CHECKSUM,
        assetId: 'example-linux-x86_64',
        targetPath: 'bin/example',
        mode: 'executable',
      },
    };

    const result = validatePluginPackage(plugin, validationOptions());
    expect(result.valid).toBe(false);
    expect(result.manifestModules).toHaveLength(0);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_disallowed_behavior',
      path: 'modules[0].install.kind',
      context: { kind: 'release_artifact' },
    }));
  });

  test('requires all declarative release artifact fields', () => {
    const plugin = validPlugin();
    plugin.capabilities = {
      allowed: ['release_artifact', 'doctor_check'],
      reviewRequired: ['root_run_as', 'cross_plugin_dependency'],
      disallowed: ['arbitrary_shell', 'secret_values'],
    };
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      install: {
        kind: 'release_artifact',
        url: 'https://example.com/tool.tar.gz',
        sha256: CHECKSUM,
        targetPath: 'bin/example',
      },
    };

    const missingPaths = validatePluginPackage(plugin, validationOptions()).diagnostics
      .filter((diagnostic) => diagnostic.code === 'plugin_missing_required_field')
      .map((diagnostic) => diagnostic.path);
    expect(missingPaths).toContain('modules[0].install.assetId');
    expect(missingPaths).toContain('modules[0].install.mode');
  });

  test('requires all declarative copy asset fields', () => {
    const plugin = validPlugin();
    plugin.capabilities = {
      allowed: ['copy_asset', 'doctor_check'],
      reviewRequired: ['root_run_as', 'cross_plugin_dependency'],
      disallowed: ['arbitrary_shell', 'secret_values'],
    };
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      install: {
        kind: 'copy_asset',
        sourcePath: 'assets/example',
        targetPath: 'bin/example',
      },
    };

    const missingPaths = validatePluginPackage(plugin, validationOptions()).diagnostics
      .filter((diagnostic) => diagnostic.code === 'plugin_missing_required_field')
      .map((diagnostic) => diagnostic.path);
    expect(missingPaths).toContain('modules[0].install.assetId');
    expect(missingPaths).toContain('modules[0].install.mode');
  });

  test('requires a manual step blocking decision', () => {
    const plugin = validPlugin();
    plugin.capabilities = {
      allowed: ['manual_step', 'doctor_check'],
      reviewRequired: ['root_run_as', 'cross_plugin_dependency'],
      disallowed: ['arbitrary_shell', 'secret_values'],
    };
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      install: {
        kind: 'manual_step',
        summary: 'Complete the documented setup.',
        docs_url: 'https://example.com/manual-setup',
      },
    };

    expect(validatePluginPackage(plugin, validationOptions()).diagnostics).toContainEqual(
      expect.objectContaining({
        code: 'plugin_missing_required_field',
        path: 'modules[0].install.blocking',
      })
    );
  });

  test('rejects credential-bearing fields without echoing values', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    const forbiddenKey = ['to', 'ken'].join('');
    modules[0] = { ...modules[0], [forbiddenKey]: 'redacted-fixture-value' };

    const result = validatePluginPackage(plugin, validationOptions());
    const secretDiagnostic = result.diagnostics.find(
      (diagnostic) => diagnostic.code === 'plugin_secret_material_refused'
    );

    expect(secretDiagnostic).toBeDefined();
    expect(secretDiagnostic?.context?.value).toBe('<redacted>');
    expect(result.package).toBeUndefined();
    expect(formatPluginDiagnostics(result)).not.toContain('redacted-fixture-value');
  });

  test('rejects compound credential field names instead of requiring an exact key match', () => {
    const plugin = validPlugin();
    plugin.extensions = { databasePassword: 'short-secret-value' };

    const result = validatePluginPackage(plugin, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.package).toBeUndefined();
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_secret_material_refused',
      path: 'extensions.databasePassword',
    }));
    expect(JSON.stringify(result)).not.toContain('short-secret-value');
  });

  test('rejects split multi-word credential phrases inside longer field names', () => {
    for (const credentialField of ['rotatedApiKeyValue', 'backup_private_key_path']) {
      const plugin = validPlugin();
      plugin.extensions = { [credentialField]: 'short-auth-value' };

      const result = validatePluginPackage(plugin, validationOptions());

      expect(result.valid).toBe(false);
      expect(result.package).toBeUndefined();
      expect(result.diagnostics).toContainEqual(expect.objectContaining({
        code: 'plugin_secret_material_refused',
        path: `extensions.${credentialField}`,
      }));
      expect(JSON.stringify(result)).not.toContain('short-auth-value');
    }
  });

  test('rejects and redacts credentials embedded in URL userinfo', () => {
    const plugin = validPlugin();
    plugin.extensions = {
      endpoint: 'https://alice:swordfish@example.com/plugin',
    };

    const result = validatePluginPackage(plugin, validationOptions());
    const serialized = JSON.stringify(result);

    expect(result.valid).toBe(false);
    expect(result.package).toBeUndefined();
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_secret_material_refused',
      path: 'extensions.endpoint',
    }));
    expect(serialized).not.toContain('alice');
    expect(serialized).not.toContain('swordfish');
  });

  test('rejects embedded IPv6 literals without returning the host value', () => {
    const plugin = validPlugin();
    const hostValue = ['2001', 'db8', '', '42'].join(':');
    plugin.description = `Private deployment host [${hostValue}]`;

    const result = validatePluginPackage(plugin, validationOptions());
    const serialized = JSON.stringify(result);

    expect(result.valid).toBe(false);
    expect(result.package).toBeUndefined();
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_secret_material_refused',
      path: 'description',
    }));
    expect(serialized).not.toContain(hostValue);
  });

  test('rejects representative provider token shapes beyond legacy prefixes', () => {
    const tokenValues = [
      ['github', '_pat_', 'A1'.repeat(16)].join(''),
      ['hvs', '.', 'A1'.repeat(12)].join(''),
      ['xoxb', '-', 'A1'.repeat(8)].join(''),
      ['AKIA', 'A1'.repeat(8)].join(''),
      ['AIza', 'A1'.repeat(16)].join(''),
    ];

    for (const tokenValue of tokenValues) {
      const plugin = validPlugin();
      plugin.description = `Credential ${tokenValue}`;

      const result = validatePluginPackage(plugin, validationOptions());
      expect(result.valid).toBe(false);
      expect(result.package).toBeUndefined();
      expect(result.diagnostics).toContainEqual(expect.objectContaining({
        code: 'plugin_secret_material_refused',
        path: 'description',
      }));
      expect(JSON.stringify(result)).not.toContain(tokenValue);
    }
  });

  test('fails closed on cyclic input instead of recursing indefinitely', () => {
    const plugin = validPlugin();
    const cyclicExtension: Record<string, unknown> = {};
    cyclicExtension.self = cyclicExtension;
    plugin.extensions = cyclicExtension;

    expect(() => validatePluginPackage(plugin, validationOptions())).not.toThrow();
    expect(validatePluginPackage(plugin, validationOptions()).diagnostics).toContainEqual(
      expect.objectContaining({
        code: 'plugin_disallowed_behavior',
        message: expect.stringContaining('cyclic object references'),
      })
    );
  });

  test('rejects accessor-bearing input without invoking the accessor', () => {
    const plugin = validPlugin();
    const extensions: Record<string, unknown> = {};
    let accessorInvoked = false;
    Object.defineProperty(extensions, 'payload', {
      enumerable: true,
      get() {
        accessorInvoked = true;
        throw new Error('accessor must not execute');
      },
    });
    plugin.extensions = extensions;

    const result = validatePluginPackage(plugin, validationOptions());

    expect(accessorInvoked).toBe(false);
    expect(result.valid).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_disallowed_behavior',
      message: expect.stringContaining('accessor properties'),
    }));
  });

  test('rejects hostile array prototypes without invoking inherited methods', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as unknown[];
    let inheritedMethodInvoked = false;
    const hostilePrototype = Object.create(Array.prototype) as Record<string, unknown>;
    Object.defineProperty(hostilePrototype, 'map', {
      value() {
        inheritedMethodInvoked = true;
        throw new Error('inherited array method must not execute');
      },
    });
    Object.setPrototypeOf(modules, hostilePrototype);

    const result = validatePluginPackage(plugin, validationOptions());

    expect(inheritedMethodInvoked).toBe(false);
    expect(result.valid).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_disallowed_behavior',
      message: expect.stringContaining('standard JSON arrays'),
    }));
  });

  test('rejects proxy input without invoking reflection traps', () => {
    const plugin = validPlugin();
    let reflectionTrapInvoked = false;
    plugin.extensions = new Proxy({}, {
      getPrototypeOf() {
        reflectionTrapInvoked = true;
        throw new Error('proxy reflection trap must not execute');
      },
      ownKeys() {
        reflectionTrapInvoked = true;
        throw new Error('proxy reflection trap must not execute');
      },
    });

    const result = validatePluginPackage(plugin, validationOptions());

    expect(reflectionTrapInvoked).toBe(false);
    expect(result.valid).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_disallowed_behavior',
      message: expect.stringContaining('Proxy objects'),
    }));
  });

  test('bounds direct object validation by JSON node count', () => {
    const plugin = validPlugin();
    plugin.extensions = {
      nodes: Array.from({ length: MAX_PLUGIN_JSON_NODES }, () => null),
    };

    const result = validatePluginPackage(plugin, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_disallowed_behavior',
      message: expect.stringContaining('maximum JSON node count'),
    }));
  });

  test('applies the direct object string budget in UTF-8 bytes', () => {
    const plugin = validPlugin();
    plugin.extensions = {
      multibyteText: '界'.repeat(Math.floor(MAX_PLUGIN_MANIFEST_BYTES / 3) + 1),
    };

    const result = validatePluginPackage(plugin, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_disallowed_behavior',
      message: expect.stringContaining('accepted size budget'),
    }));
  });

  test('includes object keys in the direct object string budget', () => {
    const plugin = validPlugin();
    const oversizedKey = 'k'.repeat(MAX_PLUGIN_MANIFEST_BYTES + 1);
    plugin.extensions = { [oversizedKey]: null };

    const result = validatePluginPackage(plugin, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_disallowed_behavior',
      message: expect.stringContaining('accepted size budget'),
      path: '<root>',
    }));
  });

  test('rejects sparse arrays whose declared length exceeds the validation budget', () => {
    const plugin = validPlugin();
    const sparseEntries: unknown[] = [];
    sparseEntries.length = MAX_PLUGIN_JSON_NODES + 1;
    plugin.extensions = { sparseEntries };

    const result = validatePluginPackage(plugin, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_disallowed_behavior',
      message: expect.stringContaining('maximum item count'),
    }));
  });

  test('rejects sparse arrays even when their declared length is within budget', () => {
    const plugin = validPlugin();
    const sparseEntries: unknown[] = [];
    sparseEntries.length = 3;
    sparseEntries[1] = 'present';
    plugin.extensions = { sparseEntries };

    const result = validatePluginPackage(plugin, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_disallowed_behavior',
      message: expect.stringContaining('sparse arrays'),
    }));
  });

  test('rejects direct object values outside the JSON primitive domain', () => {
    const nonJsonValues: unknown[] = [
      undefined,
      1n,
      Symbol('not-json'),
      () => true,
      Number.NaN,
      Number.POSITIVE_INFINITY,
    ];

    for (const nonJsonValue of nonJsonValues) {
      const plugin = validPlugin();
      plugin.extensions = { nonJsonValue };

      const result = validatePluginPackage(plugin, validationOptions());

      expect(result.valid).toBe(false);
      expect(result.package).toBeUndefined();
      expect(result.diagnostics).toContainEqual(expect.objectContaining({
        code: 'plugin_disallowed_behavior',
      }));
      expect(() => JSON.stringify(result)).not.toThrow();
    }
  });

  test('does not confuse ordinary words containing secret-name substrings with credential fields', () => {
    const plugin = validPlugin();
    plugin.extensions = {
      tokenizerModel: 'sentencepiece',
      sessionlessMode: true,
    };

    const result = validatePluginPackage(plugin, validationOptions());

    expect(result.valid).toBe(true);
    expect(result.diagnostics).toHaveLength(0);
  });

  test('rejects and redacts credential material embedded in a field name', () => {
    const plugin = validPlugin();
    const credentialLikeKey = ['ghp_', 'A1'.repeat(12)].join('');
    plugin.extensions = { [credentialLikeKey]: 'ignored' };

    const result = validatePluginPackage(plugin, validationOptions());
    const serializedDiagnostics = JSON.stringify(result.diagnostics);

    expect(result.valid).toBe(false);
    expect(result.package).toBeUndefined();
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_secret_material_refused',
      path: '<redacted>',
    }));
    expect(serializedDiagnostics).not.toContain(credentialLikeKey);
    expect(formatPluginDiagnostics(result)).not.toContain(credentialLikeKey);
  });

  test('surfaces review-required root execution', () => {
    const plugin = validPlugin();
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = { ...modules[0], run_as: 'root' };

    const result = validatePluginPackage(plugin, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.diagnostics.some((diagnostic) => diagnostic.code === 'plugin_review_required')).toBe(true);
  });

  test('does not let a package self-classify root execution as allowed', () => {
    const plugin = validPlugin();
    plugin.capabilities = {
      allowed: ['verified_installer', 'doctor_check', 'root_run_as'],
      reviewRequired: ['cross_plugin_dependency'],
      disallowed: ['arbitrary_shell', 'secret_values'],
    };
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = { ...modules[0], run_as: 'root' };

    expect(validatePluginPackage(plugin, validationOptions()).diagnostics).toContainEqual(
      expect.objectContaining({
        code: 'plugin_review_required',
        path: 'modules[0].run_as',
      })
    );
  });

  test('treats current-user execution as review-required because the installer may be root', () => {
    const plugin = validPlugin();
    plugin.capabilities = {
      allowed: ['verified_installer', 'doctor_check', 'root_run_as'],
      reviewRequired: ['cross_plugin_dependency'],
      disallowed: ['arbitrary_shell', 'secret_values'],
    };
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = { ...modules[0], run_as: 'current' };

    expect(validatePluginPackage(plugin, validationOptions()).diagnostics).toContainEqual(
      expect.objectContaining({
        code: 'plugin_review_required',
        path: 'modules[0].run_as',
      })
    );
  });

  test('does not let a package self-classify cross-plugin dependencies as allowed', () => {
    const plugin = validPlugin();
    plugin.capabilities = {
      allowed: ['verified_installer', 'doctor_check', 'cross_plugin_dependency'],
      reviewRequired: ['root_run_as'],
      disallowed: ['arbitrary_shell', 'secret_values'],
    };
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = { ...modules[0], dependencies: ['plugin.other.dep'] };

    expect(validatePluginPackage(
      plugin,
      validationOptions({ existingPluginModuleIds: ['plugin.other.dep'] })
    ).diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_review_required',
      path: 'modules[0].dependencies',
    }));
  });
});

describe('loadPluginManifestFromFile', () => {
  test('loads and validates a valid JSON plugin file', () => {
    const dir = mkdtempSync(join(tmpdir(), 'acfs-plugin-test-'));
    const pluginPath = join(dir, 'plugin.json');
    const plugin = validPlugin();
    const pluginBytes = JSON.stringify(plugin, null, 2);
    writeFileSync(pluginPath, pluginBytes, 'utf-8');

    const result = loadPluginManifestFromFile(pluginPath, validationOptions());
    expect(result.valid).toBe(true);
    expect(result.manifestModules.length).toBe(1);
    expect(result.manifestModules[0].id).toBe('plugin.example_tools.cli');
    expect(result.manifestModules[0].plugin?.pluginSha256).toBe(CHECKSUM);
  });

  test('refuses to infer an archive hash from extracted manifest bytes', () => {
    const dir = mkdtempSync(join(tmpdir(), 'acfs-untrusted-plugin-test-'));
    const pluginPath = join(dir, 'plugin.json');
    writeFileSync(pluginPath, JSON.stringify(validPlugin()), 'utf-8');
    const opts = validationOptions();
    delete opts.expectedPackageSha256;
    delete opts.packageSha256;

    const result = loadPluginManifestFromFile(pluginPath, opts);

    expect(result.valid).toBe(false);
    expect(result.manifestModules).toHaveLength(0);
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      code: 'plugin_package_hash_mismatch',
      context: {
        packageSha256Prefix: '<missing>',
        expectedPackageSha256Prefix: '<missing>',
      },
    }));
  });

  test('refuses YAML before parsing even when its content is valid JSON', () => {
    const dir = mkdtempSync(join(tmpdir(), 'acfs-yaml-plugin-test-'));
    const pluginPath = join(dir, 'plugin.yaml');
    const pluginBytes = JSON.stringify(validPlugin());
    writeFileSync(pluginPath, pluginBytes, 'utf-8');

    const result = loadPluginManifestFromFile(pluginPath, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.manifestModules).toHaveLength(0);
    expect(result.diagnostics).toEqual([
      expect.objectContaining({
        code: 'plugin_archive_layout_invalid',
        path: '<file>',
      }),
    ]);
  });

  test('refuses an oversized manifest before syntax parsing', () => {
    const dir = mkdtempSync(join(tmpdir(), 'acfs-oversized-plugin-test-'));
    const pluginPath = join(dir, 'plugin.json');
    writeFileSync(pluginPath, '{', 'utf-8');
    truncateSync(pluginPath, MAX_PLUGIN_MANIFEST_BYTES + 1);

    const result = loadPluginManifestFromFile(pluginPath, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.manifestModules).toHaveLength(0);
    expect(result.diagnostics).toEqual([
      expect.objectContaining({
        code: 'plugin_disallowed_behavior',
        path: '<file>',
        context: {
          sizeBytes: MAX_PLUGIN_MANIFEST_BYTES + 1,
          maximumBytes: MAX_PLUGIN_MANIFEST_BYTES,
        },
      }),
    ]);
  });

  test('refuses invalid UTF-8 that a lossy decoder could turn into valid JSON', () => {
    const dir = mkdtempSync(join(tmpdir(), 'acfs-invalid-utf8-plugin-test-'));
    const pluginPath = join(dir, 'plugin.json');
    const pluginBytes = Buffer.from(JSON.stringify(validPlugin()), 'utf-8');
    const displayNameOffset = pluginBytes.indexOf(Buffer.from('Example Tools'));
    expect(displayNameOffset).toBeGreaterThanOrEqual(0);
    pluginBytes[displayNameOffset] = 0xff;
    writeFileSync(pluginPath, pluginBytes);

    const result = loadPluginManifestFromFile(pluginPath, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.manifestModules).toHaveLength(0);
    expect(result.diagnostics).toEqual([
      expect.objectContaining({
        code: 'plugin_disallowed_behavior',
        message: expect.stringContaining('valid UTF-8'),
      }),
    ]);
  });

  test('refuses duplicate JSON keys instead of silently accepting the last value', () => {
    const dir = mkdtempSync(join(tmpdir(), 'acfs-duplicate-key-plugin-test-'));
    const pluginPath = join(dir, 'plugin.json');
    const pluginBytes = JSON.stringify(validPlugin()).replace(
      '"displayName":"Example Tools"',
      '"displayName":"Decoy","displayName":"Example Tools"'
    );
    writeFileSync(pluginPath, pluginBytes, 'utf-8');

    const result = loadPluginManifestFromFile(pluginPath, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.manifestModules).toHaveLength(0);
    expect(result.diagnostics).toEqual([
      expect.objectContaining({
        code: 'plugin_disallowed_behavior',
        message: expect.stringContaining('duplicate object keys'),
      }),
    ]);
  });

  test('refuses excessive JSON nesting before recursive schema inspection', () => {
    const dir = mkdtempSync(join(tmpdir(), 'acfs-deep-json-plugin-test-'));
    const pluginPath = join(dir, 'plugin.json');
    const plugin = validPlugin();
    const nestedValue = `${'{"next":'.repeat(MAX_PLUGIN_JSON_NESTING_DEPTH + 1)}null${'}'.repeat(MAX_PLUGIN_JSON_NESTING_DEPTH + 1)}`;
    const pluginBytes = JSON.stringify({ ...plugin, extensions: undefined }).replace(
      /}$/,
      `,"extensions":${nestedValue}}`
    );
    writeFileSync(pluginPath, pluginBytes, 'utf-8');

    const result = loadPluginManifestFromFile(pluginPath, validationOptions());

    expect(result.valid).toBe(false);
    expect(result.manifestModules).toHaveLength(0);
    expect(result.diagnostics).toEqual([
      expect.objectContaining({
        code: 'plugin_disallowed_behavior',
        message: expect.stringContaining('maximum JSON nesting depth'),
      }),
    ]);
  });

  test('fails closed on non-existent or invalid JSON file', () => {
    const missingPath = '/non/existent/path/plugin.json';
    const result = loadPluginManifestFromFile(missingPath, validationOptions());
    expect(result.valid).toBe(false);
    expect(result.diagnostics.length).toBeGreaterThan(0);
    expect(formatPluginDiagnostics(result)).not.toContain(missingPath);
  });
});

describe('collectPluginInputPaths', () => {
  test('keeps unbound plugin paths behind the activation trust boundary', () => {
    expect(() => enforcePluginActivationBoundary([])).not.toThrow();
    expect(() => enforcePluginActivationBoundary(['/tmp/plugin.json'])).toThrow(
      PLUGIN_ACTIVATION_UNAVAILABLE_MESSAGE,
    );
  });

  test('accepts documented control flags but rejects unknown arguments', () => {
    expect(
      collectPluginInputPaths(
        ['--dry-run', '--verbose', '--validate', '--diff', '--help', '-h'],
        {},
      ),
    ).toEqual([]);

    expect(() => collectPluginInputPaths(['--plguin', 'plugin.json'], {})).toThrow(
      'Unknown generator option: --plguin',
    );
    expect(() => collectPluginInputPaths(['plugin.json'], {})).toThrow(
      'Unexpected positional argument: plugin.json',
    );
  });

  test('refuses missing option values and missing directories', () => {
    const workingDirectory = mkdtempSync(join(tmpdir(), 'acfs-plugin-input-errors-'));

    expect(() => collectPluginInputPaths(['--plugin'], {}, workingDirectory)).toThrow(
      '--plugin requires a value'
    );
    expect(() =>
      collectPluginInputPaths(['--plugins-dir', 'missing'], {}, workingDirectory)
    ).toThrow('is not a readable plugin package directory');
  });

  test('expands supported directory entries deterministically', () => {
    const directory = mkdtempSync(join(tmpdir(), 'acfs-plugin-inputs-'));
    const first = join(directory, 'a.json');
    const second = join(directory, 'b.json');
    writeFileSync(second, '{}\n', 'utf8');
    writeFileSync(first, '{}\n', 'utf8');
    writeFileSync(join(directory, 'ignored.yaml'), '{}\n', 'utf8');
    writeFileSync(join(directory, 'notes.txt'), 'ignored\n', 'utf8');

    expect(collectPluginInputPaths(['--plugins-dir', directory], {})).toEqual([
      first,
      second,
    ]);
  });

  test('refuses explicitly configured empty plugin inputs', () => {
    const directory = mkdtempSync(join(tmpdir(), 'acfs-empty-plugin-inputs-'));

    expect(() => collectPluginInputPaths([], { ACFS_PLUGIN_PATHS: '  ' })).toThrow(
      'ACFS_PLUGIN_PATHS must name at least one plugin package'
    );
    expect(() => collectPluginInputPaths([], { ACFS_PLUGINS_DIR: directory })).toThrow(
      'contains no JSON plugin packages'
    );
  });
});

describe('mergeValidatedPlugins', () => {
  test('merges validated plugin modules into manifest without modifying original', () => {
    const manifest = firstPartyManifest();
    const plugin = validPlugin();
    const validationResult = validatePluginPackage(plugin, validationOptions());
    expect(validationResult.valid).toBe(true);

    const merged = mergeValidatedPlugins(manifest, [validationResult]);
    expect(merged.modules.length).toBe(manifest.modules.length + 1);
    expect(merged.modules.some((m) => m.id === 'plugin.example_tools.cli')).toBe(true);
    // Original manifest is unmodified
    expect(manifest.modules.length).toBe(2);
  });

  test('throws if attempting to merge an invalid plugin result', () => {
    const manifest = firstPartyManifest();
    const invalidResult = {
      valid: false,
      diagnostics: [
        {
          code: 'plugin_missing_required_field' as const,
          message: 'Invalid plugin',
          path: '<root>',
          severity: 'error' as const,
        },
      ],
      manifestModules: [],
    };

    expect(() => mergeValidatedPlugins(manifest, [invalidResult])).toThrow();
  });
});

describe('Installer, doctor, and web metadata generation from validated plugins', () => {
  test('generates category script with plugin module function and labels', () => {
    const manifest = firstPartyManifest();
    const plugin = validPlugin();
    const validationResult = validatePluginPackage(plugin, validationOptions());
    expect(validationResult.valid).toBe(true);

    const merged = mergeValidatedPlugins(manifest, [validationResult]);
    const categoryScript = generateCategoryScript(merged, 'tools');

    expect(categoryScript).toContain('[plugin: example.tools@1.2.3]');
  });

  test('generates doctor checks with plugin verify command and tab delimiter', () => {
    const manifest = firstPartyManifest();
    const plugin = validPlugin();
    const validationResult = validatePluginPackage(plugin, validationOptions());
    expect(validationResult.valid).toBe(true);

    const merged = mergeValidatedPlugins(manifest, [validationResult]);
    const doctorChecks = generateDoctorChecks(merged);

    expect(doctorChecks).toContain('plugin.example_tools.cli\tExample command-line tool.');
    expect(doctorChecks).toContain('command -v -- example');
  });

  test('generates manifest index with plugin provenance arrays', () => {
    const manifest = firstPartyManifest();
    const plugin = validPlugin();
    const validationResult = validatePluginPackage(plugin, validationOptions());
    expect(validationResult.valid).toBe(true);

    const merged = mergeValidatedPlugins(manifest, [validationResult]);
    const indexScript = generateManifestIndex(merged, 'test-sha256');

    expect(indexScript).toContain("['plugin.example_tools.cli']=\"example.tools\"");
    expect(indexScript).toContain("['plugin.example_tools.cli']=\"1.2.3\"");
    expect(indexScript).toContain('ACFS_MODULE_PLUGIN_PACKAGE=(');
    expect(indexScript).toContain('ACFS_MODULE_PLUGIN_VERSION=(');
    expect(indexScript).toContain('ACFS_MODULE_PLUGIN_SHA256=(');
  });

  test('generates web modules and tools with ManifestPluginProvenance', () => {
    const manifest = firstPartyManifest();
    const plugin = validPlugin();
    plugin.capabilities = {
      allowed: ['verified_installer', 'doctor_check', 'web_metadata'],
      reviewRequired: ['root_run_as', 'cross_plugin_dependency'],
      disallowed: ['arbitrary_shell', 'secret_values'],
    };
    const modules = plugin.modules as Record<string, unknown>[];
    modules[0] = {
      ...modules[0],
      web: {
        display_name: 'Example CLI',
        tagline: 'Example CLI tool',
        cli_name: 'example',
        visible: true,
      },
    };
    const validationResult = validatePluginPackage(plugin, validationOptions());
    expect(validationResult.valid).toBe(true);

    const merged = mergeValidatedPlugins(manifest, [validationResult]);
    const webModules = generateWebModules(merged, '1.0.0', 'manifest-hash', 'checksums-hash');
    const webTools = generateWebTools(merged);
    const webCommands = generateWebCommands(merged);

    expect(webModules).toContain('export interface ManifestPluginProvenance {');
    expect(webModules).toContain('packageId: "example.tools"');
    expect(webModules).toContain('version: "1.2.3"');

    expect(webTools).toContain(
      "import type { ManifestPluginProvenance } from './manifest-modules';"
    );
    expect(webTools).toContain('plugin?: ManifestPluginProvenance;');
    expect(webTools).toContain('packageId: "example.tools"');

    expect(webCommands).toContain('moduleId: "plugin.example_tools.cli"');
    expect(webCommands).toContain('cliName: "example"');
  });
});

describe('Documentation plugin example fixtures', () => {
  test('schema fixture validates only with explicit synthetic trust bindings', () => {
    const docPath = resolve(__dirname, '../../../docs/operations/plugin-review-workflow.md');
    const docContent = readFileSync(docPath, 'utf-8');

    expect(docContent).toMatch(/does not\s+>\s*activate or install plugins/);
    const jsonMatch = docContent.match(
      /### Safe Plugin Schema Fixture[\s\S]*?```json\n([\s\S]*?)\n```/,
    );
    expect(jsonMatch).not.toBeNull();
    const parsed = JSON.parse(jsonMatch![1]);

    const result = validatePluginPackage(parsed, validationOptions());
    if (!result.valid) {
      console.error('Doc example validation failed:', formatPluginDiagnostics(result));
    }
    expect(result.valid).toBe(true);
    expect(result.manifestModules.length).toBe(1);
    expect(result.manifestModules[0].id).toBe('plugin.example_tools.cli');
  });
});
