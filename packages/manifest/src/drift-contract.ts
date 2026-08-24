#!/usr/bin/env bun
/**
 * Manifest drift contract checks for non-generated release surfaces.
 *
 * The generator diff already compares bytes for generated files. This module
 * adds semantic checks so release gates can explain which manifest-derived
 * surface is missing coverage.
 */

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse as parseYaml } from 'yaml';
import { parseManifestFile, validateManifestData } from './parser.js';
import {
  validateManifest as validateManifestAdvanced,
  validateVerifiedInstallerChecksums,
  type InstallerChecksumEntry,
} from './validate.js';
import type { Manifest, Module } from './types.js';

export type DriftContractCode =
  | 'MANIFEST_PARSE_FAILED'
  | 'MANIFEST_SEMANTIC_INVALID'
  | 'CHECKSUMS_PARSE_FAILED'
  | 'MISSING_FILE'
  | 'MANIFEST_INDEX_MODULE_MISSING'
  | 'DOCTOR_CHECK_MISSING'
  | 'WEB_MODULE_MISSING'
  | 'WEB_TOOL_MISSING'
  | 'WEB_COMMAND_MISSING'
  | 'WEB_TLDR_MISSING'
  | 'LESSON_LINK_MISSING'
  | 'ONBOARDING_LESSON_MISSING'
  | 'README_SNIPPET_MISSING'
  | 'MISSING_VERIFIED_INSTALLER_CHECKSUM'
  | 'INVALID_VERIFIED_INSTALLER_CHECKSUM'
  | 'VERIFIED_INSTALLER_URL_MISMATCH'
  | 'GENERATED_ID_UNEXPECTED'
  | 'GENERATED_ID_DUPLICATE';

export interface DriftContractMismatch {
  code: DriftContractCode;
  message: string;
  file: string;
  moduleId?: string;
  expected?: string;
  actual?: string;
}

export interface DriftContractSummary {
  modules: number;
  verifiedInstallers: number;
  webVisibleModules: number;
  webCommandModules: number;
  webTldrModules: number;
  lessonLinkedModules: number;
  doctorChecksExpected: number;
  readmeSnippetsExpected: number;
  checked: number;
}

export interface DriftContractResult {
  ok: boolean;
  root: string;
  summary: DriftContractSummary;
  mismatches: DriftContractMismatch[];
}

const SCRIPT_FILE = fileURLToPath(import.meta.url);
const DEFAULT_ROOT = resolve(dirname(SCRIPT_FILE), '../../..');

const REQUIRED_README_SNIPPETS = [
  {
    snippet: 'scripts/check-manifest-drift.sh --json',
    reason: 'release drift gate',
  },
  {
    snippet: 'bun run generate:diff',
    reason: 'generated artifact byte comparison',
  },
  {
    snippet: 'scripts/generated/doctor_checks.sh',
    reason: 'manifest-derived doctor checks',
  },
  {
    snippet: 'apps/web/lib/generated',
    reason: 'manifest-derived website metadata',
  },
  {
    snippet: 'acfs/onboard/lessons',
    reason: 'manifest-linked onboarding lesson content',
  },
  {
    snippet: 'checksums.yaml',
    reason: 'verified installer checksum coverage',
  },
];

function rel(root: string, path: string): string {
  return relative(root, path) || '.';
}

function readText(
  root: string,
  relPath: string,
  mismatches: DriftContractMismatch[]
): string | null {
  const absPath = join(root, relPath);
  if (!existsSync(absPath)) {
    mismatches.push({
      code: 'MISSING_FILE',
      file: relPath,
      message: `Required manifest drift contract file is missing: ${relPath}`,
    });
    return null;
  }
  return readFileSync(absPath, 'utf-8');
}

interface GeneratedIdInventory {
  ids: Set<string>;
  duplicates: Set<string>;
}

function buildIdInventory(values: Iterable<string>): GeneratedIdInventory {
  const ids = new Set<string>();
  const duplicates = new Set<string>();
  for (const value of values) {
    if (ids.has(value)) duplicates.add(value);
    ids.add(value);
  }
  return { ids, duplicates };
}

function extractModuleIdsFromGeneratedTs(content: string): GeneratedIdInventory {
  const values: string[] = [];
  const regex = /moduleId:\s*"([^"]+)"/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(content)) !== null) {
    values.push(match[1]);
  }
  return buildIdInventory(values);
}

function extractManifestModuleIds(content: string): GeneratedIdInventory {
  const arrayMatch = content.match(
    /export const manifestModules[^=]*=\s*\[([\s\S]*?)\n\];/
  );
  if (!arrayMatch) return buildIdInventory([]);

  const values: string[] = [];
  const regex = /^\s*id:\s*"([^"]+)"/gm;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(arrayMatch[1])) !== null) {
    values.push(match[1]);
  }
  return buildIdInventory(values);
}

interface LessonIndexInventory {
  linkIds: GeneratedIdInventory;
  lookupIds: GeneratedIdInventory;
  linkSlugs: Map<string, string>;
  lookupSlugs: Map<string, string>;
}

function extractLessonIndex(content: string): LessonIndexInventory {
  const linkValues: string[] = [];
  const lookupValues: string[] = [];
  const linkSlugs = new Map<string, string>();
  const lookupSlugs = new Map<string, string>();
  const linksMatch = content.match(
    /export const manifestLessonLinks[^=]*=\s*\[([\s\S]*?)\n\];/
  );
  if (linksMatch) {
    const linkRegex = /\{\s*moduleId:\s*"([^"]+)",\s*lessonSlug:\s*"([^"]+)"/g;
    let match: RegExpExecArray | null;
    while ((match = linkRegex.exec(linksMatch[1])) !== null) {
      linkValues.push(match[1]);
      linkSlugs.set(match[1], match[2]);
    }
  }

  const lookupMatch = content.match(
    /export const lessonSlugByModuleId[^=]*=\s*\{([\s\S]*?)\n\};/
  );
  if (lookupMatch) {
    const lookupRegex = /^\s*"([^"]+)":\s*"([^"]+)",?$/gm;
    let match: RegExpExecArray | null;
    while ((match = lookupRegex.exec(lookupMatch[1])) !== null) {
      lookupValues.push(match[1]);
      lookupSlugs.set(match[1], match[2]);
    }
  }

  return {
    linkIds: buildIdInventory(linkValues),
    lookupIds: buildIdInventory(lookupValues),
    linkSlugs,
    lookupSlugs,
  };
}

function extractDoctorCheckIds(content: string): GeneratedIdInventory {
  const values: string[] = [];
  const regex = /^\s*"([^"\t]+)\t/gm;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(content)) !== null) {
    values.push(match[1]);
  }
  return buildIdInventory(values);
}

function extractManifestIndexModuleIds(content: string): GeneratedIdInventory {
  const arrayMatch = content.match(/ACFS_MODULES_IN_ORDER=\(\n([\s\S]*?)\n\)/);
  if (!arrayMatch) {
    return buildIdInventory([]);
  }

  const values: string[] = [];
  const regex = /"([^"]+)"/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(arrayMatch[1])) !== null) {
    values.push(match[1]);
  }
  return buildIdInventory(values);
}

function webVisibleModules(manifest: Manifest): Module[] {
  return manifest.modules.filter((module) => Boolean(module.web) && module.web?.visible !== false);
}

function webCommandModules(manifest: Manifest): Module[] {
  return webVisibleModules(manifest).filter((module) => Boolean(module.web?.cli_name));
}

function webTldrModules(manifest: Manifest): Module[] {
  return webVisibleModules(manifest).filter((module) =>
    Boolean(module.web?.tldr_snippet || module.web?.tagline)
  );
}

function lessonLinkedModules(manifest: Manifest): Module[] {
  return webVisibleModules(manifest).filter((module) => Boolean(module.web?.lesson_slug));
}

function expectedDoctorCheckIds(manifest: Manifest): Array<{ module: Module; id: string }> {
  const ids: Array<{ module: Module; id: string }> = [];
  for (const module of manifest.modules) {
    for (let i = 0; i < module.verify.length; i += 1) {
      const suffix = module.verify.length > 1 ? `.${i + 1}` : '';
      ids.push({ module, id: `${module.id}${suffix}` });
    }
  }
  return ids;
}

function addMissingModuleIds(
  mismatches: DriftContractMismatch[],
  code: DriftContractCode,
  file: string,
  expectedModules: Module[],
  actualIds: Set<string>,
  label: string
): void {
  for (const module of expectedModules) {
    if (actualIds.has(module.id)) {
      continue;
    }
    mismatches.push({
      code,
      file,
      moduleId: module.id,
      expected: module.id,
      message: `${label} is missing manifest module "${module.id}"`,
    });
  }
}

function addUnexpectedIds(
  mismatches: DriftContractMismatch[],
  file: string,
  expectedIds: ReadonlySet<string>,
  actualIds: ReadonlySet<string>,
  label: string
): void {
  for (const actualId of Array.from(actualIds).sort()) {
    if (expectedIds.has(actualId)) continue;
    mismatches.push({
      code: 'GENERATED_ID_UNEXPECTED',
      file,
      moduleId: actualId,
      actual: actualId,
      message: `${label} contains unexpected generated ID "${actualId}"`,
    });
  }
}

function addDuplicateIds(
  mismatches: DriftContractMismatch[],
  file: string,
  duplicateIds: ReadonlySet<string>,
  label: string
): void {
  for (const duplicateId of Array.from(duplicateIds).sort()) {
    mismatches.push({
      code: 'GENERATED_ID_DUPLICATE',
      file,
      moduleId: duplicateId,
      actual: duplicateId,
      message: `${label} contains duplicate generated ID "${duplicateId}"`,
    });
  }
}

function moduleIds(modules: Module[]): Set<string> {
  return new Set(modules.map((module) => module.id));
}

function checkOnboardingLessons(
  root: string,
  modules: Module[],
  mismatches: DriftContractMismatch[]
): void {
  const lessonsDir = join(root, 'acfs/onboard/lessons');
  let files: string[] = [];
  if (!existsSync(lessonsDir)) {
    mismatches.push({
      code: 'MISSING_FILE',
      file: rel(root, lessonsDir),
      message: 'Onboarding lessons directory is missing',
    });
    return;
  }

  files = readdirSync(lessonsDir);
  for (const module of modules) {
    const slug = module.web?.lesson_slug;
    if (!slug) continue;
    const expectedSuffix = `_${slug}.md`;
    if (!files.some((file) => file.endsWith(expectedSuffix))) {
      mismatches.push({
        code: 'ONBOARDING_LESSON_MISSING',
        file: 'acfs/onboard/lessons',
        moduleId: module.id,
        expected: expectedSuffix,
        message: `Onboarding lesson file ending in "${expectedSuffix}" is missing for "${module.id}"`,
      });
    }
  }
}

function checkReadmeSnippets(
  readme: string | null,
  mismatches: DriftContractMismatch[]
): void {
  if (readme === null) return;

  for (const { snippet, reason } of REQUIRED_README_SNIPPETS) {
    if (readme.includes(snippet)) {
      continue;
    }
    mismatches.push({
      code: 'README_SNIPPET_MISSING',
      file: 'README.md',
      expected: snippet,
      message: `README is missing manifest drift snippet "${snippet}" for ${reason}`,
    });
  }
}

export function checkManifestDriftContract(rootDir = DEFAULT_ROOT): DriftContractResult {
  const root = resolve(rootDir);
  const mismatches: DriftContractMismatch[] = [];
  const summary: DriftContractSummary = {
    modules: 0,
    verifiedInstallers: 0,
    webVisibleModules: 0,
    webCommandModules: 0,
    webTldrModules: 0,
    lessonLinkedModules: 0,
    doctorChecksExpected: 0,
    readmeSnippetsExpected: REQUIRED_README_SNIPPETS.length,
    checked: 0,
  };

  const manifestPath = join(root, 'acfs.manifest.yaml');
  const parseResult = parseManifestFile(manifestPath);
  if (!parseResult.success || !parseResult.data) {
    mismatches.push({
      code: 'MANIFEST_PARSE_FAILED',
      file: 'acfs.manifest.yaml',
      message: parseResult.error?.message ?? 'Failed to parse manifest',
    });
    return { ok: false, root, summary, mismatches };
  }

  const manifest = parseResult.data;
  const manifestValidation = validateManifestData(manifest);
  if (!manifestValidation.valid) {
    for (const error of manifestValidation.errors) {
      mismatches.push({
        code: 'MANIFEST_SEMANTIC_INVALID',
        file: 'acfs.manifest.yaml',
        message: `${error.path}: ${error.message}`,
      });
    }
    return { ok: false, root, summary, mismatches };
  }
  const advancedValidation = validateManifestAdvanced(manifest);
  if (!advancedValidation.valid) {
    for (const error of advancedValidation.errors) {
      mismatches.push({
        code: 'MANIFEST_SEMANTIC_INVALID',
        file: 'acfs.manifest.yaml',
        moduleId: error.moduleId,
        message: `${error.code}: ${error.message}`,
      });
    }
    return { ok: false, root, summary, mismatches };
  }
  const verifiedModules = manifest.modules.filter((module) => Boolean(module.verified_installer));
  const visibleModules = webVisibleModules(manifest);
  const commandModules = webCommandModules(manifest);
  const tldrModules = webTldrModules(manifest);
  const lessonModules = lessonLinkedModules(manifest);
  const doctorIds = expectedDoctorCheckIds(manifest);

  summary.modules = manifest.modules.length;
  summary.verifiedInstallers = verifiedModules.length;
  summary.webVisibleModules = visibleModules.length;
  summary.webCommandModules = commandModules.length;
  summary.webTldrModules = tldrModules.length;
  summary.lessonLinkedModules = lessonModules.length;
  summary.doctorChecksExpected = doctorIds.length;

  const checksumsText = readText(root, 'checksums.yaml', mismatches);
  if (checksumsText !== null) {
    try {
      const checksums = parseYaml(checksumsText) as {
        installers?: Record<string, InstallerChecksumEntry>;
      };
      const checksumErrors = validateVerifiedInstallerChecksums(
        manifest,
        checksums.installers ?? {}
      );
      for (const err of checksumErrors) {
        mismatches.push({
          code: err.code as DriftContractCode,
          file: 'checksums.yaml',
          moduleId: err.moduleId,
          message: err.message,
        });
      }
    } catch (err) {
      mismatches.push({
        code: 'CHECKSUMS_PARSE_FAILED',
        file: 'checksums.yaml',
        message: `Failed to parse checksums.yaml: ${err instanceof Error ? err.message : String(err)}`,
      });
    }
  }

  const manifestIndex = readText(root, 'scripts/generated/manifest_index.sh', mismatches);
  if (manifestIndex !== null) {
    const inventory = extractManifestIndexModuleIds(manifestIndex);
    addMissingModuleIds(
      mismatches,
      'MANIFEST_INDEX_MODULE_MISSING',
      'scripts/generated/manifest_index.sh',
      manifest.modules,
      inventory.ids,
      'Generated manifest index'
    );
    addUnexpectedIds(
      mismatches,
      'scripts/generated/manifest_index.sh',
      moduleIds(manifest.modules),
      inventory.ids,
      'Generated manifest index'
    );
    addDuplicateIds(
      mismatches,
      'scripts/generated/manifest_index.sh',
      inventory.duplicates,
      'Generated manifest index'
    );
  }

  const doctorChecks = readText(root, 'scripts/generated/doctor_checks.sh', mismatches);
  if (doctorChecks !== null) {
    const inventory = extractDoctorCheckIds(doctorChecks);
    for (const { module, id } of doctorIds) {
      if (inventory.ids.has(id)) {
        continue;
      }
      mismatches.push({
        code: 'DOCTOR_CHECK_MISSING',
        file: 'scripts/generated/doctor_checks.sh',
        moduleId: module.id,
        expected: id,
        message: `Generated doctor checks are missing manifest check "${id}"`,
      });
    }
    addUnexpectedIds(
      mismatches,
      'scripts/generated/doctor_checks.sh',
      new Set(doctorIds.map(({ id }) => id)),
      inventory.ids,
      'Generated doctor checks'
    );
    addDuplicateIds(
      mismatches,
      'scripts/generated/doctor_checks.sh',
      inventory.duplicates,
      'Generated doctor checks'
    );
  }

  const webModules = readText(root, 'apps/web/lib/generated/manifest-modules.ts', mismatches);
  if (webModules !== null) {
    const inventory = extractManifestModuleIds(webModules);
    addMissingModuleIds(
      mismatches,
      'WEB_MODULE_MISSING',
      'apps/web/lib/generated/manifest-modules.ts',
      manifest.modules,
      inventory.ids,
      'Generated website module metadata'
    );
    addUnexpectedIds(
      mismatches,
      'apps/web/lib/generated/manifest-modules.ts',
      moduleIds(manifest.modules),
      inventory.ids,
      'Generated website module metadata'
    );
    addDuplicateIds(
      mismatches,
      'apps/web/lib/generated/manifest-modules.ts',
      inventory.duplicates,
      'Generated website module metadata'
    );
  }

  const webTools = readText(root, 'apps/web/lib/generated/manifest-tools.ts', mismatches);
  if (webTools !== null) {
    const inventory = extractModuleIdsFromGeneratedTs(webTools);
    addMissingModuleIds(
      mismatches,
      'WEB_TOOL_MISSING',
      'apps/web/lib/generated/manifest-tools.ts',
      visibleModules,
      inventory.ids,
      'Generated website tool metadata'
    );
    addUnexpectedIds(
      mismatches,
      'apps/web/lib/generated/manifest-tools.ts',
      moduleIds(visibleModules),
      inventory.ids,
      'Generated website tool metadata'
    );
    addDuplicateIds(
      mismatches,
      'apps/web/lib/generated/manifest-tools.ts',
      inventory.duplicates,
      'Generated website tool metadata'
    );
  }

  const webCommands = readText(root, 'apps/web/lib/generated/manifest-commands.ts', mismatches);
  if (webCommands !== null) {
    const inventory = extractModuleIdsFromGeneratedTs(webCommands);
    addMissingModuleIds(
      mismatches,
      'WEB_COMMAND_MISSING',
      'apps/web/lib/generated/manifest-commands.ts',
      commandModules,
      inventory.ids,
      'Generated command reference metadata'
    );
    addUnexpectedIds(
      mismatches,
      'apps/web/lib/generated/manifest-commands.ts',
      moduleIds(commandModules),
      inventory.ids,
      'Generated command reference metadata'
    );
    addDuplicateIds(
      mismatches,
      'apps/web/lib/generated/manifest-commands.ts',
      inventory.duplicates,
      'Generated command reference metadata'
    );
  }

  const webTldr = readText(root, 'apps/web/lib/generated/manifest-tldr.ts', mismatches);
  if (webTldr !== null) {
    const inventory = extractModuleIdsFromGeneratedTs(webTldr);
    addMissingModuleIds(
      mismatches,
      'WEB_TLDR_MISSING',
      'apps/web/lib/generated/manifest-tldr.ts',
      tldrModules,
      inventory.ids,
      'Generated TLDR metadata'
    );
    addUnexpectedIds(
      mismatches,
      'apps/web/lib/generated/manifest-tldr.ts',
      moduleIds(tldrModules),
      inventory.ids,
      'Generated TLDR metadata'
    );
    addDuplicateIds(
      mismatches,
      'apps/web/lib/generated/manifest-tldr.ts',
      inventory.duplicates,
      'Generated TLDR metadata'
    );
  }

  const lessonIndex = readText(root, 'apps/web/lib/generated/manifest-lessons-index.ts', mismatches);
  if (lessonIndex !== null) {
    const lessonInventory = extractLessonIndex(lessonIndex);
    const allLessonIds = new Set([
      ...lessonInventory.linkIds.ids,
      ...lessonInventory.lookupIds.ids,
    ]);
    addMissingModuleIds(
      mismatches,
      'LESSON_LINK_MISSING',
      'apps/web/lib/generated/manifest-lessons-index.ts',
      lessonModules,
      lessonInventory.linkIds.ids,
      'Generated lesson index'
    );
    addUnexpectedIds(
      mismatches,
      'apps/web/lib/generated/manifest-lessons-index.ts',
      moduleIds(lessonModules),
      allLessonIds,
      'Generated lesson index'
    );
    addDuplicateIds(
      mismatches,
      'apps/web/lib/generated/manifest-lessons-index.ts',
      lessonInventory.linkIds.duplicates,
      'Generated lesson link array'
    );
    addDuplicateIds(
      mismatches,
      'apps/web/lib/generated/manifest-lessons-index.ts',
      lessonInventory.lookupIds.duplicates,
      'Generated lesson lookup map'
    );
    for (const module of lessonModules) {
      const slug = module.web?.lesson_slug;
      if (slug && lessonInventory.linkSlugs.get(module.id) !== slug) {
        mismatches.push({
          code: 'LESSON_LINK_MISSING',
          file: 'apps/web/lib/generated/manifest-lessons-index.ts',
          moduleId: module.id,
          expected: slug,
          actual: lessonInventory.linkSlugs.get(module.id),
          message: `Generated lesson link for "${module.id}" must map to "${slug}"`,
        });
      }
      if (slug && lessonInventory.lookupSlugs.get(module.id) !== slug) {
        mismatches.push({
          code: 'LESSON_LINK_MISSING',
          file: 'apps/web/lib/generated/manifest-lessons-index.ts',
          moduleId: module.id,
          expected: slug,
          actual: lessonInventory.lookupSlugs.get(module.id),
          message: `Generated lesson lookup for "${module.id}" must map to "${slug}"`,
        });
      }
    }
  }

  checkOnboardingLessons(root, lessonModules, mismatches);
  checkReadmeSnippets(readText(root, 'README.md', mismatches), mismatches);

  summary.checked =
    summary.verifiedInstallers +
    summary.modules * 2 +
    summary.doctorChecksExpected +
    summary.webVisibleModules +
    summary.webCommandModules +
    summary.webTldrModules +
    summary.lessonLinkedModules * 2 +
    summary.readmeSnippetsExpected;

  return {
    ok: mismatches.length === 0,
    root,
    summary,
    mismatches,
  };
}

function showHelp(): void {
  console.log(`Usage: bun run src/drift-contract.ts [--root DIR] [--json] [--quiet]

Checks manifest-derived surfaces for semantic drift:
  - checksums.yaml coverage for verified installers
  - scripts/generated/manifest_index.sh module coverage
  - scripts/generated/doctor_checks.sh verify coverage
  - apps/web/lib/generated manifest metadata
  - acfs/onboard/lessons lesson files
  - README release gate snippets
`);
}

function parseArgs(args: string[]): { root: string; json: boolean; quiet: boolean; help: boolean } {
  let root = DEFAULT_ROOT;
  let json = false;
  let quiet = false;
  let help = false;

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    switch (arg) {
      case '--root':
        i += 1;
        if (!args[i]) {
          throw new Error('--root requires a directory argument');
        }
        root = args[i];
        break;
      case '--json':
        json = true;
        break;
      case '--quiet':
        quiet = true;
        break;
      case '--help':
      case '-h':
        help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return { root, json, quiet, help };
}

async function main(): Promise<void> {
  let args: ReturnType<typeof parseArgs>;
  try {
    args = parseArgs(process.argv.slice(2));
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(2);
  }

  if (args.help) {
    showHelp();
    process.exit(0);
  }

  const result = checkManifestDriftContract(args.root);

  if (args.json) {
    console.log(JSON.stringify(result, null, 2));
  } else if (result.ok) {
    if (!args.quiet) {
      console.log(`Manifest drift contract clean: ${result.summary.checked} checks`);
    }
  } else {
    for (const mismatch of result.mismatches) {
      console.error(`[${mismatch.code}] ${mismatch.file}: ${mismatch.message}`);
    }
  }

  process.exit(result.ok ? 0 : 1);
}

if (import.meta.main) {
  main();
}
