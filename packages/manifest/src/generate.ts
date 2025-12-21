#!/usr/bin/env bun
/**
 * ACFS Manifest-to-Installer Generator
 * Generates bash installer scripts and doctor checks from acfs.manifest.yaml
 *
 * Usage:
 *   bun run packages/manifest/src/generate.ts [--dry-run] [--verbose]
 *   bun run generate (from packages/manifest)
 */

import { createHash } from 'node:crypto';
import { writeFileSync, mkdirSync, readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse as parseYaml } from 'yaml';
import { parseManifestFile } from './parser.js';
import {
  getCategories,
  getModuleCategory,
  getModulesByCategory,
  sortModulesByInstallOrder,
} from './utils.js';
import type { Module, ModuleCategory, Manifest } from './types.js';

// ============================================================
// Configuration
// ============================================================

const SCRIPT_FILE = fileURLToPath(import.meta.url);
const PROJECT_ROOT = resolve(dirname(SCRIPT_FILE), '../../..');
const MANIFEST_PATH = join(PROJECT_ROOT, 'acfs.manifest.yaml');
const OUTPUT_DIR = join(PROJECT_ROOT, 'scripts/generated');
const CHECKSUMS_PATH = join(PROJECT_ROOT, 'checksums.yaml');

const HEADER = `#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Ensure logging functions available
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "\$SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "\$SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    log_step() { echo "[*] \$*"; }
    log_section() { echo ""; echo "=== \$* ==="; }
    log_success() { echo "[OK] \$*"; }
    log_error() { echo "[ERROR] \$*" >&2; }
    log_warn() { echo "[WARN] \$*" >&2; }
    log_info() { echo "    \$*"; }
fi

# Source install helpers (run_as_*_shell, selection helpers)
if [[ -f "\$SCRIPT_DIR/../lib/install_helpers.sh" ]]; then
    source "\$SCRIPT_DIR/../lib/install_helpers.sh"
fi

# Optional security verification for upstream installer scripts.
# Scripts that need it should call: acfs_security_init
ACFS_SECURITY_READY=false
acfs_security_init() {
    if [[ "\${ACFS_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    local security_lib="\$SCRIPT_DIR/../lib/security.sh"
    if [[ ! -f "\$security_lib" ]]; then
        log_error "Security library not found: \$security_lib"
        return 1
    fi

    # shellcheck source=../lib/security.sh
    # shellcheck disable=SC1091  # runtime relative source
    source "\$security_lib"
    load_checksums || { log_error "Failed to load checksums.yaml"; return 1; }
    ACFS_SECURITY_READY=true
    return 0
}
`;

const MANIFEST_INDEX_HEADER = `#!/usr/bin/env bash
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================
# Data-only manifest index. Safe to source.
`;

// ============================================================
// Helpers
// ============================================================

/**
 * Build the pipe command from verified_installer.runner and args
 */
function buildVerifiedInstallerPipe(module: Module): string {
  const vi = module.verified_installer;
  if (!vi) return '';

  const parts = [vi.runner];
  if (vi.args && vi.args.length > 0) {
    // Quote args that contain spaces
    for (const arg of vi.args) {
      parts.push(arg.includes(' ') ? `"${arg}"` : arg);
    }
  }
  return parts.join(' ');
}

/**
 * Map module.run_as to the appropriate shell helper function name
 */
function getRunAsShellHelper(runAs: string): string {
  switch (runAs) {
    case 'target_user':
      return 'run_as_target_shell';
    case 'root':
      return 'run_as_root_shell';
    case 'current':
    default:
      return 'run_as_current_shell';
  }
}

/**
 * Generate a heredoc delimiter from module ID (sanitized, collision-resistant)
 */
function toHeredocDelimiter(moduleId: string): string {
  // Convert module.id to SCREAMING_SNAKE_CASE and prefix with INSTALL_
  return 'INSTALL_' + moduleId.replace(/\./g, '_').toUpperCase();
}

/**
 * Convert module ID to a valid bash function name
 */
function toFunctionName(moduleId: string): string {
  return `install_${moduleId.replace(/\./g, '_')}`;
}

/**
 * Convert module ID to a check ID for doctor
 * Currently a passthrough - kept for future extensibility
 */
function toCheckId(moduleId: string): string {
  return moduleId;
}

/**
 * Escape special characters for use inside double-quoted bash strings.
 * Handles: backslash, double-quote, dollar sign, backtick
 */
function escapeBash(str: string): string {
  return str
    .replace(/\\/g, '\\\\')  // Backslash first (order matters)
    .replace(/"/g, '\\"')    // Double quotes
    .replace(/\$/g, '\\$')   // Dollar sign (prevents variable expansion)
    .replace(/`/g, '\\`');   // Backticks (prevents command substitution)
}

function indentLines(lines: string[], spaces: number): string[] {
  const pad = ' '.repeat(spaces);
  return lines.map((line) => (line.length === 0 ? line : `${pad}${line}`));
}

function moduleFailureLines(module: Module, reason: string): string[] {
  const escapedReason = escapeBash(reason);

  if (module.optional) {
    return [
      `log_warn "${module.id}: ${escapedReason}"`,
      'if type -t record_skipped_tool >/dev/null 2>&1; then',
      `  record_skipped_tool "${module.id}" "${escapedReason}"`,
      'elif type -t state_tool_skip >/dev/null 2>&1; then',
      `  state_tool_skip "${module.id}"`,
      'fi',
      'return 0',
    ];
  }

  return [
    `log_error "${module.id}: ${escapedReason}"`,
    'return 1',
  ];
}

function wrapCommandBlock(
  module: Module,
  summary: string,
  commandLines: string[],
  failureReason: string
): string[] {
  const lines: string[] = [];
  const escapedSummary = escapeBash(summary);

  lines.push('    if [[ "${DRY_RUN:-false}" == "true" ]]; then');
  lines.push(`        log_info "dry-run: ${escapedSummary}"`);
  lines.push('    else');
  lines.push('        if ! {');
  lines.push(...indentLines(commandLines, 12));
  lines.push('        }; then');
  lines.push(...indentLines(moduleFailureLines(module, failureReason), 12));
  lines.push('        fi');
  lines.push('    fi');

  return lines;
}

/**
 * Wrap install commands in a run_as_*_shell heredoc
 * Uses single-quoted delimiter to prevent outer shell expansion
 */
function wrapInstallHeredoc(
  module: Module,
  summary: string,
  commandLines: string[],
  failureReason: string
): string[] {
  const lines: string[] = [];
  const escapedSummary = escapeBash(summary);
  const shellHelper = getRunAsShellHelper(module.run_as);
  const delimiter = toHeredocDelimiter(module.id);

  lines.push('    if [[ "${DRY_RUN:-false}" == "true" ]]; then');
  lines.push(`        log_info "dry-run: ${escapedSummary} (${module.run_as})"`);
  lines.push('    else');
  lines.push(`        if ! ${shellHelper} <<'${delimiter}'`);
  // Commands inside heredoc (no extra indentation - heredoc is literal)
  for (const cmd of commandLines) {
    lines.push(cmd);
  }
  lines.push(delimiter);
  lines.push('        then');
  lines.push(...indentLines(moduleFailureLines(module, failureReason), 12));
  lines.push('        fi');
  lines.push('    fi');

  return lines;
}

function wrapOptionalVerifyBlock(module: Module, summary: string, commandLines: string[]): string[] {
  const lines: string[] = [];
  const escapedSummary = escapeBash(summary);

  lines.push('    if [[ "${DRY_RUN:-false}" == "true" ]]; then');
  lines.push(`        log_info "dry-run: verify (optional): ${escapedSummary}"`);
  lines.push('    else');
  lines.push('        if ! {');
  lines.push(...indentLines(commandLines, 12));
  lines.push('        }; then');
  lines.push(`            log_warn "Optional verify failed: ${module.id}"`);
  lines.push('        fi');
  lines.push('    fi');

  return lines;
}

function getModulePhase(module: Module): number {
  return module.phase ?? 1;
}

function joinList(values?: string[]): string {
  if (!values || values.length === 0) {
    return '';
  }
  return values.join(',');
}

function computeManifestSha256(): string {
  const content = readFileSync(MANIFEST_PATH);
  return createHash('sha256').update(content).digest('hex');
}

function sortModulesByPhaseAndDependency(manifest: Manifest): Module[] {
  const modulesById = new Map(manifest.modules.map((module) => [module.id, module]));
  const modulesByPhase = new Map<number, Module[]>();

  for (const module of manifest.modules) {
    const phase = getModulePhase(module);
    const group = modulesByPhase.get(phase);
    if (group) {
      group.push(module);
    } else {
      modulesByPhase.set(phase, [module]);
    }
  }

  const phases = Array.from(modulesByPhase.keys()).sort((a, b) => a - b);
  const ordered: Module[] = [];

  for (const phase of phases) {
    const phaseModules = modulesByPhase.get(phase) ?? [];
    const phaseIds = new Set(phaseModules.map((module) => module.id));
    const visited = new Set<string>();
    const visiting = new Set<string>();

    function visit(moduleId: string): void {
      if (visited.has(moduleId)) return;
      if (visiting.has(moduleId)) return;

      visiting.add(moduleId);

      const module = modulesById.get(moduleId);
      if (module?.dependencies) {
        for (const depId of module.dependencies) {
          if (phaseIds.has(depId)) {
            visit(depId);
          }
        }
      }

      visiting.delete(moduleId);
      if (module) {
        visited.add(moduleId);
        ordered.push(module);
      }
    }

    for (const module of phaseModules) {
      visit(module.id);
    }
  }

  return ordered;
}

function generateVerifiedInstallerSnippet(module: Module): string[] {
  const vi = module.verified_installer!;
  const tool = vi.tool;
  const pipe = buildVerifiedInstallerPipe(module);

  return [
    '# Verified upstream installer script (checksums.yaml)',
    'if ! acfs_security_init; then',
    `    log_error "Security verification unavailable for ${module.id}"`,
    '    false',
    'else',
    `    local tool="${tool}"`,
    '    local url="${KNOWN_INSTALLERS[$tool]:-}"',
    '    local expected_sha256',
    '    expected_sha256="$(get_checksum "$tool")"',
    '    if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then',
    '        log_error "Missing checksum entry for $tool"',
    '        false',
    '    else',
    `        verify_checksum "$url" "$expected_sha256" "$tool" | ${pipe}`,
    '    fi',
    'fi',
  ];
}

/**
 * Generate the install commands for a module
 * Uses run_as_*_shell heredocs for proper user context execution
 */
function generateInstallCommands(module: Module): string[] {
  const lines: string[] = [];

  // If module has verified_installer, generate that first (before any install commands)
  // Note: verified_installer runs in current context since it needs access to security.sh
  // The actual installer script is piped through the runner, so it runs correctly
  if (module.verified_installer) {
    const snippet = generateVerifiedInstallerSnippet(module);
    const summary = `verified installer: ${module.id}`;
    lines.push(...wrapCommandBlock(module, summary, snippet, 'verified installer failed'));
  }

  // Process remaining install commands via heredocs
  for (const cmd of module.install) {
    // Check if it's a description (not an actual command)
    if (cmd.startsWith('"') || cmd.match(/^[A-Z][a-z]/)) {
      lines.push(`    # ${cmd}`);
      lines.push(`    log_info "TODO: ${escapeBash(cmd)}"`);
    } else if (cmd.includes('\n') || cmd.startsWith('|')) {
      // Multi-line command (from YAML literal block)
      const cleanCmd = cmd.replace(/^\|?\n?/, '').trim();
      const blockLines = cleanCmd.split('\n');
      const summary = blockLines[0]?.trim() || 'install command';
      lines.push(
        ...wrapInstallHeredoc(
          module,
          `install: ${summary}`,
          blockLines,
          `install command failed: ${summary}`
        )
      );
    } else {
      const summary = cmd.trim();
      lines.push(
        ...wrapInstallHeredoc(
          module,
          `install: ${summary}`,
          [summary],
          `install command failed: ${summary}`
        )
      );
    }
  }

  return lines;
}

/**
 * Generate verify commands for a module
 */
function generateVerifyCommands(module: Module): string[] {
  const lines: string[] = [];

  for (const cmd of module.verify) {
    // Skip commands with || true at the end for required checks
    const isOptional = cmd.includes('|| true');
    const cleanCmd = cmd.replace(/\s*\|\|\s*true\s*$/, '').trim();
    const blockLines = cleanCmd.includes('\n') || cleanCmd.startsWith('|')
      ? cleanCmd.replace(/^\|?\n?/, '').trim().split('\n')
      : [cleanCmd];
    const summary = blockLines[0]?.trim() || 'verify command';

    if (isOptional) {
      lines.push(...wrapOptionalVerifyBlock(module, summary, blockLines));
    } else {
      lines.push(
        ...wrapCommandBlock(
          module,
          `verify: ${summary}`,
          blockLines,
          `verify failed: ${summary}`
        )
      );
    }
  }

  return lines;
}

// ============================================================
// Generators
// ============================================================

/**
 * Generate manifest index script (data-only, deterministic)
 */
function generateManifestIndex(manifest: Manifest, manifestSha256: string): string {
  const orderedModules = sortModulesByPhaseAndDependency(manifest);
  const lines: string[] = [MANIFEST_INDEX_HEADER];

  lines.push(`ACFS_MANIFEST_SHA256="${manifestSha256}"`);
  lines.push('');

  lines.push('ACFS_MODULES_IN_ORDER=(');
  for (const module of orderedModules) {
    lines.push(`  "${module.id}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -A ACFS_MODULE_PHASE=(');
  for (const module of orderedModules) {
    lines.push(`  ["${module.id}"]="${getModulePhase(module)}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -A ACFS_MODULE_DEPS=(');
  for (const module of orderedModules) {
    lines.push(`  ["${module.id}"]="${escapeBash(joinList(module.dependencies))}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -A ACFS_MODULE_FUNC=(');
  for (const module of orderedModules) {
    lines.push(`  ["${module.id}"]="${toFunctionName(module.id)}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -A ACFS_MODULE_CATEGORY=(');
  for (const module of orderedModules) {
    const category = module.category ?? getModuleCategory(module.id);
    lines.push(`  ["${module.id}"]="${escapeBash(category)}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -A ACFS_MODULE_TAGS=(');
  for (const module of orderedModules) {
    lines.push(`  ["${module.id}"]="${escapeBash(joinList(module.tags))}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -A ACFS_MODULE_DEFAULT=(');
  for (const module of orderedModules) {
    lines.push(`  ["${module.id}"]="${module.enabled_by_default ? '1' : '0'}"`);
  }
  lines.push(')');
  lines.push('');

  return lines.join('\n');
}

/**
 * Generate a category install script
 */
function generateCategoryScript(manifest: Manifest, category: ModuleCategory): string {
  const modules = getModulesByCategory(manifest, category);
  const sortedModules = sortModulesByInstallOrder({
    ...manifest,
    modules: modules,
  });

  const lines: string[] = [HEADER];
  lines.push(`# Category: ${category}`);
  lines.push(`# Modules: ${sortedModules.length}`);
  lines.push('');

  // Generate individual install functions
  for (const module of sortedModules) {
    const funcName = toFunctionName(module.id);
    lines.push(`# ${module.description}`);
    lines.push(`${funcName}() {`);
    lines.push(`    local module_id="${module.id}"`);
    lines.push('    acfs_require_contract "module:${module_id}" || return 1');
    lines.push(`    log_step "Installing ${module.id}"`);
    lines.push('');

    // Install commands
    lines.push(...generateInstallCommands(module));
    lines.push('');

    // Verify commands
    lines.push('    # Verify');
    lines.push(...generateVerifyCommands(module));
    lines.push('');
    lines.push(`    log_success "${module.id} installed"`);
    lines.push('}');
    lines.push('');
  }

  // Generate main install function for the category
  lines.push(`# Install all ${category} modules`);
  lines.push(`install_${category}() {`);
  lines.push(`    log_section "Installing ${category} modules"`);
  for (const module of sortedModules) {
    const funcName = toFunctionName(module.id);
    lines.push(`    ${funcName}`);
  }
  lines.push('}');
  lines.push('');

  // Add main execution
  lines.push('# Run if executed directly');
  lines.push('if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then');
  lines.push(`    install_${category}`);
  lines.push('fi');
  lines.push('');

  return lines.join('\n');
}

/**
 * Generate doctor checks script
 */
function generateDoctorChecks(manifest: Manifest): string {
  const lines: string[] = [HEADER];
  lines.push('# Doctor checks generated from manifest');
  lines.push('# Format: ID<TAB>DESCRIPTION<TAB>CHECK_COMMAND<TAB>REQUIRED/OPTIONAL');
  lines.push('# Using tab delimiter to avoid conflicts with | in shell commands');
  lines.push('');

  // Export check array
  lines.push('declare -a MANIFEST_CHECKS=(');

  const sortedModules = sortModulesByInstallOrder(manifest);

  for (const module of sortedModules) {
    const checkId = toCheckId(module.id);

    for (let i = 0; i < module.verify.length; i++) {
      const verify = module.verify[i];
      const isOptional = verify.includes('|| true');
      const cleanCmd = verify.replace(/\s*\|\|\s*true\s*$/, '').trim();
      const suffix = module.verify.length > 1 ? `.${i + 1}` : '';
      const description = escapeBash(module.description);

      // Use tab delimiter (\t) instead of pipe to avoid conflicts with || in commands
      lines.push(`    "${checkId}${suffix}\t${description}\t${escapeBash(cleanCmd)}\t${isOptional ? 'optional' : 'required'}"`);
    }
  }

  lines.push(')');
  lines.push('');

  // Add helper function
  lines.push('# Run all manifest checks');
  lines.push('run_manifest_checks() {');
  lines.push('    local passed=0');
  lines.push('    local failed=0');
  lines.push('    local skipped=0');
  lines.push('');
  lines.push('    for check in "${MANIFEST_CHECKS[@]}"; do');
  lines.push('        # Use tab as delimiter (safe - won\'t appear in commands)');
  lines.push('        IFS=$\'\\t\' read -r id desc cmd optional <<< "$check"');
  lines.push('        ');
  // Run checks in a subshell to avoid leaking side effects into this script.
  // Enable pipefail so pipeline-based checks behave as expected.
  lines.push('        if bash -c "set -o pipefail; $cmd" &>/dev/null; then');
  lines.push('            echo -e "\\033[0;32m[ok]\\033[0m $id - $desc"');
  lines.push('            ((passed += 1))');
  lines.push('        elif [[ "$optional" == "optional" ]]; then');
  lines.push('            echo -e "\\033[0;33m[skip]\\033[0m $id - $desc"');
  lines.push('            ((skipped += 1))');
  lines.push('        else');
  lines.push('            echo -e "\\033[0;31m[fail]\\033[0m $id - $desc"');
  lines.push('            ((failed += 1))');
  lines.push('        fi');
  lines.push('    done');
  lines.push('');
  lines.push('    echo ""');
  lines.push('    echo "Passed: $passed, Failed: $failed, Skipped: $skipped"');
  lines.push('    [[ $failed -eq 0 ]]');
  lines.push('}');
  lines.push('');

  // Add main execution
  lines.push('# Run if executed directly');
  lines.push('if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then');
  lines.push('    run_manifest_checks');
  lines.push('fi');
  lines.push('');

  return lines.join('\n');
}

/**
 * Generate master installer script
 */
function generateMasterInstaller(manifest: Manifest): string {
  const categories = getCategories(manifest);
  const lines: string[] = [HEADER];
  lines.push('# Master installer - sources all category scripts');
  lines.push('');

  // Source all category scripts
  for (const category of categories) {
    lines.push(`source "\$SCRIPT_DIR/install_${category}.sh"`);
  }
  lines.push('');

  // Main install function
  lines.push('# Install all modules in order');
  lines.push('install_all() {');
  lines.push('    log_section "ACFS Full Installation"');
  lines.push('');

  for (const category of categories) {
    lines.push(`    install_${category}`);
  }

  lines.push('');
  lines.push('    log_success "All modules installed!"');
  lines.push('}');
  lines.push('');

  // Add main execution
  lines.push('# Run if executed directly');
  lines.push('if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then');
  lines.push('    install_all');
  lines.push('fi');
  lines.push('');

  return lines.join('\n');
}

// ============================================================
// Main
// ============================================================

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const verbose = args.includes('--verbose');

  console.log('ACFS Manifest-to-Installer Generator');
  console.log('=====================================');
  console.log('');

  // Parse manifest
  console.log(`Reading manifest from: ${MANIFEST_PATH}`);
  const result = parseManifestFile(MANIFEST_PATH);

  if (!result.success || !result.data) {
    console.error('Failed to parse manifest:', result.error);
    process.exit(1);
  }

  const manifest = result.data;
  console.log(`Parsed ${manifest.modules.length} modules`);

  const categories = getCategories(manifest);
  console.log(`Categories: ${categories.join(', ')}`);
  console.log('');

  const manifestSha256 = computeManifestSha256();

  // Validate checksum coverage for known upstream installers (fail closed).
  if (!existsSync(CHECKSUMS_PATH)) {
    console.error(`Missing required file: ${CHECKSUMS_PATH}`);
    console.error('Refusing to generate scripts that require checksum verification without checksums.yaml.');
    process.exit(1);
  }

  try {
    const checksums = parseYaml(readFileSync(CHECKSUMS_PATH, 'utf-8')) as {
      installers?: Record<string, { url?: string; sha256?: string }>;
    };
    const installers = checksums.installers ?? {};

    // Validate all verified_installer entries in manifest have checksums.yaml coverage
    const missingTools = new Set<string>();
    for (const module of manifest.modules) {
      if (module.verified_installer) {
        const tool = module.verified_installer.tool;
        const entry = installers[tool];
        if (!entry?.url || !entry?.sha256) {
          missingTools.add(`${tool} (used by ${module.id})`);
        }
      }
    }

    if (missingTools.size > 0) {
      console.error(`checksums.yaml missing installer entries: ${Array.from(missingTools).sort().join(', ')}`);
      console.error('Update checksums.yaml (./scripts/lib/security.sh --update-checksums > checksums.yaml) before regenerating.');
      process.exit(1);
    }
  } catch (err) {
    console.error(`Failed to parse checksums.yaml: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }

  // Ensure output directory exists
  if (!dryRun) {
    mkdirSync(OUTPUT_DIR, { recursive: true });
  }

  const generatedFiles: string[] = [];

  // Generate category scripts
  for (const category of categories) {
    const filename = `install_${category}.sh`;
    const filepath = join(OUTPUT_DIR, filename);
    const content = generateCategoryScript(manifest, category);

    if (dryRun) {
      console.log(`[DRY-RUN] Would generate: ${filename}`);
      if (verbose) {
        console.log('---');
        console.log(content.slice(0, 500) + '...');
        console.log('---');
      }
    } else {
      writeFileSync(filepath, content, { mode: 0o755 });
      console.log(`Generated: ${filename}`);
      generatedFiles.push(filepath);
    }
  }

  // Generate doctor checks
  {
    const filename = 'doctor_checks.sh';
    const filepath = join(OUTPUT_DIR, filename);
    const content = generateDoctorChecks(manifest);

    if (dryRun) {
      console.log(`[DRY-RUN] Would generate: ${filename}`);
    } else {
      writeFileSync(filepath, content, { mode: 0o755 });
      console.log(`Generated: ${filename}`);
      generatedFiles.push(filepath);
    }
  }

  // Generate master installer
  {
    const filename = 'install_all.sh';
    const filepath = join(OUTPUT_DIR, filename);
    const content = generateMasterInstaller(manifest);

    if (dryRun) {
      console.log(`[DRY-RUN] Would generate: ${filename}`);
    } else {
      writeFileSync(filepath, content, { mode: 0o755 });
      console.log(`Generated: ${filename}`);
      generatedFiles.push(filepath);
    }
  }

  // Generate manifest index (data-only)
  {
    const filename = 'manifest_index.sh';
    const filepath = join(OUTPUT_DIR, filename);
    const content = generateManifestIndex(manifest, manifestSha256);

    if (dryRun) {
      console.log(`[DRY-RUN] Would generate: ${filename}`);
    } else {
      writeFileSync(filepath, content, { mode: 0o644 });
      console.log(`Generated: ${filename}`);
      generatedFiles.push(filepath);
    }
  }

  console.log('');
  if (dryRun) {
    console.log('Dry run complete. No files written.');
  } else {
    console.log(`Generated ${generatedFiles.length} files in ${OUTPUT_DIR}`);
  }
}

main().catch((err) => {
  console.error('Generator failed:', err);
  process.exit(1);
});
