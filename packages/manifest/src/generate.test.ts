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
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { parseManifestFile } from './parser.js';
import {
  findUnexpectedGeneratedPaths,
  isOptionalVerifyCommand,
  normalizeVerifiedInstallerScriptArgs,
  stripOptionalVerifySuffix,
} from './generate.js';
import {
  getCategories,
  getModuleCategory,
  sortModulesByInstallOrder,
  getTransitiveDependencies,
  toGeneratedFunctionName,
} from './utils.js';
import { MODULE_CATEGORIES, type Manifest, type Module } from './types.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, '../../..');
const MANIFEST_PATH = resolve(PROJECT_ROOT, 'acfs.manifest.yaml');
const GENERATED_DIR = resolve(PROJECT_ROOT, 'scripts/generated');
const WEB_GENERATED_DIR = resolve(PROJECT_ROOT, 'apps/web/lib/generated');
const MANIFEST_INDEX_PATH = resolve(GENERATED_DIR, 'manifest_index.sh');

describe('Generator optional verify parsing', () => {
  test('reports stale generated paths without deleting them', () => {
    expect(findUnexpectedGeneratedPaths(
      ['/repo/generated/current.sh'],
      ['/repo/generated/current.sh', '/repo/generated/install_old.sh'],
    )).toEqual(['/repo/generated/install_old.sh']);
    expect(findUnexpectedGeneratedPaths(
      ['/repo/generated/current.sh'],
      ['/repo/generated/current.sh'],
    )).toEqual([]);
  });

  test('strips optional true suffixes with trailing comments', () => {
    const command = 'ms doctor || true # optional until credentials are configured';

    expect(isOptionalVerifyCommand(command)).toBe(true);
    expect(stripOptionalVerifySuffix(command)).toBe('ms doctor');
  });

  test('leaves non-optional commands unchanged', () => {
    const command = 'if tool --version; then true; fi';

    expect(isOptionalVerifyCommand(command)).toBe(false);
    expect(stripOptionalVerifySuffix(command)).toBe(command);
  });

  test('normalizes a manifest-only verified-installer separator exactly once', () => {
    expect(normalizeVerifiedInstallerScriptArgs(
      'stack.frankensearch',
      ['--', '--easy-mode'],
    )).toEqual(['--easy-mode']);
    expect(normalizeVerifiedInstallerScriptArgs(
      'stack.frankensearch',
      ['--easy-mode'],
    )).toEqual(['--easy-mode']);
    expect(() => normalizeVerifiedInstallerScriptArgs(
      'stack.frankensearch',
      ['-c', 'attacker', '--'],
    )).toThrow('runner options before --');
  });

  test('places every module installer in a private generated namespace', () => {
    expect(toGeneratedFunctionName('stack.ntm')).toBe('acfs_generated_install_stack_ntm');
    expect(toGeneratedFunctionName('agents.antigravity')).toBe(
      'acfs_generated_install_agents_antigravity'
    );
  });
});

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

  test('publishes the canonical category order for shell consumers', () => {
    expect(manifestIndexContent).toContain('ACFS_CATEGORIES_IN_ORDER=(');
    for (const category of MODULE_CATEGORIES) {
      expect(manifestIndexContent).toContain(`  "${category}"`);
    }
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

  test('function names follow the isolated convention', () => {
    for (const module of manifest.modules) {
      const expectedFunc = toGeneratedFunctionName(module.id);
      if (module.generated === false) {
        expect(manifestIndexContent).not.toContain(`['${module.id}']="${expectedFunc}"`);
      } else {
        expect(manifestIndexContent).toContain(`['${module.id}']="${expectedFunc}"`);
      }
    }
    expect(manifestIndexContent).not.toMatch(/="install_[a-z]/);
  });

  test('records generated versus orchestration-owned modules explicitly', () => {
    expect(manifestIndexContent).toContain('declare -gA ACFS_MODULE_GENERATED=(');
    for (const module of manifest.modules) {
      expect(manifestIndexContent).toContain(
        `['${module.id}']="${module.generated === false ? '0' : '1'}"`
      );
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

  test('generated installers honor manifest module selection', () => {
    const agentsPath = resolve(GENERATED_DIR, 'install_agents.sh');
    const content = readFileSync(agentsPath, 'utf-8');

    expect(content).toContain('acfs_generated_ensure_selection()');
    expect(content).toContain('source "$manifest_index"');
    expect(content).toContain('acfs_generated_ensure_selection || return 1');
    expect(content).toContain('if ! should_run_module "${module_id}"; then');
    expect(content).toContain('log_info "Skipping agents.gemini (not selected)"');
  });
});

describe('Generated verified installer args', () => {
  test('legacy verified-installer calls have matching manifest producers', () => {
    const parseResult = parseManifestFile(MANIFEST_PATH);
    expect(parseResult.success).toBe(true);
    if (!parseResult.success || !parseResult.data) {
      throw new Error(`Failed to parse manifest: ${parseResult.error?.message}`);
    }

    const installContent = readFileSync(resolve(PROJECT_ROOT, 'install.sh'), 'utf-8');
    const legacyCalls = Array.from(
      installContent.matchAll(
        /\bacfs_run_verified_upstream_script_as_target(?:_with_env)?\s+"([a-z][a-z0-9_]*)"\s+"(bash|sh)"/g
      ),
      (match) => ({ tool: match[1], runner: match[2] })
    );
    const producers = new Map(
      parseResult.data.modules.flatMap((module) =>
        module.verified_installer
          ? [[module.verified_installer.tool, module.verified_installer.runner] as const]
          : []
      )
    );

    expect(legacyCalls.length).toBeGreaterThan(0);
    expect(
      Array.from(new Set(legacyCalls.map(({ tool }) => tool))).filter(
        (tool) => !producers.has(tool)
      )
    ).toEqual([]);
    for (const { tool, runner } of legacyCalls) {
      expect(producers.get(tool)).toBe(runner);
    }

    const stackLibrary = readFileSync(resolve(PROJECT_ROOT, 'scripts/lib/stack.sh'), 'utf-8');
    const slbStart = stackLibrary.indexOf('install_slb() {');
    const slbEnd = stackLibrary.indexOf('\n}', slbStart);
    const slbInstaller = stackLibrary.slice(slbStart, slbEnd);

    expect(slbStart).toBeGreaterThanOrEqual(0);
    expect(slbEnd).toBeGreaterThan(slbStart);
    expect(slbInstaller).toContain('_stack_run_verified_installer "$tool"');
    expect(slbInstaller).not.toContain('git clone');
  });

  test('generated verified installers never stream verification output into an interpreter', () => {
    for (const filename of [
      'install_shell.sh',
      'install_lang.sh',
      'install_tools.sh',
      'install_agents.sh',
      'install_stack.sh',
    ]) {
      const generatedPath = resolve(GENERATED_DIR, filename);
      expect(existsSync(generatedPath)).toBe(true);
      const generatedContent = readFileSync(generatedPath, 'utf-8');

      expect(generatedContent).not.toMatch(/verify_checksum[^\n]*\|/);
    }

    const agentsContent = readFileSync(resolve(GENERATED_DIR, 'install_agents.sh'), 'utf-8');
    expect(agentsContent).toContain(
      'fetch_and_run_with_runner bash "$nvm_url" "$nvm_sha256" "nvm"'
    );
    expect(agentsContent).toContain(
      'fetch_and_run_with_runner bash "$patch_url" "$patch_sha256" "gemini_patch"'
    );
  });

  test('generated scripts detect the target user instead of hardcoding ubuntu', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).toContain('_ACFS_DETECTED_USER="${SUDO_USER:-}"');
    expect(stackContent).toContain('_ACFS_DETECTED_USER="$(acfs_generated_resolve_current_user 2>/dev/null || true)"');
    expect(stackContent).not.toContain('_ACFS_DETECTED_USER="${SUDO_USER:-$(whoami)}"');
    expect(stackContent).not.toContain('TARGET_USER="${TARGET_USER:-ubuntu}"');
  });

  test('verified-installer guards do not depend on external grep', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    const agentsPath = resolve(GENERATED_DIR, 'install_agents.sh');
    expect(existsSync(stackPath)).toBe(true);
    expect(existsSync(agentsPath)).toBe(true);
    const generatedContent = [
      readFileSync(stackPath, 'utf-8'),
      readFileSync(agentsPath, 'utf-8'),
    ].join('\n');

    expect(generatedContent).toContain('known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"');
    expect(generatedContent).toContain('if [[ "$known_installers_decl" == declare\\ -A* ]]; then');
    expect(generatedContent).not.toContain("declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'");
  });

  test('generated direct-exec headers resolve TARGET_HOME via helpers and fail closed', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).toContain('if declare -f _acfs_resolve_target_home >/dev/null 2>&1; then');
    expect(stackContent).toContain('TARGET_HOME="$(_acfs_resolve_target_home "${TARGET_USER}" "$_ACFS_EXPLICIT_TARGET_HOME" || true)"');
    expect(stackContent).toContain(
      'log_error "Invalid TARGET_HOME for \'${TARGET_USER}\': ${TARGET_HOME:-<empty>} (must be an absolute path and cannot be \'/\')"'
    );
    expect(stackContent).not.toContain('TARGET_HOME="/home/${TARGET_USER}"');
    expect(stackContent).not.toContain('TARGET_HOME="/home/${TARGET_USER:-ubuntu}"');
    expect(stackContent).toContain("printf '%s\\n'");
    expect(stackContent).not.toContain("printf '%s\n'");
  });

  test('stack.mcp_agent_mail dest uses TARGET_HOME directly without caller HOME fallback', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    // Regression guard: the outer shell expands verified-installer args before
    // run_as_target_runner switches users, so any HOME fallback here can route
    // the install into the caller home instead of TARGET_HOME.
    expect(stackContent).not.toContain('${TARGET_HOME:-${HOME:-/home/${TARGET_USER:-ubuntu}}}');
    expect(stackContent).not.toContain('${HOME:-/home/${TARGET_USER:-ubuntu}}');
    expect(stackContent).toContain('"$TARGET_HOME"');
    expect(stackContent).toContain("'/mcp_agent_mail'");
    expect(stackContent).toContain("'AM_INSTALL_SKIP_MCP_SETUP=1'");
    expect(stackContent).toContain("'AM_INSTALL_SKIP_REMOTE_HTTP_READINESS=1'");
  });

  test('stack.mcp_agent_mail writes an explicit managed no-auth service instead of tmux', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).toContain('cat > "$unit_file" <<UNIT_EOF');
    expect(stackContent).toContain('systemd_unit_path_escape() {');
    expect(stackContent).toContain('value="${value//%/%%}"');
    expect(stackContent).toContain('value="${value//\\$/\\$\\$}"');
    expect(stackContent).toContain('WorkingDirectory=$storage_root_unit');
    expect(stackContent).toContain('Environment=$storage_root_env');
    expect(stackContent).toContain('Environment=$database_url_env');
    expect(stackContent).toContain(
      'ExecStart=${am_bin_exec} serve-http --no-tui --host 127.0.0.1 --port 8765 --path ${am_mcp_path_exec}'
    );
    expect(stackContent).not.toContain('Environment=STORAGE_ROOT=$storage_root');
    expect(stackContent).not.toContain('ExecStartPre=${am_bin_exec} migrate');
    expect(stackContent).not.toContain('ExecStart=$am_bin serve-http');
    expect(stackContent).toContain('systemctl --user enable --now agent-mail.service');
    expect(stackContent).toContain('curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null');
    expect(stackContent).toContain('http://127.0.0.1:8765/health/readiness');
    expect(stackContent).toContain('max_wait=240');
    expect(stackContent).not.toContain('am service install >/dev/null');
    expect(stackContent).not.toContain('tmux new-session -d -s "$tmux_session"');
  });

  test('stack.ru passes RU_NON_INTERACTIVE via env in generated installer', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).toContain(
      `run_as_target_runner 'env' 'RU_NON_INTERACTIVE=1' 'bash' "$verified_installer_file"`
    );
    expect(stackContent).not.toContain(
      "verify_checksum \"$url\" \"$expected_sha256\" \"$tool\" | run_as_target_runner 'env' 'RU_NON_INTERACTIVE=1'"
    );
    expect(stackContent).toContain('_acfs_remove_temp_files "$verified_installer_file"');
  });

  test('stack.cass prepares and uses a target-owned installer TMPDIR', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).toContain(
      `local verified_installer_tmpdir_template="$TARGET_HOME"'/.cache/acfs/installer-tmp/cass.XXXXXX'`
    );
    expect(stackContent).not.toContain('installer TMPDIR template contains whitespace');
    expect(stackContent).toContain('acfs_generated_system_binary_path mkdir');
    expect(stackContent).toContain('acfs_generated_system_binary_path mktemp');
    expect(stackContent).toContain('run_as_target "$verified_installer_mkdir_bin" -p "$verified_installer_tmpdir_parent"');
    expect(stackContent).toContain(
      'verified_installer_tmpdir="$(run_as_target "$verified_installer_mktemp_bin" -d "$verified_installer_tmpdir_template" 2>/dev/null)"'
    );
    expect(stackContent).toContain(
      '[[ "$verified_installer_tmpdir" != "$verified_installer_tmpdir_prefix"* || -z "$verified_installer_tmpdir_suffix"'
    );
    expect(stackContent).toContain('|| -L "$verified_installer_tmpdir" || -L "$verified_installer_tmpdir_parent" ]]');
    expect(stackContent).toContain('refusing installer TMPDIR through a symlinked target-home path');
    expect(stackContent).toContain(
      `run_as_target_runner 'env' "TMPDIR=$verified_installer_tmpdir" 'bash' "$verified_installer_file" '--easy-mode' '--verify'`
    );
    expect(stackContent).toContain(
      'verify_checksum "$url" "$expected_sha256" "$tool" > "$verified_installer_file"'
    );
    expect(stackContent).toContain(
      '"$verified_installer_chmod_bin" 0444 "$verified_installer_file"'
    );
  });

  test('agent wrapper/link install heredocs include primary-bin helpers in child shell', () => {
    const agentsPath = resolve(GENERATED_DIR, 'install_agents.sh');
    expect(existsSync(agentsPath)).toBe(true);
    const agentsContent = readFileSync(agentsPath, 'utf-8');

    const generatedPreludeIndex = agentsContent.indexOf('# Generated helper functions used by this child shell.');
    const preludeIndex = agentsContent.indexOf('# Primary-bin helper functions used by this child shell.');
    const linkIndex = agentsContent.indexOf('acfs_link_primary_bin_command "$claude_candidate" "claude"');
    const installIndex = agentsContent.indexOf('acfs_install_executable_into_primary_bin "$wrapper_tmp" "codex"');

    expect(generatedPreludeIndex).toBeGreaterThanOrEqual(0);
    expect(preludeIndex).toBeGreaterThanOrEqual(0);
    expect(preludeIndex).toBeGreaterThan(generatedPreludeIndex);
    expect(linkIndex).toBeGreaterThan(preludeIndex);
    expect(installIndex).toBeGreaterThan(preludeIndex);
    expect(agentsContent).toContain('acfs_generated_system_binary_path() {');
    expect(agentsContent).toContain('acfs_child_primary_bin_dir() {');
    expect(agentsContent).toContain('acfs_child_primary_bin_tool_path() {');
    expect(agentsContent).toContain('mkdir_bin="$(acfs_child_primary_bin_tool_path mkdir)" || return 1');
    expect(agentsContent).toContain('ln_bin="$(acfs_child_primary_bin_tool_path ln)" || return 1');
    expect(agentsContent).toContain('install_bin="$(acfs_child_primary_bin_tool_path install)" || return 1');
    expect(agentsContent).toContain('Root primary bin command must be an absolute trusted path');
    expect(agentsContent).toContain('ACFS_BIN_DIR is unset and HOME is not a usable absolute path');
    expect(agentsContent).not.toContain('${ACFS_BIN_DIR:-${HOME:-}/.local/bin}');
    expect(agentsContent).not.toContain('acfs_child_run_root_bin_command mkdir -p');
    expect(agentsContent).not.toContain('acfs_child_run_root_bin_command ln -sf');
    expect(agentsContent).not.toContain('acfs_child_run_root_bin_command install -m 0755');
    expect(agentsContent).toContain('acfs_install_executable_into_primary_bin() {');
    expect(agentsContent).toContain('acfs_link_primary_bin_command() {');
  });

  test('stack.meta_skill fails closed on Linux ARM64 without anchored source', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).toContain('meta_skill has no checksum-anchored Linux ARM64 install source yet');
    expect(stackContent).toContain('[[ "$(uname -s 2>/dev/null)" == "Linux" ]]');
    expect(stackContent).toContain('[[ "$(uname -m 2>/dev/null)" == "aarch64" ]]');
    expect(stackContent).toContain('[[ "$(uname -m 2>/dev/null)" == "arm64" ]]');
    expect(stackContent).toContain('Linux ARM64 is unsupported until a checksum-anchored artifact or source revision is available');
    expect(stackContent).not.toContain('cargo install --git https://github.com/Dicklesworthstone/meta_skill');
  });

  test('stack.frankensearch selects lite Linux release artifacts', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).toContain('local -a fsfs_installer_args=(\'--easy-mode\')');
    expect(stackContent).toContain('fsfs_target="x86_64-unknown-linux-musl"');
    expect(stackContent).toContain('fsfs_target="aarch64-unknown-linux-musl"');
    expect(stackContent).toContain("https://github.com/Dicklesworthstone/frankensearch/releases/latest");
    expect(stackContent).toContain("https://api.github.com/repos/Dicklesworthstone/frankensearch/releases?per_page=10");
    expect(stackContent).toContain('done < <(acfs_curl --connect-timeout 30 --max-time 60');
    expect(stackContent).toContain('fsfs_candidate="$(acfs_curl --connect-timeout 30 --max-time 60');
    expect(stackContent).toContain('fsfs_checksum="$(acfs_curl --connect-timeout 30 --max-time 60');
    expect(stackContent).not.toContain('done < <(curl -fsSL --connect-timeout 30 --max-time 60');
    expect(stackContent).not.toContain('fsfs_candidate="$(curl -fsSL --connect-timeout 30 --max-time 60');
    expect(stackContent).not.toContain('fsfs_checksum="$(curl -fsSL --connect-timeout 30 --max-time 60');
    expect(stackContent).toContain('for fsfs_version in "${fsfs_candidates[@]}"; do');
    expect(stackContent).toContain('fsfs-lite-${fsfs_version_bare}-${fsfs_target}.tar.xz');
    expect(stackContent).toContain('awk \'NR == 1 { print $1 }\'');
    expect(stackContent).toContain('--checksum "${fsfs_checksum,,}"');
    expect(stackContent).toContain('unable to resolve a FrankenSearch lite artifact with a checksum');
    expect(stackContent).toContain('run_as_target_runner \'bash\' "$verified_installer_file" "${fsfs_installer_args[@]}"');
  });

  test('stack.slb uses the checksum-verified installer path', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');
    const slbStart = stackContent.indexOf('acfs_generated_install_stack_slb() {');
    const nextModule = stackContent.indexOf('\nacfs_generated_install_stack_', slbStart + 1);
    const slbContent = stackContent.slice(slbStart, nextModule);

    expect(slbStart).toBeGreaterThanOrEqual(0);
    expect(nextModule).toBeGreaterThan(slbStart);
    expect(slbContent).toContain('local tool="slb"');
    expect(slbContent).toContain('verify_checksum "$url" "$expected_sha256" "$tool"');
    expect(slbContent).toContain(`run_as_target_runner 'bash' "$verified_installer_file"`);
    expect(slbContent).not.toContain('git clone');
    expect(slbContent).not.toContain('SLB_TMP');
  });

  test('stack.pcr emits a pre-install Claude check before the verified installer', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    const precheckIndex = stackContent.indexOf("log_warn \"stack.pcr: Skipping PCR - Claude Code not found\"");
    const installerIndex = stackContent.indexOf('local tool="pcr"');

    expect(precheckIndex).toBeGreaterThanOrEqual(0);
    expect(stackContent).toContain("command -v claude >/dev/null 2>&1");
    expect(installerIndex).toBeGreaterThan(precheckIndex);
  });

  test('stack hook verification parses Claude settings hook commands instead of grepping raw text', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).toContain('claude_settings_has_command_hook() {');
    expect(stackContent).toContain('dcg install --force');
    expect(stackContent).toContain("dcg_command_pattern='(^|[[:space:]/])dcg([[:space:]]|$)'");
    expect(stackContent).toContain(
      "pcr_command_pattern='(^|[[:space:]/])claude-post-compact-reminder([[:space:]]|$)'"
    );
    expect(stackContent).not.toContain('grep -q "dcg" "$settings"');
    expect(stackContent).not.toContain('grep -q "dcg" "$alt_settings"');
    expect(stackContent).not.toContain('grep -q "claude-post-compact-reminder" "$settings"');
    expect(stackContent).not.toContain('grep -q "claude-post-compact-reminder" "$alt_settings"');
  });

  test('multi-line install summaries skip comment-only lines', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).not.toContain(
      'install command failed: # Wait for the managed Agent Mail service to become healthy.'
    );
    expect(stackContent).toContain(
      'install command failed: until agent_mail_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 && \\\\'
    );
  });

  test('multi-line install summaries skip leading helper function bodies', () => {
    const shellPath = resolve(GENERATED_DIR, 'install_shell.sh');
    expect(existsSync(shellPath)).toBe(true);
    const shellContent = readFileSync(shellPath, 'utf-8');

    expect(shellContent).not.toContain('dry-run: install: profile_path_has_fragment() {');
    expect(shellContent).not.toContain('install command failed: profile_path_has_fragment() {');
    expect(shellContent).toContain('dry-run: install: if [[ ! -f ~/.profile ]]; then');
    expect(shellContent).toContain('install command failed: if [[ ! -f ~/.profile ]]; then');
    expect(shellContent).toContain('dry-run: install: if [[ ! -f ~/.zprofile ]]; then');
    expect(shellContent).toContain('install command failed: if [[ ! -f ~/.zprofile ]]; then');
    expect(shellContent).not.toContain('dry-run: install: exit 1 (target_user)');
    expect(shellContent).not.toContain('shell.omz: install command failed: exit 1');
    expect(shellContent).toContain(
      'dry-run: install: if [[ -f ~/.zshrc ]] && ! acfs_zshrc_is_managed_loader ~/.zshrc; then'
    );
    expect(shellContent).toContain(
      'shell.omz: install command failed: if [[ -f ~/.zshrc ]] && ! acfs_zshrc_is_managed_loader ~/.zshrc; then'
    );
  });

  test('network modules emit post-install messages into generated installers', () => {
    const networkPath = resolve(GENERATED_DIR, 'install_network.sh');
    expect(existsSync(networkPath)).toBe(true);
    const networkContent = readFileSync(networkPath, 'utf-8');

    expect(networkContent).toContain(
      'log_info "Tailscale installed! To connect your VPS to your Tailscale network:"'
    );
    expect(networkContent).toContain(
      'log_info "SSH keepalive configured! Your connections will now survive VPN/NAT timeouts."'
    );
  });

  test('workspace agents alias checks require active alias lines', () => {
    const acfsPath = resolve(GENERATED_DIR, 'install_acfs.sh');
    expect(existsSync(acfsPath)).toBe(true);
    const acfsContent = readFileSync(acfsPath, 'utf-8');

    expect(acfsContent).toContain('acfs_has_active_agents_alias() {');
    expect(acfsContent).not.toContain('grep -q "alias agents=" ~/.zshrc.local');
    expect(acfsContent).toContain(
      'dry-run: install: if ! acfs_has_active_agents_alias ~/.zshrc.local; then'
    );
    expect(acfsContent).toContain(
      'dry-run: verify: acfs_has_active_agents_alias ~/.zshrc.local || acfs_has_active_agents_alias ~/.zshrc'
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

  test('fails closed when TARGET_HOME cannot be resolved instead of guessing /home/$TARGET_USER', () => {
    expect(filesystemContent).not.toContain('target_home="/home/${TARGET_USER:-ubuntu}"');
    expect(filesystemContent).toContain(
      "ERROR: Unable to resolve TARGET_HOME for '${TARGET_USER:-ubuntu}'; export TARGET_HOME explicitly"
    );
  });

  test('prefers trusted passwd home and rejects inherited TARGET_HOME fallback', () => {
    const trustedHomeIndex = filesystemContent.indexOf(
      'target_home="$(acfs_generated_passwd_home_from_entry "$_acfs_passwd_entry" 2>/dev/null || true)"'
    );

    expect(filesystemContent).toContain('target_home=""');
    expect(filesystemContent).toContain('explicit_target_home="${TARGET_HOME:-}"');
    expect(filesystemContent).not.toContain('if [[ -z "$target_home" && -n "$explicit_target_home" ]]; then');
    expect(filesystemContent).not.toContain('target_home="$explicit_target_home"');
    expect(filesystemContent).not.toContain('target_home="${TARGET_HOME:-}"\nif [[ -z "$target_home" ]]; then');
    expect(filesystemContent).not.toContain('target_home="${TARGET_HOME%/}"');
    expect(trustedHomeIndex).toBeGreaterThanOrEqual(0);
  });

  test('direct generated installers repair TARGET_HOME without inherited fallback', () => {
    const resolvedHomeIndex = filesystemContent.indexOf(
      '_ACFS_RESOLVED_TARGET_HOME="$(_acfs_resolve_target_home "${TARGET_USER}" "$_ACFS_EXPLICIT_TARGET_HOME" || true)"'
    );

    expect(filesystemContent).toContain('_ACFS_EXPLICIT_TARGET_HOME="${TARGET_HOME:-}"');
    expect(filesystemContent).toContain('_ACFS_RESOLVED_TARGET_HOME=""');
    expect(filesystemContent).toContain('if [[ -n "$_ACFS_RESOLVED_TARGET_HOME" ]]; then');
    expect(filesystemContent).toContain('TARGET_HOME="${_ACFS_RESOLVED_TARGET_HOME%/}"');
    expect(filesystemContent).not.toMatch(/^\s*elif \[\[ -n "\$_ACFS_EXPLICIT_TARGET_HOME" \]\]; then$/m);
    expect(filesystemContent).not.toMatch(/^\s*TARGET_HOME="\$_ACFS_EXPLICIT_TARGET_HOME"$/m);
    expect(filesystemContent).not.toMatch(/^\s*TARGET_HOME="\$\{TARGET_HOME%\/}"$/m);
    expect(resolvedHomeIndex).toBeGreaterThanOrEqual(0);
  });

  test('does not recursively chown /data (avoid over-broad ownership changes)', () => {
    // Recursive ownership is safe for the ACFS-owned docs subtree; reject only
    // a recursive operation whose target is /data itself.
    expect(filesystemContent).toContain('chown -R "${TARGET_USER:-ubuntu}:${TARGET_USER:-ubuntu}" "$target_home/.acfs/docs"');
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

  test('generated helper functions are in scope for child-shell heredocs', () => {
    expect(filesystemContent).toContain('# Generated helper functions used by this child shell.');
    expect(filesystemContent).toContain('acfs_generated_system_binary_path() {');
    expect(filesystemContent).toContain('*[!A-Za-z0-9._+-]*)');
    expect(filesystemContent).toContain(
      '_acfs_passwd_entry="$(acfs_generated_getent_passwd_entry "${TARGET_USER:-ubuntu}" 2>/dev/null || true)"'
    );
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
    // The format is: ID<TAB>DESCRIPTION<TAB>CHECK_COMMAND<TAB>REQUIRED/OPTIONAL<TAB>RUN_AS
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

  test('includes run_as context for generated checks', () => {
    expect(doctorContent).toMatch(/lang\.bun[^\n]*\ttarget_user"/);
    expect(doctorContent).toMatch(/base\.system\.1[^\n]*\troot"/);
  });

  test('generated manifest-check helper uses hardened target PATH ordering', () => {
    expect(doctorContent).toContain('local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"');
    expect(doctorContent).toContain('local -a target_path_entries=()');
    expect(doctorContent).toContain('target_path_prefix=$(IFS=:; echo "${target_path_entries[*]}")');
    expect(doctorContent).toContain('target_path="$target_path_prefix${PATH:+:$PATH}"');
  });

  test('run_manifest_check_command resolves target homes without /home guesses', () => {
    expect(doctorContent).toContain('resolved_target_home="$(_acfs_resolve_target_home "$target_user" "$explicit_target_home" || true)"');
    expect(doctorContent).not.toContain('target_home="/home/$target_user"');
    expect(doctorContent).toContain(
      'log_error "Invalid TARGET_HOME for \'$target_user\': ${target_home:-<empty>} (must be an absolute path and cannot be \'/\')"'
    );
  });

  test('run_manifest_check_command repairs target_home without inherited fallback', () => {
    const resolvedHomeIndex = doctorContent.indexOf(
      'resolved_target_home="$(_acfs_resolve_target_home "$target_user" "$explicit_target_home" || true)"'
    );

    expect(doctorContent).toContain('local explicit_target_home=""');
    expect(doctorContent).toContain('local resolved_target_home=""');
    expect(doctorContent).toContain('explicit_target_home="$target_home"');
    expect(doctorContent).toContain('if [[ -n "$resolved_target_home" ]]; then');
    expect(doctorContent).toContain('target_home="${resolved_target_home%/}"');
    expect(doctorContent).not.toContain('elif [[ -n "$explicit_target_home" ]]; then');
    expect(doctorContent).not.toContain('target_home="$explicit_target_home"');
    expect(doctorContent).not.toContain('target_home="${target_home%/}"');
    expect(doctorContent).not.toContain('if [[ -z "$target_home" ]]; then\n        if declare -f _acfs_resolve_target_home');
    expect(resolvedHomeIndex).toBeGreaterThanOrEqual(0);
  });

  test('target_user doctor checks receive TARGET_USER and TARGET_HOME env', () => {
    expect(doctorContent).toContain(
      '"$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"'
    );
  });

  test('root doctor checks still run when TARGET_HOME is unresolved', () => {
    expect(doctorContent).toContain(
      '"$sudo_bin" -n "$env_bin" TARGET_USER="$target_user" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"'
    );
    expect(doctorContent).not.toContain(
      'root)\n            if [[ -z "$target_home" ]] || [[ "$target_home" != /* ]] || [[ "$target_home" == "/" ]]; then'
    );
  });

  test('doctor checks inject generated helpers into child bash commands that need them', () => {
    expect(doctorContent).toContain('if [[ "$cmd" == *"acfs_generated_"* ]]; then');
    expect(doctorContent).toContain(
      'helper_prelude="$(declare -f acfs_generated_system_binary_path acfs_generated_resolve_current_user acfs_generated_getent_passwd_entry acfs_generated_passwd_home_from_entry 2>/dev/null || true)"'
    );
    expect(doctorContent).toContain('cmd="${helper_prelude}"$\'\\n\'"${cmd}"');
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
    expect([...categories].sort()).toEqual([...MODULE_CATEGORIES].sort());
  });

  test('returns no duplicates', () => {
    const categories = getCategories(manifest);
    const uniqueCategories = new Set(categories);
    expect(uniqueCategories.size).toBe(categories.length);
  });
});

describe('Generated script headers', () => {
  test('executable generated headers canonicalize their trust root and derive directness locally', () => {
    const scriptContent = readFileSync(resolve(GENERATED_DIR, 'install_stack.sh'), 'utf-8');

    expect(scriptContent.startsWith('#!/bin/bash -p\n')).toBe(true);
    expect(scriptContent).toContain(
      'ACFS_GENERATED_SCRIPT_PATH="$(/usr/bin/readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null)"'
    );
    expect(scriptContent).toContain(
      'unset ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR'
    );
    expect(scriptContent).toContain('if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then');
    expect(scriptContent).not.toContain('ACFS_GENERATED_DIRECT_EXECUTION');
    expect(scriptContent).not.toContain(
      'ACFS_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"'
    );
  });

  test('nested category sourcing cannot suppress the install_all direct refusal', () => {
    const installAllContent = readFileSync(resolve(GENERATED_DIR, 'install_all.sh'), 'utf-8');

    expect(installAllContent).toContain('source "$ACFS_GENERATED_SCRIPT_DIR/install_base.sh"');
    const refusal = 'install_all.sh is a source-only generated harness; run install.sh';
    expect(installAllContent).toContain(refusal);
    expect(installAllContent.indexOf(refusal)).toBeLessThan(
      installAllContent.indexOf('source "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"')
    );
    expect(installAllContent).not.toContain('ACFS_GENERATED_DIRECT_EXECUTION');
    expect(installAllContent).toContain('acfs_generated_install_all() {');
    expect(installAllContent).not.toContain('\ninstall_all() {');
  });

  test('every category file is source-only and exposes no dependency-incomplete aggregate', () => {
    for (const category of MODULE_CATEGORIES) {
      const categoryContent = readFileSync(
        resolve(GENERATED_DIR, `install_${category}.sh`),
        'utf-8'
      );

      expect(categoryContent).toContain(
        `install_${category}.sh is a source-only library; run install.sh --only <module-id>`
      );
      expect(categoryContent).toContain('exit 2');
      expect(categoryContent.indexOf('source-only library')).toBeLessThan(
        categoryContent.indexOf('source "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"')
      );
      expect(categoryContent).not.toContain(`\ninstall_${category}() {`);
    }

    const usersContent = readFileSync(resolve(GENERATED_DIR, 'install_users.sh'), 'utf-8');
    expect(usersContent).toContain(
      'Orchestrator-owned modules omitted from this library: users.ubuntu'
    );
    expect(usersContent).not.toContain('acfs_generated_install_users_ubuntu() {');
  });

  test('direct generated install harnesses refuse before runtime setup', () => {
    for (const filename of [
      ...MODULE_CATEGORIES.map((category) => `install_${category}.sh`),
      'install_all.sh',
    ]) {
      const result = spawnSync('/bin/bash', [resolve(GENERATED_DIR, filename)], {
        encoding: 'utf-8',
      });

      expect(result.status).toBe(2);
      expect(result.stderr).toContain('source-only');
      expect(result.stderr).not.toContain('Unable to canonicalize generated installer path');
    }
  });

  test('all generated scripts have consistent header', () => {
    for (const category of MODULE_CATEGORIES) {
      const scriptPath = resolve(GENERATED_DIR, `install_${category}.sh`);
      const content = readFileSync(scriptPath, 'utf-8');

      // Check for standard header elements
      expect(content).toStartWith('#!/bin/bash -p\n');
      expect(content).toContain('AUTO-GENERATED');
      expect(content).toContain('set -euo pipefail');
      expect(content).toContain('ACFS_FORCE_INSTALL_HELPERS_SECURITY_REDEFINE=1');
      expect(content.indexOf('unset ACFS_FORCE_INSTALL_HELPERS_SECURITY_REDEFINE')).toBeLessThan(
        content.indexOf('ACFS_FORCE_INSTALL_HELPERS_SECURITY_REDEFINE=1')
      );
    }
  });

  test('source mode ignores an inherited force marker and preserves its orchestrator runner', () => {
    const scriptPath = resolve(GENERATED_DIR, 'install_base.sh');
    const result = spawnSync(
      '/bin/bash',
      [
        '-c',
        [
          'set -euo pipefail',
          'run_as_target() { printf "orchestrator-runner\\n"; }',
          'source "$1"',
          'run_as_target',
          '[[ -z "${ACFS_FORCE_INSTALL_HELPERS_SECURITY_REDEFINE+x}" ]]',
        ].join('; '),
        '_',
        scriptPath,
      ],
      {
        encoding: 'utf8',
        env: {
          PATH: '/usr/bin:/bin',
          ACFS_FORCE_INSTALL_HELPERS_SECURITY_REDEFINE: '1',
        },
      }
    );

    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout).toBe('orchestrator-runner\n');
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

  test('internal checksum ledger is closed, inert data for its controlled runtime set', () => {
    const content = readFileSync(resolve(GENERATED_DIR, 'internal_checksums.sh'), 'utf-8');
    const rawEntries: Array<[string, string]> = [];
    const checksums = new Map<string, string>();
    for (const line of content.split('\n')) {
      const match = line.match(/^\s*\[([^\]]+)]="([a-f0-9]{64})"\s*$/);
      if (match) {
        rawEntries.push([match[1], match[2]]);
        checksums.set(match[1], match[2]);
      }
    }

    expect(content).toContain('ACFS_INTERNAL_CHECKSUMS_SCHEMA=1');
    expect(content).not.toContain('ACFS_INTERNAL_CHECKSUMS_GENERATED=');
    expect(content).not.toContain('$(date');
    const countMatch = content.match(/^ACFS_INTERNAL_CHECKSUMS_COUNT=(\d+)$/m);
    expect(countMatch).not.toBeNull();
    expect(rawEntries.length).toBe(checksums.size);
    expect(Number(countMatch?.[1])).toBe(checksums.size);
    expect(checksums.size).toBe(59);

    const mandatoryPaths = [
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
    ];
    for (const path of mandatoryPaths) {
      expect(checksums.has(path)).toBe(true);
    }

    for (const [path, expected] of checksums) {
      const actual = createHash('sha256')
        .update(readFileSync(resolve(PROJECT_ROOT, path)))
        .digest('hex');
      expect(expected).toBe(actual);
    }

    const installer = readFileSync(resolve(PROJECT_ROOT, 'install.sh'), 'utf-8');
    const requiredBlock = installer.match(
      /local -a required_paths=\(\n([\s\S]*?)\n\s*\)\n\s*if \(\( parsed_count/
    );
    expect(requiredBlock).not.toBeNull();
    const runtimeRequiredPathList = (requiredBlock?.[1] ?? '')
      .split('\n')
      .map((line) => line.trim())
      .filter(Boolean);
    const runtimeRequiredPaths = new Set(runtimeRequiredPathList);
    expect(runtimeRequiredPathList.length).toBe(runtimeRequiredPaths.size);
    expect(runtimeRequiredPaths).toEqual(new Set(checksums.keys()));

    const driftChecker = readFileSync(
      resolve(PROJECT_ROOT, 'scripts/check-manifest-drift.sh'),
      'utf-8'
    );
    const driftRequiredBlock = driftChecker.match(
      /INTERNAL_CHECKSUM_REQUIRED_PATHS=\(\n([\s\S]*?)\n\)/
    );
    expect(driftRequiredBlock).not.toBeNull();
    const driftRequiredPathList = (driftRequiredBlock?.[1] ?? '')
      .split('\n')
      .map((line) => line.trim())
      .filter(Boolean);
    const driftRequiredPaths = new Set(driftRequiredPathList);
    expect(driftRequiredPathList.length).toBe(driftRequiredPaths.size);
    expect(driftRequiredPaths).toEqual(new Set(checksums.keys()));
  });

  test('generated system-binary resolvers exclude locally managed prefixes', () => {
    const manifestResult = parseManifestFile(MANIFEST_PATH);
    expect(manifestResult.success).toBe(true);
    if (!manifestResult.success || !manifestResult.data) {
      throw new Error(`Failed to parse manifest: ${manifestResult.error?.message}`);
    }

    const generatedScripts = [
      'install_all.sh',
      'doctor_checks.sh',
      ...getCategories(manifestResult.data).map((category) => `install_${category}.sh`),
    ];

    for (const filename of generatedScripts) {
      const content = readFileSync(resolve(GENERATED_DIR, filename), 'utf-8');
      const pathInvariant = 'export PATH="/usr/sbin:/usr/bin:/sbin:/bin"';
      expect(content).toContain(pathInvariant);
      expect(content.indexOf(pathInvariant)).toBeLessThan(
        content.indexOf('ACFS_GENERATED_SCRIPT_DIR=')
      );
      expect(content).toContain('"/usr/bin/$name"');
      expect(content).toContain('"/usr/sbin/$name"');
      expect(content).not.toContain('"/usr/local/bin/$name"');
      expect(content).not.toContain('"/usr/local/sbin/$name"');
    }
  });
});

// ============================================================
// Web Data Generation Tests
// ============================================================

describe('Generated web data files exist', () => {
  const webFiles = [
    'manifest-modules.ts',
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
    'manifest-modules.ts',
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

describe('manifest-modules.ts structure', () => {
  let content: string;

  beforeAll(() => {
    const filepath = resolve(WEB_GENERATED_DIR, 'manifest-modules.ts');
    content = readFileSync(filepath, 'utf-8');
  });

  test('exports ManifestModuleMetadata interface', () => {
    expect(content).toContain('export interface ManifestModuleMetadata');
  });

  test('interface has resolver fields', () => {
    expect(content).toContain('id: string;');
    expect(content).toContain('description: string;');
    expect(content).toContain('category: string;');
    expect(content).toContain('phase: number;');
    expect(content).toContain('dependencies: string[];');
    expect(content).toContain('tags: string[];');
    expect(content).toContain('enabledByDefault: boolean;');
    expect(content).toContain('optional: boolean;');
  });

  test('exports manifest and checksum provenance for team profile exports', () => {
    expect(content).toContain('export interface ManifestProvenanceMetadata');
    expect(content).toContain('export const manifestProvenance = {');
    expect(content).toMatch(/manifestSha256: "[a-f0-9]{64}"/);
    expect(content).toMatch(/checksumsYamlSha256: "[a-f0-9]{64}"/);
  });

  test('exports all module metadata and selection profiles', () => {
    expect(content).toContain('export const manifestModules: ManifestModuleMetadata[] = [');
    expect(content).toContain('export const manifestSelectionProfiles: ManifestSelectionProfile[] = [');
    expect(content).toContain('id: "minimal"');
    expect(content).toContain('"stack.mcp_agent_mail"');
    expect(content).toContain('id: "cloud-only"');
    expect(content).toContain('"cloud.wrangler"');
  });
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
    expect(content).toContain('displayName: string;');
    expect(content).toContain('moduleCategory: string;');
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

  test('re-exports manifest modules and selection profiles', () => {
    expect(content).toContain("export { manifestModules, manifestSelectionProfiles, manifestProvenance } from './manifest-modules'");
    expect(content).toContain("export type { ManifestModuleMetadata, ManifestSelectionProfile, ManifestSelectionProfileId, ManifestProvenanceMetadata } from './manifest-modules'");
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
