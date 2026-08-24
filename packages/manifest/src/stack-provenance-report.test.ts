import { describe, expect, test } from 'bun:test';
import {
  buildStackProvenanceReport,
  type ChecksumsFile,
  type GitHubReleaseFixture,
} from './stack-provenance-report.js';
import type { Manifest, Module } from './types.js';

const HASH_A = 'a'.repeat(64);
const HASH_B = 'b'.repeat(64);
const SNAPSHOT_TIME = '2026-01-15T00:00:00Z';

function installerUrl(repo: string): string {
  return `https://raw.githubusercontent.com/Dicklesworthstone/${repo}/main/install.sh`;
}

function stackModule(repo: string, tool: string, id = `stack.${tool}`): Module {
  const url = installerUrl(repo);
  return {
    id,
    description: `${tool} stack tool`,
    category: 'stack',
    run_as: 'target_user',
    verified_installer: {
      tool,
      url,
      runner: 'bash',
      args: [],
      env: [],
    },
    optional: false,
    enabled_by_default: true,
    installed_check: {
      run_as: 'target_user',
      command: `command -v ${tool}`,
    },
    generated: true,
    phase: 9,
    install: [],
    verify: [`${tool} --version || ${tool} --help`],
    tags: ['recommended'],
    dependencies: [],
    aliases: [],
    notes: [],
    web: {
      display_name: tool.toUpperCase(),
      href: `https://github.com/Dicklesworthstone/${repo}`,
      cli_name: tool,
      visible: true,
    },
  };
}

function manifestFor(modules: Module[]): Manifest {
  return {
    version: 1,
    name: 'Test ACFS',
    id: 'test_acfs',
    defaults: {
      user: 'ubuntu',
      workspace_root: '/data/projects',
      mode: 'vibe',
    },
    modules,
  };
}

function checksums(entries: Record<string, { repo: string; sha256?: string }>): ChecksumsFile {
  const installers: ChecksumsFile['installers'] = {};
  for (const [tool, entry] of Object.entries(entries)) {
    installers[tool] = {
      url: installerUrl(entry.repo),
      sha256: entry.sha256 ?? HASH_A,
    };
  }
  return {
    generatedAt: SNAPSHOT_TIME,
    installers,
  };
}

function release(
  repo: string,
  fixture: GitHubReleaseFixture
): Record<string, GitHubReleaseFixture> {
  return {
    [`Dicklesworthstone/${repo}`]: fixture,
  };
}

describe('stack provenance report', () => {
  test('rejects semantically invalid manifests before reporting', async () => {
    const module = stackModule('ultimate_bug_scanner', 'ubs', 'stack.duplicate');
    const manifest = manifestFor([module, { ...module }]);
    const current = checksums({ ubs: { repo: 'ultimate_bug_scanner' } });

    await expect(buildStackProvenanceReport({
      manifest,
      currentChecksums: current,
      network: 'skip',
    })).rejects.toThrow('Manifest semantic validation failed');
  });

  test('rejects generator-level function-name collisions before reporting', async () => {
    const manifest = manifestFor([
      stackModule('one', 'one', 'foo.bar_baz'),
      stackModule('two', 'two', 'foo_bar.baz'),
    ]);

    await expect(buildStackProvenanceReport({
      manifest,
      currentChecksums: checksums({
        one: { repo: 'one' },
        two: { repo: 'two' },
      }),
      network: 'skip',
    })).rejects.toThrow('FUNCTION_NAME_COLLISION');
  });

  test('reports non-GitHub stack provenance as explicit unknown without fetching', async () => {
    const module = stackModule('jeffreysprompts', 'jp', 'stack.jeffreysprompts');
    if (module.web) module.web.href = 'https://jeffreysprompts.com';
    let fetchCalls = 0;
    const current = checksums({ jp: { repo: 'jeffreysprompts' } });

    const report = await buildStackProvenanceReport({
      manifest: manifestFor([module]),
      currentChecksums: current,
      candidateChecksums: current,
      network: 'check',
      fetcher: async () => {
        fetchCalls += 1;
        throw new Error('unexpected release fetch');
      },
    });

    expect(report.tools).toHaveLength(1);
    expect(report.tools[0]).toMatchObject({
      moduleId: 'stack.jeffreysprompts',
      repositoryResolution: 'unsupported_href',
      sourceHref: 'https://jeffreysprompts.com',
      release: { status: 'unknown', relation: 'unknown' },
    });
    expect(report.tools[0].repo).toBeUndefined();
    expect(fetchCalls).toBe(0);
  });

  test('includes stack modules whose category is derived from their ID', async () => {
    const module = stackModule('ultimate_bug_scanner', 'ubs', 'stack.ultimate_bug_scanner');
    module.category = undefined;
    const current = checksums({ ubs: { repo: 'ultimate_bug_scanner' } });

    const report = await buildStackProvenanceReport({
      manifest: manifestFor([module]),
      currentChecksums: current,
      network: 'skip',
    });

    expect(report.tools.map((tool) => tool.moduleId)).toEqual([
      'stack.ultimate_bug_scanner',
    ]);
  });

  test('flags newer rch release as mandatory checksum review', async () => {
    const manifest = manifestFor([
      stackModule('remote_compilation_helper', 'rch', 'stack.rch'),
    ]);
    const current = checksums({ rch: { repo: 'remote_compilation_helper' } });

    const report = await buildStackProvenanceReport({
      manifest,
      currentChecksums: current,
      candidateChecksums: current,
      githubReleases: release('remote_compilation_helper', {
        status: 'ok',
        tagName: 'v9.9.9',
        publishedAt: '2026-02-01T00:00:00Z',
      }),
      network: 'check',
    });

    const tool = report.tools[0];
    expect(report.ok).toBe(false);
    expect(tool.release.relation).toBe('newer_upstream_release');
    expect(tool.release.status).toBe('fail');
    expect(tool.advisories.join('\n')).toContain('rch requires canonical checksum refresh review');
  });

  test('passes when latest release is not newer than checksum snapshot', async () => {
    const manifest = manifestFor([
      stackModule('ultimate_bug_scanner', 'ubs', 'stack.ultimate_bug_scanner'),
    ]);
    const current = checksums({ ubs: { repo: 'ultimate_bug_scanner' } });

    const report = await buildStackProvenanceReport({
      manifest,
      currentChecksums: current,
      candidateChecksums: current,
      githubReleases: release('ultimate_bug_scanner', {
        status: 'ok',
        tagName: 'v1.0.0',
        publishedAt: '2026-01-01T00:00:00Z',
      }),
      network: 'check',
    });

    expect(report.ok).toBe(true);
    expect(report.tools[0].release.status).toBe('pass');
    expect(report.tools[0].release.relation).toBe('same_or_older');
  });

  test('ignores checksum candidate timestamp-only changes', async () => {
    const manifest = manifestFor([
      stackModule('ultimate_bug_scanner', 'ubs', 'stack.ultimate_bug_scanner'),
    ]);
    const current = checksums({ ubs: { repo: 'ultimate_bug_scanner' } });
    const candidate: ChecksumsFile = {
      generatedAt: '2026-01-16T00:00:00Z',
      installers: current.installers,
    };

    const report = await buildStackProvenanceReport({
      manifest,
      currentChecksums: current,
      candidateChecksums: candidate,
      githubReleases: release('ultimate_bug_scanner', {
        status: 'ok',
        tagName: 'v1.0.0',
        publishedAt: '2026-01-01T00:00:00Z',
      }),
      network: 'check',
    });

    expect(report.ok).toBe(true);
    expect(report.checksumDiffs.stack).toEqual([]);
    expect(report.checksumDiffs.unrelated).toEqual([]);
    expect(report.tools[0].candidate.status).toBe('pass');
  });

  test('warns when a stack repo has no latest release metadata', async () => {
    const manifest = manifestFor([
      stackModule('beads_viewer', 'bv', 'stack.beads_viewer'),
    ]);
    const current = checksums({ bv: { repo: 'beads_viewer' } });

    const report = await buildStackProvenanceReport({
      manifest,
      currentChecksums: current,
      candidateChecksums: current,
      githubReleases: release('beads_viewer', {
        status: 'missing',
      }),
      network: 'check',
    });

    expect(report.ok).toBe(true);
    expect(report.tools[0].release.status).toBe('warn');
    expect(report.tools[0].release.relation).toBe('missing_release');
  });

  test('fails when stack installer checksum candidate changes', async () => {
    const manifest = manifestFor([
      stackModule('ultimate_bug_scanner', 'ubs', 'stack.ultimate_bug_scanner'),
    ]);
    const current = checksums({ ubs: { repo: 'ultimate_bug_scanner', sha256: HASH_A } });
    const candidate = checksums({ ubs: { repo: 'ultimate_bug_scanner', sha256: HASH_B } });

    const report = await buildStackProvenanceReport({
      manifest,
      currentChecksums: current,
      candidateChecksums: candidate,
      githubReleases: release('ultimate_bug_scanner', {
        status: 'ok',
        tagName: 'v1.0.0',
        publishedAt: '2026-01-01T00:00:00Z',
      }),
      network: 'check',
    });

    expect(report.ok).toBe(false);
    expect(report.checksumDiffs.stack).toHaveLength(1);
    expect(report.checksumDiffs.stack[0].tool).toBe('ubs');
    expect(report.tools[0].candidate.status).toBe('fail');
  });

  test('fails when checksum candidate contains unrelated installer diffs', async () => {
    const manifest = manifestFor([
      stackModule('ultimate_bug_scanner', 'ubs', 'stack.ultimate_bug_scanner'),
    ]);
    const current = checksums({
      ubs: { repo: 'ultimate_bug_scanner', sha256: HASH_A },
      bun: { repo: 'not_a_stack_repo', sha256: HASH_A },
    });
    const candidate = checksums({
      ubs: { repo: 'ultimate_bug_scanner', sha256: HASH_A },
      bun: { repo: 'not_a_stack_repo', sha256: HASH_B },
    });

    const report = await buildStackProvenanceReport({
      manifest,
      currentChecksums: current,
      candidateChecksums: candidate,
      githubReleases: release('ultimate_bug_scanner', {
        status: 'ok',
        tagName: 'v1.0.0',
        publishedAt: '2026-01-01T00:00:00Z',
      }),
      network: 'check',
    });

    expect(report.ok).toBe(false);
    expect(report.checksumDiffs.stack).toHaveLength(0);
    expect(report.checksumDiffs.unrelated).toHaveLength(1);
    expect(report.checksumDiffs.unrelated[0].tool).toBe('bun');
    expect(report.advisories.join('\n')).toContain('unrelated installer changes');
  });
});
