/**
 * Tests for ACFS Manifest Parser using real fixtures
 * Related: bead dvt.2
 *
 * Uses the actual acfs.manifest.yaml as the primary fixture.
 * This ensures tests reflect real-world usage.
 */

import { describe, test, expect, beforeAll } from 'bun:test';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseManifestFile, parseManifestString, validateManifest, validateManifestData } from './parser.js';
import { validateVerifiedInstallerChecksums } from './validate.js';
import type { Manifest } from './types.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, '../../..');
const MANIFEST_PATH = resolve(PROJECT_ROOT, 'acfs.manifest.yaml');

describe('parseManifestFile with real manifest', () => {
  let manifest: Manifest;

  beforeAll(() => {
    const result = parseManifestFile(MANIFEST_PATH);
    expect(result.success).toBe(true);
    if (!result.success || !result.data) {
      throw new Error(`Failed to parse manifest: ${result.error?.message}`);
    }
    manifest = result.data;
  });

  test('parses acfs.manifest.yaml successfully', () => {
    expect(manifest).toBeDefined();
    expect(manifest.version).toBeGreaterThan(0);
    expect(manifest.name).toBeTruthy();
    expect(manifest.id).toBe('acfs');
  });

  test('has expected defaults', () => {
    expect(manifest.defaults.user).toBe('ubuntu');
    expect(manifest.defaults.workspace_root).toBe('/data/projects');
    expect(manifest.defaults.mode).toBe('vibe');
  });

  test('has modules with correct structure', () => {
    expect(manifest.modules.length).toBeGreaterThan(0);

    for (const module of manifest.modules) {
      // Every module must have required fields
      expect(module.id).toBeTruthy();
      expect(module.description).toBeTruthy();
      expect(module.verify).toBeInstanceOf(Array);
      expect(module.verify.length).toBeGreaterThan(0);
    }
  });

  test('all module IDs follow naming convention', () => {
    const idPattern = /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/;

    for (const module of manifest.modules) {
      expect(module.id).toMatch(idPattern);
    }
  });

  test('validates with no errors', () => {
    const result = validateManifest(manifest);
    expect(result.valid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  test('includes expected core modules', () => {
    const moduleIds = new Set(manifest.modules.map((m) => m.id));

    // Critical base modules
    expect(moduleIds.has('base.system')).toBe(true);
    expect(moduleIds.has('shell.zsh')).toBe(true);

    // Languages
    expect(moduleIds.has('lang.bun')).toBe(true);
    expect(moduleIds.has('lang.uv')).toBe(true);
    expect(moduleIds.has('lang.rust')).toBe(true);

    // Agents
    expect(moduleIds.has('agents.claude')).toBe(true);
    expect(moduleIds.has('agents.codex')).toBe(true);
    expect(moduleIds.has('agents.gemini')).toBe(true);
  });

  test('dependencies reference existing modules', () => {
    const moduleIds = new Set(manifest.modules.map((m) => m.id));

    for (const module of manifest.modules) {
      if (module.dependencies) {
        for (const dep of module.dependencies) {
          expect(moduleIds.has(dep)).toBe(true);
        }
      }
    }
  });

  test('phases are assigned correctly (1-10 range)', () => {
    for (const module of manifest.modules) {
      if (module.phase !== undefined) {
        expect(module.phase).toBeGreaterThanOrEqual(1);
        expect(module.phase).toBeLessThanOrEqual(10);
      }
    }
  });
});

describe('parseManifestFile error handling', () => {
  test('returns error for non-existent file', () => {
    const result = parseManifestFile('/nonexistent/path/manifest.yaml');
    expect(result.success).toBe(false);
    expect(result.error?.message).toContain('not found');
  });
});

describe('parseManifestString', () => {
  test('parses valid minimal manifest', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data/projects
  mode: vibe
modules:
  - id: base.core
    description: Core packages
    install:
      - echo "install"
    verify:
      - echo "verify"
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(true);
    expect(result.data?.modules.length).toBe(1);
    expect(result.data?.modules[0].id).toBe('base.core');
  });

  test('returns error for invalid YAML syntax', () => {
    const yaml = `
version: 1
name: test
  bad indentation here
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(false);
    expect(result.error).toBeDefined();
  });

  test('returns error for missing required fields', () => {
    const yaml = `
version: 1
name: test
id: test
# Missing defaults and modules
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(false);
  });

  test('returns error for empty modules array', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules: []
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(false);
  });

  test('returns error for invalid module ID format', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: Invalid-Module-ID
    description: Bad ID
    install:
      - echo "test"
    verify:
      - echo "test"
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(false);
    expect(result.error?.message).toContain('lowercase');
  });

  test('parses module with verified_installer', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: lang.bun
    description: Bun runtime
    verified_installer:
      tool: bun
      url: https://bun.sh/install
      runner: bash
      env: ["BUN_INSTALL=1"]
      args: []
    verify:
      - bun --version
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(true);
    expect(result.data?.modules[0].verified_installer).toBeDefined();
    expect(result.data?.modules[0].verified_installer?.tool).toBe('bun');
    expect(result.data?.modules[0].verified_installer?.url).toBe('https://bun.sh/install');
    expect(result.data?.modules[0].verified_installer?.runner).toBe('bash');
    expect(result.data?.modules[0].verified_installer?.env).toEqual(['BUN_INSTALL=1']);
  });

  test('rejects invalid verified_installer runner', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: lang.python
    description: Python
    verified_installer:
      tool: python
      runner: python
      args: []
    verify:
      - python --version
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(false);
    expect(result.error?.message).toContain('runner');
  });

  test('allows sh as valid runner', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: tools.test
    description: Test tool
    verified_installer:
      tool: test
      runner: sh
      args: ["-s"]
    verify:
      - test --version
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(true);
  });

  test('parses module with post_install_message', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: network.test
    description: Test network module
    install: ["echo install"]
    verify: ["true"]
    post_install_message: |
      Installed successfully
      Next step: run test-command
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(true);
    expect(result.data?.modules[0].post_install_message).toContain('Next step: run test-command');
  });

  test('rejects unsupported verified_installer fallback_url', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: tools.test
    description: Test tool
    verified_installer:
      tool: test
      runner: bash
      fallback_url: https://example.com/install.sh
    verify:
      - test --version
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(false);
    expect(result.error?.message).toContain('fallback_url');
    expect(result.error?.message).toContain('fail closed');
  });
});

describe('validateManifest with inline manifests', () => {
  test('detects duplicate module IDs', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: a.same
    description: First
    install: ["true"]
    verify: ["true"]
  - id: a.same
    description: Second
    install: ["true"]
    verify: ["true"]
`;
    const parseResult = parseManifestString(yaml);
    expect(parseResult.success).toBe(true);
    if (!parseResult.success || !parseResult.data) return;

    const validationResult = validateManifest(parseResult.data);
    expect(validationResult.valid).toBe(false);
    expect(validationResult.errors.some((e) => e.message.includes('Duplicate'))).toBe(true);
  });

  test('detects missing dependencies', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: a.one
    description: A
    install: ["true"]
    verify: ["true"]
    dependencies: ["nonexistent.module"]
`;
    const parseResult = parseManifestString(yaml);
    expect(parseResult.success).toBe(true);
    if (!parseResult.success || !parseResult.data) return;

    const validationResult = validateManifest(parseResult.data);
    expect(validationResult.valid).toBe(false);
    expect(validationResult.errors.some((e) => e.message.includes('which does not exist'))).toBe(
      true
    );
  });

  test('detects dependency cycles', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: a.one
    description: A
    install: ["true"]
    verify: ["true"]
    dependencies: ["b.two"]
  - id: b.two
    description: B
    install: ["true"]
    verify: ["true"]
    dependencies: ["a.one"]
`;
    const parseResult = parseManifestString(yaml);
    expect(parseResult.success).toBe(true);
    if (!parseResult.success || !parseResult.data) return;

    const validationResult = validateManifest(parseResult.data);
    expect(validationResult.valid).toBe(false);
    expect(validationResult.errors.some((e) => e.message.includes('cycle'))).toBe(true);
  });

  test('detects phase ordering violations', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: early.module
    description: Early module (phase 1)
    phase: 1
    install: ["true"]
    verify: ["true"]
    dependencies: ["late.module"]
  - id: late.module
    description: Late module (phase 5)
    phase: 5
    install: ["true"]
    verify: ["true"]
`;
    const parseResult = parseManifestString(yaml);
    expect(parseResult.success).toBe(true);
    if (!parseResult.success || !parseResult.data) return;

    const validationResult = validateManifest(parseResult.data);
    expect(validationResult.valid).toBe(false);
    // Note: This test may fail if phase validation is in parser.ts's validateManifest
    // Check both possible error messages
    const hasPhaseError = validationResult.errors.some(
      (e) => e.message.includes('phase') || e.message.includes('Phase')
    );
    expect(hasPhaseError).toBe(true);
  });
});

describe('parseManifestString with run_as field', () => {
  test('parses target_user run_as', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: lang.bun
    description: Bun
    run_as: target_user
    install: ["curl -fsSL https://bun.sh/install | bash"]
    verify: ["bun --version"]
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(true);
    expect(result.data?.modules[0].run_as).toBe('target_user');
  });

  test('parses root run_as', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: base.system
    description: Base system
    run_as: root
    install: ["apt-get update"]
    verify: ["true"]
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(true);
    expect(result.data?.modules[0].run_as).toBe('root');
  });

  test('defaults run_as to target_user', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: tools.test
    description: Test tool
    install: ["echo test"]
    verify: ["true"]
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(true);
    expect(result.data?.modules[0].run_as).toBe('target_user');
  });
});

describe('parseManifestString with tags and aliases', () => {
  test('parses tags array', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: agents.claude
    description: Claude Code
    install: ["bun install -g --trust @anthropic-ai/claude-code@latest"]
    verify: ["claude --version"]
    tags:
      - recommended
      - agent
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(true);
    expect(result.data?.modules[0].tags).toContain('recommended');
    expect(result.data?.modules[0].tags).toContain('agent');
  });

  test('parses aliases array', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: agents.claude
    description: Claude Code
    install: ["echo install"]
    verify: ["claude --version"]
    aliases:
      - cc
      - claude-code
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(true);
    expect(result.data?.modules[0].aliases).toContain('cc');
    expect(result.data?.modules[0].aliases).toContain('claude-code');
  });
});

describe('validateManifestData web metadata warnings', () => {
  const baseManifest: Manifest = {
    version: 1,
    name: 'test',
    id: 'test',
    defaults: { user: 'ubuntu', workspace_root: '/data/projects', mode: 'vibe' },
    modules: [],
  };

  test('no warnings for modules without web metadata', () => {
    const manifest: Manifest = {
      ...baseManifest,
      modules: [
        {
          id: 'base.system',
          description: 'Base system',
          run_as: 'target_user',
          optional: false,
          enabled_by_default: true,
          generated: true,
          install: ['apt-get update'],
          verify: ['curl --version'],
        },
      ],
    };
    const result = validateManifestData(manifest);
    expect(result.warnings.filter((w) => w.path.includes('.web.'))).toHaveLength(0);
  });

  test('warns when web-visible module is missing recommended fields', () => {
    const manifest: Manifest = {
      ...baseManifest,
      modules: [
        {
          id: 'tools.test',
          description: 'Test tool',
          run_as: 'target_user',
          optional: false,
          enabled_by_default: true,
          generated: true,
          install: ['echo test'],
          verify: ['true'],
          web: {
            visible: true,
          },
        },
      ],
    };
    const result = validateManifestData(manifest);
    const webWarnings = result.warnings.filter((w) => w.path.includes('.web.'));
    // Should warn for display_name, short_name, tagline, icon, color
    expect(webWarnings.length).toBe(5);
    expect(webWarnings.some((w) => w.path.includes('display_name'))).toBe(true);
    expect(webWarnings.some((w) => w.path.includes('short_name'))).toBe(true);
    expect(webWarnings.some((w) => w.path.includes('tagline'))).toBe(true);
    expect(webWarnings.some((w) => w.path.includes('icon'))).toBe(true);
    expect(webWarnings.some((w) => w.path.includes('color'))).toBe(true);
  });

  test('no warnings when all recommended web fields are present', () => {
    const manifest: Manifest = {
      ...baseManifest,
      modules: [
        {
          id: 'tools.test',
          description: 'Test tool',
          run_as: 'target_user',
          optional: false,
          enabled_by_default: true,
          generated: true,
          install: ['echo test'],
          verify: ['true'],
          web: {
            display_name: 'Test Tool',
            short_name: 'Test',
            tagline: 'A test tool',
            icon: 'wrench',
            color: '#3B82F6',
            visible: true,
          },
        },
      ],
    };
    const result = validateManifestData(manifest);
    const webWarnings = result.warnings.filter((w) => w.path.includes('.web.'));
    expect(webWarnings).toHaveLength(0);
  });

  test('no warnings when web visible is false', () => {
    const manifest: Manifest = {
      ...baseManifest,
      modules: [
        {
          id: 'tools.hidden',
          description: 'Hidden tool',
          run_as: 'target_user',
          optional: false,
          enabled_by_default: true,
          generated: true,
          install: ['echo test'],
          verify: ['true'],
          web: {
            visible: false,
          },
        },
      ],
    };
    const result = validateManifestData(manifest);
    const webWarnings = result.warnings.filter((w) => w.path.includes('.web.'));
    expect(webWarnings).toHaveLength(0);
  });

  test('does not treat quoted commands as description-only entries', () => {
    const manifest: Manifest = {
      ...baseManifest,
      modules: [
        {
          id: 'tools.quoted_command',
          description: 'Quoted command test',
          run_as: 'target_user',
          optional: false,
          enabled_by_default: true,
          generated: true,
          install: ['"${HOME}/.local/bin/demo" --install'],
          verify: ['true'],
        },
      ],
    };
    const result = validateManifestData(manifest);
    expect(result.warnings.some((w) => w.path === 'modules.tools.quoted_command.install')).toBe(
      false
    );
  });
});

describe('validateVerifiedInstallerChecksums', () => {
  test('reports manifest/checksums URL drift for verified installers', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: stack.rch
    description: Remote Compilation Helper
    install: []
    verified_installer:
      tool: rch
      url: https://example.com/custom-install.sh
      runner: bash
    verify:
      - rch --version
`;
    const parseResult = parseManifestString(yaml);
    expect(parseResult.success).toBe(true);
    if (!parseResult.success || !parseResult.data) return;

    const validationErrors = validateVerifiedInstallerChecksums(parseResult.data, {
      rch: {
        url: 'https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh',
        sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      },
    });

    expect(validationErrors).toHaveLength(1);
    expect(validationErrors[0]?.code).toBe('VERIFIED_INSTALLER_URL_MISMATCH');
  });

  test('rejects malformed verified installer checksums', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: stack.rch
    description: Remote Compilation Helper
    install: []
    verified_installer:
      tool: rch
      url: https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh
      runner: bash
    verify:
      - rch --version
`;
    const parseResult = parseManifestString(yaml);
    expect(parseResult.success).toBe(true);
    if (!parseResult.success || !parseResult.data) return;

    const validationErrors = validateVerifiedInstallerChecksums(parseResult.data, {
      rch: {
        url: 'https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh',
        sha256: 'not-a-real-sha',
      },
    });

    expect(validationErrors).toHaveLength(1);
    expect(validationErrors[0]?.code).toBe('INVALID_VERIFIED_INSTALLER_CHECKSUM');
  });
});

describe('parseManifestString with web metadata', () => {
  test('parses module with web metadata', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: tools.br
    description: Beads Rust issue tracker
    install: ["cargo install beads-rust"]
    verify: ["br --version"]
    web:
      display_name: Beads Rust
      short_name: BR
      tagline: Local-first issue tracking
      icon: git-branch
      color: "#F97316"
      cli_name: br
      visible: true
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(true);
    if (result.success && result.data) {
      expect(result.data.modules[0].web).toBeDefined();
      expect(result.data.modules[0].web?.display_name).toBe('Beads Rust');
      expect(result.data.modules[0].web?.icon).toBe('git-branch');
      expect(result.data.modules[0].web?.color).toBe('#F97316');
      expect(result.data.modules[0].web?.visible).toBe(true);
    }
  });

  test('parses module without web metadata (backwards compatible)', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: base.system
    description: Base system
    install: ["apt-get update"]
    verify: ["curl --version"]
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(true);
    if (result.success && result.data) {
      expect(result.data.modules[0].web).toBeUndefined();
    }
  });

  test('rejects module with invalid web color in YAML', () => {
    const yaml = `
version: 1
name: test
id: test
defaults:
  user: ubuntu
  workspace_root: /data
  mode: vibe
modules:
  - id: tools.test
    description: Test
    install: ["echo test"]
    verify: ["true"]
    web:
      color: "red"
`;
    const result = parseManifestString(yaml);
    expect(result.success).toBe(false);
  });
});
