/**
 * Tests: Verify all new Dicklesworthstone tools have complete manifest entries
 * Related: bead bd-bd536
 *
 * Parses the real acfs.manifest.yaml and checks each tool has:
 *   - Correct module ID and description
 *   - installed_check with run_as and command
 *   - verify commands
 *   - web metadata (display_name, tagline, icon, category_label, href, features, cli_name)
 *   - verified_installer with tool and runner
 */

import { describe, test, expect, beforeAll } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse as parseYaml } from 'yaml';
import { parseManifestFile } from './parser.js';
import { detectDependencyCycles, validateDependencyExistence } from './validate.js';
import type { Manifest, Module, VerifiedInstaller, ModuleWebMetadata } from './types.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, '../../..');
const MANIFEST_PATH = resolve(PROJECT_ROOT, 'acfs.manifest.yaml');
const CHECKSUMS_PATH = resolve(PROJECT_ROOT, 'checksums.yaml');

interface ToolExpectation {
  moduleId: string;
  cli: string;
  name: string;
  shortName: string;
  installerTool: string;
  href: string;
  installedCheckToken?: string;
  verifyToken?: string;
}

// The new tools and their expected module IDs
const NEW_TOOLS: ToolExpectation[] = [
  {
    moduleId: 'stack.rch',
    cli: 'rch',
    name: 'Remote Compilation Helper',
    shortName: 'RCH',
    installerTool: 'rch',
    href: 'https://github.com/Dicklesworthstone/remote_compilation_helper',
  },
  {
    moduleId: 'stack.process_triage',
    cli: 'pt',
    name: 'Process Triage',
    shortName: 'PT',
    installerTool: 'pt',
    href: 'https://github.com/Dicklesworthstone/process_triage',
  },
  {
    moduleId: 'stack.frankensearch',
    cli: 'fsfs',
    name: 'FrankenSearch',
    shortName: 'FSFS',
    installerTool: 'fsfs',
    href: 'https://github.com/Dicklesworthstone/frankensearch',
  },
  {
    moduleId: 'stack.storage_ballast_helper',
    cli: 'sbh',
    name: 'Storage Ballast Helper',
    shortName: 'SBH',
    installerTool: 'sbh',
    href: 'https://github.com/Dicklesworthstone/storage_ballast_helper',
  },
  {
    moduleId: 'stack.cross_agent_session_resumer',
    cli: 'casr',
    name: 'Cross-Agent Session Resumer',
    shortName: 'CASR',
    installerTool: 'casr',
    href: 'https://github.com/Dicklesworthstone/cross_agent_session_resumer',
  },
  {
    moduleId: 'stack.doodlestein_self_releaser',
    cli: 'dsr',
    name: 'Doodlestein Self-Releaser',
    shortName: 'DSR',
    installerTool: 'dsr',
    href: 'https://github.com/Dicklesworthstone/doodlestein_self_releaser',
  },
  {
    moduleId: 'stack.ru',
    cli: 'ru',
    name: 'Repo Updater',
    shortName: 'RU',
    installerTool: 'ru',
    href: 'https://github.com/Dicklesworthstone/repo_updater',
  },
  {
    moduleId: 'stack.agent_settings_backup',
    cli: 'asb',
    name: 'Agent Settings Backup',
    shortName: 'ASB',
    installerTool: 'asb',
    href: 'https://github.com/Dicklesworthstone/agent_settings_backup_script',
  },
  {
    moduleId: 'stack.pcr',
    cli: 'claude-post-compact-reminder',
    name: 'Post-Compact Reminder',
    shortName: 'PCR',
    installerTool: 'pcr',
    href: 'https://github.com/Dicklesworthstone/post_compact_reminder',
    installedCheckToken: 'claude-post-compact-reminder',
    verifyToken: 'claude-post-compact-reminder',
  },
  {
    moduleId: 'stack.eidetic_engine_cli',
    cli: 'ee',
    name: 'Eidetic Engine',
    shortName: 'EE',
    installerTool: 'ee',
    href: 'https://github.com/Dicklesworthstone/eidetic_engine_cli',
  },
  {
    moduleId: 'stack.franken_markdown',
    cli: 'fmd',
    name: 'Franken Markdown',
    shortName: 'FMD',
    installerTool: 'fmd',
    href: 'https://github.com/Dicklesworthstone/franken_markdown',
  },
  {
    moduleId: 'stack.pi_agent_rust',
    cli: 'pi',
    name: 'Pi Agent (Rust)',
    shortName: 'PI',
    installerTool: 'pi',
    href: 'https://github.com/Dicklesworthstone/pi_agent_rust',
  },
  {
    moduleId: 'stack.power_failure_resumer',
    cli: 'pfr',
    name: 'Power Failure Resumer',
    shortName: 'PFR',
    installerTool: 'pfr',
    href: 'https://github.com/Dicklesworthstone/power_failure_resumer',
  },
] as const;

interface ChecksumsFile {
  installers?: Record<string, { url?: string; sha256?: string }>;
}

function getModuleOrThrow(manifest: Manifest, moduleId: string): Module {
  const mod = manifest.modules.find((module) => module.id === moduleId);
  expect(mod).toBeDefined();
  if (!mod) {
    throw new Error(`Missing module ${moduleId}`);
  }
  return mod;
}

function getWebOrThrow(module: Module, moduleId: string): ModuleWebMetadata {
  expect(module.web).toBeDefined();
  if (!module.web) {
    throw new Error(`Missing web metadata for ${moduleId}`);
  }
  return module.web;
}

function getVerifiedInstallerOrThrow(module: Module, moduleId: string): VerifiedInstaller {
  expect(module.verified_installer).toBeDefined();
  if (!module.verified_installer) {
    throw new Error(`Missing verified_installer for ${moduleId}`);
  }
  return module.verified_installer;
}

function syntaxCheckBash(script: string): void {
  const result = spawnSync('bash', ['-n', '-c', script], { encoding: 'utf8' });
  expect(result.status).toBe(0);
}

describe('New tool manifest entries', () => {
  let manifest: Manifest;
  let checksums: ChecksumsFile;
  let moduleIds: Set<string>;

  beforeAll(() => {
    const result = parseManifestFile(MANIFEST_PATH);
    expect(result.success).toBe(true);
    if (!result.success || !result.data) {
      throw new Error(`Failed to parse manifest: ${result.error?.message}`);
    }
    manifest = result.data;
    moduleIds = new Set(manifest.modules.map((module) => module.id));
    checksums = parseYaml(readFileSync(CHECKSUMS_PATH, 'utf-8')) as ChecksumsFile;
  });

  test('all new tools exist in manifest', () => {
    for (const tool of NEW_TOOLS) {
      expect(moduleIds.has(tool.moduleId)).toBe(true);
    }
  });

  test('new tool coverage target has no dependency errors or cycles', () => {
    expect(validateDependencyExistence(manifest)).toHaveLength(0);
    expect(detectDependencyCycles(manifest)).toHaveLength(0);
  });

  for (const tool of NEW_TOOLS) {
    describe(`${tool.cli} (${tool.moduleId})`, () => {
      test('has expected stack identity', () => {
        const mod = getModuleOrThrow(manifest, tool.moduleId);
        expect(mod.category).toBe('stack');
        expect(mod.phase).toBe(9);
        expect(mod.description.trim().length).toBeGreaterThan(10);
      });

      test('has installed_check with valid bash syntax', () => {
        const mod = getModuleOrThrow(manifest, tool.moduleId);
        expect(mod.installed_check).toBeDefined();
        expect(mod.installed_check?.run_as).toBeTruthy();
        expect(mod.installed_check?.command.trim().length).toBeGreaterThan(0);

        const expectedToken = tool.installedCheckToken ?? tool.cli;
        expect(mod.installed_check?.command).toContain(expectedToken);
        syntaxCheckBash(mod.installed_check?.command ?? '');
      });

      test('has verify commands that mention the tool and parse as bash', () => {
        const mod = getModuleOrThrow(manifest, tool.moduleId);
        expect(mod.verify).toBeInstanceOf(Array);
        expect(mod.verify.length).toBeGreaterThan(0);
        const expectedToken = tool.verifyToken ?? tool.cli;
        for (const command of mod.verify) {
          expect(command).toContain(expectedToken);
          syntaxCheckBash(command);
        }
      });

      test('has web metadata that is complete and well-formed', () => {
        const mod = getModuleOrThrow(manifest, tool.moduleId);
        const web = getWebOrThrow(mod, tool.moduleId);

        expect(web.display_name).toBe(tool.name);
        expect(web.short_name).toBe(tool.shortName);
        expect(web.tagline).toBeTruthy();
        expect(web.tagline?.length).toBeLessThan(100);
        expect(web.icon).toMatch(/^[a-z][a-z0-9-]*$/);
        expect(web.color).toMatch(/^#[0-9a-fA-F]{6}$/);
        expect(web.features).toBeInstanceOf(Array);
        expect(web.features?.length).toBeGreaterThanOrEqual(3);
        expect(web.tech_stack).toBeInstanceOf(Array);
        expect(web.tech_stack?.length).toBeGreaterThan(0);
        expect(web.cli_name).toBe(tool.cli);
        expect(web.command_example).toBeTruthy();
        expect(web.href).toBe(tool.href);
        expect(web.href?.startsWith('https://github.com/Dicklesworthstone/')).toBe(true);
      });

      test('depends only on modules that exist', () => {
        const mod = getModuleOrThrow(manifest, tool.moduleId);
        const missingDependencies = (mod.dependencies ?? []).filter((dep) => !moduleIds.has(dep));
        expect(missingDependencies).toEqual([]);
      });

      test('has verified_installer aligned with checksums.yaml', () => {
        const mod = getModuleOrThrow(manifest, tool.moduleId);
        const verifiedInstaller = getVerifiedInstallerOrThrow(mod, tool.moduleId);
        const checksumEntry = checksums.installers?.[tool.installerTool];

        expect(verifiedInstaller.tool).toBe(tool.installerTool);
        expect(['bash', 'sh']).toContain(verifiedInstaller.runner);
        expect(verifiedInstaller.url).toBeTruthy();
        expect(checksumEntry).toBeDefined();
        expect(checksumEntry?.url).toBe(verifiedInstaller.url);
        expect(checksumEntry?.sha256).toMatch(/^[a-f0-9]{64}$/i);
      });
    });
  }
});
