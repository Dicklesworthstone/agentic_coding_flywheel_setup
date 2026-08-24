import { describe, expect, test } from 'bun:test';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import {
  checkManifestDriftContract,
  type DriftContractCode,
} from './drift-contract.js';

const HASH = 'a'.repeat(64);
const INSTALLER_URL = 'https://example.com/example/install.sh';

function write(path: string, content: string): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
}

function writeFixtureFile(root: string, relPath: string, content: string): void {
  write(join(root, relPath), content);
}

function cleanFixture(): string {
  const root = mkdtempSync(join(tmpdir(), 'acfs-manifest-drift-contract-'));

  writeFixtureFile(
    root,
    'acfs.manifest.yaml',
    `version: 1
name: Test ACFS
id: test_acfs
defaults:
  user: ubuntu
  workspace_root: /data/projects
  mode: vibe
modules:
  - id: stack.example
    description: Example stack tool
    run_as: target_user
    optional: false
    enabled_by_default: true
    generated: true
    install: []
    verify:
      - example --version
    verified_installer:
      tool: example
      url: ${INSTALLER_URL}
      runner: bash
      args: []
    web:
      display_name: Example Tool
      short_name: EX
      tagline: Example stack tool
      short_desc: Example generated tool metadata
      icon: terminal
      color: "#0EA5E9"
      cli_name: example
      command_example: example --help
      lesson_slug: example
      tldr_snippet: example --version
  - id: stack.hidden
    description: Hidden stack tool
    run_as: target_user
    optional: true
    enabled_by_default: false
    generated: true
    install:
      - echo hidden
    verify:
      - hidden --version
    web:
      visible: false
      display_name: Hidden Tool
      tagline: Hidden stack tool
      cli_name: hidden
      lesson_slug: hidden
  - id: base.local
    description: Local base tool
    run_as: target_user
    optional: false
    enabled_by_default: true
    generated: true
    install:
      - echo local
    verify:
      - local --version
`
  );

  writeFixtureFile(
    root,
    'checksums.yaml',
    `installers:
  example:
    url: ${INSTALLER_URL}
    sha256: ${HASH}
`
  );

  writeFixtureFile(
    root,
    'scripts/generated/manifest_index.sh',
    `ACFS_MODULES_IN_ORDER=(
    "stack.example"
    "stack.hidden"
    "base.local"
)
`
  );

  writeFixtureFile(
    root,
    'scripts/generated/doctor_checks.sh',
    `declare -a MANIFEST_CHECKS=(
    "stack.example\tExample stack tool\texample --version\trequired\ttarget_user"
    "stack.hidden\tHidden stack tool\thidden --version\toptional\ttarget_user"
    "base.local\tLocal base tool\tlocal --version\trequired\ttarget_user"
)
`
  );

  writeFixtureFile(
    root,
    'apps/web/lib/generated/manifest-modules.ts',
    `export const manifestModules = [
  {
    id: "stack.example",
  },
  {
    id: "stack.hidden",
  },
  {
    id: "base.local",
  },
];
`
  );
  writeFixtureFile(
    root,
    'apps/web/lib/generated/manifest-tools.ts',
    'export const manifestTools = [{ moduleId: "stack.example" }];\n'
  );
  writeFixtureFile(
    root,
    'apps/web/lib/generated/manifest-commands.ts',
    'export const manifestCommands = [{ moduleId: "stack.example" }];\n'
  );
  writeFixtureFile(
    root,
    'apps/web/lib/generated/manifest-tldr.ts',
    'export const manifestTldrTools = [{ moduleId: "stack.example" }];\n'
  );
  writeFixtureFile(
    root,
    'apps/web/lib/generated/manifest-lessons-index.ts',
    `export const manifestLessonLinks = [
  { moduleId: "stack.example", lessonSlug: "example" },
];
export const lessonSlugByModuleId = {
  "stack.example": "example",
};
`
  );
  writeFixtureFile(root, 'acfs/onboard/lessons/01_example.md', '# Example\n');
  writeFixtureFile(
    root,
    'README.md',
    [
      'scripts/check-manifest-drift.sh --json',
      'bun run generate:diff',
      'scripts/generated/doctor_checks.sh',
      'apps/web/lib/generated',
      'acfs/onboard/lessons',
      'checksums.yaml',
    ].join('\n')
  );

  return root;
}

function codes(root: string): DriftContractCode[] {
  return checkManifestDriftContract(root).mismatches.map((mismatch) => mismatch.code);
}

describe('manifest drift contract', () => {
  test('passes clean fixtures and honors intentional skip cases', () => {
    const result = checkManifestDriftContract(cleanFixture());

    expect(result.ok).toBe(true);
    expect(result.mismatches).toEqual([]);
    expect(result.summary.verifiedInstallers).toBe(1);
    expect(result.summary.webVisibleModules).toBe(1);
    expect(result.summary.lessonLinkedModules).toBe(1);
  });

  test('detects stale generated manifest index output', () => {
    const root = cleanFixture();
    writeFixtureFile(
      root,
      'scripts/generated/manifest_index.sh',
      `ACFS_MODULES_IN_ORDER=(
    "stack.hidden"
    "base.local"
)
`
    );

    expect(codes(root)).toContain('MANIFEST_INDEX_MODULE_MISSING');
  });

  test('rejects structurally valid manifests with semantic errors', () => {
    const root = cleanFixture();
    const path = join(root, 'acfs.manifest.yaml');
    const manifest = readFileSync(path, 'utf-8');
    writeFixtureFile(
      root,
      'acfs.manifest.yaml',
      `${manifest}  - id: stack.example
    description: Duplicate module
    install:
      - echo duplicate
    verify:
      - duplicate --version
`
    );

    const result = checkManifestDriftContract(root);
    expect(result.ok).toBe(false);
    expect(result.mismatches).toContainEqual(expect.objectContaining({
      code: 'MANIFEST_SEMANTIC_INVALID',
      message: expect.stringContaining('Duplicate module ID'),
    }));
  });

  test('rejects generated function-name collisions inside the private namespace', () => {
    const modules = `  - id: tools.foo_bar
    description: First colliding module
    category: tools
    install: [echo first]
    verify: [first --version]
  - id: tools_foo.bar
    description: Second colliding module
    category: tools
    install: [echo second]
    verify: [second --version]
`;
    const root = cleanFixture();
    const path = join(root, 'acfs.manifest.yaml');
    writeFixtureFile(
      root,
      'acfs.manifest.yaml',
      `${readFileSync(path, 'utf-8')}${modules}`,
    );

    const semanticErrors = checkManifestDriftContract(root).mismatches.filter(
      (mismatch) => mismatch.code === 'MANIFEST_SEMANTIC_INVALID'
    );
    expect(semanticErrors).not.toHaveLength(0);
    expect(semanticErrors.some((mismatch) =>
      mismatch.message.includes('FUNCTION_NAME_COLLISION')
    )).toBe(true);
  });

  test('detects unexpected IDs on every generated ID surface', () => {
    const root = cleanFixture();
    const orphan = 'stack.orphan';
    const files = [
      'scripts/generated/manifest_index.sh',
      'scripts/generated/doctor_checks.sh',
      'apps/web/lib/generated/manifest-modules.ts',
      'apps/web/lib/generated/manifest-tools.ts',
      'apps/web/lib/generated/manifest-commands.ts',
      'apps/web/lib/generated/manifest-tldr.ts',
      'apps/web/lib/generated/manifest-lessons-index.ts',
    ];
    for (const file of files) {
      const path = join(root, file);
      const existing = readFileSync(path, 'utf-8');
      if (file.endsWith('manifest_index.sh')) {
        writeFixtureFile(root, file, existing.replace(
          '\n)\n',
          `\n    "${orphan}"\n)\n`,
        ));
      } else if (file.endsWith('doctor_checks.sh')) {
        writeFixtureFile(root, file, existing.replace(
          '\n)\n',
          `\n    "${orphan}\tOrphan\torphan --version\toptional\ttarget_user"\n)\n`,
        ));
      } else if (file.endsWith('manifest-modules.ts')) {
        writeFixtureFile(root, file, existing.replace(
          '\n];\n',
          `\n  {\n    id: "${orphan}",\n  },\n];\n`,
        ));
      } else if (file.endsWith('manifest-lessons-index.ts')) {
        writeFixtureFile(root, file, existing.replace(
          '\n];\n',
          `\n  { moduleId: "${orphan}", lessonSlug: "orphan" },\n];\n`,
        ));
      } else {
        writeFixtureFile(
          root,
          file,
          `${existing}\nexport const orphan = { moduleId: "${orphan}" };\n`,
        );
      }
    }

    const unexpected = checkManifestDriftContract(root).mismatches.filter(
      (mismatch) => mismatch.code === 'GENERATED_ID_UNEXPECTED'
    );
    expect(unexpected).toHaveLength(files.length);
    expect(unexpected.every((mismatch) => mismatch.actual === orphan)).toBe(true);
  });

  test('detects missing canonical website module metadata', () => {
    const root = cleanFixture();
    writeFixtureFile(
      root,
      'apps/web/lib/generated/manifest-modules.ts',
      'export const manifestModules = [\n];\n',
    );

    expect(codes(root)).toContain('WEB_MODULE_MISSING');
  });

  test('detects duplicate IDs on every generated ID surface', () => {
    const files = [
      'scripts/generated/manifest_index.sh',
      'scripts/generated/doctor_checks.sh',
      'apps/web/lib/generated/manifest-modules.ts',
      'apps/web/lib/generated/manifest-tools.ts',
      'apps/web/lib/generated/manifest-commands.ts',
      'apps/web/lib/generated/manifest-tldr.ts',
      'apps/web/lib/generated/manifest-lessons-index.ts',
    ];
    for (const file of files) {
      const root = cleanFixture();
      const existing = readFileSync(join(root, file), 'utf-8');
      if (file.endsWith('manifest_index.sh')) {
        writeFixtureFile(root, file, existing.replace(
          '\n)\n',
          '\n    "stack.example"\n)\n',
        ));
      } else if (file.endsWith('doctor_checks.sh')) {
        writeFixtureFile(root, file, existing.replace(
          '\n)\n',
          '\n    "stack.example\\tDuplicate\\texample --version\\trequired\\ttarget_user"\n)\n',
        ));
      } else if (file.endsWith('manifest-modules.ts')) {
        writeFixtureFile(root, file, existing.replace(
          '\n];\n',
          '\n  {\n    id: "stack.example",\n  },\n];\n',
        ));
      } else if (file.endsWith('manifest-lessons-index.ts')) {
        writeFixtureFile(root, file, existing.replace(
          '\n];\n',
          '\n  { moduleId: "stack.example", lessonSlug: "example" },\n];\n',
        ));
      } else {
        writeFixtureFile(
          root,
          file,
          `${existing}\nexport const duplicate = { moduleId: "stack.example" };\n`,
        );
      }

      expect(checkManifestDriftContract(root).mismatches).toContainEqual(
        expect.objectContaining({
          code: 'GENERATED_ID_DUPLICATE',
          file,
          actual: 'stack.example',
        })
      );
    }
  });

  test('detects duplicate lesson lookup keys and wrong module-to-slug mappings', () => {
    const root = cleanFixture();
    const file = 'apps/web/lib/generated/manifest-lessons-index.ts';
    const existing = readFileSync(join(root, file), 'utf-8');
    writeFixtureFile(
      root,
      file,
      existing
        .replace('lessonSlug: "example"', 'lessonSlug: "wrong"')
        .replace(
          '\n};\n',
          '\n  "stack.example": "example",\n};\n',
        ),
    );

    const result = checkManifestDriftContract(root);
    expect(result.mismatches).toContainEqual(expect.objectContaining({
      code: 'GENERATED_ID_DUPLICATE',
      actual: 'stack.example',
      message: expect.stringContaining('lookup map'),
    }));
    expect(result.mismatches).toContainEqual(expect.objectContaining({
      code: 'LESSON_LINK_MISSING',
      moduleId: 'stack.example',
      expected: 'example',
      actual: 'wrong',
    }));
  });

  test('detects missing generated website content', () => {
    const root = cleanFixture();
    writeFixtureFile(root, 'apps/web/lib/generated/manifest-tools.ts', 'export const manifestTools = [];\n');

    expect(codes(root)).toContain('WEB_TOOL_MISSING');
  });

  test('detects stale generated website command tldr and lesson indexes', () => {
    const root = cleanFixture();
    writeFixtureFile(root, 'apps/web/lib/generated/manifest-commands.ts', 'export const manifestCommands = [];\n');
    writeFixtureFile(root, 'apps/web/lib/generated/manifest-tldr.ts', 'export const manifestTldrTools = [];\n');
    writeFixtureFile(root, 'apps/web/lib/generated/manifest-lessons-index.ts', 'export const manifestLessonLinks = [];\n');

    const mismatchCodes = codes(root);
    expect(mismatchCodes).toContain('WEB_COMMAND_MISSING');
    expect(mismatchCodes).toContain('WEB_TLDR_MISSING');
    expect(mismatchCodes).toContain('LESSON_LINK_MISSING');
  });

  test('detects missing generated doctor checks', () => {
    const root = cleanFixture();
    writeFixtureFile(
      root,
      'scripts/generated/doctor_checks.sh',
      `declare -a MANIFEST_CHECKS=(
    "stack.hidden\tHidden stack tool\thidden --version\toptional\ttarget_user"
    "base.local\tLocal base tool\tlocal --version\trequired\ttarget_user"
)
`
    );

    expect(codes(root)).toContain('DOCTOR_CHECK_MISSING');
  });

  test('detects missing verified installer checksum coverage', () => {
    const root = cleanFixture();
    writeFixtureFile(root, 'checksums.yaml', 'installers: {}\n');

    expect(codes(root)).toContain('MISSING_VERIFIED_INSTALLER_CHECKSUM');
  });

  test('detects missing lesson and README contract snippets', () => {
    const root = cleanFixture();
    writeFixtureFile(root, 'README.md', 'checksums.yaml\n');

    expect(codes(root)).toContain('README_SNIPPET_MISSING');
  });

  test('detects missing onboarding lesson files for lesson-linked modules', () => {
    const root = cleanFixture();
    writeFixtureFile(
      root,
      'acfs.manifest.yaml',
      `version: 1
name: Test ACFS
id: test_acfs
defaults:
  user: ubuntu
  workspace_root: /data/projects
  mode: vibe
modules:
  - id: stack.example
    description: Example stack tool
    run_as: target_user
    optional: false
    enabled_by_default: true
    generated: true
    install: []
    verify:
      - example --version
    verified_installer:
      tool: example
      url: ${INSTALLER_URL}
      runner: bash
      args: []
    web:
      display_name: Example Tool
      short_name: EX
      tagline: Example stack tool
      short_desc: Example generated tool metadata
      icon: terminal
      color: "#0EA5E9"
      cli_name: example
      command_example: example --help
      lesson_slug: missing
      tldr_snippet: example --version
  - id: stack.hidden
    description: Hidden stack tool
    run_as: target_user
    optional: true
    enabled_by_default: false
    generated: true
    install:
      - echo hidden
    verify:
      - hidden --version
    web:
      visible: false
      display_name: Hidden Tool
      tagline: Hidden stack tool
      cli_name: hidden
      lesson_slug: hidden
  - id: base.local
    description: Local base tool
    run_as: target_user
    optional: false
    enabled_by_default: true
    generated: true
    install:
      - echo local
    verify:
      - local --version
`
    );
    writeFixtureFile(
      root,
      'apps/web/lib/generated/manifest-lessons-index.ts',
      'export const manifestLessonLinks = [{ moduleId: "stack.example", lessonSlug: "missing" }];\n'
    );

    expect(codes(root)).toContain('ONBOARDING_LESSON_MISSING');
  });
});
