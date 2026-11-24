import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { generateCategoryScript } from "./generate.js";
import { parseManifestFile } from "./parser.js";

const PROJECT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const currentUser = spawnSync("/usr/bin/id", ["-un"], { encoding: "utf8" });
if (currentUser.status !== 0 || !currentUser.stdout.trim()) throw new Error("Unable to resolve test account");
const parsed = parseManifestFile(resolve(PROJECT_ROOT, "acfs.manifest.yaml"));
if (!parsed.success || !parsed.data) throw new Error("Unable to parse the ACFS manifest");
const generated = generateCategoryScript(parsed.data, "agents");
const generatedStart = generated.indexOf("acfs_generated_install_agents_codex() {");
const generatedEnd = generated.indexOf("\nacfs_generated_install_", generatedStart + 1);
if (generatedStart < 0 || generatedEnd < 0) throw new Error("Generated Codex function missing");
const generatedCodex = generated.slice(generatedStart, generatedEnd);
const installer = readFileSync(resolve(PROJECT_ROOT, "install.sh"), "utf8");
const legacyStart = installer.indexOf("install_agents_phase() {");
const legacyEnd = installer.indexOf("\ninstall_agents_legacy_optional() {", legacyStart);
if (legacyStart < 0 || legacyEnd < 0) throw new Error("Legacy agents phase missing");
const legacyAgents = installer.slice(legacyStart, legacyEnd);

type Route = "generated" | "legacy";
type Configuration = "default" | "environment" | "bunfig";

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function fixture(configuration: Configuration) {
  const root = mkdtempSync(resolve(tmpdir(), "acfs-codex-install-"));
  // Exercise literal shell metacharacters as well as spaces in every path.
  const home = resolve(root, "target 'home $literal");
  const globalBin = configuration === "default"
    ? resolve(home, ".bun/bin")
    : resolve(home, "configured 'global $bin");
  const primaryBin = resolve(home, "configured 'primary $bin");
  mkdirSync(resolve(home, ".bun/bin"), { recursive: true });
  mkdirSync(resolve(home, ".bun/install/global"), { recursive: true });
  mkdirSync(globalBin, { recursive: true });
  mkdirSync(primaryBin, { recursive: true });
  writeFileSync(resolve(home, ".bun/install/global/package.json"), "{}\n");
  if (configuration === "bunfig") {
    writeFileSync(resolve(home, ".bunfig.toml"),
      `[install]\nglobalBinDir = ${JSON.stringify(globalBin)}\n`);
  }
  const packagePath = resolve(globalBin, "codex");
  const packageSource = [
    "#!/usr/bin/env node",
    'const args = process.argv.slice(2);',
    'if (args[0] === "--version" || args[0] === "--help") console.log("codex-cli 9.9.9-fixture");',
    'else console.log(JSON.stringify(args));',
    "",
  ].join("\n");
  writeFileSync(packagePath, packageSource, { mode: 0o755 });
  // Only package retrieval is offline. Bun itself resolves .bunfig.toml /
  // BUN_INSTALL_BIN and executes the actual JS launcher without Node on PATH.
  writeFileSync(resolve(home, ".bun/bin/bun"), [
    "#!/bin/bash",
    "set -euo pipefail",
    'if [[ "${1:-}" == install ]]; then',
    '  printf "%s\\n" "$*" >> "$HOME/install-invocations.log"',
    "  exit 0",
    "fi",
    'if [[ "${1:-}" == pm ]]; then',
    '  if [[ -f "$HOME/query-exit" ]]; then exit "$(< "$HOME/query-exit")"; fi',
    '  if [[ -f "$HOME/query-output" ]]; then cat "$HOME/query-output"; exit 0; fi',
    "fi",
    `exec ${shellQuote(process.execPath)} "$@"`,
    "",
  ].join("\n"), { mode: 0o755 });
  const env: Record<string, string> = {
    PATH: "/usr/bin:/bin",
    HOME: home,
    TARGET_HOME: home,
    TARGET_USER: currentUser.stdout.trim(),
    ACFS_BIN_DIR: primaryBin,
    BUN_INSTALL: resolve(home, ".bun"),
    ...(configuration === "environment" ? { BUN_INSTALL_BIN: globalBin } : {}),
  };
  return { root, home, globalBin, primaryBin, packagePath, packageSource, env };
}

type Fixture = ReturnType<typeof fixture>;

function runInstall(route: Route, context: Fixture) {
  const script = [
    `source ${shellQuote(resolve(PROJECT_ROOT, "scripts/lib/install_helpers.sh"))}`,
    '_acfs_getent_passwd_entry() { printf "%s:x:%s:%s::%s:/bin/bash\\n" "$TARGET_USER" "$(id -u)" "$(id -g)" "$TARGET_HOME"; }',
    'acfs_early_system_binary_path() { _acfs_system_binary_path "$@"; }',
    'set_phase() { :; }',
    'log_step() { :; }; log_detail() { :; }; log_success() { :; }',
    'acfs_require_contract() { :; }; acfs_generated_ensure_selection() { :; }',
    'should_run_module() { [[ "$1" == agents.codex ]]; }',
    'acfs_legacy_module_selected() { should_run_module "$@"; }',
    'acfs_use_generated_category() { return 1; }',
    'acfs_should_skip_module() { return 1; }',
    'acfs_verify_module() { [[ "$1" == agents.codex ]] && run_as_target "$ACFS_BIN_DIR/codex" --version; }',
    'acfs_note_bun_global_bin_mismatch() { :; }',
    'try_step() { shift; "$@"; }',
    'install_agents_legacy_optional() { :; }',
    'ACFS_MODULE_FAILURES=()',
    route === "generated" ? generatedCodex : legacyAgents,
    route === "generated" ? "acfs_generated_install_agents_codex" : "install_agents_phase",
  ].join("\n");
  writeFileSync(resolve(context.root, `${route}.sh`), script);
  const result = spawnSync("/bin/bash", ["-euo", "pipefail", "-c", script], {
    encoding: "utf8", env: context.env, cwd: context.home, timeout: 15_000,
  });
  writeFileSync(resolve(context.root, `${route}.log`), `${result.stdout ?? ""}${result.stderr ?? ""}`);
  return result;
}

function launcher(context: Fixture, args = ["--version"]) {
  return spawnSync(resolve(context.env.ACFS_BIN_DIR, "codex"), args, {
    encoding: "utf8", env: context.env, cwd: context.home, timeout: 5_000,
  });
}

for (const route of ["generated", "legacy"] as const) {
  describe(`${route} fresh Codex installation`, () => {
    for (const configuration of ["default", "environment", "bunfig"] as const) {
      test(`runs the package from Bun's ${configuration} global bin`, () => {
        const context = fixture(configuration);
        const result = runInstall(route, context);
        expect({ status: result.status, stderr: result.stderr }).toEqual({ status: 0, stderr: "" });
        expect(launcher(context).stdout.trim()).toBe("codex-cli 9.9.9-fixture");
        const args = ["exec", "argument with spaces", "$literal", "single'quote"];
        expect(launcher(context, args).stdout.trim()).toBe(JSON.stringify(args));
        expect(readFileSync(resolve(context.home, "install-invocations.log"), "utf8"))
          .toContain("install -g --trust @openai/codex@latest");
      });
    }

    test("replaces a stale nonworking launcher during an installation retry", () => {
      const context = fixture("bunfig");
      writeFileSync(resolve(context.primaryBin, "codex"), "#!/bin/bash\nexit 23\n", { mode: 0o755 });
      expect(runInstall(route, context).status).toBe(0);
      expect(launcher(context).stdout.trim()).toBe("codex-cli 9.9.9-fixture");
    });

    for (const failure of ["query", "relative", "multiline", "root", "missing", "broken"] as const) {
      test(`preserves the previous launcher when Bun reports a ${failure} package location`, () => {
        const context = fixture("bunfig");
        const oldLauncher = "#!/bin/bash\nexit 23\n";
        writeFileSync(resolve(context.primaryBin, "codex"), oldLauncher, { mode: 0o755 });
        if (failure === "query") writeFileSync(resolve(context.home, "query-exit"), "42\n");
        if (failure === "relative") writeFileSync(resolve(context.home, "query-output"), "relative/path\n");
        if (failure === "multiline") writeFileSync(resolve(context.home, "query-output"), `${context.globalBin}\n/other\n`);
        if (failure === "root") writeFileSync(resolve(context.home, "query-output"), "/\n");
        if (failure === "missing") {
          const emptyBin = resolve(context.home, "empty global bin");
          mkdirSync(emptyBin);
          writeFileSync(resolve(context.home, "query-output"), `${emptyBin}\n`);
        }
        if (failure === "broken") writeFileSync(context.packagePath, "process.exit(37);\n");
        const result = runInstall(route, context);
        expect(result.status).not.toBe(0);
        expect(readFileSync(resolve(context.primaryBin, "codex"), "utf8")).toBe(oldLauncher);
      });
    }

    for (const alias of [false, true]) {
      test(`preserves the package when the primary bin ${alias ? "aliases" : "equals"} the global bin`, () => {
        const context = fixture("bunfig");
        if (alias) {
          const aliasBin = resolve(context.home, "global bin alias");
          symlinkSync(context.globalBin, aliasBin);
          context.env.ACFS_BIN_DIR = aliasBin;
        } else context.env.ACFS_BIN_DIR = context.globalBin;
        const result = runInstall(route, context);
        expect(result.status).not.toBe(0);
        expect(readFileSync(context.packagePath, "utf8")).toBe(context.packageSource);
      });
    }
  });
}
