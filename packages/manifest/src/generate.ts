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
import {
  closeSync,
  constants,
  fchmodSync,
  fstatSync,
  fsyncSync,
  renameSync,
  unlinkSync,
  writeFileSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  existsSync,
  lstatSync,
  openSync,
} from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parse as parseYaml } from 'yaml';
import {
  parseManifestString,
  validateManifest as validateManifestSchema,
  validateManifestData,
} from './parser.js';
import {
  validateManifest as validateManifestAdvanced,
  formatValidationErrors,
  validateVerifiedInstallerChecksums,
  type InstallerChecksumEntry,
} from './validate.js';
import {
  loadPluginManifestFromFile,
  mergeValidatedPlugins,
  formatPluginDiagnostics,
  type PluginValidationResult,
} from './plugin.js';
import {
  getModuleCategory,
  resolveModuleCategory,
  getModulesByCategory,
  sortModulesByInstallOrder,
  toGeneratedFunctionName,
} from './utils.js';
import { MODULE_CATEGORIES, type Module, type ModuleCategory, type Manifest } from './types.js';

// ============================================================
// Configuration
// ============================================================

const SCRIPT_FILE = fileURLToPath(import.meta.url);
const PROJECT_ROOT = resolve(dirname(SCRIPT_FILE), '../../..');
const MANIFEST_PATH = join(PROJECT_ROOT, 'acfs.manifest.yaml');
const OUTPUT_DIR = join(PROJECT_ROOT, 'scripts/generated');
const WEB_OUTPUT_DIR = join(PROJECT_ROOT, 'apps/web/lib/generated');
const CHECKSUMS_PATH = join(PROJECT_ROOT, 'checksums.yaml');
const VERSION_PATH = join(PROJECT_ROOT, 'VERSION');

export function findUnexpectedGeneratedPaths(
  expectedPaths: Iterable<string>,
  actualPaths: Iterable<string>,
): string[] {
  const expected = new Set(Array.from(expectedPaths, (path) => resolve(path)));
  return Array.from(actualPaths, (path) => resolve(path))
    .filter((path) => !expected.has(path))
    .sort();
}

function inspectRegularFileNoFollow(
  path: string,
  label: string,
): { content: Buffer; mode: number } {
  let fd: number | undefined;
  try {
    fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.nlink !== 1) {
      throw new Error(`${label} is not a single-link regular file: ${path}`);
    }
    return { content: readFileSync(fd), mode: stat.mode & 0o777 };
  } catch (error) {
    if (error instanceof Error && error.message.startsWith(`${label} is not`)) {
      throw error;
    }
    throw new Error(`${label} could not be opened safely: ${path}`, { cause: error });
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

function readRegularFileNoFollow(path: string, label: string): Buffer {
  return inspectRegularFileNoFollow(path, label).content;
}

function assertSafeGeneratedDirectory(directory: string): void {
  const rel = relative(PROJECT_ROOT, directory);
  if (rel === '' || rel === '..' || rel.startsWith(`..${process.platform === 'win32' ? '\\' : '/'}`)) {
    throw new Error(`Generated output directory escapes the project root: ${directory}`);
  }

  let current = PROJECT_ROOT;
  for (const segment of rel.split(/[\\/]+/)) {
    current = join(current, segment);
    if (!existsSync(current)) return;
    const stat = lstatSync(current);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw new Error(`Generated output parent is not a real directory: ${current}`);
    }
  }
}

function writeGeneratedFileNoFollow(path: string, content: string, mode: number): void {
  if (existsSync(path)) {
    const stat = lstatSync(path);
    if (stat.isSymbolicLink() || !stat.isFile() || stat.nlink !== 1) {
      throw new Error(`Refusing unsafe generated output target: ${path}`);
    }
  }

  // Write to a sibling temp file and rename it over the target so a crash
  // mid-write (or a concurrent reader — install.sh sources these files) can
  // never observe a truncated generated file. O_EXCL on the temp path keeps
  // the no-symlink-target guarantees: we never open the destination at all.
  const tmpPath = `${path}.tmp-${process.pid}`;
  let fd: number | undefined;
  let renamed = false;
  try {
    fd = openSync(
      tmpPath,
      constants.O_WRONLY | constants.O_NOFOLLOW | constants.O_CREAT | constants.O_EXCL,
      mode,
    );
    writeFileSync(fd, content);
    fchmodSync(fd, mode); // umask may have masked bits at open()
    fsyncSync(fd);
    closeSync(fd);
    fd = undefined;
    renameSync(tmpPath, path);
    renamed = true;
  } finally {
    if (fd !== undefined) closeSync(fd);
    if (!renamed) {
      try {
        unlinkSync(tmpPath);
      } catch {
        // best-effort cleanup; the .tmp-<pid> file is inert if left behind
      }
    }
  }
}

const HEADER = `#!/bin/bash -p
# shellcheck disable=SC1090,SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Generated scripts can execute root-context manifest commands. Establish the
# same OS-owned command-search invariant as install.sh before even resolving
# this script's directory.
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

# Resolve the script itself before deriving any trusted sibling path. Bash
# preserves the lexical symlink invocation in BASH_SOURCE, so dirname alone
# would let an attacker-selected sibling lib directory become the trust root.
if [[ ! -x /usr/bin/readlink ]] \
    || ! ACFS_GENERATED_SCRIPT_PATH="\$(/usr/bin/readlink -f -- "\${BASH_SOURCE[0]}" 2>/dev/null)" \
    || [[ -z "\$ACFS_GENERATED_SCRIPT_PATH" ]] \
    || [[ ! -f "\$ACFS_GENERATED_SCRIPT_PATH" ]]; then
    printf '[ERROR] Unable to canonicalize generated installer path\n' >&2
    return 1 2>/dev/null || exit 1
fi
ACFS_GENERATED_SCRIPT_DIR="\${ACFS_GENERATED_SCRIPT_PATH%/*}"
[[ -n "\$ACFS_GENERATED_SCRIPT_DIR" ]] || ACFS_GENERATED_SCRIPT_DIR="/"

# Ensure logging functions available
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
    # This marker is process-minted control state, never caller configuration.
    # Discard any inherited value before deciding whether this script owns the
    # helper security boundary or is being sourced by install.sh.
    unset ACFS_FORCE_INSTALL_HELPERS_SECURITY_REDEFINE
    if [[ "\${BASH_SOURCE[0]}" == "\$0" ]]; then
        ACFS_FORCE_INSTALL_HELPERS_SECURITY_REDEFINE=1
    fi
    source "\$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh"
    unset ACFS_FORCE_INSTALL_HELPERS_SECURITY_REDEFINE
fi

acfs_generated_system_binary_path() {
    local name="\${1:-}"
    local candidate=""

    [[ -n "\$name" ]] || return 1
    case "\$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \\
        "/usr/bin/\$name" \\
        "/bin/\$name" \\
        "/usr/sbin/\$name" \\
        "/sbin/\$name"
    do
        [[ -x "\$candidate" ]] || continue
        printf '%s\\n' "\$candidate"
        return 0
    done

    return 1
}

acfs_generated_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="\$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    if [[ -n "\$id_bin" ]]; then
        current_user="\$("\$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "\$current_user" ]]; then
        whoami_bin="\$(acfs_generated_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "\$whoami_bin" ]]; then
            current_user="\$("\$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "\$current_user" ]] || return 1
    printf '%s\\n' "\$current_user"
}

acfs_generated_getent_passwd_entry() {
    local user="\${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="\$(acfs_generated_system_binary_path getent 2>/dev/null || true)"
    if [[ -z "\$user" ]]; then
        if [[ -n "\$getent_bin" ]]; then
            while IFS= read -r passwd_line; do
                printf '%s\\n' "\$passwd_line"
                printed_any=true
            done < <("\$getent_bin" passwd 2>/dev/null || true)
            if [[ "\$printed_any" == true ]]; then
                return 0
            fi
        fi

        [[ -r /etc/passwd ]] || return 1
        while IFS= read -r passwd_line; do
            printf '%s\\n' "\$passwd_line"
        done < /etc/passwd
        return 0
    fi

    if [[ -n "\$getent_bin" ]]; then
        passwd_entry="\$("\$getent_bin" passwd "\$user" 2>/dev/null || true)"
    fi

    if [[ -z "\$passwd_entry" ]] && [[ -r /etc/passwd ]]; then
        while IFS= read -r passwd_line; do
            [[ "\${passwd_line%%:*}" == "\$user" ]] || continue
            passwd_entry="\$passwd_line"
            break
        done < /etc/passwd
    fi

    [[ -n "\$passwd_entry" ]] || return 1
    printf '%s\\n' "\$passwd_entry"
}

acfs_generated_passwd_home_from_entry() {
    local passwd_entry="\${1:-}"
    local passwd_home=""

    [[ -n "\$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "\$passwd_entry"
    if [[ -n "\$passwd_home" ]] && [[ "\$passwd_home" == /* ]] && [[ "\$passwd_home" != "/" ]]; then
        printf '%s\\n' "\${passwd_home%/}"
        return 0
    fi

    return 1
}

acfs_generated_target_user_exists() {
    local user="\${1:-}"
    local id_bin=""

    [[ -n "\$user" ]] || return 1
    id_bin="\$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    [[ -n "\$id_bin" ]] || return 1
    "\$id_bin" "\$user" >/dev/null 2>&1
}

acfs_generated_default_home_for_new_user() {
    local user="\${1:-}"

    [[ -n "\$user" ]] || return 1
    [[ "\$user" =~ ^[a-z_][a-z0-9._-]*$ ]] || return 1

    if [[ "\$user" == "root" ]]; then
        printf '/root\\n'
        return 0
    fi

    printf '/home/%s\\n' "\$user"
}

# When running a generated installer directly (not sourced by install.sh),
# set sane defaults and derive ACFS paths from the script location so
# contract validation passes and local assets are discoverable.
if [[ "\${BASH_SOURCE[0]}" == "\$0" ]]; then
    # Match install.sh defaults
    if [[ -z "\${TARGET_USER:-}" ]]; then
        if [[ \$EUID -eq 0 ]] && [[ -z "\${SUDO_USER:-}" ]]; then
            _ACFS_DETECTED_USER="ubuntu"
        else
            _ACFS_DETECTED_USER="\${SUDO_USER:-}"
            if [[ -z "\$_ACFS_DETECTED_USER" ]]; then
                _ACFS_DETECTED_USER="\$(acfs_generated_resolve_current_user 2>/dev/null || true)"
            fi
            if [[ -z "\$_ACFS_DETECTED_USER" ]]; then
                log_error "Unable to resolve the current user for TARGET_USER"
                exit 1
            fi
        fi
        TARGET_USER="\$_ACFS_DETECTED_USER"
    fi
    unset _ACFS_DETECTED_USER

    if declare -f _acfs_validate_target_user >/dev/null 2>&1; then
        _acfs_validate_target_user "\${TARGET_USER}" "TARGET_USER" || exit 1
    elif [[ -z "\${TARGET_USER:-}" ]] || [[ ! "\${TARGET_USER}" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        log_error "Invalid TARGET_USER '\${TARGET_USER:-<empty>}' (expected: lowercase user name like 'ubuntu')"
        exit 1
    fi

    MODE="\${MODE:-vibe}"

    _ACFS_EXPLICIT_TARGET_HOME="\${TARGET_HOME:-}"
    if [[ -n "\$_ACFS_EXPLICIT_TARGET_HOME" ]]; then
        _ACFS_EXPLICIT_TARGET_HOME="\${_ACFS_EXPLICIT_TARGET_HOME%/}"
    fi
    _ACFS_RESOLVED_TARGET_HOME=""
    if declare -f _acfs_resolve_target_home >/dev/null 2>&1; then
        _ACFS_RESOLVED_TARGET_HOME="\$(_acfs_resolve_target_home "\${TARGET_USER}" "\$_ACFS_EXPLICIT_TARGET_HOME" || true)"
    else
        if [[ "\${TARGET_USER}" == "root" ]]; then
            _ACFS_RESOLVED_TARGET_HOME="/root"
        else
            _acfs_passwd_entry="\$(acfs_generated_getent_passwd_entry "\${TARGET_USER}" 2>/dev/null || true)"
            if [[ -n "\$_acfs_passwd_entry" ]]; then
                _ACFS_RESOLVED_TARGET_HOME="\$(acfs_generated_passwd_home_from_entry "\$_acfs_passwd_entry" 2>/dev/null || true)"
            else
                _acfs_current_user="\$(acfs_generated_resolve_current_user 2>/dev/null || true)"
                _acfs_current_home="\${HOME:-}"
                if [[ -n "\$_acfs_current_home" ]]; then
                    _acfs_current_home="\${_acfs_current_home%/}"
                fi
                if [[ "\${_acfs_current_user:-}" == "\${TARGET_USER}" ]] && [[ -n "\$_acfs_current_home" ]] && [[ "\$_acfs_current_home" == /* ]] && [[ "\$_acfs_current_home" != "/" ]] && { [[ -z "\$_ACFS_EXPLICIT_TARGET_HOME" ]] || [[ "\$_acfs_current_home" == "\$_ACFS_EXPLICIT_TARGET_HOME" ]]; }; then
                    _ACFS_RESOLVED_TARGET_HOME="\$_acfs_current_home"
                fi
                unset _acfs_current_user _acfs_current_home
            fi
            unset _acfs_passwd_entry
        fi
    fi
    if [[ -z "\$_ACFS_RESOLVED_TARGET_HOME" ]] && [[ \$EUID -eq 0 ]] && ! acfs_generated_target_user_exists "\${TARGET_USER}"; then
        if [[ -n "\$_ACFS_EXPLICIT_TARGET_HOME" ]] && [[ "\$_ACFS_EXPLICIT_TARGET_HOME" == /* ]] && [[ "\$_ACFS_EXPLICIT_TARGET_HOME" != "/" ]]; then
            _ACFS_RESOLVED_TARGET_HOME="\$_ACFS_EXPLICIT_TARGET_HOME"
        else
            _ACFS_RESOLVED_TARGET_HOME="\$(acfs_generated_default_home_for_new_user "\${TARGET_USER}" 2>/dev/null || true)"
        fi
    fi
    if [[ -n "\$_ACFS_RESOLVED_TARGET_HOME" ]]; then
        TARGET_HOME="\${_ACFS_RESOLVED_TARGET_HOME%/}"
    fi
    unset _ACFS_EXPLICIT_TARGET_HOME _ACFS_RESOLVED_TARGET_HOME

    if [[ -z "\${TARGET_HOME:-}" ]] || [[ "\${TARGET_HOME}" == "/" ]] || [[ "\${TARGET_HOME}" != /* ]]; then
        log_error "Invalid TARGET_HOME for '\${TARGET_USER}': \${TARGET_HOME:-<empty>} (must be an absolute path and cannot be '/')"
        exit 1
    fi

    # Internal path/checksum authority is process-minted in direct mode. Never
    # accept caller-provided ACFS_* path overrides or CHECKSUMS_FILE here.
    unset ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR
    unset ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML CHECKSUMS_FILE
    unset ACFS_MANIFEST_INDEX_LOADED ACFS_GENERATED_SELECTION_READY
    if ! ACFS_BOOTSTRAP_DIR="\$(/usr/bin/readlink -f -- "\$ACFS_GENERATED_SCRIPT_DIR/../.." 2>/dev/null)" \
        || [[ -z "\$ACFS_BOOTSTRAP_DIR" ]] \
        || [[ "\$ACFS_BOOTSTRAP_DIR" == "/" ]] \
        || [[ ! -d "\$ACFS_BOOTSTRAP_DIR" ]]; then
        log_error "Unable to derive generated installer repository root"
        exit 1
    fi

    ACFS_BIN_DIR="\${ACFS_BIN_DIR:-\$TARGET_HOME/.local/bin}"
    if [[ -z "\${ACFS_BIN_DIR:-}" ]] || [[ "\${ACFS_BIN_DIR}" == "/" ]] || [[ "\${ACFS_BIN_DIR}" != /* ]]; then
        log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: \${ACFS_BIN_DIR:-<empty>})"
        exit 1
    fi
    ACFS_LIB_DIR="\$ACFS_BOOTSTRAP_DIR/scripts/lib"
    ACFS_GENERATED_DIR="\$ACFS_BOOTSTRAP_DIR/scripts/generated"
    ACFS_ASSETS_DIR="\$ACFS_BOOTSTRAP_DIR/acfs"
    ACFS_CHECKSUMS_YAML="\$ACFS_BOOTSTRAP_DIR/checksums.yaml"
    ACFS_MANIFEST_YAML="\$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml"

    export TARGET_USER TARGET_HOME MODE ACFS_BIN_DIR
    export ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML

fi

acfs_generated_ensure_selection() {
    if [[ "\${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        local manifest_index="\${ACFS_GENERATED_DIR:-\$ACFS_GENERATED_SCRIPT_DIR}/manifest_index.sh"
        if [[ ! -f "\$manifest_index" ]]; then
            log_error "Manifest index not found: \$manifest_index"
            return 1
        fi
        source "\$manifest_index"
        ACFS_MANIFEST_INDEX_LOADED=true
        export ACFS_MANIFEST_INDEX_LOADED
    fi

    if [[ "\${ACFS_GENERATED_SELECTION_READY:-false}" != "true" ]]; then
        if ! declare -f acfs_resolve_selection >/dev/null 2>&1; then
            log_error "Install selection helper not loaded"
            return 1
        fi
        acfs_resolve_selection || return 1
        ACFS_GENERATED_SELECTION_READY=true
        export ACFS_GENERATED_SELECTION_READY
    fi

    return 0
}

acfs_generated_should_run_module() {
    local module_id="\${1:-}"
    [[ -n "\$module_id" ]] || return 1
    acfs_generated_ensure_selection || return 1
    should_run_module "\$module_id"
}

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

function sourceOnlyHeader(message: string): string {
  return HEADER.replace(
    '#!/bin/bash -p\n# shellcheck disable=SC1090,SC1091\n',
    `#!/bin/bash -p
# shellcheck disable=SC1090,SC1091
if [[ "\${BASH_SOURCE[0]}" == "\$0" ]]; then
    builtin printf '%s\\n' '${message}' >&2
    exit 2
fi
`
  );
}

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
# SHA256 checksums for checksum-controlled runtime files (bd-3tpl).
# Parsed as inert data by install.sh and used by check-manifest-drift.sh.
`;

/**
 * Critical internal scripts that should be checksummed.
 * Paths are relative to PROJECT_ROOT.
 */
const INTERNAL_SCRIPTS_TO_CHECKSUM = [
  'install.sh',
  'checksums.yaml',
  'scripts/preflight.sh',
  'scripts/lib/security.sh',
  'scripts/lib/github_api.sh',
  'scripts/lib/contract.sh',
  'scripts/lib/agents.sh',
  'scripts/lib/update.sh',
  'scripts/lib/doctor.sh',
  'scripts/lib/acfs-services.sh',
  'scripts/lib/doctor_fix.sh',
  'scripts/lib/offline_artifact_pack.sh',
  'scripts/lib/autofix.sh',
  'scripts/lib/autofix_existing.sh',
  'scripts/lib/autofix_unattended.sh',
  'scripts/lib/autofix_version_managers.sh',
  'scripts/lib/ubuntu_upgrade.sh',
  'scripts/lib/upgrade_resume.sh',
  'scripts/lib/install_helpers.sh',
  'scripts/lib/logging.sh',
  'scripts/lib/output.sh',
  'scripts/lib/gum_ui.sh',
  'scripts/lib/progress.sh',
  'scripts/lib/state.sh',
  'scripts/lib/report.sh',
  'scripts/lib/error_tracking.sh',
  'scripts/lib/session.sh',
  'scripts/lib/os_detect.sh',
  'scripts/lib/errors.sh',
  'scripts/lib/user.sh',
  'scripts/lib/tools.sh',
  'scripts/lib/tailscale.sh',
  'scripts/lib/webhook.sh',
  'scripts/lib/notify.sh',
  'scripts/lib/stack.sh',
  'scripts/lib/export-config.sh',
  'scripts/acfs-global',
  'scripts/acfs-update',
  'scripts/lib/nightly_update.sh',
  'scripts/templates/acfs-upgrade-resume.service',
  'scripts/templates/acfs-nightly-update.service',
  'scripts/templates/acfs-nightly-update.timer',
  'packages/onboard/onboard.sh',
  'scripts/generated/manifest_index.sh',
  'scripts/generated/doctor_checks.sh',
  'scripts/generated/install_all.sh',
  ...MODULE_CATEGORIES.map((category) => `scripts/generated/install_${category}.sh`),
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
 * - TARGET_USER with Ubuntu default fallback
 * - $$ for per-process temp directories
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
  const variablePattern = /(\$\{TARGET_USER:-ubuntu\}|\$\{TARGET_HOME\}|\$TARGET_HOME|\$\{TARGET_USER\}|\$TARGET_USER|\$\$)/g;

  const parts = str.split(variablePattern);

  return parts
    .map((part) => {
      // If it's one of our allowed variables, wrap in double quotes to allow expansion
      if (
        part === '${TARGET_USER:-ubuntu}' ||
        part === '${TARGET_HOME}' ||
        part === '$TARGET_HOME' ||
        part === '${TARGET_USER}' ||
        part === '$TARGET_USER' ||
        part === '$$'
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
 * Build the command that executes a fully staged verified installer file.
 *
 * SECURITY: Uses shellQuote() to prevent command injection via args.
 * Runner must be in ALLOWED_RUNNERS (enforced by schema, validated here too).
 */
function buildVerifiedInstallerFileCommand(module: Module): string {
  const vi = module.verified_installer;
  if (!vi) return '';

  if (module.run_as !== 'target_user') {
    throw new Error(
      `SECURITY: verified installer for module "${module.id}" must use the clean target-user runner.`
    );
  }

  // SECURITY: Validate runner is in allowlist (belt-and-suspenders with schema)
  if (!ALLOWED_RUNNERS.has(vi.runner)) {
    throw new Error(
      `SECURITY: Invalid runner "${vi.runner}" for module "${module.id}". ` +
        `Only ${Array.from(ALLOWED_RUNNERS).join(', ')} allowed.`
    );
  }

  const parts: string[] = ['run_as_target_runner'];
  const envVars = vi.env ?? [];
  const args = vi.args ?? [];
  const tmpdirEnvValue = verifiedInstallerTmpdirEnvValue(module);

  if (envVars.length > 0) {
    parts.push(shellQuote('env'));
    for (const envVar of envVars) {
      if (tmpdirEnvValue && envVar.startsWith('TMPDIR=')) {
        parts.push('"TMPDIR=$verified_installer_tmpdir"');
      } else {
        parts.push(shellQuoteVerifiedInstallerArg(envVar));
      }
    }
  }
  parts.push(shellQuote(vi.runner));

  // A leading `--` is a manifest-only separator and is never passed to the
  // interpreter. Any later separator would imply runner options and is unsafe.
  const scriptArgs = normalizeVerifiedInstallerScriptArgs(module.id, args);

  // The file is created by acfs_security_mktemp, populated only after
  // verification succeeds, and made read-only before this command runs.
  // Executing it by pathname prevents a late producer/read failure from
  // feeding and executing only a prefix of the verified script.
  parts.push('"$verified_installer_file"');

  if (scriptArgs.length > 0) {
    for (const arg of scriptArgs) {
      parts.push(shellQuoteVerifiedInstallerArg(arg));
    }
  }

  return parts.join(' ');
}

export function normalizeVerifiedInstallerScriptArgs(
  moduleId: string,
  args: readonly string[],
): string[] {
  const separatorIndex = args.indexOf('--');
  if (separatorIndex > 0) {
    throw new Error(
      `SECURITY: verified installer for module "${moduleId}" contains runner options before --.`
    );
  }
  return separatorIndex === 0 ? args.slice(1) : [...args];
}

function verifiedInstallerTmpdirEnvValue(module: Module): string | null {
  if (module.run_as !== 'target_user') return null;

  const envVars = module.verified_installer?.env ?? [];
  const tmpdirEnv = envVars.find((envVar) => envVar.startsWith('TMPDIR='));
  if (!tmpdirEnv) return null;

  const value = tmpdirEnv.slice('TMPDIR='.length);
  return value.length > 0 ? value : null;
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
    .replace(/`/g, '\\`')    // Backticks (prevents command substitution)
    .replace(/\n/g, ' ')     // Newlines break double-quoted strings in generated scripts
    .replace(/\r/g, '');     // Strip carriage returns
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

const OPTIONAL_VERIFY_TRUE_SUFFIX = /\s*\|\|\s*true\s*(?:#.*)?$/;

export function isOptionalVerifyCommand(command: string): boolean {
  return OPTIONAL_VERIFY_TRUE_SUFFIX.test(command);
}

export function stripOptionalVerifySuffix(command: string): string {
  return command.replace(OPTIONAL_VERIFY_TRUE_SUFFIX, '').trim();
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

function generatedHelperPreludeLines(): string[] {
  const startMarker = 'acfs_generated_system_binary_path() {';
  const endMarker = '\n# When running a generated installer directly';
  const start = HEADER.indexOf(startMarker);
  const end = HEADER.indexOf(endMarker, start);

  if (start < 0 || end < 0) {
    throw new Error('Generated helper prelude markers not found in header');
  }

  return HEADER.slice(start, end).trimEnd().split('\n');
}

function generatedSystemBinaryPreludeLines(): string[] {
  const startMarker = 'acfs_generated_system_binary_path() {';
  const endMarker = '\n\nacfs_generated_resolve_current_user() {';
  const start = HEADER.indexOf(startMarker);
  const end = HEADER.indexOf(endMarker, start);

  if (start < 0 || end < 0) {
    throw new Error('Generated system-binary helper prelude markers not found in header');
  }

  return HEADER.slice(start, end).trimEnd().split('\n');
}

function commandLinesNeedGeneratedHelpers(commandLines: string[]): boolean {
  return commandLines.some((line) => line.includes('acfs_generated_'));
}

function commandLinesNeedPrimaryBinHelpers(commandLines: string[]): boolean {
  return commandLines.some(
    (line) =>
      line.includes('acfs_link_primary_bin_command') ||
      line.includes('acfs_install_executable_into_primary_bin')
  );
}

function primaryBinHelperPreludeLines(): string[] {
  return [
    'acfs_child_log_error() {',
    '    if declare -f log_error >/dev/null 2>&1; then',
    '        log_error "$@"',
    '    else',
    '        echo "[ERROR] $*" >&2',
    '    fi',
    '}',
    '',
    'acfs_child_primary_bin_dir() {',
    '    local primary_bin_dir="${ACFS_BIN_DIR:-}"',
    '    local fallback_home="${HOME:-}"',
    '',
    '    if [[ -z "$primary_bin_dir" ]]; then',
    '        if [[ -z "$fallback_home" ]] || [[ "$fallback_home" == "/" ]] || [[ "$fallback_home" != /* ]]; then',
    '            acfs_child_log_error "ACFS_BIN_DIR is unset and HOME is not a usable absolute path"',
    '            return 1',
    '        fi',
    '        primary_bin_dir="$fallback_home/.local/bin"',
    '    fi',
    '',
    '    if [[ -z "$primary_bin_dir" ]] || [[ "$primary_bin_dir" == "/" ]] || [[ "$primary_bin_dir" != /* ]]; then',
    '        acfs_child_log_error "ACFS_BIN_DIR must be an absolute path and cannot be \'/\' (got: ${primary_bin_dir:-<empty>})"',
    '        return 1',
    '    fi',
    '',
    '    printf \'%s\\n\' "$primary_bin_dir"',
    '}',
    '',
    'acfs_child_primary_bin_requires_root() {',
    '    local primary_bin_dir="$1"',
    '    local target_home="${TARGET_HOME:-${HOME:-}}"',
    '',
    '    [[ -n "$target_home" && "$target_home" == /* && "$target_home" != "/" ]] || return 0',
    '    case "$primary_bin_dir" in',
    '        "$target_home"|"$target_home"/*) return 1 ;;',
    '        *) return 0 ;;',
    '    esac',
    '}',
    '',
    'acfs_child_run_root_bin_command() {',
    '    if [[ -z "${1:-}" || "${1:-}" != /* ]]; then',
    '        acfs_child_log_error "Root primary bin command must be an absolute trusted path (got: ${1:-<empty>})"',
    '        return 1',
    '    fi',
    '',
    '    if [[ $EUID -eq 0 ]]; then',
    '        "$@"',
    '        return $?',
    '    fi',
    '',
    '    local sudo_bin=""',
    '    sudo_bin="$(acfs_generated_system_binary_path sudo 2>/dev/null || true)"',
    '    if [[ -n "$sudo_bin" ]]; then',
    '        "$sudo_bin" -n "$@"',
    '        return $?',
    '    fi',
    '',
    '    acfs_child_log_error "Primary bin dir requires root, but sudo is unavailable: ${ACFS_BIN_DIR:-<unset>}"',
    '    return 1',
    '}',
    '',
    'acfs_child_primary_bin_tool_path() {',
    '    local name="${1:-}"',
    '    local tool_path=""',
    '',
    '    tool_path="$(acfs_generated_system_binary_path "$name" 2>/dev/null || true)"',
    '    if [[ -z "$tool_path" ]]; then',
    '        acfs_child_log_error "Unable to locate trusted $name for primary bin operation"',
    '        return 1',
    '    fi',
    '',
    '    printf \'%s\\n\' "$tool_path"',
    '}',
    '',
    'acfs_child_ensure_primary_bin_dir() {',
    '    local primary_bin_dir="$1"',
    '    local mkdir_bin=""',
    '',
    '    mkdir_bin="$(acfs_child_primary_bin_tool_path mkdir)" || return 1',
    '',
    '    if acfs_child_primary_bin_requires_root "$primary_bin_dir"; then',
    '        acfs_child_run_root_bin_command "$mkdir_bin" -p "$primary_bin_dir"',
    '        return $?',
    '    fi',
    '',
    '    "$mkdir_bin" -p "$primary_bin_dir"',
    '}',
    '',
    'acfs_link_primary_bin_command() {',
    '    local source_path="$1"',
    '    local command_name="$2"',
    '    local primary_bin_dir=""',
    '    local dest_path=""',
    '    local ln_bin=""',
    '',
    '    primary_bin_dir="$(acfs_child_primary_bin_dir)" || return 1',
    '    dest_path="$primary_bin_dir/$command_name"',
    '    acfs_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1',
    '    ln_bin="$(acfs_child_primary_bin_tool_path ln)" || return 1',
    '',
    '    if acfs_child_primary_bin_requires_root "$primary_bin_dir"; then',
    '        acfs_child_run_root_bin_command "$ln_bin" -sf "$source_path" "$dest_path"',
    '        return $?',
    '    fi',
    '',
    '    "$ln_bin" -sf "$source_path" "$dest_path"',
    '}',
    '',
    'acfs_install_executable_into_primary_bin() {',
    '    local src_path="$1"',
    '    local command_name="$2"',
    '    local primary_bin_dir=""',
    '    local dest_path=""',
    '    local install_bin=""',
    '',
    '    primary_bin_dir="$(acfs_child_primary_bin_dir)" || return 1',
    '    dest_path="$primary_bin_dir/$command_name"',
    '    acfs_child_ensure_primary_bin_dir "$primary_bin_dir" || return 1',
    '    install_bin="$(acfs_child_primary_bin_tool_path install)" || return 1',
    '',
    '    if acfs_child_primary_bin_requires_root "$primary_bin_dir"; then',
    '        acfs_child_run_root_bin_command "$install_bin" -m 0755 "$src_path" "$dest_path"',
    '        return $?',
    '    fi',
    '',
    '    "$install_bin" -m 0755 "$src_path" "$dest_path"',
    '}',
  ];
}

function commandLinesWithChildHelperPreludes(commandLines: string[]): string[] {
  const preludeLines: string[] = [];
  const needsGeneratedHelpers = commandLinesNeedGeneratedHelpers(commandLines);
  const needsPrimaryBinHelpers = commandLinesNeedPrimaryBinHelpers(commandLines);

  if (needsGeneratedHelpers) {
    preludeLines.push(
      '# Generated helper functions used by this child shell.',
      ...generatedHelperPreludeLines(),
      ''
    );
  } else if (needsPrimaryBinHelpers) {
    preludeLines.push(
      '# Generated helper functions used by this child shell.',
      ...generatedSystemBinaryPreludeLines(),
      ''
    );
  }

  if (needsPrimaryBinHelpers) {
    preludeLines.push(
      '# Primary-bin helper functions used by this child shell.',
      ...primaryBinHelperPreludeLines(),
      ''
    );
  }

  if (preludeLines.length === 0) {
    return commandLines;
  }

  return [
    ...preludeLines,
    ...commandLines,
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
  for (const cmd of commandLinesWithChildHelperPreludes(commandLines)) {
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
  for (const cmd of commandLinesWithChildHelperPreludes(commandLines)) {
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
  for (const line of commandLinesWithChildHelperPreludes(blockLines)) {
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

function computeContentSha256(content: string | Buffer): string {
  return createHash('sha256').update(content).digest('hex');
}

function assertInputSnapshotUnchanged(path: string, snapshot: Buffer, label: string): void {
  const current = readRegularFileNoFollow(path, label);
  if (!current.equals(snapshot)) {
    throw new Error(`${label} changed during generation; refusing incoherent output`);
  }
}

function readProjectVersion(): { value: string; snapshot: Buffer } {
  const snapshot = readRegularFileNoFollow(VERSION_PATH, 'VERSION');
  const value = snapshot.toString('utf-8').trim();
  if (!value) {
    throw new Error('VERSION must contain a non-empty version');
  }
  return { value, snapshot };
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
  if (module.run_as !== 'target_user') {
    throw new Error(
      `SECURITY: verified installer for module "${module.id}" must use the clean target-user runner.`
    );
  }
  const tool = vi.tool;
  const tmpdirEnvValue = verifiedInstallerTmpdirEnvValue(module);
  const hasTmpdirEnv = Boolean(tmpdirEnvValue);

  // The runner consumes a fully verified
  // staging file, never a producer pipeline.
  const execCmd = buildVerifiedInstallerFileCommand(module);

  const lines: string[] = [
    '# Try security-verified install (no unverified fallback; fail closed)',
    'local install_success=false',
    'local verified_installer_file=""',
    'local verified_installer_chmod_bin=""',
    ...(hasTmpdirEnv ? ['local verified_installer_env_ready=true'] : []),
    '',
  ];

  if (tmpdirEnvValue) {
    lines.push(
      `local verified_installer_tmpdir_template=${shellQuoteVerifiedInstallerArg(tmpdirEnvValue)}`,
      'local verified_installer_tmpdir_parent="${verified_installer_tmpdir_template%/*}"',
      'local verified_installer_tmpdir_prefix="${verified_installer_tmpdir_template%XXXXXX}"',
      'local verified_installer_tmpdir=""',
      'local verified_installer_tmpdir_suffix=""',
      'local verified_installer_mkdir_bin=""',
      'local verified_installer_mktemp_bin=""',
      'if [[ "$verified_installer_tmpdir_template" != *XXXXXX* ]]; then',
      `    log_error "${escapeBash(module.id)}: installer TMPDIR template must contain XXXXXX: $verified_installer_tmpdir_template"`,
      '    verified_installer_env_ready=false',
      'elif ! verified_installer_mkdir_bin="$(acfs_generated_system_binary_path mkdir 2>/dev/null)"; then',
      `    log_error "${escapeBash(module.id)}: trusted mkdir not found for installer TMPDIR"`,
      '    verified_installer_env_ready=false',
      'elif ! verified_installer_mktemp_bin="$(acfs_generated_system_binary_path mktemp 2>/dev/null)"; then',
      `    log_error "${escapeBash(module.id)}: trusted mktemp not found for installer TMPDIR"`,
      '    verified_installer_env_ready=false',
      'elif [[ "$verified_installer_tmpdir_parent" != "$TARGET_HOME/.cache/acfs/installer-tmp" ]]; then',
      `    log_error "${escapeBash(module.id)}: installer TMPDIR parent escaped the approved target-home path"`,
      '    verified_installer_env_ready=false',
      'elif [[ -L "$TARGET_HOME" || -L "$TARGET_HOME/.cache" || -L "$TARGET_HOME/.cache/acfs" || -L "$verified_installer_tmpdir_parent" ]]; then',
      `    log_error "${escapeBash(module.id)}: refusing installer TMPDIR through a symlinked target-home path"`,
      '    verified_installer_env_ready=false',
      'elif ! run_as_target "$verified_installer_mkdir_bin" -p "$verified_installer_tmpdir_parent"; then',
      `    log_error "${escapeBash(module.id)}: failed to prepare installer TMPDIR parent: $verified_installer_tmpdir_parent"`,
      '    verified_installer_env_ready=false',
      'elif [[ ! -d "$verified_installer_tmpdir_parent" || -L "$TARGET_HOME" || -L "$TARGET_HOME/.cache" || -L "$TARGET_HOME/.cache/acfs" || -L "$verified_installer_tmpdir_parent" ]]; then',
      `    log_error "${escapeBash(module.id)}: installer TMPDIR parent is not a confined real directory"`,
      '    verified_installer_env_ready=false',
      'elif ! verified_installer_tmpdir="$(run_as_target "$verified_installer_mktemp_bin" -d "$verified_installer_tmpdir_template" 2>/dev/null)"; then',
      `    log_error "${escapeBash(module.id)}: failed to create installer TMPDIR from template: $verified_installer_tmpdir_template"`,
      '    verified_installer_env_ready=false',
      'elif [[ -z "$verified_installer_tmpdir" ]]; then',
      `    log_error "${escapeBash(module.id)}: installer TMPDIR creation returned an empty path"`,
      '    verified_installer_env_ready=false',
      'else',
      '    verified_installer_tmpdir_suffix="${verified_installer_tmpdir#"$verified_installer_tmpdir_prefix"}"',
      '    if [[ "$verified_installer_tmpdir" != "$verified_installer_tmpdir_prefix"* || -z "$verified_installer_tmpdir_suffix" || "$verified_installer_tmpdir_suffix" == *[!A-Za-z0-9]* || ! -d "$verified_installer_tmpdir" || -L "$verified_installer_tmpdir" || -L "$verified_installer_tmpdir_parent" ]]; then',
      `        log_error "${escapeBash(module.id)}: installer TMPDIR escaped its trusted template: $verified_installer_tmpdir"`,
      '        verified_installer_env_ready=false',
      '    fi',
      'fi',
      ''
    );
  }

  const securityInitCondition = hasTmpdirEnv
    ? 'if [[ "$verified_installer_env_ready" = "true" ]] && acfs_security_init; then'
    : 'if acfs_security_init; then';
  const securityInitFailureLines = hasTmpdirEnv
    ? [
        '    if [[ "$verified_installer_env_ready" != "true" ]]; then',
        `        log_error "${escapeBash(module.id)}: verified installer environment setup failed"`,
        '        ACFS_LAST_MODULE_FAILURE_REASON="environment setup"',
        '    else',
        `        log_error "${escapeBash(module.id)}: acfs_security_init failed - check security.sh and checksums.yaml"`,
        '        ACFS_LAST_MODULE_FAILURE_REASON="environment setup"',
        '    fi',
      ]
    : [
        `    log_error "${escapeBash(module.id)}: acfs_security_init failed - check security.sh and checksums.yaml"`,
        '    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"',
      ];

  const verifiedInstallAttemptLines: string[] = [
    '    # Cleared per attempt so a stale reason from an earlier module can',
    '    # never be misattributed to this one.',
    '    ACFS_LAST_MODULE_FAILURE_REASON=""',
    securityInitCondition,
    '    local known_installers_decl=""',
    '    # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)',
    '    known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"',
    '    if [[ "$known_installers_decl" == declare\\ -A* ]]; then',
    `        local tool="${tool}"`,
    '        local url=""',
    '        local expected_sha256=""',
    '',
    '        # Safe access with explicit empty default',
    '        url="${KNOWN_INSTALLERS[$tool]:-}"',
    '        if ! expected_sha256="$(get_checksum "$tool")"; then',
    `            log_error "${escapeBash(module.id)}: get_checksum failed for tool '$tool'"`,
    '            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"',
    '            expected_sha256=""',
    '        fi',
    '',
    '        if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then',
    '            if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then',
    `                log_error "${escapeBash(module.id)}: failed to create verified installer staging file"`,
    '                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"',
    '                verified_installer_file=""',
    '            elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then',
    `                log_error "${escapeBash(module.id)}: installer verification failed"`,
    '                : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"',
    '            elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then',
    `                log_error "${escapeBash(module.id)}: trusted chmod not found for verified installer staging"`,
    '                ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"',
    '            elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then',
    `                log_error "${escapeBash(module.id)}: failed to make verified installer staging file read-only"`,
    '                ACFS_LAST_MODULE_FAILURE_REASON="environment setup"',
    `            elif ${execCmd}; then`,
    '                install_success=true',
    '            else',
    `                log_error "${escapeBash(module.id)}: verified installer execution failed"`,
    '                ACFS_LAST_MODULE_FAILURE_REASON="installer execution"',
    '            fi',
    '        else',
    '            if [[ -z "$url" ]]; then',
    `                log_error "${escapeBash(module.id)}: KNOWN_INSTALLERS[$tool] not found"`,
    '                ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"',
    '            fi',
    '            if [[ -z "$expected_sha256" ]]; then',
    `                log_error "${escapeBash(module.id)}: checksum for '$tool' not found"`,
    '                ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"',
    '            fi',
    '        fi',
    '    else',
    `        log_error "${escapeBash(module.id)}: KNOWN_INSTALLERS array not available"`,
    '        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"',
    '    fi',
    'else',
    ...securityInitFailureLines,
    'fi',
    'if [[ -n "$verified_installer_file" ]]; then',
    '    _acfs_remove_temp_files "$verified_installer_file"',
    '    verified_installer_file=""',
    'fi',
  ];

  const normalizedScriptArgs = normalizeVerifiedInstallerScriptArgs(module.id, vi.args ?? []);
  const fsfsInstallerArgs = normalizedScriptArgs.length > 0
    ? normalizedScriptArgs.map(a => shellQuoteVerifiedInstallerArg(a)).join(' ')
    : '';
  const fsfsExecCmd = `run_as_target_runner ${shellQuote(vi.runner)} "$verified_installer_file" "\${fsfs_installer_args[@]}"`;
  const fsfsVerifiedInstallAttemptLines: string[] = [
    '# Cleared per attempt so a stale reason from an earlier module can',
    '# never be misattributed to this one.',
    'ACFS_LAST_MODULE_FAILURE_REASON=""',
    'if acfs_security_init; then',
    '    local known_installers_decl=""',
    '    # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)',
    '    known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"',
    '    if [[ "$known_installers_decl" == declare\\ -A* ]]; then',
    `        local tool="${tool}"`,
    '        local url=""',
    '        local expected_sha256=""',
    '',
    '        # Safe access with explicit empty default',
    '        url="${KNOWN_INSTALLERS[$tool]:-}"',
    '        if ! expected_sha256="$(get_checksum "$tool")"; then',
    `            log_error "${escapeBash(module.id)}: get_checksum failed for tool '$tool'"`,
    '            ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"',
    '            expected_sha256=""',
    '        fi',
    '',
    '        if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then',
    `            local -a fsfs_installer_args=(${fsfsInstallerArgs})`,
    '            local fsfs_arch=""',
    '            local fsfs_target=""',
    '            local fsfs_version=""',
    '            local fsfs_version_bare=""',
    '            local fsfs_artifact_url=""',
    '            local fsfs_checksum=""',
    '            local fsfs_candidate=""',
    '            local -a fsfs_candidates=()',
    '            local fsfs_can_run=true',
    '',
    '            if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then',
    '                fsfs_arch="$(uname -m 2>/dev/null || true)"',
    '                case "$fsfs_arch" in',
    '                    x86_64|amd64) fsfs_target="x86_64-unknown-linux-musl" ;;',
    '                    aarch64|arm64) fsfs_target="aarch64-unknown-linux-musl" ;;',
    '                    *) fsfs_target="" ;;',
    '                esac',
    '',
    '                if [[ -z "$fsfs_target" ]]; then',
    '                    fsfs_can_run=false',
    `                    log_warn "${escapeBash(module.id)}: FrankenSearch Linux binary artifact unavailable for this architecture; skipping source-build fallback"`,
    '                else',
    '                    if [[ -n "${ACFS_FSFS_VERSION:-}" ]]; then',
    '                        fsfs_candidates+=("$ACFS_FSFS_VERSION")',
    '                    else',
    '                        while IFS= read -r fsfs_candidate; do',
    '                            [[ -n "$fsfs_candidate" ]] || continue',
    '                            case " ${fsfs_candidates[*]} " in',
    '                                *" $fsfs_candidate "*) ;;',
    '                                *) fsfs_candidates+=("$fsfs_candidate") ;;',
    '                            esac',
    '                        done < <(acfs_curl --connect-timeout 30 --max-time 60 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/Dicklesworthstone/frankensearch/releases?per_page=10" 2>/dev/null | sed -n \'s/.*"tag_name"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p\' || true)',
    '',
    '                        fsfs_candidate="$(acfs_curl --connect-timeout 30 --max-time 60 -o /dev/null -w \'%{url_effective}\' "https://github.com/Dicklesworthstone/frankensearch/releases/latest" 2>/dev/null | sed -E \'s|.*/tag/||\' || true)"',
    '                        if [[ "$fsfs_candidate" =~ ^v[0-9][A-Za-z0-9._-]*$ ]]; then',
    '                            case " ${fsfs_candidates[*]} " in',
    '                                *" $fsfs_candidate "*) ;;',
    '                                *) fsfs_candidates+=("$fsfs_candidate") ;;',
    '                            esac',
    '                        fi',
    '                    fi',
    '',
    '                    if [[ ${#fsfs_candidates[@]} -eq 0 ]]; then',
    '                        fsfs_can_run=false',
    `                        log_warn "${escapeBash(module.id)}: unable to resolve FrankenSearch release; skipping source-build fallback"`,
    '                    else',
    '                        for fsfs_version in "${fsfs_candidates[@]}"; do',
    '                            [[ "$fsfs_version" =~ ^v[0-9][A-Za-z0-9._-]*$ ]] || continue',
    '                            fsfs_version_bare="${fsfs_version#v}"',
    '                            fsfs_artifact_url="https://github.com/Dicklesworthstone/frankensearch/releases/download/${fsfs_version}/fsfs-lite-${fsfs_version_bare}-${fsfs_target}.tar.xz"',
    '                            fsfs_checksum="$(acfs_curl --connect-timeout 30 --max-time 60 "${fsfs_artifact_url}.sha256" 2>/dev/null | awk \'NR == 1 { print $1 }\' || true)"',
    '                            if [[ "$fsfs_checksum" =~ ^[0-9A-Fa-f]{64}$ ]]; then',
    '                                fsfs_installer_args+=(',
    '                                    --version "$fsfs_version"',
    '                                    --artifact-url "$fsfs_artifact_url"',
    '                                    --checksum "${fsfs_checksum,,}"',
    '                                )',
    `                                log_info "${escapeBash(module.id)}: using FrankenSearch Linux lite artifact $fsfs_artifact_url"`,
    '                                break',
    '                            fi',
    `                            log_warn "${escapeBash(module.id)}: FrankenSearch lite artifact checksum unavailable for $fsfs_version"`,
    '                        done',
    '                        if [[ ! "$fsfs_checksum" =~ ^[0-9A-Fa-f]{64}$ ]]; then',
    '                            fsfs_can_run=false',
    `                            log_warn "${escapeBash(module.id)}: unable to resolve a FrankenSearch lite artifact with a checksum; skipping source-build fallback"`,
    '                        fi',
    '                    fi',
    '                fi',
    '            fi',
    '',
    '            if [[ "$fsfs_can_run" == "true" ]]; then',
    '                if ! verified_installer_file="$(acfs_security_mktemp "/tmp/acfs-verified-installer.XXXXXX" 2>/dev/null)" || [[ -z "$verified_installer_file" ]]; then',
    `                    log_error "${escapeBash(module.id)}: failed to create verified installer staging file"`,
    '                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"',
    '                    verified_installer_file=""',
    '                elif ! verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"; then',
    `                    log_error "${escapeBash(module.id)}: installer verification failed"`,
    '                    : "${ACFS_LAST_MODULE_FAILURE_REASON:=checksum}"',
    '                elif ! verified_installer_chmod_bin="$(acfs_generated_system_binary_path chmod 2>/dev/null)"; then',
    `                    log_error "${escapeBash(module.id)}: trusted chmod not found for verified installer staging"`,
    '                    ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"',
    '                elif ! "$verified_installer_chmod_bin" 0444 "$verified_installer_file"; then',
    `                    log_error "${escapeBash(module.id)}: failed to make verified installer staging file read-only"`,
    '                    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"',
    `                elif ${fsfsExecCmd}; then`,
    '                    install_success=true',
    '                else',
    `                    log_error "${escapeBash(module.id)}: verified installer execution failed"`,
    '                    ACFS_LAST_MODULE_FAILURE_REASON="installer execution"',
    '                fi',
    '            fi',
    '        else',
    '            if [[ -z "$url" ]]; then',
    `                log_error "${escapeBash(module.id)}: KNOWN_INSTALLERS[$tool] not found"`,
    '                ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"',
    '            fi',
    '            if [[ -z "$expected_sha256" ]]; then',
    `                log_error "${escapeBash(module.id)}: checksum for '$tool' not found"`,
    '                ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"',
    '            fi',
    '        fi',
    '    else',
    `        log_error "${escapeBash(module.id)}: KNOWN_INSTALLERS array not available"`,
    '        ACFS_LAST_MODULE_FAILURE_REASON="missing dependency"',
    '    fi',
    'else',
    `    log_error "${escapeBash(module.id)}: acfs_security_init failed - check security.sh and checksums.yaml"`,
    '    ACFS_LAST_MODULE_FAILURE_REASON="environment setup"',
    'fi',
    'if [[ -n "$verified_installer_file" ]]; then',
    '    _acfs_remove_temp_files "$verified_installer_file"',
    '    verified_installer_file=""',
    'fi',
  ];

  if (tool === 'ms') {
    lines.push(
      '# meta_skill has no checksum-anchored Linux ARM64 install source yet.',
      'if [[ "$(uname -s 2>/dev/null)" == "Linux" ]] && { [[ "$(uname -m 2>/dev/null)" == "aarch64" ]] || [[ "$(uname -m 2>/dev/null)" == "arm64" ]]; }; then',
      `    log_error "${escapeBash(module.id)}: Linux ARM64 is unsupported until a checksum-anchored artifact or source revision is available"`,
      '    ACFS_LAST_MODULE_FAILURE_REASON="unsupported architecture"',
      'else',
      ...indentLines(verifiedInstallAttemptLines, 4),
      'fi',
    );
  } else if (tool === 'fsfs') {
    lines.push(...fsfsVerifiedInstallAttemptLines);
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

type ShellQuoteState = {
  double: boolean;
  single: boolean;
};

function updateShellQuoteState(line: string, initialState: ShellQuoteState): ShellQuoteState {
  let double = initialState.double;
  let single = initialState.single;

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];

    if (!single && !double && char === '#' && (index === 0 || /\s/.test(line[index - 1]))) {
      break;
    }

    if (single) {
      if (char === "'") single = false;
      continue;
    }

    if (double) {
      if (char === '"' && line[index - 1] !== '\\') double = false;
      continue;
    }

    if (char === "'") {
      single = true;
    } else if (char === '"') {
      double = true;
    }
  }

  return { double, single };
}

function summarizeShellBlock(blockLines: string[], fallback: string): string {
  for (const line of blockLines) {
    const match = line.trim().match(/^#\s*acfs-summary:\s*(.+)$/);
    const summary = match?.[1]?.trim();
    if (summary) return summary;
  }

  const topLevel: string[] = [];
  let skippingFunction = false;
  let skippingFunctionQuoteState: ShellQuoteState = { double: false, single: false };

  for (const line of blockLines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    if (skippingFunction) {
      skippingFunctionQuoteState = updateShellQuoteState(line, skippingFunctionQuoteState);
      if (!skippingFunctionQuoteState.double && !skippingFunctionQuoteState.single && trimmed === '}') {
        skippingFunction = false;
      }
      continue;
    }

    if (/^(?:function\s+)?[A-Za-z_][A-Za-z0-9_]*(?:\s*\(\))?\s*\{$/.test(trimmed)) {
      skippingFunction = true;
      skippingFunctionQuoteState = { double: false, single: false };
      continue;
    }

    topLevel.push(trimmed);
  }

  if (topLevel.length === 0) return fallback;

  const commandLike = topLevel.find(
    (line) => !/^(?:local\s+)?[A-Za-z_][A-Za-z0-9_]*=(?!=)/.test(line)
  );

  return commandLike ?? topLevel[0] ?? fallback;
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
  // The verified bytes are staged completely before the runner opens the file.
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
    const isOptional = isOptionalVerifyCommand(cmd);
    const cleanCmd = stripOptionalVerifySuffix(cmd);

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
export function generateManifestIndex(manifest: Manifest, manifestSha256: string): string {
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

  lines.push('ACFS_CATEGORIES_IN_ORDER=(');
  for (const category of MODULE_CATEGORIES) {
    lines.push(`  "${category}"`);
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
    if (module.generated !== false) {
      lines.push(`  ['${module.id}']="${toGeneratedFunctionName(module.id)}"`);
    }
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_GENERATED=(');
  for (const module of orderedModules) {
    lines.push(`  ['${module.id}']="${module.generated === false ? '0' : '1'}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_CATEGORY=(');
  for (const module of orderedModules) {
    const category = resolveModuleCategory(module);
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

  // Plugin provenance metadata (bd-vv8x5)
  lines.push('declare -gA ACFS_MODULE_PLUGIN_PACKAGE=(');
  for (const module of orderedModules) {
    if (module.plugin) {
      lines.push(`  ['${module.id}']="${escapeBash(module.plugin.packageId)}"`);
    }
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_PLUGIN_VERSION=(');
  for (const module of orderedModules) {
    if (module.plugin) {
      lines.push(`  ['${module.id}']="${escapeBash(module.plugin.version)}"`);
    }
  }
  lines.push(')');
  lines.push('');

  lines.push('declare -gA ACFS_MODULE_PLUGIN_SHA256=(');
  for (const module of orderedModules) {
    if (module.plugin) {
      lines.push(`  ['${module.id}']="${escapeBash(module.plugin.pluginSha256)}"`);
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
export function generateInternalChecksums(
  generatedFiles: ReadonlyMap<string, { content: string; mode: number }>,
  boundStaticSnapshots: ReadonlyMap<string, Buffer>,
): { content: string; staticSnapshots: ReadonlyMap<string, Buffer> } {
  const lines: string[] = [INTERNAL_CHECKSUMS_HEADER];
  const staticSnapshots = new Map<string, Buffer>();

  lines.push('ACFS_INTERNAL_CHECKSUMS_SCHEMA=1');
  lines.push('');
  lines.push('declare -gA ACFS_INTERNAL_CHECKSUMS=(');
  for (const relPath of INTERNAL_SCRIPTS_TO_CHECKSUM) {
    const absPath = join(PROJECT_ROOT, relPath);
    const pendingGeneratedFile = generatedFiles.get(absPath);
    let content: Buffer;
    if (pendingGeneratedFile) {
      content = Buffer.from(pendingGeneratedFile.content, 'utf-8');
    } else {
      if (relPath.startsWith('scripts/generated/')) {
        throw new Error(`Generated checksum input was not produced in this run: ${relPath}`);
      }
      content = boundStaticSnapshots.get(absPath)
        ?? readRegularFileNoFollow(absPath, `Internal checksum input ${relPath}`);
      staticSnapshots.set(absPath, content);
    }
    const hash = createHash('sha256').update(content).digest('hex');
    lines.push(`  [${relPath}]="${hash}"`);
  }
  lines.push(')');
  lines.push('');

  lines.push(`ACFS_INTERNAL_CHECKSUMS_COUNT=${INTERNAL_SCRIPTS_TO_CHECKSUM.length}`);
  lines.push('');

  return { content: lines.join('\n'), staticSnapshots };
}

/**
 * Generate a category install script
 */
export function generateCategoryScript(manifest: Manifest, category: ModuleCategory): string {
  // Sort the complete dependency graph before filtering. Category-local
  // sorting silently discards cross-category edges such as agents -> lang.
  const sortedModules = sortModulesByPhaseAndDependency(manifest).filter(
    (module) => resolveModuleCategory(module) === category
  );
  const generatedModules = sortedModules.filter((module) => module.generated !== false);
  const orchestrationModules = sortedModules.filter((module) => module.generated === false);

  const lines: string[] = [
    sourceOnlyHeader(
      `ERROR: install_${category}.sh is a source-only library; run install.sh --only <module-id>`
    ),
  ];
  lines.push(`# Category: ${category}`);
  lines.push(`# Generated modules: ${generatedModules.length}`);
  lines.push('');

  // Generate individual install functions
  for (const module of generatedModules) {
    const funcName = toGeneratedFunctionName(module.id);
    const pluginComment = module.plugin ? ` [plugin: ${module.plugin.packageId}@${module.plugin.version}]` : '';
    lines.push(`# ${sanitizeForBashComment(module.description)}${pluginComment}`);
    lines.push(`${funcName}() {`);
    lines.push(`    local module_id="${module.id}"`);
    lines.push('    acfs_require_contract "module:${module_id}" || return 1');
    lines.push('    acfs_generated_ensure_selection || return 1');
    lines.push('    if ! should_run_module "${module_id}"; then');
    lines.push(`        log_info "Skipping ${module.id} (not selected)"`);
    lines.push('        return 0');
    lines.push('    fi');
    lines.push(`    log_step "Installing ${module.id}"`);
    lines.push('');

    // Install commands
    lines.push(...generateInstallCommands(module));
    lines.push('');

    // Verify commands
    lines.push('    # Verify');
    lines.push(...generateVerifyCommands(module));
    if (module.post_install_message) {
      lines.push('');
      lines.push(...generatePostInstallMessage(module));
    }
    lines.push('');
    lines.push(`    log_success "${module.id} installed"`);
    lines.push('}');
    lines.push('');
  }

  if (orchestrationModules.length > 0) {
    lines.push(
      `# Orchestrator-owned modules omitted from this library: ${orchestrationModules.map((module) => module.id).join(', ')}`
    );
    lines.push('');
  }

  lines.push('# Category scripts are source-only libraries.');
  lines.push('');

  return lines.join('\n');
}

/**
 * Generate doctor checks script
 */
export function generateDoctorChecks(manifest: Manifest): string {
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
      const isOptional = module.optional || isOptionalVerifyCommand(verify);
      const cleanCmd = stripOptionalVerifySuffix(verify);
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
  lines.push('    local explicit_target_home=""');
  lines.push('    local resolved_target_home=""');
  lines.push('    local target_path=""');
  lines.push('    local current_user=""');
  lines.push('    local current_home=""');
  lines.push('    local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"');
  lines.push('');
  lines.push('    explicit_target_home="$target_home"');
  lines.push('    if [[ -n "$explicit_target_home" ]]; then');
  lines.push('        explicit_target_home="${explicit_target_home%/}"');
  lines.push('    fi');
  lines.push('');
  lines.push('    if declare -f _acfs_validate_target_user >/dev/null 2>&1; then');
  lines.push('        _acfs_validate_target_user "$target_user" "TARGET_USER" || return 1');
  lines.push('    elif [[ -z "$target_user" ]] || [[ ! "$target_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then');
  lines.push('        log_error "Invalid TARGET_USER \'${target_user:-<empty>}\' (expected: lowercase user name like \'ubuntu\')"');
  lines.push('        return 1');
  lines.push('    fi');
  lines.push('');
  lines.push('    if declare -f _acfs_resolve_target_home >/dev/null 2>&1; then');
  lines.push('        resolved_target_home="$(_acfs_resolve_target_home "$target_user" "$explicit_target_home" || true)"');
  lines.push('    elif [[ "$target_user" == "root" ]]; then');
  lines.push('        resolved_target_home="/root"');
  lines.push('    else');
  lines.push('        local _acfs_passwd_entry=""');
  lines.push('        _acfs_passwd_entry="$(acfs_generated_getent_passwd_entry "$target_user" 2>/dev/null || true)"');
  lines.push('        if [[ -n "$_acfs_passwd_entry" ]]; then');
  lines.push('            resolved_target_home="$(acfs_generated_passwd_home_from_entry "$_acfs_passwd_entry" 2>/dev/null || true)"');
  lines.push('        else');
  lines.push('            _acfs_current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"');
  lines.push('            current_home="${HOME:-}"');
  lines.push('            if [[ -n "$current_home" ]]; then');
  lines.push('                current_home="${current_home%/}"');
  lines.push('            fi');
  lines.push('            if [[ "${_acfs_current_user:-}" == "$target_user" ]] && [[ -n "$current_home" ]] && [[ "$current_home" == /* ]] && [[ "$current_home" != "/" ]] && { [[ -z "$explicit_target_home" ]] || [[ "$current_home" == "$explicit_target_home" ]]; }; then');
  lines.push('                resolved_target_home="$current_home"');
  lines.push('            fi');
  lines.push('            unset _acfs_current_user');
  lines.push('        fi');
  lines.push('        unset _acfs_passwd_entry');
  lines.push('    fi');
  lines.push('    if [[ -n "$resolved_target_home" ]]; then');
  lines.push('        target_home="${resolved_target_home%/}"');
  lines.push('    fi');
  lines.push('');
  lines.push('    if [[ "$cmd" == *"acfs_generated_"* ]]; then');
  lines.push('        local helper_prelude=""');
  lines.push('        helper_prelude="$(declare -f acfs_generated_system_binary_path acfs_generated_resolve_current_user acfs_generated_getent_passwd_entry acfs_generated_passwd_home_from_entry 2>/dev/null || true)"');
  lines.push('        if [[ -z "$helper_prelude" ]]; then');
  lines.push('            log_error "Generated helper functions are unavailable for manifest check command"');
  lines.push('            return 1');
  lines.push('        fi');
  lines.push("        cmd=\"${helper_prelude}\"$'\\n'\"${cmd}\"");
  lines.push('    fi');
  lines.push('');
  lines.push('    local env_bin=""');
  lines.push('    local bash_bin=""');
  lines.push('    env_bin="$(acfs_generated_system_binary_path env 2>/dev/null || true)"');
  lines.push('    bash_bin="$(acfs_generated_system_binary_path bash 2>/dev/null || true)"');
  lines.push('    if [[ -z "$env_bin" || -z "$bash_bin" ]]; then');
  lines.push('        return 1');
  lines.push('    fi');
  lines.push('');
  lines.push('    case "$run_as" in');
  lines.push('        target_user)');
  lines.push('            if [[ -z "$target_home" ]] || [[ "$target_home" != /* ]] || [[ "$target_home" == "/" ]]; then');
  lines.push('                log_error "Invalid TARGET_HOME for \'$target_user\': ${target_home:-<empty>} (must be an absolute path and cannot be \'/\')"');
  lines.push('                return 1');
  lines.push('            fi');
  lines.push('            local target_bin="${ACFS_BIN_DIR:-$target_home/.local/bin}"');
  lines.push('            if [[ -z "$target_bin" ]] || [[ "$target_bin" != /* ]] || [[ "$target_bin" == "/" ]]; then');
  lines.push('                log_error "ACFS_BIN_DIR must be an absolute path and cannot be \'/\' (got: ${target_bin:-<empty>})"');
  lines.push('                return 1');
  lines.push('            fi');
  lines.push('            local dir=""');
  lines.push('            local seen_path=":"');
  lines.push('            local target_path_prefix=""');
  lines.push('            local -a target_path_entries=()');
  lines.push('            for dir in \\');
  lines.push('                "$target_bin" \\');
  lines.push('                "$target_home/.local/bin" \\');
  lines.push('                "$target_home/.acfs/bin" \\');
  lines.push('                "$target_home/.bun/bin" \\');
  lines.push('                "$target_home/.cargo/bin" \\');
  lines.push('                "$target_home/.atuin/bin" \\');
  lines.push('                "$target_home/go/bin" \\');
  lines.push('                "$target_home/google-cloud-sdk/bin" \\');
  lines.push('                "/usr/local/sbin" \\');
  lines.push('                "/usr/local/bin" \\');
  lines.push('                "/usr/sbin" \\');
  lines.push('                "/usr/bin" \\');
  lines.push('                "/sbin" \\');
  lines.push('                "/bin" \\');
  lines.push('                "/snap/bin"; do');
  lines.push('                case "$seen_path" in');
  lines.push('                    *":$dir:"*) ;;');
  lines.push('                    *)');
  lines.push('                        target_path_entries+=("$dir")');
  lines.push('                        seen_path="${seen_path}${dir}:"');
  lines.push('                        ;;');
  lines.push('                esac');
  lines.push('            done');
  lines.push('            target_path_prefix=$(IFS=:; echo "${target_path_entries[*]}")');
  lines.push('            target_path="$target_path_prefix${PATH:+:$PATH}"');
  lines.push('            current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"');
  lines.push('            if [[ "${current_user:-}" == "$target_user" ]]; then');
  lines.push('                "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"');
  lines.push('                return $?');
  lines.push('            fi');
  lines.push('            local runuser_bin=""');
  lines.push('            runuser_bin="$(acfs_generated_system_binary_path runuser 2>/dev/null || true)"');
  lines.push('            if [[ $EUID -eq 0 && -n "$runuser_bin" ]]; then');
  lines.push('                "$runuser_bin" -u "$target_user" -- "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"');
  lines.push('                return $?');
  lines.push('            fi');
  lines.push('            local sudo_bin=""');
  lines.push('            sudo_bin="$(acfs_generated_system_binary_path sudo 2>/dev/null || true)"');
  lines.push('            if [[ -n "$sudo_bin" ]]; then');
  lines.push('                "$sudo_bin" -n -u "$target_user" "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"');
  lines.push('                return $?');
  lines.push('            fi');
  lines.push('            return 1');
  lines.push('            ;;');
  lines.push('        root)');
  lines.push('            if [[ $EUID -eq 0 ]]; then');
  lines.push('                if [[ -n "$target_home" ]] && [[ "$target_home" == /* ]] && [[ "$target_home" != "/" ]]; then');
  lines.push('                    "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"');
  lines.push('                else');
  lines.push('                    "$env_bin" TARGET_USER="$target_user" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"');
  lines.push('                fi');
  lines.push('                return $?');
  lines.push('            fi');
  lines.push('            local sudo_bin=""');
  lines.push('            sudo_bin="$(acfs_generated_system_binary_path sudo 2>/dev/null || true)"');
  lines.push('            if [[ -n "$sudo_bin" ]]; then');
  lines.push('                if [[ -n "$target_home" ]] && [[ "$target_home" == /* ]] && [[ "$target_home" != "/" ]]; then');
  lines.push('                    "$sudo_bin" -n "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"');
  lines.push('                else');
  lines.push('                    "$sudo_bin" -n "$env_bin" TARGET_USER="$target_user" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"');
  lines.push('                fi');
  lines.push('                return $?');
  lines.push('            fi');
  lines.push('            return 1');
  lines.push('            ;;');
  lines.push('        current|*)');
  lines.push('            if [[ -n "$target_home" ]] && [[ "$target_home" == /* ]] && [[ "$target_home" != "/" ]]; then');
  lines.push('                "$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" "$bash_bin" -o pipefail -c "$cmd"');
  lines.push('            else');
  lines.push('                "$env_bin" TARGET_USER="$target_user" "$bash_bin" -o pipefail -c "$cmd"');
  lines.push('            fi');
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
  lines.push('if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then');
  lines.push('    run_manifest_checks');
  lines.push('fi');
  lines.push('');

  return lines.join('\n');
}

/**
 * Generate top-level installer script
 */
export function generateTopLevelInstaller(manifest: Manifest): string {
  // Emit the complete canonical category surface, including zero-handler
  // orchestration-owned categories such as users.
  const categories: ModuleCategory[] = [...MODULE_CATEGORIES];
  const lines: string[] = [
    sourceOnlyHeader(
      'ERROR: install_all.sh is a source-only generated harness; run install.sh'
    ),
  ];
  lines.push('# Top-level installer - sources all category scripts');
  lines.push('');

  // Source all category scripts
  for (const category of categories) {
    lines.push(`source "\$ACFS_GENERATED_SCRIPT_DIR/install_${category}.sh"`);
  }
  lines.push('');

  // Main install function
  lines.push('# Install all modules in global dependency order');
  lines.push('acfs_generated_install_all() {');
  lines.push('    log_section "ACFS Full Installation"');
  lines.push('');

  // Use global sort to ensure dependencies are met across categories
  const allOrderedModules = sortModulesByPhaseAndDependency(manifest);
  const orderedModules = allOrderedModules.filter((module) => module.generated !== false);
  const orchestrationModules = allOrderedModules.filter((module) => module.generated === false);
  let currentCategory: string | null = null;

  if (orchestrationModules.length > 0) {
    lines.push(
      `    log_info "Orchestrator-owned modules are not run by acfs_generated_install_all: ${orchestrationModules.map((module) => module.id).join(', ')}"`
    );
    lines.push('');
  }

  for (const module of orderedModules) {
    const category = resolveModuleCategory(module);
    if (category !== currentCategory) {
      lines.push(`    log_section "Category: ${category}"`);
      currentCategory = category;
    }

    const funcName = toGeneratedFunctionName(module.id);
    lines.push(`    ${funcName}`);
  }

  lines.push('');
  lines.push('    log_success "All generated modules installed!"');
  lines.push('}');
  lines.push('');

  // acfs_generated_install_all omits orchestration-owned modules and does not reproduce the
  // production dispatcher's installed-check/failure semantics. Its prologue
  // rejects direct execution before any adjacent helper can be sourced.
  lines.push('# Source-only generated harness.');
  lines.push('');

  return lines.join('\n');
}

// ============================================================
// Web Data Generators
// ============================================================

const TS_HEADER = `// ============================================================
// AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT DIRECTLY
// To regenerate: bun run --cwd packages/manifest generate
// ============================================================
`;

const WEB_SELECTION_PROFILES = [
  {
    id: 'full',
    label: 'Full',
    onlyModules: [],
    onlyPhases: [],
  },
  {
    id: 'safe',
    label: 'Safe',
    mode: 'safe',
    onlyModules: [],
    onlyPhases: [],
  },
  {
    id: 'vibe',
    label: 'Vibe',
    mode: 'vibe',
    onlyModules: [],
    onlyPhases: [],
  },
  {
    id: 'minimal',
    label: 'Minimal',
    onlyModules: [
      'shell.omz',
      'cli.modern',
      'lang.bun',
      'lang.uv',
      'agents.claude',
      'agents.codex',
      'agents.antigravity',
      'stack.ntm',
      'stack.mcp_agent_mail',
      'stack.ultimate_bug_scanner',
      'stack.beads_rust',
      'stack.beads_viewer',
      'stack.cass',
      'stack.cm',
      'stack.dcg',
      'stack.ru',
      'stack.rch',
      'acfs.workspace',
      'acfs.onboard',
      'acfs.update',
      'acfs.doctor',
    ],
    onlyPhases: [],
  },
  {
    id: 'agents-only',
    label: 'Agents only',
    onlyModules: [],
    onlyPhases: ['agents'],
  },
  {
    id: 'cloud-only',
    label: 'Cloud only',
    onlyModules: ['cloud.wrangler', 'cloud.supabase', 'cloud.vercel'],
    onlyPhases: [],
  },
  {
    id: 'stack-only',
    label: 'Stack only',
    onlyModules: [],
    onlyPhases: ['stack'],
  },
] as const;

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
 * Generate manifest-modules.ts — full module metadata for web-side planning.
 */
export function generateWebModules(
  manifest: Manifest,
  acfsVersion: string,
  manifestSha256: string,
  checksumsYamlSha256: string,
): string {
  const modules = sortModulesByPhaseAndDependency(manifest);
  const lines: string[] = [TS_HEADER];

  lines.push('export interface ManifestPluginProvenance {');
  lines.push('  packageId: string;');
  lines.push('  version: string;');
  lines.push('  pluginSha256: string;');
  lines.push('  sourceRef: string;');
  lines.push('  sourceCommit: string;');
  lines.push('}');
  lines.push('');

  lines.push('export interface ManifestModuleMetadata {');
  lines.push('  id: string;');
  lines.push('  description: string;');
  lines.push('  category: string;');
  lines.push('  phase: number;');
  lines.push('  dependencies: string[];');
  lines.push('  tags: string[];');
  lines.push('  enabledByDefault: boolean;');
  lines.push('  optional: boolean;');
  lines.push('  plugin?: ManifestPluginProvenance;');
  lines.push('}');
  lines.push('');

  const profileIds = WEB_SELECTION_PROFILES.map((profile) => `"${profile.id}"`).join(' | ');
  lines.push(`export type ManifestSelectionProfileId = ${profileIds};`);
  lines.push('');
  lines.push('export interface ManifestSelectionProfile {');
  lines.push('  id: ManifestSelectionProfileId;');
  lines.push('  label: string;');
  lines.push('  mode?: "safe" | "vibe";');
  lines.push('  onlyModules: string[];');
  lines.push('  onlyPhases: string[];');
  lines.push('}');
  lines.push('');

  lines.push('export interface ManifestProvenanceMetadata {');
  lines.push('  acfsVersion: string;');
  lines.push('  manifestSha256: string;');
  lines.push('  checksumsYamlSha256: string;');
  lines.push('}');
  lines.push('');

  lines.push('export const manifestProvenance = {');
  lines.push(`  acfsVersion: "${escapeTs(acfsVersion)}",`);
  lines.push(`  manifestSha256: "${manifestSha256}",`);
  lines.push(`  checksumsYamlSha256: "${checksumsYamlSha256}",`);
  lines.push('} as const satisfies ManifestProvenanceMetadata;');
  lines.push('');

  lines.push('export const manifestModules: ManifestModuleMetadata[] = [');
  for (const module of modules) {
    lines.push('  {');
    lines.push(`    id: "${escapeTs(module.id)}",`);
    lines.push(`    description: "${escapeTs(module.description)}",`);
    lines.push(`    category: "${escapeTs(resolveModuleCategory(module))}",`);
    lines.push(`    phase: ${getModulePhase(module)},`);
    lines.push(`    dependencies: ${formatTsArray(module.dependencies ?? [], 4)},`);
    lines.push(`    tags: ${formatTsArray(module.tags ?? [], 4)},`);
    lines.push(`    enabledByDefault: ${module.enabled_by_default ? 'true' : 'false'},`);
    lines.push(`    optional: ${module.optional ? 'true' : 'false'},`);
    if (module.plugin) {
      lines.push('    plugin: {');
      lines.push(`      packageId: "${escapeTs(module.plugin.packageId)}",`);
      lines.push(`      version: "${escapeTs(module.plugin.version)}",`);
      lines.push(`      pluginSha256: "${escapeTs(module.plugin.pluginSha256)}",`);
      lines.push(`      sourceRef: "${escapeTs(module.plugin.sourceRef)}",`);
      lines.push(`      sourceCommit: "${escapeTs(module.plugin.sourceCommit)}",`);
      lines.push('    },');
    }
    lines.push('  },');
  }
  lines.push('];');
  lines.push('');

  lines.push('export const manifestSelectionProfiles: ManifestSelectionProfile[] = [');
  for (const profile of WEB_SELECTION_PROFILES) {
    lines.push('  {');
    lines.push(`    id: "${escapeTs(profile.id)}",`);
    lines.push(`    label: "${escapeTs(profile.label)}",`);
    if ('mode' in profile) {
      lines.push(`    mode: "${profile.mode}",`);
    }
    lines.push(`    onlyModules: ${formatTsArray([...profile.onlyModules], 4)},`);
    lines.push(`    onlyPhases: ${formatTsArray([...profile.onlyPhases], 4)},`);
    lines.push('  },');
  }
  lines.push('];');
  lines.push('');

  return lines.join('\n');
}

/**
 * Generate manifest-tools.ts — web tool data from manifest web metadata.
 * Pure data file, no React imports, tree-shakable.
 */
export function generateWebTools(manifest: Manifest): string {
  const modules = getWebVisibleModules(manifest);
  const lines: string[] = [TS_HEADER];

  lines.push("import type { ManifestPluginProvenance } from './manifest-modules';");
  lines.push('');

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
  lines.push('  plugin?: ManifestPluginProvenance;');
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
    if (module.plugin) {
      lines.push('    plugin: {');
      lines.push(`      packageId: "${escapeTs(module.plugin.packageId)}",`);
      lines.push(`      version: "${escapeTs(module.plugin.version)}",`);
      lines.push(`      pluginSha256: "${escapeTs(module.plugin.pluginSha256)}",`);
      lines.push(`      sourceRef: "${escapeTs(module.plugin.sourceRef)}",`);
      lines.push(`      sourceCommit: "${escapeTs(module.plugin.sourceCommit)}",`);
      lines.push('    },');
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
export function generateWebCommands(manifest: Manifest): string {
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
export function generateWebTldr(manifest: Manifest): string {
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
export function generateWebLessonsIndex(manifest: Manifest): string {
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
export function generateWebIndex(): string {
  const lines: string[] = [TS_HEADER];

  lines.push("export { manifestModules, manifestSelectionProfiles, manifestProvenance } from './manifest-modules';");
  lines.push("export type { ManifestModuleMetadata, ManifestSelectionProfile, ManifestSelectionProfileId, ManifestProvenanceMetadata, ManifestPluginProvenance } from './manifest-modules';");
  lines.push('');
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

const PLUGIN_PACKAGE_SUFFIXES = ['.json'] as const;

function pluginOptionValue(args: readonly string[], index: number, option: string): string {
  const value = args[index + 1];
  if (!value || value.startsWith('--')) {
    throw new Error(`${option} requires a value`);
  }
  return value;
}

function appendPluginDirectory(
  paths: string[],
  rawDirectory: string,
  option: string,
  cwd: string,
): void {
  if (!rawDirectory.trim()) {
    throw new Error(`${option} requires a plugin package directory`);
  }

  const directory = resolve(cwd, rawDirectory);
  let directoryStat: ReturnType<typeof lstatSync>;
  try {
    directoryStat = lstatSync(directory);
  } catch {
    throw new Error(`${option} is not a readable plugin package directory: ${directory}`);
  }
  if (directoryStat.isSymbolicLink() || !directoryStat.isDirectory()) {
    throw new Error(`${option} must name a real plugin package directory: ${directory}`);
  }

  const entries = readdirSync(directory)
    .filter((entry) => PLUGIN_PACKAGE_SUFFIXES.some((suffix) => entry.endsWith(suffix)))
    .sort();
  if (entries.length === 0) {
    throw new Error(`${option} contains no JSON plugin packages: ${directory}`);
  }
  paths.push(...entries.map((entry) => join(directory, entry)));
}

export function collectPluginInputPaths(
  args: readonly string[],
  environment: Readonly<Record<string, string | undefined>> = process.env,
  cwd = process.cwd(),
): string[] {
  const paths: string[] = [];

  for (let index = 0; index < args.length; index++) {
    const argument = args[index];
    if (argument === '--plugin' || argument === '--plugins') {
      paths.push(resolve(cwd, pluginOptionValue(args, index, argument)));
      index++;
    } else if (argument.startsWith('--plugin=') || argument.startsWith('--plugins=')) {
      const value = argument.slice(argument.indexOf('=') + 1);
      if (!value.trim()) {
        throw new Error(`${argument.slice(0, argument.indexOf('='))} requires a plugin package path`);
      }
      paths.push(resolve(cwd, value));
    } else if (argument === '--plugins-dir' || argument === '--plugin-dir') {
      appendPluginDirectory(
        paths,
        pluginOptionValue(args, index, argument),
        argument,
        cwd,
      );
      index++;
    } else if (
      argument.startsWith('--plugins-dir=') ||
      argument.startsWith('--plugin-dir=')
    ) {
      const option = argument.slice(0, argument.indexOf('='));
      appendPluginDirectory(
        paths,
        argument.slice(argument.indexOf('=') + 1),
        option,
        cwd,
      );
    }
  }

  const environmentPaths = environment.ACFS_PLUGIN_PATHS;
  if (environmentPaths !== undefined) {
    const configuredPaths = environmentPaths
      .split(/[:;,]/)
      .map((path) => path.trim())
      .filter(Boolean);
    if (configuredPaths.length === 0) {
      throw new Error('ACFS_PLUGIN_PATHS must name at least one plugin package');
    }
    paths.push(...configuredPaths.map((path) => resolve(cwd, path)));
  }

  const environmentDirectory = environment.ACFS_PLUGINS_DIR;
  if (environmentDirectory !== undefined) {
    appendPluginDirectory(paths, environmentDirectory, 'ACFS_PLUGINS_DIR', cwd);
  }

  return paths;
}

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
  --plugin       Path to a plugin package JSON file (can be repeated)
  --plugins-dir  Directory containing plugin package files
  --help         Show this help message

Examples:
  bun run generate                 # Generate all files
  bun run generate --dry-run       # Preview generation
  bun run generate --validate      # Check for issues (CI friendly)
  bun run generate --diff          # Show what would change
  bun run generate --plugin ./pkg.json # Include plugin in generation
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

  // Bind each authoritative input to one immutable in-process snapshot. Parsing
  // and provenance hashes must describe the same bytes even if another agent
  // edits the shared worktree while generation is running.
  console.log(`Reading manifest from: ${MANIFEST_PATH}`);
  const manifestBytes = readRegularFileNoFollow(MANIFEST_PATH, 'Manifest');
  const result = parseManifestString(manifestBytes.toString('utf-8'));

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

  const categories: ModuleCategory[] = [...MODULE_CATEGORIES];
  console.log(`Categories: ${categories.join(', ')}`);
  console.log('');

  const manifestSha256 = computeContentSha256(manifestBytes);

  // Validate checksum coverage for known upstream installers (fail closed).
  if (!existsSync(CHECKSUMS_PATH)) {
    console.error(`Missing required file: ${CHECKSUMS_PATH}`);
    console.error('Refusing to generate scripts that require checksum verification without checksums.yaml.');
    process.exit(1);
  }

  const checksumsBytes = readRegularFileNoFollow(CHECKSUMS_PATH, 'Verified installer checksums');
  let installers: Record<string, InstallerChecksumEntry> = {};
  try {
    const checksums = parseYaml(checksumsBytes.toString('utf-8')) as {
      installers?: Record<string, InstallerChecksumEntry>;
    };
    installers = checksums.installers ?? {};
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
        'Update checksums.yaml (./scripts/lib/security.sh --update-checksums > /tmp/acfs-checksums.candidate.yaml, review the diff, then copy it over) or reconcile the manifest URLs before regenerating.'
      );
      process.exit(1);
    }
  } catch (err) {
    console.error(`Failed to parse checksums.yaml: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }

  // Explicit plugin inputs are a trust-boundary contract. A missing value or
  // unreadable/empty directory must never degrade to first-party-only output.
  let pluginPaths: string[];
  try {
    pluginPaths = collectPluginInputPaths(args);
  } catch (error) {
    console.error(`Plugin input error: ${error instanceof Error ? error.message : String(error)}`);
    process.exit(2);
  }

  let effectiveManifest = manifest;
  if (pluginPaths.length > 0) {
    const pluginResults: PluginValidationResult[] = [];
    const existingPluginModuleIds: string[] = [];

    for (const [pluginIndex, resolvedPath] of pluginPaths.entries()) {
      console.log(`Validating plugin manifest ${pluginIndex + 1}/${pluginPaths.length}`);
      const result = loadPluginManifestFromFile(resolvedPath, {
        firstPartyManifest: manifest,
        installers,
        existingPluginModuleIds,
      });

      if (!result.valid) {
        console.error('');
        console.error(formatPluginDiagnostics(result));
        console.error('');
        process.exit(1);
      }

      for (const m of result.manifestModules) {
        existingPluginModuleIds.push(m.id);
      }
      pluginResults.push(result);
      console.log(
        `✓ Plugin package "${result.package?.packageId ?? '<validated>'}" validated (${result.manifestModules.length} module(s))`
      );
    }

    effectiveManifest = mergeValidatedPlugins(manifest, pluginResults);

    // A plugin is first validated in isolation, but generation consumes the
    // merged graph. Re-run every first-party invariant over that exact graph so
    // no composition bug can bypass schema, dependency, orchestration, function
    // name, runner, or checksum policy.
    const mergedBasicValidation = validateManifestSchema(effectiveManifest);
    if (!mergedBasicValidation.valid) {
      console.error('');
      console.error(
        `Merged manifest validation failed with ${mergedBasicValidation.errors.length} error(s):`
      );
      for (const error of mergedBasicValidation.errors) {
        console.error(`- ${error.path}: ${error.message}`);
      }
      console.error('');
      process.exit(1);
    }

    const mergedAdvancedValidation = validateManifestAdvanced(effectiveManifest);
    if (!mergedAdvancedValidation.valid) {
      console.error('');
      console.error(formatValidationErrors(mergedAdvancedValidation));
      console.error('');
      process.exit(1);
    }

    const mergedChecksumErrors = validateVerifiedInstallerChecksums(
      effectiveManifest,
      installers
    );
    if (mergedChecksumErrors.length > 0) {
      console.error('Merged verified installer checksum validation failed:');
      for (const error of mergedChecksumErrors) {
        console.error(`- [${error.code}] ${error.message}`);
      }
      process.exit(1);
    }

    if (mergedBasicValidation.warnings.length > 0) {
      console.error('');
      console.error(
        `Merged manifest validation warnings (${mergedBasicValidation.warnings.length}):`
      );
      for (const warning of mergedBasicValidation.warnings) {
        console.error(`- ${warning.path}: ${warning.message}`);
      }
      console.error('');
    }

    console.log(
      `Merged ${pluginResults.length} plugin package(s) (${existingPluginModuleIds.length} total plugin modules)`
    );
    console.log('');
  }

  // --validate mode: validation already passed, print success and exit
  if (validateOnly) {
    console.log('✓ Manifest schema valid');
    console.log('✓ Manifest dependency graph valid');
    console.log('✓ Checksums.yaml coverage complete');
    if (pluginPaths.length > 0) {
      console.log(`✓ Plugin packages valid (${pluginPaths.length} package(s))`);
    }
    console.log('');
    console.log('Validation passed.');
    process.exit(0);
  }

  const projectVersion = readProjectVersion();
  const boundStaticSnapshots = new Map<string, Buffer>([
    [MANIFEST_PATH, manifestBytes],
    [CHECKSUMS_PATH, checksumsBytes],
  ]);

  // Build map of all files we would generate
  const filesToGenerate: Map<string, { content: string; mode: number }> = new Map();

  // Category scripts
  for (const category of categories) {
    const filename = `install_${category}.sh`;
    const filepath = join(OUTPUT_DIR, filename);
    const content = generateCategoryScript(effectiveManifest, category);
    filesToGenerate.set(filepath, { content, mode: 0o755 });
  }

  // Doctor checks
  {
    const filepath = join(OUTPUT_DIR, 'doctor_checks.sh');
    const content = generateDoctorChecks(effectiveManifest);
    filesToGenerate.set(filepath, { content, mode: 0o755 });
  }

  // Top-level installer
  {
    const filepath = join(OUTPUT_DIR, 'install_all.sh');
    const content = generateTopLevelInstaller(effectiveManifest);
    filesToGenerate.set(filepath, { content, mode: 0o755 });
  }

  // Manifest index
  {
    const filepath = join(OUTPUT_DIR, 'manifest_index.sh');
    const content = generateManifestIndex(effectiveManifest, manifestSha256);
    filesToGenerate.set(filepath, { content, mode: 0o644 });
  }

  // Internal script checksums (bd-3tpl)
  let internalChecksumSnapshots: ReadonlyMap<string, Buffer> = new Map();
  {
    const filepath = join(OUTPUT_DIR, 'internal_checksums.sh');
    const generated = generateInternalChecksums(filesToGenerate, boundStaticSnapshots);
    internalChecksumSnapshots = generated.staticSnapshots;
    filesToGenerate.set(filepath, { content: generated.content, mode: 0o644 });
  }

  // Web data: TypeScript modules for apps/web
  {
    const modulesPath = join(WEB_OUTPUT_DIR, 'manifest-modules.ts');
    filesToGenerate.set(modulesPath, {
      content: generateWebModules(
        effectiveManifest,
        projectVersion.value,
        manifestSha256,
        computeContentSha256(checksumsBytes),
      ),
      mode: 0o644,
    });

    const toolsPath = join(WEB_OUTPUT_DIR, 'manifest-tools.ts');
    filesToGenerate.set(toolsPath, { content: generateWebTools(effectiveManifest), mode: 0o644 });

    const commandsPath = join(WEB_OUTPUT_DIR, 'manifest-commands.ts');
    filesToGenerate.set(commandsPath, { content: generateWebCommands(effectiveManifest), mode: 0o644 });

    const tldrPath = join(WEB_OUTPUT_DIR, 'manifest-tldr.ts');
    filesToGenerate.set(tldrPath, { content: generateWebTldr(effectiveManifest), mode: 0o644 });

    const lessonsPath = join(WEB_OUTPUT_DIR, 'manifest-lessons-index.ts');
    filesToGenerate.set(lessonsPath, { content: generateWebLessonsIndex(effectiveManifest), mode: 0o644 });

    const indexPath = join(WEB_OUTPUT_DIR, 'manifest-web-index.ts');
    filesToGenerate.set(indexPath, { content: generateWebIndex(), mode: 0o644 });
  }

  const allInputSnapshots = new Map<string, Buffer>(internalChecksumSnapshots);
  allInputSnapshots.set(MANIFEST_PATH, manifestBytes);
  allInputSnapshots.set(CHECKSUMS_PATH, checksumsBytes);
  allInputSnapshots.set(VERSION_PATH, projectVersion.snapshot);
  const assertAllInputSnapshotsUnchanged = (): void => {
    for (const [path, snapshot] of allInputSnapshots) {
      const label = path === MANIFEST_PATH
        ? 'Manifest'
        : path === CHECKSUMS_PATH
          ? 'Verified installer checksums'
          : path === VERSION_PATH
            ? 'VERSION'
            : `Internal checksum input ${relative(PROJECT_ROOT, path)}`;
      assertInputSnapshotUnchanged(path, snapshot, label);
    }
  };
  assertAllInputSnapshotsUnchanged();

  for (const directory of [OUTPUT_DIR, WEB_OUTPUT_DIR]) {
    if (existsSync(directory)) assertSafeGeneratedDirectory(directory);
  }
  const actualPaths = [OUTPUT_DIR, WEB_OUTPUT_DIR].flatMap((directory) =>
    existsSync(directory)
      ? readdirSync(directory).map((name) => join(directory, name))
      : []
  );
  const stalePaths = findUnexpectedGeneratedPaths(filesToGenerate.keys(), actualPaths);

  // --diff mode: compare against existing files
  if (diffMode) {
    let hasDiff = false;
    console.log('Comparing generated content against existing files...');
    console.log('');

    for (const [filepath, { content, mode }] of filesToGenerate) {
      const filename = filepath.startsWith(WEB_OUTPUT_DIR)
        ? 'web/' + filepath.replace(WEB_OUTPUT_DIR + '/', '')
        : filepath.replace(OUTPUT_DIR + '/', '');
      if (existsSync(filepath)) {
        let existing: string | undefined;
        let actualMode: number | undefined;
        try {
          const inspected = inspectRegularFileNoFollow(filepath, `Generated output ${filename}`);
          existing = inspected.content.toString('utf-8');
          actualMode = inspected.mode;
        } catch (error) {
          hasDiff = true;
          // Keep the machine-consumed path token exact.  The drift checker
          // parses `[DIFF] <path>` lines; appending a diagnosis here would turn
          // the annotation into a fictitious filename.
          console.log(`[DIFF] ${filename}`);
          console.log('       Unsafe output type or link topology');
          if (verbose) console.log(`       ${error instanceof Error ? error.message : String(error)}`);
          continue;
        }
        if (existing !== content || (process.platform !== 'win32' && actualMode !== mode)) {
          hasDiff = true;
          console.log(`[DIFF] ${filename}`);
          if (verbose) {
            // Show a simple line count diff
            const existingLines = existing.split('\n').length;
            const newLines = content.split('\n').length;
            console.log(`       Existing: ${existingLines} lines, Generated: ${newLines} lines`);
            if (process.platform !== 'win32' && actualMode !== mode) {
              console.log(
                `       Mode: ${actualMode?.toString(8) ?? 'unknown'} (expected ${mode.toString(8)})`
              );
            }
          }
        } else {
          console.log(`[OK]   ${filename}`);
        }
      } else {
        hasDiff = true;
        console.log(`[NEW]  ${filename}`);
      }
    }

    for (const stalePath of stalePaths) {
      hasDiff = true;
      console.log(`[STALE] ${relative(PROJECT_ROOT, stalePath)}`);
    }

    assertAllInputSnapshotsUnchanged();
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
    assertAllInputSnapshotsUnchanged();
    console.log('');
    console.log('Dry run complete. No files written.');
    process.exit(0);
  }

  if (stalePaths.length > 0) {
    throw new Error(
      `Refusing generation while stale artifacts require explicit removal approval: ${stalePaths
        .map((path) => relative(PROJECT_ROOT, path))
        .join(', ')}`
    );
  }

  // Normal generation mode: write all files
  assertSafeGeneratedDirectory(OUTPUT_DIR);
  assertSafeGeneratedDirectory(WEB_OUTPUT_DIR);
  mkdirSync(OUTPUT_DIR, { recursive: true });
  mkdirSync(WEB_OUTPUT_DIR, { recursive: true });
  assertSafeGeneratedDirectory(OUTPUT_DIR);
  assertSafeGeneratedDirectory(WEB_OUTPUT_DIR);

  const generatedFiles: string[] = [];
  for (const [filepath, { content, mode }] of filesToGenerate) {
    writeGeneratedFileNoFollow(filepath, content, mode);
    const filename = filepath.startsWith(WEB_OUTPUT_DIR)
      ? 'web/' + filepath.replace(WEB_OUTPUT_DIR + '/', '')
      : filepath.replace(OUTPUT_DIR + '/', '');
    console.log(`Generated: ${filename}`);
    generatedFiles.push(filepath);
  }
  assertAllInputSnapshotsUnchanged();

  console.log('');
  console.log(`Generated ${generatedFiles.length} files (${OUTPUT_DIR} + ${WEB_OUTPUT_DIR})`);
}

function isDirectInvocation(): boolean {
  const scriptArg = process.argv[1];
  if (!scriptArg) return false;
  return import.meta.url === pathToFileURL(resolve(scriptArg)).href;
}

if (isDirectInvocation()) {
  main().catch((err) => {
    console.error('Generator failed:', err);
    process.exit(1);
  });
}
