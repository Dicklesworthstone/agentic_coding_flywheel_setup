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
import { parseManifestFile, validateManifestData } from './parser.js';
import {
  validateManifest as validateManifestAdvanced,
  formatValidationErrors,
  validateVerifiedInstallerChecksums,
  type InstallerChecksumEntry,
} from './validate.js';
import {
  getCategories,
  getModuleCategory,
  resolveModuleCategory,
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
const WEB_OUTPUT_DIR = join(PROJECT_ROOT, 'apps/web/lib/generated');
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

# When running a generated installer directly (not sourced by install.sh),
# set sane defaults and derive ACFS paths from the script location so
# contract validation passes and local assets are discoverable.
if [[ "\${BASH_SOURCE[0]}" = "\${0}" ]]; then
    # Match install.sh defaults
    if [[ -z "\${TARGET_USER:-}" ]]; then
        if [[ \$EUID -eq 0 ]] && [[ -z "\${SUDO_USER:-}" ]]; then
            _ACFS_DETECTED_USER="ubuntu"
        else
            _ACFS_DETECTED_USER="\${SUDO_USER:-\$(whoami)}"
        fi
        TARGET_USER="\$_ACFS_DETECTED_USER"
    fi
    unset _ACFS_DETECTED_USER
    MODE="\${MODE:-vibe}"

    if [[ -z "\${TARGET_HOME:-}" ]]; then
        if [[ "\${TARGET_USER}" == "root" ]]; then
            TARGET_HOME="/root"
        elif [[ "\$(whoami 2>/dev/null || true)" == "\${TARGET_USER}" ]]; then
            TARGET_HOME="\${HOME}"
        else
            TARGET_HOME="/home/\${TARGET_USER}"
        fi
    fi

    # Derive "bootstrap" paths from the repo layout (scripts/generated/.. -> repo root).
    if [[ -z "\${ACFS_BOOTSTRAP_DIR:-}" ]]; then
        ACFS_BOOTSTRAP_DIR="\$(cd "\$ACFS_GENERATED_SCRIPT_DIR/../.." && pwd)"
    fi

    ACFS_LIB_DIR="\${ACFS_LIB_DIR:-\$ACFS_BOOTSTRAP_DIR/scripts/lib}"
    ACFS_GENERATED_DIR="\${ACFS_GENERATED_DIR:-\$ACFS_BOOTSTRAP_DIR/scripts/generated}"
    ACFS_ASSETS_DIR="\${ACFS_ASSETS_DIR:-\$ACFS_BOOTSTRAP_DIR/acfs}"
    ACFS_CHECKSUMS_YAML="\${ACFS_CHECKSUMS_YAML:-\$ACFS_BOOTSTRAP_DIR/checksums.yaml}"
    ACFS_MANIFEST_YAML="\${ACFS_MANIFEST_YAML:-\$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml}"

    export TARGET_USER TARGET_HOME MODE
    export ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML
fi
if [[ -f "\$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "\$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    # Progress/status output should go to stderr so stdout stays clean for piping.
    log_step() { echo "[*] \$*" >&2; }
    log_section() { echo "" >&2; echo "=== \$* ===" >&2; }
    log_success() { echo "[OK] \$*" >&2; }
    log_error() { echo "[ERROR] \$*" >&2; }
    log_warn() { echo "[WARN] \$*" >&2; }
    log_info() { echo "    \$*" >&2; }
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
    if [[ "\${ACFS_SECURITY_READY}" = "true" ]]; then
        return 0
    fi

    local security_lib="\$ACFS_GENERATED_SCRIPT_DIR/../lib/security.sh"
    if [[ ! -f "\$security_lib" ]]; then
        log_error "Security library not found: \$security_lib"
        return 1
    fi

    # Use ACFS_CHECKSUMS_YAML if set by install.sh bootstrap (overrides security.sh default)
    if [[ -n "\${ACFS_CHECKSUMS_YAML:-}" ]]; then
        export CHECKSUMS_FILE="\${ACFS_CHECKSUMS_YAML}"
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

const INTERNAL_CHECKSUMS_HEADER = `#!/usr/bin/env bash
# shellcheck disable=SC2034
# ============================================================
# AUTO-GENERATED internal script checksums - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================
# SHA256 checksums for critical internal scripts (bd-3tpl).
# Used by check-manifest-drift.sh to detect unauthorized changes.
`;

/**
 * Critical internal scripts that should be checksummed.
 * Paths are relative to PROJECT_ROOT.
 */
const INTERNAL_SCRIPTS_TO_CHECKSUM = [
  'scripts/lib/security.sh',
  'scripts/lib/agents.sh',
  'scripts/lib/update.sh',
  'scripts/lib/doctor.sh',
  'scripts/lib/install_helpers.sh',
  'scripts/lib/logging.sh',
  'scripts/lib/state.sh',
  'scripts/lib/session.sh',
  'scripts/lib/os_detect.sh',
  'scripts/lib/errors.sh',
  'scripts/lib/user.sh',
  'scripts/lib/tools.sh',
  'scripts/lib/export-config.sh',
  'scripts/acfs-global',
  'scripts/acfs-update',
] as const;

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
 * Quote verified-installer args.
 *
 * Most args are treated as literal words (single-quoted) to prevent injection.
 * However, we allow specific runtime variables to be expanded:
 * - TARGET_HOME
 * - TARGET_USER
 * - TARGET_HOME with Ubuntu default fallback
 * - TARGET_USER with Ubuntu default fallback
 *
 * SECURITY:
 * - We do NOT use a blacklist (e.g. banning `$(`).
 * - We use a strict tokenizer: allowed variables are wrapped in double quotes `"..."`,
 *   and EVERYTHING else is wrapped in single quotes `'...'`.
 * - This ensures that input like `$(rm -rf /)` is treated as a literal string `'$(rm -rf /)'`.
 */
function shellQuoteVerifiedInstallerArg(str: string): string {
  if (str === '') return "''";

  // Regex to capture allowed variables.
  // Order matters: match longest tokens first (${VAR} before $VAR).
  // capturing group () is included in split output.
  const variablePattern = /(\$\{TARGET_HOME:-\/home\/ubuntu\}|\$\{TARGET_USER:-ubuntu\}|\$\{TARGET_HOME\}|\$TARGET_HOME|\$\{TARGET_USER\}|\$TARGET_USER)/g;

  const parts = str.split(variablePattern);

  return parts
    .map((part) => {
      // If it's one of our allowed variables, wrap in double quotes to allow expansion
      if (
        part === '${TARGET_HOME:-/home/ubuntu}' ||
        part === '${TARGET_USER:-ubuntu}' ||
        part === '${TARGET_HOME}' ||
        part === '$TARGET_HOME' ||
        part === '${TARGET_USER}' ||
        part === '$TARGET_USER'
      ) {
        return `"${part}"`;
      }
      // Otherwise, strict single quoting
      // Optimization: skip empty parts (result of split) to avoid empty '' strings
      if (part === '') return '';
      return shellQuote(part);
    })
    .join('');
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

  const parts: string[] = [];
  const envVars = vi.env ?? [];
  const args = vi.args ?? [];

  if (envVars.length > 0) {
    parts.push('env');
    for (const envVar of envVars) {
      parts.push(shellQuoteVerifiedInstallerArg(envVar));
    }
  }
  parts.push(vi.runner);

  // No args: `echo ... | bash` / `echo ... | sh` already reads from stdin.
  if (args.length === 0) {
    return parts.join(' ');
  }

  // Interpret args as: [runner_options..., '--', script_args...]
  // If no '--' is provided, treat all args as script args.
  const dashIndex = args.indexOf('--');
  const runnerArgs = dashIndex === -1 ? [] : args.slice(0, dashIndex);
  const scriptArgs = dashIndex === -1 ? args : args.slice(dashIndex + 1);

  if (!runnerArgs.includes('-s')) {
    runnerArgs.unshift('-s');
  }

  for (const arg of runnerArgs) {
    parts.push(shellQuoteVerifiedInstallerArg(arg));
  }

  if (scriptArgs.length > 0) {
    parts.push(shellQuote('--'));
    for (const arg of scriptArgs) {
      parts.push(shellQuoteVerifiedInstallerArg(arg));
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

/**
 * Encode a doctor-check command into a single-line, tab-safe representation.
 *
 * Why:
 * - We store checks as tab-delimited records in a bash array.
 * - `read` consumes a single line, so raw newlines in commands break parsing.
 *
 * Encoding rules (decoded via `printf '%b'` at runtime):
 * - Backslash -> \\ (preserves literal backslashes, prevents accidental escape decoding)
 * - Tab -> \t  (keeps records parseable)
 * - Newline -> \n (restores multi-line scripts when running the check)
 */
function encodeDoctorCommand(cmd: string): string {
  return cmd
    .replace(/\\/g, '\\\\')
    .replace(/\t/g, '\\t')
    .replace(/\r?\n/g, '\\n');
}

/**
 * Sanitize a string for use in a bash comment.
 * Replaces newlines and other control characters with spaces to prevent
 * breaking the generated script structure.
 */
function sanitizeForBashComment(str: string): string {
  return str.replace(/[\r\n\t]+/g, ' ').trim();
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

  lines.push('    if [[ "${DRY_RUN:-false}" = "true" ]]; then');
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

  lines.push('    if [[ "${DRY_RUN:-false}" = "true" ]]; then');
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

  lines.push('    if [[ "${DRY_RUN:-false}" = "true" ]]; then');
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

function generatePreInstallCheck(module: Module): string[] {
  const check = module.pre_install_check;
  if (!check) {
    return [];
  }

  const lines: string[] = [];
  const shellHelper = getRunAsShellHelper(check.run_as);
  const delimiter = toHeredocDelimiter(`${module.id}_PRE_INSTALL_CHECK`);
  const blockLines = check.command.includes('\n')
    ? check.command.replace(/^\|?\n?/, '').trim().split('\n')
    : [check.command.trim()];
  const summary = summarizeShellBlock(blockLines, 'pre-install check');
  const escapedSummary = escapeBash(summary);

  lines.push('    if [[ "${DRY_RUN:-false}" = "true" ]]; then');
  lines.push(`        log_info "dry-run: pre-install check: ${escapedSummary} (${check.run_as})"`);
  lines.push('    else');
  lines.push(`        if ! ${shellHelper} <<'${delimiter}'`);
  for (const line of blockLines) {
    lines.push(line);
  }
  lines.push(delimiter);
  lines.push('        then');
  lines.push(...indentLines(moduleFailureLines(module, check.skip_message), 12));
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
      if (visiting.has(moduleId)) {
        throw new Error(`Dependency cycle detected in phase: ${moduleId}`);
      }

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
  const runInTmux = vi.run_in_tmux === true;
  const envStr = vi.env && vi.env.length > 0
    ? vi.env.map(a => shellQuoteVerifiedInstallerArg(a)).join(' ')
    : '';

  // Build the args string for the installer runner invocation.
  const argsStr = vi.args && vi.args.length > 0
    ? vi.args.map(a => shellQuoteVerifiedInstallerArg(a)).join(' ')
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
      'if acfs_security_init; then',
      "    if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then",
      '        url="${KNOWN_INSTALLERS[$tool]:-}"',
      '        if ! expected_sha256="$(get_checksum "$tool")"; then',
      `            log_error "${escapeBash(module.id)}: get_checksum failed for tool '$tool'"`,
      '            expected_sha256=""',
      '        fi',
      '    else',
      `        log_error "${escapeBash(module.id)}: KNOWN_INSTALLERS array not available"`,
      '    fi',
      'else',
      `    log_error "${escapeBash(module.id)}: acfs_security_init failed - check security.sh and checksums.yaml"`,
      'fi',
      '',
      'if [[ -z "$url" ]]; then',
      `    log_error "${escapeBash(module.id)}: KNOWN_INSTALLERS[$tool] not found"`,
      '    false',
      'fi',
      'if [[ -z "$expected_sha256" ]]; then',
      `    log_error "${escapeBash(module.id)}: checksum for '$tool' not found"`,
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
        (envStr ? `env ${envStr} ` : '') +
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
    const parts = ['run_as_target_runner'];

    if (vi.env && vi.env.length > 0) {
      parts.push(shellQuote('env'));
      for (const envVar of vi.env) {
        parts.push(shellQuoteVerifiedInstallerArg(envVar));
      }
    }

    parts.push(shellQuote(vi.runner));

    const viArgs = vi.args ?? [];
    const dashIndex = viArgs.indexOf('--');
    const runnerArgs = dashIndex === -1 ? [] : viArgs.slice(0, dashIndex);
    const scriptArgs = dashIndex === -1 ? viArgs : viArgs.slice(dashIndex + 1);

    const needsStdinFlag = ['bash', 'sh'].includes(vi.runner);
    if (needsStdinFlag && !runnerArgs.includes('-s')) {
      runnerArgs.unshift('-s');
    }

    for (const arg of runnerArgs) {
      parts.push(shellQuoteVerifiedInstallerArg(arg));
    }

    if (scriptArgs.length > 0) {
      parts.push(shellQuote('--'));
      for (const arg of scriptArgs) {
        parts.push(shellQuoteVerifiedInstallerArg(arg));
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
  ];

  const verifiedInstallAttemptLines: string[] = [
    'if acfs_security_init; then',
    '    # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)',
    '    # The grep ensures we specifically have an associative array, not just any variable',
    "    if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then",
    `        local tool="${tool}"`,
    '        local url=""',
    '        local expected_sha256=""',
    '',
    '        # Safe access with explicit empty default',
    '        url="${KNOWN_INSTALLERS[$tool]:-}"',
    '        if ! expected_sha256="$(get_checksum "$tool")"; then',
    `            log_error "${escapeBash(module.id)}: get_checksum failed for tool '$tool'"`,
    '            expected_sha256=""',
    '        fi',
    '',
    '        if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then',
    `            if verify_checksum "$url" "$expected_sha256" "$tool" | ${execCmd}; then`,
    '                install_success=true',
    '            else',
    `                log_error "${escapeBash(module.id)}: verify_checksum or installer execution failed"`,
    '            fi',
    '        else',
    '            if [[ -z "$url" ]]; then',
    `                log_error "${escapeBash(module.id)}: KNOWN_INSTALLERS[$tool] not found"`,
    '            fi',
    '            if [[ -z "$expected_sha256" ]]; then',
    `                log_error "${escapeBash(module.id)}: checksum for '$tool' not found"`,
    '            fi',
    '        fi',
    '    else',
    `        log_error "${escapeBash(module.id)}: KNOWN_INSTALLERS array not available"`,
    '    fi',
    'else',
    `    log_error "${escapeBash(module.id)}: acfs_security_init failed - check security.sh and checksums.yaml"`,
    'fi',
  ];

  if (tool === 'ms') {
    const sourceInstallCmd = module.run_as === 'target_user'
      ? 'run_as_target_shell "command -v cargo >/dev/null 2>&1 && cargo install --git https://github.com/Dicklesworthstone/meta_skill --force"'
      : 'command -v cargo >/dev/null 2>&1 && cargo install --git https://github.com/Dicklesworthstone/meta_skill --force';

    lines.push(
      '# meta_skill has no prebuilt Linux ARM64 release asset yet; build from source there.',
      'if [[ "$(uname -s 2>/dev/null)" == "Linux" ]] && { [[ "$(uname -m 2>/dev/null)" == "aarch64" ]] || [[ "$(uname -m 2>/dev/null)" == "arm64" ]]; }; then',
      `    log_info "${escapeBash(module.id)}: Linux ARM64 detected; building meta_skill from source"`,
      `    if ${sourceInstallCmd}; then`,
      '        install_success=true',
      '    else',
      `        log_error "${escapeBash(module.id)}: cargo source install failed for Linux ARM64"`,
      '    fi',
      'else',
      ...indentLines(verifiedInstallAttemptLines, 4),
      'fi',
    );
  } else {
    lines.push(...verifiedInstallAttemptLines);
  }

  lines.push('', '# Verified install is required - no fallback');
  lines.push('if [[ "$install_success" = "true" ]]; then');
  lines.push('    true');
  lines.push('else');
  lines.push(`    log_error "Verified install failed for ${escapeBash(module.id)}"`);
  lines.push('    false');
  lines.push('fi');

  return lines;
}

type NonCommandInstallEntryLabel = 'TODO' | 'NOTE';

function isEntirelyWrappedInMatchingQuotes(value: string): boolean {
  if (value.length < 2) return false;

  const quote = value[0];
  if (quote !== '"' && quote !== "'") return false;
  if (!value.endsWith(quote)) return false;

  for (let i = 1; i < value.length - 1; i++) {
    if (value[i] === quote && value[i - 1] !== '\\') {
      return false;
    }
  }
  return true;
}

function unwrapOptionalQuotes(value: string): string {
  if (isEntirelyWrappedInMatchingQuotes(value)) {
    return value.slice(1, -1).trim();
  }
  return value;
}

function looksLikeDescriptionSentence(value: string): boolean {
  // Keep this conservative: false positives would skip real install commands.
  // Prefer common imperative verbs used in descriptions.
  const prefixes = [
    'Install ',
    'Ensure ',
    'Configure ',
    'Set up ',
    'Setup ',
    'Create ',
    'Write ',
    'Copy ',
    'Add ',
    'Remove ',
    'Link ',
    'Enable ',
    'Disable ',
    'Restart ',
    'Start ',
    'Stop ',
    'Open ',
    'Select ',
    'Choose ',
    'Run ',
  ];

  return prefixes.some((p) => value.startsWith(p));
}

function classifyNonCommandInstallEntry(
  raw: string
): { label: NonCommandInstallEntryLabel; text: string } | null {
  // Multi-line install entries are handled separately via heredocs.
  if (raw.includes('\n')) return null;

  const trimmed = raw.trim();
  if (!trimmed) return null;

  const directiveMatch = /^(TODO|NOTE):\s*(.*)$/i.exec(trimmed);
  if (directiveMatch) {
    const label = directiveMatch[1].toUpperCase() as NonCommandInstallEntryLabel;
    const text = directiveMatch[2].trim();
    return { label, text: text || trimmed };
  }

  const unquoted = unwrapOptionalQuotes(trimmed);
  if (looksLikeDescriptionSentence(unquoted)) {
    return { label: 'TODO', text: unquoted };
  }

  return null;
}

function summarizeShellBlock(blockLines: string[], fallback: string): string {
  const trimmed = blockLines.map((line) => line.trim()).filter(Boolean);
  if (trimmed.length === 0) return fallback;

  const nonComment = trimmed.filter((line) => !line.startsWith('#'));
  if (nonComment.length === 0) return fallback;

  const commandLike = nonComment.find(
    (line) => !/^(?:local\s+)?[A-Za-z_][A-Za-z0-9_]*=(?!=)/.test(line)
  );

  return commandLike ?? nonComment[0] ?? fallback;
}

/**
 * Generate the install commands for a module
 * Uses run_as_*_shell heredocs for proper user context execution
 */
function generateInstallCommands(module: Module): string[] {
  const lines: string[] = [];

  lines.push(...generatePreInstallCheck(module));

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
    const nonCommand = classifyNonCommandInstallEntry(cmd);
    if (nonCommand) {
      lines.push(`    # ${cmd}`);
      lines.push(`    log_info "${nonCommand.label}: ${escapeBash(nonCommand.text)}"`);
    } else if (cmd.includes('\n') || cmd.startsWith('|')) {
      // Multi-line command (from YAML literal block)
      const cleanCmd = cmd.replace(/^\|?\n?/, '').trim();
      const blockLines = cleanCmd.split('\n');
      const summary = summarizeShellBlock(blockLines, 'install command');
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
    const summary = summarizeShellBlock(blockLines, 'verify command');

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

function generatePostInstallMessage(module: Module): string[] {
  const message = module.post_install_message?.trimEnd();
  if (!message) {
    return [];
  }

  const lines: string[] = ['    # Post-install message'];
  for (const line of message.split('\n')) {
    lines.push(`    log_info "${escapeBash(line)}"`);
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
    lines.push(`  ['${module.id}']="${getModulePhase(module)}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_DEPS=(');
  for (const module of orderedModules) {
    lines.push(`  ['${module.id}']="${escapeBash(joinList(module.dependencies))}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_FUNC=(');
  for (const module of orderedModules) {
    lines.push(`  ['${module.id}']="${toFunctionName(module.id)}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_CATEGORY=(');
  for (const module of orderedModules) {
    const category = module.category ?? getModuleCategory(module.id);
    lines.push(`  ['${module.id}']="${escapeBash(category)}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_TAGS=(');
  for (const module of orderedModules) {
    lines.push(`  ['${module.id}']="${escapeBash(joinList(module.tags))}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_DEFAULT=(');
  for (const module of orderedModules) {
    lines.push(`  ['${module.id}']="${module.enabled_by_default ? '1' : '0'}"`);
  }
  lines.push(')');
  lines.push('');

  // Module descriptions for progress display (bd-21kh)
  lines.push('declare -gA ACFS_MODULE_DESC=(');
  for (const module of orderedModules) {
    lines.push(`  ['${module.id}']="${escapeBash(module.description || module.id)}"`);
  }
  lines.push(')');
  lines.push('');

  // Installed check commands for skip-if-present logic (bd-1eop)
  lines.push('declare -gA ACFS_MODULE_INSTALLED_CHECK=(');
  for (const module of orderedModules) {
    if (module.installed_check?.command) {
      lines.push(`  ['${module.id}']="${escapeBash(module.installed_check.command)}"`);
    }
  }
  lines.push(')');
  lines.push('');

  // Installed check run_as context (bd-1eop)
  lines.push('declare -gA ACFS_MODULE_INSTALLED_CHECK_RUN_AS=(');
  for (const module of orderedModules) {
    if (module.installed_check?.run_as) {
      lines.push(`  ['${module.id}']="${escapeBash(module.installed_check.run_as)}"`);
    }
  }
  lines.push(')');
  lines.push('');

  // Mark that the index is fully loaded (used by acfs_resolve_selection)
  lines.push('ACFS_MANIFEST_INDEX_LOADED=true');
  lines.push('');

  return lines.join('\n');
}

/**
 * Generate internal script checksums file (bd-3tpl).
 * Computes SHA256 for critical internal scripts and emits a bash associative array.
 */
function generateInternalChecksums(): string {
  const lines: string[] = [INTERNAL_CHECKSUMS_HEADER];

  lines.push('declare -gA ACFS_INTERNAL_CHECKSUMS=(');
  for (const relPath of INTERNAL_SCRIPTS_TO_CHECKSUM) {
    const absPath = join(PROJECT_ROOT, relPath);
    if (existsSync(absPath)) {
      const content = readFileSync(absPath);
      const hash = createHash('sha256').update(content).digest('hex');
      lines.push(`  [${relPath}]="${hash}"`);
    } else {
      lines.push(`  # MISSING: ${relPath}`);
    }
  }
  lines.push(')');
  lines.push('');

  lines.push(`ACFS_INTERNAL_CHECKSUMS_COUNT=${INTERNAL_SCRIPTS_TO_CHECKSUM.length}`);
  lines.push(`ACFS_INTERNAL_CHECKSUMS_GENERATED="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"`);
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
    lines.push(`# ${sanitizeForBashComment(module.description)}`);
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
    if (module.post_install_message) {
      lines.push('');
      lines.push(...generatePostInstallMessage(module));
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
  lines.push('if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then');
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
  lines.push('# Format: ID<TAB>DESCRIPTION<TAB>CHECK_COMMAND<TAB>REQUIRED/OPTIONAL<TAB>RUN_AS');
  lines.push('# Using tab delimiter to avoid conflicts with | in shell commands');
  lines.push('# Commands are encoded (\\n, \\t, \\\\) and decoded via printf before execution');
  lines.push('');

  // Export check array
  lines.push('declare -a MANIFEST_CHECKS=(');

  const sortedModules = sortModulesByInstallOrder(manifest);

  for (const module of sortedModules) {
    const checkId = toCheckId(module.id);

    for (let i = 0; i < module.verify.length; i++) {
      const verify = module.verify[i];
      // Module is optional if: the module itself is marked optional OR the command ends with || true
      const isOptional = module.optional || /\|\|\s*true\s*(#.*)?$/.test(verify);
      const cleanCmd = verify.replace(/\s*\|\|\s*true\s*$/, '').trim();
      const suffix = module.verify.length > 1 ? `.${i + 1}` : '';
      const description = escapeBash(module.description);
      const encodedCmd = encodeDoctorCommand(cleanCmd);

      // Use tab delimiter (\t) instead of pipe to avoid conflicts with || in commands
      lines.push(`    "${checkId}${suffix}\t${description}\t${escapeBash(encodedCmd)}\t${isOptional ? 'optional' : 'required'}\t${module.run_as}"`);
    }
  }

  lines.push(')');
  lines.push('');
  lines.push('# Execute a manifest check in the requested context without prompting.');
  lines.push('run_manifest_check_command() {');
  lines.push('    local run_as="$1"');
  lines.push('    local cmd="$2"');
  lines.push('    local target_user="${TARGET_USER:-ubuntu}"');
  lines.push('    local target_home="${TARGET_HOME:-}"');
  lines.push('    local target_path=""');
  lines.push('');
  lines.push('    if [[ -z "$target_home" ]]; then');
  lines.push('        if [[ "$target_user" == "root" ]]; then');
  lines.push('            target_home="/root"');
  lines.push('        else');
  lines.push('            target_home="/home/$target_user"');
  lines.push('        fi');
  lines.push('    fi');
  lines.push('');
  lines.push('    target_path="$target_home/.local/bin:$target_home/.acfs/bin:$target_home/.bun/bin:$target_home/.cargo/bin:$target_home/.atuin/bin:$target_home/go/bin:${PATH:-/usr/local/bin:/usr/bin:/bin}"');
  lines.push('');
  lines.push('    case "$run_as" in');
  lines.push('        target_user)');
  lines.push('            if [[ "$(id -un 2>/dev/null || true)" == "$target_user" ]]; then');
  lines.push('                HOME="$target_home" PATH="$target_path" bash -o pipefail -c "$cmd"');
  lines.push('                return $?');
  lines.push('            fi');
  lines.push('            if [[ $EUID -eq 0 ]] && command -v runuser >/dev/null 2>&1; then');
  lines.push('                runuser -u "$target_user" -- env HOME="$target_home" PATH="$target_path" bash -o pipefail -c "$cmd"');
  lines.push('                return $?');
  lines.push('            fi');
  lines.push('            if command -v sudo >/dev/null 2>&1; then');
  lines.push('                sudo -n -u "$target_user" env HOME="$target_home" PATH="$target_path" bash -o pipefail -c "$cmd"');
  lines.push('                return $?');
  lines.push('            fi');
  lines.push('            return 1');
  lines.push('            ;;');
  lines.push('        root)');
  lines.push('            if [[ $EUID -eq 0 ]]; then');
  lines.push('                bash -o pipefail -c "$cmd"');
  lines.push('                return $?');
  lines.push('            fi');
  lines.push('            if command -v sudo >/dev/null 2>&1; then');
  lines.push('                sudo -n env PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}" bash -o pipefail -c "$cmd"');
  lines.push('                return $?');
  lines.push('            fi');
  lines.push('            return 1');
  lines.push('            ;;');
  lines.push('        current|*)');
  lines.push('            bash -o pipefail -c "$cmd"');
  lines.push('            ;;');
  lines.push('    esac');
  lines.push('}');
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
  lines.push('        IFS=$\'\\t\' read -r id desc cmd optional run_as <<< "$check"');
  lines.push('        cmd="$(printf \'%b\' "$cmd")"');
  lines.push('        run_as="${run_as:-current}"');
  lines.push('        ');
  // Run checks in the proper execution context while keeping the script non-interactive.
  // Use ${ACFS_*-default} to respect NO_COLOR (empty preserves empty). Related: bd-39ye
  lines.push('        if run_manifest_check_command "$run_as" "$cmd" &>/dev/null; then');
  lines.push('            echo -e "${ACFS_GREEN-\\033[0;32m}[ok]${ACFS_NC-\\033[0m} $id - $desc"');
  lines.push('            ((passed += 1))');
  lines.push('        elif [[ "$optional" = "optional" ]]; then');
  lines.push('            echo -e "${ACFS_YELLOW-\\033[0;33m}[skip]${ACFS_NC-\\033[0m} $id - $desc"');
  lines.push('            ((skipped += 1))');
  lines.push('        else');
  lines.push('            echo -e "${ACFS_RED-\\033[0;31m}[fail]${ACFS_NC-\\033[0m} $id - $desc"');
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
  lines.push('if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then');
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
  lines.push('# Install all modules in global dependency order');
  lines.push('install_all() {');
  lines.push('    log_section "ACFS Full Installation"');
  lines.push('');

  // Use global sort to ensure dependencies are met across categories
  const orderedModules = sortModulesByPhaseAndDependency(manifest);
  let currentCategory: string | null = null;

  for (const module of orderedModules) {
    const category = resolveModuleCategory(module);
    if (category !== currentCategory) {
      lines.push(`    log_section "Category: ${category}"`);
      currentCategory = category;
    }

    const funcName = toFunctionName(module.id);
    lines.push(`    ${funcName}`);
  }

  lines.push('');
  lines.push('    log_success "All modules installed!"');
  lines.push('}');
  lines.push('');

  // Add main execution
  lines.push('# Run if executed directly');
  lines.push('if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then');
  lines.push('    install_all');
  lines.push('fi');
  lines.push('');

  return lines.join('\n');
}

// ============================================================
// Web Data Generators
// ============================================================

const TS_HEADER = `// ============================================================
// AUTO-GENERATED FROM acfs.manifest.yaml — DO NOT EDIT
// Regenerate: bun run generate (from packages/manifest)
// ============================================================
`;

/**
 * Escape a string for use inside a TypeScript string literal (double-quoted).
 */
function escapeTs(str: string): string {
  return str
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')
    .replace(/\t/g, '\\t');
}

/**
 * Format a string array as a TypeScript literal, one item per line.
 */
function formatTsArray(items: string[], indent: number): string {
  if (items.length === 0) return '[]';
  const pad = ' '.repeat(indent);
  const inner = items.map((item) => `${pad}  "${escapeTs(item)}",`).join('\n');
  return `[\n${inner}\n${pad}]`;
}

/**
 * Get all web-visible modules, sorted by ID for deterministic output.
 */
function getWebVisibleModules(manifest: Manifest): Module[] {
  return manifest.modules
    .filter((m) => m.web && m.web.visible !== false)
    .sort((a, b) => a.id.localeCompare(b.id));
}

/**
 * Generate manifest-tools.ts — web tool data from manifest web metadata.
 * Pure data file, no React imports, tree-shakable.
 */
function generateWebTools(manifest: Manifest): string {
  const modules = getWebVisibleModules(manifest);
  const lines: string[] = [TS_HEADER];

  // Type definition
  lines.push('export interface ManifestWebTool {');
  lines.push('  id: string;');
  lines.push('  moduleId: string;');
  lines.push('  displayName: string;');
  lines.push('  shortName: string;');
  lines.push('  tagline: string;');
  lines.push('  shortDesc: string;');
  lines.push('  icon: string;');
  lines.push('  color: string;');
  lines.push('  categoryLabel?: string;');
  lines.push('  href?: string;');
  lines.push('  features: string[];');
  lines.push('  techStack: string[];');
  lines.push('  useCases: string[];');
  lines.push('  language?: string;');
  lines.push('  stars?: number;');
  lines.push('  cliName?: string;');
  lines.push('  cliAliases: string[];');
  lines.push('  commandExample?: string;');
  lines.push('  lessonSlug?: string;');
  lines.push('  tldrSnippet?: string;');
  lines.push('}');
  lines.push('');

  lines.push('export const manifestTools: ManifestWebTool[] = [');

  for (const module of modules) {
    const web = module.web!;
    lines.push('  {');
    lines.push(`    id: "${escapeTs(module.id.replace(/\./g, '-'))}",`);
    lines.push(`    moduleId: "${escapeTs(module.id)}",`);
    lines.push(`    displayName: "${escapeTs(web.display_name ?? module.description)}",`);
    lines.push(`    shortName: "${escapeTs(web.short_name ?? module.id.split('.').pop() ?? module.id)}",`);
    lines.push(`    tagline: "${escapeTs(web.tagline ?? module.description)}",`);
    lines.push(`    shortDesc: "${escapeTs(web.short_desc ?? module.description)}",`);
    lines.push(`    icon: "${escapeTs(web.icon ?? 'box')}",`);
    lines.push(`    color: "${escapeTs(web.color ?? '#6B7280')}",`);
    if (web.category_label) {
      lines.push(`    categoryLabel: "${escapeTs(web.category_label)}",`);
    }
    if (web.href) {
      lines.push(`    href: "${escapeTs(web.href)}",`);
    }
    lines.push(`    features: ${formatTsArray(web.features ?? [], 4)},`);
    lines.push(`    techStack: ${formatTsArray(web.tech_stack ?? [], 4)},`);
    lines.push(`    useCases: ${formatTsArray(web.use_cases ?? [], 4)},`);
    if (web.language) {
      lines.push(`    language: "${escapeTs(web.language)}",`);
    }
    if (web.stars !== undefined) {
      lines.push(`    stars: ${web.stars},`);
    }
    if (web.cli_name) {
      lines.push(`    cliName: "${escapeTs(web.cli_name)}",`);
    }
    lines.push(`    cliAliases: ${formatTsArray(web.cli_aliases ?? [], 4)},`);
    if (web.command_example) {
      lines.push(`    commandExample: "${escapeTs(web.command_example)}",`);
    }
    if (web.lesson_slug) {
      lines.push(`    lessonSlug: "${escapeTs(web.lesson_slug)}",`);
    }
    if (web.tldr_snippet) {
      lines.push(`    tldrSnippet: "${escapeTs(web.tldr_snippet)}",`);
    }
    lines.push('  },');
  }

  lines.push('];');
  lines.push('');

  return lines.join('\n');
}

/**
 * Generate manifest-commands.ts — CLI command references from manifest web metadata.
 */
function generateWebCommands(manifest: Manifest): string {
  const modules = manifest.modules
    .filter((m) => m.web && m.web.visible !== false && m.web.cli_name)
    .sort((a, b) => a.id.localeCompare(b.id));

  const lines: string[] = [TS_HEADER];

  lines.push('export interface ManifestCommand {');
  lines.push('  moduleId: string;');
  lines.push('  displayName: string;');
  lines.push('  moduleCategory: string;');
  lines.push('  cliName: string;');
  lines.push('  cliAliases: string[];');
  lines.push('  description: string;');
  lines.push('  commandExample?: string;');
  lines.push('  docsUrl?: string;');
  lines.push('}');
  lines.push('');

  lines.push('export const manifestCommands: ManifestCommand[] = [');

  for (const module of modules) {
    const web = module.web!;
    const moduleCategory = resolveModuleCategory(module);
    lines.push('  {');
    lines.push(`    moduleId: "${escapeTs(module.id)}",`);
    lines.push(`    displayName: "${escapeTs(web.display_name ?? module.description)}",`);
    lines.push(`    moduleCategory: "${escapeTs(moduleCategory)}",`);
    lines.push(`    cliName: "${escapeTs(web.cli_name!)}",`);
    lines.push(`    cliAliases: ${formatTsArray(web.cli_aliases ?? [], 4)},`);
    lines.push(`    description: "${escapeTs(web.short_desc ?? module.description)}",`);
    if (web.command_example) {
      lines.push(`    commandExample: "${escapeTs(web.command_example)}",`);
    }
    if (web.href ?? module.docs_url) {
      lines.push(`    docsUrl: "${escapeTs(web.href ?? module.docs_url ?? '')}",`);
    }
    lines.push('  },');
  }

  lines.push('];');
  lines.push('');

  return lines.join('\n');
}

/**
 * Generate manifest-tldr.ts — TL;DR card data from manifest web metadata.
 * Focused subset for the TL;DR summary page.
 */
function generateWebTldr(manifest: Manifest): string {
  const modules = getWebVisibleModules(manifest);
  const lines: string[] = [TS_HEADER];

  // Type definition
  lines.push('export interface ManifestTldrTool {');
  lines.push('  id: string;');
  lines.push('  moduleId: string;');
  lines.push('  displayName: string;');
  lines.push('  shortName: string;');
  lines.push('  tagline: string;');
  lines.push('  tldrSnippet: string;');
  lines.push('  icon: string;');
  lines.push('  color: string;');
  lines.push('  href?: string;');
  lines.push('  features: string[];');
  lines.push('  techStack: string[];');
  lines.push('  useCases: string[];');
  lines.push('  language?: string;');
  lines.push('  stars?: number;');
  lines.push('}');
  lines.push('');

  lines.push('export const manifestTldrTools: ManifestTldrTool[] = [');

  for (const module of modules) {
    const web = module.web!;
    // Only include modules that have a tldr_snippet or tagline (enough content for a TL;DR card)
    const snippet = web.tldr_snippet ?? web.tagline ?? '';
    if (!snippet && !web.tagline) continue;

    lines.push('  {');
    lines.push(`    id: "${escapeTs(module.id.replace(/\./g, '-'))}",`);
    lines.push(`    moduleId: "${escapeTs(module.id)}",`);
    lines.push(`    displayName: "${escapeTs(web.display_name ?? module.description)}",`);
    lines.push(`    shortName: "${escapeTs(web.short_name ?? module.id.split('.').pop() ?? module.id)}",`);
    lines.push(`    tagline: "${escapeTs(web.tagline ?? module.description)}",`);
    lines.push(`    tldrSnippet: "${escapeTs(web.tldr_snippet ?? web.short_desc ?? module.description)}",`);
    lines.push(`    icon: "${escapeTs(web.icon ?? 'box')}",`);
    lines.push(`    color: "${escapeTs(web.color ?? '#6B7280')}",`);
    if (web.href) {
      lines.push(`    href: "${escapeTs(web.href)}",`);
    }
    lines.push(`    features: ${formatTsArray(web.features ?? [], 4)},`);
    lines.push(`    techStack: ${formatTsArray(web.tech_stack ?? [], 4)},`);
    lines.push(`    useCases: ${formatTsArray(web.use_cases ?? [], 4)},`);
    if (web.language) {
      lines.push(`    language: "${escapeTs(web.language)}",`);
    }
    if (web.stars !== undefined) {
      lines.push(`    stars: ${web.stars},`);
    }
    lines.push('  },');
  }

  lines.push('];');
  lines.push('');

  return lines.join('\n');
}

/**
 * Generate manifest-lessons-index.ts — mapping from module IDs to lesson slugs.
 * Used to link module detail pages to onboarding lessons.
 */
function generateWebLessonsIndex(manifest: Manifest): string {
  const modules = manifest.modules
    .filter((m) => m.web && m.web.visible !== false && m.web.lesson_slug)
    .sort((a, b) => a.id.localeCompare(b.id));

  const lines: string[] = [TS_HEADER];

  // Type definition
  lines.push('export interface ManifestLessonLink {');
  lines.push('  moduleId: string;');
  lines.push('  lessonSlug: string;');
  lines.push('  displayName: string;');
  lines.push('}');
  lines.push('');

  lines.push('export const manifestLessonLinks: ManifestLessonLink[] = [');

  for (const module of modules) {
    const web = module.web!;
    lines.push('  {');
    lines.push(`    moduleId: "${escapeTs(module.id)}",`);
    lines.push(`    lessonSlug: "${escapeTs(web.lesson_slug!)}",`);
    lines.push(`    displayName: "${escapeTs(web.display_name ?? module.description)}",`);
    lines.push('  },');
  }

  lines.push('];');
  lines.push('');

  // Convenience lookup map
  lines.push('/** Lookup lesson slug by module ID */');
  lines.push('export const lessonSlugByModuleId: Record<string, string> = {');
  for (const module of modules) {
    const web = module.web!;
    lines.push(`  "${escapeTs(module.id)}": "${escapeTs(web.lesson_slug!)}",`);
  }
  lines.push('};');
  lines.push('');

  return lines.join('\n');
}

/**
 * Generate manifest-web-index.ts — barrel re-export for all web generated data.
 */
function generateWebIndex(): string {
  const lines: string[] = [TS_HEADER];

  lines.push("export { manifestTools } from './manifest-tools';");
  lines.push("export type { ManifestWebTool } from './manifest-tools';");
  lines.push('');
  lines.push("export { manifestTldrTools } from './manifest-tldr';");
  lines.push("export type { ManifestTldrTool } from './manifest-tldr';");
  lines.push('');
  lines.push("export { manifestCommands } from './manifest-commands';");
  lines.push("export type { ManifestCommand } from './manifest-commands';");
  lines.push('');
  lines.push("export { manifestLessonLinks, lessonSlugByModuleId } from './manifest-lessons-index';");
  lines.push("export type { ManifestLessonLink } from './manifest-lessons-index';");
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

  // Preflight: validate dependency graph + generator invariants.
  // - Basic validation returns user-facing warnings (e.g., install steps that are descriptions).
  // - Advanced validation catches generator-breaking issues (e.g., function-name collisions).
  const basicValidation = validateManifestData(manifest);
  if (!basicValidation.valid) {
    console.error('');
    console.error(
      `Manifest validation failed with ${basicValidation.errors.length} error(s):`
    );
    for (const err of basicValidation.errors) {
      console.error(`- ${err.path}: ${err.message}`);
    }
    console.error('');
    process.exit(1);
  }

  const advancedValidation = validateManifestAdvanced(manifest);
  if (!advancedValidation.valid) {
    console.error('');
    console.error(formatValidationErrors(advancedValidation));
    console.error('');
    process.exit(1);
  }

  if (basicValidation.warnings.length > 0) {
    console.error('');
    console.error(`Manifest validation warnings (${basicValidation.warnings.length}):`);
    for (const warn of basicValidation.warnings) {
      console.error(`- ${warn.path}: ${warn.message}`);
    }
    console.error('');
  }

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
      installers?: Record<string, InstallerChecksumEntry>;
    };
    const installers = checksums.installers ?? {};
    const checksumValidationErrors = validateVerifiedInstallerChecksums(
      manifest,
      installers
    );

    if (checksumValidationErrors.length > 0) {
      console.error('Verified installer checksum validation failed:');
      for (const err of checksumValidationErrors) {
        console.error(`- [${err.code}] ${err.message}`);
      }
      console.error(
        'Update checksums.yaml (./scripts/lib/security.sh --update-checksums > checksums.yaml) or reconcile the manifest URLs before regenerating.'
      );
      process.exit(1);
    }
  } catch (err) {
    console.error(`Failed to parse checksums.yaml: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }

  // --validate mode: validation already passed, print success and exit
  if (validateOnly) {
    console.log('✓ Manifest schema valid');
    console.log('✓ Manifest dependency graph valid');
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

  // Internal script checksums (bd-3tpl)
  {
    const filepath = join(OUTPUT_DIR, 'internal_checksums.sh');
    const content = generateInternalChecksums();
    filesToGenerate.set(filepath, { content, mode: 0o644 });
  }

  // Web data: TypeScript modules for apps/web
  {
    const toolsPath = join(WEB_OUTPUT_DIR, 'manifest-tools.ts');
    filesToGenerate.set(toolsPath, { content: generateWebTools(manifest), mode: 0o644 });

    const commandsPath = join(WEB_OUTPUT_DIR, 'manifest-commands.ts');
    filesToGenerate.set(commandsPath, { content: generateWebCommands(manifest), mode: 0o644 });

    const tldrPath = join(WEB_OUTPUT_DIR, 'manifest-tldr.ts');
    filesToGenerate.set(tldrPath, { content: generateWebTldr(manifest), mode: 0o644 });

    const lessonsPath = join(WEB_OUTPUT_DIR, 'manifest-lessons-index.ts');
    filesToGenerate.set(lessonsPath, { content: generateWebLessonsIndex(manifest), mode: 0o644 });

    const indexPath = join(WEB_OUTPUT_DIR, 'manifest-web-index.ts');
    filesToGenerate.set(indexPath, { content: generateWebIndex(), mode: 0o644 });
  }

  // --diff mode: compare against existing files
  if (diffMode) {
    let hasDiff = false;
    console.log('Comparing generated content against existing files...');
    console.log('');

    for (const [filepath, { content }] of filesToGenerate) {
      const filename = filepath.startsWith(WEB_OUTPUT_DIR)
        ? 'web/' + filepath.replace(WEB_OUTPUT_DIR + '/', '')
        : filepath.replace(OUTPUT_DIR + '/', '');
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
      const filename = filepath.startsWith(WEB_OUTPUT_DIR)
        ? 'web/' + filepath.replace(WEB_OUTPUT_DIR + '/', '')
        : filepath.replace(OUTPUT_DIR + '/', '');
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
  mkdirSync(WEB_OUTPUT_DIR, { recursive: true });

  const generatedFiles: string[] = [];
  for (const [filepath, { content, mode }] of filesToGenerate) {
    writeFileSync(filepath, content, { mode });
    const filename = filepath.startsWith(WEB_OUTPUT_DIR)
      ? 'web/' + filepath.replace(WEB_OUTPUT_DIR + '/', '')
      : filepath.replace(OUTPUT_DIR + '/', '');
    console.log(`Generated: ${filename}`);
    generatedFiles.push(filepath);
  }

  console.log('');
  console.log(`Generated ${generatedFiles.length} files (${OUTPUT_DIR} + ${WEB_OUTPUT_DIR})`);
}

main().catch((err) => {
  console.error('Generator failed:', err);
  process.exit(1);
});
