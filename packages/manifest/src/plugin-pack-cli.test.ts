import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { extname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { readVerifiedPluginArchive } from "./plugin-archive.js";
import { buildPluginArchive } from "./plugin-pack.js";
import {
  type PluginPackCommandServices,
  type PluginPackValidation,
  parsePluginPackArguments,
  pluginPackMain,
  validatePluginArchiveForPublication,
} from "./plugin-pack-cli.js";
import {
  PluginReviewError,
  parsePluginTarget,
  readReviewedPluginArchive,
} from "./plugin-review.js";

const targetText = "ubuntu/26.04/x86_64/glibc";
const target = parsePluginTarget(targetText);
const digest = (bytes: Buffer): string => createHash("sha256").update(bytes).digest("hex");
function fixture() {
  const directory = mkdtempSync(join(tmpdir(), "acfs-pack-command-"));
  const source = join(directory, "source");
  mkdirSync(source);
  const manifest = {
    schema: "acfs.plugin-package.v1",
    schemaVersion: 1,
    packageId: "example.tools",
    displayName: "Example Tools",
    version: "1.2.3",
    description: "Pack command fixture.",
    publisher: {
      name: "Example Maintainers",
      contactUrl: "https://example.com/security",
      sourceUrl: "https://example.com/source",
    },
    license: "MIT",
    docsUrl: "https://example.com/docs",
    provenance: {
      generatedAt: "2026-05-08T00:00:00Z",
      sourceRef: "main",
      sourceCommit: "a".repeat(40),
      acfsManifestVersion: 1,
    },
    targets: [{ os: "ubuntu", versions: ["26.04"], arch: ["x86_64"], libc: ["glibc"] }],
    capabilities: {
      allowed: ["verified_installer", "doctor_check"],
      reviewRequired: [],
      disallowed: ["arbitrary_shell", "secret_values"],
    },
    modules: [
      {
        id: "plugin.example_tools.cli",
        description: "Reviewed CLI fixture.",
        category: "tools",
        phase: 6,
        run_as: "target_user",
        optional: false,
        enabled_by_default: false,
        dependencies: [] as string[],
        install: {
          kind: "verified_installer",
          tool: "bun",
          url: "https://bun.sh/install",
          runner: "bash",
          args: [],
          env: [],
        },
        verify: [{ kind: "command_exists", command: "bun" }],
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
  writeFileSync(join(source, "plugin.json"), JSON.stringify(manifest));
  writeFileSync(join(source, "README.md"), "Package documentation.");
  writeFileSync(join(source, "LICENSE"), "MIT");
  const output = join(directory, "package.tar.gz");
  const messages: string[] = [];
  let calls = 0;
  const services: PluginPackCommandServices = {
    validate: async (build, checkedTarget) => {
      calls++;
      assert.deepEqual(build.manifest, manifest);
      assert.deepEqual(checkedTarget, target);
      assert.equal(existsSync(output), false);
      return { valid: true, moduleCount: 1, diagnosticCodes: [] };
    },
    write: (message) => messages.push(message),
  };
  const args = ["--source", source, "--target", targetText, "--output", output, "--json"];
  return { directory, source, manifest, output, messages, services, args, calls: () => calls };
}

test("command builds, validates, and publishes actual archives but never reviews or installers", async () => {
  const item = fixture();
  assert.equal(await pluginPackMain(item.args, item.services), 0);
  assert.equal(item.calls(), 1);
  const output = JSON.parse(item.messages[0]!);
  assert.equal(output.status, "packed");
  assert.equal(output.reviewRequired, true);
  assert.equal(output.archive.reviewRequired, true);
  assert.equal(output.moduleCount, 1);
  assert.equal(output.archive.packageSha256, digest(readFileSync(item.output)));
  assert.deepEqual(
    readVerifiedPluginArchive(item.output, output.archive.packageSha256).manifest,
    item.manifest,
  );
  assert.deepEqual(readdirSync(item.directory).sort(), ["package.tar.gz", "source"]);
});

test("dry run checks actual source/archive without creating output, directories, or review files", async () => {
  const item = fixture();
  const args = ["--source", item.source, "--target", targetText, "--dry-run", "--json"];
  assert.equal(await pluginPackMain(args, item.services), 0);
  assert.equal(item.calls(), 1);
  const output = JSON.parse(item.messages[0]!);
  assert.equal(output.status, "validated");
  assert.equal(output.dryRun, true);
  assert.equal(output.reviewRequired, true);
  assert.equal(output.archive.packageSha256, buildPluginArchive(item.source).packageSha256);
  assert.deepEqual(readdirSync(item.directory), ["source"]);
  assert.equal(await pluginPackMain([...item.args, "--dry-run"], item.services), 0);
  assert.equal(existsSync(item.output), false);
});

test("validation refuses publication before any output even for a structurally valid tar", async () => {
  const item = fixture();
  item.services.validate = async () => ({
    valid: false,
    moduleCount: 0,
    diagnosticCodes: ["plugin_verified_installer_checksum_required"],
  });
  assert.equal(await pluginPackMain(item.args, item.services), 1);
  assert.equal(existsSync(item.output), false);
  assert.deepEqual(JSON.parse(item.messages[0]!).diagnostic.causes, [
    "plugin_verified_installer_checksum_required",
  ]);
});

for (const result of [
  { valid: true, moduleCount: 0, diagnosticCodes: [] },
  { valid: true, moduleCount: -1, diagnosticCodes: [] },
  { valid: true, moduleCount: NaN, diagnosticCodes: [] },
  { valid: true, moduleCount: 1, diagnosticCodes: ["plugin_review_required"] },
  { valid: "yes", moduleCount: 1, diagnosticCodes: [] },
  { valid: true, moduleCount: 1, diagnosticCodes: null },
]) {
  test("rejects inconsistent validation results instead of publishing an empty or unvalidated package", async () => {
    const item = fixture();
    item.services.validate = async () => result as PluginPackValidation;
    assert.equal(await pluginPackMain(item.args, item.services), 1);
    assert.equal(existsSync(item.output), false);
  });
}

test("failed validator errors and diagnostic payloads do not disclose local paths or credentials", async () => {
  for (const thrown of [true, false]) {
    const item = fixture();
    item.services.validate = async () => {
      if (thrown) throw new Error("/private/SECRET_TOKEN raw loader error");
      return {
        valid: false,
        moduleCount: 0,
        diagnosticCodes: ["/private/SECRET_TOKEN", "plugin_review_required"],
      };
    };
    assert.equal(await pluginPackMain(item.args, item.services), 1);
    assert.ok(!item.messages.join("").includes("SECRET_TOKEN"));
    assert.ok(!item.messages.join("").includes("/private"));
    assert.ok(!item.messages.join("").includes(item.source));
    assert.equal(existsSync(item.output), false);
  }
});

test("unsafe or malformed source never reaches semantic validation or publication", async () => {
  const item = fixture();
  writeFileSync(join(item.source, ".env"), "PRIVATE");
  assert.equal(await pluginPackMain(item.args, item.services), 1);
  assert.equal(item.calls(), 0);
  assert.equal(existsSync(item.output), false);
  assert.ok(!item.messages.join("").includes("PRIVATE"));
});

test("source changes during validation cannot replace the archived bytes that passed validation", async () => {
  const item = fixture();
  const expected = buildPluginArchive(item.source).packageSha256;
  item.services.validate = async () => {
    writeFileSync(join(item.source, "README.md"), "modified during validation");
    return { valid: true, moduleCount: 1, diagnosticCodes: [] };
  };
  assert.equal(await pluginPackMain(item.args, item.services), 0);
  assert.equal(digest(readFileSync(item.output)), expected);
});

test("existing output is retained and never treated as successful publication", async () => {
  const item = fixture();
  writeFileSync(item.output, "do not replace");
  item.services.validate = async () => ({ valid: true, moduleCount: 1, diagnosticCodes: [] });
  assert.equal(await pluginPackMain(item.args, item.services), 1);
  assert.equal(readFileSync(item.output, "utf8"), "do not replace");
  assert.equal(JSON.parse(item.messages[0]!).status, "failed");
});

for (const args of [
  [],
  ["--source", "x"],
  ["--source", "x", "--target", targetText],
  ["--source", "x", "--target", "ubuntu/26.04/x86_64", "--dry-run"],
  ["--source", "x", "--target", targetText, "--dry-run", "--force"],
  ["--source", "x", "--target", targetText, "--dry-run", "--review", "SELF_APPROVAL"],
  ["--source", "x", "--source", "y", "--target", targetText, "--dry-run"],
  ["--source", "x", "--target", targetText, "--dry-run", "--json", "--json"],
]) {
  test(`requires explicit valid inputs with no bypass or self-review option ${JSON.stringify(args)}`, () => {
    assert.throws(() => parsePluginPackArguments(args));
  });
}

test("cancellation during async validation prevents publication and restores signal handlers", async () => {
  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    const item = fixture();
    const before = process.listenerCount(signal);
    item.services.validate = async () => {
      process.emit(signal);
      return { valid: true, moduleCount: 1, diagnosticCodes: [] };
    };
    assert.equal(await pluginPackMain(item.args, item.services), signal === "SIGINT" ? 130 : 143);
    assert.equal(existsSync(item.output), false);
    assert.equal(process.listenerCount(signal), before);
    assert.equal(JSON.parse(item.messages[0]!).diagnostic.code, "plugin_pack_cancelled");
  }
});

test("public command help and invalid arguments run without importing canonical dependencies", () => {
  const extension = extname(fileURLToPath(import.meta.url));
  const script = fileURLToPath(new URL(`./plugin-pack-cli${extension}`, import.meta.url));
  const help = spawnSync(process.execPath, [script, "--help"], { encoding: "utf8" });
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, /Never executes installers/);
  const bad = spawnSync(process.execPath, [script, "--source", "/PRIVATE", "--json"], {
    encoding: "utf8",
  });
  assert.equal(bad.status, 2, bad.stderr);
  assert.equal(JSON.parse(bad.stdout).status, "failed");
  assert.ok(!bad.stdout.includes("PRIVATE"));
});

test("published packages require a separately selected review with exact hash, target and identity", async () => {
  const item = fixture();
  assert.equal(await pluginPackMain(item.args, item.services), 0);
  assert.throws(
    () => readReviewedPluginArchive(item.output, join(item.directory, "missing.json"), target),
    PluginReviewError,
  );
  const now = Date.now();
  const review = {
    schema: "acfs.plugin-review.v1",
    packageId: item.manifest.packageId,
    version: item.manifest.version,
    sourceCommit: item.manifest.provenance.sourceCommit,
    packageSha256: digest(readFileSync(item.output)),
    reviewer: "Independently selected test maintainer",
    reviewedAt: new Date(now - 1000).toISOString(),
    expiresAt: new Date(now + 60_000).toISOString(),
    target,
    approvedCapabilities: ["verified_installer", "doctor_check"],
  };
  const path = join(item.directory, "external-review.json");
  writeFileSync(path, JSON.stringify(review));
  assert.deepEqual(
    readReviewedPluginArchive(item.output, path, target, now).manifest,
    item.manifest,
  );
  for (const mutation of [
    { packageSha256: "f".repeat(64) },
    { packageId: "different.package" },
    { expiresAt: new Date(now).toISOString() },
    { target: { ...target, arch: "aarch64" } },
  ]) {
    writeFileSync(path, JSON.stringify({ ...review, ...mutation }));
    assert.throws(() => readReviewedPluginArchive(item.output, path, target, now));
  }
});

test("canonical publication validation uses actual manifest/checksum/schema integration", async () => {
  const item = fixture();
  const build = buildPluginArchive(item.source);
  const checked = await validatePluginArchiveForPublication(build, target);
  assert.equal(checked.valid, true, JSON.stringify(checked));
  assert.equal(checked.moduleCount, 1);
  for (const change of ["root", "checksum", "dependency", "target"]) {
    const bad = structuredClone(item.manifest);
    if (change === "root") bad.modules[0]!.run_as = "root";
    if (change === "checksum") bad.modules[0]!.install.url = "https://example.com/not-canonical.sh";
    if (change === "dependency") bad.modules[0]!.dependencies = ["plugin.example_tools.missing"];
    if (change === "target") bad.targets[0]!.arch = ["aarch64"];
    writeFileSync(join(item.source, "plugin.json"), JSON.stringify(bad));
    assert.equal(
      (await validatePluginArchiveForPublication(buildPluginArchive(item.source), target)).valid,
      false,
      change,
    );
    assert.equal(existsSync(item.output), false);
  }
});
