import { describe, expect, test } from 'bun:test';
import {
  formatPluginDiagnostics,
  validatePluginPackage,
  type PluginValidationOptions,
} from './plugin.js';
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
    modules.push({ ...modules[0] });

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
