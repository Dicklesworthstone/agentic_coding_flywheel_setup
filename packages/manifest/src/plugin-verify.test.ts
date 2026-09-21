import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { extname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { loadReviewedPluginPackage, parsePluginVerifyArguments } from "./plugin-verify.js";
import type { Manifest } from "./types.js";

const target = { os: "ubuntu", version: "26.04", arch: "x86_64", libc: "glibc" };
const options = () => ({
  target,
  firstPartyManifest: {
    version: 1,
    name: "Plugin verification fixture",
    id: "acfs",
    defaults: { user: "ubuntu", workspace_root: "/data/projects", mode: "vibe" },
    modules: [
      {
        id: "base.system",
        description: "Base system",
        category: "base",
        phase: 1,
        run_as: "target_user",
        optional: false,
        enabled_by_default: true,
        generated: true,
        install: ["echo base"],
        verify: ["true"],
      },
    ],
  } as Manifest,
  installers: { example_tools: { url: "https://example.com/install.sh", sha256: "b".repeat(64) } },
});
function plugin() {
  return {
    schema: "acfs.plugin-package.v1",
    schemaVersion: 1,
    packageId: "example.tools",
    displayName: "Example Tools",
    version: "1.2.3",
    description: "Example plugin.",
    publisher: {
      name: "Example Maintainers",
      contactUrl: "https://example.com/security",
      sourceUrl: "https://github.com/example/tools",
    },
    license: "MIT",
    docsUrl: "https://example.com/docs",
    provenance: {
      generatedAt: "2026-05-08T00:00:00Z",
      sourceRef: "main",
      sourceCommit: "a".repeat(40),
      acfsManifestVersion: 1,
    },
    targets: [
      { os: target.os, versions: [target.version], arch: [target.arch], libc: [target.libc] },
    ],
    capabilities: {
      allowed: ["verified_installer", "doctor_check"],
      reviewRequired: ["root_run_as", "cross_plugin_dependency", "default_enabled_module"],
      disallowed: ["arbitrary_shell", "secret_values"],
    },
    modules: [
      {
        id: "plugin.example_tools.cli",
        description: "Example command-line tool.",
        category: "tools",
        phase: 6,
        run_as: "target_user",
        optional: false,
        enabled_by_default: false,
        dependencies: ["base.system"],
        install: {
          kind: "verified_installer",
          tool: "example_tools",
          url: "https://example.com/install.sh",
          runner: "bash",
          args: [],
          env: [],
        },
        verify: [{ kind: "command_exists", command: "example" }],
        docs_url: "https://example.com/docs",
      },
    ],
    offline: {
      bundlingPolicy: "metadata_only",
      liveAuthRequired: false,
      providerInteractionRequired: false,
    },
    extensions: {},
  };
}
function fixture(value = plugin()) {
  const directory = mkdtempSync(join(tmpdir(), "acfs-plugin-verify-"));
  const packageDir = join(directory, "acfs-plugin-package");
  mkdirSync(packageDir);
  writeFileSync(join(packageDir, "plugin.json"), JSON.stringify(value));
  writeFileSync(join(packageDir, "README.md"), "Example package");
  writeFileSync(join(packageDir, "LICENSE"), "MIT");
  const bytes = execFileSync("tar", [
    "--format=ustar",
    "-czf",
    "-",
    "-C",
    directory,
    "acfs-plugin-package",
  ]);
  const packageSha256 = createHash("sha256").update(bytes).digest("hex");
  const archive = join(directory, "package.tar.gz");
  const review = join(directory, "review.json");
  writeFileSync(archive, bytes);
  writeFileSync(
    review,
    JSON.stringify({
      schema: "acfs.plugin-review.v1",
      packageId: value.packageId,
      version: value.version,
      sourceCommit: value.provenance.sourceCommit,
      packageSha256,
      reviewer: "Test maintainer",
      reviewedAt: new Date(Date.now() - 60_000).toISOString(),
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
      target,
      approvedCapabilities: ["verified_installer", "doctor_check"],
    }),
  );
  return { archive, review, packageSha256 };
}

test("CLI arguments require explicit archive, review and target", () => {
  assert.deepEqual(
    parsePluginVerifyArguments([
      "--archive",
      "a.tar.gz",
      "--review",
      "r.json",
      "--target",
      "ubuntu/26.04/x86_64/glibc",
      "--json",
    ]),
    { archive: "a.tar.gz", review: "r.json", target, json: true },
  );
  for (const args of [
    [],
    ["--archive"],
    ["--archive", "--json"],
    ["--unknown", "SECRET"],
    ["--json", "--json"],
    ["--target", "ubuntu/26.04/x86_64/glibc", "--target", "another"],
  ]) {
    assert.throws(() => parsePluginVerifyArguments(args));
  }
});

test("CLI help and invalid-input JSON are runnable without loading package validators", () => {
  const extension = extname(fileURLToPath(import.meta.url));
  const script = fileURLToPath(new URL(`./plugin-verify${extension}`, import.meta.url));
  const help = spawnSync(process.execPath, [script, "--help"], { encoding: "utf8" });
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, /Never installs/);
  const failure = spawnSync(process.execPath, [script, "--archive", "PRIVATE_PATH", "--json"], {
    encoding: "utf8",
  });
  assert.equal(failure.status, 2, failure.stderr);
  const output = JSON.parse(failure.stdout);
  assert.equal(output.valid, false);
  assert.equal(output.activation, "disabled");
  assert.ok(!failure.stdout.includes("PRIVATE_PATH"));
});

test("canonical integration validates reviewed package and binds normalized provenance", async () => {
  const item = fixture();
  const config = options();
  const before = JSON.stringify(config.firstPartyManifest);
  const result = await loadReviewedPluginPackage(item.archive, item.review, config);
  assert.equal(result.valid, true, JSON.stringify(result.diagnostics));
  assert.equal(result.manifestModules.length, 1);
  assert.equal(result.manifestModules[0]!.plugin?.pluginSha256, item.packageSha256);
  assert.equal(JSON.stringify(config.firstPartyManifest), before);
});

test("canonical integration requires the first-party installer checksum and exact URL", async () => {
  const item = fixture();
  for (const installers of [
    {},
    { example_tools: { url: "https://example.com/other.sh", sha256: "b".repeat(64) } },
  ]) {
    const result = await loadReviewedPluginPackage(item.archive, item.review, {
      ...options(),
      installers,
    });
    assert.equal(result.valid, false);
    assert.equal(result.manifestModules.length, 0);
    assert.ok(
      result.diagnostics.some(
        (entry) => entry.code === "plugin_verified_installer_checksum_required",
      ),
    );
  }
});

test("canonical integration never grants root authority or default enablement from a review", async () => {
  for (const update of [{ run_as: "root" }, { run_as: "current" }, { enabled_by_default: true }]) {
    const data = plugin();
    Object.assign(data.modules[0]!, update);
    const item = fixture(data);
    const result = await loadReviewedPluginPackage(item.archive, item.review, options());
    assert.equal(result.valid, false);
    assert.equal(result.manifestModules.length, 0);
    assert.ok(result.diagnostics.some((entry) => entry.code === "plugin_review_required"));
  }
});

test("canonical integration rejects merged graph cycles and unsafe verification commands", async () => {
  for (const change of ["cycle", "command"]) {
    const data = plugin();
    if (change === "cycle") data.modules[0]!.dependencies = [data.modules[0]!.id];
    else data.modules[0]!.verify[0]!.command = "example;id";
    const item = fixture(data);
    const result = await loadReviewedPluginPackage(item.archive, item.review, options());
    assert.equal(result.valid, false);
    assert.equal(result.manifestModules.length, 0);
  }
});
