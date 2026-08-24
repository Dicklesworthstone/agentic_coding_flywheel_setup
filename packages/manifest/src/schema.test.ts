/**
 * Tests for ACFS Manifest Schema (Zod schemas)
 * Related: bead dvt.2
 *
 * Tests schema validation behavior, error messages, and defaults.
 */

import { describe, test, expect } from 'bun:test';
import {
  ManifestSchema,
  ManifestDefaultsSchema,
  ModuleSchema,
  ModuleWebMetadataSchema,
} from './schema.js';

describe('ManifestDefaultsSchema', () => {
  test('validates complete defaults', () => {
    const result = ManifestDefaultsSchema.safeParse({
      user: 'ubuntu',
      workspace_root: '/data/projects',
      mode: 'vibe',
    });
    expect(result.success).toBe(true);
  });

  test('applies default mode when not specified', () => {
    const result = ManifestDefaultsSchema.safeParse({
      user: 'ubuntu',
      workspace_root: '/data/projects',
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.mode).toBe('vibe');
    }
  });

  test('rejects empty user', () => {
    const result = ManifestDefaultsSchema.safeParse({
      user: '',
      workspace_root: '/data/projects',
      mode: 'vibe',
    });
    expect(result.success).toBe(false);
  });

  test('rejects empty workspace_root', () => {
    const result = ManifestDefaultsSchema.safeParse({
      user: 'ubuntu',
      workspace_root: '',
      mode: 'vibe',
    });
    expect(result.success).toBe(false);
  });

  test('accepts safe mode', () => {
    const result = ManifestDefaultsSchema.safeParse({
      user: 'ubuntu',
      workspace_root: '/data',
      mode: 'safe',
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.mode).toBe('safe');
    }
  });

  test('rejects invalid mode', () => {
    const result = ManifestDefaultsSchema.safeParse({
      user: 'ubuntu',
      workspace_root: '/data',
      mode: 'invalid',
    });
    expect(result.success).toBe(false);
  });

  test('rejects unknown default fields instead of silently discarding typos', () => {
    const result = ManifestDefaultsSchema.safeParse({
      user: 'ubuntu',
      workspace_root: '/data',
      mode: 'vibe',
      workspace_rooot: '/wrong/path',
    });
    expect(result.success).toBe(false);
  });
});

describe('ModuleSchema', () => {
  const validMinimalModule = {
    id: 'base.system',
    description: 'Base system packages',
    install: ['apt-get update'],
    verify: ['curl --version'],
  };

  test('validates minimal module', () => {
    const result = ModuleSchema.safeParse(validMinimalModule);
    expect(result.success).toBe(true);
  });

  test('applies default values', () => {
    const result = ModuleSchema.safeParse(validMinimalModule);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.run_as).toBe('target_user');
      expect(result.data.optional).toBe(false);
      expect(result.data.enabled_by_default).toBe(true);
      expect(result.data.generated).toBe(true);
    }
  });

  test('rejects empty module ID', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      id: '',
    });
    expect(result.success).toBe(false);
  });

  test('rejects uppercase module ID', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      id: 'Base.System',
    });
    expect(result.success).toBe(false);
  });

  test('rejects module ID starting with number', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      id: '1base.system',
    });
    expect(result.success).toBe(false);
  });

  test('accepts module ID with underscores', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      id: 'stack.mcp_agent_mail',
    });
    expect(result.success).toBe(true);
  });

  test('accepts validated plugin provenance on normalized modules', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      id: 'plugin.example_tools.cli',
      category: 'tools',
      plugin: {
        packageId: 'example.tools',
        version: '1.2.3',
        pluginSha256: 'a'.repeat(64),
        sourceRef: 'main',
        sourceCommit: '0123456789abcdef0123456789abcdef01234567',
      },
    });
    expect(result.success).toBe(true);
  });

  test('rejects malformed or misspelled plugin provenance', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      id: 'plugin.example_tools.cli',
      category: 'tools',
      plugin: {
        packageId: 'example.tools',
        version: '1.2.3',
        pluginSha256: 'not-a-hash',
        sourceRef: 'main',
        sourceCommit: '0123456789abcdef0123456789abcdef01234567',
        sourceCommmit: 'ffffffffffffffffffffffffffffffffffffffff',
      },
    });
    expect(result.success).toBe(false);
  });

  test('accepts multi-segment module ID', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      id: 'cloud.aws.s3',
    });
    expect(result.success).toBe(true);
  });

  test('rejects categories outside the canonical generator set', () => {
    expect(ModuleSchema.safeParse({
      ...validMinimalModule,
      category: 'weird',
    }).success).toBe(false);
  });

  test('rejects an unknown ID-derived category when category is omitted', () => {
    expect(ModuleSchema.safeParse({
      ...validMinimalModule,
      id: 'weird.module',
    }).success).toBe(false);
  });

  test('rejects empty description', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      description: '',
    });
    expect(result.success).toBe(false);
  });

  test('rejects empty verify array', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      verify: [],
    });
    expect(result.success).toBe(false);
  });

  test('accepts empty install array when verified_installer is provided', () => {
    const result = ModuleSchema.safeParse({
      id: 'lang.bun',
      description: 'Bun runtime',
      install: [],
      verify: ['bun --version'],
      verified_installer: {
        tool: 'bun',
        runner: 'bash',
        args: [],
      },
    });
    expect(result.success).toBe(true);
  });

  test('rejects empty install array without verified_installer when generated is true', () => {
    const result = ModuleSchema.safeParse({
      id: 'lang.bun',
      description: 'Bun runtime',
      install: [],
      verify: ['bun --version'],
      generated: true,
    });
    expect(result.success).toBe(false);
  });

  test('rejects whitespace-only install entries instead of generating a successful no-op', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      install: ['   '],
    });
    expect(result.success).toBe(false);
  });

  test('rejects blank verify entries instead of generating a vacuous health check', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      verify: [''],
    });
    expect(result.success).toBe(false);
  });

  test('accepts empty install array when generated is false', () => {
    const result = ModuleSchema.safeParse({
      id: 'lang.bun',
      description: 'Bun runtime',
      install: [],
      verify: ['bun --version'],
      generated: false,
    });
    expect(result.success).toBe(true);
  });

  test('validates run_as enum', () => {
    const runAsValues = ['target_user', 'root', 'current'];
    for (const runAs of runAsValues) {
      const result = ModuleSchema.safeParse({
        ...validMinimalModule,
        run_as: runAs,
      });
      expect(result.success).toBe(true);
    }
  });

  test('rejects invalid run_as value', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      run_as: 'invalid',
    });
    expect(result.success).toBe(false);
  });

  test('rejects unknown module fields instead of silently dropping dependency typos', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      dependecies: ['base.prerequisite'],
    });
    expect(result.success).toBe(false);
  });

  test('validates phase range (1-10)', () => {
    // Valid phases
    for (const phase of [1, 5, 10]) {
      const result = ModuleSchema.safeParse({
        ...validMinimalModule,
        phase,
      });
      expect(result.success).toBe(true);
    }

    // Invalid phases
    for (const phase of [0, 11, -1, 100]) {
      const result = ModuleSchema.safeParse({
        ...validMinimalModule,
        phase,
      });
      expect(result.success).toBe(false);
    }
  });

  test('validates dependencies array', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      dependencies: ['base.core', 'lang.bun'],
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.dependencies).toEqual(['base.core', 'lang.bun']);
    }
  });

  test('validates tags array', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      tags: ['critical', 'runtime'],
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.tags).toContain('critical');
      expect(result.data.tags).toContain('runtime');
    }
  });

  test('validates notes array', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      notes: ['First note', 'Second note'],
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.notes).toHaveLength(2);
    }
  });

  test('validates docs_url as valid URL', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      docs_url: 'https://docs.example.com/module',
    });
    expect(result.success).toBe(true);
  });

  test('rejects invalid docs_url', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      docs_url: 'not-a-valid-url',
    });
    expect(result.success).toBe(false);
  });

  test('validates verified_installer object', () => {
    const result = ModuleSchema.safeParse({
      id: 'lang.bun',
      description: 'Bun runtime',
      install: [],
      verify: ['bun --version'],
      verified_installer: {
        tool: 'bun',
        runner: 'bash',
        args: ['--', '--yes'],
      },
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.verified_installer?.tool).toBe('bun');
      expect(result.data.verified_installer?.runner).toBe('bash');
      expect(result.data.verified_installer?.args).toEqual(['--', '--yes']);
    }
  });

  test('rejects unknown verified-installer fields', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      verified_installer: {
        tool: 'bun',
        runner: 'bash',
        arguements: ['--yes'],
      },
    });
    expect(result.success).toBe(false);
  });

  test('validates verified_installer env assignments', () => {
    const result = ModuleSchema.safeParse({
      id: 'stack.ru',
      description: 'Repo Updater',
      install: [],
      verify: ['ru --version'],
      verified_installer: {
        tool: 'ru',
        runner: 'bash',
        env: ['RU_NON_INTERACTIVE=1'],
        args: [],
      },
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.verified_installer?.env).toEqual(['RU_NON_INTERACTIVE=1']);
    }
  });

  test('accepts https verified_installer url metadata', () => {
    const result = ModuleSchema.safeParse({
      id: 'stack.rch',
      description: 'Remote Compilation Helper',
      install: [],
      verify: ['rch --version'],
      verified_installer: {
        tool: 'rch',
        url: 'https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh',
        runner: 'bash',
      },
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.verified_installer?.url).toBe(
        'https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh'
      );
    }
  });

  test('rejects non-https verified_installer url metadata', () => {
    const result = ModuleSchema.safeParse({
      id: 'stack.rch',
      description: 'Remote Compilation Helper',
      install: [],
      verify: ['rch --version'],
      verified_installer: {
        tool: 'rch',
        url: 'http://example.com/install.sh',
        runner: 'bash',
      },
    });
    expect(result.success).toBe(false);
  });

  test('rejects invalid verified_installer env entries', () => {
    const result = ModuleSchema.safeParse({
      id: 'stack.ru',
      description: 'Repo Updater',
      install: [],
      verify: ['ru --version'],
      verified_installer: {
        tool: 'ru',
        runner: 'bash',
        env: ['not-an-assignment'],
        args: [],
      },
    });
    expect(result.success).toBe(false);
  });

  test('allows only security-reviewed verified_installer environment contracts', () => {
    const allowedContracts = [
      { tool: 'atuin', entry: 'ATUIN_NO_MODIFY_PATH=1' },
      { tool: 'mcp_agent_mail', entry: 'AM_INSTALL_SKIP_MCP_SETUP=1' },
      { tool: 'mcp_agent_mail', entry: 'AM_INSTALL_SKIP_REMOTE_HTTP_READINESS=1' },
      { tool: 'ru', entry: 'RU_NON_INTERACTIVE=1' },
      { tool: 's2p', entry: 'RU_NON_INTERACTIVE=1' },
      { tool: 'grok', entry: 'GROK_BIN_DIR=$TARGET_HOME/.local/bin' },
      { tool: 'cass', entry: 'TMPDIR=$TARGET_HOME/.cache/acfs/installer-tmp/cass.XXXXXX' },
    ];

    for (const { tool, entry } of allowedContracts) {
      const result = ModuleSchema.safeParse({
        ...validMinimalModule,
        install: [],
        verified_installer: {
          tool,
          runner: 'bash',
          env: [entry],
        },
      });
      expect(result.success).toBe(true);
    }
  });

  test('rejects startup hooks, unsafe values, duplicate env names, and detached runners', () => {
    const rejectedEnvironments = [
      ['BASH_ENV=/tmp/attacker.sh'],
      ['PATH=/tmp/attacker'],
      ['RU_NON_INTERACTIVE=0'],
      ['TMPDIR=$TARGET_HOME/../../tmp/cass.XXXXXX'],
      ['RU_NON_INTERACTIVE=1', 'RU_NON_INTERACTIVE=1'],
    ];

    for (const env of rejectedEnvironments) {
      const result = ModuleSchema.safeParse({
        ...validMinimalModule,
        install: [],
        verified_installer: { tool: 'ru', runner: 'bash', env },
      });
      expect(result.success).toBe(false);
    }

    expect(ModuleSchema.safeParse({
      ...validMinimalModule,
      install: [],
      verified_installer: {
        tool: 'ru',
        runner: 'bash',
        env: ['AM_INSTALL_SKIP_MCP_SETUP=1'],
      },
    }).success).toBe(false);

    for (const { tool, env } of [
      { tool: 'cass', env: ['TMPDIR=$TARGET_HOME/.cache/acfs/installer-tmp/cass.XXXXXY'] },
      { tool: 'cass', env: ['TMPDIR=$TARGET_HOME/.cache/acfs/installer-tmp/other.XXXXXX'] },
      { tool: 'cass', env: ['TMPDIR=$TARGET_HOME/.cache/acfs/../installer-tmp/cass.XXXXXX'] },
      { tool: 'grok', env: ['GROK_BIN_DIR=$TARGET_HOME/.grok/bin'] },
      { tool: 'grok', env: ['RU_NON_INTERACTIVE=1'] },
      { tool: 'mcp_agent_mail', env: ['ATUIN_NO_MODIFY_PATH=1'] },
    ]) {
      expect(ModuleSchema.safeParse({
        ...validMinimalModule,
        install: [],
        verified_installer: { tool, runner: 'bash', env },
      }).success).toBe(false);
    }

    expect(ModuleSchema.safeParse({
      ...validMinimalModule,
      install: [],
      verified_installer: { tool: 'ru', runner: 'bash', run_in_tmux: true },
    }).success).toBe(false);
    expect(ModuleSchema.safeParse({
      ...validMinimalModule,
      run_as: 'root',
      install: [],
      verified_installer: { tool: 'ru', runner: 'bash' },
    }).success).toBe(false);
  });

  test('rejects interpreter options before a verified installer file', () => {
    for (const args of [
      ['-s', '--'],
      ['-c', 'source /tmp/attacker', '--'],
      ['--rcfile', '/tmp/attacker', '--'],
      ['--init-file', '/tmp/attacker', '--'],
      ['-O', 'extdebug', '--'],
    ]) {
      expect(ModuleSchema.safeParse({
        ...validMinimalModule,
        install: [],
        verified_installer: { tool: 'ru', runner: 'bash', args },
      }).success).toBe(false);
    }

    expect(ModuleSchema.safeParse({
      ...validMinimalModule,
      install: [],
      verified_installer: {
        tool: 'ru',
        runner: 'bash',
        args: ['--', '--easy-mode'],
      },
    }).success).toBe(true);
  });

  test('rejects verified_installer with python runner (security)', () => {
    const result = ModuleSchema.safeParse({
      id: 'lang.python',
      description: 'Python',
      install: [],
      verify: ['python --version'],
      verified_installer: {
        tool: 'python',
        runner: 'python',
        args: [],
      },
    });
    expect(result.success).toBe(false);
  });

  test('accepts sh as verified_installer runner', () => {
    const result = ModuleSchema.safeParse({
      id: 'tools.test',
      description: 'Test',
      install: [],
      verify: ['test --version'],
      verified_installer: {
        tool: 'test',
        runner: 'sh',
        args: [],
      },
    });
    expect(result.success).toBe(true);
  });

  test('validates installed_check object', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      installed_check: {
        run_as: 'target_user',
        command: 'which curl',
      },
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.installed_check?.command).toBe('which curl');
    }
  });

  test('rejects installed_check with empty command', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      installed_check: {
        run_as: 'target_user',
        command: '',
      },
    });
    expect(result.success).toBe(false);
  });

  test('rejects unknown installed-check fields', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      installed_check: {
        run_as: 'target_user',
        command: 'which curl',
        commmand: 'which wrong-binary',
      },
    });
    expect(result.success).toBe(false);
  });

  test('validates pre_install_check object', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      pre_install_check: {
        run_as: 'target_user',
        command: 'command -v claude >/dev/null 2>&1',
        skip_message: 'Skipping PCR - Claude Code not found',
      },
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.pre_install_check?.command).toBe('command -v claude >/dev/null 2>&1');
      expect(result.data.pre_install_check?.skip_message).toBe('Skipping PCR - Claude Code not found');
    }
  });

  test('validates aliases array', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      aliases: ['sys', 'system'],
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.aliases).toContain('sys');
      expect(result.data.aliases).toContain('system');
    }
  });
});

describe('ManifestSchema', () => {
  const validMinimalManifest = {
    version: 1,
    name: 'Test Manifest',
    id: 'test',
    defaults: {
      user: 'ubuntu',
      workspace_root: '/data/projects',
      mode: 'vibe',
    },
    modules: [
      {
        id: 'base.system',
        description: 'Base system',
        install: ['apt-get update'],
        verify: ['curl --version'],
      },
    ],
  };

  test('validates complete manifest', () => {
    const result = ManifestSchema.safeParse(validMinimalManifest);
    expect(result.success).toBe(true);
  });

  test('rejects unknown top-level fields', () => {
    const result = ManifestSchema.safeParse({
      ...validMinimalManifest,
      module: validMinimalManifest.modules,
    });
    expect(result.success).toBe(false);
  });

  test('rejects negative version', () => {
    const result = ManifestSchema.safeParse({
      ...validMinimalManifest,
      version: -1,
    });
    expect(result.success).toBe(false);
  });

  test('rejects zero version', () => {
    const result = ManifestSchema.safeParse({
      ...validMinimalManifest,
      version: 0,
    });
    expect(result.success).toBe(false);
  });

  test('rejects non-integer version', () => {
    const result = ManifestSchema.safeParse({
      ...validMinimalManifest,
      version: 1.5,
    });
    expect(result.success).toBe(false);
  });

  test('rejects empty name', () => {
    const result = ManifestSchema.safeParse({
      ...validMinimalManifest,
      name: '',
    });
    expect(result.success).toBe(false);
  });

  test('rejects empty id', () => {
    const result = ManifestSchema.safeParse({
      ...validMinimalManifest,
      id: '',
    });
    expect(result.success).toBe(false);
  });

  test('rejects uppercase id', () => {
    const result = ManifestSchema.safeParse({
      ...validMinimalManifest,
      id: 'TestManifest',
    });
    expect(result.success).toBe(false);
  });

  test('accepts id with underscores', () => {
    const result = ManifestSchema.safeParse({
      ...validMinimalManifest,
      id: 'test_manifest',
    });
    expect(result.success).toBe(true);
  });

  test('rejects empty modules array', () => {
    const result = ManifestSchema.safeParse({
      ...validMinimalManifest,
      modules: [],
    });
    expect(result.success).toBe(false);
  });

  test('validates multiple modules', () => {
    const result = ManifestSchema.safeParse({
      ...validMinimalManifest,
      modules: [
        {
          id: 'base.system',
          description: 'Base system',
          install: ['apt-get update'],
          verify: ['curl --version'],
        },
        {
          id: 'shell.zsh',
          description: 'Zsh shell',
          dependencies: ['base.system'],
          install: ['apt-get install zsh'],
          verify: ['zsh --version'],
        },
      ],
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.modules).toHaveLength(2);
    }
  });

  test('rejects missing defaults', () => {
    const { defaults, ...withoutDefaults } = validMinimalManifest;
    const result = ManifestSchema.safeParse(withoutDefaults);
    expect(result.success).toBe(false);
  });

  test('provides descriptive error messages', () => {
    const result = ManifestSchema.safeParse({
      version: -1,
      name: '',
      id: 'UPPERCASE',
      defaults: { user: '', workspace_root: '', mode: 'invalid' },
      modules: [],
    });
    expect(result.success).toBe(false);
    if (!result.success) {
      // Should have multiple errors
      expect(result.error.issues.length).toBeGreaterThan(0);
    }
  });
});

describe('ModuleWebMetadataSchema', () => {
  test('validates complete web metadata', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      display_name: 'MCP Agent Mail',
      short_name: 'Agent Mail',
      tagline: 'Inter-agent coordination via messages',
      short_desc: 'Provides message routing and file reservation for cooperating agents.',
      icon: 'mail',
      color: '#3B82F6',
      category_label: 'AI Agent',
      href: '/tools/agent-mail',
      features: ['Message routing', 'File reservations'],
      tech_stack: ['Rust', 'SQLite'],
      use_cases: ['Multi-agent coordination'],
      language: 'Rust',
      stars: 150,
      cli_name: 'mcp-agent-mail',
      cli_aliases: ['mam'],
      command_example: 'mcp-agent-mail --help',
      lesson_slug: 'agent-mail-basics',
      tldr_snippet: 'Routes messages between AI coding agents.',
      visible: true,
    });
    expect(result.success).toBe(true);
  });

  test('accepts empty object (all fields optional except visible default)', () => {
    const result = ModuleWebMetadataSchema.safeParse({});
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.visible).toBe(true);
    }
  });

  test('rejects unknown web metadata fields', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      display_name: 'Test Tool',
      displayname: 'Misspelled Tool',
    });
    expect(result.success).toBe(false);
  });

  test('defaults visible to true', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      display_name: 'Test Tool',
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.visible).toBe(true);
    }
  });

  test('accepts visible=false', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      visible: false,
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.visible).toBe(false);
    }
  });

  test('rejects invalid hex color (no hash)', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      color: '3B82F6',
    });
    expect(result.success).toBe(false);
  });

  test('rejects invalid hex color (3-digit)', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      color: '#F00',
    });
    expect(result.success).toBe(false);
  });

  test('rejects invalid hex color (CSS injection attempt)', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      color: '#000;background:url(evil)',
    });
    expect(result.success).toBe(false);
  });

  test('accepts valid hex colors', () => {
    for (const color of ['#000000', '#FFFFFF', '#3B82F6', '#ff5733']) {
      const result = ModuleWebMetadataSchema.safeParse({ color });
      expect(result.success).toBe(true);
    }
  });

  test('rejects uppercase icon names', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      icon: 'Terminal',
    });
    expect(result.success).toBe(false);
  });

  test('accepts kebab-case icon names', () => {
    for (const icon of ['mail', 'terminal-square', 'git-branch']) {
      const result = ModuleWebMetadataSchema.safeParse({ icon });
      expect(result.success).toBe(true);
    }
  });

  test('rejects href without leading slash', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      href: 'tools/agent-mail',
    });
    expect(result.success).toBe(false);
  });

  test('rejects scheme-relative href values', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      href: '//attacker',
    });
    expect(result.success).toBe(false);
  });

  test('rejects malformed and credential-bearing external href values', () => {
    for (const href of [
      'https://',
      'https://example.com/path with spaces',
      'https://alice:swordfish@example.com/tool',
    ]) {
      expect(ModuleWebMetadataSchema.safeParse({ href }).success).toBe(false);
    }
  });

  test('accepts valid href paths', () => {
    for (const href of ['/tools/agent-mail', '/tldr', '/tools/br_cli']) {
      const result = ModuleWebMetadataSchema.safeParse({ href });
      expect(result.success).toBe(true);
    }
  });

  test('accepts valid HTTP and HTTPS href URLs', () => {
    for (const href of ['https://example.com/tool', 'http://localhost.test/tool']) {
      expect(ModuleWebMetadataSchema.safeParse({ href }).success).toBe(true);
    }
  });

  test('rejects negative stars', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      stars: -1,
    });
    expect(result.success).toBe(false);
  });

  test('rejects non-integer stars', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      stars: 1.5,
    });
    expect(result.success).toBe(false);
  });

  test('rejects empty display_name', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      display_name: '',
    });
    expect(result.success).toBe(false);
  });

  test('rejects display_name over 100 chars', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      display_name: 'x'.repeat(101),
    });
    expect(result.success).toBe(false);
  });

  test('rejects invalid cli_name (uppercase)', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      cli_name: 'MyTool',
    });
    expect(result.success).toBe(false);
  });

  test('accepts valid cli_name', () => {
    for (const cli_name of ['br', 'mcp-agent-mail', 'bun_run']) {
      const result = ModuleWebMetadataSchema.safeParse({ cli_name });
      expect(result.success).toBe(true);
    }
  });

  test('rejects invalid lesson_slug', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      lesson_slug: 'Bad Slug With Spaces',
    });
    expect(result.success).toBe(false);
  });

  test('accepts valid lesson_slug', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      lesson_slug: 'getting-started',
    });
    expect(result.success).toBe(true);
  });

  test('limits features array length', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      features: Array.from({ length: 21 }, (_, i) => `Feature ${i}`),
    });
    expect(result.success).toBe(false);
  });

  test('rejects empty strings in features array', () => {
    const result = ModuleWebMetadataSchema.safeParse({
      features: ['Valid feature', ''],
    });
    expect(result.success).toBe(false);
  });
});

describe('ModuleSchema with web metadata', () => {
  const validMinimalModule = {
    id: 'base.system',
    description: 'Base system packages',
    install: ['apt-get update'],
    verify: ['curl --version'],
  };

  test('accepts module without web field', () => {
    const result = ModuleSchema.safeParse(validMinimalModule);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.web).toBeUndefined();
    }
  });

  test('accepts module with web metadata', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      web: {
        display_name: 'Base System',
        short_name: 'System',
        tagline: 'Core system packages',
        icon: 'server',
        color: '#6B7280',
      },
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.web?.display_name).toBe('Base System');
      expect(result.data.web?.visible).toBe(true);
    }
  });

  test('accepts module with web visible=false', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      web: { visible: false },
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.web?.visible).toBe(false);
    }
  });

  test('rejects module with invalid web color', () => {
    const result = ModuleSchema.safeParse({
      ...validMinimalModule,
      web: { color: 'red' },
    });
    expect(result.success).toBe(false);
  });
});
