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
ACFS_GENERATED_SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "\$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "\$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"
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
if [[ -f "\$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh" ]]; then
    source "\$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh"
fi

# Source contract validation
if [[ -f "\$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh" ]]; then
    source "\$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh"
fi

# Optional security verification for upstream installer scripts.
# Scripts that need it should call: acfs_security_init
ACFS_SECURITY_READY=false
acfs_security_init() {
    if [[ "\${ACFS_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    local security_lib="\$ACFS_GENERATED_SCRIPT_DIR/../lib/security.sh"
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
# shellcheck disable=SC2034
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================
# Data-only manifest index. Safe to source.
`;

// ============================================================
// Security Constants
// ============================================================

/**
 * Allowlist of valid runners for verified_installer.
 * SECURITY: Only allow known-safe shell interpreters.
 * Must match schema.ts VerifiedInstallerRunnerSchema.
 */
const ALLOWED_RUNNERS = new Set(['bash', 'sh']);

// ============================================================
// Helpers
// ============================================================

/**
 * Shell-safe quoting using single quotes.
 * Single quotes prevent all shell expansion except for the single quote character itself.
 * To include a single quote: close the quote, add escaped quote, reopen quote.
 *
 * SECURITY: This is the only safe way to quote arbitrary strings for shell execution.
 *
 * @example
 * shellQuote("hello world") → "'hello world'"
 * shellQuote("it's") → "'it'\\''s'" (which produces: it's)
 * shellQuote("$HOME") → "'$HOME'" (no expansion)
 * shellQuote("$(rm -rf /)") → "'$(rm -rf /)'" (no command execution)
 */
function shellQuote(str: string): string {
  // Replace each single quote with: '\'' (close quote, escaped quote, reopen quote)
  const escaped = str.replace(/'/g, "'\\''");
  return `'${escaped}'`;
}

/**
 * Build the pipe command from verified_installer.runner and args
 *
 * SECURITY: Uses shellQuote() to prevent command injection via args.
 * Runner must be in ALLOWED_RUNNERS (enforced by schema, validated here too).
 */
function buildVerifiedInstallerPipe(module: Module): string {
  const vi = module.verified_installer;
  if (!vi) return '';

  // SECURITY: Validate runner is in allowlist (belt-and-suspenders with schema)
  if (!ALLOWED_RUNNERS.has(vi.runner)) {
    throw new Error(
      `SECURITY: Invalid runner "${vi.runner}" for module "${module.id}". ` +
        `Only ${Array.from(ALLOWED_RUNNERS).join(', ')} allowed.`
    );
  }

  const parts: string[] = [vi.runner];
  if (vi.args && vi.args.length > 0) {
    // SECURITY: Use proper shell quoting to prevent command injection
    for (const arg of vi.args) {
      parts.push(shellQuote(arg));
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

function wrapOptionalVerifyHeredoc(
  module: Module,
  summary: string,
  commandLines: string[]
): string[] {
  const lines: string[] = [];
  const escapedSummary = escapeBash(summary);
  const shellHelper = getRunAsShellHelper(module.run_as);
  const delimiter = toHeredocDelimiter(module.id);

  lines.push('    if [[ "${DRY_RUN:-false}" == "true" ]]; then');
  lines.push(`        log_info "dry-run: verify (optional): ${escapedSummary} (${module.run_as})"`);
  lines.push('    else');
  lines.push(`        if ! ${shellHelper} <<'${delimiter}'`);
  for (const cmd of commandLines) {
    lines.push(cmd);
  }
  lines.push(delimiter);
  lines.push('        then');
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
  const fallbackUrl = vi.fallback_url;
  const runInTmux = vi.run_in_tmux === true;

  // Build the args string for the installer runner invocation.
  const argsStr = vi.args && vi.args.length > 0
    ? vi.args.map(a => shellQuote(a)).join(' ')
    : '';

  // If run_in_tmux is true, we run the installer in a detached tmux session
  // This prevents blocking when the installer starts a long-running server
  if (runInTmux) {
    const tmuxSession = 'acfs-services';
    const lines: string[] = [
      '# Run installer in detached tmux session (run_in_tmux: true)',
      '# This prevents blocking when the installer starts a long-running service',
      `local tmux_session="${tmuxSession}"`,
      '',
      '# Resolve verified installer URL + checksum (fail closed)',
      `local tool="${tool}"`,
      'local url=""',
      'local expected_sha256=""',
      'if acfs_security_init 2>/dev/null; then',
      "    if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then",
      '        url="${KNOWN_INSTALLERS[$tool]:-}"',
      '        expected_sha256="$(get_checksum "$tool" 2>/dev/null)" || expected_sha256=""',
      '    fi',
      'fi',
      '',
      'if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then',
      `    log_error "Missing verified installer URL/checksum for ${module.id}"`,
      '    false',
      'fi',
      '',
      '# Download verified installer to a temp file (so tmux can exec it without pipes)',
      'local tmp_install',
      'tmp_install="$(mktemp "${TMPDIR:-/tmp}/acfs-install-${tool}.XXXXXX" 2>/dev/null)" || tmp_install=""',
      'if [[ -z "$tmp_install" ]]; then',
      `    log_error "Failed to create temp installer for ${module.id}"`,
      '    false',
      'fi',
      '',
      'if ! verify_checksum "$url" "$expected_sha256" "$tool" > "$tmp_install"; then',
      '    rm -f "$tmp_install" 2>/dev/null || true',
      `    log_error "${module.id}: installer verification failed"`,
      '    false',
      'fi',
      'chmod 755 "$tmp_install" 2>/dev/null || true',
      '',
      '# Kill existing session if any (clean slate)',
      'run_as_target tmux kill-session -t "$tmux_session" 2>/dev/null || true',
      '',
      '# Create new detached tmux session and run the installer',
      'if run_as_target tmux new-session -d -s "$tmux_session" ' +
        `${shellQuote(vi.runner)} "$tmp_install"` +
        (argsStr ? ` ${argsStr}` : '') +
        '; then',
      `        log_success "${module.id} installing in tmux session '$tmux_session'"`,
      '        log_info "Attach with: tmux attach -t $tmux_session"',
      '        # Give it a moment to start',
      '        sleep 3',
      '    else',
      `        log_warn "${module.id} tmux installation may have failed"`,
      '    fi',
    ];
    return lines;
  }

  // Standard non-tmux installation
  let execCmd: string;
  if (module.run_as === 'target_user') {
    // Use run_as_target_runner to switch user while preserving stdin
    // When runner is bash/sh, we ALWAYS need -s to read from stdin (piped content)
    // When there are args, we also need -- to separate bash flags from script args
    const parts = ['run_as_target_runner', shellQuote(vi.runner)];

    // Always add -s for bash/sh since we're piping script content to stdin
    // Without -s, bash expects a filename argument, not stdin input
    const needsStdinFlag = ['bash', 'sh'].includes(vi.runner);
    if (needsStdinFlag) {
      parts.push("'-s'");
    }

    if (vi.args && vi.args.length > 0) {
      // Add -- separator before args (unless already present)
      const hasDash = vi.args.includes('--');
      if (!hasDash) {
        parts.push("'--'");
      }
      for (const arg of vi.args) {
        parts.push(shellQuote(arg));
      }
    }
    execCmd = parts.join(' ');
  } else {
    // Default/root: run directly
    execCmd = buildVerifiedInstallerPipe(module);
  }

  const lines: string[] = [
    '# Try security-verified install (no unverified fallback; fail closed)',
    'local install_success=false',
    '',
    'if acfs_security_init 2>/dev/null; then',
    '    # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)',
    '    # The grep ensures we specifically have an associative array, not just any variable',
    "    if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then",
    `        local tool="${tool}"`,
    '        local url=""',
    '        local expected_sha256=""',
    '',
    '        # Safe access with explicit empty default',
    '        url="${KNOWN_INSTALLERS[$tool]:-}"',
    '        expected_sha256="$(get_checksum "$tool" 2>/dev/null)" || expected_sha256=""',
    '',
    '        if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then',
    `            if verify_checksum "$url" "$expected_sha256" "$tool" 2>/dev/null | ${execCmd}; then`,
    '                install_success=true',
    '            fi',
    '        fi',
    '    fi',
    'fi',
  ];

  lines.push('', '# No unverified fallback: verified install is required');
  lines.push('if [[ "$install_success" != "true" ]]; then');
  if (fallbackUrl) {
    lines.push(`    log_error "Unverified fallback_url configured (refusing): ${fallbackUrl}"`);
  }
  lines.push(`    log_error "Verified install failed for ${module.id}"`);
  lines.push('    false');
  lines.push('fi');

  return lines;
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
    // Regex matches: optional whitespace, ||, optional whitespace, true, optional whitespace, optional comment, end of string
    const optionalRegex = /\s*\|\|\s*true\s*(#.*)?$/;
    const isOptional = optionalRegex.test(cmd);
    const cleanCmd = cmd.replace(optionalRegex, '').trim();

    const blockLines = cleanCmd.includes('\n') || cleanCmd.startsWith('|')
      ? cleanCmd.replace(/^\|?\n?/, '').trim().split('\n')
      : [cleanCmd];
    const summary = blockLines[0]?.trim() || 'verify command';

    if (isOptional) {
      lines.push(...wrapOptionalVerifyHeredoc(module, summary, blockLines));
    } else {
      lines.push(
        ...wrapInstallHeredoc(
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

  // Note: Associative array keys must NOT use double quotes inside [] with set -u
  // Using ["key"] causes bash to try variable expansion on $key, failing with "unbound variable"
  // Correct: [key]="value" or ['key']="value"
  lines.push('declare -gA ACFS_MODULE_PHASE=(');
  for (const module of orderedModules) {
    lines.push(`  [${module.id}]="${getModulePhase(module)}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_DEPS=(');
  for (const module of orderedModules) {
    lines.push(`  [${module.id}]="${escapeBash(joinList(module.dependencies))}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_FUNC=(');
  for (const module of orderedModules) {
    lines.push(`  [${module.id}]="${toFunctionName(module.id)}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_CATEGORY=(');
  for (const module of orderedModules) {
    const category = module.category ?? getModuleCategory(module.id);
    lines.push(`  [${module.id}]="${escapeBash(category)}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_TAGS=(');
  for (const module of orderedModules) {
    lines.push(`  [${module.id}]="${escapeBash(joinList(module.tags))}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_DEFAULT=(');
  for (const module of orderedModules) {
    lines.push(`  [${module.id}]="${module.enabled_by_default ? '1' : '0'}"`);
  }
  lines.push(')');
  lines.push('');

  // Mark that the index is fully loaded (used by acfs_resolve_selection)
  lines.push('ACFS_MANIFEST_INDEX_LOADED=true');
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
    // Skip verification for run_in_tmux modules - they install async in a detached session
    // and won't be ready for immediate verification. The installed_check will work on re-runs.
    const skipVerify = module.verified_installer?.run_in_tmux === true;
    if (skipVerify) {
      lines.push('    # Verify skipped: run_in_tmux installs async in detached tmux session');
      lines.push(`    log_info "${module.id}: installation running in background tmux session"`);
      const tmuxSession = 'acfs-services';
      lines.push(`    log_info "Attach with: tmux attach -t ${tmuxSession}"`);
    } else {
      lines.push('    # Verify');
      lines.push(...generateVerifyCommands(module));
    }
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
      const isOptional = /\|\|\s*true\s*$/.test(verify);
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
  // Run the command string in a fresh bash so quoted commands remain intact.
  // Use `bash -o pipefail -c "$cmd"` (NOT `bash -c "… $cmd"`) to avoid breaking
  // when `$cmd` itself contains quotes.
  lines.push('        if bash -o pipefail -c "$cmd" &>/dev/null; then');
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
    lines.push(`source "\$ACFS_GENERATED_SCRIPT_DIR/install_${category}.sh"`);
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

/**
 * Show help message
 */
function showHelp(): void {
  console.log(`ACFS Manifest-to-Installer Generator

Usage: bun run generate [options]

Options:
  --dry-run      Show what would be generated without writing files
  --verbose      Show more details (with --dry-run: show content previews)
  --validate     Validate manifest and checksums coverage, exit with status
  --diff         Show diff between current and generated files
  --help         Show this help message

Examples:
  bun run generate                 # Generate all files
  bun run generate --dry-run       # Preview generation
  bun run generate --validate      # Check for issues (CI friendly)
  bun run generate --diff          # Show what would change
`);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const verbose = args.includes('--verbose');
  const validateOnly = args.includes('--validate');
  const diffMode = args.includes('--diff');
  const help = args.includes('--help') || args.includes('-h');

  if (help) {
    showHelp();
    process.exit(0);
  }

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

  // --validate mode: validation already passed, print success and exit
  if (validateOnly) {
    console.log('✓ Manifest schema valid');
    console.log('✓ Checksums.yaml coverage complete');
    console.log('');
    console.log('Validation passed.');
    process.exit(0);
  }

  // Build map of all files we would generate
  const filesToGenerate: Map<string, { content: string; mode: number }> = new Map();

  // Category scripts
  for (const category of categories) {
    const filename = `install_${category}.sh`;
    const filepath = join(OUTPUT_DIR, filename);
    const content = generateCategoryScript(manifest, category);
    filesToGenerate.set(filepath, { content, mode: 0o755 });
  }

  // Doctor checks
  {
    const filepath = join(OUTPUT_DIR, 'doctor_checks.sh');
    const content = generateDoctorChecks(manifest);
    filesToGenerate.set(filepath, { content, mode: 0o755 });
  }

  // Master installer
  {
    const filepath = join(OUTPUT_DIR, 'install_all.sh');
    const content = generateMasterInstaller(manifest);
    filesToGenerate.set(filepath, { content, mode: 0o755 });
  }

  // Manifest index
  {
    const filepath = join(OUTPUT_DIR, 'manifest_index.sh');
    const content = generateManifestIndex(manifest, manifestSha256);
    filesToGenerate.set(filepath, { content, mode: 0o644 });
  }

  // --diff mode: compare against existing files
  if (diffMode) {
    let hasDiff = false;
    console.log('Comparing generated content against existing files...');
    console.log('');

    for (const [filepath, { content }] of filesToGenerate) {
      const filename = filepath.replace(OUTPUT_DIR + '/', '');
      if (existsSync(filepath)) {
        const existing = readFileSync(filepath, 'utf-8');
        if (existing !== content) {
          hasDiff = true;
          console.log(`[DIFF] ${filename}`);
          if (verbose) {
            // Show a simple line count diff
            const existingLines = existing.split('\n').length;
            const newLines = content.split('\n').length;
            console.log(`       Existing: ${existingLines} lines, Generated: ${newLines} lines`);
          }
        } else {
          console.log(`[OK]   ${filename}`);
        }
      } else {
        hasDiff = true;
        console.log(`[NEW]  ${filename}`);
      }
    }

    console.log('');
    if (hasDiff) {
      console.log('Generated files would change. Run without --diff to update.');
      process.exit(1);
    } else {
      console.log('All generated files are up to date.');
      process.exit(0);
    }
  }

  // --dry-run mode: just show what would be generated
  if (dryRun) {
    for (const [filepath, { content }] of filesToGenerate) {
      const filename = filepath.replace(OUTPUT_DIR + '/', '');
      console.log(`[DRY-RUN] Would generate: ${filename}`);
      if (verbose) {
        console.log('---');
        console.log(content.slice(0, 500) + '...');
        console.log('---');
      }
    }
    console.log('');
    console.log('Dry run complete. No files written.');
    process.exit(0);
  }

  // Normal generation mode: write all files
  mkdirSync(OUTPUT_DIR, { recursive: true });

  const generatedFiles: string[] = [];
  for (const [filepath, { content, mode }] of filesToGenerate) {
    writeFileSync(filepath, content, { mode });
    const filename = filepath.replace(OUTPUT_DIR + '/', '');
    console.log(`Generated: ${filename}`);
    generatedFiles.push(filepath);
  }

  console.log('');
  console.log(`Generated ${generatedFiles.length} files in ${OUTPUT_DIR}`);
}

main().catch((err) => {
  console.error('Generator failed:', err);
  process.exit(1);
});
