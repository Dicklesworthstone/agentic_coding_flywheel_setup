#!/usr/bin/env bun
/**
 * ACFS Manifest-to-Installer Generator
 * Generates bash installer scripts and doctor checks from acfs.manifest.yaml
 *
 * Usage:
 *   bun run packages/manifest/src/generate.ts [--dry-run] [--verbose]
 *   bun run generate (from packages/manifest)
 */

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseManifestFile } from './parser.js';
import {
  getCategories,
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
fi
`;

// ============================================================
// Helpers
// ============================================================

/**
 * Convert module ID to a valid bash function name
 */
function toFunctionName(moduleId: string): string {
  return `install_${moduleId.replace(/\./g, '_')}`;
}

/**
 * Convert module ID to a check ID for doctor
 */
function toCheckId(moduleId: string): string {
  return moduleId.replace(/\./g, '.');
}

/**
 * Escape bash special characters in a string
 */
function escapeBash(str: string): string {
  return str.replace(/'/g, "'\\''");
}

/**
 * Generate the install commands for a module
 */
function generateInstallCommands(module: Module): string[] {
  const lines: string[] = [];

  for (const cmd of module.install) {
    // Check if it's a description (not an actual command)
    if (cmd.startsWith('"') || cmd.match(/^[A-Z][a-z]/)) {
      lines.push(`    # ${cmd}`);
      lines.push(`    log_info "TODO: ${escapeBash(cmd)}"`);
    } else if (cmd.includes('\n') || cmd.startsWith('|')) {
      // Multi-line command (from YAML literal block)
      const cleanCmd = cmd.replace(/^\|?\n?/, '').trim();
      lines.push(`    ${cleanCmd}`);
    } else {
      lines.push(`    ${cmd}`);
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

    if (isOptional) {
      lines.push(`    ${cleanCmd} || log_warn "Optional: ${module.id} verify skipped"`);
    } else {
      lines.push(`    ${cleanCmd} || { log_error "Verify failed: ${module.id}"; return 1; }`);
    }
  }

  return lines;
}

// ============================================================
// Generators
// ============================================================

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
  lines.push('# Format: ID|DESCRIPTION|CHECK_COMMAND');
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

      lines.push(`    "${checkId}${suffix}|${description}|${escapeBash(cleanCmd)}|${isOptional ? 'optional' : 'required'}"`);
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
  lines.push('        IFS="|" read -r id desc cmd optional <<< "$check"');
  lines.push('        ');
  lines.push('        if eval "$cmd" &>/dev/null; then');
  lines.push('            echo -e "\\033[0;32m[ok]\\033[0m $id - $desc"');
  lines.push('            ((passed++))');
  lines.push('        elif [[ "$optional" == "optional" ]]; then');
  lines.push('            echo -e "\\033[0;33m[skip]\\033[0m $id - $desc"');
  lines.push('            ((skipped++))');
  lines.push('        else');
  lines.push('            echo -e "\\033[0;31m[fail]\\033[0m $id - $desc"');
  lines.push('            ((failed++))');
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
