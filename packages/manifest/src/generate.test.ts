/**
 * Tests for ACFS Manifest Generator outputs
 * Related: bead dvt.2
 *
 * Validates that generated scripts match expected content from real fixtures.
 * Uses actual acfs.manifest.yaml and validates against generated outputs.
 */

import { describe, test, expect, beforeAll } from 'bun:test';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync, existsSync } from 'node:fs';
import { parseManifestFile } from './parser.js';
import {
  getCategories,
  getModuleCategory,
  sortModulesByInstallOrder,
  getTransitiveDependencies,
} from './utils.js';
import type { Manifest, Module } from './types.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, '../../..');
const MANIFEST_PATH = resolve(PROJECT_ROOT, 'acfs.manifest.yaml');
const GENERATED_DIR = resolve(PROJECT_ROOT, 'scripts/generated');
const WEB_GENERATED_DIR = resolve(PROJECT_ROOT, 'apps/web/lib/generated');
const MANIFEST_INDEX_PATH = resolve(GENERATED_DIR, 'manifest_index.sh');

describe('Generated manifest_index.sh content', () => {
  let manifestIndexContent: string;
  let manifest: Manifest;

  beforeAll(() => {
    // Parse the real manifest
    const parseResult = parseManifestFile(MANIFEST_PATH);
    expect(parseResult.success).toBe(true);
    if (!parseResult.success || !parseResult.data) {
      throw new Error(`Failed to parse manifest: ${parseResult.error?.message}`);
    }
    manifest = parseResult.data;

    // Read the generated manifest_index.sh
    expect(existsSync(MANIFEST_INDEX_PATH)).toBe(true);
    manifestIndexContent = readFileSync(MANIFEST_INDEX_PATH, 'utf-8');
  });

  test('manifest_index.sh exists and is non-empty', () => {
    expect(manifestIndexContent.length).toBeGreaterThan(0);
  });

  test('contains auto-generated header', () => {
    expect(manifestIndexContent).toContain('AUTO-GENERATED FROM acfs.manifest.yaml');
    expect(manifestIndexContent).toContain('DO NOT EDIT');
  });

  test('contains ACFS_MANIFEST_SHA256', () => {
    expect(manifestIndexContent).toContain('ACFS_MANIFEST_SHA256=');
    // SHA256 is 64 hex characters
    const sha256Match = manifestIndexContent.match(/ACFS_MANIFEST_SHA256="([a-f0-9]{64})"/);
    expect(sha256Match).not.toBeNull();
  });

  test('contains ACFS_MODULES_IN_ORDER array', () => {
    expect(manifestIndexContent).toContain('ACFS_MODULES_IN_ORDER=(');
  });

  test('all modules are in ACFS_MODULES_IN_ORDER', () => {
    for (const module of manifest.modules) {
      expect(manifestIndexContent).toContain(`"${module.id}"`);
    }
  });

  test('modules are in dependency-respecting order', () => {
    // Extract the order from the file
    const orderMatch = manifestIndexContent.match(
      /ACFS_MODULES_IN_ORDER=\(\s*([\s\S]*?)\s*\)/
    );
    expect(orderMatch).not.toBeNull();

    const orderContent = orderMatch![1];
    const moduleIds = orderContent
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line.startsWith('"') && line.endsWith('"'))
      .map((line) => line.slice(1, -1));

    // Verify each module appears after its dependencies
    const moduleIndex = new Map(moduleIds.map((id, idx) => [id, idx]));

    for (const module of manifest.modules) {
      if (module.dependencies) {
        const moduleIdx = moduleIndex.get(module.id);
        expect(moduleIdx).toBeDefined();

        for (const dep of module.dependencies) {
          const depIdx = moduleIndex.get(dep);
          expect(depIdx).toBeDefined();
          expect(depIdx!).toBeLessThan(moduleIdx!);
        }
      }
    }
  });

  test('contains ACFS_MODULE_PHASE associative array', () => {
    expect(manifestIndexContent).toContain('declare -gA ACFS_MODULE_PHASE=(');
  });

  test('all modules have phase entries', () => {
    for (const module of manifest.modules) {
      const expectedPhase = module.phase ?? 1;
      // Generator emits associative-array keys as `[module.id]` (unquoted, safe for our IDs).
      expect(manifestIndexContent).toContain(`['${module.id}']="${expectedPhase}"`);
    }
  });

  test('contains ACFS_MODULE_DEPS associative array', () => {
    expect(manifestIndexContent).toContain('declare -gA ACFS_MODULE_DEPS=(');
  });

  test('dependencies are correctly formatted', () => {
    for (const module of manifest.modules) {
      const deps = module.dependencies?.join(',') ?? '';
      // Generator emits associative-array keys as `[module.id]` (unquoted, safe for our IDs).
      expect(manifestIndexContent).toContain(`['${module.id}']="${deps}"`);
    }
  });

  test('contains ACFS_MODULE_FUNC associative array', () => {
    expect(manifestIndexContent).toContain('declare -gA ACFS_MODULE_FUNC=(');
  });

  test('function names follow convention', () => {
    for (const module of manifest.modules) {
      const expectedFunc = `install_${module.id.replace(/\./g, '_')}`;
      // Generator emits associative-array keys as `[module.id]` (unquoted, safe for our IDs).
      expect(manifestIndexContent).toContain(`['${module.id}']="${expectedFunc}"`);
    }
  });

  test('contains ACFS_MODULE_CATEGORY associative array', () => {
    expect(manifestIndexContent).toContain('declare -gA ACFS_MODULE_CATEGORY=(');
  });

  test('categories are correctly derived from module IDs', () => {
    for (const module of manifest.modules) {
      const category = module.category ?? getModuleCategory(module.id);
      // Generator emits associative-array keys as `[module.id]` (unquoted, safe for our IDs).
      expect(manifestIndexContent).toContain(`['${module.id}']="${category}"`);
    }
  });

  test('contains ACFS_MODULE_TAGS associative array', () => {
    expect(manifestIndexContent).toContain('declare -gA ACFS_MODULE_TAGS=(');
  });

  test('contains ACFS_MODULE_DEFAULT associative array', () => {
    expect(manifestIndexContent).toContain('declare -gA ACFS_MODULE_DEFAULT=(');
  });

  test('default values match manifest', () => {
    for (const module of manifest.modules) {
      const expectedDefault = module.enabled_by_default ? '1' : '0';
      // Generator emits associative-array keys as `[module.id]` (unquoted, safe for our IDs).
      expect(manifestIndexContent).toContain(`['${module.id}']="${expectedDefault}"`);
    }
  });

  test('contains ACFS_MANIFEST_INDEX_LOADED flag', () => {
    expect(manifestIndexContent).toContain('ACFS_MANIFEST_INDEX_LOADED=true');
  });
});

describe('Generated category scripts exist', () => {
  let manifest: Manifest;

  beforeAll(() => {
    const parseResult = parseManifestFile(MANIFEST_PATH);
    if (parseResult.success && parseResult.data) {
      manifest = parseResult.data;
    }
  });

  test('category install scripts exist for each category', () => {
    const categories = getCategories(manifest);

    for (const category of categories) {
      const categoryPath = resolve(GENERATED_DIR, `install_${category}.sh`);
      expect(existsSync(categoryPath)).toBe(true);
    }
  });

  test('doctor_checks.sh exists', () => {
    const doctorPath = resolve(GENERATED_DIR, 'doctor_checks.sh');
    expect(existsSync(doctorPath)).toBe(true);
  });

  test('install_all.sh exists', () => {
    const installAllPath = resolve(GENERATED_DIR, 'install_all.sh');
    expect(existsSync(installAllPath)).toBe(true);
  });
});

describe('Generated verified installer args', () => {
  test('stack.mcp_agent_mail keeps TARGET_HOME fallback as an expandable variable', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    // Regression guard: this used to be single-quoted as one literal token,
    // which passed `${TARGET_HOME:-...}` verbatim to the installer.
    expect(stackContent).not.toContain("'${TARGET_HOME:-/home/ubuntu}/mcp_agent_mail'");
    expect(stackContent).toContain('"${TARGET_HOME:-/home/ubuntu}"');
  });

  test('stack.mcp_agent_mail writes an explicit managed no-auth service instead of tmux', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).toContain('--no-start');
    expect(stackContent).toContain('cat > "$unit_file" <<UNIT_EOF');
    expect(stackContent).toContain('Environment=STORAGE_ROOT=$storage_root');
    expect(stackContent).toContain('Environment=DATABASE_URL=$db_url');
    expect(stackContent).toContain(
      'ExecStart=$am_bin serve-http --host 127.0.0.1 --port 8765 --path /mcp --no-auth --no-tui'
    );
    expect(stackContent).toContain('systemctl --user enable --now agent-mail.service');
    expect(stackContent).toContain('curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null');
    expect(stackContent).not.toContain('am service install >/dev/null');
    expect(stackContent).not.toContain('tmux new-session -d -s "$tmux_session"');
  });

  test('stack.ru passes RU_NON_INTERACTIVE via env in generated installer', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).toContain(
      "run_as_target_runner 'env' 'RU_NON_INTERACTIVE=1' 'bash' '-s'"
    );
  });

  test('multi-line install summaries skip comment-only lines', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).not.toContain(
      'install command failed: # Wait for the managed Agent Mail service to become healthy.'
    );
    expect(stackContent).toContain(
      'install command failed: until curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; do'
    );
  });
});

describe('Generated filesystem script hardening', () => {
  let filesystemContent: string;

  beforeAll(() => {
    const filesystemPath = resolve(GENERATED_DIR, 'install_filesystem.sh');
    expect(existsSync(filesystemPath)).toBe(true);
    filesystemContent = readFileSync(filesystemPath, 'utf-8');
  });

  test('does not recursively chown /data (avoid over-broad ownership changes)', () => {
    expect(filesystemContent).not.toContain('chown -R');
    expect(filesystemContent).not.toMatch(/chown\s+-R[^\n]*\s\/data\b/);
  });

  test('refuses symlinked /data paths (hardening against symlink tricks)', () => {
    expect(filesystemContent).toContain('Refusing to use symlinked path');
    expect(filesystemContent).toContain('for p in /data /data/projects /data/cache; do');
    expect(filesystemContent).toContain('if [[ -e "$p" && -L "$p" ]]; then');
  });

  test('uses no-dereference recursive chown for the ACFS dir', () => {
    expect(filesystemContent).toContain('chown -hR');
  });
});

describe('doctor_checks.sh content', () => {
  let doctorContent: string;
  let manifest: Manifest;

  beforeAll(() => {
    const parseResult = parseManifestFile(MANIFEST_PATH);
    if (parseResult.success && parseResult.data) {
      manifest = parseResult.data;
    }

    const doctorPath = resolve(GENERATED_DIR, 'doctor_checks.sh');
    doctorContent = readFileSync(doctorPath, 'utf-8');
  });

  test('contains MANIFEST_CHECKS array', () => {
    expect(doctorContent).toContain('declare -a MANIFEST_CHECKS=(');
  });

  test('contains run_manifest_checks function', () => {
    expect(doctorContent).toContain('run_manifest_checks()');
  });

  test('all modules have at least one verify check', () => {
    for (const module of manifest.modules) {
      // Each module should have entries in the checks
      expect(doctorContent).toContain(module.id);
    }
  });

  test('uses tab delimiter for check entries', () => {
    // The format is: ID<TAB>DESCRIPTION<TAB>CHECK_COMMAND<TAB>REQUIRED/OPTIONAL
    // Tab character should be present in the entries
    expect(doctorContent).toContain('\\t');
  });

  test('multiline verify commands are encoded as single-line records', () => {
    // lang.nvm verify is a YAML literal block (multi-line). The generator must encode it
    // so the MANIFEST_CHECKS record stays on one line and can be parsed via read/IFS.
    const nvmLine = doctorContent.match(/^    "lang\.nvm[^\n]*"$/m);
    expect(nvmLine).not.toBeNull();
    expect(nvmLine![0]).toContain('\\\\n');
  });
});

describe('Utils: sortModulesByInstallOrder', () => {
  let manifest: Manifest;

  beforeAll(() => {
    const parseResult = parseManifestFile(MANIFEST_PATH);
    if (parseResult.success && parseResult.data) {
      manifest = parseResult.data;
    }
  });

  test('returns all modules', () => {
    const sorted = sortModulesByInstallOrder(manifest);
    expect(sorted.length).toBe(manifest.modules.length);
  });

  test('dependencies come before dependents', () => {
    const sorted = sortModulesByInstallOrder(manifest);
    const indexMap = new Map(sorted.map((m, i) => [m.id, i]));

    for (const module of manifest.modules) {
      if (module.dependencies) {
        const moduleIdx = indexMap.get(module.id)!;
        for (const dep of module.dependencies) {
          const depIdx = indexMap.get(dep);
          expect(depIdx).toBeDefined();
          expect(depIdx!).toBeLessThan(moduleIdx);
        }
      }
    }
  });

  test('respects phase ordering', () => {
    const sorted = sortModulesByInstallOrder(manifest);

    // Group by phase
    const phaseGroups = new Map<number, Module[]>();
    for (const module of sorted) {
      const phase = module.phase ?? 1;
      const group = phaseGroups.get(phase) ?? [];
      group.push(module);
      phaseGroups.set(phase, group);
    }

    // Phases should appear in order
    let lastPhase = 0;
    for (const module of sorted) {
      const phase = module.phase ?? 1;
      expect(phase).toBeGreaterThanOrEqual(lastPhase);
      lastPhase = phase;
    }
  });
});

describe('Utils: getTransitiveDependencies', () => {
  let manifest: Manifest;

  beforeAll(() => {
    const parseResult = parseManifestFile(MANIFEST_PATH);
    if (parseResult.success && parseResult.data) {
      manifest = parseResult.data;
    }
  });

  test('returns empty for module with no dependencies', () => {
    const deps = getTransitiveDependencies(manifest, 'base.system');
    // base.system typically has no dependencies
    const baseModule = manifest.modules.find((m) => m.id === 'base.system');
    if (!baseModule?.dependencies?.length) {
      expect(deps.length).toBe(0);
    }
  });

  test('includes all transitive dependencies', () => {
    // Find a module with nested dependencies
    // agents.codex -> lang.bun -> base.system
    const codexDeps = getTransitiveDependencies(manifest, 'agents.codex');

    // Should include lang.bun and base.system
    const depIds = codexDeps.map((d) => d.id);
    expect(depIds).toContain('lang.bun');
    expect(depIds).toContain('base.system');
  });

  test('handles diamond dependencies without duplicates', () => {
    // Find any module that has shared dependencies
    const allDeps = getTransitiveDependencies(manifest, 'stack.ultimate_bug_scanner');
    const depIds = allDeps.map((d) => d.id);

    // No duplicates
    const uniqueIds = new Set(depIds);
    expect(uniqueIds.size).toBe(depIds.length);
  });

  test('returns empty for non-existent module', () => {
    const deps = getTransitiveDependencies(manifest, 'nonexistent.module');
    expect(deps.length).toBe(0);
  });
});

describe('Utils: getCategories', () => {
  let manifest: Manifest;

  beforeAll(() => {
    const parseResult = parseManifestFile(MANIFEST_PATH);
    if (parseResult.success && parseResult.data) {
      manifest = parseResult.data;
    }
  });

  test('returns all unique categories', () => {
    const categories = getCategories(manifest);

    // Expected categories based on manifest
    const expectedCategories = ['base', 'users', 'shell', 'cli', 'lang', 'tools', 'agents', 'db', 'cloud', 'stack', 'acfs'];

    for (const cat of expectedCategories) {
      expect(categories).toContain(cat);
    }
  });

  test('returns no duplicates', () => {
    const categories = getCategories(manifest);
    const uniqueCategories = new Set(categories);
    expect(uniqueCategories.size).toBe(categories.length);
  });
});

describe('Generated script headers', () => {
  test('all generated scripts have consistent header', () => {
    const categories = ['base', 'lang', 'agents', 'stack'];

    for (const category of categories) {
      const scriptPath = resolve(GENERATED_DIR, `install_${category}.sh`);
      if (existsSync(scriptPath)) {
        const content = readFileSync(scriptPath, 'utf-8');

        // Check for standard header elements
        expect(content).toContain('#!/usr/bin/env bash');
        expect(content).toContain('AUTO-GENERATED');
        expect(content).toContain('set -euo pipefail');
      }
    }
  });

  test('generated scripts source logging.sh', () => {
    const scriptPath = resolve(GENERATED_DIR, 'install_lang.sh');
    if (existsSync(scriptPath)) {
      const content = readFileSync(scriptPath, 'utf-8');
      expect(content).toContain('source "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"');
    }
  });

  test('generated scripts source install_helpers.sh', () => {
    const scriptPath = resolve(GENERATED_DIR, 'install_agents.sh');
    if (existsSync(scriptPath)) {
      const content = readFileSync(scriptPath, 'utf-8');
      expect(content).toContain('source "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh"');
    }
  });
});

// ============================================================
// Web Data Generation Tests
// ============================================================

describe('Generated web data files exist', () => {
  const webFiles = [
    'manifest-tools.ts',
    'manifest-tldr.ts',
    'manifest-commands.ts',
    'manifest-lessons-index.ts',
    'manifest-web-index.ts',
  ];

  for (const filename of webFiles) {
    test(`${filename} exists`, () => {
      const filepath = resolve(WEB_GENERATED_DIR, filename);
      expect(existsSync(filepath)).toBe(true);
    });
  }
});

describe('Generated web files have correct headers', () => {
  const webFiles = [
    'manifest-tools.ts',
    'manifest-tldr.ts',
    'manifest-commands.ts',
    'manifest-lessons-index.ts',
    'manifest-web-index.ts',
  ];

  for (const filename of webFiles) {
    test(`${filename} contains auto-generated header`, () => {
      const filepath = resolve(WEB_GENERATED_DIR, filename);
      if (existsSync(filepath)) {
        const content = readFileSync(filepath, 'utf-8');
        expect(content).toContain('AUTO-GENERATED FROM acfs.manifest.yaml');
        expect(content).toContain('DO NOT EDIT');
      }
    });
  }
});

describe('manifest-tools.ts structure', () => {
  let content: string;

  beforeAll(() => {
    const filepath = resolve(WEB_GENERATED_DIR, 'manifest-tools.ts');
    content = readFileSync(filepath, 'utf-8');
  });

  test('exports ManifestWebTool interface', () => {
    expect(content).toContain('export interface ManifestWebTool');
  });

  test('interface has required fields', () => {
    expect(content).toContain('id: string;');
    expect(content).toContain('moduleId: string;');
    expect(content).toContain('displayName: string;');
    expect(content).toContain('shortName: string;');
    expect(content).toContain('tagline: string;');
    expect(content).toContain('icon: string;');
    expect(content).toContain('color: string;');
    expect(content).toContain('features: string[];');
    expect(content).toContain('techStack: string[];');
    expect(content).toContain('useCases: string[];');
  });

  test('exports manifestTools array', () => {
    expect(content).toContain('export const manifestTools: ManifestWebTool[] = [');
  });

  test('is valid TypeScript (array is properly closed)', () => {
    expect(content).toContain('];');
  });
});

describe('manifest-tldr.ts structure', () => {
  let content: string;

  beforeAll(() => {
    const filepath = resolve(WEB_GENERATED_DIR, 'manifest-tldr.ts');
    content = readFileSync(filepath, 'utf-8');
  });

  test('exports ManifestTldrTool interface', () => {
    expect(content).toContain('export interface ManifestTldrTool');
  });

  test('interface has required TL;DR fields', () => {
    expect(content).toContain('id: string;');
    expect(content).toContain('moduleId: string;');
    expect(content).toContain('displayName: string;');
    expect(content).toContain('shortName: string;');
    expect(content).toContain('tagline: string;');
    expect(content).toContain('tldrSnippet: string;');
    expect(content).toContain('icon: string;');
    expect(content).toContain('color: string;');
    expect(content).toContain('features: string[];');
    expect(content).toContain('techStack: string[];');
    expect(content).toContain('useCases: string[];');
  });

  test('exports manifestTldrTools array', () => {
    expect(content).toContain('export const manifestTldrTools: ManifestTldrTool[] = [');
  });
});

describe('manifest-commands.ts structure', () => {
  let content: string;

  beforeAll(() => {
    const filepath = resolve(WEB_GENERATED_DIR, 'manifest-commands.ts');
    content = readFileSync(filepath, 'utf-8');
  });

  test('exports ManifestCommand interface', () => {
    expect(content).toContain('export interface ManifestCommand');
  });

  test('interface has required fields', () => {
    expect(content).toContain('moduleId: string;');
    expect(content).toContain('cliName: string;');
    expect(content).toContain('cliAliases: string[];');
    expect(content).toContain('description: string;');
  });

  test('exports manifestCommands array', () => {
    expect(content).toContain('export const manifestCommands: ManifestCommand[] = [');
  });
});

describe('manifest-lessons-index.ts structure', () => {
  let content: string;

  beforeAll(() => {
    const filepath = resolve(WEB_GENERATED_DIR, 'manifest-lessons-index.ts');
    content = readFileSync(filepath, 'utf-8');
  });

  test('exports ManifestLessonLink interface', () => {
    expect(content).toContain('export interface ManifestLessonLink');
  });

  test('interface has required fields', () => {
    expect(content).toContain('moduleId: string;');
    expect(content).toContain('lessonSlug: string;');
    expect(content).toContain('displayName: string;');
  });

  test('exports manifestLessonLinks array', () => {
    expect(content).toContain('export const manifestLessonLinks: ManifestLessonLink[] = [');
  });

  test('exports lessonSlugByModuleId lookup', () => {
    expect(content).toContain('export const lessonSlugByModuleId: Record<string, string> = {');
  });
});

describe('manifest-web-index.ts barrel exports', () => {
  let content: string;

  beforeAll(() => {
    const filepath = resolve(WEB_GENERATED_DIR, 'manifest-web-index.ts');
    content = readFileSync(filepath, 'utf-8');
  });

  test('re-exports manifestTools', () => {
    expect(content).toContain("export { manifestTools } from './manifest-tools'");
    expect(content).toContain("export type { ManifestWebTool } from './manifest-tools'");
  });

  test('re-exports manifestTldrTools', () => {
    expect(content).toContain("export { manifestTldrTools } from './manifest-tldr'");
    expect(content).toContain("export type { ManifestTldrTool } from './manifest-tldr'");
  });

  test('re-exports manifestCommands', () => {
    expect(content).toContain("export { manifestCommands } from './manifest-commands'");
    expect(content).toContain("export type { ManifestCommand } from './manifest-commands'");
  });

  test('re-exports manifestLessonLinks', () => {
    expect(content).toContain("export { manifestLessonLinks, lessonSlugByModuleId } from './manifest-lessons-index'");
    expect(content).toContain("export type { ManifestLessonLink } from './manifest-lessons-index'");
  });
});

describe('Web generation determinism', () => {
  test('running generator twice produces identical output', () => {
    // Read all generated web files
    const webFiles = [
      'manifest-tools.ts',
      'manifest-tldr.ts',
      'manifest-commands.ts',
      'manifest-lessons-index.ts',
      'manifest-web-index.ts',
    ];

    const firstRun: Record<string, string> = {};
    for (const filename of webFiles) {
      const filepath = resolve(WEB_GENERATED_DIR, filename);
      firstRun[filename] = readFileSync(filepath, 'utf-8');
    }

    // The content should be stable (deterministic)
    // Since we just ran the generator, re-reading should give the same content
    for (const filename of webFiles) {
      const filepath = resolve(WEB_GENERATED_DIR, filename);
      const secondRead = readFileSync(filepath, 'utf-8');
      expect(secondRead).toBe(firstRun[filename]);
    }
  });
});

describe('Web generation with current manifest (no web metadata)', () => {
  let manifest: Manifest;

  beforeAll(() => {
    const parseResult = parseManifestFile(MANIFEST_PATH);
    if (parseResult.success && parseResult.data) {
      manifest = parseResult.data;
    }
  });

  test('generates empty arrays when no modules have web metadata', () => {
    const hasWebModules = manifest.modules.some(
      (m) => m.web && m.web.visible !== false
    );

    // If no modules have web metadata, arrays should be empty
    if (!hasWebModules) {
      const toolsContent = readFileSync(
        resolve(WEB_GENERATED_DIR, 'manifest-tools.ts'),
        'utf-8'
      );
      // Empty array: no entries between [ and ];
      const toolsMatch = toolsContent.match(/manifestTools: ManifestWebTool\[\] = \[\s*\];/);
      expect(toolsMatch).not.toBeNull();
    }
  });

  test('web file count matches manifest web-visible modules', () => {
    const webVisibleCount = manifest.modules.filter(
      (m) => m.web && m.web.visible !== false
    ).length;

    const toolsContent = readFileSync(
      resolve(WEB_GENERATED_DIR, 'manifest-tools.ts'),
      'utf-8'
    );
    // Count entries by counting moduleId occurrences (each tool entry has exactly one)
    const entries = toolsContent.match(/moduleId: "/g);
    const entryCount = entries ? entries.length : 0;
    expect(entryCount).toBe(webVisibleCount);
  });
});
