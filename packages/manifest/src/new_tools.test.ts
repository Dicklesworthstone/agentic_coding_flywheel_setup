/**
 * Tests: Verify all 9 new Dicklesworthstone tools have complete manifest entries
 * Related: bead bd-005f0
 *
 * Parses the real acfs.manifest.yaml and checks each tool has:
 *   - Correct module ID and description
 *   - installed_check with run_as and command
 *   - verify commands
 *   - web metadata (display_name, tagline, icon, category_label, href, features, cli_name)
 *   - verified_installer with tool and runner
 */

import { describe, test, expect, beforeAll } from 'bun:test';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseManifestFile } from './parser.js';
import type { Manifest } from './types.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, '../../..');
const MANIFEST_PATH = resolve(PROJECT_ROOT, 'acfs.manifest.yaml');

// The 9 new tools and their expected module IDs
const NEW_TOOLS = [
  { moduleId: 'stack.rch', cli: 'rch', name: 'Remote Compilation Helper' },
  { moduleId: 'stack.process_triage', cli: 'pt', name: 'Process Triage' },
  { moduleId: 'stack.frankensearch', cli: 'fsfs', name: 'FrankenSearch' },
  { moduleId: 'stack.storage_ballast_helper', cli: 'sbh', name: 'Storage Ballast Helper' },
  { moduleId: 'stack.cross_agent_session_resumer', cli: 'casr', name: 'Cross-Agent Session Resumer' },
  { moduleId: 'stack.doodlestein_self_releaser', cli: 'dsr', name: 'Doodlestein Self-Releaser' },
  { moduleId: 'stack.ru', cli: 'ru', name: 'Repo Updater' },
  { moduleId: 'stack.agent_settings_backup', cli: 'asb', name: 'Agent Settings Backup' },
  { moduleId: 'stack.pcr', cli: 'pcr', name: 'Post-Compact Reminder' },
] as const;

// Tools that use git-clone install instead of verified_installer
const NO_VERIFIED_INSTALLER = new Set(['stack.doodlestein_self_releaser']);

// Tools whose installed_check command doesn't contain the CLI name directly
const CUSTOM_INSTALLED_CHECK: Record<string, string> = {
  'stack.pcr': 'claude-post-compact-reminder',
};

describe('New tool manifest entries', () => {
  let manifest: Manifest;

  beforeAll(() => {
    const result = parseManifestFile(MANIFEST_PATH);
    expect(result.success).toBe(true);
    if (!result.success || !result.data) {
      throw new Error(`Failed to parse manifest: ${result.error?.message}`);
    }
    manifest = result.data;
  });

  test('all 9 new tools exist in manifest', () => {
    const moduleIds = new Set(manifest.modules.map((m) => m.id));
    for (const tool of NEW_TOOLS) {
      expect(moduleIds.has(tool.moduleId)).toBe(true);
    }
  });

  for (const tool of NEW_TOOLS) {
    describe(`${tool.cli} (${tool.moduleId})`, () => {
      test('has description', () => {
        const mod = manifest.modules.find((m) => m.id === tool.moduleId);
        expect(mod).toBeDefined();
        expect(mod!.description).toBeTruthy();
        expect(mod!.description.length).toBeGreaterThan(10);
      });

      test('has installed_check', () => {
        const mod = manifest.modules.find((m) => m.id === tool.moduleId)!;
        expect(mod.installed_check).toBeDefined();
        expect(mod.installed_check!.run_as).toBeTruthy();
        expect(mod.installed_check!.command).toBeTruthy();
        const expectedStr = CUSTOM_INSTALLED_CHECK[tool.moduleId] ?? tool.cli;
        expect(mod.installed_check!.command).toContain(expectedStr);
      });

      test('has verify commands', () => {
        const mod = manifest.modules.find((m) => m.id === tool.moduleId)!;
        expect(mod.verify).toBeInstanceOf(Array);
        expect(mod.verify.length).toBeGreaterThan(0);
      });

      test('has verified_installer or install steps', () => {
        const mod = manifest.modules.find((m) => m.id === tool.moduleId)!;
        if (NO_VERIFIED_INSTALLER.has(tool.moduleId)) {
          // DSR uses git-clone install instead of verified_installer
          expect(mod.install).toBeInstanceOf(Array);
          expect(mod.install!.length).toBeGreaterThan(0);
        } else {
          expect(mod.verified_installer).toBeDefined();
          expect(mod.verified_installer!.tool).toBeTruthy();
          expect(['bash', 'sh']).toContain(mod.verified_installer!.runner);
        }
      });

      test('has web metadata', () => {
        const mod = manifest.modules.find((m) => m.id === tool.moduleId)!;
        expect(mod.web).toBeDefined();
        expect(mod.web!.display_name).toBeTruthy();
        expect(mod.web!.tagline).toBeTruthy();
        expect(mod.web!.cli_name).toBe(tool.cli);
      });

      test('has web.features list', () => {
        const mod = manifest.modules.find((m) => m.id === tool.moduleId)!;
        expect(mod.web!.features).toBeInstanceOf(Array);
        expect(mod.web!.features!.length).toBeGreaterThan(0);
      });

      test('has web.href for tool page', () => {
        const mod = manifest.modules.find((m) => m.id === tool.moduleId)!;
        expect(mod.web!.href).toBeTruthy();
      });
    });
  }
});
